import 'package:riseg_one/features/inventario/domain/repositories/articulo_repository.dart';
import 'package:riseg_one/features/inventario/domain/repositories/asignacion_repository.dart';
import 'package:riseg_one/features/inventario/domain/repositories/inventario_repository.dart';

/// Resumen de Inventario para el bloque "Operación" de Reportes (Etapa
/// 12C) — un resumen compacto que reutiliza exactamente las mismas
/// llamadas que ya usa el Reportes completo de Inventario (Etapa 7D,
/// `lib/features/inventario/presentation/reportes/`), **nunca**
/// reconstruye esa pantalla. La UI de Reportes generales complementa
/// este resumen con un enlace directo a `/inventario/reportes`.
class ResumenInventarioReportes {
  const ResumenInventarioReportes({
    required this.existenciaTotal,
    required this.asignacionesVigentes,
    required this.danadosPerdidos,
    required this.descuentosPendientes,
    required this.movimientosEnPeriodo,
    required this.valorAproximado,
    required this.articulosConValorExcluido,
  });

  /// Snapshot — suma de existencia (disponible+asignado+dañado+perdido)
  /// de todos los artículos, a la fecha de hoy.
  final int existenciaTotal;

  /// Snapshot — igual a "pendientes de devolución" (mismo concepto, no
  /// uno nuevo — ver el doc comment de `AsignacionRepository.listarTodasActivas`).
  final int asignacionesVigentes;
  final int danadosPerdidos;
  final int descuentosPendientes;

  /// Del periodo consultado — `COUNT()`, nunca la lista completa.
  final int movimientosEnPeriodo;

  /// Snapshot, y **aproximado**: excluye artículos con variante y
  /// artículos sin `costoUnitario` capturado en ninguna entrada — mismo
  /// criterio que el Reportes de Inventario (7D). Nunca se presenta sin
  /// [articulosConValorExcluido] a la vista para que la UI muestre la
  /// salvedad.
  final int valorAproximado;
  final int articulosConValorExcluido;
}

class ObtenerResumenInventarioUseCase {
  ObtenerResumenInventarioUseCase(this._articuloRepository, this._inventarioRepository, this._asignacionRepository);

  final ArticuloRepository _articuloRepository;
  final InventarioRepository _inventarioRepository;
  final AsignacionRepository _asignacionRepository;

  Future<ResumenInventarioReportes> ejecutar({DateTime? rangoInicio, DateTime? rangoFin}) async {
    final articulos = await _articuloRepository.listar(soloActivos: false);

    var existenciaTotal = 0;
    var valorAproximado = 0;
    var articulosConValorExcluido = 0;

    for (final articulo in articulos) {
      final existencia = articulo.manejaSerie
          ? await _inventarioRepository.calcularExistenciaUnidades(articulo.id)
          : await _inventarioRepository.calcularExistencia(articuloId: articulo.id);
      existenciaTotal += existencia.total;

      if (articulo.manejaVariante) {
        articulosConValorExcluido++;
        continue;
      }
      final costoPromedio = await _inventarioRepository.calcularCostoPromedio(articuloId: articulo.id);
      if (costoPromedio == null) {
        articulosConValorExcluido++;
        continue;
      }
      valorAproximado += costoPromedio * existencia.total;
    }

    final asignacionesVigentes = await _asignacionRepository.listarTodasActivas();
    final danadosPerdidos = await _asignacionRepository.listarDanadasPerdidas();
    final descuentosPendientes = await _asignacionRepository.listarTodosDescuentosPendientes();
    final movimientosEnPeriodo = await _inventarioRepository.totalMovimientosEnRango(desde: rangoInicio, hasta: rangoFin);

    return ResumenInventarioReportes(
      existenciaTotal: existenciaTotal,
      asignacionesVigentes: asignacionesVigentes.length,
      danadosPerdidos: danadosPerdidos.length,
      descuentosPendientes: descuentosPendientes.length,
      movimientosEnPeriodo: movimientosEnPeriodo,
      valorAproximado: valorAproximado,
      articulosConValorExcluido: articulosConValorExcluido,
    );
  }
}
