import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/reportes/domain/usecases/clasificar_egresos_por_origen_usecase.dart' show OrigenEgreso;

/// Filtro de Origen de un Egreso (Etapa 17) — mismo criterio que
/// `ClasificarEgresosPorOrigenUseCase` (Reportes): `Egreso` no tiene
/// columna de origen propia, se deriva por FK inversa
/// (`Compra.egresoId`/`PagoNomina.egresoId`). Filtro en memoria sobre
/// la página ya cargada, nunca una consulta nueva.
enum FiltroOrigenEgreso { todos, nomina, compra, tiempoExtra, deuda, descuentoProgramado, vehiculo, telefonia, manual }

/// Estado del listado de Egresos (Etapa 4K.1) — mismo shape que
/// `IngresosState`, con Origen resuelto en lote (una sola llamada a
/// `ClasificarEgresosPorOrigenUseCase` por carga, nunca por fila).
class EgresosState {
  const EgresosState({
    this.cargando = true,
    this.egresos = const [],
    this.errorCarga,
    this.estatus,
    this.servicioId,
    this.categoriaFinancieraId,
    this.rangoInicio,
    this.rangoFin,
    this.origen = FiltroOrigenEgreso.todos,
    this.formaPago,
    this.origenPorEgreso = const {},
    this.totalNomina = 0,
    this.totalCompra = 0,
    this.totalTiempoExtra = 0,
    this.totalDeuda = 0,
    this.totalDescuentoProgramado = 0,
    this.totalManual = 0,
    this.totalCargadoTarjeta = 0,
  });

  final bool cargando;
  final List<EgresoData> egresos;
  final String? errorCarga;
  final String? estatus;
  final String? servicioId;
  final String? categoriaFinancieraId;
  final DateTime? rangoInicio;
  final DateTime? rangoFin;
  final FiltroOrigenEgreso origen;
  final String? formaPago;

  /// Origen real por Egreso (Etapa 17) — resuelto en una sola llamada a
  /// `ClasificarEgresosPorOrigenUseCase` dentro del controlador.
  final Map<String, OrigenEgreso> origenPorEgreso;

  /// Totales por origen del periodo (Etapa 17, resumen) — mismos
  /// totales que ya expone `ClasificarEgresosPorOrigenUseCase`, nunca
  /// una segunda suma independiente.
  final int totalNomina;
  final int totalCompra;
  final int totalTiempoExtra;
  final int totalDeuda;
  final int totalDescuentoProgramado;
  final int totalManual;
  int get totalPeriodo =>
      totalNomina + totalCompra + totalTiempoExtra + totalDeuda + totalDescuentoProgramado + totalManual;

  /// Etapa 19B — informativo, nunca sumado en `totalPeriodo` (esas
  /// Compras no generan Egreso, así que no son parte de "Egresos del
  /// periodo" en el sentido de filas reales de esta tabla).
  final int totalCargadoTarjeta;

  bool get hayFiltrosActivos =>
      estatus != null ||
      servicioId != null ||
      categoriaFinancieraId != null ||
      rangoInicio != null ||
      rangoFin != null ||
      origen != FiltroOrigenEgreso.todos ||
      formaPago != null;

  List<EgresoData> get egresosFiltrados {
    return egresos.where((e) {
      if (origen != FiltroOrigenEgreso.todos) {
        final origenReal = origenPorEgreso[e.id];
        final coincide = switch (origen) {
          FiltroOrigenEgreso.nomina => origenReal == OrigenEgreso.nomina,
          FiltroOrigenEgreso.compra => origenReal == OrigenEgreso.compra,
          FiltroOrigenEgreso.tiempoExtra => origenReal == OrigenEgreso.tiempoExtra,
          FiltroOrigenEgreso.deuda => origenReal == OrigenEgreso.deuda,
          FiltroOrigenEgreso.descuentoProgramado => origenReal == OrigenEgreso.descuentoProgramado,
          FiltroOrigenEgreso.vehiculo => origenReal == OrigenEgreso.vehiculo,
          FiltroOrigenEgreso.telefonia => origenReal == OrigenEgreso.telefonia,
          FiltroOrigenEgreso.manual => origenReal == OrigenEgreso.manual || origenReal == null,
          FiltroOrigenEgreso.todos => true,
        };
        if (!coincide) return false;
      }
      if (formaPago != null && e.formaPago != formaPago) return false;
      return true;
    }).toList();
  }

  EgresosState copyWith({
    bool? cargando,
    List<EgresoData>? egresos,
    String? errorCarga,
    String? estatus,
    String? servicioId,
    String? categoriaFinancieraId,
    DateTime? rangoInicio,
    DateTime? rangoFin,
    FiltroOrigenEgreso? origen,
    String? formaPago,
    Map<String, OrigenEgreso>? origenPorEgreso,
    int? totalNomina,
    int? totalCompra,
    int? totalTiempoExtra,
    int? totalDeuda,
    int? totalDescuentoProgramado,
    int? totalManual,
    int? totalCargadoTarjeta,
    bool limpiarEstatus = false,
    bool limpiarServicioId = false,
    bool limpiarCategoria = false,
    bool limpiarRango = false,
    bool limpiarFormaPago = false,
  }) {
    return EgresosState(
      cargando: cargando ?? this.cargando,
      egresos: egresos ?? this.egresos,
      errorCarga: errorCarga,
      estatus: limpiarEstatus ? null : (estatus ?? this.estatus),
      servicioId: limpiarServicioId ? null : (servicioId ?? this.servicioId),
      categoriaFinancieraId: limpiarCategoria ? null : (categoriaFinancieraId ?? this.categoriaFinancieraId),
      rangoInicio: limpiarRango ? null : (rangoInicio ?? this.rangoInicio),
      rangoFin: limpiarRango ? null : (rangoFin ?? this.rangoFin),
      origen: origen ?? this.origen,
      formaPago: limpiarFormaPago ? null : (formaPago ?? this.formaPago),
      origenPorEgreso: origenPorEgreso ?? this.origenPorEgreso,
      totalNomina: totalNomina ?? this.totalNomina,
      totalCompra: totalCompra ?? this.totalCompra,
      totalTiempoExtra: totalTiempoExtra ?? this.totalTiempoExtra,
      totalDeuda: totalDeuda ?? this.totalDeuda,
      totalDescuentoProgramado: totalDescuentoProgramado ?? this.totalDescuentoProgramado,
      totalManual: totalManual ?? this.totalManual,
      totalCargadoTarjeta: totalCargadoTarjeta ?? this.totalCargadoTarjeta,
    );
  }
}
