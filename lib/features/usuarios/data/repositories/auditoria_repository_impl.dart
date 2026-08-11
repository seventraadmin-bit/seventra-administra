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
    eventos.addAll(compraEventos.map((e) => EventoAuditoria(
          fechaHora: e.fechaHora,
          actorUsuarioId: e.actorUsuarioId,
          modulo: 'compras',
          accion: e.tipoEvento,
          registroId: e.compraId,
          motivo: e.observacion,
          detalleJson: e.datosRelevantes,
        )));

    final complementoEventos = await (_db.select(_db.complementoPagoEvento)..where((t) => enRango(t.fechaHora))).get();
    eventos.addAll(complementoEventos.map((e) => EventoAuditoria(
          fechaHora: e.fechaHora,
          actorUsuarioId: e.actorUsuarioId,
          modulo: 'finanzas',
          accion: e.tipoEvento,
          registroId: e.complementoPagoId,
          motivo: e.observacion,
          detalleJson: e.datosRelevantes,
        )));

    final cuentaPorCobrarEventos = await (_db.select(_db.cuentaPorCobrarEvento)..where((t) => enRango(t.fechaHora))).get();
    eventos.addAll(cuentaPorCobrarEventos.map((e) => EventoAuditoria(
          fechaHora: e.fechaHora,
          actorUsuarioId: e.actorUsuarioId,
          modulo: 'finanzas',
          accion: e.tipoEvento,
          registroId: e.cuentaPorCobrarId,
          motivo: e.observacion,
          detalleJson: e.datosRelevantes,
        )));

    final egresoEventos = await (_db.select(_db.egresoEvento)..where((t) => enRango(t.fechaHora))).get();
    eventos.addAll(egresoEventos.map((e) => EventoAuditoria(
          fechaHora: e.fechaHora,
          actorUsuarioId: e.actorUsuarioId,
          modulo: 'finanzas',
          accion: e.tipoEvento,
          registroId: e.egresoId,
          motivo: e.observacion,
          detalleJson: e.datosRelevantes,
        )));

    final ingresoEventos = await (_db.select(_db.ingresoEvento)..where((t) => enRango(t.fechaHora))).get();
    eventos.addAll(ingresoEventos.map((e) => EventoAuditoria(
          fechaHora: e.fechaHora,
          actorUsuarioId: e.actorUsuarioId,
          modulo: 'finanzas',
          accion: e.tipoEvento,
          registroId: e.ingresoId,
          motivo: e.observacion,
          detalleJson: e.datosRelevantes,
        )));

    final pagoEventos = await (_db.select(_db.pagoEvento)..where((t) => enRango(t.fechaHora))).get();
    eventos.addAll(pagoEventos.map((e) => EventoAuditoria(
          fechaHora: e.fechaHora,
          actorUsuarioId: e.actorUsuarioId,
          modulo: 'finanzas',
          accion: e.tipoEvento,
          registroId: e.pagoId,
          motivo: e.observacion,
          detalleJson: e.datosRelevantes,
        )));

    final nominaEventos = await (_db.select(_db.nominaEvento)..where((t) => enRango(t.fechaHora))).get();
    eventos.addAll(nominaEventos.map((e) => EventoAuditoria(
          fechaHora: e.fechaHora,
          actorUsuarioId: e.actorUsuarioId,
          modulo: 'nomina',
          accion: e.tipoEvento,
          registroId: e.nominaEmpleadoId ?? e.nominaId,
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

    final documentoPorEmitirEventos =
        await (_db.select(_db.documentoPorEmitirEvento)..where((t) => enRango(t.fechaHora))).get();
    eventos.addAll(documentoPorEmitirEventos.map((e) => EventoAuditoria(
          fechaHora: e.fechaHora,
          actorUsuarioId: e.actorUsuarioId,
          modulo: 'comercial',
          accion: e.tipoEvento,
          registroId: e.documentoPorEmitirId,
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
    eventos.addAll(usuarioEventos.map((e) => EventoAuditoria(
          fechaHora: e.fechaHora,
          actorUsuarioId: e.actorUsuarioId,
          modulo: 'usuarios',
          accion: e.tipoEvento,
          registroId: e.usuarioId,
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

  /// Traduce el `tipoEntidad` de una eliminación física (singular, ej.
  /// `'vehiculo'`) al código de módulo estándar del catálogo de
  /// permisos (ej. `'vehiculos'`) — así el filtro de Módulo de la
  /// pantalla de Auditoría encuentra estos eventos igual que cualquier
  /// otro del mismo dominio.
  String _moduloDeTipoEntidad(String tipoEntidad) {
    return switch (tipoEntidad) {
      'vehiculo' => 'vehiculos',
      'lineaTelefonica' => 'telefonia',
      'articulo' || 'categoriaArticulo' => 'inventario',
      'area' || 'puesto' || 'sucursal' => 'organizacion',
      _ => tipoEntidad,
    };
  }
}
