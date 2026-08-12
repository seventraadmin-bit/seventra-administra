import '../domain/usecases/buscar_global_usecase.dart';

/// Estado de Búsqueda global (Etapa 14A). `resultados` es `null`
/// mientras no se ha completado ninguna búsqueda todavía (texto vacío
/// o con menos de 2 caracteres) — distinto de una `ResultadosBusquedaGlobal`
/// ya resuelta pero sin coincidencias (`sinResultados == true`).
class BusquedaState {
  const BusquedaState({this.texto = '', this.resultados, this.cargando = false});

  final String texto;
  final ResultadosBusquedaGlobal? resultados;
  final bool cargando;

  BusquedaState copyWith({String? texto, ResultadosBusquedaGlobal? resultados, bool? cargando}) {
    return BusquedaState(
      texto: texto ?? this.texto,
      resultados: resultados ?? this.resultados,
      cargando: cargando ?? this.cargando,
    );
  }
}
