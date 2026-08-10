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
  const MovimientoResumenReporte({required this.movimiento, required this.articuloNombre});

  final MovimientoInventarioData movimiento;
  final String articuloNombre;
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
  final String? errorCarga;

  ReportesState copyWith({
    bool? cargando,
    List<ExistenciaResumen>? existencias,
    List<AsignacionResumenReporte>? asignacionesVigentes,
    List<AsignacionResumenReporte>? danadosPerdidos,
    List<DescuentoResumenReporte>? descuentosPendientes,
    List<MovimientoResumenReporte>? movimientosRecientes,
    ResultadoBusquedaInventario? resultadoBusqueda,
    String? consultaBusqueda,
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
      errorCarga: errorCarga,
    );
  }
}
