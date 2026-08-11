import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/compra_repository.dart';

sealed class CorregirCompraResultado {}

class CorregirCompraExitosa extends CorregirCompraResultado {
  CorregirCompraExitosa(this.compra);
  final CompraData compra;
}

class CorregirCompraNoExiste extends CorregirCompraResultado {}

class CorregirCompraCancelada extends CorregirCompraResultado {}

class CorregirCompraErrorInesperado extends CorregirCompraResultado {
  CorregirCompraErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Corrige únicamente campos administrativos de una Compra ya
/// registrada — proveedor, forma de pago, observaciones. Nunca
/// partidas, cantidades ni costos: esos quedan fijos desde `crear`
/// (ver el doc comment de `CompraPartida`). Bloqueado si la Compra ya
/// está cancelada.
class CorregirCompraUseCase {
  CorregirCompraUseCase(this._compraRepository);

  final CompraRepository _compraRepository;

  Future<CorregirCompraResultado> ejecutar({
    required String compraId,
    String? proveedor,
    String? formaPago,
    String? formaPagoOtroDescripcion,
    String? observaciones,
    required String motivo,
    String? actor,
  }) async {
    final compra = await _compraRepository.obtenerPorId(compraId);
    if (compra == null) return CorregirCompraNoExiste();
    if (compra.estatus == 'cancelada') return CorregirCompraCancelada();

    try {
      final actualizada = await _compraRepository.corregir(
        compraId: compraId,
        proveedor: proveedor,
        formaPago: formaPago,
        formaPagoOtroDescripcion: formaPagoOtroDescripcion,
        observaciones: observaciones,
        motivo: motivo,
        actor: actor,
      );
      return CorregirCompraExitosa(actualizada);
    } catch (e) {
      return CorregirCompraErrorInesperado(e.toString());
    }
  }
}
