import 'package:riseg_one/features/reportes/domain/usecases/obtener_resumen_general_usecase.dart';

/// Estado de la pestaña General de Reportes (Etapa 12A).
class ReportesGeneralState {
  const ReportesGeneralState({
    this.cargando = true,
    this.rangoInicio,
    this.rangoFin,
    this.resumen,
    this.errorCarga,
  });

  final bool cargando;
  final DateTime? rangoInicio;
  final DateTime? rangoFin;
  final ResumenGeneralReportes? resumen;
  final String? errorCarga;

  /// `true` cuando ninguna sección devolvió datos — ni siquiera un cero
  /// autorizado — es decir, la sesión no tiene ningún permiso de
  /// dominio relevante (`finanzas.ver`/`compras.ver`/`nomina.ver`/
  /// `personal.ver`/`comercial.ver`).
  bool get sinNingunaSeccionAutorizada {
    final r = resumen;
    if (r == null) return false;
    return r.totalIngresos == null &&
        r.totalEgresos == null &&
        r.resultadoOperativo == null &&
        r.totalComprasPeriodo == null &&
        r.totalNominaPagadaPeriodo == null &&
        r.personalActivoActual == null &&
        r.serviciosActivosActual == null;
  }

  ReportesGeneralState copyWith({
    bool? cargando,
    DateTime? rangoInicio,
    DateTime? rangoFin,
    ResumenGeneralReportes? resumen,
    String? errorCarga,
  }) {
    return ReportesGeneralState(
      cargando: cargando ?? this.cargando,
      rangoInicio: rangoInicio ?? this.rangoInicio,
      rangoFin: rangoFin ?? this.rangoFin,
      resumen: resumen ?? this.resumen,
      errorCarga: errorCarga,
    );
  }
}
