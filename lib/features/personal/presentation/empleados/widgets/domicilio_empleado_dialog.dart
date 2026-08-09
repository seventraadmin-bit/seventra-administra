import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/core/validation/direccion_validator.dart';
import 'package:riseg_one/features/organizacion/presentation/shared/direccion_controllers.dart';
import 'package:riseg_one/features/personal/domain/usecases/guardar_domicilio_empleado_usecase.dart';

import '../../../personal_providers.dart';

/// Diálogo "Domicilio" del expediente del Empleado (Etapa 5A) —
/// reutiliza por completo `DireccionControllers`/`DireccionValidator`
/// (misma infraestructura que Empresa/Sucursal/Servicio/EntidadFiscal),
/// sin duplicar nada.
///
/// Devuelve `true` si el domicilio se guardó correctamente.
Future<bool> mostrarDialogoDomicilioEmpleado(
  BuildContext context,
  WidgetRef ref, {
  required String empleadoId,
  required DireccionData? domicilioActual,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final controllers = DireccionControllers()..poblar(domicilioActual);
  List<ErrorCampoDireccion> errores = const [];

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.domicilioEmpleadoDialogoTitulo,
    confirmLabel: l10n.domicilioEmpleadoBotonConfirmar,
    cancelLabel: l10n.domicilioEmpleadoBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        ErrorCampoDireccion? errorDe(CampoDireccion campo) => errorParaCampoDireccion(errores, campo);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RisegTextField(
              label: l10n.domicilioEmpleadoCampoCalle,
              controller: controllers.calle,
              autofocus: true,
              errorText: errorDe(CampoDireccion.calle) == null ? null : l10n.domicilioEmpleadoErrorRequerido,
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: RisegTextField(
                    label: l10n.domicilioEmpleadoCampoNumeroExterior,
                    controller: controllers.numeroExterior,
                    errorText:
                        errorDe(CampoDireccion.numeroExterior) == null ? null : l10n.domicilioEmpleadoErrorRequerido,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: RisegTextField(
                    label: l10n.domicilioEmpleadoCampoNumeroInterior,
                    controller: controllers.numeroInterior,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(
              label: l10n.domicilioEmpleadoCampoColonia,
              controller: controllers.colonia,
              errorText: errorDe(CampoDireccion.colonia) == null ? null : l10n.domicilioEmpleadoErrorRequerido,
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(
              label: l10n.domicilioEmpleadoCampoMunicipio,
              controller: controllers.municipioAlcaldia,
              errorText:
                  errorDe(CampoDireccion.municipioAlcaldia) == null ? null : l10n.domicilioEmpleadoErrorRequerido,
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(label: l10n.domicilioEmpleadoCampoCiudad, controller: controllers.ciudadLocalidad),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: RisegTextField(
                    label: l10n.domicilioEmpleadoCampoEstado,
                    controller: controllers.estado,
                    errorText: errorDe(CampoDireccion.estado) == null ? null : l10n.domicilioEmpleadoErrorRequerido,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: RisegTextField(
                    label: l10n.domicilioEmpleadoCampoCodigoPostal,
                    controller: controllers.codigoPostal,
                    errorText:
                        errorDe(CampoDireccion.codigoPostal) == null ? null : l10n.domicilioEmpleadoErrorRequerido,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(label: l10n.domicilioEmpleadoCampoReferencias, controller: controllers.referencias),
          ],
        );
      },
    ),
    onConfirm: () async {
      final resultado = await ref.read(guardarDomicilioEmpleadoUseCaseProvider).ejecutar(
            empleadoId: empleadoId,
            domicilio: controllers.capturar(),
          );

      if (!context.mounted) return false;

      switch (resultado) {
        case GuardarDomicilioEmpleadoExitoso():
          RisegFeedback.showSuccess(context, l10n.domicilioEmpleadoExito);
          return true;
        case GuardarDomicilioEmpleadoErroresValidacion():
          errores = resultado.errores;
          return false;
        case GuardarDomicilioEmpleadoNoExiste():
        case GuardarDomicilioEmpleadoErrorInesperado():
          RisegFeedback.showError(context, l10n.domicilioEmpleadoErrorInesperado);
          return false;
      }
    },
  );

  controllers.dispose();
  return resultado ?? false;
}
