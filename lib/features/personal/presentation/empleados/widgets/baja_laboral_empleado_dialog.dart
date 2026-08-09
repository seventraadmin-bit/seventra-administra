import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart';
import 'package:riseg_one/features/personal/domain/usecases/registrar_baja_laboral_usecase.dart';

import '../../../personal_providers.dart';

String motivoBajaEmpleadoLabel(AppLocalizations l10n, String valor) {
  return switch (MotivoBajaEmpleado.values.byName(valor)) {
    MotivoBajaEmpleado.abandonoServicio => l10n.motivoBajaEmpleadoAbandonoServicio,
    MotivoBajaEmpleado.robo => l10n.motivoBajaEmpleadoRobo,
    MotivoBajaEmpleado.malaConducta => l10n.motivoBajaEmpleadoMalaConducta,
    MotivoBajaEmpleado.inasistencias => l10n.motivoBajaEmpleadoInasistencias,
    MotivoBajaEmpleado.incumplimientoConsignas => l10n.motivoBajaEmpleadoIncumplimientoConsignas,
    MotivoBajaEmpleado.noAproboCapacitacion => l10n.motivoBajaEmpleadoNoAproboCapacitacion,
    MotivoBajaEmpleado.renuncia => l10n.motivoBajaEmpleadoRenuncia,
    MotivoBajaEmpleado.finContrato => l10n.motivoBajaEmpleadoFinContrato,
    MotivoBajaEmpleado.reduccionPersonal => l10n.motivoBajaEmpleadoReduccionPersonal,
    MotivoBajaEmpleado.otro => l10n.motivoBajaEmpleadoOtro,
  };
}

/// Diálogo "Dar de baja" (Etapa 5C) — cierra el periodo laboral
/// vigente. `observaciones` se vuelve obligatoria cuando el motivo es
/// `otro` (`MotivoBajaEmpleado.requiereObservaciones`).
///
/// Devuelve `true` si se registró correctamente.
Future<bool> mostrarDialogoBajaLaboralEmpleado(BuildContext context, WidgetRef ref, EmpleadoData empleado) async {
  final l10n = AppLocalizations.of(context)!;

  DateTime? fecha = DateTime.now();
  MotivoBajaEmpleado motivo = MotivoBajaEmpleado.renuncia;
  final observacionesController = TextEditingController();
  String? errorFecha;
  String? errorObservaciones;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.bajaLaboralEmpleadoDialogoTitulo,
    confirmLabel: l10n.bajaLaboralEmpleadoBotonConfirmar,
    cancelLabel: l10n.bajaLaboralEmpleadoBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RisegDateField(
              label: l10n.empleadoCampoFechaBaja,
              value: fecha,
              errorText: errorFecha,
              onChanged: (valor) => setState(() {
                fecha = valor;
                errorFecha = null;
              }),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegSelect<MotivoBajaEmpleado>(
              label: l10n.empleadoCampoMotivoBaja,
              value: motivo,
              items: [
                for (final m in MotivoBajaEmpleado.values)
                  RisegSelectItem(value: m, label: motivoBajaEmpleadoLabel(l10n, m.name)),
              ],
              onChanged: (valor) => setState(() {
                motivo = valor ?? motivo;
                errorObservaciones = null;
              }),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(
              label: l10n.empleadoCampoObservacionesBaja,
              controller: observacionesController,
              errorText: errorObservaciones,
              onChanged: (_) => setState(() => errorObservaciones = null),
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

      final resultado = await ref.read(registrarBajaLaboralUseCaseProvider).ejecutar(
            empleadoId: empleado.id,
            fechaBaja: fecha!,
            motivo: motivo,
            observaciones: observacionesController.text,
          );

      if (!context.mounted) return false;

      switch (resultado) {
        case RegistrarBajaLaboralExitoso():
          RisegFeedback.showSuccess(context, l10n.bajaLaboralEmpleadoExito);
          return true;
        case RegistrarBajaLaboralNoExiste():
        case RegistrarBajaLaboralYaDeBaja():
        case RegistrarBajaLaboralErrorInesperado():
          RisegFeedback.showError(context, l10n.bajaLaboralEmpleadoErrorInesperado);
          return false;
        case RegistrarBajaLaboralFechaInvalida():
          errorFecha = l10n.bajaLaboralEmpleadoErrorFechaInvalida;
          return false;
        case RegistrarBajaLaboralObservacionesRequeridas():
          errorObservaciones = l10n.bajaLaboralEmpleadoErrorObservacionesRequeridas;
          return false;
      }
    },
  );

  observacionesController.dispose();
  return resultado ?? false;
}
