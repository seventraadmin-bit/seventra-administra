import 'package:riseg_one/core/database/app_database.dart';

/// Origen de un Ingreso (Etapa 17) — deriva directo de `pagoId`
/// (nullable, único): no existe una columna "origen" separada, el
/// discriminador YA ES `pagoId != null`. Filtro en memoria sobre la
/// página ya cargada, nunca una consulta nueva.
enum FiltroOrigenIngreso { todos, automatico, manual }

/// Estado del listado de Ingresos (Etapa 4K.1) — mismo shape que
/// `PagosState`, con Origen/Forma de pago como filtros en memoria
/// (el repositorio no los soporta como parámetro — filtrar sobre la
/// página ya cargada no es un N+1, es agregación local).
class IngresosState {
  const IngresosState({
    this.cargando = true,
    this.ingresos = const [],
    this.errorCarga,
    this.estatus,
    this.servicioId,
    this.rangoInicio,
    this.rangoFin,
    this.origen = FiltroOrigenIngreso.todos,
    this.formaPago,
    this.folioPagoPorIngreso = const {},
  });

  final bool cargando;
  final List<IngresoData> ingresos;
  final String? errorCarga;
  final String? estatus;
  final String? servicioId;
  final DateTime? rangoInicio;
  final DateTime? rangoFin;
  final FiltroOrigenIngreso origen;
  final String? formaPago;

  /// Folio del Pago de origen por Ingreso automático (Etapa 17) —
  /// resuelto en una sola consulta en lote (`PagoRepository.listar()`)
  /// dentro del controlador, nunca una consulta por fila.
  final Map<String, String> folioPagoPorIngreso;

  bool get hayFiltrosActivos =>
      estatus != null ||
      servicioId != null ||
      rangoInicio != null ||
      rangoFin != null ||
      origen != FiltroOrigenIngreso.todos ||
      formaPago != null;

  List<IngresoData> get ingresosFiltrados {
    return ingresos.where((i) {
      if (origen == FiltroOrigenIngreso.automatico && i.pagoId == null) return false;
      if (origen == FiltroOrigenIngreso.manual && i.pagoId != null) return false;
      if (formaPago != null && i.formaPago != formaPago) return false;
      return true;
    }).toList();
  }

  IngresosState copyWith({
    bool? cargando,
    List<IngresoData>? ingresos,
    String? errorCarga,
    String? estatus,
    String? servicioId,
    DateTime? rangoInicio,
    DateTime? rangoFin,
    FiltroOrigenIngreso? origen,
    String? formaPago,
    Map<String, String>? folioPagoPorIngreso,
    bool limpiarEstatus = false,
    bool limpiarServicioId = false,
    bool limpiarRango = false,
    bool limpiarFormaPago = false,
  }) {
    return IngresosState(
      cargando: cargando ?? this.cargando,
      ingresos: ingresos ?? this.ingresos,
      errorCarga: errorCarga,
      estatus: limpiarEstatus ? null : (estatus ?? this.estatus),
      servicioId: limpiarServicioId ? null : (servicioId ?? this.servicioId),
      rangoInicio: limpiarRango ? null : (rangoInicio ?? this.rangoInicio),
      rangoFin: limpiarRango ? null : (rangoFin ?? this.rangoFin),
      origen: origen ?? this.origen,
      formaPago: limpiarFormaPago ? null : (formaPago ?? this.formaPago),
      folioPagoPorIngreso: folioPagoPorIngreso ?? this.folioPagoPorIngreso,
    );
  }
}
