import 'package:riseg_one/core/database/app_database.dart';

/// Estado del listado de Categorías financieras (Etapa 4K.1) — mismo
/// shape que `AreasListState`.
class CategoriasListState {
  const CategoriasListState({this.cargando = true, this.categorias = const [], this.errorCarga});

  final bool cargando;
  final List<CategoriaFinancieraData> categorias;
  final String? errorCarga;

  CategoriasListState copyWith({
    bool? cargando,
    List<CategoriaFinancieraData>? categorias,
    String? errorCarga,
  }) {
    return CategoriasListState(
      cargando: cargando ?? this.cargando,
      categorias: categorias ?? this.categorias,
      errorCarga: errorCarga,
    );
  }
}
