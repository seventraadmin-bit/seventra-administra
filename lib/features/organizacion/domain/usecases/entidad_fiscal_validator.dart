import 'package:riseg_one/core/database/tables/audit_columns.dart';
import 'package:riseg_one/core/validation/rfc_validator.dart';

import '../repositories/cliente_repository.dart';
import '../repositories/entidad_fiscal_repository.dart';
import 'entidad_fiscal_errors.dart';

/// Datos de Entidad fiscal tal como llegan del formulario — sin
/// validar. No incluye `clienteId`: la relación con el Cliente es
/// inmutable después de creada, así que nunca es parte de lo que un
/// formulario de edición puede cambiar (ver `validar`).
class EntidadFiscalBorrador {
  const EntidadFiscalBorrador({required this.razonSocial, required this.rfc});

  final String razonSocial;
  final String rfc;
}

/// Entidad fiscal ya validada y normalizada — lista para persistir.
class EntidadFiscalValidada {
  const EntidadFiscalValidada({required this.razonSocial, required this.rfc});

  final String razonSocial;
  final String rfc;
}

/// Validación compartida entre alta y edición de Entidad fiscal —
/// nunca duplicada entre `CrearEntidadFiscalUseCase` y
/// `ActualizarEntidadFiscalUseCase` (mismo motivo que `PuestoValidator`).
///
/// Depende de `ClienteRepository` (para confirmar que el Cliente
/// propietario existe y no está archivado/dado de baja — su estatus
/// *comercial* prospecto/activo/suspendido/terminado/descartado no
/// bloquea nada todavía) y de `EntidadFiscalRepository` (para la
/// unicidad global del RFC).
class EntidadFiscalValidator {
  EntidadFiscalValidator(this._clienteRepository, this._entidadFiscalRepository);

  final ClienteRepository _clienteRepository;
  final EntidadFiscalRepository _entidadFiscalRepository;

  Future<({EntidadFiscalValidada? resultado, List<ErrorCampoEntidadFiscal> errores})> validar({
    required String clienteId,
    required EntidadFiscalBorrador borrador,
    String? excluirEntidadFiscalId,
  }) async {
    final errores = <ErrorCampoEntidadFiscal>[];

    final cliente = await _clienteRepository.obtenerPorId(clienteId);
    if (cliente == null || cliente.cicloVidaRegistro != CicloVidaRegistro.activo.name) {
      errores.add(
        const ErrorCampoEntidadFiscal(campo: CampoEntidadFiscal.cliente, codigo: CodigoErrorEntidadFiscal.clienteInactivo),
      );
    }

    final razonSocial = borrador.razonSocial.trim();
    if (razonSocial.isEmpty) {
      errores.add(
        const ErrorCampoEntidadFiscal(campo: CampoEntidadFiscal.razonSocial, codigo: CodigoErrorEntidadFiscal.requerido),
      );
    }

    final rfcNormalizado = RfcValidator.normalizar(borrador.rfc);
    if (rfcNormalizado.isEmpty) {
      errores.add(
        const ErrorCampoEntidadFiscal(campo: CampoEntidadFiscal.rfc, codigo: CodigoErrorEntidadFiscal.requerido),
      );
    } else if (!RfcValidator.esFormatoValido(rfcNormalizado)) {
      errores.add(
        const ErrorCampoEntidadFiscal(campo: CampoEntidadFiscal.rfc, codigo: CodigoErrorEntidadFiscal.formatoInvalido),
      );
    } else if (await _entidadFiscalRepository.existeRfc(rfcNormalizado, excluirId: excluirEntidadFiscalId)) {
      errores.add(
        const ErrorCampoEntidadFiscal(campo: CampoEntidadFiscal.rfc, codigo: CodigoErrorEntidadFiscal.yaExiste),
      );
    }

    if (errores.isNotEmpty) {
      return (resultado: null, errores: errores);
    }

    return (
      resultado: EntidadFiscalValidada(razonSocial: razonSocial, rfc: rfcNormalizado),
      errores: const <ErrorCampoEntidadFiscal>[],
    );
  }
}
