import 'dart:convert';

import 'package:drift/drift.dart';

import 'package:riseg_one/core/database/app_database.dart';

import '../../domain/repositories/asignacion_linea_telefonica_repository.dart';
import '../tables/linea_telefonica_table.dart';
import '../../domain/repositories/linea_telefonica_equipo_repository.dart';
import '../../domain/repositories/linea_telefonica_repository.dart';
import '../../domain/usecases/eliminar_linea_telefonica_fisicamente_usecase.dart';

class LineaTelefonicaRepositoryImpl implements LineaTelefonicaRepository {
  LineaTelefonicaRepositoryImpl(this._db, this._asignacionRepository, this._equipoRepository);

  final AppDatabase _db;

  /// Repositorio compone repositorio (Etapa 9B) — mismo criterio que
  /// `VehiculoRepositoryImpl` con `AsignacionVehiculoRepository`:
  /// `darDeBaja` necesita cerrar la asignación y el equipo vigentes de
  /// la línea (si existen) en la misma transacción que la baja misma.
  /// `_equipoRepository.cerrarPorBajaLinea` a su vez libera la custodia
  /// en Inventario cuando coincide (ver su doc comment) — nunca da de
  /// baja ni toca el teléfono físico en sí.
  final AsignacionLineaTelefonicaRepository _asignacionRepository;
  final LineaTelefonicaEquipoRepository _equipoRepository;

  @override
  Future<LineaTelefonicaData?> obtenerPorId(String id) {
    return (_db.select(_db.lineaTelefonica)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  @override
  Future<LineaTelefonicaData?> obtenerPorNumero(String numero) {
    return (_db.select(_db.lineaTelefonica)..where((t) => t.numero.equals(numero))).getSingleOrNull();
  }

  @override
  Future<List<LineaTelefonicaData>> listar({bool soloActivos = true}) {
    final query = _db.select(_db.lineaTelefonica);
    if (soloActivos) query.where((t) => t.cicloVidaRegistro.equals('activo'));
    query.orderBy([(t) => OrderingTerm.asc(t.codigo)]);
    return query.get();
  }

  @override
  Future<LineaTelefonicaData> crear({
    required String codigo,
    String? numero,
    required String operador,
    String? operadorOtroNombre,
    required String modalidadSim,
    String? iccid,
    DateTime? fechaActivacion,
    String? observaciones,
  }) {
    return _db.into(_db.lineaTelefonica).insertReturning(
          LineaTelefonicaCompanion.insert(
            codigo: codigo,
            numero: Value(numero),
            operador: operador,
            operadorOtroNombre: Value(operadorOtroNombre),
            modalidadSim: modalidadSim,
            iccid: Value(iccid),
            fechaActivacion: Value(fechaActivacion),
            observaciones: Value(observaciones),
          ),
        );
  }

  @override
  Future<void> registrarEvento({
    required String lineaTelefonicaId,
    required TipoEventoLineaTelefonica tipoEvento,
    String? recargaId,
    String? observacion,
    String? estadoAnterior,
    String? estadoNuevo,
    String? actorUsuarioId,
  }) async {
    await _db.into(_db.lineaTelefonicaEvento).insert(
          LineaTelefonicaEventoCompanion.insert(
            lineaTelefonicaId: lineaTelefonicaId,
            recargaId: Value(recargaId),
            fechaHora: DateTime.now(),
            tipoEvento: tipoEvento.name,
            observacion: Value(observacion),
            estadoAnterior: Value(estadoAnterior),
            estadoNuevo: Value(estadoNuevo),
            actorUsuarioId: Value(actorUsuarioId),
          ),
        );
  }

  @override
  Future<List<LineaTelefonicaEventoData>> listarEventos(String lineaTelefonicaId) {
    return (_db.select(_db.lineaTelefonicaEvento)
          ..where((t) => t.lineaTelefonicaId.equals(lineaTelefonicaId))
          ..orderBy([(t) => OrderingTerm.desc(t.fechaHora), (t) => OrderingTerm.desc(t.id)]))
        .get();
  }

  @override
  Future<LineaTelefonicaData> corregir({
    required String lineaTelefonicaId,
    String? numero,
    String? operador,
    String? operadorOtroNombre,
    String? modalidadSim,
    String? iccid,
    DateTime? fechaActivacion,
    String? observaciones,
    bool limpiarNumero = false,
    bool limpiarOperadorOtroNombre = false,
    bool limpiarIccid = false,
    bool limpiarFechaActivacion = false,
    bool limpiarObservaciones = false,
  }) {
    return _db.transaction(() async {
      await (_db.update(_db.lineaTelefonica)..where((t) => t.id.equals(lineaTelefonicaId))).write(
        LineaTelefonicaCompanion(
          numero: limpiarNumero ? const Value(null) : (numero == null ? const Value.absent() : Value(numero)),
          operador: operador == null ? const Value.absent() : Value(operador),
          operadorOtroNombre: limpiarOperadorOtroNombre
              ? const Value(null)
              : (operadorOtroNombre == null ? const Value.absent() : Value(operadorOtroNombre)),
          modalidadSim: modalidadSim == null ? const Value.absent() : Value(modalidadSim),
          iccid: limpiarIccid ? const Value(null) : (iccid == null ? const Value.absent() : Value(iccid)),
          fechaActivacion: limpiarFechaActivacion
              ? const Value(null)
              : (fechaActivacion == null ? const Value.absent() : Value(fechaActivacion)),
          observaciones: limpiarObservaciones
              ? const Value(null)
              : (observaciones == null ? const Value.absent() : Value(observaciones)),
          updatedAt: Value(DateTime.now()),
        ),
      );
      return (_db.select(_db.lineaTelefonica)..where((t) => t.id.equals(lineaTelefonicaId))).getSingle();
    });
  }

  @override
  Future<LineaTelefonicaData> cambiarEstatus({required String lineaTelefonicaId, required String estatus}) {
    return _db.transaction(() async {
      await (_db.update(_db.lineaTelefonica)..where((t) => t.id.equals(lineaTelefonicaId))).write(
        LineaTelefonicaCompanion(estatus: Value(estatus), updatedAt: Value(DateTime.now())),
      );
      return (_db.select(_db.lineaTelefonica)..where((t) => t.id.equals(lineaTelefonicaId))).getSingle();
    });
  }

  @override
  Future<LineaTelefonicaData> darDeBaja({
    required String lineaTelefonicaId,
    required DateTime fechaBaja,
    required String motivoBaja,
    String? observacionesBaja,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final anterior = await (_db.select(_db.lineaTelefonica)..where((t) => t.id.equals(lineaTelefonicaId))).getSingle();
      await _equipoRepository.cerrarPorBajaLinea(lineaTelefonicaId: lineaTelefonicaId, fecha: fechaBaja);
      await _asignacionRepository.cerrarPorBajaLinea(lineaTelefonicaId: lineaTelefonicaId, fecha: fechaBaja);
      await (_db.update(_db.lineaTelefonica)..where((t) => t.id.equals(lineaTelefonicaId))).write(
        LineaTelefonicaCompanion(
          estatus: const Value('baja'),
          fechaBaja: Value(fechaBaja),
          motivoBaja: Value(motivoBaja),
          observacionesBaja: Value(observacionesBaja),
          updatedAt: Value(DateTime.now()),
        ),
      );
      // El hecho "esta línea se dio de baja" es propio de la LÍNEA y no
      // lo expresa ninguna otra fila: la asignación cerrada dice que
      // terminó una asignación, no que la línea murió. Por eso sí lleva
      // evento — a diferencia del cierre de la asignación, que la
      // propia fila ya expresa con su `motivoTermino`.
      await registrarEvento(
        lineaTelefonicaId: lineaTelefonicaId,
        tipoEvento: TipoEventoLineaTelefonica.dadaDeBaja,
        observacion: observacionesBaja,
        estadoAnterior: anterior.estatus,
        estadoNuevo: 'baja',
        actorUsuarioId: actorUsuarioId,
      );

      return (_db.select(_db.lineaTelefonica)..where((t) => t.id.equals(lineaTelefonicaId))).getSingle();
    });
  }

  /// Eliminación física extraordinaria (Etapa 11D) — condiciones exactas
  /// acordadas con Marlon: elegible solo si la línea nunca tuvo
  /// `AsignacionLineaTelefonica`, `LineaTelefonicaEquipo` ni
  /// `RecargaLineaTelefonica`. Sin adjunto propio que revisar — el
  /// comprobante de una recarga cuelga de `RecargaLineaTelefonica`, ya
  /// cubierto por ese mismo chequeo. Todo — validación, snapshot,
  /// registro de auditoría y `DELETE` — ocurre en una sola transacción;
  /// nunca `CASCADE` sobre ninguna de esas tablas.
  @override
  Future<EliminarLineaTelefonicaFisicamenteResultado> eliminarFisicamente({
    required String lineaTelefonicaId,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final linea =
          await (_db.select(_db.lineaTelefonica)..where((t) => t.id.equals(lineaTelefonicaId))).getSingleOrNull();
      if (linea == null) return EliminarLineaTelefonicaFisicamenteNoExiste();

      final asignaciones = await (_db.select(_db.asignacionLineaTelefonica)
            ..where((t) => t.lineaTelefonicaId.equals(lineaTelefonicaId)))
          .get();
      if (asignaciones.isNotEmpty) {
        return EliminarLineaTelefonicaFisicamenteTieneDependencias(
          'Tiene ${asignaciones.length} asignación(es) registrada(s).',
        );
      }

      final equipos = await (_db.select(_db.lineaTelefonicaEquipo)
            ..where((t) => t.lineaTelefonicaId.equals(lineaTelefonicaId)))
          .get();
      if (equipos.isNotEmpty) {
        return EliminarLineaTelefonicaFisicamenteTieneDependencias(
          'Tiene ${equipos.length} equipo(s) asociado(s) registrado(s).',
        );
      }

      final recargas = await (_db.select(_db.recargaLineaTelefonica)
            ..where((t) => t.lineaTelefonicaId.equals(lineaTelefonicaId)))
          .get();
      if (recargas.isNotEmpty) {
        return EliminarLineaTelefonicaFisicamenteTieneDependencias(
          'Tiene ${recargas.length} recarga(s) registrada(s).',
        );
      }

      await _db.into(_db.eliminacionFisicaEvento).insert(
            EliminacionFisicaEventoCompanion.insert(
              tipoEntidad: 'lineaTelefonica',
              entidadIdOriginal: lineaTelefonicaId,
              fechaHora: DateTime.now(),
              motivo: motivo,
              snapshotJson: jsonEncode(linea.toJson()),
              actorUsuarioId: Value(actorUsuarioId),
            ),
          );
      await (_db.delete(_db.lineaTelefonica)..where((t) => t.id.equals(lineaTelefonicaId))).go();

      return EliminarLineaTelefonicaFisicamenteExitoso();
    });
  }
}
