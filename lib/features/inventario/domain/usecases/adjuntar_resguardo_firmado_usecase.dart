import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/asignacion_repository.dart';

sealed class AdjuntarResguardoFirmadoResultado {}

class AdjuntarResguardoFirmadoExitoso extends AdjuntarResguardoFirmadoResultado {
  AdjuntarResguardoFirmadoExitoso(this.adjunto);
  final AttachmentData adjunto;
}

class AdjuntarResguardoFirmadoSinAsignaciones extends AdjuntarResguardoFirmadoResultado {}

class AdjuntarResguardoFirmadoAsignacionNoExiste extends AdjuntarResguardoFirmadoResultado {}

/// Las Asignaciones seleccionadas no son todas del mismo Empleado, o
/// todas del mismo Servicio.
class AdjuntarResguardoFirmadoDestinoInvalido extends AdjuntarResguardoFirmadoResultado {}

class AdjuntarResguardoFirmadoErrorInesperado extends AdjuntarResguardoFirmadoResultado {
  AdjuntarResguardoFirmadoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Adjunta el escaneo/foto ya firmado de un resguardo (Etapa 7C) — el
/// único paso que persiste algo: un `Attachment` unido a **todas** las
/// Asignaciones cubiertas (`AsignacionRepository.adjuntarResguardo`,
/// llave compuesta). No valida que las Asignaciones sigan `activa` —
/// el documento sigue siendo constancia histórica válida aunque la
/// Asignación ya haya cambiado (ver el doc comment de
/// `AsignacionAttachment`).
class AdjuntarResguardoFirmadoUseCase {
  AdjuntarResguardoFirmadoUseCase(this._repository, this._storage);

  final AsignacionRepository _repository;
  final AttachmentStorage _storage;

  Future<AdjuntarResguardoFirmadoResultado> ejecutar({
    required List<String> asignacionIds,
    required String sourceFilePath,
    required String originalFileName,
    required String mimeType,
  }) async {
    if (asignacionIds.isEmpty) return AdjuntarResguardoFirmadoSinAsignaciones();

    final asignaciones = <AsignacionData>[];
    for (final id in asignacionIds) {
      final asignacion = await _repository.obtenerPorId(id);
      if (asignacion == null) return AdjuntarResguardoFirmadoAsignacionNoExiste();
      asignaciones.add(asignacion);
    }

    final empleadoIds = asignaciones.map((a) => a.empleadoId).toSet();
    final servicioIds = asignaciones.map((a) => a.servicioId).toSet();
    final mismoEmpleado = empleadoIds.length == 1 && empleadoIds.single != null;
    final mismoServicio = servicioIds.length == 1 && servicioIds.single != null;
    if (!mismoEmpleado && !mismoServicio) return AdjuntarResguardoFirmadoDestinoInvalido();

    try {
      final ownerId = (mismoEmpleado ? empleadoIds.single : servicioIds.single)!;
      final guardado = await _storage.guardar(
        ownerId: ownerId,
        categoria: 'resguardo',
        sourceFilePath: sourceFilePath,
        originalFileName: originalFileName,
      );
      final adjunto = await _repository.adjuntarResguardo(
        asignacionIds: asignacionIds,
        originalFileName: originalFileName,
        storedFileName: guardado.storedFileName,
        path: guardado.path,
        mimeType: mimeType,
        sizeBytes: guardado.sizeBytes,
      );
      return AdjuntarResguardoFirmadoExitoso(adjunto);
    } catch (e) {
      return AdjuntarResguardoFirmadoErrorInesperado(e.toString());
    }
  }
}
