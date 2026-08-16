import 'package:drift/drift.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/security/credential_cipher.dart';

import '../repositories/cliente_portal_repository.dart';
import 'cliente_portal_validator.dart';
import 'guardar_cliente_portal_resultado.dart';

/// Alta de un portal del Cliente (Etapa 15) — única fuente de verdad
/// nueva para nombre/URL/usuario/contraseña/observaciones de portal,
/// reemplazando la captura duplicada que antes vivía en cada
/// Configuración de cobro. `contrasenaNueva`, si viene, se cifra con
/// [CredentialCipher] antes de persistirse — nunca en texto plano.
class CrearClientePortalUseCase {
  CrearClientePortalUseCase(this._repository, this._validator, this._cipher);

  final ClientePortalRepository _repository;
  final ClientePortalValidator _validator;
  final CredentialCipher _cipher;

  Future<GuardarClientePortalResultado> ejecutar({
    required String clienteId,
    required ClientePortalBorrador borrador,
  }) async {
    final validacion = await _validator.validar(clienteId: clienteId, borrador: borrador);
    if (validacion.errores.isNotEmpty) {
      return GuardarClientePortalErroresValidacion(validacion.errores);
    }
    final validado = validacion.resultado!;

    try {
      final contrasenaCifrada =
          validado.contrasenaNueva == null ? null : await _cipher.cifrar(validado.contrasenaNueva!);

      final portal = await _repository.crear(
        ClientePortalCompanion.insert(
          clienteId: clienteId,
          nombre: validado.nombre,
          tipo: validado.tipo.name,
          url: Value(validado.url),
          usuario: Value(validado.usuario),
          contrasenaCifrada: Value(contrasenaCifrada),
          observaciones: Value(validado.observaciones),
        ),
      );
      return GuardarClientePortalExitoso(portal);
    } catch (e) {
      return GuardarClientePortalErrorInesperado(e.toString());
    }
  }
}
