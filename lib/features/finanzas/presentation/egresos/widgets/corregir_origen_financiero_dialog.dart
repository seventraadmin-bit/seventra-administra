import 'package:riseg_one/features/finanzas/presentation/mensaje_saldo_insuficiente.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';

import '../../../domain/usecases/corregir_origen_financiero_egreso_usecase.dart';
import '../../../finanzas_providers.dart';
import '../egresos_controller.dart';
import '../../pagos/pagos_list_screen.dart' show formatoCentavosPago;

/// Contingencia del Maestro: corregir **sólo** de qué cuenta salió un
/// Egreso ya registrado, incluso si lo generó otro módulo.
///
/// No es "editar el Egreso": monto, fecha, concepto y origen funcional
/// siguen corrigiéndose desde su módulo, y el aviso de "movimiento
/// generado automáticamente" se conserva tal cual. Lo único que cambia
/// aquí es dónde ocurrió la salida de efectivo.
///
/// Devuelve `true` si se corrigió.
Future<bool> mostrarDialogoCorregirOrigenFinanciero(
  BuildContext context,
  WidgetRef ref, {
  required EgresoData egreso,
  required String descripcionOrigen,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final cuentas = await ref.read(cuentaFinancieraRepositoryProvider).listar(soloActivas: true);
  if (!context.mounted) return false;

  final cuentaActual = cuentas.where((c) => c.id == egreso.cuentaFinancieraId).firstOrNull;
  String? nuevaCuentaId;
  final motivoCtrl = TextEditingController();
  String? error;

  final corregido = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.egresoAccionCorregirOrigenFinanciero,
    confirmLabel: l10n.egresoCorregirOrigenBotonGuardar,
    cancelLabel: l10n.compraBotonCancelarFormulario,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Lo que NO se puede tocar, a la vista: deja claro que esto
            // no es una edición del movimiento.
            RisegFieldGrid(
              children: [
                _campo(context, l10n.egresoColumnaFolio, egreso.folioEgreso),
                _campo(context, l10n.egresoColumnaMonto, formatoCentavosPago(egreso.monto)),
                _campo(context, l10n.egresoDetalleOrigen, descripcionOrigen),
                _campo(
                  context,
                  l10n.egresoCorregirOrigenCuentaActual,
                  cuentaActual?.nombre ?? l10n.egresoCampoSinAsignar,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            RisegSelect<String?>(
              key: const Key('corregir_origen_campo_cuenta'),
              label: l10n.egresoCorregirOrigenCuentaNueva,
              value: nuevaCuentaId,
              items: [
                RisegSelectItem(value: null, label: l10n.registrarPagoNominaPlaceholderCuenta),
                for (final c in cuentas)
                  // La cuenta actual no se ofrece: elegirla no
                  // produciría ningún cambio que auditar.
                  if (c.id != egreso.cuentaFinancieraId) RisegSelectItem(value: c.id, label: c.nombre),
              ],
              onChanged: (valor) => setState(() => nuevaCuentaId = valor),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(
              key: const Key('corregir_origen_campo_motivo'),
              label: l10n.egresoCorregirOrigenCampoMotivo,
              controller: motivoCtrl,
            ),
            if (error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(error!, style: AppTypography.caption.copyWith(color: context.colors.error)),
            ],
          ],
        ),
      ),
    ),
    onConfirm: () async {
      // Por el controlador, nunca por el provider a pelo: él es quien
      // refresca Cuentas financieras, el Dashboard y el resto de
      // consumidores del saldo.
      // La cuenta destino también tiene que alcanzar: mismo mensaje
      // central, con los tres números, en vez de "error inesperado".
      final resultado = await ejecutarMostrandoSaldoInsuficiente(
        context,
        l10n,
        () => ref.read(egresosControllerProvider.notifier).corregirOrigenFinanciero(
            egresoId: egreso.id,
            cuentaFinancieraId: nuevaCuentaId,
            motivo: motivoCtrl.text,
          ),
      );
      if (resultado == null) return null;
      if (!context.mounted) return false;
      switch (resultado) {
        case CorregirOrigenFinancieroEgresoExitoso():
          RisegFeedback.showSuccess(context, l10n.egresoCorregirOrigenExito);
          return true;
        case CorregirOrigenFinancieroEgresoNoPuedeQuedarSinCuenta():
          error = l10n.egresoCorregirOrigenErrorCuentaRequerida;
          return null;
        case CorregirOrigenFinancieroEgresoMotivoRequerido():
          error = l10n.eliminacionFisicaErrorMotivoRequerido;
          return null;
        case CorregirOrigenFinancieroEgresoSinCambio():
          error = l10n.egresoCorregirOrigenErrorSinCambio;
          return null;
        case CorregirOrigenFinancieroEgresoOrigenNoAdmitido(:final detalle):
          error = detalle;
          return null;
        case CorregirOrigenFinancieroEgresoCuentaInvalida():
          error = l10n.registrarPagoNominaErrorCuentaInvalida;
          return null;
        case CorregirOrigenFinancieroEgresoCancelado():
        case CorregirOrigenFinancieroEgresoFinanciadoConTarjeta():
        case CorregirOrigenFinancieroEgresoNoExiste():
        case CorregirOrigenFinancieroEgresoErrorInesperado():
          RisegFeedback.showError(context, l10n.egresoCorregirOrigenErrorNoAplicable);
          return false;
      }
    },
  );

  WidgetsBinding.instance.addPostFrameCallback((_) => motivoCtrl.dispose());
  return corregido ?? false;
}

Widget _campo(BuildContext context, String etiqueta, String valor) {
  final colors = context.colors;
  return Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(etiqueta, style: AppTypography.label.copyWith(color: colors.textMuted)),
        Text(valor, style: AppTypography.body),
      ],
    ),
  );
}
