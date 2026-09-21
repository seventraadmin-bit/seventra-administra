import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/data/tables/complemento_pago_table.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/corregir_pago_usecase.dart';

import '../../../finanzas_providers.dart';
import '../pagos_controller.dart';
import '../pagos_list_screen.dart' show formaPagoLabel, formatoCentavosPago;

int? _centavosDesdeTexto(String texto) {
  final normalizado = texto.trim().replaceAll(',', '');
  if (normalizado.isEmpty) return null;
  final pesos = double.tryParse(normalizado);
  if (pesos == null) return null;
  return (pesos * 100).round();
}

class _FilaDistribucion {
  _FilaDistribucion({this.cuentaPorCobrarId, String montoTexto = ''}) : montoController = TextEditingController(text: montoTexto);
  String? cuentaPorCobrarId;
  final TextEditingController montoController;
}

/// Diálogo para corregir un Pago (Etapa 6, reversa de la resolución de
/// la Etapa 4J.2 "nunca `montoTotal`") — ahora también el monto total,
/// la Cuenta financiera de destino y la distribución completa entre
/// Cuentas por cobrar (modelo N:M real). Si existe un `ComplementoPago`
/// vigente, monto/fecha/forma de pago/distribución quedan bloqueados
/// (Sección 6/17 del pedido) — solo Cuenta financiera/referencia/banco
/// de origen/cuenta bancaria destino/observaciones siguen corregibles.
///
/// Devuelve `true` si la corrección tuvo éxito.
Future<bool> mostrarDialogoCorregirPago(
  BuildContext context,
  WidgetRef ref,
  PagoData pago, {
  required List<AplicacionPagoData> aplicacionesActivas,
  required ComplementoPagoData? complemento,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final complementoVigente =
      complemento != null && EstatusComplementoPago.values.byName(complemento.estatus) == EstatusComplementoPago.registrado;

  final cuentasDelCliente = await ref.read(cuentaPorCobrarRepositoryProvider).listar(clienteId: pago.clienteId);
  final cuentasFinancieras = await ref.read(cuentaFinancieraRepositoryProvider).listar(soloActivas: true);
  if (!context.mounted) return false;
  final folioPorCuenta = {for (final c in cuentasDelCliente) c.id: c.folioDocumento ?? c.documentoPorEmitirId};

  final montoTotalController = TextEditingController(text: (pago.montoTotal / 100).toStringAsFixed(2));
  DateTime fechaSeleccionada = pago.fechaPago;
  FormaPago formaSeleccionada = FormaPago.values.byName(pago.formaPago);
  final referenciaController = TextEditingController(text: pago.referencia ?? '');
  final bancoOrigenController = TextEditingController(text: pago.bancoOrigen ?? '');
  final cuentaBancariaController = TextEditingController(text: pago.cuentaBancariaDestino ?? '');
  final observacionesController = TextEditingController(text: pago.observaciones ?? '');
  final motivoController = TextEditingController();
  String? cuentaFinancieraId;
  var tocaDistribucion = false;
  final filas = [
    for (final a in aplicacionesActivas)
      _FilaDistribucion(cuentaPorCobrarId: a.cuentaPorCobrarId, montoTexto: (a.monto / 100).toStringAsFixed(2)),
  ];
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.corregirPagoDialogoTitulo,
    confirmLabel: l10n.corregirPagoBotonConfirmar,
    cancelLabel: l10n.corregirPagoBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        final montoTotal = _centavosDesdeTexto(montoTotalController.text) ?? pago.montoTotal;
        final aplicado = filas.fold<int>(0, (s, f) => s + (_centavosDesdeTexto(f.montoController.text) ?? 0));
        final pendiente = montoTotal - aplicado;

        return SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (complementoVigente) ...[
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: Theme.of(dialogContext).colorScheme.errorContainer.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      l10n.corregirPagoAvisoComplementoVigente(complemento.uuid),
                      style: AppTypography.caption,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                RisegTextField(
                  label: l10n.corregirPagoCampoMontoTotal,
                  controller: montoTotalController,
                  keyboardType: TextInputType.number,
                  enabled: !complementoVigente,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: AppSpacing.md),
                RisegDateField(
                  label: l10n.corregirPagoCampoFecha,
                  value: fechaSeleccionada,
                  enabled: !complementoVigente,
                  onChanged: (valor) => setState(() => fechaSeleccionada = valor),
                ),
                const SizedBox(height: AppSpacing.md),
                RisegSelect<FormaPago>(
                  label: l10n.corregirPagoCampoFormaPago,
                  value: formaSeleccionada,
                  enabled: !complementoVigente,
                  items: [
                    for (final f in FormaPago.values) RisegSelectItem(value: f, label: formaPagoLabel(l10n, f.name)),
                  ],
                  onChanged: (valor) => setState(() => formaSeleccionada = valor ?? formaSeleccionada),
                ),
                const SizedBox(height: AppSpacing.md),
                RisegTextField(label: l10n.corregirPagoCampoReferencia, controller: referenciaController),
                const SizedBox(height: AppSpacing.md),
                RisegTextField(label: l10n.corregirPagoCampoBancoOrigen, controller: bancoOrigenController),
                const SizedBox(height: AppSpacing.md),
                RisegTextField(label: l10n.corregirPagoCampoCuentaBancariaDestino, controller: cuentaBancariaController),
                const SizedBox(height: AppSpacing.md),
                RisegSelect<String?>(
                  label: l10n.corregirPagoCampoCuentaFinanciera,
                  value: cuentaFinancieraId,
                  items: [
                    RisegSelectItem(value: null, label: l10n.egresoCampoSinAsignar),
                    for (final c in cuentasFinancieras) RisegSelectItem(value: c.id, label: c.nombre),
                  ],
                  onChanged: (valor) => setState(() => cuentaFinancieraId = valor),
                ),
                const SizedBox(height: AppSpacing.md),
                RisegTextField(label: l10n.corregirPagoCampoObservaciones, controller: observacionesController),
                const SizedBox(height: AppSpacing.lg),
                const Divider(),
                const SizedBox(height: AppSpacing.sm),
                Text(l10n.corregirPagoSeccionDistribucion, style: AppTypography.label),
                const SizedBox(height: AppSpacing.xs),
                if (complementoVigente)
                  Text(
                    l10n.corregirPagoAvisoComplementoVigente(complemento.uuid),
                    style: AppTypography.caption,
                  )
                else ...[
                  for (var i = 0; i < filas.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
                      child: Row(
                        children: [
                          Expanded(
                            child: RisegSelect<String?>(
                              label: l10n.corregirPagoCampoCuentaPorCobrar,
                              value: filas[i].cuentaPorCobrarId,
                              items: [
                                for (final c in cuentasDelCliente)
                                  RisegSelectItem(value: c.id, label: folioPorCuenta[c.id] ?? c.id),
                              ],
                              onChanged: (valor) => setState(() {
                                filas[i].cuentaPorCobrarId = valor;
                                tocaDistribucion = true;
                              }),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          SizedBox(
                            width: 140,
                            child: RisegTextField(
                              label: l10n.corregirPagoCampoMontoAplicacion,
                              controller: filas[i].montoController,
                              keyboardType: TextInputType.number,
                              onChanged: (_) => setState(() => tocaDistribucion = true),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => setState(() {
                              filas.removeAt(i);
                              tocaDistribucion = true;
                            }),
                          ),
                        ],
                      ),
                    ),
                  RisegButton(
                    label: l10n.corregirPagoBotonAgregarCuenta,
                    variant: RisegButtonVariant.ghost,
                    onPressed: () => setState(() {
                      filas.add(_FilaDistribucion());
                      tocaDistribucion = true;
                    }),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(l10n.corregirPagoLabelAplicado, style: AppTypography.body),
                      Text(formatoCentavosPago(aplicado), style: AppTypography.body),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(l10n.corregirPagoLabelPendientePorAplicar, style: AppTypography.label),
                      Text(formatoCentavosPago(pendiente), style: AppTypography.label),
                    ],
                  ),
                ],
                if (errorGeneral != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    errorGeneral!,
                    style: AppTypography.caption.copyWith(color: Theme.of(dialogContext).colorScheme.error),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                RisegTextField(label: l10n.corregirPagoCampoMotivo, controller: motivoController),
              ],
            ),
          ),
        );
      },
    ),
    onConfirm: () async {
      final motivo = motivoController.text.trim();
      if (motivo.isEmpty) {
        errorGeneral = l10n.corregirPagoErrorMotivoRequerido;
        return null;
      }
      final montoTotal = _centavosDesdeTexto(montoTotalController.text);
      if (montoTotal == null || montoTotal <= 0) {
        errorGeneral = l10n.corregirPagoErrorValorInvalido;
        return null;
      }

      List<({String cuentaPorCobrarId, int monto})>? nuevaDistribucion;
      if (!complementoVigente && tocaDistribucion) {
        final distribucion = <({String cuentaPorCobrarId, int monto})>[];
        for (final fila in filas) {
          final cuentaId = fila.cuentaPorCobrarId;
          if (cuentaId == null) continue;
          final monto = _centavosDesdeTexto(fila.montoController.text);
          if (monto == null || monto <= 0) {
            errorGeneral = l10n.corregirPagoErrorValorInvalido;
            return null;
          }
          distribucion.add((cuentaPorCobrarId: cuentaId, monto: monto));
        }
        nuevaDistribucion = distribucion;
      }

      final resultado = await ref.read(pagosControllerProvider.notifier).corregir(
            pagoId: pago.id,
            fechaPago: complementoVigente ? null : fechaSeleccionada,
            formaPago: complementoVigente ? null : formaSeleccionada.name,
            referencia: referenciaController.text.trim().isEmpty ? null : referenciaController.text.trim(),
            bancoOrigen: bancoOrigenController.text.trim().isEmpty ? null : bancoOrigenController.text.trim(),
            cuentaBancariaDestino:
                cuentaBancariaController.text.trim().isEmpty ? null : cuentaBancariaController.text.trim(),
            cuentaFinancieraId: cuentaFinancieraId,
            limpiarCuentaFinancieraId: cuentaFinancieraId == null,
            observaciones: observacionesController.text.trim().isEmpty ? null : observacionesController.text.trim(),
            montoTotal: complementoVigente ? null : montoTotal,
            nuevaDistribucion: nuevaDistribucion,
            motivo: motivo,
          );

      if (!context.mounted) return false;

      switch (resultado) {
        case CorregirPagoExitoso():
          RisegFeedback.showSuccess(context, l10n.corregirPagoExito);
          return true;
        case CorregirPagoMotivoRequerido():
          errorGeneral = l10n.corregirPagoErrorMotivoRequerido;
          return null;
        case CorregirPagoValorInvalido():
          errorGeneral = l10n.corregirPagoErrorValorInvalido;
          return null;
        case CorregirPagoMontoMenorQueAplicado(:final montoAplicado):
          errorGeneral = l10n.corregirPagoErrorMontoMenorQueAplicado(formatoCentavosPago(montoAplicado));
          return null;
        case CorregirPagoSobrepago(:final montoDisponible):
          errorGeneral = l10n.corregirPagoErrorSobrepago(formatoCentavosPago(montoDisponible));
          return null;
        case CorregirPagoCuentaNoExiste():
          errorGeneral = l10n.corregirPagoErrorCuentaNoExiste;
          return null;
        case CorregirPagoClienteNoCoincide():
          errorGeneral = l10n.corregirPagoErrorClienteNoCoincide;
          return null;
        case CorregirPagoSobrepagoDeCuenta(:final saldoDisponible):
          errorGeneral = l10n.corregirPagoErrorSobrepagoDeCuenta(formatoCentavosPago(saldoDisponible));
          return null;
        case CorregirPagoComplementoVigente(:final uuid):
          errorGeneral = l10n.corregirPagoErrorComplementoVigente(uuid);
          return null;
        case CorregirPagoNoExiste():
        case CorregirPagoCancelado():
          RisegFeedback.showError(context, l10n.corregirPagoErrorCancelado);
          return false;
        case CorregirPagoErrorInesperado():
          RisegFeedback.showError(context, l10n.corregirPagoErrorInesperado);
          return false;
      }
    },
  );

  montoTotalController.dispose();
  referenciaController.dispose();
  bancoOrigenController.dispose();
  cuentaBancariaController.dispose();
  observacionesController.dispose();
  motivoController.dispose();
  for (final fila in filas) {
    fila.montoController.dispose();
  }
  return resultado ?? false;
}
