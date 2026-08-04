import 'package:riseg_one/core/database/app_database.dart';

/// Se justifica por dos reglas propias: normalización + verificación de
/// unicidad de RFC antes de persistir, y filtrado consistente por
/// `cicloVidaRegistro`.
abstract interface class ClienteRepository {
  /// [rfcNormalizado] ya debe venir en mayúsculas y sin espacios — este
  /// repositorio no normaliza, eso es responsabilidad del caso de uso.
  Future<bool> existeRfc(String rfcNormalizado);

  Future<ClienteData> crear(ClienteCompanion datos);

  Future<ClienteData?> obtenerPorId(String id);

  Future<List<ClienteData>> listarActivos();

  Future<ContactoData> agregarContacto(ContactoCompanion datos);

  Future<List<ContactoData>> obtenerContactos(String clienteId);
}
