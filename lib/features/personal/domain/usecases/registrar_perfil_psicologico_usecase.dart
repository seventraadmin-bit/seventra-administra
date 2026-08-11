import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/empleado_repository.dart';
import 'adjuntar_documento_empleado_usecase.dart';
import 'empleado_validator.dart';

sealed class RegistrarPerfilPsicologicoResultado {}

class RegistrarPerfilPsicologicoExitoso extends RegistrarPerfilPsicologicoResultado {
  RegistrarPerfilPsicologicoExitoso(this.empleado);
  final EmpleadoData empleado;
}

class RegistrarPerfilPsicologicoNoExiste extends RegistrarPerfilPsicologicoResultado {}

class RegistrarPerfilPsicologicoFechaInvalida extends RegistrarPerfilPsicologicoResultado {}

class RegistrarPerfilPsicologicoErrorInesperado extends RegistrarPerfilPsicologicoResultado {
  RegistrarPerfilPsicologicoErrorInesperado(this.mensaje);
  final String mensaje;
}

String? _vacioANull(String? valor) {
  final recortado = valor?.trim();
  return (recortado == null || recortado.isEmpty) ? null : recortado;
}

/// Registra/actualiza el Perfil psicológico vigente de un Empleado
/// (Etapa 5B) — un solo diálogo captura fecha/resumen/observaciones y,
/// opcionalmente, el PDF en el mismo paso (Resolución explícita de
/// Marlon: "no quiero obligar al usuario a guardar primero y después
/// navegar a otra sección para adjuntar el documento"). Sin PDF, se
/// guarda igual — el archivo es completamente opcional.
class RegistrarPerfilPsicologicoUseCase {
  RegistrarPerfilPsicologicoUseCase(this._repository, this._storage, this._validator);

  final EmpleadoRepository _repository;
  final AttachmentStorage _storage;
  final EmpleadoValidator _validator;

  Future<RegistrarPerfilPsicologicoResultado> ejecutar({
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
    if (empleado == null) return RegistrarPerfilPsicologicoNoExiste();
    if (!_validator.fechaEvaluacionValida(fecha)) return RegistrarPerfilPsicologicoFechaInvalida();

    try {
      final actualizado = await _repository.actualizarPerfilPsicologico(
        empleadoId: empleadoId,
        fecha: fecha,
        resumen: _vacioANull(resumen),
        observaciones: _vacioANull(observaciones),
        actorUsuarioId: actorUsuarioId,
      );

      if (sourceFilePath != null && originalFileName != null && mimeType != null) {
        final guardado = await _storage.guardar(
          ownerId: empleadoId,
          categoria: CategoriaDocumentoEmpleado.perfilPsicologico.name,
          sourceFilePath: sourceFilePath,
          originalFileName: originalFileName,
        );
        await _repository.adjuntarDocumento(
          empleadoId: empleadoId,
          categoria: CategoriaDocumentoEmpleado.perfilPsicologico.name,
          originalFileName: originalFileName,
          storedFileName: guardado.storedFileName,
          path: guardado.path,
          mimeType: mimeType,
          sizeBytes: guardado.sizeBytes,
          actorUsuarioId: actorUsuarioId,
        );
      }

      return RegistrarPerfilPsicologicoExitoso(actualizado);
    } catch (e) {
      return RegistrarPerfilPsicologicoErrorInesperado(e.toString());
    }
  }
}
