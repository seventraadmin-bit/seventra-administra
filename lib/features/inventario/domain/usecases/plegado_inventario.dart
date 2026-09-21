/// Las tres fórmulas derivadas de Inventario, en un solo lugar.
///
/// Existen como funciones puras —sin repositorio, sin SQL— para que la
/// versión individual (`calcularExistencia`, `calcularExistenciaUnidades`,
/// `calcularCostoPromedio`) y la versión en lote compartan
/// **exactamente** el mismo plegado. Antes de esto, cada consulta
/// repetía el `switch` y el promedio ponderado, que es justo como nacen
/// dos definiciones de la misma cifra.
///
/// Aquí no se decide QUÉ filas leer: eso sigue siendo responsabilidad
/// del repositorio, que es quien conoce el SQL. Aquí sólo se decide qué
/// significan.
library;

import 'package:riseg_one/core/database/app_database.dart';

import '../../data/tables/articulo_unidad_table.dart';
import '../../data/tables/movimiento_inventario_table.dart';
import 'existencia_articulo.dart';

/// Existencia de un artículo POR CANTIDAD, a partir de sus movimientos.
///
/// Recibe ya filtradas las filas que correspondan (todo el artículo, o
/// una variante concreta). `enProceso` siempre queda en 0: un artículo
/// por cantidad no tiene estados físicos intermedios.
ExistenciaArticulo plegarExistenciaDeMovimientos(Iterable<MovimientoInventarioData> movimientos) {
  var disponible = 0;
  var asignado = 0;
  var danado = 0;
  var perdido = 0;

  for (final m in movimientos) {
    final tipo = TipoMovimientoInventario.values.byName(m.tipoMovimiento);
    switch (tipo) {
      case TipoMovimientoInventario.entrada:
      case TipoMovimientoInventario.ajusteEntrada:
        disponible += m.cantidad;
      case TipoMovimientoInventario.baja:
      case TipoMovimientoInventario.ajusteSalida:
        disponible -= m.cantidad;
      case TipoMovimientoInventario.salidaAsignacion:
        disponible -= m.cantidad;
        asignado += m.cantidad;
      case TipoMovimientoInventario.entradaDevolucion:
        asignado -= m.cantidad;
        disponible += m.cantidad;
      case TipoMovimientoInventario.salidaDano:
        asignado -= m.cantidad;
        danado += m.cantidad;
      case TipoMovimientoInventario.salidaPerdida:
        asignado -= m.cantidad;
        perdido += m.cantidad;
    }
  }

  return ExistenciaArticulo(disponible: disponible, asignado: asignado, danado: danado, perdido: perdido);
}

/// Existencia de un artículo SERIALIZADO, contando el estatus de sus
/// unidades.
///
/// `baja` es el único estatus que NO cuenta: es la única operación que
/// reduce la existencia real. Lavandería, reparación y pendiente de
/// desecho van a `enProceso` — siguen siendo propiedad de RISEG, pero
/// no se pueden entregar.
ExistenciaArticulo plegarExistenciaDeUnidades(Iterable<ArticuloUnidadData> unidades) {
  var disponible = 0;
  var asignado = 0;
  var danado = 0;
  var perdido = 0;
  var enProceso = 0;

  for (final u in unidades) {
    switch (EstatusArticuloUnidad.values.byName(u.estatus)) {
      case EstatusArticuloUnidad.disponible:
        disponible++;
      case EstatusArticuloUnidad.asignado:
        asignado++;
      case EstatusArticuloUnidad.danado:
        danado++;
      case EstatusArticuloUnidad.perdido:
        perdido++;
      case EstatusArticuloUnidad.enLavanderia:
      case EstatusArticuloUnidad.enReparacion:
      case EstatusArticuloUnidad.pendienteDesecho:
        enProceso++;
      case EstatusArticuloUnidad.baja:
        break;
    }
  }

  return ExistenciaArticulo(
    disponible: disponible,
    asignado: asignado,
    danado: danado,
    perdido: perdido,
    enProceso: enProceso,
  );
}

/// Costo promedio ponderado en centavos, derivado únicamente de
/// entradas con `costoUnitario` capturado.
///
/// `null` cuando no hay ninguna: nunca se asume 0 — un artículo sin
/// costo capturado no vale cero, simplemente no se sabe cuánto vale.
/// Las entradas sin costo se ignoran por completo (no entran ni al
/// numerador ni al denominador), para no diluir el promedio de las que
/// sí lo traen.
int? plegarCostoPromedio(Iterable<MovimientoInventarioData> entradas) {
  var cantidadTotal = 0;
  var costoTotal = 0;

  for (final entrada in entradas) {
    final costo = entrada.costoUnitario;
    if (costo == null) continue;
    cantidadTotal += entrada.cantidad;
    costoTotal += entrada.cantidad * costo;
  }

  if (cantidadTotal == 0) return null;
  return (costoTotal / cantidadTotal).round();
}
