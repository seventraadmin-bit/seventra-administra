import 'package:drift/drift.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';

import '../repositories/entidad_fiscal_repository.dart';
import 'entidad_fiscal_validator.dart';
import 'guardar_entidad_fiscal_resultado.dart';

/// Comparte exactamente las mismas reglas que `CrearEntidadFiscalUseCase`
/// vía `EntidadFiscalValidator` — mismo patrón que `ActualizarPuestoUseCase`.
/// Nunca acepta un `clienteId` nuevo: la relación con el Cliente es
/// inmutable, así que se relee del registro existente, nunca del
/// formulario. Una Entidad fiscal archivada es de solo consulta —
/// rechaza la edición sin siquiera validar los campos. El domicilio
/// fiscal no se toca aquí — es responsabilidad exclusiva de
/// `GuardarDomicilioFiscalUseCase`.
class ActualizarEntidadFiscalUseCase {
  ActualizarEntidadFiscalUseCase(this._repository, this._validator);

  final EntidadFiscalRepository _repository;
  final EntidadFiscalValidator _validator;

  Future<GuardarEntidadFiscalResultado> ejecutar({
    required String id,
    required EntidadFiscalBorrador borrador,
  }) async {
    final existente = await _repository.obtenerPorId(id);
    if (existente == null) {
      return GuardarEntidadFiscalErrorInesperado('Entidad fiscal no encontrada: $id');
    }
    if (existente.cicloVidaRegistro != CicloVidaRegistro.activo.name) {
      return GuardarEntidadFiscalArchivada();
    }

    final validacion = await _validator.validar(
      clienteId: existente.clienteId,
      borrador: borrador,
      excluirEntidadFiscalId: id,
    );
    if (validacion.errores.isNotEmpty) {
      return GuardarEntidadFiscalErroresValidacion(
        [for (final e in validacion.errores) ErrorCampoEntidadFiscalGeneral(e)],
      );
    }
    final validado = validacion.resultado!;

    try {
      final actualizada = await _repository.actualizar(
        id: id,
        cambios: EntidadFiscalCompanion(
          razonSocial: Value(validado.razonSocial),
          rfc: Value(validado.rfc),
        ),
      );
      return GuardarEntidadFiscalExitoso(actualizada);
    } catch (e) {
      return GuardarEntidadFiscalErrorInesperado(e.toString());
    }
  }
}
