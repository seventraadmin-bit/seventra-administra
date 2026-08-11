import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:riseg_one/core/database/app_database.dart';

import '../../domain/repositories/recarga_linea_telefonica_repository.dart';

class RecargaLineaTelefonicaRepositoryImpl implements RecargaLineaTelefonicaRepository {
  RecargaLineaTelefonicaRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<RecargaLineaTelefonicaData?> obtenerPorId(String recargaLineaTelefonicaId) {
    return (_db.select(_db.recargaLineaTelefonica)..where((t) => t.id.equals(recargaLineaTelefonicaId))).getSingleOrNull();
  }

  @override
  Future<List<RecargaLineaTelefonicaData>> listarPorLinea(String lineaTelefonicaId) {
    return (_db.select(_db.recargaLineaTelefonica)
          ..where((t) => t.lineaTelefonicaId.equals(lineaTelefonicaId))
          ..orderBy([(t) => OrderingTerm.desc(t.fecha)]))
        .get();
  }

  @override
  Future<int> totalPorLinea(String lineaTelefonicaId) async {
    final recargas = await listarPorLinea(lineaTelefonicaId);
    return recargas.fold<int>(0, (suma, r) => suma + r.importe);
  }

  @override
  Future<Map<String, RecargaLineaTelefonicaData>> obtenerUltimasPorTodasLasLineas() async {
    final todas = await (_db.select(_db.recargaLineaTelefonica)..orderBy([(t) => OrderingTerm.desc(t.fecha)])).get();
    final ultimaPorLinea = <String, RecargaLineaTelefonicaData>{};
    for (final r in todas) {
      ultimaPorLinea.putIfAbsent(r.lineaTelefonicaId, () => r);
    }
    return ultimaPorLinea;
  }

  Future<List<AsignacionLineaTelefonicaData>> _asignacionesTodas() {
    return _db.select(_db.asignacionLineaTelefonica).get();
  }

  /// Entre las asignaciones vigentes en la fecha de [recarga] para su
  /// línea, la más reciente por `fechaInicio` — desempate para el día
  /// exacto en que una asignación se cierra y otra se abre a la vez
  /// (mismo día en ambos extremos, ver `AsignacionLineaTelefonicaRepositoryImpl.cambiarResponsable`).
  AsignacionLineaTelefonicaData? _resolverDestino(
    RecargaLineaTelefonicaData recarga,
    List<AsignacionLineaTelefonicaData> asignaciones,
  ) {
    final candidatas = asignaciones.where(
      (a) =>
          a.lineaTelefonicaId == recarga.lineaTelefonicaId &&
          !a.fechaInicio.isAfter(recarga.fecha) &&
          (a.fechaTermino == null || !a.fechaTermino!.isBefore(recarga.fecha)),
    );
    if (candidatas.isEmpty) return null;
    return candidatas.reduce((a, b) => a.fechaInicio.isAfter(b.fechaInicio) ? a : b);
  }

  @override
  Future<DestinoHistoricoRecarga?> obtenerDestinoHistorico(String recargaLineaTelefonicaId) async {
    final recarga = await obtenerPorId(recargaLineaTelefonicaId);
    if (recarga == null) return null;
    final asignaciones = await _asignacionesTodas();
    final destino = _resolverDestino(recarga, asignaciones);
    if (destino == null) return null;
    return DestinoHistoricoRecarga(empleadoId: destino.empleadoId, servicioId: destino.servicioId);
  }

  Future<List<RecargaLineaTelefonicaData>> _listarConRango({DateTime? desde, DateTime? hasta}) {
    final query = _db.select(_db.recargaLineaTelefonica);
    if (desde != null) query.where((t) => t.fecha.isBiggerOrEqualValue(desde));
    if (hasta != null) query.where((t) => t.fecha.isSmallerOrEqualValue(hasta));
    return query.get();
  }

  @override
  Future<int> totalPorEmpleado(String empleadoId, {DateTime? desde, DateTime? hasta}) async {
    final recargas = await _listarConRango(desde: desde, hasta: hasta);
    final asignaciones = await _asignacionesTodas();
    var total = 0;
    for (final r in recargas) {
      final destino = _resolverDestino(r, asignaciones);
      if (destino?.empleadoId == empleadoId) total += r.importe;
    }
    return total;
  }

  @override
  Future<int> totalPorServicio(String servicioId, {DateTime? desde, DateTime? hasta}) async {
    final recargas = await _listarConRango(desde: desde, hasta: hasta);
    final asignaciones = await _asignacionesTodas();
    var total = 0;
    for (final r in recargas) {
      final destino = _resolverDestino(r, asignaciones);
      if (destino?.servicioId == servicioId) total += r.importe;
    }
    return total;
  }

  @override
  Future<int> totalPorRango({DateTime? desde, DateTime? hasta}) async {
    final recargas = await _listarConRango(desde: desde, hasta: hasta);
    return recargas.fold<int>(0, (suma, r) => suma + r.importe);
  }

  @override
  Future<RecargaLineaTelefonicaData> registrar({
    required String lineaTelefonicaId,
    required DateTime fecha,
    required int importe,
    String? observaciones,
  }) {
    return _db.into(_db.recargaLineaTelefonica).insertReturning(
          RecargaLineaTelefonicaCompanion.insert(
            lineaTelefonicaId: lineaTelefonicaId,
            fecha: fecha,
            importe: importe,
            observaciones: Value(observaciones),
          ),
        );
  }

  @override
  Future<AttachmentData> adjuntarComprobante({
    required String recargaLineaTelefonicaId,
    required String originalFileName,
    required String storedFileName,
    required String path,
    required String mimeType,
    required int sizeBytes,
  }) {
    return _db.transaction(() async {
      final adjunto = await _db.into(_db.attachment).insertReturning(
            AttachmentCompanion.insert(
              id: const Uuid().v4(),
              originalFileName: originalFileName,
              storedFileName: storedFileName,
              path: path,
              mimeType: mimeType,
              sizeBytes: sizeBytes,
            ),
          );
      await _db.into(_db.recargaLineaTelefonicaAttachment).insert(
            RecargaLineaTelefonicaAttachmentCompanion.insert(
              attachmentId: adjunto.id,
              recargaLineaTelefonicaId: recargaLineaTelefonicaId,
            ),
          );
      return adjunto;
    });
  }
}
