import 'package:riseg_one/features/reportes/domain/usecases/obtener_resumen_general_usecase.dart';

import '../reportes_rango_controller.dart';

/// Estado de la pestaña General de Reportes.
class ReportesGeneralState {
  const ReportesGeneralState({
    required this.seleccion,
    this.cargando = true,
    this.resumen,
    this.errorCarga,
  });

  /// El periodo viene del controlador compartido — esta pestaña ya no
  /// tiene un rango propio que se reinicie al cambiar de pestaña.
  final SeleccionRangoReportes seleccion;

  final bool cargando;
  final ResumenGeneralReportes? resumen;
  final String? errorCarga;

  DateTime get rangoInicio => seleccion.rango.inicio;
  DateTime get rangoFin => seleccion.rango.fin;

  /// `true` cuando ninguna sección devolvió datos — ni siquiera un cero
  /// autorizado — es decir, la sesión no tiene ningún permiso de
  /// dominio relevante (`finanzas.ver`/`compras.ver`/`nomina.ver`/
  /// `personal.ver`/`comercial.ver`).
  bool get sinNingunaSeccionAutorizada => resumen?.sinNingunaSeccionAutorizada ?? false;

  ReportesGeneralState copyWith({
    bool? cargando,
    ResumenGeneralReportes? resumen,
    String? errorCarga,
  }) {
    return ReportesGeneralState(
      seleccion: seleccion,
      cargando: cargando ?? this.cargando,
      resumen: resumen ?? this.resumen,
      errorCarga: errorCarga,
    );
  }
}
