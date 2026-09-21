import 'package:riseg_one/core/database/app_database.dart';

import '../../data/tables/vehiculo_mantenimiento_table.dart';

/// Costos acumulados de un Vehículo (Etapa 8D, punto 6) — todo derivado
/// en consulta, nunca almacenado (mismo criterio que "costo promedio" en
/// Inventario). Sin depreciación, sin FIFO/LIFO, sin contabilidad —
/// instrucción explícita de Marlon.
///
/// Deliberadamente **no incluye costos documentales**: `VehiculoDocumento`
/// no tiene columna `costo` (decisión explícita de la Etapa 8C, "no
/// quiero todavía mantenimiento ni gastos" en ese momento) — el punto 6
/// de esta etapa los pide "si ya existen", y todavía no existen. Si una
/// etapa futura agrega esa columna, sumarla aquí es un cambio de una
/// línea.
class CostosVehiculo {
  const CostosVehiculo({
    required this.costoAdquisicion,
    required this.totalMantenimientos,
    required this.totalIncidencias,
  });

  final int? costoAdquisicion;
  final int totalMantenimientos;
  final int totalIncidencias;

  int get costoOperativoAcumulado => (costoAdquisicion ?? 0) + totalMantenimientos + totalIncidencias;
}

CostosVehiculo calcularCostosVehiculo(VehiculoData vehiculo, List<VehiculoMantenimientoData> historial) {
  var totalMantenimientos = 0;
  var totalIncidencias = 0;
  for (final registro in historial) {
    // Un mantenimiento anulado (schemaVersion 80) ya revirtió su efecto
    // financiero — su Egreso quedó cancelado, o su cargo de TDC
    // revertido. Seguir sumándolo aquí dejaría el costo del vehículo
    // contradiciendo a Finanzas. La fila SÍ se conserva y se sigue
    // viendo en el historial: lo que no se conserva es su peso en el
    // total.
    if (registro.estatus == EstatusMantenimientoVehiculo.cancelado.name) continue;
    final costo = registro.costo;
    if (costo == null) continue;
    final esIncidencia = TipoMantenimientoVehiculo.values.byName(registro.tipo).esIncidencia;
    if (esIncidencia) {
      totalIncidencias += costo;
    } else {
      totalMantenimientos += costo;
    }
  }
  return CostosVehiculo(
    costoAdquisicion: vehiculo.costoAdquisicion,
    totalMantenimientos: totalMantenimientos,
    totalIncidencias: totalIncidencias,
  );
}
