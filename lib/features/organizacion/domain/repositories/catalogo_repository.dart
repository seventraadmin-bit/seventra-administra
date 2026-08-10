/// Fila de un catálogo abierto (`TipoSucursal`, `Industria`, ...) ya
/// desacoplada del tipo `Data` que genera Drift para cada tabla — la UI
/// nunca debe importar `app_database.dart` solo para mostrar un selector.
class CatalogoItem {
  const CatalogoItem({required this.id, required this.codigo, required this.nombre});

  final String id;
  final String codigo;
  final String nombre;
}

/// Lecturas de catálogos abiertos y editables de Organización.
///
/// Los catálogos son datos de referencia sembrados (ver
/// `core/database/seed/seed_data.dart`), no se crean desde una pantalla
/// todavía — por eso esta interfaz solo expone lecturas.
abstract interface class CatalogoRepository {
  Future<List<CatalogoItem>> listarTiposSucursal();

  Future<List<CatalogoItem>> listarTiposServicio();

  Future<List<CatalogoItem>> listarModalidadesTurno();

  Future<List<CatalogoItem>> listarFrecuenciasCobro();

  Future<List<CatalogoItem>> listarBancos();
}
