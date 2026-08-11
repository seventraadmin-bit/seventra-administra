import 'package:riseg_one/core/database/app_database.dart';

/// Estado del listado de Telefonía (Etapa 9A) — mismo shape que
/// `VehiculosState`.
class TelefoniaState {
  const TelefoniaState({this.cargando = true, this.lineas = const [], this.errorCarga});

  final bool cargando;
  final List<LineaTelefonicaData> lineas;
  final String? errorCarga;

  TelefoniaState copyWith({bool? cargando, List<LineaTelefonicaData>? lineas, String? errorCarga}) {
    return TelefoniaState(
      cargando: cargando ?? this.cargando,
      lineas: lineas ?? this.lineas,
      errorCarga: errorCarga,
    );
  }
}
