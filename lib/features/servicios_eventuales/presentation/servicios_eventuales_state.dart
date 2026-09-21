import '../data/tables/servicio_eventual_table.dart';
import '../domain/usecases/listar_servicios_eventuales_usecase.dart';

/// Estado del listado global de Servicios Eventuales.
///
/// Los KPI se derivan de los renglones ya cargados — no hay una consulta
/// aparte para ellos, así que la tarjeta y la tabla nunca pueden decir
/// cosas distintas.
class ServiciosEventualesState {
  const ServiciosEventualesState({
    this.cargando = true,
    this.renglones = const [],
    this.estatus,
    this.errorCarga,
  });

  final bool cargando;
  final List<RenglonServicioEventual> renglones;
  final EstatusServicioEventual? estatus;
  final String? errorCarga;

  /// Los renglones que cuentan para los indicadores económicos: los
  /// **vigentes**.
  ///
  /// Una venta anulada no es venta. Sumarla inflaba "Total de venta" y
  /// —peor— "Resultado", porque un evento cancelado conserva su venta
  /// y pierde sus costos comprometidos, así que aportaba utilidad pura
  /// que nunca existió. Sigue visible en la tabla (y en el filtro
  /// "Todos") con toda su historia: lo que deja de contar es el
  /// indicador, no el registro.
  List<RenglonServicioEventual> get _vigentes => [
        for (final r in renglones)
          if (r.servicioEventual.estatus != EstatusServicioEventual.cancelado.name) r,
      ];

  /// Suma de TOTALES de venta, no de importes capturados — si no,
  /// el KPI no cuadraría con la suma de la columna ni con las Cuentas
  /// por cobrar en cuanto hubiera un eventual "más IVA".
  int get ventaTotal => _vigentes.fold(0, (suma, r) => suma + r.totalVenta);

  int get costoComprometidoTotal =>
      _vigentes.fold(0, (suma, r) => suma + r.totales.costoComprometido);

  int get resultadoTotal => ventaTotal - costoComprometidoTotal;

  /// Cuántos de los listados quedaron fuera de los tres indicadores.
  int get canceladosExcluidos => renglones.length - _vigentes.length;

  ServiciosEventualesState copyWith({
    bool? cargando,
    List<RenglonServicioEventual>? renglones,
    EstatusServicioEventual? estatus,
    bool limpiarEstatus = false,
    String? errorCarga,
  }) {
    return ServiciosEventualesState(
      cargando: cargando ?? this.cargando,
      renglones: renglones ?? this.renglones,
      estatus: limpiarEstatus ? null : (estatus ?? this.estatus),
      errorCarga: errorCarga,
    );
  }
}
