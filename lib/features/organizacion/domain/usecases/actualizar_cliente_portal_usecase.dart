import 'package:riseg_one/core/auditoria/diff_evento.dart';
import 'package:drift/drift.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';
import 'package:riseg_one/core/security/credential_cipher.dart';

import '../repositories/cliente_portal_repository.dart';
import 'cliente_portal_validator.dart';
import 'guardar_cliente_portal_resultado.dart';

/// Comparte exactamente las mismas reglas que `CrearClientePortalUseCase`
/// vía `ClientePortalValidator` — mismo patrón que
/// `ActualizarEntidadFiscalUseCase`. Nunca acepta un `clienteId` nuevo:
/// la relación con el Cliente es inmutable, así que se relee del
/// registro existente, nunca del formulario. Un portal archivado es de
/// solo consulta — rechaza la edición sin siquiera validar los campos.
///
/// `borrador.contrasenaNueva == null` deja `contrasenaCifrada` sin
/// tocar (el formulario de edición nunca prellena la contraseña, así
/// que no hay forma de distinguir "no la cambié" de "la borré" salvo
/// por convención: en blanco siempre significa "no tocar"). Solo un
/// valor no vacío la reemplaza.
class ActualizarClientePortalUseCase {
  ActualizarClientePortalUseCase(this._repository, this._validator, this._cipher);

  final ClientePortalRepository _repository;
  final ClientePortalValidator _validator;
  final CredentialCipher _cipher;

  Future<GuardarClientePortalResultado> ejecutar({
    required String id,
    required ClientePortalBorrador borrador,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    if (!motivoEsValido(motivo)) return GuardarClientePortalMotivoRequerido();
    final existente = await _repository.obtenerPorId(id);
    if (existente == null) {
      return GuardarClientePortalErrorInesperado('Portal no encontrado: $id');
    }
    if (existente.cicloVidaRegistro != CicloVidaRegistro.activo.name) {
      return GuardarClientePortalArchivado();
    }

    final validacion = await _validator.validar(clienteId: existente.clienteId, borrador: borrador);
    if (validacion.errores.isNotEmpty) {
      return GuardarClientePortalErroresValidacion(validacion.errores);
    }
    final validado = validacion.resultado!;

    try {
      final contrasenaCifrada =
          validado.contrasenaNueva == null ? null : await _cipher.cifrar(validado.contrasenaNueva!);

      final actualizado = await _repository.actualizar(
        id: id,
        cambios: ClientePortalCompanion(
          nombre: Value(validado.nombre),
          tipo: Value(validado.tipo.name),
          url: Value(validado.url),
          usuario: Value(validado.usuario),
          contrasenaCifrada: contrasenaCifrada == null ? const Value.absent() : Value(contrasenaCifrada),
          observaciones: Value(validado.observaciones),
        ),
        motivo: motivo.trim(),
        actorUsuarioId: actorUsuarioId,
      );
      return GuardarClientePortalExitoso(actualizado);
    } catch (e) {
      return GuardarClientePortalErrorInesperado(e.toString());
    }
  }
}
