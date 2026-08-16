import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';
import 'package:riseg_one/core/utils/clock.dart';

import '../../domain/repositories/servicio_comercial_repository.dart';
import '../../domain/shared/horario_input.dart';
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

  @override
  Future<({ServicioLineaComercialData linea, ServicioLineaComercialVigenciaData vigencia})> crearLinea({
    required String servicioId,
    required LineaComercialValidada datos,
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
    for (final linea in lineas) {
      final vigenciasActivas = await _vigenciasActivasDeLinea(linea.id);

      final (:vigente, :programadas) = clasificarVigencias(vigenciasActivas, hoy);
      final vigenciaParaNombres = vigente ?? (programadas.isEmpty ? null : programadas.first);

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

    return resultado;
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
      return nueva;
    });
  }

  @override
  Future<ServicioLineaComercialVigenciaData> cerrarVigencia({
    required String vigenciaId,
    required DateTime fechaEfectiva,
  }) async {
    await (_db.update(_db.servicioLineaComercialVigencia)..where((t) => t.id.equals(vigenciaId))).write(
      ServicioLineaComercialVigenciaCompanion(
        fechaFinVigencia: Value(fechaEfectiva),
        updatedAt: Value(DateTime.now()),
      ),
    );
    return (_db.select(_db.servicioLineaComercialVigencia)..where((t) => t.id.equals(vigenciaId))).getSingle();
  }

  @override
  Future<void> cancelarVigenciaProgramada(String vigenciaId) {
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
  }) async {
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
    return (_db.select(_db.servicioLineaComercialVigencia)..where((t) => t.id.equals(vigenciaId))).getSingle();
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
