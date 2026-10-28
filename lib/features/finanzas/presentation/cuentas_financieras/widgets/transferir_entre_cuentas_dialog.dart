import 'package:riseg_one/features/finanzas/presentation/mensaje_saldo_insuficiente.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/transferir_entre_cuentas_usecase.dart';

import '../../../finanzas_providers.dart';
import '../cuentas_financieras_controller.dart';
import '../cuentas_financieras_list_screen.dart' show formatoCentavosCuentaFinanciera;


/// Diálogo "Transferir entre cuentas".
///
/// Mover dinero de una cuenta propia a otra **no es un Ingreso ni un
/// Egreso**: no toca ingresos, gasto operativo ni resultado, y "Caja y
/// bancos" global queda idéntico. El diálogo lo hace visible mostrando
/// el saldo de ambas cuentas antes y después.
///
/// Devuelve `true` si la transferencia se registró.
Future<bool> mostrarDialogoTransferir(
  BuildContext context,
  WidgetRef ref, {
  String? cuentaOrigenIdInicial,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final estado = ref.read(cuentasFinancierasControllerProvider);
  final activas = [
    for (final c in estado.cuentas)
      if (c.cicloVidaRegistro == 'activo') c,
  ];
  if (activas.length < 2) {
    RisegFeedback.showError(context, l10n.transferirErrorMismaCuenta);
    return false;
  }

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.transferirTitulo,
    confirmLabel: l10n.transferirConfirmar,
    cancelLabel: l10n.transferirCancelar,
    contentBuilder: (_) => _FormularioTransferencia(
      cuentas: activas,
      saldos: estado.saldosPorCuenta,
      cuentaOrigenIdInicial: cuentaOrigenIdInicial,
    ),
    onConfirm: () async {
      final formulario = _claveFormulario.currentState;
      if (formulario == null) return null;
      return formulario.confirmar(context, ref);
    },
  );
  return resultado ?? false;
}

/// Una `GlobalKey` para que el pie del diálogo alcance el estado del
/// formulario — mismo patrón que los diálogos de Servicios Eventuales.
final _claveFormulario = GlobalKey<_FormularioTransferenciaState>();

class _FormularioTransferencia extends StatefulWidget {
  _FormularioTransferencia({
    required this.cuentas,
    required this.saldos,
    this.cuentaOrigenIdInicial,
  }) : super(key: _claveFormulario);

  final List<CuentaFinancieraData> cuentas;
  final Map<String, int> saldos;
  final String? cuentaOrigenIdInicial;

  @override
  State<_FormularioTransferencia> createState() => _FormularioTransferenciaState();
}

class _FormularioTransferenciaState extends State<_FormularioTransferencia> {
  /// Nulos a propósito: RISEG ONE no elige por el usuario de qué
  /// cuenta sale el dinero. Sólo se precarga cuando hay un contexto
  /// legítimo — abrir Transferir desde el expediente de una cuenta.
  String? _origenId;
  String? _destinoId;
  final _importeController = TextEditingController();
  DateTime _fecha = DateTime.now();
  final _conceptoController = TextEditingController();
  String? _errorImporte;
  String? _errorGeneral;

  @override
  void initState() {
    super.initState();
    _origenId = widget.cuentaOrigenIdInicial;
  }

  @override
  void dispose() {
    _importeController.dispose();
    _conceptoController.dispose();
    super.dispose();
  }

  int? get _importeCentavos {
    final texto = _importeController.text.trim().replaceAll(',', '');
    if (texto.isEmpty) return null;
    final pesos = double.tryParse(texto);
    if (pesos == null) return null;
    return (pesos * 100).round();
  }

  int get _saldoOrigen => _origenId == null ? 0 : (widget.saldos[_origenId] ?? 0);
  int get _saldoDestino => _destinoId == null ? 0 : (widget.saldos[_destinoId] ?? 0);

  /// El saldo va en la propia opción: elegir de dónde sale el dinero
  /// sin ver cuánto hay en cada cuenta es adivinar.
  String _etiqueta(CuentaFinancieraData c) =>
      '${c.nombre}    ${formatoCentavosCuentaFinanciera(widget.saldos[c.id] ?? 0)}';

  /// Devuelve `true` si se registró, o `null` para que el diálogo siga
  /// abierto mostrando el error (contrato de `RisegDialog.showForm`).
  Future<bool?> confirmar(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final importe = _importeCentavos;
    if (importe == null || importe <= 0) {
      setState(() => _errorImporte = l10n.transferirErrorImporte);
      return null;
    }
    if (_origenId == null || _destinoId == null || _destinoId == _origenId) {
      setState(() => _errorGeneral = l10n.transferirErrorMismaCuenta);
      return null;
    }

    final resultado = await ref.read(transferirEntreCuentasAutorizadoProvider)(
      cuentaOrigenId: _origenId!,
      cuentaDestinoId: _destinoId!,
      importe: importe,
      fecha: _fecha,
      concepto: _conceptoController.text.trim().isEmpty ? null : _conceptoController.text.trim(),
    );

    if (!context.mounted) return null;

    switch (resultado) {
      case TransferirEntreCuentasExitoso():
        // Una transferencia cambia el saldo de dos cuentas: se avisa a
        // TODOS los consumidores financieros con el helper compartido,
        // nunca con una lista propia.
        // `WidgetRef` no es `Ref`: la invalidación compartida se aplica
        // desde el controlador, que sí lo es.
        await ref.read(cuentasFinancierasControllerProvider.notifier).reintentarCarga();

        // ⚠️ **LA COMPROBACIÓN VA DESPUÉS DE *CADA* `await`, Y ÉSTE ES EL SEGUNDO.** La
        // guarda de arriba está antes del `switch`, y aquí ya pasó otra espera: entre la
        // recarga y el aviso el diálogo puede haberse cerrado, y buscar un ancestro desde
        // un `context` muerto LANZA. Sin esto, quien cerrara el diálogo mientras la
        // recarga volaba podía recibir un error y ningún aviso de una transferencia de
        // dinero que YA se había hecho.
        //
        // EL `return true` SE QUEDA FUERA DE LA GUARDA a propósito: la transferencia se
        // hizo, así que el resultado del diálogo no depende de que siga abierto.
        if (context.mounted) RisegFeedback.showSuccess(context, l10n.transferirExito);

        return true;
      // Mismo texto central que el resto de los orígenes. Transferir
      // no reparte entre cuentas, así que usa la variante sin
      // multicuenta: sugerirla sería una instrucción falsa.
      case TransferirEntreCuentasSaldoInsuficiente(:final detalle):
        setState(() => _errorGeneral = mensajeDeVeredictoSaldo(l10n, detalle));
        return null;
      case TransferirEntreCuentasFechaAnteriorAlSaldoInicial(:final detalle):
        setState(() => _errorGeneral = mensajeDeVeredictoSaldo(l10n, detalle));
        return null;
      case TransferirEntreCuentasMismaCuenta():
        setState(() => _errorGeneral = l10n.transferirErrorMismaCuenta);
        return null;
      case TransferirEntreCuentasImporteInvalido():
        setState(() => _errorImporte = l10n.transferirErrorImporte);
        return null;
      case TransferirEntreCuentasCuentaNoDisponible():
      case TransferirEntreCuentasErrorInesperado():
        setState(() => _errorGeneral = l10n.transferirErrorInesperado);
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final importe = _importeCentavos ?? 0;
    final destinos = [
      for (final c in widget.cuentas)
        if (c.id != _origenId) c,
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RisegSelect<String?>(
          key: const Key('transferir_origen'),
          label: l10n.transferirCampoOrigen,
          value: _origenId,
          items: [
            RisegSelectItem(value: null, label: l10n.selectorCuentaPlaceholder),
            for (final c in widget.cuentas) RisegSelectItem(value: c.id, label: _etiqueta(c)),
          ],
          onChanged: (valor) => setState(() {
            _origenId = valor;
            // Si el destino coincidía con el nuevo origen se limpia,
            // nunca se sustituye por otro elegido por el sistema.
            if (_destinoId == _origenId) _destinoId = null;
            _errorGeneral = null;
          }),
        ),
        if (_origenId != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.transferirSaldoDisponible(formatoCentavosCuentaFinanciera(_saldoOrigen)),
            style: AppTypography.caption.copyWith(color: colors.textMuted),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        RisegSelect<String?>(
          key: const Key('transferir_destino'),
          label: l10n.transferirCampoDestino,
          value: _destinoId,
          items: [
            RisegSelectItem(value: null, label: l10n.selectorCuentaPlaceholder),
            for (final c in destinos) RisegSelectItem(value: c.id, label: _etiqueta(c)),
          ],
          onChanged: (valor) => setState(() {
            _destinoId = valor;
            _errorGeneral = null;
          }),
        ),
        const SizedBox(height: AppSpacing.md),
        RisegTextField(
          key: const Key('transferir_importe'),
          label: l10n.transferirCampoImporte,
          controller: _importeController,
          keyboardType: TextInputType.number,
          errorText: _errorImporte,
          onChanged: (_) => setState(() {
            _errorImporte = null;
            _errorGeneral = null;
          }),
        ),
        const SizedBox(height: AppSpacing.md),
        RisegDateField(
          label: l10n.transferirCampoFecha,
          value: _fecha,
          onChanged: (valor) => setState(() {
            _fecha = valor;
            _errorGeneral = null;
          }),
        ),
        const SizedBox(height: AppSpacing.md),
        RisegTextField(
          label: l10n.transferirCampoConcepto,
          controller: _conceptoController,
        ),
        const SizedBox(height: AppSpacing.md),
        // El resumen hace evidente que el dinero no desaparece: lo que
        // baja de una cuenta sube en la otra.
        Text(
          l10n.transferirResumenOrigenDespues(formatoCentavosCuentaFinanciera(_saldoOrigen - importe)),
          style: AppTypography.body.copyWith(color: colors.textMuted),
        ),
        Text(
          l10n.transferirResumenDestinoDespues(formatoCentavosCuentaFinanciera(_saldoDestino + importe)),
          style: AppTypography.body.copyWith(color: colors.textMuted),
        ),
        if (_errorGeneral != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            _errorGeneral!,
            key: const Key('transferir_error'),
            style: AppTypography.body.copyWith(color: colors.error),
          ),
        ],
      ],
    );
  }
}
