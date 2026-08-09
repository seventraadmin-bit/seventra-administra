import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/personal/domain/usecases/alerta_recontratacion_empleado.dart';
import 'package:riseg_one/features/personal/domain/usecases/registrar_reingreso_usecase.dart';

import '../../../../organizacion/organizacion_providers.dart';
import '../../../personal_providers.dart';
import 'baja_laboral_empleado_dialog.dart' show motivoBajaEmpleadoLabel;

/// Diálogo "Registrar reingreso" (Etapa 5C) — recontrata a un Empleado
/// existente, nunca crea uno nuevo. Si el historial (periodo vigente
/// cerrado + `EmpleadoPeriodoLaboral`) tiene algún motivo que genera
/// advertencia (`MotivoBajaEmpleado.generaAdvertenciaRecontratacion`),
/// se muestra un banner informativo — nunca bloquea el reingreso
/// (Resolución explícita de Marlon: "no quiero bloquear el reingreso,
/// solo advertir").
///
/// Devuelve `true` si se registró correctamente.
Future<bool> mostrarDialogoReingresoEmpleado(
  BuildContext context,
  WidgetRef ref,
  EmpleadoData empleado,
  AlertaRecontratacionEmpleado alerta,
) async {
  final l10n = AppLocalizations.of(context)!;

  DateTime? fecha = DateTime.now();
  String? puestoId = empleado.puestoId;
  String? sucursalId = empleado.sucursalId;
  String? errorFecha;

  final puestos = await ref.read(puestoRepositoryProvider).listarActivos();
  final sucursales = await ref.read(sucursalRepositoryProvider).listarActivas();
  if (!context.mounted) return false;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.reingresoEmpleadoDialogoTitulo,
    confirmLabel: l10n.reingresoEmpleadoBotonConfirmar,
    cancelLabel: l10n.reingresoEmpleadoBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        final colors = context.colors;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (alerta.tieneAdvertencia) ...[
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(color: colors.warningBg, borderRadius: AppRadius.mdRadius),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_outlined, size: 18, color: colors.warning),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        l10n.reingresoEmpleadoAdvertenciaMensaje(
                          alerta.motivos.map((m) => motivoBajaEmpleadoLabel(l10n, m.name)).join(', '),
                        ),
                        style: AppTypography.body.copyWith(color: colors.warning),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            RisegDateField(
              label: l10n.empleadoCampoFechaIngreso,
              value: fecha,
              errorText: errorFecha,
              onChanged: (valor) => setState(() {
                fecha = valor;
                errorFecha = null;
              }),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegSelect<String?>(
              label: l10n.empleadoCampoPuesto,
              value: puestoId,
              items: [
                RisegSelectItem(value: null, label: l10n.empleadoCampoSinAsignar),
                for (final p in puestos) RisegSelectItem(value: p.id, label: p.nombre),
              ],
              onChanged: (valor) => setState(() => puestoId = valor),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegSelect<String?>(
              label: l10n.empleadoCampoSucursal,
              value: sucursalId,
              items: [
                RisegSelectItem(value: null, label: l10n.empleadoCampoSinAsignar),
                for (final s in sucursales) RisegSelectItem(value: s.id, label: s.nombre),
              ],
              onChanged: (valor) => setState(() => sucursalId = valor),
            ),
          ],
        );
      },
    ),
    onConfirm: () async {
      if (fecha == null) {
        errorFecha = l10n.evaluacionEmpleadoCampoFecha;
        return false;
      }

      final resultado = await ref.read(registrarReingresoUseCaseProvider).ejecutar(
            empleadoId: empleado.id,
            fechaIngreso: fecha!,
            puestoId: puestoId,
            limpiarPuesto: puestoId == null,
            sucursalId: sucursalId,
            limpiarSucursal: sucursalId == null,
          );

      if (!context.mounted) return false;

      switch (resultado) {
        case RegistrarReingresoExitoso():
          RisegFeedback.showSuccess(context, l10n.reingresoEmpleadoExito);
          return true;
        case RegistrarReingresoNoExiste():
        case RegistrarReingresoNoEstaDeBaja():
        case RegistrarReingresoErrorInesperado():
          RisegFeedback.showError(context, l10n.reingresoEmpleadoErrorInesperado);
          return false;
        case RegistrarReingresoFechaInvalida():
          errorFecha = l10n.reingresoEmpleadoErrorFechaInvalida;
          return false;
      }
    },
  );

  return resultado ?? false;
}
