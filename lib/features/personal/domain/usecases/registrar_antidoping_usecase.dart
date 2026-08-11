import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart';

import '../repositories/empleado_repository.dart';
import 'adjuntar_documento_empleado_usecase.dart';
import 'empleado_validator.dart';

sealed class RegistrarAntidopingResultado {}

class RegistrarAntidopingExitoso extends RegistrarAntidopingResultado {
  RegistrarAntidopingExitoso(this.empleado);
  final EmpleadoData empleado;
}

class RegistrarAntidopingNoExiste extends RegistrarAntidopingResultado {}

class RegistrarAntidopingFechaInvalida extends RegistrarAntidopingResultado {}

class RegistrarAntidopingErrorInesperado extends RegistrarAntidopingResultado {
  RegistrarAntidopingErrorInesperado(this.mensaje);
  final String mensaje;
}

String? _vacioANull(String? valor) {
  final recortado = valor?.trim();
  return (recortado == null || recortado.isEmpty) ? null : recortado;
}

/// Registra/actualiza el Antidoping vigente de un Empleado (Etapa 5B)
/// — un resultado por sustancia (AMP/BZD/COC/MET/OPI), nunca un
/// resultado único general (Resolución explícita de Marlon, para
/// adaptarse a distintos paneles comerciales de laboratorio sin
/// complicar el modelo). Mismo diseño de diálogo combinado que Perfil
/// psicológico/Estudio socioeconómico: PDF opcional en el mismo paso.
class RegistrarAntidopingUseCase {
  RegistrarAntidopingUseCase(this._repository, this._storage, this._validator);

  final EmpleadoRepository _repository;
  final AttachmentStorage _storage;
  final EmpleadoValidator _validator;

  Future<RegistrarAntidopingResultado> ejecutar({
    required String empleadoId,
    required DateTime fecha,
    required ResultadoSustanciaAntidoping amp,
    required ResultadoSustanciaAntidoping bzd,
    required ResultadoSustanciaAntidoping coc,
    required ResultadoSustanciaAntidoping met,
    required ResultadoSustanciaAntidoping opi,
    String? observaciones,
    String? sourceFilePath,
    String? originalFileName,
    String? mimeType,
    String? actorUsuarioId,
  }) async {
    final empleado = await _repository.obtenerPorId(empleadoId);
    if (empleado == null) return RegistrarAntidopingNoExiste();
    if (!_validator.fechaEvaluacionValida(fecha)) return RegistrarAntidopingFechaInvalida();

    try {
      final actualizado = await _repository.actualizarAntidoping(
        empleadoId: empleadoId,
        fecha: fecha,
        amp: amp,
        bzd: bzd,
        coc: coc,
        met: met,
        opi: opi,
        observaciones: _vacioANull(observaciones),
        actorUsuarioId: actorUsuarioId,
      );

      if (sourceFilePath != null && originalFileName != null && mimeType != null) {
        final guardado = await _storage.guardar(
          ownerId: empleadoId,
          categoria: CategoriaDocumentoEmpleado.antidoping.name,
          sourceFilePath: sourceFilePath,
          originalFileName: originalFileName,
        );
        await _repository.adjuntarDocumento(
          empleadoId: empleadoId,
          categoria: CategoriaDocumentoEmpleado.antidoping.name,
          originalFileName: originalFileName,
          storedFileName: guardado.storedFileName,
          path: guardado.path,
          mimeType: mimeType,
          sizeBytes: guardado.sizeBytes,
          actorUsuarioId: actorUsuarioId,
        );
      }

      return RegistrarAntidopingExitoso(actualizado);
    } catch (e) {
      return RegistrarAntidopingErrorInesperado(e.toString());
    }
  }
}
