import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_list_screen.dart' show formaPagoLabel, formatoCentavosPago;
import 'package:riseg_one/features/nomina/domain/usecases/registrar_pago_nomina_usecase.dart';

import '../nominas_controller.dart';

class _FilaSeleccionable {
  _FilaSeleccionable({required this.renglon, required this.saldoPendiente});

  final NominaEmpleadoData renglon;
  final int saldoPendiente;
  bool seleccionado = true;
  late final TextEditingController montoCtrl = TextEditingController(text: (saldoPendiente / 100).toStringAsFixed(2));
}

int? _centavosDesdeTexto(String texto) {
  final normalizado = texto.trim().replaceAll(',', '');
  if (normalizado.isEmpty) return null;
  final pesos = double.tryParse(normalizado);
  if (pesos == null) return null;
  return (pesos * 100).round();
}

/// Diálogo "Registrar pago de nómina" (Etapa 6D) — un lote real de
/// pago, nunca uno por Nómina completa: el usuario elige qué
/// empleados (de los que todavía tienen saldo pendiente) cubre este
/// lote, con el monto de cada uno editable hasta su saldo. Devuelve
/// `true` si el registro tuvo éxito.
Future<bool> mostrarDialogoRegistrarPagoNomina(
  BuildContext context,
  WidgetRef ref, {
  required String nominaId,
  required List<NominaEmpleadoData> renglonesPendientesOParciales,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final notifier = ref.read(nominasControllerProvider.notifier);

  final filas = <_FilaSeleccionable>[];
  for (final renglon in renglonesPendientesOParciales) {
    final saldo = await notifier.saldoPendientePago(renglon.id);
    if (saldo > 0) filas.add(_FilaSeleccionable(renglon: renglon, saldoPendiente: saldo));
  }

  if (!context.mounted) return false;

  DateTime? fechaSeleccionada = DateTime.now();
  FormaPago formaSeleccionada = FormaPago.transferencia;
  final referenciaCtrl = TextEditingController();
  final cuentaOrigenCtrl = TextEditingController();
  final observacionesCtrl = TextEditingController();
  String? errorFecha;
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.registrarPagoNominaDialogoTitulo,
    confirmLabel: l10n.registrarPagoNominaBotonConfirmar,
    cancelLabel: l10n.registrarPagoNominaBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RisegDateField(
                label: l10n.registrarPagoNominaCampoFecha,
                value: fechaSeleccionada,
                errorText: errorFecha,
                onChanged: (valor) => setState(() {
                  fechaSeleccionada = valor;
                  errorFecha = null;
                }),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegSelect<FormaPago>(
                label: l10n.registrarPagoNominaCampoFormaPago,
                value: formaSeleccionada,
                items: [for (final f in FormaPago.values) RisegSelectItem(value: f, label: formaPagoLabel(l10n, f.name))],
                onChanged: (valor) => setState(() => formaSeleccionada = valor ?? formaSeleccionada),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.registrarPagoNominaCampoReferencia, controller: referenciaCtrl),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.registrarPagoNominaCampoCuentaOrigen, controller: cuentaOrigenCtrl),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.registrarPagoNominaCampoObservaciones, controller: observacionesCtrl),
              const SizedBox(height: AppSpacing.md),
              Text(l10n.registrarPagoNominaSeccionEmpleados, style: AppTypography.label),
              const SizedBox(height: AppSpacing.xs),
              if (filas.isEmpty)
                Text(l10n.registrarPagoNominaSinPendientes, style: AppTypography.body)
              else
                for (final fila in filas)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: Row(
                      children: [
                        Checkbox(
                          value: fila.seleccionado,
                          onChanged: (valor) => setState(() => fila.seleccionado = valor ?? false),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text('${fila.renglon.nombreCompleto} · ${formatoCentavosPago(fila.saldoPendiente)}'),
                        ),
                        Expanded(
                          child: RisegTextField(
                            label: l10n.registrarPagoNominaCampoMonto,
                            controller: fila.montoCtrl,
                            enabled: fila.seleccionado,
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                  ),
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
      if (fechaSeleccionada == null) {
        errorFecha = l10n.registrarPagoNominaCampoFecha;
        return null;
      }

      final aplicaciones = <({String nominaEmpleadoId, int monto})>[];
      for (final fila in filas) {
        if (!fila.seleccionado) continue;
        final monto = _centavosDesdeTexto(fila.montoCtrl.text);
        if (monto == null || monto <= 0) {
          errorGeneral = l10n.registrarPagoNominaErrorMontoInvalido;
          return null;
        }
        aplicaciones.add((nominaEmpleadoId: fila.renglon.id, monto: monto));
      }

      if (aplicaciones.isEmpty) {
        errorGeneral = l10n.registrarPagoNominaErrorListaVacia;
        return null;
      }

      final resultado = await ref.read(nominasControllerProvider.notifier).registrarPago(
            nominaId: nominaId,
            fechaPago: fechaSeleccionada!,
            formaPago: formaSeleccionada.name,
            referencia: referenciaCtrl.text.trim().isEmpty ? null : referenciaCtrl.text.trim(),
            cuentaBancariaOrigen: cuentaOrigenCtrl.text.trim().isEmpty ? null : cuentaOrigenCtrl.text.trim(),
            observaciones: observacionesCtrl.text.trim().isEmpty ? null : observacionesCtrl.text.trim(),
            aplicaciones: aplicaciones,
          );

      if (!context.mounted) return false;

      switch (resultado) {
        case RegistrarPagoNominaExitoso():
          RisegFeedback.showSuccess(context, l10n.registrarPagoNominaExito);
          return true;
        case RegistrarPagoNominaListaVacia():
          errorGeneral = l10n.registrarPagoNominaErrorListaVacia;
          return null;
        case RegistrarPagoNominaNominaNoCerrada():
        case RegistrarPagoNominaNominaNoExiste():
          errorGeneral = l10n.registrarPagoNominaErrorNominaNoCerrada;
          return null;
        case RegistrarPagoNominaMontoInvalido():
          errorGeneral = l10n.registrarPagoNominaErrorMontoInvalido;
          return null;
        case RegistrarPagoNominaSobrepago():
        case RegistrarPagoNominaRenglonNoPerteneceANomina():
          errorGeneral = l10n.registrarPagoNominaErrorSobrepago;
          return null;
        case RegistrarPagoNominaErrorInesperado():
          RisegFeedback.showError(context, l10n.registrarPagoNominaErrorInesperado);
          return false;
      }
    },
  );

  for (final fila in filas) {
    fila.montoCtrl.dispose();
  }
  referenciaCtrl.dispose();
  cuentaOrigenCtrl.dispose();
  observacionesCtrl.dispose();

  return resultado ?? false;
}
