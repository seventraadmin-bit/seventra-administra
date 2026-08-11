import 'package:riseg_one/features/compras/domain/repositories/compra_repository.dart';
import 'package:riseg_one/features/inventario/domain/repositories/articulo_repository.dart';

/// Un total agrupado por una clave legible (proveedor, forma de pago,
/// artículo/concepto) — Etapa 12C (Reportes).
class TotalPorClave {
  const TotalPorClave({required this.clave, required this.total});
  final String clave;
  final int total;
}

/// Resumen de Compras para el bloque "Operación" de Reportes (Etapa
/// 12C). [totalCanceladas] es un indicador **separado**, nunca sumado
/// a [totalComprado] ni a los desgloses — mismo criterio que
/// `CompraRepository.totalCompradoEnRango` ya excluye canceladas.
/// Puramente operativo/informativo: este resumen **nunca** se combina
/// con `Egreso`/Resultado operativo (eso ya lo resuelve el Reporte
/// General de la Etapa 12A).
class ResumenComprasReportes {
  const ResumenComprasReportes({
    required this.totalComprado,
    required this.totalCanceladas,
    required this.totalInventario,
    required this.totalGastoDirecto,
    required this.porProveedor,
    required this.porFormaPago,
    required this.porArticuloOConcepto,
  });

  final int totalComprado;
  final int totalCanceladas;
  final int totalInventario;
  final int totalGastoDirecto;
  final List<TotalPorClave> porProveedor;
  final List<TotalPorClave> porFormaPago;
  final List<TotalPorClave> porArticuloOConcepto;
}

const _sinProveedor = '—';

class ObtenerResumenComprasUseCase {
  ObtenerResumenComprasUseCase(this._compraRepository, this._articuloRepository);

  final CompraRepository _compraRepository;
  final ArticuloRepository _articuloRepository;

  Future<ResumenComprasReportes> ejecutar({DateTime? rangoInicio, DateTime? rangoFin}) async {
    final totalComprado = await _compraRepository.totalCompradoEnRango(desde: rangoInicio, hasta: rangoFin);

    final partidasRegistradas = await _compraRepository.listarPartidasEnRango(
      desde: rangoInicio,
      hasta: rangoFin,
      estatus: 'registrada',
    );
    final partidasCanceladas = await _compraRepository.listarPartidasEnRango(
      desde: rangoInicio,
      hasta: rangoFin,
      estatus: 'cancelada',
    );
    final totalCanceladas = partidasCanceladas.fold<int>(0, (s, f) => s + f.partida.cantidad * f.partida.costoUnitario);

    final articulos = await _articuloRepository.listar(soloActivos: false);
    final nombrePorArticulo = {for (final a in articulos) a.id: a.nombre};

    var totalInventario = 0;
    var totalGastoDirecto = 0;
    final porProveedor = <String, int>{};
    final porFormaPago = <String, int>{};
    final porArticuloOConcepto = <String, int>{};

    for (final fila in partidasRegistradas) {
      final monto = fila.partida.cantidad * fila.partida.costoUnitario;
      final esInventario = fila.partida.destino == 'inventario';
      if (esInventario) {
        totalInventario += monto;
      } else {
        totalGastoDirecto += monto;
      }

      final proveedor = fila.compra.proveedor?.trim();
      final claveProveedor = (proveedor == null || proveedor.isEmpty) ? _sinProveedor : proveedor;
      porProveedor[claveProveedor] = (porProveedor[claveProveedor] ?? 0) + monto;

      porFormaPago[fila.compra.formaPago] = (porFormaPago[fila.compra.formaPago] ?? 0) + monto;

      final claveArticulo = esInventario
          ? (nombrePorArticulo[fila.partida.articuloId] ?? fila.partida.articuloId ?? _sinProveedor)
          : (fila.partida.concepto ?? _sinProveedor);
      porArticuloOConcepto[claveArticulo] = (porArticuloOConcepto[claveArticulo] ?? 0) + monto;
    }

    List<TotalPorClave> aLista(Map<String, int> mapa) =>
        [for (final entrada in mapa.entries) TotalPorClave(clave: entrada.key, total: entrada.value)]
          ..sort((a, b) => b.total.compareTo(a.total));

    return ResumenComprasReportes(
      totalComprado: totalComprado,
      totalCanceladas: totalCanceladas,
      totalInventario: totalInventario,
      totalGastoDirecto: totalGastoDirecto,
      porProveedor: aLista(porProveedor),
      porFormaPago: aLista(porFormaPago),
      porArticuloOConcepto: aLista(porArticuloOConcepto),
    );
  }
}
