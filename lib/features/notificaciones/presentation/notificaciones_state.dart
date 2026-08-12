import '../domain/usecases/obtener_notificaciones_usecase.dart';

class NotificacionesState {
  const NotificacionesState({this.cargando = true, this.resultados, this.errorCarga});

  final bool cargando;
  final ResultadosNotificaciones? resultados;
  final String? errorCarga;

  int get total => resultados?.total ?? 0;

  NotificacionesState copyWith({bool? cargando, ResultadosNotificaciones? resultados, String? errorCarga}) {
    return NotificacionesState(
      cargando: cargando ?? this.cargando,
      resultados: resultados ?? this.resultados,
      errorCarga: errorCarga,
    );
  }
}
