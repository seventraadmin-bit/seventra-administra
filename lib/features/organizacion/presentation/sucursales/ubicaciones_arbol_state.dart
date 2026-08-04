import 'package:riseg_one/features/organizacion/domain/repositories/ubicacion_repository.dart';

/// Estado del árbol de Ubicaciones de una Sucursal.
///
/// `expandidos` es puramente de presentación (qué nodos se ven abiertos)
/// — no existe en el dominio, se reinicia a "todo expandido" cada vez
/// que el árbol se vuelve a cargar (tras agregar o mover un nodo).
class UbicacionesArbolState {
  const UbicacionesArbolState({
    this.cargando = true,
    this.arbol,
    this.errorCarga,
    this.expandidos = const {},
    this.procesando = false,
  });

  final bool cargando;
  final UbicacionArbol? arbol;
  final String? errorCarga;
  final Set<String> expandidos;

  /// `true` mientras una acción de agregar/mover está en curso — bloquea
  /// que se dispare una segunda mientras la primera no ha resuelto.
  final bool procesando;

  UbicacionesArbolState copyWith({
    bool? cargando,
    UbicacionArbol? arbol,
    String? errorCarga,
    Set<String>? expandidos,
    bool? procesando,
  }) {
    return UbicacionesArbolState(
      cargando: cargando ?? this.cargando,
      arbol: arbol ?? this.arbol,
      errorCarga: errorCarga,
      expandidos: expandidos ?? this.expandidos,
      procesando: procesando ?? this.procesando,
    );
  }
}
