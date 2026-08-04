import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/data/tables/ubicacion_table.dart';

/// Un nodo del árbol de [Ubicacion] junto con sus hijos ya ensamblados.
///
/// No es un simple duplicado de `UbicacionData` — es una estructura real
/// (anidada) que Drift no genera por sí solo, así que sí se justifica
/// como un tipo propio.
class UbicacionArbol {
  const UbicacionArbol({required this.nodo, required this.hijos});

  final UbicacionData nodo;
  final List<UbicacionArbol> hijos;
}

/// Operaciones sobre el árbol de ubicaciones físicas.
///
/// Sin columna `ubicacionRaizId` en `Sucursal`/`Servicio`: la raíz se
/// resuelve aquí por consulta. La creación de la raíz + Almacén General
/// vive en `SucursalRepository` (transaccional junto con la Sucursal
/// misma) — este repositorio se ocupa de las operaciones que sí son
/// puramente de Ubicación: crear un hijo, mover, consultar el árbol.
abstract interface class UbicacionRepository {
  Future<UbicacionData?> obtenerPorId(String id);

  Future<UbicacionData?> obtenerRaizDeSucursal(String sucursalId);

  Future<UbicacionData?> obtenerRaizDeServicio(String servicioId);

  Future<List<UbicacionData>> obtenerHijos(String parentId);

  Future<UbicacionArbol> obtenerArbol(String raizId);

  Future<UbicacionData> crearHijo({
    required String codigo,
    required String nombre,
    required TipoUbicacion tipo,
    required String parentId,
  });

  /// Operación mecánica — sin validar profundidad/ciclos/raíz-inmóvil,
  /// eso vive en `MoverUbicacionUseCase`. Sí impide moverse a sí mismo
  /// como propio padre (`ubicacionId == nuevoParentId`), por ser un
  /// error de invocación, no una regla de negocio.
  Future<void> moverA({required String ubicacionId, required String nuevoParentId});
}
