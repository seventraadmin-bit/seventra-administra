import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';

import '../repositories/area_repository.dart';
import '../repositories/puesto_repository.dart';

/// Resultado de `CambiarCicloVidaPuestoUseCase` — su propio tipo sellado
/// porque el bloqueo de reactivación por Área inactiva es un caso
/// estructurado propio, no un mensaje genérico de texto.
sealed class CambiarCicloVidaPuestoResultado {}

class CambiarCicloVidaPuestoExitoso extends CambiarCicloVidaPuestoResultado {
  CambiarCicloVidaPuestoExitoso(this.puesto);
  final PuestoData puesto;
}

/// Reactivar (nunca archivar) fue rechazado porque el Área del Puesto no
/// existe o está inactiva — el registro no se modificó.
class CambiarCicloVidaPuestoAreaInactiva extends CambiarCicloVidaPuestoResultado {}

class CambiarCicloVidaPuestoErrorInesperado extends CambiarCicloVidaPuestoResultado {
  CambiarCicloVidaPuestoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Archivar un Puesto siempre está permitido. Reactivarlo exige que su
/// Área exista y esté activa — evita que quede un Puesto activo
/// relacionado con un Área fuera de circulación (la misma situación que
/// `DesactivarAreaUseCase` ya impide del otro lado).
class CambiarCicloVidaPuestoUseCase {
  CambiarCicloVidaPuestoUseCase(this._puestoRepository, this._areaRepository);

  final PuestoRepository _puestoRepository;
  final AreaRepository _areaRepository;

  Future<CambiarCicloVidaPuestoResultado> ejecutar({
    required String puestoId,
    required CicloVidaRegistro nuevo,
  }) async {
    if (nuevo == CicloVidaRegistro.activo) {
      final puesto = await _puestoRepository.obtenerPorId(puestoId);
      if (puesto == null) {
        return CambiarCicloVidaPuestoErrorInesperado('Puesto no encontrado: $puestoId');
      }
      final area = await _areaRepository.obtenerPorId(puesto.areaId);
      if (area == null || !area.activo) {
        return CambiarCicloVidaPuestoAreaInactiva();
      }
    }

    try {
      final actualizado = await _puestoRepository.cambiarCicloVida(id: puestoId, nuevo: nuevo);
      return CambiarCicloVidaPuestoExitoso(actualizado);
    } catch (e) {
      return CambiarCicloVidaPuestoErrorInesperado(e.toString());
    }
  }
}
