import 'package:riseg_one/features/compras/domain/repositories/compra_repository.dart';

/// Resuelve el origen (`Compra`) de uno o varios `MovimientoInventario`,
/// cuando lo tienen — lectura cruzada hacia Compras (Etapa 10), mismo
/// criterio ya establecido por Telefonía→Personal/Organización/
/// Inventario (9B): el dominio que necesita el dato ajeno inyecta el
/// repositorio real del otro dominio y lo envuelve en su propio caso
/// de uso — la UI de Inventario nunca importa `CompraRepository`
/// directo.
class ObtenerOrigenCompraUseCase {
  ObtenerOrigenCompraUseCase(this._compraRepository);

  final CompraRepository _compraRepository;

  Future<Map<String, OrigenCompra>> obtenerParaMovimientos(Iterable<String> movimientoInventarioIds) {
    return _compraRepository.obtenerOrigenesPorMovimientos(movimientoInventarioIds);
  }
}
