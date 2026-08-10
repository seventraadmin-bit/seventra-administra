import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/asignacion_repository.dart';
import '../../data/tables/asignacion_table.dart' show EstatusAsignacion, MotivoCierreAsignacion;

sealed class CerrarAsignacionResultado {}

class CerrarAsignacionExitoso extends CerrarAsignacionResultado {
  CerrarAsignacionExitoso(this.asignacion);
  final AsignacionData asignacion;
}

class CerrarAsignacionNoExiste extends CerrarAsignacionResultado {}

class CerrarAsignacionYaCerrada extends CerrarAsignacionResultado {}

class CerrarAsignacionObservacionesRequeridas extends CerrarAsignacionResultado {}

/// `motivo` es `dano`/`perdida` pero no se indicó si es atribuible al
/// empleado.
class CerrarAsignacionAtribucionRequerida extends CerrarAsignacionResultado {}

/// `generaDescuento == true` sin `importeDescuento`/`empleadoResponsable`,
/// o marcado sobre un motivo que no dispara daño/pérdida.
class CerrarAsignacionDescuentoInvalido extends CerrarAsignacionResultado {}

class CerrarAsignacionErrorInesperado extends CerrarAsignacionResultado {
  CerrarAsignacionErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Cierra una `Asignacion` activa — cubre Devolución y Reporte de
/// daño/pérdida con el mismo caso de uso (la UI restringe el picker de
/// `motivo` según el botón de origen, ver el doc comment de
/// `MotivoCierreAsignacion`). `estatus` final se deriva de `motivo`,
/// nunca se captura por separado.
class CerrarAsignacionUseCase {
  CerrarAsignacionUseCase(this._repository);

  final AsignacionRepository _repository;

  Future<CerrarAsignacionResultado> ejecutar({
    required String asignacionId,
    required MotivoCierreAsignacion motivo,
    required DateTime fechaCierre,
    String? observacionesCierre,
    bool? atribuibleAlEmpleado,
    bool generaDescuento = false,
    int? importeDescuento,
    String? empleadoResponsableDescuentoId,
    String? actor,
  }) async {
    final asignacion = await _repository.obtenerPorId(asignacionId);
    if (asignacion == null) return CerrarAsignacionNoExiste();
    if (EstatusAsignacion.values.byName(asignacion.estatus) != EstatusAsignacion.activa) {
      return CerrarAsignacionYaCerrada();
    }

    final observaciones = observacionesCierre?.trim();
    if (motivo.requiereObservaciones && (observaciones == null || observaciones.isEmpty)) {
      return CerrarAsignacionObservacionesRequeridas();
    }

    if (motivo.disparaDanoPerdida && atribuibleAlEmpleado == null) {
      return CerrarAsignacionAtribucionRequerida();
    }

    if (generaDescuento) {
      if (!motivo.disparaDanoPerdida) return CerrarAsignacionDescuentoInvalido();
      if (importeDescuento == null || importeDescuento <= 0) return CerrarAsignacionDescuentoInvalido();
      if (empleadoResponsableDescuentoId == null || empleadoResponsableDescuentoId.isEmpty) {
        return CerrarAsignacionDescuentoInvalido();
      }
    }

    try {
      final actualizada = await _repository.cerrar(
        asignacionId: asignacionId,
        motivo: motivo.name,
        fechaCierre: fechaCierre,
        observacionesCierre: observaciones,
        atribuibleAlEmpleado: motivo.disparaDanoPerdida ? atribuibleAlEmpleado : null,
        generaDescuento: generaDescuento,
        importeDescuento: generaDescuento ? importeDescuento : null,
        empleadoResponsableDescuentoId: generaDescuento ? empleadoResponsableDescuentoId : null,
        actor: actor,
      );
      return CerrarAsignacionExitoso(actualizada);
    } catch (e) {
      return CerrarAsignacionErrorInesperado(e.toString());
    }
  }
}
