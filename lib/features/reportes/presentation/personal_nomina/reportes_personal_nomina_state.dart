import 'package:riseg_one/features/reportes/domain/usecases/obtener_resumen_nomina_usecase.dart';
import 'package:riseg_one/features/reportes/domain/usecases/obtener_resumen_personal_usecase.dart';

/// Estado de la pestaña Personal · Nómina de Reportes (Etapa 12B).
///
/// [resumenPersonal]/[resumenNomina] son `null` cuando la sesión no
/// tiene el permiso de esa subsección (`personal.ver`/`nomina.ver`) —
/// nunca se calculan ni se consultan en ese caso (guardia real en el
/// controller, antes de tocar cualquier repositorio).
class ReportesPersonalNominaState {
  const ReportesPersonalNominaState({
    this.cargando = true,
    this.rangoInicio,
    this.rangoFin,
    this.resumenPersonal,
    this.resumenNomina,
    this.errorCarga,
  });

  final bool cargando;
  final DateTime? rangoInicio;
  final DateTime? rangoFin;
  final ResumenPersonalReportes? resumenPersonal;
  final ResumenNominaReportes? resumenNomina;
  final String? errorCarga;

  ReportesPersonalNominaState copyWith({
    bool? cargando,
    DateTime? rangoInicio,
    DateTime? rangoFin,
    ResumenPersonalReportes? resumenPersonal,
    ResumenNominaReportes? resumenNomina,
    String? errorCarga,
  }) {
    return ReportesPersonalNominaState(
      cargando: cargando ?? this.cargando,
      rangoInicio: rangoInicio ?? this.rangoInicio,
      rangoFin: rangoFin ?? this.rangoFin,
      resumenPersonal: resumenPersonal ?? this.resumenPersonal,
      resumenNomina: resumenNomina ?? this.resumenNomina,
      errorCarga: errorCarga,
    );
  }
}
