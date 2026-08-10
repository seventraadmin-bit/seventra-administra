import 'package:riseg_one/core/database/app_database.dart';

import '../../domain/usecases/existencia_articulo.dart';

/// Una fila del listado de Artículos — el catálogo más su existencia
/// derivada (nunca guardada, ver el doc comment de
/// `MovimientoInventario`) y el nombre de su categoría ya resuelto.
class ArticuloResumen {
  const ArticuloResumen({required this.articulo, required this.categoriaNombre, required this.existencia});

  final ArticuloData articulo;
  final String categoriaNombre;
  final ExistenciaArticulo existencia;
}

/// Estado del listado de Artículos (Etapa 7A) — mismo shape que
/// cualquier otro listado del proyecto.
class ArticulosState {
  const ArticulosState({this.cargando = true, this.articulos = const [], this.categorias = const [], this.errorCarga});

  final bool cargando;
  final List<ArticuloResumen> articulos;
  final List<CategoriaArticuloData> categorias;
  final String? errorCarga;

  ArticulosState copyWith({
    bool? cargando,
    List<ArticuloResumen>? articulos,
    List<CategoriaArticuloData>? categorias,
    String? errorCarga,
  }) {
    return ArticulosState(
      cargando: cargando ?? this.cargando,
      articulos: articulos ?? this.articulos,
      categorias: categorias ?? this.categorias,
      errorCarga: errorCarga,
    );
  }
}
