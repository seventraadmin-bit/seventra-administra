import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/personal/domain/usecases/asignacion_sueldo_con_vigencia.dart';
import 'package:riseg_one/features/personal/domain/usecases/cambiar_vigencia_sueldo_asignacion_usecase.dart';

import '../../../personal_providers.dart';
import 'crear_empleado_dialog.dart' show centavosDesdeTexto, pesosDesdeCentavosParaEditar;

/// Diálogo "Actualizar sueldo/bono" (ajuste funcional final de la Etapa
/// 6B) — registra un cambio de sueldo/bono dentro de la asignación
/// vigente del Empleado (`CambiarVigenciaSueldoAsignacionUseCase`).
/// Precarga con el sueldo/bono actualmente vigente para que el usuario
/// solo tenga que cambiar lo que sea distinto. Si la fecha de vigencia
/// es futura, el cambio queda programado — nunca sustituye de inmediato
/// al vigente ni modifica vigencias anteriores (Resolución explícita de
/// Marlon).
///
/// Devuelve `true` si se registró correctamente.
Future<bool> mostrarDialogoActualizarSueldoAsignacion(
  BuildContext context,
  WidgetRef ref,
  AsignacionServicioData asignacion,
) async {
  final l10n = AppLocalizations.of(context)!;

  final vigenciasActivas = await ref.read(asignacionServicioRepositoryProvider).listarVigenciasSueldoActivas(asignacion.id);
  final vigente = clasificarVigenciasSueldo(vigenciasActivas, DateTime.now()).vigente;
  if (!context.mounted) return false;

  final sueldoController = TextEditingController(text: pesosDesdeCentavosParaEditar(vigente?.sueldoMensual));
  final bonoController = TextEditingController(text: pesosDesdeCentavosParaEditar(vigente?.bonoMensual));
  DateTime? fecha = DateTime.now();
  String? errorSueldo;
  String? errorBono;
  String? errorFecha;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.actualizarSueldoAsignacionDialogoTitulo,
    confirmLabel: l10n.actualizarSueldoAsignacionBotonConfirmar,
    cancelLabel: l10n.actualizarSueldoAsignacionBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.actualizarSueldoAsignacionAyuda,
              style: AppTypography.caption.copyWith(color: dialogContext.colors.textMuted),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(
              label: l10n.empleadoCampoSueldoAcordado,
              controller: sueldoController,
              errorText: errorSueldo,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() => errorSueldo = null),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(
              label: l10n.empleadoCampoBonoAcordado,
              controller: bonoController,
              errorText: errorBono,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() => errorBono = null),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegDateField(
              label: l10n.actualizarSueldoAsignacionCampoFechaVigencia,
              value: fecha,
              errorText: errorFecha,
              onChanged: (valor) => setState(() {
                fecha = valor;
                errorFecha = null;
              }),
            ),
          ],
        );
      },
    ),
    onConfirm: () async {
      // `showForm` solo mantiene el diálogo abierto cuando `onConfirm`
      // devuelve `null` — mismo criterio que
      // `asignar_servicio_empleado_dialog.dart`.
      if (fecha == null) {
        errorFecha = l10n.actualizarSueldoAsignacionCampoFechaVigencia;
        return null;
      }
      final sueldo = centavosDesdeTexto(sueldoController.text);
      if (sueldo == null) {
        errorSueldo = l10n.empleadoErrorSueldoAcordadoInvalido;
        return null;
      }
      final bono = centavosDesdeTexto(bonoController.text) ?? 0;

      final resultado = await ref.read(cambiarVigenciaSueldoAsignacionUseCaseProvider).ejecutar(
            asignacionServicioId: asignacion.id,
            sueldoMensual: sueldo,
            bonoMensual: bono,
            fechaInicioVigencia: fecha!,
          );

      if (!context.mounted) return null;

      switch (resultado) {
        case CambiarVigenciaSueldoAsignacionExitoso():
          final programada = fecha!.isAfter(DateTime.now());
          RisegFeedback.showSuccess(
            context,
            programada ? l10n.actualizarSueldoAsignacionExitoProgramada : l10n.actualizarSueldoAsignacionExito,
          );
          return true;
        case CambiarVigenciaSueldoAsignacionSueldoInvalido():
          errorSueldo = l10n.empleadoErrorSueldoAcordadoInvalido;
          return null;
        case CambiarVigenciaSueldoAsignacionBonoInvalido():
          errorBono = l10n.empleadoErrorBonoAcordadoInvalido;
          return null;
        case CambiarVigenciaSueldoAsignacionFechaInvalida():
          errorFecha = l10n.actualizarSueldoAsignacionErrorFechaInvalida;
          return null;
        case CambiarVigenciaSueldoAsignacionFechaDuplicada():
          errorFecha = l10n.actualizarSueldoAsignacionErrorFechaDuplicada;
          return null;
        case CambiarVigenciaSueldoAsignacionNoExiste():
        case CambiarVigenciaSueldoAsignacionErrorInesperado():
          RisegFeedback.showError(context, l10n.actualizarSueldoAsignacionErrorInesperado);
          return false;
      }
    },
  );

  // Deferred — mismo criterio que `asignar_servicio_empleado_dialog.dart`.
  unawaited(
    Future.delayed(const Duration(milliseconds: 300), () {
      sueldoController.dispose();
      bonoController.dispose();
    }),
  );
  return resultado ?? false;
}
