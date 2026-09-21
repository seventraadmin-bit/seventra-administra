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

  /// Corrige un documento YA registrado (schemaVersion 80) — es lo
  /// contrario de renovar: renovar crea una fila nueva porque el
  /// documento cambió en la realidad; corregir arregla lo que se
  /// capturó mal (un folio con un dígito de mas, una fecha invertida)
  /// sobre la MISMA fila, para no inventar una vigencia que nunca
  /// existió.
  ///
  /// Escritura cruda, sin validaciones ni auditoría: el motivo y el
  /// evento en el historial del vehículo los impone
  /// `CorregirDocumentoVehiculoUseCase`. Solo se escriben los campos
  /// no nulos; `limpiarNumeroFolio`/`limpiarFechaEmision`/
  /// `limpiarFechaVencimiento`/`limpiarObservaciones` existen porque
  /// "dejarlo vacío" y "no tocarlo" son cosas distintas y `null` no
  /// puede significar las dos.
  Future<VehiculoDocumentoData> corregir({
    required String vehiculoDocumentoId,
    String? tipo,
    String? tipoOtroDescripcion,
    String? numeroFolio,
    bool limpiarNumeroFolio = false,
    DateTime? fechaEmision,
    bool limpiarFechaEmision = false,
    DateTime? fechaVencimiento,
    bool limpiarFechaVencimiento = false,
    String? observaciones,
    bool limpiarObservaciones = false,
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
