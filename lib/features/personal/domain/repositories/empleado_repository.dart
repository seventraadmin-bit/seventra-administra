import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/domain/shared/direccion_input.dart';

/// Expediente del empleado (Etapa 5A) — la base de Personal.
abstract interface class EmpleadoRepository {
  Future<EmpleadoData?> obtenerPorId(String id);

  Future<List<EmpleadoData>> listar({
    String? estatus,
    String? puestoId,
    String? empresaId,
    String? sucursalId,
  });

  Future<List<EmpleadoEventoData>> listarEventos(String empleadoId);

  /// El llamador ya generó `codigoEmpleado` (mismo criterio que
  /// `PagoRepository.crear`).
  Future<EmpleadoData> crear(EmpleadoCompanion datos);

  /// `cambios` nunca debe incluir `codigoEmpleado` — inmutable después
  /// de creado (responsabilidad de `CorregirEmpleadoUseCase`, mismo
  /// criterio que `ActualizarServicioUseCase` con `clienteId`).
  Future<EmpleadoData> corregir({
    required String empleadoId,
    required EmpleadoCompanion cambios,
    required String motivo,
    String? actor,
  });

  Future<EmpleadoData> cambiarEstatus({
    required String empleadoId,
    required String nuevo,
    String? motivo,
    String? actor,
  });

  /// Actualiza el puntero `fotografiaAttachmentId` — el Attachment y su
  /// fila de unión en `EmpleadoAttachment` ya deben existir (los crea
  /// `ActualizarFotografiaEmpleadoUseCase` antes de llamar aquí).
  Future<EmpleadoData> actualizarFotografia({
    required String empleadoId,
    required String attachmentId,
    String? actor,
  });

  Future<DireccionData?> obtenerDomicilio(String empleadoId);

  /// Upsert — mismo criterio que
  /// `EntidadFiscalRepository.guardarDomicilioFiscal`: busca la fila
  /// existente sin importar `cicloVidaRegistro` (a lo más una,
  /// garantizado por el `UNIQUE` real de `empleadoId`), reactiva y
  /// actualiza si existe, inserta solo si nunca existió. `input ==
  /// null` archiva la existente (si había alguna) sin borrarla
  /// físicamente.
  Future<DireccionData?> guardarDomicilio(String empleadoId, DireccionInput? input, {String? actor});

  Future<AttachmentData> adjuntarDocumento({
    required String empleadoId,
    required String categoria,
    required String originalFileName,
    required String storedFileName,
    required String path,
    required String mimeType,
    required int sizeBytes,
    String? actor,
  });
}
