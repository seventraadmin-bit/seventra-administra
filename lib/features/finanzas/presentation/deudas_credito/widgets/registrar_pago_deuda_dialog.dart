import 'package:riseg_one/features/finanzas/presentation/mensaje_saldo_insuficiente.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_pago_deuda_usecase.dart';

import '../../../finanzas_providers.dart';
import '../../ingresos/widgets/ingreso_monto_utils.dart';
import '../../pagos/pagos_list_screen.dart' show formaPagoLabel;
import '../deudas_credito_list_screen.dart' show formatoCentavosDeuda;

/// Diálogo "Registrar pago" de una Deuda (Etapa 19) — en una sola
/// transacción crea el `Egreso` real de la salida de efectivo, el
/// `MovimientoDeuda`, y actualiza saldo/estatus. Bloquea inline
/// cualquier intento de pagar más del saldo actual.
///
/// Devuelve `true` si el registro tuvo éxito.
Future<bool> mostrarDialogoRegistrarPagoDeuda(BuildContext context, WidgetRef ref, {required DeudaData deuda}) async {
  final l10n = AppLocalizations.of(context)!;
  String? errorGeneral;
  final cuentasFinancieras = await ref.read(cuentaFinancieraRepositoryProvider).listar(soloActivas: true);
  if (!context.mounted) return false;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.registrarPagoDeudaDialogoTitulo,
    confirmLabel: l10n.registrarPagoDeudaBotonConfirmar,
    cancelLabel: l10n.asignarArticuloBotonCancelar,
    contentBuilder: (_) => _RegistrarPagoDeudaForm(deuda: deuda, cuentasFinancieras: cuentasFinancieras, errorGeneral: errorGeneral),
    onConfirm: () async {
      final formState = _formKey.currentState;
      if (formState == null) return null;

      final importe = centavosDesdeTexto(formState.importeCtrl.text);
      if (importe == null || importe <= 0) {
        errorGeneral = l10n.registrarPagoDeudaErrorImporteInvalido;
        return null;
      }
      if (importe > deuda.saldoActual) {
        errorGeneral = l10n.registrarPagoDeudaErrorSobrepasaSaldo(formatoCentavosDeuda(deuda.saldoActual));
        return null;
      }

      // Saldo insuficiente no es un "error inesperado": lo traduce el
      // mecanismo central y el formulario sigue abierto, con lo ya
      // capturado, para que el usuario elija otra cuenta.
      final resultado = await ejecutarMostrandoSaldoInsuficiente(
        context,
        l10n,
        () => ref.read(registrarPagoDeudaAutorizadoProvider)(
        deudaId: deuda.id,
        fecha: formState.fecha ?? DateTime.now(),
        importe: importe,
        formaPago: formState.formaPago.name,
        cuentaCaja: formState.cuentaCajaCtrl.text.trim().isEmpty ? null : formState.cuentaCajaCtrl.text.trim(),
        cuentaFinancieraId: formState.cuentaFinancieraId,
        referencia: formState.referenciaCtrl.text.trim().isEmpty ? null : formState.referenciaCtrl.text.trim(),
        observaciones: formState.observacionesCtrl.text.trim().isEmpty ? null : formState.observacionesCtrl.text.trim(),
        ),
      );
      if (resultado == null) return null;
      if (!context.mounted) return false;
      switch (resultado) {
        case RegistrarPagoDeudaExitoso():
          RisegFeedback.showSuccess(context, l10n.registrarPagoDeudaExito);
          return true;
        case RegistrarPagoDeudaNoExiste():
        case RegistrarPagoDeudaNoActiva():
          RisegFeedback.showError(context, l10n.registrarPagoDeudaErrorNoActiva);
          return false;
        case RegistrarPagoDeudaImporteInvalido():
          errorGeneral = l10n.registrarPagoDeudaErrorImporteInvalido;
          return null;
        case RegistrarPagoDeudaSobrepasaSaldo(:final saldoActual):
          errorGeneral = l10n.registrarPagoDeudaErrorSobrepasaSaldo(formatoCentavosDeuda(saldoActual));
          return null;
        case RegistrarPagoDeudaErrorInesperado():
          RisegFeedback.showError(context, l10n.registrarPagoDeudaErrorInesperado);
          return false;
      }
    },
  );

  return resultado ?? false;
}

final _formKey = GlobalKey<_RegistrarPagoDeudaFormState>();

class _RegistrarPagoDeudaForm extends StatefulWidget {
  _RegistrarPagoDeudaForm({required this.deuda, required this.cuentasFinancieras, this.errorGeneral}) : super(key: _formKey);

  final DeudaData deuda;
  final List<CuentaFinancieraData> cuentasFinancieras;
  final String? errorGeneral;

  @override
  State<_RegistrarPagoDeudaForm> createState() => _RegistrarPagoDeudaFormState();
}

class _RegistrarPagoDeudaFormState extends State<_RegistrarPagoDeudaForm> {
  final importeCtrl = TextEditingController();
  final cuentaCajaCtrl = TextEditingController();
  final referenciaCtrl = TextEditingController();
  final observacionesCtrl = TextEditingController();

  DateTime? fecha = DateTime.now();
  FormaPago formaPago = FormaPago.transferencia;
  String? cuentaFinancieraId;

  @override
  void dispose() {
    importeCtrl.dispose();
    cuentaCajaCtrl.dispose();
    referenciaCtrl.dispose();
    observacionesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    return SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.registrarPagoDeudaSaldoActual(formatoCentavosDeuda(widget.deuda.saldoActual)),
            style: AppTypography.label,
          ),
          const SizedBox(height: AppSpacing.md),
          RisegDateField(label: l10n.registrarPagoDeudaCampoFecha, value: fecha, onChanged: (v) => setState(() => fecha = v)),
          const SizedBox(height: AppSpacing.md),
          RisegTextField(label: l10n.registrarPagoDeudaCampoImporte, controller: importeCtrl, keyboardType: TextInputType.number, autofocus: true),
          const SizedBox(height: AppSpacing.md),
          RisegSelect<FormaPago>(
            label: l10n.egresoCampoFormaPago,
            value: formaPago,
            items: [for (final f in FormaPago.values) RisegSelectItem(value: f, label: formaPagoLabel(l10n, f.name))],
            onChanged: (valor) => setState(() => formaPago = valor ?? formaPago),
          ),
          const SizedBox(height: AppSpacing.md),
          RisegTextField(label: l10n.egresoCampoCuentaCaja, controller: cuentaCajaCtrl),
          const SizedBox(height: AppSpacing.md),
          RisegSelect<String?>(
            label: l10n.movimientoCampoCuentaFinanciera,
            value: cuentaFinancieraId,
            items: [
              RisegSelectItem(value: null, label: l10n.egresoCampoSinAsignar),
              for (final c in widget.cuentasFinancieras) RisegSelectItem(value: c.id, label: c.nombre),
            ],
            onChanged: (valor) => setState(() => cuentaFinancieraId = valor),
          ),
          const SizedBox(height: AppSpacing.md),
          RisegTextField(label: l10n.registrarPagoDeudaCampoReferencia, controller: referenciaCtrl),
          const SizedBox(height: AppSpacing.md),
          RisegTextField(label: l10n.egresoCampoObservaciones, controller: observacionesCtrl),
          if (widget.errorGeneral != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(widget.errorGeneral!, style: AppTypography.caption.copyWith(color: colors.error)),
          ],
        ],
      ),
    );
  }
}
