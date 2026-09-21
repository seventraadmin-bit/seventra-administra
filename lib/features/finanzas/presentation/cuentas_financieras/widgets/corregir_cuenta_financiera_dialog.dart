import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/data/tables/cuenta_financiera_table.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/corregir_cuenta_financiera_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/catalogo_repository.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart';

import '../../../finanzas_providers.dart';

/// Diálogo "Corregir" de una Cuenta financiera (Etapa 19C) — metadata
/// pura, nunca `tipo`/`saldoInicial`/`fechaSaldoInicial` (ver el doc
/// comment de `CorregirCuentaFinancieraUseCase`).
///
/// Devuelve `true` si la corrección tuvo éxito.
Future<bool> mostrarDialogoCorregirCuentaFinanciera(BuildContext context, WidgetRef ref, {required CuentaFinancieraData cuenta}) async {
  final l10n = AppLocalizations.of(context)!;
  final bancos = await ref.read(catalogoRepositoryProvider).listarBancos();
  if (!context.mounted) return false;
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.corregirCuentaFinancieraTitulo,
    confirmLabel: l10n.editarDeudaBotonConfirmar,
    cancelLabel: l10n.asignarArticuloBotonCancelar,
    contentBuilder: (_) => _CorregirCuentaFinancieraForm(cuenta: cuenta, bancos: bancos, errorGeneral: errorGeneral),
    onConfirm: () async {
      final formState = _formKey.currentState;
      if (formState == null) return null;

      final resultado = await ref.read(corregirCuentaFinancieraAutorizadoProvider)(
        cuentaId: cuenta.id,
        nombre: formState.nombreCtrl.text.trim().isEmpty ? null : formState.nombreCtrl.text.trim(),
        institucionId: formState.institucionId,
        limpiarInstitucionId: formState.institucionId == null,
        ultimosDigitos: formState.ultimosDigitosCtrl.text.trim(),
        limpiarUltimosDigitos: formState.ultimosDigitosCtrl.text.trim().isEmpty,
        observaciones: formState.observacionesCtrl.text.trim(),
      );
      if (!context.mounted) return false;
      switch (resultado) {
        case CorregirCuentaFinancieraExitoso():
          RisegFeedback.showSuccess(context, l10n.corregirCuentaFinancieraExito);
          return true;
        case CorregirCuentaFinancieraNoExiste():
          RisegFeedback.showError(context, l10n.corregirCuentaFinancieraErrorInesperado);
          return false;
        case CorregirCuentaFinancieraErrorInesperado():
          RisegFeedback.showError(context, l10n.corregirCuentaFinancieraErrorInesperado);
          return false;
      }
    },
  );

  return resultado ?? false;
}

final _formKey = GlobalKey<_CorregirCuentaFinancieraFormState>();

class _CorregirCuentaFinancieraForm extends StatefulWidget {
  _CorregirCuentaFinancieraForm({required this.cuenta, required this.bancos, this.errorGeneral}) : super(key: _formKey);

  final CuentaFinancieraData cuenta;
  final List<CatalogoItem> bancos;
  final String? errorGeneral;

  @override
  State<_CorregirCuentaFinancieraForm> createState() => _CorregirCuentaFinancieraFormState();
}

class _CorregirCuentaFinancieraFormState extends State<_CorregirCuentaFinancieraForm> {
  late final nombreCtrl = TextEditingController(text: widget.cuenta.nombre);
  late final ultimosDigitosCtrl = TextEditingController(text: widget.cuenta.ultimosDigitos ?? '');
  late final observacionesCtrl = TextEditingController(text: widget.cuenta.observaciones ?? '');
  late String? institucionId = widget.cuenta.institucionId;

  @override
  void dispose() {
    nombreCtrl.dispose();
    ultimosDigitosCtrl.dispose();
    observacionesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final esBanco = widget.cuenta.tipo == TipoCuentaFinanciera.banco.name;

    return SizedBox(
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RisegTextField(label: l10n.registrarCuentaFinancieraCampoNombre, controller: nombreCtrl, autofocus: true),
          if (esBanco) ...[
            const SizedBox(height: AppSpacing.md),
            RisegSelect<String?>(
              label: l10n.registrarCuentaFinancieraCampoInstitucion,
              value: institucionId,
              items: [
                RisegSelectItem(value: null, label: l10n.egresoCampoSinAsignar),
                for (final b in widget.bancos) RisegSelectItem(value: b.id, label: b.nombre),
              ],
              onChanged: (valor) => setState(() => institucionId = valor),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(label: l10n.registrarCuentaFinancieraCampoUltimosDigitos, controller: ultimosDigitosCtrl),
          ],
          const SizedBox(height: AppSpacing.md),
          RisegTextField(label: l10n.registrarCuentaFinancieraCampoObservaciones, controller: observacionesCtrl),
          if (widget.errorGeneral != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(widget.errorGeneral!, style: AppTypography.caption.copyWith(color: colors.error)),
          ],
        ],
      ),
    );
  }
}
