import 'package:riseg_one/core/error/failure.dart';
import 'package:riseg_one/core/error/result.dart';

import '../repositories/cliente_repository.dart';
import 'cliente_expediente_data.dart';

/// Ensambla el expediente completo de un Cliente (Cliente + dirección de
/// referencia + contactos activos) — mismo patrón que
/// `ObtenerExpedienteSucursalUseCase`.
class ObtenerExpedienteClienteUseCase {
  ObtenerExpedienteClienteUseCase(this._repository);

  final ClienteRepository _repository;

  Future<Result<ClienteExpedienteData>> ejecutar(String clienteId) async {
    final cliente = await _repository.obtenerPorId(clienteId);
    if (cliente == null) {
      return Result.failure(NotFoundFailure('Cliente no encontrado: $clienteId'));
    }

    final direccionReferencia = await _repository.obtenerDireccionReferencia(clienteId);
    final contactos = await _repository.obtenerContactos(clienteId);

    return Result.ok(
      ClienteExpedienteData(cliente: cliente, direccionReferencia: direccionReferencia, contactos: contactos),
    );
  }
}
