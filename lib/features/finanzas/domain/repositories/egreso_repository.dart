import 'package:riseg_one/core/database/app_database.dart';

/// Dinero pagado por RISEG (Etapa 4K.1) — 100% captura manual en esta
/// etapa, sin ninguna fuente automática (Nómina/Compras no existen
/// todavía).
abstract interface class EgresoRepository {
  Future<EgresoData?> obtenerPorId(String id);

  Future<List<EgresoData>> listar({
    String? estatus,
    String? categoriaFinancieraId,
    String? servicioId,
    String? sucursalId,
    String? areaId,
    DateTime? rangoInicio,
    DateTime? rangoFin,
  });

  Future<List<EgresoEventoData>> listarEventos(String egresoId);

  Future<EgresoData> crear({
    required String folioEgreso,
    required int monto,
    required DateTime fecha,
    String? categoriaFinancieraId,
    String? servicioId,
    String? sucursalId,
    String? areaId,
    String? cuentaCaja,
    required String formaPago,
    String? beneficiario,
    required String concepto,
    String? observaciones,
    String? actorUsuarioId,
  });

  /// Corrige metadatos administrativos — nunca `monto`.
  Future<EgresoData> corregir({
    required String egresoId,
    DateTime? fecha,
    String? categoriaFinancieraId,
    String? servicioId,
    String? sucursalId,
    String? areaId,
    String? cuentaCaja,
    String? formaPago,
    String? beneficiario,
    String? concepto,
    String? observaciones,
    required String motivo,
    String? actorUsuarioId,
  });

  Future<EgresoData> cancelar({
    required String egresoId,
    required String motivo,
    String? actorUsuarioId,
  });

  Future<AttachmentData> adjuntarComprobante({
    required String egresoId,
    required String originalFileName,
    required String storedFileName,
    required String path,
    required String mimeType,
    required int sizeBytes,
    String? actorUsuarioId,
  });

  /// Suma de `monto` de Egresos `registrado` en el rango dado —
  /// consulta base para reportes (Resolución 5 de Marlon).
  Future<int> totalEgresos({DateTime? rangoInicio, DateTime? rangoFin});

  /// Suma de `monto` de Egresos `registrado` en el rango, agrupada por
  /// `categoriaFinancieraId` — Etapa 12A (Reportes). La llave `null`
  /// agrupa los Egresos sin categoría asignada.
  Future<Map<String?, int>> totalPorCategoria({DateTime? rangoInicio, DateTime? rangoFin});
}
