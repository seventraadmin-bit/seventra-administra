import 'package:drift/drift.dart';
import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/cliente_repository.dart';
import 'contacto_validator.dart';
import 'guardar_contacto_resultado.dart';

class AgregarContactoUseCase {
  AgregarContactoUseCase(this._repository);

  final ClienteRepository _repository;

  Future<GuardarContactoResultado> ejecutar({
    required String clienteId,
    required ContactoBorrador borrador,
    String? actorUsuarioId,
  }) async {
    final validacion = ContactoValidator.validar(borrador);
    if (validacion.errores.isNotEmpty) {
      return GuardarContactoErroresValidacion(validacion.errores);
    }
    final validado = validacion.resultado!;

    try {
      final contacto = await _repository.agregarContacto(
        ContactoCompanion.insert(
          clienteId: clienteId,
          nombre: validado.nombre,
          tipo: validado.tipo.name,
          puesto: Value(validado.puesto),
          telefono: Value(validado.telefono),
          correo: Value(validado.correo),
          esPrincipal: Value(validado.esPrincipal),
        ),
        actorUsuarioId: actorUsuarioId,
      );
      return GuardarContactoExitoso(contacto);
    } catch (e) {
      return GuardarContactoErrorInesperado(e.toString());
    }
  }
}
