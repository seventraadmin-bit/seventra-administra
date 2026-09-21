import 'package:riseg_one/features/reportes/domain/usecases/obtener_resumen_nomina_usecase.dart';
import 'package:riseg_one/features/reportes/domain/usecases/obtener_resumen_personal_usecase.dart';

import '../reportes_rango_controller.dart';

/// Estado de la pestaña Personal · Nómina de Reportes.
///
/// [resumenPersonal]/[resumenNomina] son `null` cuando la sesión no
/// tiene el permiso de esa subsección (`personal.ver`/`nomina.ver`) —
/// nunca se calculan ni se consultan en ese caso (guardia real en el
/// controller, antes de tocar cualquier repositorio).
class ReportesPersonalNominaState {
  const ReportesPersonalNominaState({
    required this.seleccion,
    this.cargando = true,
    this.resumenPersonal,
    this.resumenNomina,
    this.errorCarga,
  });

  final SeleccionRangoReportes seleccion;
  final bool cargando;
  final ResumenPersonalReportes? resumenPersonal;
  final ResumenNominaReportes? resumenNomina;
  final String? errorCarga;

  DateTime get rangoInicio => seleccion.rango.inicio;
  DateTime get rangoFin => seleccion.rango.fin;

  ReportesPersonalNominaState copyWith({
    bool? cargando,
    ResumenPersonalReportes? resumenPersonal,
    ResumenNominaReportes? resumenNomina,
    String? errorCarga,
  }) {
    return ReportesPersonalNominaState(
      seleccion: seleccion,
      cargando: cargando ?? this.cargando,
      resumenPersonal: resumenPersonal ?? this.resumenPersonal,
      resumenNomina: resumenNomina ?? this.resumenNomina,
      errorCarga: errorCarga,
    );
  }
}
