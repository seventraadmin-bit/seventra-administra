import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:riseg_one/core/auditoria/diff_evento.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';
import 'package:riseg_one/core/utils/clock.dart';

import '../tables/comercial_evento_table.dart';
import 'comercial_evento_writer.dart';
import '../../domain/repositories/servicio_comercial_repository.dart';
import '../../domain/shared/horario_input.dart';
import '../../domain/usecases/atribucion_historica_linea_comercial.dart';
import '../../domain/usecases/eliminar_linea_comercial_fisicamente_usecase.dart';
import '../../domain/usecases/linea_comercial_con_vigencia.dart';
import '../../domain/usecases/linea_comercial_validator.dart';

class ServicioComercialRepositoryImpl implements ServicioComercialRepository {
  ServicioComercialRepositoryImpl(this._db, {Clock clock = const SystemClock()}) : _clock = clock;

  final AppDatabase _db;
  final Clock _clock;

  /// Reemplaza por completo el horario personalizado de una vigencia —
  /// mismo criterio que `SucursalRepositoryImpl._guardarHorario`: los 7
  /// renglones no tienen identidad propia fuera de "el renglón del día
  /// X de esta vigencia", así que se borran y se vuelven a insertar
  /// dentro de la misma transacción en vez de actualizarse uno a uno.
  /// `horario == null` solo deja la vigencia sin ningún renglón (caso
  /// normal cuando su modalidad no es Personalizado).
  Future<void> _guardarHorario(String vigenciaId, HorarioSemanalInput? horario) async {
    await (_db.delete(_db.servicioLineaComercialVigenciaHorario)
          ..where((t) => t.lineaComercialVigenciaId.equals(vigenciaId)))
        .go();
    if (horario == null) return;

    for (final dia in horario.dias) {
      await _db.into(_db.servicioLineaComercialVigenciaHorario).insert(
            ServicioLineaComercialVigenciaHorarioCompanion.insert(
              lineaComercialVigenciaId: vigenciaId,
              diaSemana: dia.diaSemana,
              horaInicio: dia.horaInicioMinutos ?? 0,
              horaFin: dia.horaFinMinutos ?? 0,
              cruzaMedianoche: Value(dia.cruzaMedianoche),
              activo: Value(dia.abierto),
            ),
          );
    }
  }

  @override
  Future<List<ServicioLineaComercialVigenciaHorarioData>> obtenerHorario(String vigenciaId) {
    return (_db.select(_db.servicioLineaComercialVigenciaHorario)
          ..where((t) => t.lineaComercialVigenciaId.equals(vigenciaId))
          ..orderBy([(t) => OrderingTerm.asc(t.diaSemana)]))
        .get();
  }

  /// Las condiciones ECONÓMICAS de una vigencia, tal como quedan.
  ///
  /// Se usa como snapshot en los hechos que ABREN condiciones (alta y
  /// nueva vigencia): ahí no hay un "antes" que comparar, lo que hay
  /// que poder responder después es qué empezó a aplicar. Importes en
  /// centavos enteros, como en todo el proyecto.
  Map<String, dynamic> _condicionesDe(ServicioLineaComercialVigenciaData v) => {
        'vigenciaId': v.id,
        'puestoId': v.puestoId,
        'modalidadTurnoId': v.modalidadTurnoId,
        'cantidadElementos': v.cantidadElementos,
        'precioUnitario': v.precioUnitario,
        'tratamientoIva': v.tratamientoIva,
        'fechaInicioVigencia': v.fechaInicioVigencia.toIso8601String(),
        'fechaFinVigencia': v.fechaFinVigencia?.toIso8601String(),
        'sueldoMensualReferenciaPersonal': v.sueldoMensualReferenciaPersonal,
        'bonoMensualReferenciaPersonal': v.bonoMensualReferenciaPersonal,
      };

  /// Diff entre dos estados de una MISMA vigencia — sólo para
  /// correcciones. Abrir una vigencia nueva nunca pasa por aquí.
  DiffEvento _diffCondiciones(
    ServicioLineaComercialVigenciaData antes,
    ServicioLineaComercialVigenciaData despues,
  ) =>
      DiffEvento()
        ..anotar('puestoId', antes.puestoId, despues.puestoId)
        ..anotar('modalidadTurnoId', antes.modalidadTurnoId, despues.modalidadTurnoId)
        ..anotar('cantidadElementos', antes.cantidadElementos, despues.cantidadElementos)
        ..anotar('precioUnitario', antes.precioUnitario, despues.precioUnitario)
        ..anotar('tratamientoIva', antes.tratamientoIva, despues.tratamientoIva)
        ..anotar('fechaInicioVigencia', antes.fechaInicioVigencia, despues.fechaInicioVigencia)
        ..anotar('fechaFinVigencia', antes.fechaFinVigencia, despues.fechaFinVigencia)
        ..anotar('descripcion', antes.descripcion, despues.descripcion)
        ..anotar('observaciones', antes.observaciones, despues.observaciones)
        ..anotar(
          'sueldoMensualReferenciaPersonal',
          antes.sueldoMensualReferenciaPersonal,
          despues.sueldoMensualReferenciaPersonal,
        )
        ..anotar(
          'bonoMensualReferenciaPersonal',
          antes.bonoMensualReferenciaPersonal,
          despues.bonoMensualReferenciaPersonal,
        );

  @override
  Future<({ServicioLineaComercialData linea, ServicioLineaComercialVigenciaData vigencia})> crearLinea({
    required String servicioId,
    required LineaComercialValidada datos,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final linea = await _db.into(_db.servicioLineaComercial).insertReturning(
            ServicioLineaComercialCompanion.insert(servicioId: servicioId),
          );

      final vigencia = await _db.into(_db.servicioLineaComercialVigencia).insertReturning(
            ServicioLineaComercialVigenciaCompanion.insert(
              lineaComercialId: linea.id,
              puestoId: datos.puestoId,
              modalidadTurnoId: datos.modalidadTurnoId,
              cantidadElementos: datos.cantidadElementos,
              precioUnitario: datos.precioUnitario,
              tratamientoIva: datos.tratamientoIva.name,
              descripcion: Value(datos.descripcion),
              fechaInicioVigencia: datos.fechaInicioVigencia,
              fechaFinVigencia: Value(datos.fechaFinVigencia),
              observaciones: Value(datos.observaciones),
              sueldoMensualReferenciaPersonal: Value(datos.sueldoMensualReferenciaPersonal),
              bonoMensualReferenciaPersonal: Value(datos.bonoMensualReferenciaPersonal),
            ),
          );
      await _guardarHorario(vigencia.id, datos.horario);

      // Alta: no hay un "antes" que comparar, así que se guarda el
      // snapshot de las condiciones que empiezan a aplicar. Sin motivo:
      // dar de alta una línea no es enmendar nada.
      await registrarEventoServicio(
        _db,
        servicioId: servicioId,
        tipoEvento: TipoEventoServicio.lineaComercialCreada,
        actorUsuarioId: actorUsuarioId,
        datosRelevantes: {'lineaComercialId': linea.id, ..._condicionesDe(vigencia)},
      );

      return (linea: linea, vigencia: vigencia);
    });
  }

  @override
  Future<List<LineaComercialConVigencia>> listarLineas(String servicioId) {
    return listarLineasEnFecha(servicioId, _clock.now());
  }

  @override
  Future<List<LineaComercialConVigencia>> listarLineasEnFecha(String servicioId, DateTime fecha) async {
    final lineas = await (_db.select(_db.servicioLineaComercial)..where((t) => t.servicioId.equals(servicioId))).get();
    final hoy = fecha;

    final resultado = <LineaComercialConVigencia>[];
    final lineasVigentesAtribuibles = <LineaVigenteAtribuible>[];
    for (final linea in lineas) {
      final vigenciasActivas = await _vigenciasActivasDeLinea(linea.id);

      final (:vigente, :programadas) = clasificarVigencias(vigenciasActivas, hoy);
      final vigenciaParaNombres = vigente ?? (programadas.isEmpty ? null : programadas.first);
      if (vigente != null) {
        lineasVigentesAtribuibles.add(LineaVigenteAtribuible(lineaComercialId: linea.id, modalidadTurnoId: vigente.modalidadTurnoId));
      }

      var puestoNombre = '';
      var modalidadTurnoNombre = '';
      if (vigenciaParaNombres != null) {
        final puesto = await (_db.select(_db.puesto)..where((t) => t.id.equals(vigenciaParaNombres.puestoId)))
            .getSingleOrNull();
        final modalidad = await (_db.select(_db.tipoModalidadTurno)
              ..where((t) => t.id.equals(vigenciaParaNombres.modalidadTurnoId)))
            .getSingleOrNull();
        puestoNombre = puesto?.nombre ?? '';
        modalidadTurnoNombre = modalidad?.nombre ?? '';
      }

      // Etapa 15: "corregible" = sigue siendo la captura original, sin
      // historia real todavía — todas las vigencias registradas
      // (`vigenciasActivas` no incluye las canceladas, pero una línea
      // corregible nunca tiene ninguna) son a lo más una, y esa una
      // nunca generó un documento de Agenda.
      final esCorregible =
          vigenciasActivas.length == 1 && !(await tieneDocumentosGenerados(vigenciasActivas.single.id));

      final asignadosVigentes = await (_db.selectOnly(_db.asignacionServicio)
            ..addColumns([_db.asignacionServicio.id.count()])
            ..where(
              _db.asignacionServicio.lineaComercialId.equals(linea.id) &
                  _db.asignacionServicio.fechaTermino.isNull(),
            ))
          .map((row) => row.read(_db.asignacionServicio.id.count()) ?? 0)
          .getSingle();

      final horarioVigenciaMostrada = vigenciaParaNombres == null ? const <ServicioLineaComercialVigenciaHorarioData>[] : await obtenerHorario(vigenciaParaNombres.id);

      resultado.add(
        LineaComercialConVigencia(
          linea: linea,
          vigenciaActual: vigente,
          vigenciasProgramadas: programadas,
          puestoNombre: puestoNombre,
          modalidadTurnoNombre: modalidadTurnoNombre,
          esCorregible: esCorregible,
          asignadosVigentes: asignadosVigentes,
          horarioVigenciaMostrada: horarioVigenciaMostrada,
        ),
      );
    }

    // Corrección de compatibilidad histórica: una `AsignacionServicio`
    // vigente con `lineaComercialId == NULL` (dato previo a Etapa 15,
    // ver el doc comment de esa columna) nunca aparecía en el conteo
    // directo de arriba — el bug real reportado ("MILOYILE 0/1" con un
    // Empleado realmente asignado). Se atribuye sin adivinar según
    // `atribuirAsignacionesHistoricas` (una sola línea vigente = sin
    // ambigüedad; 2+ líneas = solo si el turno coincide con exactamente
    // una) — nunca se escribe nada aquí, es una atribución de solo
    // lectura para el cálculo de cobertura.
    if (lineasVigentesAtribuibles.isNotEmpty) {
      final asignacionesSinLinea = await (_db.select(_db.asignacionServicio)
            ..where(
              (t) =>
                  t.servicioId.equals(servicioId) & t.lineaComercialId.isNull() & t.fechaTermino.isNull(),
            ))
          .get();

      if (asignacionesSinLinea.isNotEmpty) {
        final atribucion = atribuirAsignacionesHistoricas(
          asignacionesSinLinea: asignacionesSinLinea,
          lineasVigentes: lineasVigentesAtribuibles,
        );
        for (var i = 0; i < resultado.length; i++) {
          final extra = atribucion.atribuidasPorLinea[resultado[i].linea.id];
          if (extra == null || extra == 0) continue;
          resultado[i] = resultado[i].copyWith(asignadosVigentes: resultado[i].asignadosVigentes + extra);
        }
      }
    }

    return resultado;
  }

  @override
  Future<
      List<
          ({
            String servicioId,
            String lineaComercialId,
            String puestoNombre,
            int requerido,
            int cubierto,
          })>> listarCoberturaPorServicios(List<String> servicioIds, DateTime fecha) async {
    if (servicioIds.isEmpty) return const [];

    // 1) Todas las líneas de todos los Servicios pedidos.
    final lineas =
        await (_db.select(_db.servicioLineaComercial)..where((t) => t.servicioId.isIn(servicioIds))).get();
    if (lineas.isEmpty) return const [];
    final lineaIds = lineas.map((l) => l.id).toList();

    // 2) Todas las vigencias `activo` de esas líneas, agrupadas en
    // memoria — misma clasificación pura que `listarLineasEnFecha`
    // (`clasificarVigencias`), cero fórmula nueva.
    final vigencias = await (_db.select(_db.servicioLineaComercialVigencia)
          ..where(
            (t) => t.lineaComercialId.isIn(lineaIds) & t.cicloVidaRegistro.equals(CicloVidaRegistro.activo.name),
          ))
        .get();
    final vigenciasPorLinea = <String, List<ServicioLineaComercialVigenciaData>>{};
    for (final v in vigencias) {
      (vigenciasPorLinea[v.lineaComercialId] ??= []).add(v);
    }

    final vigentePorLinea = <String, ServicioLineaComercialVigenciaData>{};
    for (final linea in lineas) {
      final (:vigente, :programadas) = clasificarVigencias(vigenciasPorLinea[linea.id] ?? const [], fecha);
      if (vigente != null) vigentePorLinea[linea.id] = vigente;
    }

    // 3) Nombres de Puesto — solo los realmente referenciados.
    final puestoIds = vigentePorLinea.values.map((v) => v.puestoId).toSet().toList();
    final puestos =
        puestoIds.isEmpty ? const <PuestoData>[] : await (_db.select(_db.puesto)..where((t) => t.id.isIn(puestoIds))).get();
    final nombrePorPuesto = {for (final p in puestos) p.id: p.nombre};

    // 4) Conteo de AsignacionServicio vigentes por línea — una sola
    // consulta, fold en memoria (mismo patrón que
    // `totalCostosAdicionalesPorTiempoExtra`, nunca SQL GROUP BY en
    // este proyecto).
    final asignadasConLinea = await (_db.select(_db.asignacionServicio)
          ..where((t) => t.lineaComercialId.isIn(lineaIds) & t.fechaTermino.isNull()))
        .get();
    final asignadosPorLinea = <String, int>{};
    for (final a in asignadasConLinea) {
      final id = a.lineaComercialId!;
      asignadosPorLinea[id] = (asignadosPorLinea[id] ?? 0) + 1;
    }

    // 5) Atribución histórica (asignaciones vigentes con
    // `lineaComercialId == null`, dato previo a Etapa 15) — una sola
    // consulta para TODOS los Servicios, agrupada por servicio en
    // memoria; se reutiliza `atribuirAsignacionesHistoricas` por
    // Servicio (CPU, no I/O — cero consultas adicionales).
    final asignacionesSinLinea = await (_db.select(_db.asignacionServicio)
          ..where((t) => t.servicioId.isIn(servicioIds) & t.lineaComercialId.isNull() & t.fechaTermino.isNull()))
        .get();
    final sinLineaPorServicio = <String, List<AsignacionServicioData>>{};
    for (final a in asignacionesSinLinea) {
      (sinLineaPorServicio[a.servicioId] ??= []).add(a);
    }
    final lineasPorServicio = <String, List<ServicioLineaComercialData>>{};
    for (final l in lineas) {
      (lineasPorServicio[l.servicioId] ??= []).add(l);
    }

    for (final servicioId in servicioIds) {
      final sinLinea = sinLineaPorServicio[servicioId];
      if (sinLinea == null || sinLinea.isEmpty) continue;
      final lineasVigentesAtribuibles = [
        for (final l in lineasPorServicio[servicioId] ?? const <ServicioLineaComercialData>[])
          if (vigentePorLinea[l.id] != null)
            LineaVigenteAtribuible(lineaComercialId: l.id, modalidadTurnoId: vigentePorLinea[l.id]!.modalidadTurnoId),
      ];
      if (lineasVigentesAtribuibles.isEmpty) continue;
      final atribucion =
          atribuirAsignacionesHistoricas(asignacionesSinLinea: sinLinea, lineasVigentes: lineasVigentesAtribuibles);
      atribucion.atribuidasPorLinea.forEach((lineaId, extra) {
        asignadosPorLinea[lineaId] = (asignadosPorLinea[lineaId] ?? 0) + extra;
      });
    }

    return [
      for (final linea in lineas)
        if (vigentePorLinea[linea.id] != null)
          (
            servicioId: linea.servicioId,
            lineaComercialId: linea.id,
            puestoNombre: nombrePorPuesto[vigentePorLinea[linea.id]!.puestoId] ?? '',
            requerido: vigentePorLinea[linea.id]!.cantidadElementos,
            cubierto: asignadosPorLinea[linea.id] ?? 0,
          ),
    ];
  }

  @override
  Future<ServicioLineaComercialData?> obtenerLinea(String lineaComercialId) {
    return (_db.select(_db.servicioLineaComercial)..where((t) => t.id.equals(lineaComercialId))).getSingleOrNull();
  }

  @override
  Future<ServicioLineaComercialVigenciaData?> obtenerVigencia(String vigenciaId) {
    return (_db.select(_db.servicioLineaComercialVigencia)..where((t) => t.id.equals(vigenciaId))).getSingleOrNull();
  }

  @override
  Future<List<ServicioLineaComercialVigenciaData>> listarHistorial(String lineaComercialId) {
    return (_db.select(_db.servicioLineaComercialVigencia)
          ..where((t) => t.lineaComercialId.equals(lineaComercialId))
          ..orderBy([(t) => OrderingTerm.asc(t.fechaInicioVigencia)]))
        .get();
  }

  Future<List<ServicioLineaComercialVigenciaData>> _vigenciasActivasDeLinea(String lineaComercialId) {
    return (_db.select(_db.servicioLineaComercialVigencia)
          ..where(
            (t) =>
                t.lineaComercialId.equals(lineaComercialId) & t.cicloVidaRegistro.equals(CicloVidaRegistro.activo.name),
          ))
        .get();
  }

  @override
  Future<ServicioLineaComercialVigenciaData> cambiarVigencia({
    required String lineaComercialId,
    required LineaComercialValidada datos,
    String? observacion,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final existentes = await _vigenciasActivasDeLinea(lineaComercialId);
      final inicioNueva = soloFecha(datos.fechaInicioVigencia);

      // Predecesora: la vigencia `activo` cuyo rango contiene o antecede
      // a la nueva fecha de inicio — a lo más una, por la invariante de
      // no-solapamiento.
      ServicioLineaComercialVigenciaData? predecesora;
      for (final v in existentes) {
        final inicio = soloFecha(v.fechaInicioVigencia);
        final fin = v.fechaFinVigencia == null ? null : soloFecha(v.fechaFinVigencia!);
        if (!inicio.isAfter(inicioNueva) && (fin == null || !fin.isBefore(inicioNueva))) {
          if (predecesora == null || inicio.isAfter(soloFecha(predecesora.fechaInicioVigencia))) {
            predecesora = v;
          }
        }
      }

      if (predecesora != null) {
        await (_db.update(_db.servicioLineaComercialVigencia)..where((t) => t.id.equals(predecesora!.id))).write(
          ServicioLineaComercialVigenciaCompanion(
            fechaFinVigencia: Value(inicioNueva.subtract(const Duration(days: 1))),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }

      // Sucesora: entre las restantes, la de fecha de inicio más
      // próxima después de la nueva.
      ServicioLineaComercialVigenciaData? sucesora;
      for (final v in existentes) {
        if (predecesora != null && v.id == predecesora.id) continue;
        final inicio = soloFecha(v.fechaInicioVigencia);
        if (inicio.isAfter(inicioNueva)) {
          if (sucesora == null || inicio.isBefore(soloFecha(sucesora.fechaInicioVigencia))) {
            sucesora = v;
          }
        }
      }

      final fechaFinNueva =
          sucesora != null ? soloFecha(sucesora.fechaInicioVigencia).subtract(const Duration(days: 1)) : datos.fechaFinVigencia;

      final nueva = await _db.into(_db.servicioLineaComercialVigencia).insertReturning(
            ServicioLineaComercialVigenciaCompanion.insert(
              lineaComercialId: lineaComercialId,
              puestoId: datos.puestoId,
              modalidadTurnoId: datos.modalidadTurnoId,
              cantidadElementos: datos.cantidadElementos,
              precioUnitario: datos.precioUnitario,
              tratamientoIva: datos.tratamientoIva.name,
              descripcion: Value(datos.descripcion),
              fechaInicioVigencia: datos.fechaInicioVigencia,
              fechaFinVigencia: Value(fechaFinNueva),
              observaciones: Value(datos.observaciones),
              sueldoMensualReferenciaPersonal: Value(datos.sueldoMensualReferenciaPersonal),
              bonoMensualReferenciaPersonal: Value(datos.bonoMensualReferenciaPersonal),
            ),
          );
      await _guardarHorario(nueva.id, datos.horario);

      // Abrir una vigencia NUEVA es un hecho de negocio, no una
      // enmienda: la anterior queda intacta, cerrada en su fecha, y
      // este evento guarda las condiciones que empiezan a aplicar.
      // Nunca se registra como corrección.
      final linea = await (_db.select(_db.servicioLineaComercial)
            ..where((t) => t.id.equals(lineaComercialId)))
          .getSingle();
      await registrarEventoServicio(
        _db,
        servicioId: linea.servicioId,
        tipoEvento: TipoEventoServicio.vigenciaComercialAbierta,
        observacion: observacion,
        actorUsuarioId: actorUsuarioId,
        datosRelevantes: {
          'lineaComercialId': lineaComercialId,
          if (predecesora != null) 'vigenciaAnteriorId': predecesora.id,
          ..._condicionesDe(nueva),
        },
      );
      return nueva;
    });
  }

  @override
  Future<ServicioLineaComercialVigenciaData> cerrarVigencia({
    required String vigenciaId,
    required DateTime fechaEfectiva,
    String? motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final anterior =
          await (_db.select(_db.servicioLineaComercialVigencia)..where((t) => t.id.equals(vigenciaId))).getSingle();
      await (_db.update(_db.servicioLineaComercialVigencia)..where((t) => t.id.equals(vigenciaId))).write(
        ServicioLineaComercialVigenciaCompanion(
          fechaFinVigencia: Value(fechaEfectiva),
          updatedAt: Value(DateTime.now()),
        ),
      );
      final cerrada =
          await (_db.select(_db.servicioLineaComercialVigencia)..where((t) => t.id.equals(vigenciaId))).getSingle();

      // Cerrar la línea sin reemplazo termina de cobrar por ella: es
      // un hecho económico propio, distinto de abrir otra vigencia.
      final linea = await (_db.select(_db.servicioLineaComercial)
            ..where((t) => t.id.equals(anterior.lineaComercialId)))
          .getSingle();
      await registrarEventoServicio(
        _db,
        servicioId: linea.servicioId,
        tipoEvento: TipoEventoServicio.lineaComercialCerrada,
        estadoAnterior: (DiffEvento()
              ..anotar('fechaFinVigencia', anterior.fechaFinVigencia, cerrada.fechaFinVigencia))
            .estadoAnteriorJson,
        estadoNuevo: (DiffEvento()
              ..anotar('fechaFinVigencia', anterior.fechaFinVigencia, cerrada.fechaFinVigencia))
            .estadoNuevoJson,
        observacion: motivo,
        actorUsuarioId: actorUsuarioId,
        datosRelevantes: {'lineaComercialId': linea.id, 'vigenciaId': vigenciaId},
      );
      return cerrada;
    });
  }

  @override
  Future<void> cancelarVigenciaProgramada(String vigenciaId, {String? motivo, String? actorUsuarioId}) {
    return _db.transaction(() async {
      final cancelada =
          await (_db.select(_db.servicioLineaComercialVigencia)..where((t) => t.id.equals(vigenciaId))).getSingle();
      final existentes = await _vigenciasActivasDeLinea(cancelada.lineaComercialId);
      final inicioCancelada = soloFecha(cancelada.fechaInicioVigencia);

      ServicioLineaComercialVigenciaData? predecesora;
      for (final v in existentes) {
        if (v.id == cancelada.id) continue;
        final inicio = soloFecha(v.fechaInicioVigencia);
        if (inicio.isBefore(inicioCancelada)) {
          if (predecesora == null || inicio.isAfter(soloFecha(predecesora.fechaInicioVigencia))) {
            predecesora = v;
          }
        }
      }

      if (predecesora != null) {
        await (_db.update(_db.servicioLineaComercialVigencia)..where((t) => t.id.equals(predecesora!.id))).write(
          ServicioLineaComercialVigenciaCompanion(
            fechaFinVigencia: Value(cancelada.fechaFinVigencia),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }

      await (_db.update(_db.servicioLineaComercialVigencia)..where((t) => t.id.equals(vigenciaId))).write(
        ServicioLineaComercialVigenciaCompanion(
          cicloVidaRegistro: Value(CicloVidaRegistro.archivado.name),
          updatedAt: Value(DateTime.now()),
        ),
      );

      // La vigencia cancelada NO se borra: queda archivada y sigue
      // apareciendo en el historial. El evento dice cuál fue y con qué
      // condiciones se había programado.
      final linea = await (_db.select(_db.servicioLineaComercial)
            ..where((t) => t.id.equals(cancelada.lineaComercialId)))
          .getSingle();
      await registrarEventoServicio(
        _db,
        servicioId: linea.servicioId,
        tipoEvento: TipoEventoServicio.vigenciaComercialCancelada,
        observacion: motivo,
        actorUsuarioId: actorUsuarioId,
        datosRelevantes: {
          'lineaComercialId': linea.id,
          if (predecesora != null) 'vigenciaRestauradaId': predecesora.id,
          ..._condicionesDe(cancelada),
        },
      );
    });
  }

  @override
  Future<ServicioLineaComercialVigenciaData> actualizarAnotaciones({
    required String vigenciaId,
    String? descripcion,
    String? observaciones,
  }) async {
    await (_db.update(_db.servicioLineaComercialVigencia)..where((t) => t.id.equals(vigenciaId))).write(
      ServicioLineaComercialVigenciaCompanion(
        descripcion: Value(descripcion),
        observaciones: Value(observaciones),
        updatedAt: Value(DateTime.now()),
      ),
    );
    return (_db.select(_db.servicioLineaComercialVigencia)..where((t) => t.id.equals(vigenciaId))).getSingle();
  }

  @override
  Future<bool> tieneDocumentosGenerados(String vigenciaId) async {
    final documento = await (_db.select(_db.documentoPorEmitirLinea)
          ..where((t) => t.lineaComercialVigenciaId.equals(vigenciaId))
          ..limit(1))
        .getSingleOrNull();
    return documento != null;
  }

  @override
  Future<ServicioLineaComercialVigenciaData> corregirVigencia({
    required String vigenciaId,
    required LineaComercialValidada datos,
    String? motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final antes =
          await (_db.select(_db.servicioLineaComercialVigencia)..where((t) => t.id.equals(vigenciaId))).getSingle();
      await (_db.update(_db.servicioLineaComercialVigencia)..where((t) => t.id.equals(vigenciaId))).write(
      ServicioLineaComercialVigenciaCompanion(
        puestoId: Value(datos.puestoId),
        modalidadTurnoId: Value(datos.modalidadTurnoId),
        cantidadElementos: Value(datos.cantidadElementos),
        precioUnitario: Value(datos.precioUnitario),
        tratamientoIva: Value(datos.tratamientoIva.name),
        descripcion: Value(datos.descripcion),
        fechaInicioVigencia: Value(datos.fechaInicioVigencia),
        fechaFinVigencia: Value(datos.fechaFinVigencia),
        observaciones: Value(datos.observaciones),
        sueldoMensualReferenciaPersonal: Value(datos.sueldoMensualReferenciaPersonal),
        bonoMensualReferenciaPersonal: Value(datos.bonoMensualReferenciaPersonal),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await _guardarHorario(vigenciaId, datos.horario);
      final despues =
          await (_db.select(_db.servicioLineaComercialVigencia)..where((t) => t.id.equals(vigenciaId))).getSingle();

      // Corrección de una vigencia YA EXISTENTE: un dato mal
      // capturado. Aquí sí hay un antes y un después que comparar, y
      // sólo se registran los campos que de verdad cambiaron.
      final diff = _diffCondiciones(antes, despues);
      if (diff.hayCambios) {
        final linea = await (_db.select(_db.servicioLineaComercial)
              ..where((t) => t.id.equals(despues.lineaComercialId)))
            .getSingle();
        await registrarEventoServicio(
          _db,
          servicioId: linea.servicioId,
          tipoEvento: TipoEventoServicio.vigenciaComercialCorregida,
          estadoAnterior: diff.estadoAnteriorJson,
          estadoNuevo: diff.estadoNuevoJson,
          observacion: motivo,
          actorUsuarioId: actorUsuarioId,
          datosRelevantes: {'lineaComercialId': linea.id, 'vigenciaId': vigenciaId},
        );
      }
      return despues;
    });
  }

  /// Eliminación física extraordinaria (Etapa 15) — solo elegible
  /// cuando la línea tiene exactamente una vigencia (nunca pasó por
  /// `cambiarVigencia`) y esa vigencia nunca produjo un
  /// `DocumentoPorEmitirLinea` (la señal real de historia). Borra la
  /// vigencia y su línea en la misma transacción; nunca `CASCADE`.
  @override
  Future<EliminarLineaComercialFisicamenteResultado> eliminarFisicamente({
    required String lineaComercialId,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final linea =
          await (_db.select(_db.servicioLineaComercial)..where((t) => t.id.equals(lineaComercialId))).getSingleOrNull();
      if (linea == null) return EliminarLineaComercialFisicamenteNoExiste();

      final historial = await listarHistorial(lineaComercialId);
      if (historial.length != 1) {
        return EliminarLineaComercialFisicamenteTieneDependencias(
          'Tiene ${historial.length} vigencia(s) registrada(s).',
        );
      }

      final vigencia = historial.single;
      if (await tieneDocumentosGenerados(vigencia.id)) {
        return EliminarLineaComercialFisicamenteTieneDependencias(
          'Ya generó documentos de Agenda — tiene historia real.',
        );
      }

      await _db.into(_db.eliminacionFisicaEvento).insert(
            EliminacionFisicaEventoCompanion.insert(
              tipoEntidad: 'servicioLineaComercial',
              entidadIdOriginal: lineaComercialId,
              fechaHora: DateTime.now(),
              motivo: motivo,
              snapshotJson: jsonEncode({'linea': linea.toJson(), 'vigencia': vigencia.toJson()}),
              actorUsuarioId: Value(actorUsuarioId),
            ),
          );

      // Sin CASCADE: la vigencia antes que la línea (FK `restrict` de
      // `lineaComercialId`).
      await (_db.delete(_db.servicioLineaComercialVigencia)..where((t) => t.id.equals(vigencia.id))).go();
      await (_db.delete(_db.servicioLineaComercial)..where((t) => t.id.equals(lineaComercialId))).go();

      return EliminarLineaComercialFisicamenteExitoso();
    });
  }
}
