import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/servicio_comercial_repository.dart';

import '../repositories/asignacion_servicio_repository.dart';

sealed class RegularizarPerfilAsignacionResultado {}

class RegularizarPerfilAsignacionExitoso extends RegularizarPerfilAsignacionResultado {
  RegularizarPerfilAsignacionExitoso(this.asignacion);
  final AsignacionServicioData asignacion;
}

class RegularizarPerfilAsignacionNoExiste extends RegularizarPerfilAsignacionResultado {}

/// Solo se regulariza una asignación VIGENTE — es la que participa en
/// la cobertura actual (Dashboard/Servicio); una fila ya cerrada no
/// afecta ningún cálculo en vivo.
class RegularizarPerfilAsignacionNoVigente extends RegularizarPerfilAsignacionResultado {}

/// Ya tiene un perfil asociado — nunca se sobrescribe uno existente
/// (evita convertir esto en una vía alterna de "cambiar de línea").
class RegularizarPerfilAsignacionYaTienePerfil extends RegularizarPerfilAsignacionResultado {}

/// La línea elegida no pertenece al mismo Servicio de la asignación, o
/// no tiene una vigencia vigente hoy.
class RegularizarPerfilAsignacionLineaInvalida extends RegularizarPerfilAsignacionResultado {}

class RegularizarPerfilAsignacionErrorInesperado extends RegularizarPerfilAsignacionResultado {
  RegularizarPerfilAsignacionErrorInesperado(this.mensaje);
  final String mensaje;
}

/// "Regularizar perfil de asignación" (Etapa 15, corrección del bug
/// real de atribución histórica) — completa el `lineaComercialId` de
/// una `AsignacionServicio` vigente que quedó `NULL` (dato previo a
/// Etapa 15). Deliberadamente estrecho: solo escribe esa columna,
/// nunca crea una asignación nueva, ni toca fecha de inicio, sueldo,
/// bono ni historial — la única corrección es la clasificación por
/// línea/perfil que faltaba. Facultad exclusiva del Usuario Maestro
/// (ver `regularizarPerfilAsignacionServicioAutorizadoProvider`).
class RegularizarPerfilAsignacionServicioUseCase {
  RegularizarPerfilAsignacionServicioUseCase(this._asignacionRepository, this._servicioComercialRepository);

  final AsignacionServicioRepository _asignacionRepository;
  final ServicioComercialRepository _servicioComercialRepository;

  Future<RegularizarPerfilAsignacionResultado> ejecutar({
    required String asignacionServicioId,
    required String lineaComercialId,
    String? actorUsuarioId,
  }) async {
    final asignacion = await _asignacionRepository.obtenerPorId(asignacionServicioId);
    if (asignacion == null) return RegularizarPerfilAsignacionNoExiste();
    if (asignacion.fechaTermino != null) return RegularizarPerfilAsignacionNoVigente();
    if (asignacion.lineaComercialId != null) return RegularizarPerfilAsignacionYaTienePerfil();

    final lineasDelServicio = await _servicioComercialRepository.listarLineas(asignacion.servicioId);
    final lineaValida = lineasDelServicio.any((l) => l.linea.id == lineaComercialId && l.vigenciaActual != null);
    if (!lineaValida) return RegularizarPerfilAsignacionLineaInvalida();

    try {
      final actualizada = await _asignacionRepository.regularizarPerfil(
        asignacionServicioId: asignacionServicioId,
        lineaComercialId: lineaComercialId,
        actorUsuarioId: actorUsuarioId,
      );
      return RegularizarPerfilAsignacionExitoso(actualizada);
    } catch (e) {
      return RegularizarPerfilAsignacionErrorInesperado(e.toString());
    }
  }
}
