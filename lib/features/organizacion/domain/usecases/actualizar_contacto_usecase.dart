import 'package:riseg_one/core/auditoria/diff_evento.dart';
import 'package:drift/drift.dart';
import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/cliente_repository.dart';
import 'contacto_validator.dart';
import 'guardar_contacto_resultado.dart';

/// Comparte exactamente las mismas reglas que `AgregarContactoUseCase`
/// vía `ContactoValidator` — mismo patrón que `ActualizarPuestoUseCase`.
class ActualizarContactoUseCase {
  ActualizarContactoUseCase(this._repository);

  final ClienteRepository _repository;

  /// [motivo] obligatorio: corregir los datos de contacto de un Cliente
  /// es un cambio que tiene que poder explicarse. Teléfono y correo
  /// llegan a la bitácora enmascarados.
  Future<GuardarContactoResultado> ejecutar({
    required String id,
    required ContactoBorrador borrador,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    if (!motivoEsValido(motivo)) return GuardarContactoMotivoRequerido();
    final validacion = ContactoValidator.validar(borrador);
    if (validacion.errores.isNotEmpty) {
      return GuardarContactoErroresValidacion(validacion.errores);
    }
    final validado = validacion.resultado!;

    try {
      final contacto = await _repository.actualizarContacto(
        id: id,
        cambios: ContactoCompanion(
          nombre: Value(validado.nombre),
          tipo: Value(validado.tipo.name),
          puesto: Value(validado.puesto),
          telefono: Value(validado.telefono),
          correo: Value(validado.correo),
          esPrincipal: Value(validado.esPrincipal),
        ),
        motivo: motivo.trim(),
        actorUsuarioId: actorUsuarioId,
      );
      return GuardarContactoExitoso(contacto);
    } catch (e) {
      return GuardarContactoErrorInesperado(e.toString());
    }
  }
}
