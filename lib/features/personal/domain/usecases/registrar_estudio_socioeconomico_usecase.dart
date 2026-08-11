import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/empleado_repository.dart';
import 'adjuntar_documento_empleado_usecase.dart';
import 'empleado_validator.dart';

sealed class RegistrarEstudioSocioeconomicoResultado {}

class RegistrarEstudioSocioeconomicoExitoso extends RegistrarEstudioSocioeconomicoResultado {
  RegistrarEstudioSocioeconomicoExitoso(this.empleado);
  final EmpleadoData empleado;
}

class RegistrarEstudioSocioeconomicoNoExiste extends RegistrarEstudioSocioeconomicoResultado {}

class RegistrarEstudioSocioeconomicoFechaInvalida extends RegistrarEstudioSocioeconomicoResultado {}

class RegistrarEstudioSocioeconomicoErrorInesperado extends RegistrarEstudioSocioeconomicoResultado {
  RegistrarEstudioSocioeconomicoErrorInesperado(this.mensaje);
  final String mensaje;
}

String? _vacioANull(String? valor) {
  final recortado = valor?.trim();
  return (recortado == null || recortado.isEmpty) ? null : recortado;
}

/// Registra/actualiza el Estudio socioeconómico vigente de un Empleado
/// (Etapa 5B) — mismo diseño exacto que
/// `RegistrarPerfilPsicologicoUseCase`: un solo diálogo, PDF opcional
/// en el mismo paso.
class RegistrarEstudioSocioeconomicoUseCase {
  RegistrarEstudioSocioeconomicoUseCase(this._repository, this._storage, this._validator);

  final EmpleadoRepository _repository;
  final AttachmentStorage _storage;
  final EmpleadoValidator _validator;

  Future<RegistrarEstudioSocioeconomicoResultado> ejecutar({
    required String empleadoId,
    required DateTime fecha,
    String? resumen,
    String? observaciones,
    String? sourceFilePath,
    String? originalFileName,
    String? mimeType,
    String? actorUsuarioId,
  }) async {
    final empleado = await _repository.obtenerPorId(empleadoId);
    if (empleado == null) return RegistrarEstudioSocioeconomicoNoExiste();
    if (!_validator.fechaEvaluacionValida(fecha)) return RegistrarEstudioSocioeconomicoFechaInvalida();

    try {
      final actualizado = await _repository.actualizarEstudioSocioeconomico(
        empleadoId: empleadoId,
        fecha: fecha,
        resumen: _vacioANull(resumen),
        observaciones: _vacioANull(observaciones),
        actorUsuarioId: actorUsuarioId,
      );

      if (sourceFilePath != null && originalFileName != null && mimeType != null) {
        final guardado = await _storage.guardar(
          ownerId: empleadoId,
          categoria: CategoriaDocumentoEmpleado.estudioSocioeconomico.name,
          sourceFilePath: sourceFilePath,
          originalFileName: originalFileName,
        );
        await _repository.adjuntarDocumento(
          empleadoId: empleadoId,
          categoria: CategoriaDocumentoEmpleado.estudioSocioeconomico.name,
          originalFileName: originalFileName,
          storedFileName: guardado.storedFileName,
          path: guardado.path,
          mimeType: mimeType,
          sizeBytes: guardado.sizeBytes,
          actorUsuarioId: actorUsuarioId,
        );
      }

      return RegistrarEstudioSocioeconomicoExitoso(actualizado);
    } catch (e) {
      return RegistrarEstudioSocioeconomicoErrorInesperado(e.toString());
    }
  }
}
