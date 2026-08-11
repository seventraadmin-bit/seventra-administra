import 'package:riseg_one/core/database/app_database.dart';

import '../usecases/eliminar_area_fisicamente_usecase.dart';

/// Área organizacional — desde la Etapa 4D es una entidad completamente
/// gestionable (alta, edición, activar/desactivar), no solo un catálogo
/// sembrado de solo lectura como sigue siendo `TipoSucursal`. Por eso
/// tiene su propio repositorio en vez de integrarse al
/// `CatalogoRepository` genérico.
abstract interface class AreaRepository {
  /// Recibe el código ya generado por el llamador (mismo patrón que
  /// `SucursalRepository.crear` — este repositorio no genera códigos).
  /// Genera su propio `id`: `CatalogoColumns.id` no tiene `clientDefault`
  /// como sí lo tiene `AuditColumns.id`.
  Future<AreaData> crear({required String codigo, required String nombre, String? descripcion});

  Future<AreaData> actualizar({required String id, required String nombre, String? descripcion});

  Future<AreaData?> obtenerPorId(String id);

  /// Todas las Áreas, activas e inactivas — para el listado propio de
  /// Áreas, que sí necesita mostrar ambas.
  Future<List<AreaData>> listarTodas();

  /// Solo activas — para el selector de Área al crear/editar un Puesto.
  Future<List<AreaData>> listarActivas();

  Future<AreaData> activar(String id);

  /// Operación mecánica — sin validar si hay Puestos activos
  /// relacionados; esa regla vive en `DesactivarAreaUseCase`.
  Future<AreaData> desactivar(String id);

  /// Eliminación física extraordinaria (Etapa 11D) — ver el doc comment
  /// de la implementación para las condiciones exactas.
  Future<EliminarAreaFisicamenteResultado> eliminarFisicamente({
    required String areaId,
    required String motivo,
    String? actorUsuarioId,
  });
}
