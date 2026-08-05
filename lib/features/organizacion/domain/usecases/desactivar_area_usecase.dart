import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/area_repository.dart';
import '../repositories/puesto_repository.dart';

sealed class DesactivarAreaResultado {}

class DesactivarAreaExitoso extends DesactivarAreaResultado {
  DesactivarAreaExitoso(this.area);
  final AreaData area;
}

/// Bloqueado porque existen Puestos con `cicloVidaRegistro = activo`
/// apuntando a esta Área — los Puestos archivados nunca cuentan para
/// este bloqueo (sí importan, en cambio, al intentar reactivarlos: ver
/// `CambiarCicloVidaPuestoUseCase`).
class DesactivarAreaBloqueadaPorPuestosActivos extends DesactivarAreaResultado {
  DesactivarAreaBloqueadaPorPuestosActivos(this.cantidad);
  final int cantidad;
}

/// Única operación que saca a un Área de circulación — la regla de
/// "sin Puestos activos" se aplica siempre aquí, sin excepción ni ruta
/// alterna que la evite.
class DesactivarAreaUseCase {
  DesactivarAreaUseCase(this._areaRepository, this._puestoRepository);

  final AreaRepository _areaRepository;
  final PuestoRepository _puestoRepository;

  Future<DesactivarAreaResultado> ejecutar(String areaId) async {
    final cantidad = await _puestoRepository.contarActivosPorArea(areaId);
    if (cantidad > 0) {
      return DesactivarAreaBloqueadaPorPuestosActivos(cantidad);
    }

    final area = await _areaRepository.desactivar(areaId);
    return DesactivarAreaExitoso(area);
  }
}
