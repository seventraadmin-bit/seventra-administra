import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/asignacion_repository.dart';
import '../../data/tables/descuento_inventario_table.dart' show EstatusDescuentoInventario;

sealed class CancelarDescuentoInventarioResultado {}

class CancelarDescuentoInventarioExitoso extends CancelarDescuentoInventarioResultado {
  CancelarDescuentoInventarioExitoso(this.descuento);
  final DescuentoInventarioData descuento;
}

class CancelarDescuentoInventarioNoExiste extends CancelarDescuentoInventarioResultado {}

class CancelarDescuentoInventarioYaResuelto extends CancelarDescuentoInventarioResultado {}

class CancelarDescuentoInventarioErrorInesperado extends CancelarDescuentoInventarioResultado {
  CancelarDescuentoInventarioErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Cancela un `DescuentoInventario` pendiente — cuando la atribución
/// resultó incorrecta. Nunca borra la fila; solo permite cancelar si
/// sigue `pendiente` (nunca revertir uno ya `aplicado`, eso pertenece
/// a la futura integración con Nómina).
class CancelarDescuentoInventarioUseCase {
  CancelarDescuentoInventarioUseCase(this._repository);

  final AsignacionRepository _repository;

  Future<CancelarDescuentoInventarioResultado> ejecutar({
    required String descuentoId,
    String? observaciones,
    String? actorUsuarioId,
  }) async {
    final descuento = await _repository.obtenerDescuentoPorId(descuentoId);
    if (descuento == null) return CancelarDescuentoInventarioNoExiste();
    if (EstatusDescuentoInventario.values.byName(descuento.estatus) != EstatusDescuentoInventario.pendiente) {
      return CancelarDescuentoInventarioYaResuelto();
    }

    try {
      final actualizado = await _repository.cancelarDescuento(
        descuentoId: descuentoId,
        observaciones: observaciones,
        actorUsuarioId: actorUsuarioId,
      );
      return CancelarDescuentoInventarioExitoso(actualizado);
    } catch (e) {
      return CancelarDescuentoInventarioErrorInesperado(e.toString());
    }
  }
}
