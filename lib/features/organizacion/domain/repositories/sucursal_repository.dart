import 'package:riseg_one/core/database/app_database.dart';

/// Transacción que compone 3 escrituras (Sucursal + nodo raíz de
/// Ubicación + Almacén General) como una sola unidad atómica — es la
/// razón por la que este repositorio existe y no es un passthrough.
///
/// Recibe los tres códigos visibles ya generados por el llamador — este
/// repositorio no genera códigos, solo persiste (ver `CrearSucursalUseCase`,
/// que es quien "solicita códigos").
abstract interface class SucursalRepository {
  Future<SucursalData> crear({
    required String codigoSucursal,
    required String nombre,
    required String tipoSucursalId,
    required String codigoUbicacionRaiz,
    required String codigoAlmacenGeneral,
  });

  Future<SucursalData?> obtenerPorId(String id);

  Future<List<SucursalData>> listarActivas();
}
