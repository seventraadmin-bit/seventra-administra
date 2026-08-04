import 'package:riseg_one/core/database/app_database.dart';

/// Campos de la dirección operativa de un Servicio — agrupados porque se
/// usan siempre juntos como una sola unidad al crear el Servicio.
class DireccionOperativaInput {
  const DireccionOperativaInput({
    required this.calle,
    required this.numeroExterior,
    required this.colonia,
    required this.municipioAlcaldia,
    required this.estado,
    required this.codigoPostal,
    this.numeroInterior,
    this.ciudadLocalidad,
    this.pais = 'México',
    this.referencias,
  });

  final String calle;
  final String numeroExterior;
  final String? numeroInterior;
  final String colonia;
  final String municipioAlcaldia;
  final String? ciudadLocalidad;
  final String estado;
  final String codigoPostal;
  final String pais;
  final String? referencias;
}

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
    required DireccionOperativaInput direccionOperativa,
    DateTime? fechaTermino,
    int elementosAutorizados = 0,
    String? responsableClienteContactoId,
    String? observaciones,
  });

  Future<ServicioData?> obtenerPorId(String id);
}
