import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/data/tables/cuenta_financiera_table.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_cuenta_financiera_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/catalogo_repository.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart';

import '../../../finanzas_providers.dart';
import '../../ingresos/widgets/ingreso_monto_utils.dart';
import '../cuentas_financieras_list_screen.dart' show cuentaFinancieraTipoLabel;

/// Diálogo "Registrar cuenta financiera" (Etapa 19C, Parte B) —
/// `saldoInicial`/`fechaSaldoInicial` son el único punto de captura
/// manual de saldo: a partir de ahí, todo se deriva de los
/// `Ingreso`/`Egreso` que se vinculen (ver el doc comment de
/// `RegistrarCuentaFinancieraUseCase`).
///
/// Devuelve `true` si el registro tuvo éxito.
Future<bool> mostrarDialogoRegistrarCuentaFinanciera(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context)!;
  final bancos = await ref.read(catalogoRepositoryProvider).listarBancos();
  if (!context.mounted) return false;
  String errorGeneral = '';

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.cuentasFinancierasBotonRegistrar,
    confirmLabel: l10n.cuentasFinancierasBotonRegistrar,
    cancelLabel: l10n.asignarArticuloBotonCancelar,
    contentBuilder: (_) => _RegistrarCuentaFinancieraForm(bancos: bancos, errorGeneral: errorGeneral.isEmpty ? null : errorGeneral),
    onConfirm: () async {
      final formState = _formKeyGlobal.currentState;
      if (formState == null) return null;
      final datos = formState.recolectar(l10n);
      if (datos == null) {
        errorGeneral = formState.ultimoError ?? '';
        return null;
      }

      final resultado = await ref.read(registrarCuentaFinancieraAutorizadoProvider)(
        nombre: datos.nombre,
        tipo: datos.tipo.name,
        institucionId: datos.institucionId,
        ultimosDigitos: datos.ultimosDigitos,
        saldoInicial: datos.saldoInicial,
        fechaSaldoInicial: datos.fechaSaldoInicial,
        observaciones: datos.observaciones,
      );
      if (!context.mounted) return false;
      switch (resultado) {
        case RegistrarCuentaFinancieraExitoso():
          RisegFeedback.showSuccess(context, l10n.registrarCuentaFinancieraExito);
          return true;
        case RegistrarCuentaFinancieraNombreRequerido():
          errorGeneral = l10n.registrarCuentaFinancieraErrorNombreRequerido;
          return null;
        case RegistrarCuentaFinancieraTipoInvalido():
          errorGeneral = l10n.registrarCuentaFinancieraErrorTipoInvalido;
          return null;
        case RegistrarCuentaFinancieraSaldoInicialInvalido():
          errorGeneral = l10n.registrarCuentaFinancieraErrorSaldoInicialInvalido;
          return null;
        case RegistrarCuentaFinancieraErrorInesperado():
          RisegFeedback.showError(context, l10n.registrarCuentaFinancieraErrorInesperado);
          return false;
      }
    },
  );

  return resultado ?? false;
}

final _formKeyGlobal = GlobalKey<_RegistrarCuentaFinancieraFormState>();

class _DatosCuentaFinanciera {
  _DatosCuentaFinanciera({
    required this.nombre,
    required this.tipo,
    this.institucionId,
    this.ultimosDigitos,
    required this.saldoInicial,
    required this.fechaSaldoInicial,
    this.observaciones,
  });

  final String nombre;
  final TipoCuentaFinanciera tipo;
  final String? institucionId;
  final String? ultimosDigitos;
  final int saldoInicial;
  final DateTime fechaSaldoInicial;
  final String? observaciones;
}

class _RegistrarCuentaFinancieraForm extends StatefulWidget {
  _RegistrarCuentaFinancieraForm({required this.bancos, this.errorGeneral}) : super(key: _formKeyGlobal);

  final List<CatalogoItem> bancos;
  final String? errorGeneral;

  @override
  State<_RegistrarCuentaFinancieraForm> createState() => _RegistrarCuentaFinancieraFormState();
}

class _RegistrarCuentaFinancieraFormState extends State<_RegistrarCuentaFinancieraForm> {
  final _nombreCtrl = TextEditingController();
  final _ultimosDigitosCtrl = TextEditingController();
  final _saldoInicialCtrl = TextEditingController(text: '0');
  final _observacionesCtrl = TextEditingController();

  TipoCuentaFinanciera _tipo = TipoCuentaFinanciera.banco;
  String? _institucionId;
  DateTime? _fechaSaldoInicial = DateTime.now();
  String? _ultimoError;

  String? get ultimoError => _ultimoError;

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _ultimosDigitosCtrl.dispose();
    _saldoInicialCtrl.dispose();
    _observacionesCtrl.dispose();
    super.dispose();
  }

  _DatosCuentaFinanciera? recolectar(AppLocalizations l10n) {
    final nombre = _nombreCtrl.text.trim();
    if (nombre.isEmpty) {
      _ultimoError = l10n.registrarCuentaFinancieraErrorNombreRequerido;
      return null;
    }
    final saldoInicial = centavosDesdeTexto(_saldoInicialCtrl.text.trim().isEmpty ? '0' : _saldoInicialCtrl.text);
    if (saldoInicial == null || saldoInicial < 0) {
      _ultimoError = l10n.registrarCuentaFinancieraErrorSaldoInicialInvalido;
      return null;
    }

    return _DatosCuentaFinanciera(
      nombre: nombre,
      tipo: _tipo,
      institucionId: _tipo == TipoCuentaFinanciera.banco ? _institucionId : null,
      ultimosDigitos: _tipo == TipoCuentaFinanciera.banco && _ultimosDigitosCtrl.text.trim().isNotEmpty
          ? _ultimosDigitosCtrl.text.trim()
          : null,
      saldoInicial: saldoInicial,
      fechaSaldoInicial: _fechaSaldoInicial ?? DateTime.now(),
      observaciones: _observacionesCtrl.text.trim().isEmpty ? null : _observacionesCtrl.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    return SizedBox(
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RisegTextField(label: l10n.registrarCuentaFinancieraCampoNombre, controller: _nombreCtrl, autofocus: true),
          const SizedBox(height: AppSpacing.md),
          RisegSelect<TipoCuentaFinanciera>(
            label: l10n.registrarCuentaFinancieraCampoTipo,
            value: _tipo,
            items: [
              for (final t in TipoCuentaFinanciera.values) RisegSelectItem(value: t, label: cuentaFinancieraTipoLabel(l10n, t.name)),
            ],
            onChanged: (valor) => setState(() => _tipo = valor ?? _tipo),
          ),
          if (_tipo == TipoCuentaFinanciera.banco) ...[
            const SizedBox(height: AppSpacing.md),
            RisegSelect<String?>(
              label: l10n.registrarCuentaFinancieraCampoInstitucion,
              value: _institucionId,
              items: [
                RisegSelectItem(value: null, label: l10n.egresoCampoSinAsignar),
                for (final b in widget.bancos) RisegSelectItem(value: b.id, label: b.nombre),
              ],
              onChanged: (valor) => setState(() => _institucionId = valor),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(label: l10n.registrarCuentaFinancieraCampoUltimosDigitos, controller: _ultimosDigitosCtrl),
          ],
          const SizedBox(height: AppSpacing.md),
          RisegTextField(
            label: l10n.registrarCuentaFinancieraCampoSaldoInicial,
            controller: _saldoInicialCtrl,
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: AppSpacing.md),
          RisegDateField(
            label: l10n.registrarCuentaFinancieraCampoFechaSaldoInicial,
            value: _fechaSaldoInicial,
            onChanged: (valor) => setState(() => _fechaSaldoInicial = valor),
          ),
          const SizedBox(height: AppSpacing.md),
          RisegTextField(label: l10n.registrarCuentaFinancieraCampoObservaciones, controller: _observacionesCtrl),
          if (widget.errorGeneral != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(widget.errorGeneral!, style: AppTypography.caption.copyWith(color: colors.error)),
          ],
        ],
      ),
    );
  }
}
