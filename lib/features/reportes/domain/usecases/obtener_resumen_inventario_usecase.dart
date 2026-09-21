import 'package:riseg_one/features/inventario/domain/repositories/articulo_repository.dart';
import 'package:riseg_one/features/inventario/domain/repositories/asignacion_repository.dart';
import 'package:riseg_one/features/inventario/domain/repositories/inventario_repository.dart';
import 'package:riseg_one/features/inventario/domain/usecases/existencia_articulo.dart';

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
    this.unidadesPorEstatus = const {},
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

  /// Snapshot de unidades serializadas por estatus — incluye los
  /// estados físicos intermedios (`enLavanderia`, `enReparacion`,
  /// `pendienteDesecho`) que existen desde que recuperar un bien dejó
  /// de significar automáticamente que está disponible. Sin esto,
  /// Reportes mostraría como "en existencia" prendas que en realidad
  /// están en la tintorería.
  ///
  /// Llave: nombre del `EstatusArticuloUnidad`. Los estatus sin
  /// unidades no aparecen.
  final Map<String, int> unidadesPorEstatus;
}

class ObtenerResumenInventarioUseCase {
  ObtenerResumenInventarioUseCase(this._articuloRepository, this._inventarioRepository, this._asignacionRepository);

  final ArticuloRepository _articuloRepository;
  final InventarioRepository _inventarioRepository;
  final AsignacionRepository _asignacionRepository;

  Future<ResumenInventarioReportes> ejecutar({DateTime? rangoInicio, DateTime? rangoFin}) async {
    final articulos = await _articuloRepository.listar(soloActivos: false);

    // Dos lecturas en lote en vez de dos consultas POR ARTÍCULO: el
    // número de consultas ya no depende de cuántos artículos haya.
    // Las cifras son idénticas — ambas rutas pliegan con las mismas
    // funciones de dominio.
    final existencias = await _inventarioRepository.calcularExistenciaPorArticulos(articulos);
    final costos = await _inventarioRepository.calcularCostoPromedioPorArticulo(
      // Los artículos con variante nunca se valúan a nivel de artículo
      // (su costo vive por talla): se excluyen antes de preguntar.
      [for (final a in articulos) if (!a.manejaVariante) a.id],
    );

    var existenciaTotal = 0;
    var valorAproximado = 0;
    var articulosConValorExcluido = 0;

    for (final articulo in articulos) {
      final existencia = existencias[articulo.id] ?? const ExistenciaArticulo(disponible: 0);
      existenciaTotal += existencia.total;

      if (articulo.manejaVariante) {
        articulosConValorExcluido++;
        continue;
      }
      final costoPromedio = costos[articulo.id];
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
    // Una sola consulta agregada, nunca una por artículo.
    final unidadesPorEstatus = await _inventarioRepository.contarUnidadesPorEstatus();

    return ResumenInventarioReportes(
      existenciaTotal: existenciaTotal,
      asignacionesVigentes: asignacionesVigentes.length,
      danadosPerdidos: danadosPerdidos.length,
      descuentosPendientes: descuentosPendientes.length,
      movimientosEnPeriodo: movimientosEnPeriodo,
      valorAproximado: valorAproximado,
      articulosConValorExcluido: articulosConValorExcluido,
      unidadesPorEstatus: unidadesPorEstatus,
    );
  }
}
