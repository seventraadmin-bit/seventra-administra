import 'dart:convert';

import 'package:drift/drift.dart';

import 'package:riseg_one/core/database/app_database.dart';

import '../../domain/repositories/auditoria_repository.dart';
import '../../domain/usecases/buscar_auditoria_usecase.dart';

/// Agrega los ~17 orígenes reales de eventos del proyecto en una sola
/// lista ordenada (Etapa 11D). Cada tabla ya vive en un dominio propio
/// — esta clase solo las lee directamente vía `AppDatabase` (mismo
/// criterio que cualquier otro repositorio: consulta lo que necesita,
/// sin inyectar 17 repositorios de dominio distintos solo para volver
/// a leer sus propias tablas). El filtro de fecha se aplica en SQL por
/// tabla (más barato); usuario/módulo/acción se aplican en memoria tras
/// combinar — el volumen de eventos de una instalación de escritorio de
/// un solo usuario no justifica una consulta `UNION` cruzada más
/// compleja.
class AuditoriaRepositoryImpl implements AuditoriaRepository {
  AuditoriaRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<List<EventoAuditoria>> buscar(FiltroAuditoria filtro) async {
    final eventos = <EventoAuditoria>[];

    Expression<bool> enRango(Expression<DateTime> columna) {
      Expression<bool> condicion = const Constant(true);
      if (filtro.desde != null) condicion = condicion & columna.isBiggerOrEqualValue(filtro.desde!);
      if (filtro.hasta != null) condicion = condicion & columna.isSmallerOrEqualValue(filtro.hasta!);
      return condicion;
    }

    // --- Tablas "Evento" propiamente dichas (fechaHora/tipoEvento/observacion/datosRelevantes) ---

    final compraEventos = await (_db.select(_db.compraEvento)..where((t) => enRango(t.fechaHora))).get();
    final etiquetaCompra = await _etiquetasPorId(
      ids: compraEventos.map((e) => e.compraId),
      cargar: (ids) async {
        final filas = await (_db.select(_db.compra)..where((t) => t.id.isIn(ids))).get();
        return {
          for (final f in filas)
            f.id: f.folioCompra,
        };
      },
    );
    eventos.addAll(compraEventos.map((e) => EventoAuditoria(
          fechaHora: e.fechaHora,
          actorUsuarioId: e.actorUsuarioId,
          modulo: 'compras',
          accion: e.tipoEvento,
          registroId: e.compraId,
          entidadEtiqueta: etiquetaCompra[e.compraId],
          motivo: e.observacion,
          detalleJson: e.datosRelevantes,
        )));

    final complementoEventos = await (_db.select(_db.complementoPagoEvento)..where((t) => enRango(t.fechaHora))).get();
    final etiquetaComplemento = await _etiquetasPorId(
      ids: complementoEventos.map((e) => e.complementoPagoId),
      cargar: (ids) async {
        final filas = await (_db.select(_db.complementoPago)..where((t) => t.id.isIn(ids))).get();
        return {
          for (final f in filas)
            if (f.folioFiscal != null) f.id: f.folioFiscal!,
        };
      },
    );
    eventos.addAll(complementoEventos.map((e) => EventoAuditoria(
          fechaHora: e.fechaHora,
          actorUsuarioId: e.actorUsuarioId,
          modulo: 'finanzas',
          accion: e.tipoEvento,
          registroId: e.complementoPagoId,
          entidadEtiqueta: etiquetaComplemento[e.complementoPagoId],
          motivo: e.observacion,
          detalleJson: e.datosRelevantes,
        )));

    final cuentaPorCobrarEventos = await (_db.select(_db.cuentaPorCobrarEvento)..where((t) => enRango(t.fechaHora))).get();
    // La Cuenta por cobrar no tiene folio propio: su identificador humano es
    // el folio del comprobante que la originó, y en un recibo puede no
    // existir. Cuando falta, la fila conserva el id técnico — nunca se
    // fabrica una etiqueta.
    final etiquetaCuentaPorCobrar = await _etiquetasPorId(
      ids: cuentaPorCobrarEventos.map((e) => e.cuentaPorCobrarId),
      cargar: (ids) async {
        final filas = await (_db.select(_db.cuentaPorCobrar)..where((t) => t.id.isIn(ids))).get();
        return {
          for (final f in filas)
            if (f.folioDocumento != null) f.id: f.folioDocumento!,
        };
      },
    );
    eventos.addAll(cuentaPorCobrarEventos.map((e) => EventoAuditoria(
          fechaHora: e.fechaHora,
          actorUsuarioId: e.actorUsuarioId,
          modulo: 'finanzas',
          accion: e.tipoEvento,
          registroId: e.cuentaPorCobrarId,
          entidadEtiqueta: etiquetaCuentaPorCobrar[e.cuentaPorCobrarId],
          motivo: e.observacion,
          detalleJson: e.datosRelevantes,
        )));

    final egresoEventos = await (_db.select(_db.egresoEvento)..where((t) => enRango(t.fechaHora))).get();
    final etiquetaEgreso = await _etiquetasPorId(
      ids: egresoEventos.map((e) => e.egresoId),
      cargar: (ids) async {
        final filas = await (_db.select(_db.egreso)..where((t) => t.id.isIn(ids))).get();
        return {
          for (final f in filas)
            f.id: f.folioEgreso,
        };
      },
    );
    eventos.addAll(egresoEventos.map((e) => EventoAuditoria(
          fechaHora: e.fechaHora,
          actorUsuarioId: e.actorUsuarioId,
          modulo: 'finanzas',
          accion: e.tipoEvento,
          registroId: e.egresoId,
          entidadEtiqueta: etiquetaEgreso[e.egresoId],
          motivo: e.observacion,
          detalleJson: e.datosRelevantes,
        )));

    final ingresoEventos = await (_db.select(_db.ingresoEvento)..where((t) => enRango(t.fechaHora))).get();
    final etiquetaIngreso = await _etiquetasPorId(
      ids: ingresoEventos.map((e) => e.ingresoId),
      cargar: (ids) async {
        final filas = await (_db.select(_db.ingreso)..where((t) => t.id.isIn(ids))).get();
        return {
          for (final f in filas)
            f.id: f.folioIngreso,
        };
      },
    );
    eventos.addAll(ingresoEventos.map((e) => EventoAuditoria(
          fechaHora: e.fechaHora,
          actorUsuarioId: e.actorUsuarioId,
          modulo: 'finanzas',
          accion: e.tipoEvento,
          registroId: e.ingresoId,
          entidadEtiqueta: etiquetaIngreso[e.ingresoId],
          motivo: e.observacion,
          detalleJson: e.datosRelevantes,
        )));

    final pagoEventos = await (_db.select(_db.pagoEvento)..where((t) => enRango(t.fechaHora))).get();
    final etiquetaPago = await _etiquetasPorId(
      ids: pagoEventos.map((e) => e.pagoId),
      cargar: (ids) async {
        final filas = await (_db.select(_db.pago)..where((t) => t.id.isIn(ids))).get();
        return {
          for (final f in filas)
            f.id: f.folioPago,
        };
      },
    );
    eventos.addAll(pagoEventos.map((e) => EventoAuditoria(
          fechaHora: e.fechaHora,
          actorUsuarioId: e.actorUsuarioId,
          modulo: 'finanzas',
          accion: e.tipoEvento,
          registroId: e.pagoId,
          entidadEtiqueta: etiquetaPago[e.pagoId],
          motivo: e.observacion,
          detalleJson: e.datosRelevantes,
        )));

    final nominaEventos = await (_db.select(_db.nominaEvento)..where((t) => enRango(t.fechaHora))).get();
    final etiquetaNomina = await _etiquetasPorId(
      ids: nominaEventos.map((e) => e.nominaId),
      cargar: (ids) async {
        final filas = await (_db.select(_db.nomina)..where((t) => t.id.isIn(ids))).get();
        return {
          for (final f in filas)
            f.id: f.folio,
        };
      },
    );
    eventos.addAll(nominaEventos.map((e) => EventoAuditoria(
          fechaHora: e.fechaHora,
          actorUsuarioId: e.actorUsuarioId,
          modulo: 'nomina',
          accion: e.tipoEvento,
          registroId: e.nominaEmpleadoId ?? e.nominaId,
          entidadEtiqueta: etiquetaNomina[e.nominaId],
          motivo: e.observacion,
          detalleJson: e.datosRelevantes,
        )));

    final pagoNominaEventos = await (_db.select(_db.pagoNominaEvento)..where((t) => enRango(t.fechaHora))).get();
    eventos.addAll(pagoNominaEventos.map((e) => EventoAuditoria(
          fechaHora: e.fechaHora,
          actorUsuarioId: e.actorUsuarioId,
          modulo: 'nomina',
          accion: e.tipoEvento,
          registroId: e.pagoNominaId,
          motivo: e.observacion,
          detalleJson: e.datosRelevantes,
        )));

    // --- Comercial: Cliente (con Entidad fiscal y Contacto), Servicio
    //     (con su configuración comercial) y Configuración de cobro ---
    //
    // Las etiquetas se resuelven SIEMPRE en lote (`_etiquetasPorId`):
    // una consulta por tabla, nunca una por fila. Y son etiquetas de
    // CONTEXTO —el nombre vivo del registro, para saber a qué se
    // refiere la fila—: el diff conserva intacto el valor anterior y
    // el nuevo que se capturaron cuando ocurrió el cambio.
    final clienteEventos = await (_db.select(_db.clienteEvento)..where((t) => enRango(t.fechaHora))).get();
    final etiquetaCliente = await _etiquetasPorId(
      ids: clienteEventos.map((e) => e.clienteId),
      cargar: (ids) async {
        final filas = await (_db.select(_db.cliente)..where((t) => t.id.isIn(ids))).get();
        return {for (final c in filas) c.id: c.nombreComercial};
      },
    );
    eventos.addAll(clienteEventos.map((e) => EventoAuditoria(
          fechaHora: e.fechaHora,
          actorUsuarioId: e.actorUsuarioId,
          modulo: 'clientes',
          accion: e.tipoEvento,
          registroId: e.clienteId,
          motivo: e.observacion,
          detalleJson: e.datosRelevantes,
          cambios: _cambiosDeJson(e.estadoAnterior, e.estadoNuevo),
          entidadEtiqueta: etiquetaCliente[e.clienteId],
        )));

    final servicioEventos = await (_db.select(_db.servicioEvento)..where((t) => enRango(t.fechaHora))).get();
    final etiquetaServicio = await _etiquetasPorId(
      ids: servicioEventos.map((e) => e.servicioId),
      cargar: (ids) async {
        final filas = await (_db.select(_db.servicio)..where((t) => t.id.isIn(ids))).get();
        return {for (final s in filas) s.id: s.nombre};
      },
    );
    eventos.addAll(servicioEventos.map((e) => EventoAuditoria(
          fechaHora: e.fechaHora,
          actorUsuarioId: e.actorUsuarioId,
          modulo: 'servicios',
          accion: e.tipoEvento,
          registroId: e.servicioId,
          motivo: e.observacion,
          detalleJson: e.datosRelevantes,
          cambios: _cambiosDeJson(e.estadoAnterior, e.estadoNuevo),
          entidadEtiqueta: etiquetaServicio[e.servicioId],
        )));

    final cobroEventos =
        await (_db.select(_db.configuracionCobroEvento)..where((t) => enRango(t.fechaHora))).get();
    // La Configuración de cobro no tiene nombre propio: su contexto
    // real es el Servicio al que pertenece, y ahí es a donde navega.
    final servicioDeConfiguracion = await _etiquetasPorId(
      ids: cobroEventos.map((e) => e.configuracionCobroId),
      cargar: (ids) async {
        final filas = await (_db.select(_db.configuracionCobro)..where((t) => t.id.isIn(ids))).get();
        return {for (final c in filas) c.id: c.servicioId};
      },
    );
    eventos.addAll(cobroEventos.map((e) => EventoAuditoria(
          fechaHora: e.fechaHora,
          actorUsuarioId: e.actorUsuarioId,
          modulo: 'configuracionCobro',
          accion: e.tipoEvento,
          registroId: e.configuracionCobroId,
          motivo: e.observacion,
          detalleJson: e.datosRelevantes,
          cambios: _cambiosDeJson(e.estadoAnterior, e.estadoNuevo),
          destinoId: servicioDeConfiguracion[e.configuracionCobroId],
        )));

    final documentoPorEmitirEventos =
        await (_db.select(_db.documentoPorEmitirEvento)..where((t) => enRango(t.fechaHora))).get();
    final etiquetaDocumento = await _etiquetasPorId(
      ids: documentoPorEmitirEventos.map((e) => e.documentoPorEmitirId),
      cargar: (ids) async {
        final filas = await (_db.select(_db.documentoPorEmitir)..where((t) => t.id.isIn(ids))).get();
        return {
          for (final f in filas)
            f.id: f.codigo,
        };
      },
    );
    eventos.addAll(documentoPorEmitirEventos.map((e) => EventoAuditoria(
          fechaHora: e.fechaHora,
          actorUsuarioId: e.actorUsuarioId,
          modulo: 'comercial',
          accion: e.tipoEvento,
          registroId: e.documentoPorEmitirId,
          entidadEtiqueta: etiquetaDocumento[e.documentoPorEmitirId],
          motivo: e.observacion,
          detalleJson: e.datosRelevantes,
        )));

    final empleadoEventos = await (_db.select(_db.empleadoEvento)..where((t) => enRango(t.fechaHora))).get();
    eventos.addAll(empleadoEventos.map((e) => EventoAuditoria(
          fechaHora: e.fechaHora,
          actorUsuarioId: e.actorUsuarioId,
          modulo: 'personal',
          accion: e.tipoEvento,
          registroId: e.empleadoId,
          motivo: e.observacion,
          detalleJson: e.datosRelevantes,
        )));

    final usuarioEventos = await (_db.select(_db.usuarioEvento)..where((t) => enRango(t.fechaHora))).get();
    final etiquetaUsuarioAuditado = await _etiquetasPorId(
      ids: usuarioEventos.map((e) => e.usuarioId),
      cargar: (ids) async {
        final filas = await (_db.select(_db.usuario)..where((t) => t.id.isIn(ids))).get();
        return {
          for (final f in filas)
            f.id: f.nombre,
        };
      },
    );
    eventos.addAll(usuarioEventos.map((e) => EventoAuditoria(
          fechaHora: e.fechaHora,
          actorUsuarioId: e.actorUsuarioId,
          modulo: 'usuarios',
          accion: e.tipoEvento,
          registroId: e.usuarioId,
          entidadEtiqueta: etiquetaUsuarioAuditado[e.usuarioId],
          motivo: e.observacion,
          detalleJson: e.datosRelevantes,
        )));

    final eliminacionesFisicas =
        await (_db.select(_db.eliminacionFisicaEvento)..where((t) => enRango(t.fechaHora))).get();
    eventos.addAll(eliminacionesFisicas.map((e) => EventoAuditoria(
          fechaHora: e.fechaHora,
          actorUsuarioId: e.actorUsuarioId,
          // `tipoEntidad` es más específico que el código de módulo
          // estándar (ej. `'vehiculo'` singular vs. `'vehiculos'`) — se
          // traduce aquí para que filtrar por Módulo también encuentre
          // las eliminaciones físicas de ese dominio; `tipoEntidad`
          // sigue disponible completo dentro de `accion`, sin perderse.
          modulo: _moduloDeTipoEntidad(e.tipoEntidad),
          accion: 'eliminacionFisica:${e.tipoEntidad}',
          registroId: e.entidadIdOriginal,
          motivo: e.motivo,
          detalleJson: e.snapshotJson,
        )));

    // --- Ledgers que ya eran su propio evento (sin tipoEvento/datosRelevantes propios) ---

    final movimientos = await (_db.select(_db.movimientoInventario)..where((t) => enRango(t.fecha))).get();
    eventos.addAll(movimientos.map((e) => EventoAuditoria(
          fechaHora: e.fecha,
          actorUsuarioId: e.actorUsuarioId,
          modulo: 'inventario',
          accion: e.tipoMovimiento,
          registroId: e.articuloId,
          motivo: e.observaciones,
        )));

    final kilometrajes = await (_db.select(_db.vehiculoKilometraje)..where((t) => enRango(t.fecha))).get();
    eventos.addAll(kilometrajes.map((e) => EventoAuditoria(
          fechaHora: e.fecha,
          actorUsuarioId: e.actorUsuarioId,
          modulo: 'vehiculos',
          accion: e.origen,
          registroId: e.vehiculoId,
          motivo: e.observaciones,
        )));

    final documentosVehiculo = await (_db.select(_db.vehiculoDocumento)..where((t) => enRango(t.createdAt))).get();
    eventos.addAll(documentosVehiculo.map((e) => EventoAuditoria(
          fechaHora: e.createdAt,
          actorUsuarioId: e.actorUsuarioId,
          modulo: 'vehiculos',
          accion: 'documento_${e.tipo}',
          registroId: e.vehiculoId,
          motivo: e.observaciones,
        )));

    final mantenimientos = await (_db.select(_db.vehiculoMantenimiento)..where((t) => enRango(t.fecha))).get();
    eventos.addAll(mantenimientos.map((e) => EventoAuditoria(
          fechaHora: e.fecha,
          actorUsuarioId: e.actorUsuarioId,
          modulo: 'vehiculos',
          accion: e.tipo,
          registroId: e.vehiculoId,
          motivo: e.observaciones,
        )));

    final recargas = await (_db.select(_db.recargaLineaTelefonica)..where((t) => enRango(t.fecha))).get();
    eventos.addAll(recargas.map((e) => EventoAuditoria(
          fechaHora: e.fecha,
          actorUsuarioId: e.actorUsuarioId,
          modulo: 'telefonia',
          accion: 'recarga',
          registroId: e.lineaTelefonicaId,
          motivo: e.observaciones,
        )));

    // --- Etapa 9D: asociación/cambio de línea y expediente del Equipo ---

    final asignacionesLinea =
        await (_db.select(_db.asignacionLineaTelefonica)..where((t) => enRango(t.updatedAt))).get();
    // El CIERRE de una asignación ya lo expresa la propia fila
    // (`fechaTermino` + `motivoTermino`): no se le emite además un
    // evento, que sería duplicar el mismo hecho. Lo que sí hace falta
    // es que la acción DIGA por qué se cerró, para distinguir
    // "asignación cerrada por baja de la LÍNEA" de "cerrada por baja
    // del EMPLEADO" — y ambas de "línea dada de baja", que sí es un
    // evento propio de `LineaTelefonicaEvento`.
    eventos.addAll(asignacionesLinea.map((e) => EventoAuditoria(
          fechaHora: e.updatedAt,
          actorUsuarioId: e.actorUsuarioId,
          modulo: 'telefonia',
          accion: e.fechaTermino == null ? 'asignacionLinea' : 'asignacionCerrada:${e.motivoTermino ?? 'otro'}',
          registroId: e.lineaTelefonicaId,
          motivo: e.observacionesTermino ?? e.observaciones,
        )));

    final equiposLinea = await (_db.select(_db.lineaTelefonicaEquipo)..where((t) => enRango(t.updatedAt))).get();
    eventos.addAll(equiposLinea.map((e) => EventoAuditoria(
          fechaHora: e.updatedAt,
          actorUsuarioId: e.actorUsuarioId,
          modulo: 'telefonia',
          accion: 'equipoLinea',
          registroId: e.lineaTelefonicaId,
          motivo: e.observaciones,
        )));

    final eventosEquipo = await (_db.select(_db.equipoTelefonicoEvento)..where((t) => enRango(t.fechaHora))).get();
    eventos.addAll(eventosEquipo.map((e) => EventoAuditoria(
          fechaHora: e.fechaHora,
          actorUsuarioId: e.actorUsuarioId,
          modulo: 'telefonia',
          accion: e.tipoEvento,
          registroId: e.unidadId,
          motivo: e.observacion,
        )));

    // Vehículos (schemaVersion 80) — cierra el gap P0 de la auditoría
    // de la v79: hasta esta etapa el módulo no dejaba NINGÚN rastro, ni
    // del expediente ni de sus gastos.
    final eventosVehiculo = await (_db.select(_db.vehiculoEvento)..where((t) => enRango(t.fechaHora))).get();
    // `estadoAnterior`/`estadoNuevo` existian desde la v80 pero esta
    // proyeccion los descartaba: el diff quedaba escrito y nunca se veia
    // en Auditoria central. Se corrige aqui, en la capa de proyeccion —
    // el modulo Vehiculos no se toca.
    final etiquetaVehiculo = await _etiquetasPorId(
      ids: eventosVehiculo.map((e) => e.vehiculoId),
      cargar: (ids) async {
        final filas = await (_db.select(_db.vehiculo)..where((t) => t.id.isIn(ids))).get();
        return {for (final v in filas) v.id: v.codigo};
      },
    );
    eventos.addAll(eventosVehiculo.map((e) => EventoAuditoria(
          fechaHora: e.fechaHora,
          actorUsuarioId: e.actorUsuarioId,
          modulo: 'vehiculos',
          accion: e.tipoEvento,
          registroId: e.vehiculoId,
          motivo: e.observacion,
          entidadEtiqueta: etiquetaVehiculo[e.vehiculoId],
          cambios: _cambiosDeJson(e.estadoAnterior, e.estadoNuevo),
        )));

    // === Etapa "Auditoria central completa": los 3 historiales que ===
    // === existian en su tabla pero NUNCA llegaban a Configuracion  ===
    // === -> Auditoria. Se LEEN las tablas existentes; ningun evento ===
    // === se copia, se reescribe ni se duplica.                     ===

    // --- Tiempo Extra ---
    //
    // Ojo con `observacion`: NO siempre es un motivo. En el evento
    // `registrado` el repositorio guarda ahi un JSON con el resumen del
    // alta (`montoTotal`/`costosAdicionales`); en `corregido` y
    // `cancelado` si es el motivo que capturo el usuario. Volcarlo
    // siempre a la columna Motivo mostraria JSON crudo donde debe ir
    // texto — se separa segun su forma real, sin tocar el origen.
    final eventosTiempoExtra = await (_db.select(_db.tiempoExtraEvento)..where((t) => enRango(t.fechaHora))).get();
    final etiquetaTiempoExtra = await _etiquetasPorId(
      ids: eventosTiempoExtra.map((e) => e.tiempoExtraId),
      cargar: (ids) async {
        final filas = await (_db.select(_db.tiempoExtra)..where((t) => t.id.isIn(ids))).get();
        return {for (final t in filas) t.id: t.folio};
      },
    );
    eventos.addAll(eventosTiempoExtra.map((e) {
      final observacionEsJson = _pareceJsonDeObjeto(e.observacion);
      return EventoAuditoria(
        fechaHora: e.fechaHora,
        actorUsuarioId: e.actorUsuarioId,
        modulo: 'tiempoExtra',
        accion: e.tipoEvento,
        registroId: e.tiempoExtraId,
        motivo: observacionEsJson ? null : e.observacion,
        detalleJson: observacionEsJson ? e.observacion : null,
        entidadEtiqueta: etiquetaTiempoExtra[e.tiempoExtraId],
        cambios: _cambiosDeJson(e.estadoAnterior, e.estadoNuevo),
      );
    }));

    // --- Inventario: correcciones de identidad de una unidad ---
    //
    // Esta tabla NO usa estadoAnterior/estadoNuevo: tiene columnas
    // dedicadas `campo`/`valorAnterior`/`valorNuevo`, una fila por
    // campo corregido. Se proyecta tal cual — forzarla a JSON solo para
    // parecerse a las demas perderia el tipado sin ganar nada.
    //
    // El id del evento es el de la UNIDAD, pero el expediente de
    // Inventario es por ARTICULO: se resuelve el articulo en lote
    // (`destinoId`), nunca con una consulta por fila.
    final eventosUnidad = await (_db.select(_db.articuloUnidadEvento)..where((t) => enRango(t.fechaHora))).get();
    final unidadesDeEventos = <String, ArticuloUnidadData>{};
    if (eventosUnidad.isNotEmpty) {
      final ids = eventosUnidad.map((e) => e.unidadId).toSet().toList();
      final filas = await (_db.select(_db.articuloUnidad)..where((t) => t.id.isIn(ids))).get();
      unidadesDeEventos.addEntries(filas.map((u) => MapEntry(u.id, u)));
    }
    eventos.addAll(eventosUnidad.map((e) {
      final unidad = unidadesDeEventos[e.unidadId];
      return EventoAuditoria(
        fechaHora: e.fechaHora,
        actorUsuarioId: e.actorUsuarioId,
        modulo: 'inventario',
        accion: e.tipoEvento,
        registroId: e.unidadId,
        motivo: e.motivo,
        entidadEtiqueta: unidad?.numeroSerie,
        destinoId: unidad?.articuloId,
        cambios: [CambioAuditoria(campo: e.campo, antes: e.valorAnterior, despues: e.valorNuevo)],
      );
    }));

    // --- Boveda de Accesos ---
    //
    // PRIVACIDAD: `BovedaCredencialEvento` no tiene ninguna columna
    // capaz de contener el secreto — no existe `datosRelevantes` ni
    // `estadoAnterior`/`estadoNuevo`, y sus 6 llamadores reales no
    // pasan `observacion` en absoluto (auditado uno por uno). Aqui se
    // proyectan EXCLUSIVAMENTE metadatos: quien, cuando, que accion y el
    // NOMBRE de la credencial. Nunca `secretoCifrado`, ni siquiera su
    // forma cifrada.
    final eventosBoveda = await (_db.select(_db.bovedaCredencialEvento)..where((t) => enRango(t.fechaHora))).get();
    final etiquetaBoveda = await _etiquetasPorId(
      ids: eventosBoveda.map((e) => e.credencialId),
      cargar: (ids) async {
        final filas = await (_db.select(_db.bovedaCredencial)..where((t) => t.id.isIn(ids))).get();
        // Solo `nombre`: nunca `secretoCifrado`, `usuarioAcceso` ni
        // `correo` — el nombre basta para identificar la credencial y no
        // revela credencial alguna.
        return {for (final c in filas) c.id: c.nombre};
      },
    );
    eventos.addAll(eventosBoveda.map((e) => EventoAuditoria(
          fechaHora: e.fechaHora,
          actorUsuarioId: e.actorUsuarioId,
          modulo: 'boveda',
          accion: e.tipoEvento,
          registroId: e.credencialId,
          // Ninguna accion de Boveda exige motivo hoy; `observacion` se
          // respeta si algun dia lo hubiera, pero nunca se inventa.
          motivo: e.observacion,
          entidadEtiqueta: etiquetaBoveda[e.credencialId],
        )));

    // Telefonía (schemaVersion 81) — hasta aquí la Auditoría central
    // solo veía las recargas, las asignaciones y los eventos del
    // EQUIPO: la línea en sí no dejaba ningún rastro, ni de su alta ni
    // de correcciones a su número/ICCID.
    //
    // NO se emite un evento por recarga registrada: esa fila YA se
    // proyecta arriba desde `recargaLineaTelefonica` (Etapa 11D).
    // Duplicarla sería justo lo que hay que evitar, y además dejaría
    // fuera las recargas históricas, que no tienen evento.
    final eventosLinea = await (_db.select(_db.lineaTelefonicaEvento)..where((t) => enRango(t.fechaHora))).get();
    final etiquetaLinea = await _etiquetasPorId(
      ids: eventosLinea.map((e) => e.lineaTelefonicaId),
      cargar: (ids) async {
        final filas = await (_db.select(_db.lineaTelefonica)..where((t) => t.id.isIn(ids))).get();
        // Solo el `codigo` (LIN-000004): nunca `numero` ni `iccid`, que
        // son los identificadores sensibles de la SIM.
        return {for (final l in filas) l.id: l.codigo};
      },
    );
    eventos.addAll(eventosLinea.map((e) => EventoAuditoria(
          fechaHora: e.fechaHora,
          actorUsuarioId: e.actorUsuarioId,
          modulo: 'telefonia',
          accion: e.tipoEvento,
          registroId: e.lineaTelefonicaId,
          motivo: e.observacion,
          entidadEtiqueta: etiquetaLinea[e.lineaTelefonicaId],
          cambios: _cambiosDeJson(e.estadoAnterior, e.estadoNuevo),
        )));

    // --- Servicios Eventuales (schemaVersion 87-89) ---
    //
    // Crear la tabla NO la integra: este bloque es lo que hace que un
    // eventual aparezca en Auditoría central, igual que Tiempo Extra y
    // Telefonía tuvieron que declararse aquí.
    //
    // NO se duplica nada financiero: el Pago del cliente, el Egreso de
    // una cobertura y el MovimientoDeuda de un cargo a tarjeta ya se
    // proyectan por su cuenta más arriba. Aquí sólo viaja el hecho
    // comercial del evento, con su motivo y su diff.
    //
    // La etiqueta es el folio (EVT-000001) — nunca el nombre del
    // solicitante ocasional ni su teléfono: no se agrega ningún dato
    // sensible que Auditoría no mostrara antes.
    final eventosEventual =
        await (_db.select(_db.servicioEventualEvento)..where((t) => enRango(t.fechaHora))).get();
    final etiquetaEventual = await _etiquetasPorId(
      ids: eventosEventual.map((e) => e.servicioEventualId),
      cargar: (ids) async {
        final filas = await (_db.select(_db.servicioEventual)..where((t) => t.id.isIn(ids))).get();
        return {for (final e in filas) e.id: e.folio};
      },
    );
    eventos.addAll(eventosEventual.map((e) => EventoAuditoria(
          fechaHora: e.fechaHora,
          actorUsuarioId: e.actorUsuarioId,
          modulo: 'serviciosEventuales',
          accion: e.tipoEvento,
          registroId: e.servicioEventualId,
          motivo: e.observacion,
          entidadEtiqueta: etiquetaEventual[e.servicioEventualId],
          cambios: _cambiosDeJson(e.estadoAnterior, e.estadoNuevo),
        )));

    // === Etapa "Ledgers de Deudas y Descuentos": los dos historiales ===
    // === con actorUsuarioId que seguían sin llegar a Auditoría.      ===

    // --- MovimientoDeuda ---
    //
    // DUPLICIDAD SEMÁNTICA, resuelta a propósito y no ocultando nada:
    // una Compra pagada con TDC produce DOS eventos legítimos y
    // distintos — `CompraEvento` (cambió el DOCUMENTO de la operación) y
    // este `MovimientoDeuda` (cambió el SALDO de la tarjeta). Los dos se
    // muestran, pero la acción de este último dice de dónde vino el
    // cargo (`cargoTarjeta:compra`), así que en la pantalla se leen como
    // "Compra corregida" y "Cargo a TDC por Compra" — nunca como la
    // misma fila repetida.
    final movimientosDeuda = await (_db.select(_db.movimientoDeuda)..where((t) => enRango(t.fecha))).get();
    final etiquetaDeuda = await _etiquetasPorId(
      ids: movimientosDeuda.map((e) => e.deudaId),
      cargar: (ids) async {
        final filas = await (_db.select(_db.deuda)..where((t) => t.id.isIn(ids))).get();
        // Solo `nombre`: identifica la tarjeta sin exponer
        // `tarjetaUltimosDigitos` ni ningún otro dato bancario que la
        // Auditoría no necesita para responder "quién movió qué".
        return {for (final d in filas) d.id: d.nombre};
      },
    );
    eventos.addAll(movimientosDeuda.map((e) => EventoAuditoria(
          fechaHora: e.fecha,
          actorUsuarioId: e.actorUsuarioId,
          modulo: 'deudas',
          accion: _accionMovimientoDeuda(e),
          registroId: e.deudaId,
          motivo: e.observaciones,
          entidadEtiqueta: etiquetaDeuda[e.deudaId],
          importe: e.importe,
          // El efecto real y verificable del movimiento: el saldo antes
          // y después. Son columnas propias de la tabla — no hay que
          // inventar ningún JSON para expresarlo.
          cambios: [
            CambioAuditoria(
              campo: 'saldo',
              antes: e.saldoAnterior.toString(),
              despues: e.saldoPosterior.toString(),
              esImporte: true,
            ),
          ],
        )));

    // --- DescuentoProgramadoMovimiento ---
    //
    // `cuotaId` nulo = movimiento de la OBLIGACIÓN completa
    // (otorgamiento, corrección, cancelación, reprogramación); no nulo =
    // movimiento de una CUOTA concreta (reservada/aplicada/revertida).
    // Esa distinción se conserva en la acción y en la etiqueta de
    // entidad, con ids reales.
    //
    // La tabla YA expresa la transición con el propio `tipoMovimiento`
    // (`cuotaReservada` → `cuotaAplicada`): no se le fabrica un
    // `estadoAnterior`/`estadoNuevo` que no tiene. Los únicos cambios
    // estructurados que se proyectan son los reales, los de
    // `correccion`, que sí vienen de `DiffEvento`.
    final movimientosDescuento =
        await (_db.select(_db.descuentoProgramadoMovimiento)..where((t) => enRango(t.fechaHora))).get();
    final etiquetaDescuento = await _etiquetasPorId(
      ids: movimientosDescuento.map((e) => e.descuentoProgramadoId),
      cargar: (ids) async {
        final filas = await (_db.select(_db.descuentoProgramadoEmpleado)..where((t) => t.id.isIn(ids))).get();
        return {for (final d in filas) d.id: d.folio};
      },
    );
    // Número de cuota, resuelto en LOTE sobre los ids distintos que
    // aparecen — nunca una consulta por movimiento.
    final numeroDeCuota = <String, int>{};
    final idsCuota = movimientosDescuento.map((e) => e.cuotaId).whereType<String>().toSet().toList();
    if (idsCuota.isNotEmpty) {
      final filas = await (_db.select(_db.descuentoProgramadoCuota)..where((t) => t.id.isIn(idsCuota))).get();
      numeroDeCuota.addEntries(filas.map((c) => MapEntry(c.id, c.numeroCuota)));
    }
    eventos.addAll(movimientosDescuento.map((e) {
      final folio = etiquetaDescuento[e.descuentoProgramadoId];
      final numero = e.cuotaId == null ? null : numeroDeCuota[e.cuotaId];
      return EventoAuditoria(
        fechaHora: e.fechaHora,
        actorUsuarioId: e.actorUsuarioId,
        modulo: 'descuentos',
        accion: e.tipoMovimiento,
        registroId: e.descuentoProgramadoId,
        motivo: e.observacion,
        detalleJson: e.datosRelevantes,
        entidadEtiqueta: numero == null ? folio : '$folio — cuota $numero',
        importe: e.importe,
        cambios: _cambiosDeJson(e.estadoAnterior, e.estadoNuevo),
      );
    }));

    // --- Filtros en memoria (usuario/módulo/acción) + orden final ---

    final filtrados = eventos.where((e) {
      if (filtro.actorUsuarioId != null && e.actorUsuarioId != filtro.actorUsuarioId) return false;
      if (filtro.modulo != null && e.modulo != filtro.modulo) return false;
      if (filtro.accion != null && e.accion != filtro.accion) return false;
      return true;
    }).toList();

    filtrados.sort((a, b) => b.fechaHora.compareTo(a.fechaHora));
    return filtrados;
  }

  /// Acción legible de un `MovimientoDeuda`, con su ORIGEN FUNCIONAL
  /// resuelto por FK real — nunca por texto ni por el nombre de nada.
  ///
  /// Distingue los dos mundos que conviven en la misma tabla:
  ///  - un ajuste con `movimientoOrigenId` corrige un PAGO;
  ///  - un ajuste con `compraId`/`tiempoExtraId`/`costoAdicionalId`/
  ///    `egresoGastoId`/`vehiculoMantenimientoId` corrige un CARGO.
  /// Es el mismo discriminador que ya usa `totalCargadoEnRango` para no
  /// contar dos veces; aquí sirve para que la acción diga la verdad.
  static String _accionMovimientoDeuda(MovimientoDeudaData m) {
    final origen = _origenFuncionalDeCargo(m);
    return switch (m.tipo) {
      'cargoCompra' => origen == null ? 'cargoTarjeta' : 'cargoTarjeta:$origen',
      'ajustePositivo' when m.movimientoOrigenId != null => 'correccionPago:positivo',
      'ajusteNegativo' when m.movimientoOrigenId != null => 'correccionPago:negativo',
      'ajustePositivo' => origen == null ? 'ajusteTarjeta:positivo' : 'ajusteTarjeta:$origen',
      'ajusteNegativo' => origen == null ? 'ajusteTarjeta:negativo' : 'ajusteTarjeta:$origen',
      _ => m.tipo,
    };
  }

  /// Cuál de las cinco FK de gasto está poblada, si alguna. Exactamente
  /// una puede estarlo (invariante de `MovimientoDeuda`).
  static String? _origenFuncionalDeCargo(MovimientoDeudaData m) {
    if (m.compraId != null) return 'compra';
    if (m.tiempoExtraId != null) return 'tiempoExtra';
    if (m.costoAdicionalId != null) return 'tiempoExtraCosto';
    if (m.egresoGastoId != null) return 'egreso';
    if (m.vehiculoMantenimientoId != null) return 'vehiculo';
    return null;
  }

  /// Lookup EN LOTE de etiquetas legibles: una sola consulta por tipo de
  /// entidad, sobre los ids DISTINTOS que aparecen en el resultado.
  /// Existe para que integrar mas origenes no convierta la pantalla en
  /// cientos de consultas — abrir Auditoria sigue costando una consulta
  /// por tabla, nunca una por fila.
  Future<Map<String, String>> _etiquetasPorId({
    required Iterable<String> ids,
    required Future<Map<String, String>> Function(List<String> ids) cargar,
  }) async {
    final distintos = ids.toSet().toList();
    if (distintos.isEmpty) return const {};
    return cargar(distintos);
  }

  /// `true` si el texto es un JSON de objeto (`{...}`) y no un motivo
  /// escrito por una persona.
  static bool _pareceJsonDeObjeto(String? texto) {
    final valor = texto?.trim();
    if (valor == null || !valor.startsWith('{') || !valor.endsWith('}')) return false;
    try {
      return jsonDecode(valor) is Map;
    } catch (_) {
      return false;
    }
  }

  /// Convierte el par `estadoAnterior`/`estadoNuevo` (JSON de objeto,
  /// el formato de `DiffEvento`) en una lista `campo: antes -> despues`.
  ///
  /// Ambos lados pueden traer claves distintas (un campo que solo
  /// aparece en uno de los dos es un alta o una baja de valor), asi que
  /// se recorre la UNION de claves. Un JSON ilegible no rompe la
  /// pantalla: se devuelve vacio y el detalle crudo sigue disponible.
  static List<CambioAuditoria> _cambiosDeJson(String? estadoAnterior, String? estadoNuevo) {
    Map<String, dynamic>? decodificar(String? texto) {
      if (texto == null || texto.trim().isEmpty) return null;
      try {
        final valor = jsonDecode(texto);
        return valor is Map<String, dynamic> ? valor : null;
      } catch (_) {
        return null;
      }
    }

    final antes = decodificar(estadoAnterior);
    final despues = decodificar(estadoNuevo);
    if (antes == null && despues == null) return const [];

    final claves = <String>{...?antes?.keys, ...?despues?.keys}.toList()..sort();
    return [
      for (final clave in claves)
        CambioAuditoria(
          campo: clave,
          antes: antes?[clave]?.toString(),
          despues: despues?[clave]?.toString(),
        ),
    ];
  }

  /// Traduce el `tipoEntidad` de una eliminación física (singular, ej.
  /// `'vehiculo'`) al código de módulo estándar del catálogo de
  /// permisos (ej. `'vehiculos'`) — así el filtro de Módulo de la
  /// pantalla de Auditoría encuentra estos eventos igual que cualquier
  /// otro del mismo dominio.
  /// Traduce el `tipoEntidad` de una eliminación física al código de módulo
  /// que usa el resto de la auditoría.
  ///
  /// Existe para dos cosas a la vez: que filtrar por Módulo encuentre
  /// también las eliminaciones físicas de ese dominio, y que la columna no
  /// enseñe el nombre técnico de la tabla. Cada tipo apunta al MISMO código
  /// que ya usa su familia de eventos (un Pago borrado cae en `finanzas`,
  /// igual que `PagoEvento`), para que un filtro no parta en dos la historia
  /// de la misma entidad.
  ///
  /// El `tipoEntidad` completo nunca se pierde: sigue dentro de `accion`
  /// (`eliminacionFisica:<tipo>`) y se muestra en el detalle.
  String _moduloDeTipoEntidad(String tipoEntidad) {
    return switch (tipoEntidad) {
      'vehiculo' => 'vehiculos',
      'lineaTelefonica' => 'telefonia',
      'articulo' || 'categoriaArticulo' => 'inventario',
      'area' || 'puesto' || 'sucursal' => 'organizacion',
      'cliente' || 'clientePortal' => 'clientes',
      'servicio' || 'servicioLineaComercial' => 'servicios',
      'documentoPorEmitir' => 'comercial',
      'servicioEventual' => 'serviciosEventuales',
      'empleado' => 'personal',
      'nomina' => 'nomina',
      'compra' => 'compras',
      'tiempoExtra' => 'tiempoExtra',
      'descuentoProgramado' => 'descuentos',
      'deuda' => 'deudas',
      // `cuenta_financiera` quedó en snake_case cuando el resto es camelCase
      // (deuda técnica del valor ya persistido): se acepta tal cual, nunca
      // se reescribe un evento histórico para que case con una convención.
      'cuenta_financiera' || 'cuentaFinanciera' => 'cuentasFinancieras',
      'categoriaFinanciera' => 'categoriasFinancieras',
      'pago' => 'finanzas',
      'egreso' => 'egresos',
      // Un tipo nuevo que nadie haya mapeado todavía cae aquí y se ve crudo:
      // es preferible a esconderlo bajo un módulo que no le corresponde.
      _ => tipoEntidad,
    };
  }
}
