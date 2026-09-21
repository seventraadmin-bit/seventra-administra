import 'package:riseg_one/core/database/app_database.dart';

import '../../domain/usecases/buscar_inventario_usecase.dart';
import '../../domain/usecases/existencia_articulo.dart';

/// Una fila de "Existencias actuales" — Artículo + categoría ya
/// resueltos + costo promedio ponderado cuando puede derivarse de
/// forma consistente (`null` para Artículos con talla/variante: un
/// solo número no representaría bien costos que pueden diferir por
/// talla — ver el doc comment de `ReportesController`).
class ExistenciaResumen {
  const ExistenciaResumen({
    required this.articulo,
    required this.categoriaNombre,
    required this.existencia,
    required this.costoPromedio,
  });

  final ArticuloData articulo;
  final String categoriaNombre;
  final ExistenciaArticulo existencia;
  final int? costoPromedio;
}

/// Una fila de Asignación ya resuelta para reporte — cubre tanto
/// "vigentes" (pendientes de devolución) como "dañadas/perdidas".
class AsignacionResumenReporte {
  const AsignacionResumenReporte({
    required this.asignacion,
    required this.articuloDetalle,
    required this.destino,
  });

  final AsignacionData asignacion;
  final String articuloDetalle;
  final String destino;
}

class DescuentoResumenReporte {
  const DescuentoResumenReporte({
    required this.descuento,
    required this.empleadoNombre,
    required this.articuloDetalle,
  });

  final DescuentoInventarioData descuento;
  final String empleadoNombre;
  final String articuloDetalle;
}

class MovimientoResumenReporte {
  const MovimientoResumenReporte({
    required this.movimiento,
    required this.articuloDetalle,
    this.actorNombre,
  });

  final MovimientoInventarioData movimiento;

  /// Nombre del Artículo + talla/código de unidad cuando aplica (Etapa
  /// 18) — mismo criterio de `detalleArticulo` en `ReportesController`,
  /// resuelto sobre los mismos mapas ya cargados en memoria.
  final String articuloDetalle;

  /// Nombre de quien registró el movimiento (Etapa 18), resuelto en
  /// bloque sobre `UsuarioRepository.listar()` — `null` si el
  /// movimiento no tiene `actorUsuarioId` (legado o automático).
  final String? actorNombre;
}

class ReportesState {
  const ReportesState({
    this.cargando = true,
    this.existencias = const [],
    this.asignacionesVigentes = const [],
    this.danadosPerdidos = const [],
    this.descuentosPendientes = const [],
    this.movimientosRecientes = const [],
    this.resultadoBusqueda = ResultadoBusquedaInventario.vacia,
    this.consultaBusqueda = '',
    this.movimientoTipoFiltro,
    this.movimientoArticuloFiltro,
    this.errorCarga,
  });

  final bool cargando;
  final List<ExistenciaResumen> existencias;
  final List<AsignacionResumenReporte> asignacionesVigentes;
  final List<AsignacionResumenReporte> danadosPerdidos;
  final List<DescuentoResumenReporte> descuentosPendientes;
  final List<MovimientoResumenReporte> movimientosRecientes;
  final ResultadoBusquedaInventario resultadoBusqueda;
  final String consultaBusqueda;

  /// Filtros del Historial (Etapa 18) — en memoria, sobre
  /// `movimientosRecientes` YA cargado (los últimos 100, ver el doc
  /// comment de `ReportesController`): nunca una consulta nueva, y
  /// nunca reinterpretan el límite de 100 — solo acotan qué parte de
  /// esos mismos 100 se muestra.
  final String? movimientoTipoFiltro;
  final String? movimientoArticuloFiltro;
  final String? errorCarga;

  bool get hayFiltrosMovimientosActivos => movimientoTipoFiltro != null || movimientoArticuloFiltro != null;

  List<MovimientoResumenReporte> get movimientosVisibles {
    return movimientosRecientes.where((r) {
      if (movimientoTipoFiltro != null && r.movimiento.tipoMovimiento != movimientoTipoFiltro) return false;
      if (movimientoArticuloFiltro != null && r.movimiento.articuloId != movimientoArticuloFiltro) return false;
      return true;
    }).toList();
  }

  /// Resumen superior (Etapa 18) — agregado sobre los mismos datos ya
  /// cargados, nunca una segunda fuente de verdad.
  int get resumenDisponible => existencias.fold(0, (s, r) => s + r.existencia.disponible);
  int get resumenAsignado => existencias.fold(0, (s, r) => s + r.existencia.asignado);
  int get resumenDanadoPerdido => existencias.fold(0, (s, r) => s + r.existencia.danado + r.existencia.perdido);

  /// Unidades que siguen siendo de RISEG pero fuera de circulación:
  /// lavandería, reparación o pendientes de desecho. Cuentan en la
  /// existencia (y en el valor), no en la disponibilidad.
  int get resumenEnProceso => existencias.fold(0, (s, r) => s + r.existencia.enProceso);
  int get resumenAsignacionesVigentes => asignacionesVigentes.length;

  /// Valor total del inventario — SOLO cuando todo artículo con
  /// existencia real (`total > 0`) y sin variante tiene un costo
  /// promedio conocido; si a alguno le falta, el total sería engañoso
  /// (pedido explícito: "no mostrar valor si una parte importante del
  /// inventario no tiene costo"). Los artículos con variante se
  /// excluyen de la verificación de cobertura (su costo se omite por
  /// diseño, no por dato faltante) y no aportan al total.
  int? get resumenValorInventario {
    var total = 0;
    for (final r in existencias) {
      if (r.articulo.manejaVariante) continue;
      if (r.existencia.total <= 0) continue;
      if (r.costoPromedio == null) return null;
      total += r.costoPromedio! * r.existencia.total;
    }
    return total;
  }

  ReportesState copyWith({
    bool? cargando,
    List<ExistenciaResumen>? existencias,
    List<AsignacionResumenReporte>? asignacionesVigentes,
    List<AsignacionResumenReporte>? danadosPerdidos,
    List<DescuentoResumenReporte>? descuentosPendientes,
    List<MovimientoResumenReporte>? movimientosRecientes,
    ResultadoBusquedaInventario? resultadoBusqueda,
    String? consultaBusqueda,
    String? movimientoTipoFiltro,
    String? movimientoArticuloFiltro,
    bool limpiarMovimientoTipoFiltro = false,
    bool limpiarMovimientoArticuloFiltro = false,
    String? errorCarga,
  }) {
    return ReportesState(
      cargando: cargando ?? this.cargando,
      existencias: existencias ?? this.existencias,
      asignacionesVigentes: asignacionesVigentes ?? this.asignacionesVigentes,
      danadosPerdidos: danadosPerdidos ?? this.danadosPerdidos,
      descuentosPendientes: descuentosPendientes ?? this.descuentosPendientes,
      movimientosRecientes: movimientosRecientes ?? this.movimientosRecientes,
      resultadoBusqueda: resultadoBusqueda ?? this.resultadoBusqueda,
      consultaBusqueda: consultaBusqueda ?? this.consultaBusqueda,
      movimientoTipoFiltro: limpiarMovimientoTipoFiltro ? null : (movimientoTipoFiltro ?? this.movimientoTipoFiltro),
      movimientoArticuloFiltro:
          limpiarMovimientoArticuloFiltro ? null : (movimientoArticuloFiltro ?? this.movimientoArticuloFiltro),
      errorCarga: errorCarga,
    );
  }
}
