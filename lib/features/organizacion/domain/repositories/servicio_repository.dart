import 'package:riseg_one/core/database/app_database.dart';

import '../shared/direccion_input.dart';

/// Transacción que compone 3 escrituras (Servicio + Dirección operativa
/// principal + nodo raíz de Ubicación) como una sola unidad atómica —
/// no existe un estado "borrador sin dirección": la dirección operativa
/// es obligatoria desde el alta.
///
/// Recibe los códigos visibles ya generados por el llamador (mismo
/// principio que `SucursalRepository`).
abstract interface class ServicioRepository {
  Future<ServicioData> crear({
    required String codigoServicio,
    required String clienteId,
    required String nombre,
    required String tipoServicioId,
    required String sucursalAdministrativaId,
    required DateTime fechaInicio,
    required String codigoUbicacionRaiz,
    required DireccionInput direccionOperativa,
    DateTime? fechaTermino,
    int elementosAutorizados = 0,
    String? responsableClienteContactoId,
    String? observaciones,
  });

  Future<ServicioData?> obtenerPorId(String id);
}
