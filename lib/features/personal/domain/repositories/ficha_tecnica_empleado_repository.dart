import 'package:riseg_one/core/database/app_database.dart';

/// Historial append-only de fichas técnicas generadas para un Empleado
/// (Etapa 5E) — ver el doc comment de `FichaTecnicaEmpleado`.
abstract interface class FichaTecnicaEmpleadoRepository {
  /// Inserta el `Attachment` del PDF ya generado y la fila de
  /// `FichaTecnicaEmpleado` que lo referencia, en la misma transacción.
  /// Recibe los datos ya resueltos por `AttachmentStorage.guardar` (el
  /// use case orquestador copia el archivo primero, fuera de la
  /// transacción — mismo reparto de responsabilidades que
  /// `AdjuntarDocumentoEmpleadoUseCase`/`EmpleadoRepository.
  /// adjuntarDocumento`): este método solo hace inserciones de BD.
  Future<FichaTecnicaEmpleadoData> generar({
    required String empleadoId,
    required String folio,
    String? servicioId,
    String? camposExcluidos,
    required String originalFileName,
    required String storedFileName,
    required String path,
    required String mimeType,
    required int sizeBytes,
    String? actor,
  });

  /// Historial completo de este Empleado, orden descendente por
  /// `createdAt` (la más reciente primero).
  Future<List<FichaTecnicaEmpleadoData>> listarPorEmpleado(String empleadoId);
}
