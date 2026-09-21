import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/data/tables/deuda_table.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/calcular_fecha_tarjeta_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_deuda_usecase.dart';

import '../../../finanzas_providers.dart';
import '../../ingresos/widgets/ingreso_monto_utils.dart';
import '../deudas_credito_list_screen.dart' show deudaTipoLabel;

/// Diálogo "Registrar deuda" (Etapa 19, ampliado por "tarjeta de
/// crédito como línea revolvente") — cubre tanto una deuda nueva como
/// una ya existente al incorporarse a RISEG ONE (saldo inicial
/// distinto al importe original, ver el doc comment de
/// `RegistrarDeudaUseCase`), con el mismo formulario para deuda fija.
/// Para `tipo == tarjetaCredito` el formulario es dinámico: oculta los
/// conceptos que no aplican a una línea revolvente (importe original,
/// "es una deuda nueva", vencimiento/pago programado/periodicidad) y
/// captura en su lugar límite de crédito, saldo inicial + su fecha, y
/// la regla explícita de fecha límite de pago. Nunca genera un Egreso:
/// el alta no es un pago.
///
/// Devuelve `true` si el registro tuvo éxito.
Future<bool> mostrarDialogoRegistrarDeuda(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context)!;
  String errorGeneral = '';

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.deudasCreditoBotonRegistrar,
    confirmLabel: l10n.deudasCreditoBotonRegistrar,
    cancelLabel: l10n.asignarArticuloBotonCancelar,
    contentBuilder: (_) => _RegistrarDeudaForm(errorGeneral: errorGeneral.isEmpty ? null : errorGeneral),
    onConfirm: () async {
      final formState = _formKeyGlobal.currentState;
      if (formState == null) return null;
      final datos = formState.recolectar(l10n);
      if (datos == null) {
        errorGeneral = formState.ultimoError ?? '';
        return null;
      }

      final resultado = await ref.read(registrarDeudaAutorizadoProvider)(
        nombre: datos.nombre,
        tipo: datos.tipo.name,
        acreedor: datos.acreedor,
        fechaOrigen: datos.fechaOrigen,
        importeOriginal: datos.importeOriginal,
        saldoInicial: datos.saldoInicial,
        fechaSaldoInicial: datos.fechaSaldoInicial,
        fechaVencimiento: datos.fechaVencimiento,
        pagoProgramado: datos.pagoProgramado,
        periodicidad: datos.periodicidad,
        tasaInteres: datos.tasaInteres,
        referencia: datos.referencia,
        observaciones: datos.observaciones,
        tarjetaUltimosDigitos: datos.tarjetaUltimosDigitos,
        tarjetaLimiteCredito: datos.tarjetaLimiteCredito,
        tarjetaDiaCorte: datos.tarjetaDiaCorte,
        tarjetaDiaPago: datos.tarjetaDiaPago,
        tarjetaReglaFechaPago: datos.tarjetaReglaFechaPago?.name,
        tarjetaDiasDespuesCorte: datos.tarjetaDiasDespuesCorte,
        tarjetaTipoTasa: datos.tarjetaTipoTasa?.name,
        tarjetaTasaReferencia: datos.tarjetaTasaReferencia,
        tarjetaTasaDiferencial: datos.tarjetaTasaDiferencial,
        tarjetaTasaMasIva: datos.tarjetaTasaMasIva,
        tarjetaTasaDescripcion: datos.tarjetaTasaDescripcion,
        tarjetaCat: datos.tarjetaCat,
        tarjetaCatIncluyeIva: datos.tarjetaCatIncluyeIva,
        tarjetaVencimientoCubiertoHasta: datos.tarjetaVencimientoCubiertoHasta,
      );
      if (!context.mounted) return false;
      switch (resultado) {
        case RegistrarDeudaExitoso():
          RisegFeedback.showSuccess(context, l10n.registrarDeudaExito);
          return true;
        case RegistrarDeudaNombreRequerido():
          errorGeneral = l10n.registrarDeudaErrorNombreRequerido;
          return null;
        case RegistrarDeudaImporteInvalido():
          errorGeneral = l10n.registrarDeudaErrorImporteInvalido;
          return null;
        case RegistrarDeudaFechaOrigenRequerida():
          errorGeneral = l10n.registrarDeudaErrorFechaOrigenRequerida;
          return null;
        case RegistrarDeudaSaldoInicialInvalido():
          errorGeneral = l10n.registrarDeudaErrorSaldoInicialInvalido;
          return null;
        case RegistrarDeudaFechaSaldoInicialRequerida():
          errorGeneral = l10n.registrarDeudaErrorFechaSaldoInicialRequerida;
          return null;
        case RegistrarDeudaErrorInesperado():
          RisegFeedback.showError(context, l10n.registrarDeudaErrorInesperado);
          return false;
      }
    },
  );

  return resultado ?? false;
}

final _formKeyGlobal = GlobalKey<_RegistrarDeudaFormState>();

class _DatosDeuda {
  _DatosDeuda({
    required this.nombre,
    required this.tipo,
    this.acreedor,
    this.fechaOrigen,
    this.importeOriginal,
    required this.saldoInicial,
    this.fechaSaldoInicial,
    this.fechaVencimiento,
    this.pagoProgramado,
    this.periodicidad,
    this.tasaInteres,
    this.referencia,
    this.observaciones,
    this.tarjetaUltimosDigitos,
    this.tarjetaLimiteCredito,
    this.tarjetaDiaCorte,
    this.tarjetaDiaPago,
    this.tarjetaReglaFechaPago,
    this.tarjetaDiasDespuesCorte,
    this.tarjetaTipoTasa,
    this.tarjetaTasaReferencia,
    this.tarjetaTasaDiferencial,
    this.tarjetaTasaMasIva,
    this.tarjetaTasaDescripcion,
    this.tarjetaCat,
    this.tarjetaCatIncluyeIva,
    this.tarjetaVencimientoCubiertoHasta,
  });

  final String nombre;
  final TipoDeuda tipo;
  final String? acreedor;
  final DateTime? fechaOrigen;
  final int? importeOriginal;
  final int saldoInicial;
  final DateTime? fechaSaldoInicial;
  final DateTime? fechaVencimiento;
  final int? pagoProgramado;
  final String? periodicidad;
  final double? tasaInteres;
  final String? referencia;
  final String? observaciones;
  final String? tarjetaUltimosDigitos;
  final int? tarjetaLimiteCredito;
  final int? tarjetaDiaCorte;
  final int? tarjetaDiaPago;
  final ReglaFechaLimitePagoTarjeta? tarjetaReglaFechaPago;
  final int? tarjetaDiasDespuesCorte;
  final TipoTasaTarjeta? tarjetaTipoTasa;
  final String? tarjetaTasaReferencia;
  final double? tarjetaTasaDiferencial;
  final bool? tarjetaTasaMasIva;
  final String? tarjetaTasaDescripcion;
  final double? tarjetaCat;
  final bool? tarjetaCatIncluyeIva;
  final DateTime? tarjetaVencimientoCubiertoHasta;
}

class _RegistrarDeudaForm extends StatefulWidget {
  _RegistrarDeudaForm({this.errorGeneral}) : super(key: _formKeyGlobal);

  final String? errorGeneral;

  @override
  State<_RegistrarDeudaForm> createState() => _RegistrarDeudaFormState();
}

class _RegistrarDeudaFormState extends State<_RegistrarDeudaForm> {
  final _nombreCtrl = TextEditingController();
  final _acreedorCtrl = TextEditingController();
  final _importeCtrl = TextEditingController();
  final _saldoInicialCtrl = TextEditingController();
  final _pagoProgramadoCtrl = TextEditingController();
  final _tasaInteresCtrl = TextEditingController();
  final _referenciaCtrl = TextEditingController();
  final _observacionesCtrl = TextEditingController();
  final _tarjetaUltimosDigitosCtrl = TextEditingController();
  final _tarjetaLimiteCtrl = TextEditingController();
  final _tarjetaDiaCorteCtrl = TextEditingController();
  final _tarjetaDiaPagoCtrl = TextEditingController();
  final _tarjetaDiasDespuesCorteCtrl = TextEditingController();
  final _tarjetaTasaReferenciaCtrl = TextEditingController();
  final _tarjetaTasaDiferencialCtrl = TextEditingController();
  final _tarjetaTasaDescripcionCtrl = TextEditingController();
  final _tarjetaCatCtrl = TextEditingController();

  TipoDeuda _tipo = TipoDeuda.prestamo;
  DateTime? _fechaOrigen = DateTime.now();
  bool _fechaOrigenDesconocida = false;
  DateTime? _fechaSaldoInicial = DateTime.now();
  DateTime? _fechaVencimiento;
  String? _periodicidad;
  bool _saldoIgualaImporte = true;
  ReglaFechaLimitePagoTarjeta _tarjetaRegla = ReglaFechaLimitePagoTarjeta.diaFijo;
  TipoTasaTarjeta? _tarjetaTipoTasa;
  bool? _tarjetaTasaMasIva;
  bool? _tarjetaCatIncluyeIva;
  bool _cicloVigenteCubierto = false;
  String? _ultimoError;

  String? get ultimoError => _ultimoError;

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _acreedorCtrl.dispose();
    _importeCtrl.dispose();
    _saldoInicialCtrl.dispose();
    _pagoProgramadoCtrl.dispose();
    _tasaInteresCtrl.dispose();
    _referenciaCtrl.dispose();
    _observacionesCtrl.dispose();
    _tarjetaUltimosDigitosCtrl.dispose();
    _tarjetaLimiteCtrl.dispose();
    _tarjetaDiaCorteCtrl.dispose();
    _tarjetaDiaPagoCtrl.dispose();
    _tarjetaDiasDespuesCorteCtrl.dispose();
    _tarjetaTasaReferenciaCtrl.dispose();
    _tarjetaTasaDiferencialCtrl.dispose();
    _tarjetaTasaDescripcionCtrl.dispose();
    _tarjetaCatCtrl.dispose();
    super.dispose();
  }

  _DatosDeuda? recolectar(AppLocalizations l10n) {
    final nombre = _nombreCtrl.text.trim();
    if (nombre.isEmpty) {
      _ultimoError = l10n.registrarDeudaErrorNombreRequerido;
      return null;
    }

    final esTarjeta = _tipo == TipoDeuda.tarjetaCredito;

    if (!esTarjeta) {
      final importeOriginal = centavosDesdeTexto(_importeCtrl.text);
      if (importeOriginal == null || importeOriginal <= 0) {
        _ultimoError = l10n.registrarDeudaErrorImporteInvalido;
        return null;
      }
      final saldoInicial = _saldoIgualaImporte ? importeOriginal : centavosDesdeTexto(_saldoInicialCtrl.text);
      if (saldoInicial == null || saldoInicial < 0 || saldoInicial > importeOriginal) {
        _ultimoError = l10n.registrarDeudaErrorSaldoInicialInvalido;
        return null;
      }

      return _DatosDeuda(
        nombre: nombre,
        tipo: _tipo,
        acreedor: _acreedorCtrl.text.trim().isEmpty ? null : _acreedorCtrl.text.trim(),
        fechaOrigen: _fechaOrigen ?? DateTime.now(),
        importeOriginal: importeOriginal,
        saldoInicial: saldoInicial,
        fechaSaldoInicial: saldoInicial > 0 ? (_fechaOrigen ?? DateTime.now()) : null,
        fechaVencimiento: _fechaVencimiento,
        pagoProgramado: centavosDesdeTexto(_pagoProgramadoCtrl.text),
        periodicidad: _periodicidad,
        tasaInteres: double.tryParse(_tasaInteresCtrl.text.trim().replaceAll(',', '')),
        referencia: _referenciaCtrl.text.trim().isEmpty ? null : _referenciaCtrl.text.trim(),
        observaciones: _observacionesCtrl.text.trim().isEmpty ? null : _observacionesCtrl.text.trim(),
      );
    }

    // Tarjeta de crédito — línea revolvente: sin "importe original",
    // saldo inicial siempre visible (default 0, sin checkbox — una
    // tarjeta nueva sin saldo previo es el caso más común).
    final limite = centavosDesdeTexto(_tarjetaLimiteCtrl.text);
    final saldoInicial = centavosDesdeTexto(_saldoInicialCtrl.text) ?? 0;
    if (saldoInicial < 0 || (limite != null && limite > 0 && saldoInicial > limite)) {
      _ultimoError = l10n.registrarDeudaErrorSaldoInicialInvalido;
      return null;
    }
    if (saldoInicial > 0 && _fechaSaldoInicial == null) {
      _ultimoError = l10n.registrarDeudaErrorFechaSaldoInicialRequerida;
      return null;
    }

    final tipoTasa = _tarjetaTipoTasa;
    final diaCorte = int.tryParse(_tarjetaDiaCorteCtrl.text.trim());
    final diaPago = _tarjetaRegla == ReglaFechaLimitePagoTarjeta.diaFijo ? int.tryParse(_tarjetaDiaPagoCtrl.text.trim()) : null;
    final diasDespuesCorte = _tarjetaRegla == ReglaFechaLimitePagoTarjeta.diasDespuesDeCorte
        ? int.tryParse(_tarjetaDiasDespuesCorteCtrl.text.trim())
        : null;
    // Reconciliación de apertura (Etapa "ciclo de TDC") — se calcula
    // con la MISMA fórmula que el Dashboard/listado mostrarían ahora
    // mismo como "próximo pago" (sin cobertura), y ese valor pasa a
    // ser el ancla. `null` si la configuración está incompleta (nunca
    // se inventa una fecha). Puro dato: nunca genera Egreso/
    // MovimientoDeuda ni toca CuentaFinanciera.
    final vencimientoCubiertoHasta = _cicloVigenteCubierto
        ? proximaFechaLimitePago(
            regla: _tarjetaRegla.name,
            diaFijo: diaPago,
            diaCorte: diaCorte,
            diasDespuesCorte: diasDespuesCorte,
            hoy: DateTime.now(),
          )
        : null;

    return _DatosDeuda(
      nombre: nombre,
      tipo: _tipo,
      acreedor: _acreedorCtrl.text.trim().isEmpty ? null : _acreedorCtrl.text.trim(),
      fechaOrigen: _fechaOrigenDesconocida ? null : (_fechaOrigen ?? DateTime.now()),
      saldoInicial: saldoInicial,
      fechaSaldoInicial: _fechaSaldoInicial,
      tasaInteres: tipoTasa == TipoTasaTarjeta.fija ? double.tryParse(_tasaInteresCtrl.text.trim().replaceAll(',', '')) : null,
      referencia: _referenciaCtrl.text.trim().isEmpty ? null : _referenciaCtrl.text.trim(),
      observaciones: _observacionesCtrl.text.trim().isEmpty ? null : _observacionesCtrl.text.trim(),
      tarjetaUltimosDigitos: _tarjetaUltimosDigitosCtrl.text.trim().isEmpty ? null : _tarjetaUltimosDigitosCtrl.text.trim(),
      tarjetaLimiteCredito: limite,
      tarjetaDiaCorte: diaCorte,
      tarjetaDiaPago: diaPago,
      tarjetaReglaFechaPago: _tarjetaRegla,
      tarjetaDiasDespuesCorte: diasDespuesCorte,
      tarjetaVencimientoCubiertoHasta: vencimientoCubiertoHasta,
      tarjetaTipoTasa: tipoTasa,
      tarjetaTasaReferencia:
          tipoTasa == TipoTasaTarjeta.variable && _tarjetaTasaReferenciaCtrl.text.trim().isNotEmpty
              ? _tarjetaTasaReferenciaCtrl.text.trim()
              : null,
      tarjetaTasaDiferencial: tipoTasa == TipoTasaTarjeta.variable
          ? double.tryParse(_tarjetaTasaDiferencialCtrl.text.trim().replaceAll(',', ''))
          : null,
      tarjetaTasaMasIva: tipoTasa == TipoTasaTarjeta.variable ? _tarjetaTasaMasIva : null,
      tarjetaTasaDescripcion:
          tipoTasa == TipoTasaTarjeta.variable && _tarjetaTasaDescripcionCtrl.text.trim().isNotEmpty
              ? _tarjetaTasaDescripcionCtrl.text.trim()
              : null,
      tarjetaCat: double.tryParse(_tarjetaCatCtrl.text.trim().replaceAll(',', '')),
      tarjetaCatIncluyeIva: _tarjetaCatIncluyeIva,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final esTarjeta = _tipo == TipoDeuda.tarjetaCredito;

    return SizedBox(
      width: 520,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RisegTextField(label: l10n.registrarDeudaCampoNombre, controller: _nombreCtrl, autofocus: true),
          const SizedBox(height: AppSpacing.md),
          RisegSelect<TipoDeuda>(
            label: l10n.deudasCreditoFiltroTipo,
            value: _tipo,
            items: [for (final t in TipoDeuda.values) RisegSelectItem(value: t, label: deudaTipoLabel(l10n, t.name))],
            onChanged: (valor) => setState(() => _tipo = valor ?? _tipo),
          ),
          const SizedBox(height: AppSpacing.md),
          RisegTextField(label: l10n.registrarDeudaCampoAcreedor, controller: _acreedorCtrl),
          const SizedBox(height: AppSpacing.md),
          if (esTarjeta) ...[
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              value: _fechaOrigenDesconocida,
              title: Text(l10n.registrarDeudaCampoFechaOrigenOpcional, style: AppTypography.body),
              onChanged: (valor) => setState(() => _fechaOrigenDesconocida = valor ?? false),
            ),
            if (!_fechaOrigenDesconocida) ...[
              const SizedBox(height: AppSpacing.sm),
              RisegDateField(
                label: l10n.registrarDeudaCampoFechaOrigen,
                value: _fechaOrigen,
                onChanged: (valor) => setState(() => _fechaOrigen = valor),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ] else ...[
            RisegDateField(
              label: l10n.registrarDeudaCampoFechaOrigen,
              value: _fechaOrigen,
              onChanged: (valor) => setState(() => _fechaOrigen = valor),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(label: l10n.registrarDeudaCampoImporteOriginal, controller: _importeCtrl, keyboardType: TextInputType.number),
            const SizedBox(height: AppSpacing.sm),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              value: _saldoIgualaImporte,
              title: Text(l10n.registrarDeudaCampoEsDeudaNueva, style: AppTypography.body),
              onChanged: (valor) => setState(() => _saldoIgualaImporte = valor ?? true),
            ),
            if (!_saldoIgualaImporte) ...[
              RisegTextField(
                label: l10n.registrarDeudaCampoSaldoInicial,
                controller: _saldoInicialCtrl,
                keyboardType: TextInputType.number,
                helperText: l10n.registrarDeudaAyudaSaldoInicial,
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            RisegDateField(
              label: l10n.registrarDeudaCampoFechaVencimiento,
              value: _fechaVencimiento,
              onChanged: (valor) => setState(() => _fechaVencimiento = valor),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(
              label: l10n.registrarDeudaCampoPagoProgramado,
              controller: _pagoProgramadoCtrl,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: AppSpacing.md),
            RisegSelect<String?>(
              label: l10n.registrarDeudaCampoPeriodicidad,
              value: _periodicidad,
              items: [
                RisegSelectItem(value: null, label: l10n.egresoCampoSinAsignar),
                for (final p in PeriodicidadDeuda.values) RisegSelectItem(value: p.name, label: _periodicidadLabel(l10n, p)),
              ],
              onChanged: (valor) => setState(() => _periodicidad = valor),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(label: l10n.registrarDeudaCampoTasaInteres, controller: _tasaInteresCtrl, keyboardType: TextInputType.number),
            const SizedBox(height: AppSpacing.md),
          ],
          RisegTextField(label: l10n.registrarDeudaCampoReferencia, controller: _referenciaCtrl),
          const SizedBox(height: AppSpacing.md),
          RisegTextField(label: l10n.registrarDeudaCampoObservaciones, controller: _observacionesCtrl),
          if (esTarjeta) ...[
            const SizedBox(height: AppSpacing.md),
            Text(l10n.registrarDeudaSeccionTarjeta, style: AppTypography.label),
            const SizedBox(height: AppSpacing.sm),
            RisegTextField(label: l10n.registrarDeudaCampoUltimosDigitos, controller: _tarjetaUltimosDigitosCtrl),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(label: l10n.registrarDeudaCampoLimiteCredito, controller: _tarjetaLimiteCtrl, keyboardType: TextInputType.number),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(
              label: l10n.registrarDeudaCampoSaldoInicial,
              controller: _saldoInicialCtrl,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: AppSpacing.md),
            RisegDateField(
              label: l10n.registrarDeudaCampoFechaSaldoInicial,
              value: _fechaSaldoInicial,
              onChanged: (valor) => setState(() => _fechaSaldoInicial = valor),
              helperText: l10n.registrarDeudaAyudaFechaSaldoInicial,
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(label: l10n.registrarDeudaCampoDiaCorte, controller: _tarjetaDiaCorteCtrl, keyboardType: TextInputType.number),
            const SizedBox(height: AppSpacing.md),
            RisegSelect<ReglaFechaLimitePagoTarjeta>(
              label: l10n.registrarDeudaCampoReglaFechaPago,
              value: _tarjetaRegla,
              items: [
                RisegSelectItem(value: ReglaFechaLimitePagoTarjeta.diaFijo, label: l10n.registrarDeudaReglaDiaFijo),
                RisegSelectItem(value: ReglaFechaLimitePagoTarjeta.diasDespuesDeCorte, label: l10n.registrarDeudaReglaDiasDespuesCorte),
              ],
              onChanged: (valor) => setState(() => _tarjetaRegla = valor ?? _tarjetaRegla),
            ),
            const SizedBox(height: AppSpacing.md),
            if (_tarjetaRegla == ReglaFechaLimitePagoTarjeta.diaFijo)
              RisegTextField(label: l10n.registrarDeudaCampoDiaPago, controller: _tarjetaDiaPagoCtrl, keyboardType: TextInputType.number)
            else
              RisegTextField(
                label: l10n.registrarDeudaCampoDiasDespuesCorte,
                controller: _tarjetaDiasDespuesCorteCtrl,
                keyboardType: TextInputType.number,
              ),
            const SizedBox(height: AppSpacing.sm),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              value: _cicloVigenteCubierto,
              title: Text(l10n.registrarDeudaCampoCicloCubierto, style: AppTypography.body),
              subtitle: Text(l10n.registrarDeudaAyudaCicloCubierto, style: AppTypography.caption.copyWith(color: colors.textMuted)),
              onChanged: (valor) => setState(() => _cicloVigenteCubierto = valor ?? false),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegSelect<TipoTasaTarjeta?>(
              label: l10n.registrarDeudaCampoTipoTasa,
              value: _tarjetaTipoTasa,
              items: [
                RisegSelectItem(value: null, label: l10n.registrarDeudaTipoTasaNoEspecificada),
                RisegSelectItem(value: TipoTasaTarjeta.fija, label: l10n.registrarDeudaTipoTasaFija),
                RisegSelectItem(value: TipoTasaTarjeta.variable, label: l10n.registrarDeudaTipoTasaVariable),
              ],
              onChanged: (valor) => setState(() => _tarjetaTipoTasa = valor),
            ),
            if (_tarjetaTipoTasa == TipoTasaTarjeta.fija) ...[
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.registrarDeudaCampoTasaOrdinariaAnual, controller: _tasaInteresCtrl, keyboardType: TextInputType.number),
            ],
            if (_tarjetaTipoTasa == TipoTasaTarjeta.variable) ...[
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.registrarDeudaCampoTasaReferencia, controller: _tarjetaTasaReferenciaCtrl),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(
                label: l10n.registrarDeudaCampoTasaDiferencial,
                controller: _tarjetaTasaDiferencialCtrl,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: AppSpacing.md),
              RisegSelect<bool?>(
                label: l10n.registrarDeudaCampoTasaMasIva,
                value: _tarjetaTasaMasIva,
                items: [
                  RisegSelectItem(value: null, label: l10n.registrarDeudaIvaNoEspecificado),
                  RisegSelectItem(value: false, label: l10n.registrarDeudaIvaSinIva),
                  RisegSelectItem(value: true, label: l10n.registrarDeudaIvaConIva),
                ],
                onChanged: (valor) => setState(() => _tarjetaTasaMasIva = valor),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.registrarDeudaCampoTasaDescripcion, controller: _tarjetaTasaDescripcionCtrl),
            ],
            const SizedBox(height: AppSpacing.md),
            RisegTextField(label: l10n.registrarDeudaCampoCat, controller: _tarjetaCatCtrl, keyboardType: TextInputType.number),
            const SizedBox(height: AppSpacing.md),
            RisegSelect<bool?>(
              label: l10n.registrarDeudaCampoCatIncluyeIva,
              value: _tarjetaCatIncluyeIva,
              items: [
                RisegSelectItem(value: null, label: l10n.registrarDeudaIvaNoEspecificado),
                RisegSelectItem(value: false, label: l10n.registrarDeudaIvaSinIva),
                RisegSelectItem(value: true, label: l10n.registrarDeudaIvaConIva),
              ],
              onChanged: (valor) => setState(() => _tarjetaCatIncluyeIva = valor),
            ),
          ],
          if (widget.errorGeneral != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(widget.errorGeneral!, style: AppTypography.caption.copyWith(color: colors.error)),
          ],
        ],
      ),
    );
  }

  String _periodicidadLabel(AppLocalizations l10n, PeriodicidadDeuda p) {
    return switch (p) {
      PeriodicidadDeuda.mensual => l10n.registrarDeudaPeriodicidadMensual,
      PeriodicidadDeuda.quincenal => l10n.registrarDeudaPeriodicidadQuincenal,
      PeriodicidadDeuda.semanal => l10n.registrarDeudaPeriodicidadSemanal,
      PeriodicidadDeuda.anual => l10n.registrarDeudaPeriodicidadAnual,
    };
  }
}
