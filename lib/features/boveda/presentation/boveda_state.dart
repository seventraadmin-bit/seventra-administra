import 'package:riseg_one/core/database/app_database.dart';

class BovedaState {
  const BovedaState({
    this.cargando = true,
    this.credenciales = const [],
    this.tipo,
    this.soloActivos = true,
    this.texto,
    this.errorCarga,
  });

  final bool cargando;
  final List<BovedaCredencialData> credenciales;
  final String? tipo;
  final bool soloActivos;
  final String? texto;
  final String? errorCarga;

  BovedaState copyWith({
    bool? cargando,
    List<BovedaCredencialData>? credenciales,
    String? tipo,
    bool limpiarTipo = false,
    bool? soloActivos,
    String? texto,
    bool limpiarTexto = false,
    String? errorCarga,
  }) {
    return BovedaState(
      cargando: cargando ?? this.cargando,
      credenciales: credenciales ?? this.credenciales,
      tipo: limpiarTipo ? null : (tipo ?? this.tipo),
      soloActivos: soloActivos ?? this.soloActivos,
      texto: limpiarTexto ? null : (texto ?? this.texto),
      errorCarga: errorCarga,
    );
  }
}
