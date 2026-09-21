import 'package:riseg_one/core/database/app_database.dart';

/// Una fila del listado de Nóminas — el encabezado más los agregados de
/// sus renglones (cantidad de empleados, total a pagar y cuántos ya
/// están pagados), que `Nomina` en sí no almacena.
class NominaResumen {
  const NominaResumen({
    required this.nomina,
    required this.totalEmpleados,
    required this.totalAPagar,
    required this.empleadosPagados,
  });

  final NominaData nomina;
  final int totalEmpleados;
  final int totalAPagar;

  /// Renglones con `estatusPago == 'pagado'` — derivado de
  /// `NominaEmpleadoReporteRow.estatusPago`, nunca de `Nomina.estatus`
  /// (son ejes independientes: una Nómina `cerrada` puede tener
  /// renglones ya pagados parcialmente vía un `PagoNomina` en lote).
  final int empleadosPagados;
}

/// Estado del listado de Nóminas (Etapa 6C) — mismo shape que
/// `IngresosState`/`PagosState`. Etapa 17: filtros de año/estatus,
/// aplicados en memoria sobre `nominas` ya cargado (nunca una consulta
/// nueva por filtro) — el resumen superior refleja el conjunto YA
/// filtrado, nunca el histórico completo.
class NominasState {
  const NominasState({
    this.cargando = true,
    this.nominas = const [],
    this.proximaNomina,
    this.anioFiltro,
    this.estatusFiltro,
    this.errorCarga,
  });

  final bool cargando;
  final List<NominaResumen> nominas;

  /// La Nómina `cerrada` con la fecha de pago más próxima (Etapa 16,
  /// evolución visual) — mismo `ObtenerProximaNominaUseCase` que ya usa
  /// el Dashboard, nunca una segunda fuente de verdad. `null` cuando no
  /// hay ninguna Nómina cerrada pendiente de pago — el resumen superior
  /// simplemente no se muestra en ese caso (nunca un total inventado).
  final NominaResumen? proximaNomina;

  final int? anioFiltro;
  final String? estatusFiltro;
  final String? errorCarga;

  /// Años reales con al menos una Nómina generada — nunca un rango
  /// arbitrario; deriva de `nominas` ya cargado.
  List<int> get aniosDisponibles {
    final anios = {for (final r in nominas) r.nomina.anio}.toList();
    anios.sort((a, b) => b.compareTo(a));
    return anios;
  }

  bool get hayFiltrosActivos => anioFiltro != null || estatusFiltro != null;

  List<NominaResumen> get visibles {
    return nominas.where((r) {
      if (anioFiltro != null && r.nomina.anio != anioFiltro) return false;
      if (estatusFiltro != null && r.nomina.estatus != estatusFiltro) return false;
      return true;
    }).toList();
  }

  int get resumenNominasDelPeriodo => visibles.length;
  int get resumenTotalNomina => visibles.fold(0, (s, r) => s + r.totalAPagar);
  int get resumenEmpleadosPagados => visibles.fold(0, (s, r) => s + r.empleadosPagados);
  int get resumenEmpleadosConsiderados => visibles.fold(0, (s, r) => s + r.totalEmpleados);

  /// Nóminas del conjunto filtrado que todavía no llegan a `pagada` —
  /// deliberadamente una cuenta de Nóminas (no de renglones): "cuántos
  /// periodos siguen pendientes de cerrarse o pagarse por completo".
  int get resumenNominasPendientes => visibles.where((r) => r.nomina.estatus != 'pagada').length;

  NominasState copyWith({
    bool? cargando,
    List<NominaResumen>? nominas,
    NominaResumen? proximaNomina,
    bool limpiarProximaNomina = false,
    int? anioFiltro,
    String? estatusFiltro,
    bool limpiarAnioFiltro = false,
    bool limpiarEstatusFiltro = false,
    String? errorCarga,
  }) {
    return NominasState(
      cargando: cargando ?? this.cargando,
      nominas: nominas ?? this.nominas,
      proximaNomina: limpiarProximaNomina ? null : (proximaNomina ?? this.proximaNomina),
      anioFiltro: limpiarAnioFiltro ? null : (anioFiltro ?? this.anioFiltro),
      estatusFiltro: limpiarEstatusFiltro ? null : (estatusFiltro ?? this.estatusFiltro),
      errorCarga: errorCarga,
    );
  }
}
