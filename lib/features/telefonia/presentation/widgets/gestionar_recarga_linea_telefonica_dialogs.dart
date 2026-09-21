import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/cancelar_recarga_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/corregir_recarga_linea_telefonica_usecase.dart';

import '../../telefonia_providers.dart';
import 'origen_financiero_recarga_campos.dart';

int? _centavosDesdeTexto(String texto) {
  final normalizado = texto.trim().replaceAll(',', '');
  if (normalizado.isEmpty) return null;
  final pesos = double.tryParse(normalizado);
  if (pesos == null) return null;
  return (pesos * 100).round();
}

String _pesosDesdeCentavos(int centavos) => (centavos / 100).toStringAsFixed(2);

/// Diálogo "Corregir recarga" (schemaVersion 81) — el que faltaba para
/// que un importe mal capturado no obligue a borrar la fila.
///
/// Corrige la MISMA recarga: no crea una sustituta, porque duplicarla
/// inflaría todos los totales del módulo. Devuelve `true` si tuvo éxito.
Future<bool> mostrarDialogoCorregirRecargaLineaTelefonica(
  BuildContext context,
  WidgetRef ref,
  RecargaLineaTelefonicaData recarga,
) async {
  final l10n = AppLocalizations.of(context)!;

  // Corregir puede MOVER el efecto financiero (§12): el origen se
  // precarga con el que tiene hoy y las seis transiciones quedan
  // disponibles. Una recarga legacy llega sin origen y aquí gana uno.
  final origen = await cargarOpcionesOrigenRecarga(ref);
  if (!context.mounted) return false;

  DateTime fecha = recarga.fecha;
  final importeCtrl = TextEditingController(text: _pesosDesdeCentavos(recarga.importe));
  final observacionesCtrl = TextEditingController(text: recarga.observaciones ?? '');
  final motivoCtrl = TextEditingController();
  var seleccion = OrigenFinancieroRecarga(
    formaPago: recarga.formaPago ?? '',
    cuentaFinancieraId: recarga.egresoId == null
        ? null
        : await ref.read(recargaLineaTelefonicaRepositoryProvider).cuentaDeEgreso(recarga.egresoId!),
    deudaIdTarjeta: recarga.deudaId,
  );
  if (!context.mounted) return false;
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.recargaDialogoCorregirTitulo,
    confirmLabel: l10n.lineaTelefonicaRecargaBotonGuardar,
    cancelLabel: l10n.vehiculoBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RisegDateField(
                label: l10n.lineaTelefonicaRecargaCampoFecha,
                value: fecha,
                onChanged: (valor) => setState(() => fecha = valor),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(
                key: const Key('recarga_corregir_importe'),
                label: l10n.lineaTelefonicaRecargaCampoImporte,
                controller: importeCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(
                label: l10n.lineaTelefonicaRecargaCampoObservaciones,
                controller: observacionesCtrl,
              ),
              const SizedBox(height: AppSpacing.md),
              ...camposOrigenFinancieroRecarga(
                l10n: l10n,
                opciones: origen,
                seleccion: seleccion,
                onCambio: (valor) => setState(() => seleccion = valor),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(
                key: const Key('recarga_corregir_motivo'),
                label: l10n.recargaCampoMotivoCorreccion,
                controller: motivoCtrl,
                autofocus: true,
              ),
              if (errorGeneral != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  errorGeneral!,
                  style: AppTypography.caption.copyWith(color: Theme.of(dialogContext).colorScheme.error),
                ),
              ],
            ],
          ),
        );
      },
    ),
    onConfirm: () async {
      final observaciones = observacionesCtrl.text.trim();
      final faltaOrigen = seleccion.errorFaltante(l10n);
      if (faltaOrigen != null) {
        errorGeneral = faltaOrigen;
        return null;
      }
      final corregida = await ref.read(corregirRecargaLineaTelefonicaAutorizadoProvider)(
            recargaLineaTelefonicaId: recarga.id,
            fecha: fecha,
            importe: _centavosDesdeTexto(importeCtrl.text),
            formaPago: seleccion.formaPago,
            cuentaFinancieraId: seleccion.cuentaFinancieraId,
            deudaIdTarjeta: seleccion.deudaIdTarjeta,
            observaciones: observaciones.isEmpty ? null : observaciones,
            limpiarObservaciones: observaciones.isEmpty,
            motivo: motivoCtrl.text,
          );
      if (!context.mounted) return false;

      switch (corregida) {
        case CorregirRecargaLineaTelefonicaOrigenFinancieroRequerido():
        case CorregirRecargaLineaTelefonicaOrigenFinancieroAmbiguo():
          errorGeneral = l10n.recargaOrigenFinancieroRequerido;
          return null;
        case CorregirRecargaLineaTelefonicaTarjetaInvalida():
          errorGeneral = l10n.recargaTarjetaInvalida;
          return null;
        case CorregirRecargaLineaTelefonicaTarjetaSinLimiteConfigurado():
          errorGeneral = l10n.recargaTarjetaSinLimite;
          return null;
        case CorregirRecargaLineaTelefonicaTarjetaExcedeLimite():
          errorGeneral = l10n.recargaTarjetaExcedeLimite;
          return null;
        case CorregirRecargaLineaTelefonicaMotivoRequerido():
          errorGeneral = l10n.recargaErrorMotivoRequerido;
          return null;
        case CorregirRecargaLineaTelefonicaImporteInvalido():
          errorGeneral = l10n.recargaErrorImporteInvalido;
          return null;
        case CorregirRecargaLineaTelefonicaCancelada():
          errorGeneral = l10n.recargaErrorCorregirCancelada;
          return null;
        case CorregirRecargaLineaTelefonicaNoExiste():
        case CorregirRecargaLineaTelefonicaErrorInesperado():
          RisegFeedback.showError(context, l10n.lineaTelefonicaRecargaErrorInesperado);
          return false;
        case CorregirRecargaLineaTelefonicaExitoso():
          RisegFeedback.showSuccess(context, l10n.recargaCorregidaExito);
          return true;
      }
    },
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    importeCtrl.dispose();
    observacionesCtrl.dispose();
    motivoCtrl.dispose();
  });
  return resultado ?? false;
}

/// Diálogo "Anular recarga" (schemaVersion 81).
///
/// Anular **no borra**: la fila se conserva en el historial de la línea
/// con su motivo, y deja de sumar en todos los totales del módulo. Es
/// terminal — no existe reactivación de una recarga.
///
/// No mueve dinero: Telefonía no generó `Egreso` al registrarla, así que
/// no hay nada que revertir en Finanzas.
Future<bool> mostrarDialogoAnularRecargaLineaTelefonica(
  BuildContext context,
  WidgetRef ref,
  RecargaLineaTelefonicaData recarga,
) async {
  final l10n = AppLocalizations.of(context)!;
  final motivoCtrl = TextEditingController();
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.recargaDialogoAnularTitulo,
    confirmLabel: l10n.recargaBotonAnular,
    cancelLabel: l10n.vehiculoBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.recargaAnularAdvertencia,
                style: AppTypography.caption.copyWith(color: dialogContext.colors.textMuted),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(
                key: const Key('recarga_anular_motivo'),
                label: l10n.recargaCampoMotivoAnulacion,
                controller: motivoCtrl,
                autofocus: true,
              ),
              if (errorGeneral != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  errorGeneral!,
                  style: AppTypography.caption.copyWith(color: Theme.of(dialogContext).colorScheme.error),
                ),
              ],
            ],
          ),
        );
      },
    ),
    onConfirm: () async {
      final anulada = await ref.read(cancelarRecargaLineaTelefonicaAutorizadoProvider)(
            recargaLineaTelefonicaId: recarga.id,
            motivo: motivoCtrl.text,
          );
      if (!context.mounted) return false;

      switch (anulada) {
        case CancelarRecargaLineaTelefonicaMotivoRequerido():
          errorGeneral = l10n.recargaErrorMotivoRequerido;
          return null;
        case CancelarRecargaLineaTelefonicaYaCancelada():
          errorGeneral = l10n.recargaErrorYaCancelada;
          return null;
        case CancelarRecargaLineaTelefonicaNoExiste():
        case CancelarRecargaLineaTelefonicaErrorInesperado():
          RisegFeedback.showError(context, l10n.lineaTelefonicaRecargaErrorInesperado);
          return false;
        case CancelarRecargaLineaTelefonicaExitoso():
          RisegFeedback.showSuccess(context, l10n.recargaAnuladaExito);
          return true;
      }
    },
  );

  WidgetsBinding.instance.addPostFrameCallback((_) => motivoCtrl.dispose());
  return resultado ?? false;
}
