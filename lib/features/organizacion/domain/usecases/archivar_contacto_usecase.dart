import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/cliente_repository.dart';

/// Archivar un Contacto siempre está permitido — no hay ninguna entidad
/// que dependa de un Contacto específico en esta etapa (a diferencia de
/// Puesto↔Área). Nunca es un `hard delete`.
class ArchivarContactoUseCase {
  ArchivarContactoUseCase(this._repository);

  final ClienteRepository _repository;

  Future<ContactoData> ejecutar(String contactoId) => _repository.archivarContacto(contactoId);
}
