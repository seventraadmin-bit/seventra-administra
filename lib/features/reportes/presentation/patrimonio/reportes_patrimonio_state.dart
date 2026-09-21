import 'package:riseg_one/features/reportes/domain/analitica/obtener_analisis_patrimonio_usecase.dart';

import '../reportes_rango_controller.dart';

/// Estado de la pestaña Patrimonio y bajas.
///
/// El rango compartido de Reportes acota la **fecha de baja**: todo lo
/// que se ve pertenece a las bajas conciliadas dentro del periodo. Los
/// estados físicos, en cambio, son de HOY — la pantalla lo dice.
class ReportesPatrimonioState {
  const ReportesPatrimonioState({
    required this.seleccion,
    this.filtro = const FiltroPatrimonio(),
    this.cargando = true,
    this.analisis,
    this.errorCarga,
  });

  final SeleccionRangoReportes seleccion;
  final FiltroPatrimonio filtro;
  final bool cargando;
  final AnalisisPatrimonio? analisis;
  final String? errorCarga;

  DateTime get rangoInicio => seleccion.rango.inicio;
  DateTime get rangoFin => seleccion.rango.fin;

  ReportesPatrimonioState copyWith({
    FiltroPatrimonio? filtro,
    bool? cargando,
    AnalisisPatrimonio? analisis,
    String? errorCarga,
  }) {
    return ReportesPatrimonioState(
      seleccion: seleccion,
      filtro: filtro ?? this.filtro,
      cargando: cargando ?? this.cargando,
      analisis: analisis ?? this.analisis,
      errorCarga: errorCarga,
    );
  }
}
