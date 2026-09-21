import 'package:drift/drift.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/inventario/domain/repositories/asignacion_repository.dart';

import '../../domain/repositories/asignacion_linea_telefonica_repository.dart';
import '../../domain/repositories/linea_telefonica_equipo_repository.dart';

/// Asociación Línea ↔ Equipo, en el tiempo.
///
/// **Sólo LEE Inventario.** Hasta la Rebanada 1 de Telefonía este
/// repositorio también escribía: creaba y cerraba `Asignacion` de
/// Inventario para "sincronizar" la custodia con el destino de la
/// línea. Se retiró en la Rebanada 2 por dos razones: le daba a
/// Telefonía autoridad sobre la custodia física del aparato —que
/// pertenece a Inventario— y escribía por debajo de
/// `CrearAsignacionUseCase`/`CerrarAsignacionUseCase`, sin sus
/// validaciones ni sus permisos.
///
/// Hoy la dirección es la contraria: cuando Inventario mueve la
/// custodia, la asignación de la línea la sigue (ver
/// `LineaTelefonicaDeUnidad`). Asociar, cambiar o retirar un equipo
/// nunca toca la custodia.
class LineaTelefonicaEquipoRepositoryImpl implements LineaTelefonicaEquipoRepository {
  LineaTelefonicaEquipoRepositoryImpl(this._db, this._asignacionLineaRepo, this._inventarioAsignacionRepo);

  final AppDatabase _db;

  /// Dependencia interna de Telefonía — la usa `asociar`/`cambiar` para
  /// que alinear la línea con la custodia vigente del aparato ocurra en
  /// la MISMA transacción que la asociación.
  final AsignacionLineaTelefonicaRepository _asignacionLineaRepo;

  /// Sólo para consultar la custodia vigente de una unidad. Nunca para
  /// escribirla.
  final AsignacionRepository _inventarioAsignacionRepo;

  Future<LineaTelefonicaEquipoData?> _buscarActualPorLinea(String lineaTelefonicaId) {
    return (_db.select(_db.lineaTelefonicaEquipo)
          ..where((t) => t.lineaTelefonicaId.equals(lineaTelefonicaId) & t.fechaFin.isNull()))
        .getSingleOrNull();
  }

  @override
  Future<LineaTelefonicaEquipoData?> obtenerActualPorLinea(String lineaTelefonicaId) =>
      _buscarActualPorLinea(lineaTelefonicaId);

  @override
  Future<Map<String, LineaTelefonicaEquipoData>> obtenerActualesPorTodasLasLineas() async {
    final filas = await (_db.select(_db.lineaTelefonicaEquipo)..where((t) => t.fechaFin.isNull())).get();
    return {for (final fila in filas) fila.lineaTelefonicaId: fila};
  }

  @override
  Future<List<LineaTelefonicaEquipoData>> listarPorLinea(String lineaTelefonicaId) {
    return (_db.select(_db.lineaTelefonicaEquipo)
          ..where((t) => t.lineaTelefonicaId.equals(lineaTelefonicaId))
          ..orderBy([(t) => OrderingTerm.desc(t.fechaInicio)]))
        .get();
  }

  @override
  Future<LineaTelefonicaEquipoData?> obtenerActualPorUnidad(String unidadId) {
    return (_db.select(_db.lineaTelefonicaEquipo)
          ..where((t) => t.unidadId.equals(unidadId) & t.fechaFin.isNull()))
        .getSingleOrNull();
  }

  @override
  Future<List<LineaTelefonicaEquipoData>> listarPorUnidad(String unidadId) {
    return (_db.select(_db.lineaTelefonicaEquipo)
          ..where((t) => t.unidadId.equals(unidadId))
          ..orderBy([(t) => OrderingTerm.desc(t.fechaInicio)]))
        .get();
  }

  @override
  Future<CustodiaInventarioLineaTelefonica?> obtenerCustodiaInventarioActual(String unidadId) async {
    final activa = await _inventarioAsignacionRepo.obtenerActivaPorUnidad(unidadId);
    if (activa == null) return null;
    return CustodiaInventarioLineaTelefonica(
      empleadoId: activa.empleadoId,
      servicioId: activa.servicioId,
      pendienteRecuperacionDesde: activa.pendienteRecuperacionDesde,
    );
  }

  @override
  Future<Map<String, CustodiaInventarioLineaTelefonica>> obtenerCustodiasInventarioActuales(
    Iterable<String> unidadIds,
  ) async {
    final ids = unidadIds.toSet().toList();
    if (ids.isEmpty) return const {};
    // Una sola consulta para todas las unidades — un listado nunca debe
    // resolver la custodia fila por fila.
    final activas = await _inventarioAsignacionRepo.listarActivasPorUnidades(ids);
    return {
      for (final a in activas)
        a.unidadId!: CustodiaInventarioLineaTelefonica(
          empleadoId: a.empleadoId,
          servicioId: a.servicioId,
          pendienteRecuperacionDesde: a.pendienteRecuperacionDesde,
        ),
    };
  }

  @override
  Future<LineaTelefonicaEquipoData> asociar({
    required String lineaTelefonicaId,
    required String unidadId,
    required DateTime fechaInicio,
    String? observaciones,
    String? alinearLineaConEmpleadoId,
    String? alinearLineaConServicioId,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final equipo = await _db.into(_db.lineaTelefonicaEquipo).insertReturning(
            LineaTelefonicaEquipoCompanion.insert(
              lineaTelefonicaId: lineaTelefonicaId,
              unidadId: unidadId,
              fechaInicio: fechaInicio,
              observaciones: Value(observaciones),
              actorUsuarioId: Value(actorUsuarioId),
            ),
          );

      await _alinearLinea(
        lineaTelefonicaId: lineaTelefonicaId,
        empleadoId: alinearLineaConEmpleadoId,
        servicioId: alinearLineaConServicioId,
        fecha: fechaInicio,
        actorUsuarioId: actorUsuarioId,
      );

      return equipo;
    });
  }

  /// La línea toma el destino que YA tiene el aparato en Inventario.
  /// Nunca al revés: aquí no se escribe una sola fila de Inventario.
  Future<void> _alinearLinea({
    required String lineaTelefonicaId,
    required String? empleadoId,
    required String? servicioId,
    required DateTime fecha,
    String? actorUsuarioId,
  }) async {
    if (empleadoId == null && servicioId == null) return;
    if (await _asignacionLineaRepo.obtenerActivaPorLinea(lineaTelefonicaId) != null) return;
    await _asignacionLineaRepo.crear(
      lineaTelefonicaId: lineaTelefonicaId,
      empleadoId: empleadoId,
      servicioId: servicioId,
      fechaInicio: fecha,
      observaciones: 'Alineada con la custodia del equipo en Inventario.',
      actorUsuarioId: actorUsuarioId,
    );
  }

  @override
  Future<void> retirar({
    required String lineaTelefonicaId,
    required DateTime fechaFin,
    String? actorUsuarioId,
  }) async {
    final actual = await _buscarActualPorLinea(lineaTelefonicaId);
    if (actual == null) return;

    // Desvinculación telefónica y nada más: el aparato sigue donde
    // Inventario diga que está.
    await (_db.update(_db.lineaTelefonicaEquipo)..where((t) => t.id.equals(actual.id))).write(
      LineaTelefonicaEquipoCompanion(
        fechaFin: Value(fechaFin),
        updatedAt: Value(DateTime.now()),
        actorUsuarioId: Value(actorUsuarioId),
      ),
    );
  }

  @override
  Future<LineaTelefonicaEquipoData> cambiar({
    required String lineaTelefonicaId,
    required String nuevaUnidadId,
    required DateTime fecha,
    String? observaciones,
    String? alinearLineaConEmpleadoId,
    String? alinearLineaConServicioId,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final actual = await _buscarActualPorLinea(lineaTelefonicaId);

      if (actual != null) {
        await (_db.update(_db.lineaTelefonicaEquipo)..where((t) => t.id.equals(actual.id))).write(
          LineaTelefonicaEquipoCompanion(
            fechaFin: Value(fecha),
            updatedAt: Value(DateTime.now()),
            actorUsuarioId: Value(actorUsuarioId),
          ),
        );
      }

      final nuevo = await _db.into(_db.lineaTelefonicaEquipo).insertReturning(
            LineaTelefonicaEquipoCompanion.insert(
              lineaTelefonicaId: lineaTelefonicaId,
              unidadId: nuevaUnidadId,
              fechaInicio: fecha,
              observaciones: Value(observaciones),
              actorUsuarioId: Value(actorUsuarioId),
            ),
          );

      await _alinearLinea(
        lineaTelefonicaId: lineaTelefonicaId,
        empleadoId: alinearLineaConEmpleadoId,
        servicioId: alinearLineaConServicioId,
        fecha: fecha,
        actorUsuarioId: actorUsuarioId,
      );

      return nuevo;
    });
  }

  @override
  Future<void> cerrarPorBajaLinea({required String lineaTelefonicaId, required DateTime fecha}) {
    return retirar(lineaTelefonicaId: lineaTelefonicaId, fechaFin: fecha);
  }
}
