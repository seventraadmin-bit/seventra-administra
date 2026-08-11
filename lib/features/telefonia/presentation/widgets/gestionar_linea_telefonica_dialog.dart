import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/telefonia/data/tables/linea_telefonica_table.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/corregir_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/crear_linea_telefonica_usecase.dart';

import '../linea_telefonica_labels.dart';
import '../telefonia_controller.dart';

/// Diálogo de alta/edición de una línea telefónica (Etapa 9A). Si
/// [linea] es `null`, da de alta; si no, corrige metadatos — mismo
/// patrón que `mostrarDialogoGestionarVehiculo`. Devuelve `true` si la
/// operación tuvo éxito.
Future<bool> mostrarDialogoGestionarLineaTelefonica(
  BuildContext context,
  WidgetRef ref, {
  LineaTelefonicaData? linea,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final notifier = ref.read(telefoniaControllerProvider.notifier);
  final esEdicion = linea != null;

  final numeroCtrl = TextEditingController(text: linea?.numero ?? '');
  final operadorOtroNombreCtrl = TextEditingController(text: linea?.operadorOtroNombre ?? '');
  final iccidCtrl = TextEditingController(text: linea?.iccid ?? '');
  final observacionesCtrl = TextEditingController(text: linea?.observaciones ?? '');
  OperadorTelefonico operador = linea == null
      ? OperadorTelefonico.telcel
      : OperadorTelefonico.values.byName(linea.operador);
  ModalidadSim modalidadSim = linea == null
      ? ModalidadSim.fisica
      : ModalidadSim.values.byName(linea.modalidadSim);
  DateTime? fechaActivacion = linea?.fechaActivacion;
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: esEdicion ? l10n.lineaTelefonicaDialogoTituloEdicion : l10n.lineaTelefonicaDialogoTituloAlta,
    confirmLabel: l10n.lineaTelefonicaBotonGuardar,
    cancelLabel: l10n.lineaTelefonicaBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RisegTextField(label: l10n.lineaTelefonicaCampoNumero, controller: numeroCtrl, autofocus: true),
              const SizedBox(height: AppSpacing.md),
              RisegSelect<OperadorTelefonico>(
                label: l10n.lineaTelefonicaCampoOperador,
                value: operador,
                items: [
                  for (final o in OperadorTelefonico.values)
                    RisegSelectItem(value: o, label: operadorTelefonicoLabel(l10n, o.name)),
                ],
                onChanged: (valor) => setState(() => operador = valor ?? operador),
              ),
              if (operador == OperadorTelefonico.otro) ...[
                const SizedBox(height: AppSpacing.md),
                RisegTextField(label: l10n.lineaTelefonicaCampoOperadorOtroNombre, controller: operadorOtroNombreCtrl),
              ],
              const SizedBox(height: AppSpacing.md),
              RisegSelect<ModalidadSim>(
                label: l10n.lineaTelefonicaCampoModalidadSim,
                value: modalidadSim,
                items: [
                  for (final m in ModalidadSim.values) RisegSelectItem(value: m, label: modalidadSimLabel(l10n, m.name)),
                ],
                onChanged: (valor) => setState(() => modalidadSim = valor ?? modalidadSim),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.lineaTelefonicaCampoIccid, controller: iccidCtrl),
              const SizedBox(height: AppSpacing.md),
              RisegDateField(
                label: l10n.lineaTelefonicaCampoFechaActivacion,
                value: fechaActivacion,
                onChanged: (valor) => setState(() => fechaActivacion = valor),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.lineaTelefonicaCampoObservaciones, controller: observacionesCtrl),
              if (errorGeneral != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(errorGeneral!, style: AppTypography.caption.copyWith(color: Theme.of(dialogContext).colorScheme.error)),
              ],
            ],
          ),
        );
      },
    ),
    onConfirm: () async {
      final numero = numeroCtrl.text.trim().isEmpty ? null : numeroCtrl.text.trim();
      final operadorOtroNombre = operadorOtroNombreCtrl.text.trim().isEmpty ? null : operadorOtroNombreCtrl.text.trim();
      final iccid = iccidCtrl.text.trim().isEmpty ? null : iccidCtrl.text.trim();
      final observaciones = observacionesCtrl.text.trim().isEmpty ? null : observacionesCtrl.text.trim();

      if (esEdicion) {
        final resultadoCorregir = await notifier.corregirLinea(
          lineaTelefonicaId: linea.id,
          numero: numero,
          operador: operador.name,
          operadorOtroNombre: operadorOtroNombre,
          modalidadSim: modalidadSim.name,
          iccid: iccid,
          fechaActivacion: fechaActivacion,
          observaciones: observaciones,
          limpiarNumero: numero == null,
          limpiarOperadorOtroNombre: operadorOtroNombre == null,
          limpiarIccid: iccid == null,
          limpiarFechaActivacion: fechaActivacion == null,
          limpiarObservaciones: observaciones == null,
        );
        if (!context.mounted) return false;
        switch (resultadoCorregir) {
          case CorregirLineaTelefonicaExitoso():
            RisegFeedback.showSuccess(context, l10n.lineaTelefonicaGuardadaExito);
            return true;
          case CorregirLineaTelefonicaNumeroDuplicado():
            errorGeneral = l10n.lineaTelefonicaErrorNumeroDuplicado;
            return null;
          case CorregirLineaTelefonicaOperadorOtroNombreRequerido():
            errorGeneral = l10n.lineaTelefonicaErrorOperadorOtroNombreRequerido;
            return null;
          case CorregirLineaTelefonicaNoExiste():
          case CorregirLineaTelefonicaErrorInesperado():
            RisegFeedback.showError(context, l10n.lineaTelefonicaErrorInesperado);
            return false;
        }
      }

      final resultadoCrear = await notifier.crearLinea(
        numero: numero,
        operador: operador.name,
        operadorOtroNombre: operadorOtroNombre,
        modalidadSim: modalidadSim.name,
        iccid: iccid,
        fechaActivacion: fechaActivacion,
        observaciones: observaciones,
      );
      if (!context.mounted) return false;
      switch (resultadoCrear) {
        case CrearLineaTelefonicaExitoso():
          RisegFeedback.showSuccess(context, l10n.lineaTelefonicaGuardadaExito);
          return true;
        case CrearLineaTelefonicaNumeroDuplicado():
          errorGeneral = l10n.lineaTelefonicaErrorNumeroDuplicado;
          return null;
        case CrearLineaTelefonicaOperadorOtroNombreRequerido():
          errorGeneral = l10n.lineaTelefonicaErrorOperadorOtroNombreRequerido;
          return null;
        case CrearLineaTelefonicaErrorInesperado():
          RisegFeedback.showError(context, l10n.lineaTelefonicaErrorInesperado);
          return false;
      }
    },
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    numeroCtrl.dispose();
    operadorOtroNombreCtrl.dispose();
    iccidCtrl.dispose();
    observacionesCtrl.dispose();
  });

  return resultado ?? false;
}
