import 'package:riseg_one/core/database/app_database.dart';

/// Documentos administrativos de un Vehículo (Etapa 8C) — ver el doc
/// comment de `VehiculoDocumento` para el criterio de diseño completo
/// (renovación = fila nueva, nunca edición).
abstract interface class VehiculoDocumentoRepository {
  Future<VehiculoDocumentoData?> obtenerPorId(String vehiculoDocumentoId);

  /// Historial completo de este Vehículo (todos los tipos, todas las
  /// renovaciones), orden descendente por `fechaEmision` (o
  /// `createdAt` cuando `fechaEmision` es nula) — el llamador agrupa
  /// por `tipo` para distinguir "el vigente" (primero de cada grupo)
  /// del histórico, sin una segunda consulta.
  Future<List<VehiculoDocumentoData>> listarPorVehiculo(String vehiculoId);

  /// Todos los documentos de todos los Vehículos, sin acotar — misma
  /// consulta masiva de una sola vez que usa `ReportesController`
  /// (Inventario 7D) para evitar N+1: la pantalla de Alertas la agrupa
  /// por Vehículo y por `tipo` en memoria, nunca con una consulta por
  /// fila.
  Future<List<VehiculoDocumentoData>> listarTodos();

  /// Escritura cruda — sin validaciones de negocio (`otro` exige
  /// `tipoOtroDescripcion`, fechas coherentes); esas viven en
  /// `RegistrarDocumentoVehiculoUseCase`.
  Future<VehiculoDocumentoData> crear({
    required String vehiculoId,
    required String tipo,
    String? tipoOtroDescripcion,
    String? numeroFolio,
    DateTime? fechaEmision,
    DateTime? fechaVencimiento,
    String? observaciones,
  });

  /// Adjunta un archivo al documento — inserta `Attachment` +
  /// `VehiculoDocumentoAttachment`, una transacción. Permite varios
  /// adjuntos por documento (ver el doc comment de
  /// `VehiculoDocumentoAttachment`).
  Future<AttachmentData> adjuntarArchivo({
    required String vehiculoDocumentoId,
    required String originalFileName,
    required String storedFileName,
    required String path,
    required String mimeType,
    required int sizeBytes,
  });
}
