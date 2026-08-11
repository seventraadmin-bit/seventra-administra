import 'package:drift/drift.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/inventario/data/tables/asignacion_table.dart' show MotivoCierreAsignacion;
import 'package:riseg_one/features/inventario/domain/repositories/asignacion_repository.dart';
import 'package:riseg_one/features/inventario/domain/repositories/inventario_repository.dart';

import '../../domain/repositories/asignacion_linea_telefonica_repository.dart';
import '../../domain/repositories/linea_telefonica_equipo_repository.dart';

class LineaTelefonicaEquipoRepositoryImpl implements LineaTelefonicaEquipoRepository {
  LineaTelefonicaEquipoRepositoryImpl(
    this._db,
    this._asignacionLineaRepo,
    this._inventarioAsignacionRepo,
    this._inventarioRepo,
  );

  final AppDatabase _db;
  final AsignacionLineaTelefonicaRepository _asignacionLineaRepo;

  /// Repositorio de Inventario, ajeno al dominio — la composición
  /// cruzada vive aquí, mismo criterio que
  /// `PagoNominaRepositoryImpl` componiendo `EgresoRepository` de
  /// Finanzas (ver el doc comment de la interfaz de este repositorio).
  final AsignacionRepository _inventarioAsignacionRepo;
  final InventarioRepository _inventarioRepo;

  Future<LineaTelefonicaEquipoData?> _buscarActualPorLinea(String lineaTelefonicaId) {
    return (_db.select(_db.lineaTelefonicaEquipo)
          ..where((t) => t.lineaTelefonicaId.equals(lineaTelefonicaId) & t.fechaFin.isNull()))
        .getSingleOrNull();
  }

  @override
  Future<LineaTelefonicaEquipoData?> obtenerActualPorLinea(String lineaTelefonicaId) =>
      _buscarActualPorLinea(lineaTelefonicaId);

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
  Future<CustodiaInventarioLineaTelefonica?> obtenerCustodiaInventarioActual(String unidadId) async {
    final activa = await _inventarioAsignacionRepo.obtenerActivaPorUnidad(unidadId);
    if (activa == null) return null;
    return CustodiaInventarioLineaTelefonica(empleadoId: activa.empleadoId, servicioId: activa.servicioId);
  }

  /// Mueve la custodia en Inventario al destino de la línea — camino de
  /// escritura oficial de Inventario (`AsignacionRepository.crear`),
  /// nunca un insert directo a `_db.asignacion`.
  Future<void> _componerAsignacionInventario({
    required String unidadId,
    required String? empleadoId,
    required String? servicioId,
    required DateTime fecha,
    required String observaciones,
  }) async {
    final unidad = await _inventarioRepo.obtenerUnidadPorId(unidadId);
    if (unidad == null) return;
    await _inventarioAsignacionRepo.crear(
      articuloId: unidad.articuloId,
      unidadId: unidadId,
      cantidad: 1,
      empleadoId: empleadoId,
      servicioId: servicioId,
      fechaEntrega: fecha,
      observaciones: observaciones,
    );
  }

  /// Cierra la custodia en Inventario **solo si** la asignación activa
  /// de la unidad todavía coincide con el destino esperado — guardia de
  /// divergencia: nunca pisa una reasignación hecha directo en
  /// Inventario.
  Future<void> _liberarAsignacionInventarioSiCoincide({
    required String unidadId,
    required String? empleadoIdEsperado,
    required String? servicioIdEsperado,
    required DateTime fecha,
    required String observaciones,
  }) async {
    final activa = await _inventarioAsignacionRepo.obtenerActivaPorUnidad(unidadId);
    if (activa == null) return;
    final coincide = activa.empleadoId == empleadoIdEsperado && activa.servicioId == servicioIdEsperado;
    if (!coincide) return;
    await _inventarioAsignacionRepo.cerrar(
      asignacionId: activa.id,
      motivo: MotivoCierreAsignacion.otro.name,
      fechaCierre: fecha,
      observacionesCierre: observaciones,
    );
  }

  @override
  Future<LineaTelefonicaEquipoData> asociar({
    required String lineaTelefonicaId,
    required String unidadId,
    required DateTime fechaInicio,
    String? observaciones,
    bool sincronizarInventario = true,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final equipo = await _db.into(_db.lineaTelefonicaEquipo).insertReturning(
            LineaTelefonicaEquipoCompanion.insert(
              lineaTelefonicaId: lineaTelefonicaId,
              unidadId: unidadId,
              fechaInicio: fechaInicio,
              observaciones: Value(observaciones),
            ),
          );

      if (sincronizarInventario) {
        final asignacionLinea = await _asignacionLineaRepo.obtenerActivaPorLinea(lineaTelefonicaId);
        if (asignacionLinea != null) {
          await _componerAsignacionInventario(
            unidadId: unidadId,
            empleadoId: asignacionLinea.empleadoId,
            servicioId: asignacionLinea.servicioId,
            fecha: fechaInicio,
            observaciones: 'Asociado como equipo de una línea telefónica.',
          );
        }
      }

      return equipo;
    });
  }

  @override
  Future<void> retirar({
    required String lineaTelefonicaId,
    required DateTime fechaFin,
    bool sincronizarInventario = true,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final actual = await _buscarActualPorLinea(lineaTelefonicaId);
      if (actual == null) return;

      await (_db.update(_db.lineaTelefonicaEquipo)..where((t) => t.id.equals(actual.id))).write(
        LineaTelefonicaEquipoCompanion(fechaFin: Value(fechaFin), updatedAt: Value(DateTime.now())),
      );

      if (sincronizarInventario) {
        final asignacionLinea = await _asignacionLineaRepo.obtenerActivaPorLinea(lineaTelefonicaId);
        await _liberarAsignacionInventarioSiCoincide(
          unidadId: actual.unidadId,
          empleadoIdEsperado: asignacionLinea?.empleadoId,
          servicioIdEsperado: asignacionLinea?.servicioId,
          fecha: fechaFin,
          observaciones: 'Liberado al retirar el equipo de una línea telefónica.',
        );
      }
    });
  }

  @override
  Future<LineaTelefonicaEquipoData> cambiar({
    required String lineaTelefonicaId,
    required String nuevaUnidadId,
    required DateTime fecha,
    String? observaciones,
    bool sincronizarInventario = true,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final actual = await _buscarActualPorLinea(lineaTelefonicaId);
      final asignacionLinea = await _asignacionLineaRepo.obtenerActivaPorLinea(lineaTelefonicaId);

      if (actual != null) {
        await (_db.update(_db.lineaTelefonicaEquipo)..where((t) => t.id.equals(actual.id))).write(
          LineaTelefonicaEquipoCompanion(fechaFin: Value(fecha), updatedAt: Value(DateTime.now())),
        );
        if (sincronizarInventario) {
          await _liberarAsignacionInventarioSiCoincide(
            unidadId: actual.unidadId,
            empleadoIdEsperado: asignacionLinea?.empleadoId,
            servicioIdEsperado: asignacionLinea?.servicioId,
            fecha: fecha,
            observaciones: 'Liberado al cambiar el equipo de una línea telefónica.',
          );
        }
      }

      final nuevo = await _db.into(_db.lineaTelefonicaEquipo).insertReturning(
            LineaTelefonicaEquipoCompanion.insert(
              lineaTelefonicaId: lineaTelefonicaId,
              unidadId: nuevaUnidadId,
              fechaInicio: fecha,
              observaciones: Value(observaciones),
            ),
          );

      if (sincronizarInventario && asignacionLinea != null) {
        await _componerAsignacionInventario(
          unidadId: nuevaUnidadId,
          empleadoId: asignacionLinea.empleadoId,
          servicioId: asignacionLinea.servicioId,
          fecha: fecha,
          observaciones: 'Asociado como equipo de una línea telefónica (reemplazo).',
        );
      }

      return nuevo;
    });
  }

  @override
  Future<void> cerrarPorBajaLinea({required String lineaTelefonicaId, required DateTime fecha}) {
    return retirar(lineaTelefonicaId: lineaTelefonicaId, fechaFin: fecha, sincronizarInventario: true);
  }

  @override
  Future<void> sincronizarConAsignacionVigente({required String lineaTelefonicaId, required DateTime fecha}) {
    return _db.transaction(() async {
      final equipo = await _buscarActualPorLinea(lineaTelefonicaId);
      if (equipo == null) return;

      final destino = await _asignacionLineaRepo.obtenerActivaPorLinea(lineaTelefonicaId);
      final activaInventario = await _inventarioAsignacionRepo.obtenerActivaPorUnidad(equipo.unidadId);

      final coincide = activaInventario != null &&
          activaInventario.empleadoId == destino?.empleadoId &&
          activaInventario.servicioId == destino?.servicioId;

      if (activaInventario != null && !coincide) {
        await _inventarioAsignacionRepo.cerrar(
          asignacionId: activaInventario.id,
          motivo: MotivoCierreAsignacion.otro.name,
          fechaCierre: fecha,
          observacionesCierre: 'Reasignado por sincronización con una línea telefónica.',
        );
      }

      if (destino != null && !coincide) {
        await _componerAsignacionInventario(
          unidadId: equipo.unidadId,
          empleadoId: destino.empleadoId,
          servicioId: destino.servicioId,
          fecha: fecha,
          observaciones: 'Sincronizado con la asignación de una línea telefónica.',
        );
      }
    });
  }
}
