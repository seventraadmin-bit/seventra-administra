import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/data/tables/deuda_table.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/calcular_fecha_tarjeta_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/corregir_deuda_usecase.dart';

import '../../../finanzas_providers.dart';
import '../../ingresos/widgets/ingreso_monto_utils.dart';

/// Diálogo "Editar" de una Deuda (Etapa 19, ampliado por "tarjeta de
/// crédito como línea revolvente") — metadata pura, nunca `tipo`/
/// `importeOriginal`/`saldoActual`/`saldoInicial`/`fechaSaldoInicial`/
/// `estatus` (esos solo cambian vía `MovimientoDeuda` o son inmutables
/// post-alta). Para una tarjeta, oculta Vencimiento/Pago programado/
/// Periodicidad (no aplican a una línea revolvente) y agrega el
/// selector de regla de fecha límite de pago.
///
/// Devuelve `true` si la corrección tuvo éxito.
Future<bool> mostrarDialogoEditarDeuda(BuildContext context, WidgetRef ref, {required DeudaData deuda}) async {
  final l10n = AppLocalizations.of(context)!;
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.editarDeudaDialogoTitulo,
    confirmLabel: l10n.editarDeudaBotonConfirmar,
    cancelLabel: l10n.asignarArticuloBotonCancelar,
    contentBuilder: (_) => _EditarDeudaForm(deuda: deuda, errorGeneral: errorGeneral),
    onConfirm: () async {
      final formState = _formKey.currentState;
      if (formState == null) return null;

      final esTarjeta = deuda.tipo == TipoDeuda.tarjetaCredito.name;
      final tipoTasa = formState.tarjetaTipoTasa;
      final resultado = await ref.read(corregirDeudaAutorizadoProvider)(
        deudaId: deuda.id,
        nombre: formState.nombreCtrl.text.trim().isEmpty ? null : formState.nombreCtrl.text.trim(),
        acreedor: formState.acreedorCtrl.text.trim(),
        fechaOrigen: formState.fechaOrigenDesconocida ? null : formState.fechaOrigen,
        limpiarFechaOrigen: formState.fechaOrigenDesconocida,
        fechaVencimiento: formState.fechaVencimiento,
        limpiarFechaVencimiento: formState.fechaVencimiento == null,
        pagoProgramado: centavosDesdeTexto(formState.pagoProgramadoCtrl.text),
        limpiarPagoProgramado: formState.pagoProgramadoCtrl.text.trim().isEmpty,
        periodicidad: formState.periodicidad,
        limpiarPeriodicidad: formState.periodicidad == null,
        tasaInteres: !esTarjeta ? double.tryParse(formState.tasaInteresCtrl.text.trim().replaceAll(',', '')) : null,
        limpiarTasaInteres: esTarjeta
            ? tipoTasa != TipoTasaTarjeta.fija
            : formState.tasaInteresCtrl.text.trim().isEmpty,
        referencia: formState.referenciaCtrl.text.trim(),
        observaciones: formState.observacionesCtrl.text.trim(),
        tarjetaUltimosDigitos: esTarjeta ? formState.tarjetaUltimosDigitosCtrl.text.trim() : null,
        tarjetaLimiteCredito: esTarjeta ? centavosDesdeTexto(formState.tarjetaLimiteCtrl.text) : null,
        tarjetaDiaCorte: esTarjeta ? int.tryParse(formState.tarjetaDiaCorteCtrl.text.trim()) : null,
        tarjetaDiaPago: esTarjeta && formState.tarjetaRegla == ReglaFechaLimitePagoTarjeta.diaFijo
            ? int.tryParse(formState.tarjetaDiaPagoCtrl.text.trim())
            : null,
        tarjetaReglaFechaPago: esTarjeta ? formState.tarjetaRegla.name : null,
        tarjetaDiasDespuesCorte: esTarjeta && formState.tarjetaRegla == ReglaFechaLimitePagoTarjeta.diasDespuesDeCorte
            ? int.tryParse(formState.tarjetaDiasDespuesCorteCtrl.text.trim())
            : null,
        tarjetaTipoTasa: esTarjeta ? tipoTasa?.name : null,
        limpiarTarjetaTipoTasa: esTarjeta && tipoTasa == null,
        tarjetaTasaReferencia: esTarjeta && tipoTasa == TipoTasaTarjeta.variable && formState.tarjetaTasaReferenciaCtrl.text.trim().isNotEmpty
            ? formState.tarjetaTasaReferenciaCtrl.text.trim()
            : null,
        tarjetaTasaDiferencial: esTarjeta && tipoTasa == TipoTasaTarjeta.variable
            ? double.tryParse(formState.tarjetaTasaDiferencialCtrl.text.trim().replaceAll(',', ''))
            : null,
        tarjetaTasaMasIva: esTarjeta && tipoTasa == TipoTasaTarjeta.variable ? formState.tarjetaTasaMasIva : null,
        tarjetaTasaDescripcion: esTarjeta && tipoTasa == TipoTasaTarjeta.variable && formState.tarjetaTasaDescripcionCtrl.text.trim().isNotEmpty
            ? formState.tarjetaTasaDescripcionCtrl.text.trim()
            : null,
        limpiarTasaVariable: esTarjeta && tipoTasa != TipoTasaTarjeta.variable,
        tarjetaCat: esTarjeta ? double.tryParse(formState.tarjetaCatCtrl.text.trim().replaceAll(',', '')) : null,
        tarjetaCatIncluyeIva: esTarjeta ? formState.tarjetaCatIncluyeIva : null,
        limpiarCat: esTarjeta && formState.tarjetaCatCtrl.text.trim().isEmpty,
        // Reconciliación de apertura (Etapa "ciclo de TDC") — solo
        // actúa sobre el CAMBIO respecto del estado ya guardado (mismo
        // criterio "limpiar solo si cambió" que el resto del diálogo):
        // recién marcado calcula el ancla ahora mismo con la MISMA
        // fórmula que el Dashboard/listado mostrarían como "próximo
        // pago"; recién desmarcado limpia; sin cambio, ninguna de las
        // dos — nunca se recalcula un valor ya conciliado.
        tarjetaVencimientoCubiertoHasta: esTarjeta && formState.cicloVigenteCubierto && deuda.tarjetaVencimientoCubiertoHasta == null
            ? proximaFechaLimitePago(
                regla: formState.tarjetaRegla.name,
                diaFijo: formState.tarjetaRegla == ReglaFechaLimitePagoTarjeta.diaFijo
                    ? int.tryParse(formState.tarjetaDiaPagoCtrl.text.trim())
                    : null,
                diaCorte: int.tryParse(formState.tarjetaDiaCorteCtrl.text.trim()),
                diasDespuesCorte: formState.tarjetaRegla == ReglaFechaLimitePagoTarjeta.diasDespuesDeCorte
                    ? int.tryParse(formState.tarjetaDiasDespuesCorteCtrl.text.trim())
                    : null,
                hoy: DateTime.now(),
              )
            : null,
        limpiarTarjetaVencimientoCubierto:
            esTarjeta && !formState.cicloVigenteCubierto && deuda.tarjetaVencimientoCubiertoHasta != null,
      );
      if (!context.mounted) return false;
      switch (resultado) {
        case CorregirDeudaExitoso():
          RisegFeedback.showSuccess(context, l10n.editarDeudaExito);
          return true;
        case CorregirDeudaNoExiste():
          RisegFeedback.showError(context, l10n.editarDeudaErrorInesperado);
          return false;
        case CorregirDeudaErrorInesperado():
          RisegFeedback.showError(context, l10n.editarDeudaErrorInesperado);
          return false;
      }
    },
  );

  return resultado ?? false;
}

final _formKey = GlobalKey<_EditarDeudaFormState>();

class _EditarDeudaForm extends StatefulWidget {
  _EditarDeudaForm({required this.deuda, this.errorGeneral}) : super(key: _formKey);

  final DeudaData deuda;
  final String? errorGeneral;

  @override
  State<_EditarDeudaForm> createState() => _EditarDeudaFormState();
}

class _EditarDeudaFormState extends State<_EditarDeudaForm> {
  late final nombreCtrl = TextEditingController(text: widget.deuda.nombre);
  late final acreedorCtrl = TextEditingController(text: widget.deuda.acreedor ?? '');
  late final pagoProgramadoCtrl =
      TextEditingController(text: widget.deuda.pagoProgramado == null ? '' : (widget.deuda.pagoProgramado! / 100).toString());
  late final tasaInteresCtrl = TextEditingController(text: widget.deuda.tasaInteres?.toString() ?? '');
  late final referenciaCtrl = TextEditingController(text: widget.deuda.referencia ?? '');
  late final observacionesCtrl = TextEditingController(text: widget.deuda.observaciones ?? '');
  late final tarjetaUltimosDigitosCtrl = TextEditingController(text: widget.deuda.tarjetaUltimosDigitos ?? '');
  late final tarjetaLimiteCtrl =
      TextEditingController(text: widget.deuda.tarjetaLimiteCredito == null ? '' : (widget.deuda.tarjetaLimiteCredito! / 100).toString());
  late final tarjetaDiaCorteCtrl = TextEditingController(text: widget.deuda.tarjetaDiaCorte?.toString() ?? '');
  late final tarjetaDiaPagoCtrl = TextEditingController(text: widget.deuda.tarjetaDiaPago?.toString() ?? '');
  late final tarjetaDiasDespuesCorteCtrl = TextEditingController(text: widget.deuda.tarjetaDiasDespuesCorte?.toString() ?? '');
  late final tarjetaTasaReferenciaCtrl = TextEditingController(text: widget.deuda.tarjetaTasaReferencia ?? '');
  late final tarjetaTasaDiferencialCtrl = TextEditingController(text: widget.deuda.tarjetaTasaDiferencial?.toString() ?? '');
  late final tarjetaTasaDescripcionCtrl = TextEditingController(text: widget.deuda.tarjetaTasaDescripcion ?? '');
  late final tarjetaCatCtrl = TextEditingController(text: widget.deuda.tarjetaCat?.toString() ?? '');

  late DateTime? fechaOrigen = widget.deuda.fechaOrigen;
  late bool fechaOrigenDesconocida = widget.deuda.fechaOrigen == null;
  late DateTime? fechaVencimiento = widget.deuda.fechaVencimiento;
  late String? periodicidad = widget.deuda.periodicidad;
  late ReglaFechaLimitePagoTarjeta tarjetaRegla = widget.deuda.tarjetaReglaFechaPago == null
      ? ReglaFechaLimitePagoTarjeta.diaFijo
      : ReglaFechaLimitePagoTarjeta.values.byName(widget.deuda.tarjetaReglaFechaPago!);
  late TipoTasaTarjeta? tarjetaTipoTasa =
      widget.deuda.tarjetaTipoTasa == null ? null : TipoTasaTarjeta.values.byName(widget.deuda.tarjetaTipoTasa!);
  late bool? tarjetaTasaMasIva = widget.deuda.tarjetaTasaMasIva;
  late bool? tarjetaCatIncluyeIva = widget.deuda.tarjetaCatIncluyeIva;
  late bool cicloVigenteCubierto = widget.deuda.tarjetaVencimientoCubiertoHasta != null;

  @override
  void dispose() {
    nombreCtrl.dispose();
    acreedorCtrl.dispose();
    pagoProgramadoCtrl.dispose();
    tasaInteresCtrl.dispose();
    referenciaCtrl.dispose();
    observacionesCtrl.dispose();
    tarjetaUltimosDigitosCtrl.dispose();
    tarjetaLimiteCtrl.dispose();
    tarjetaDiaCorteCtrl.dispose();
    tarjetaDiaPagoCtrl.dispose();
    tarjetaDiasDespuesCorteCtrl.dispose();
    tarjetaTasaReferenciaCtrl.dispose();
    tarjetaTasaDiferencialCtrl.dispose();
    tarjetaTasaDescripcionCtrl.dispose();
    tarjetaCatCtrl.dispose();
    super.dispose();
  }

  String _periodicidadLabel(AppLocalizations l10n, PeriodicidadDeuda p) {
    return switch (p) {
      PeriodicidadDeuda.mensual => l10n.registrarDeudaPeriodicidadMensual,
      PeriodicidadDeuda.quincenal => l10n.registrarDeudaPeriodicidadQuincenal,
      PeriodicidadDeuda.semanal => l10n.registrarDeudaPeriodicidadSemanal,
      PeriodicidadDeuda.anual => l10n.registrarDeudaPeriodicidadAnual,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final esTarjeta = widget.deuda.tipo == TipoDeuda.tarjetaCredito.name;

    return SizedBox(
      width: 520,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RisegTextField(label: l10n.registrarDeudaCampoNombre, controller: nombreCtrl, autofocus: true),
          const SizedBox(height: AppSpacing.md),
          RisegTextField(label: l10n.registrarDeudaCampoAcreedor, controller: acreedorCtrl),
          const SizedBox(height: AppSpacing.md),
          if (esTarjeta) ...[
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              value: fechaOrigenDesconocida,
              title: Text(l10n.registrarDeudaCampoFechaOrigenOpcional, style: AppTypography.body),
              onChanged: (v) => setState(() => fechaOrigenDesconocida = v ?? false),
            ),
            if (!fechaOrigenDesconocida) ...[
              const SizedBox(height: AppSpacing.sm),
              RisegDateField(
                label: l10n.registrarDeudaCampoFechaOrigen,
                value: fechaOrigen,
                onChanged: (v) => setState(() => fechaOrigen = v),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ] else ...[
            RisegDateField(
              label: l10n.registrarDeudaCampoFechaOrigen,
              value: fechaOrigen,
              onChanged: (v) => setState(() => fechaOrigen = v),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegDateField(
              label: l10n.registrarDeudaCampoFechaVencimiento,
              value: fechaVencimiento,
              onChanged: (v) => setState(() => fechaVencimiento = v),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(label: l10n.registrarDeudaCampoPagoProgramado, controller: pagoProgramadoCtrl, keyboardType: TextInputType.number),
            const SizedBox(height: AppSpacing.md),
            RisegSelect<String?>(
              label: l10n.registrarDeudaCampoPeriodicidad,
              value: periodicidad,
              items: [
                RisegSelectItem(value: null, label: l10n.egresoCampoSinAsignar),
                for (final p in PeriodicidadDeuda.values) RisegSelectItem(value: p.name, label: _periodicidadLabel(l10n, p)),
              ],
              onChanged: (v) => setState(() => periodicidad = v),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (!esTarjeta) ...[
            RisegTextField(
              label: l10n.registrarDeudaCampoTasaInteres,
              controller: tasaInteresCtrl,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          RisegTextField(label: l10n.registrarDeudaCampoReferencia, controller: referenciaCtrl),
          const SizedBox(height: AppSpacing.md),
          RisegTextField(label: l10n.registrarDeudaCampoObservaciones, controller: observacionesCtrl),
          if (esTarjeta) ...[
            const SizedBox(height: AppSpacing.md),
            Text(l10n.registrarDeudaSeccionTarjeta, style: AppTypography.label),
            const SizedBox(height: AppSpacing.sm),
            RisegTextField(label: l10n.registrarDeudaCampoUltimosDigitos, controller: tarjetaUltimosDigitosCtrl),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(label: l10n.registrarDeudaCampoLimiteCredito, controller: tarjetaLimiteCtrl, keyboardType: TextInputType.number),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(label: l10n.registrarDeudaCampoDiaCorte, controller: tarjetaDiaCorteCtrl, keyboardType: TextInputType.number),
            const SizedBox(height: AppSpacing.md),
            RisegSelect<ReglaFechaLimitePagoTarjeta>(
              label: l10n.registrarDeudaCampoReglaFechaPago,
              value: tarjetaRegla,
              items: [
                RisegSelectItem(value: ReglaFechaLimitePagoTarjeta.diaFijo, label: l10n.registrarDeudaReglaDiaFijo),
                RisegSelectItem(value: ReglaFechaLimitePagoTarjeta.diasDespuesDeCorte, label: l10n.registrarDeudaReglaDiasDespuesCorte),
              ],
              onChanged: (v) => setState(() => tarjetaRegla = v ?? tarjetaRegla),
            ),
            const SizedBox(height: AppSpacing.md),
            if (tarjetaRegla == ReglaFechaLimitePagoTarjeta.diaFijo)
              RisegTextField(label: l10n.registrarDeudaCampoDiaPago, controller: tarjetaDiaPagoCtrl, keyboardType: TextInputType.number)
            else
              RisegTextField(
                label: l10n.registrarDeudaCampoDiasDespuesCorte,
                controller: tarjetaDiasDespuesCorteCtrl,
                keyboardType: TextInputType.number,
              ),
            const SizedBox(height: AppSpacing.sm),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              value: cicloVigenteCubierto,
              title: Text(l10n.registrarDeudaCampoCicloCubierto, style: AppTypography.body),
              subtitle: Text(l10n.registrarDeudaAyudaCicloCubierto, style: AppTypography.caption.copyWith(color: colors.textMuted)),
              onChanged: (v) => setState(() => cicloVigenteCubierto = v ?? false),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegSelect<TipoTasaTarjeta?>(
              label: l10n.registrarDeudaCampoTipoTasa,
              value: tarjetaTipoTasa,
              items: [
                RisegSelectItem(value: null, label: l10n.registrarDeudaTipoTasaNoEspecificada),
                RisegSelectItem(value: TipoTasaTarjeta.fija, label: l10n.registrarDeudaTipoTasaFija),
                RisegSelectItem(value: TipoTasaTarjeta.variable, label: l10n.registrarDeudaTipoTasaVariable),
              ],
              onChanged: (v) => setState(() => tarjetaTipoTasa = v),
            ),
            if (tarjetaTipoTasa == TipoTasaTarjeta.fija) ...[
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.registrarDeudaCampoTasaOrdinariaAnual, controller: tasaInteresCtrl, keyboardType: TextInputType.number),
            ],
            if (tarjetaTipoTasa == TipoTasaTarjeta.variable) ...[
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.registrarDeudaCampoTasaReferencia, controller: tarjetaTasaReferenciaCtrl),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(
                label: l10n.registrarDeudaCampoTasaDiferencial,
                controller: tarjetaTasaDiferencialCtrl,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: AppSpacing.md),
              RisegSelect<bool?>(
                label: l10n.registrarDeudaCampoTasaMasIva,
                value: tarjetaTasaMasIva,
                items: [
                  RisegSelectItem(value: null, label: l10n.registrarDeudaIvaNoEspecificado),
                  RisegSelectItem(value: false, label: l10n.registrarDeudaIvaSinIva),
                  RisegSelectItem(value: true, label: l10n.registrarDeudaIvaConIva),
                ],
                onChanged: (v) => setState(() => tarjetaTasaMasIva = v),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.registrarDeudaCampoTasaDescripcion, controller: tarjetaTasaDescripcionCtrl),
            ],
            const SizedBox(height: AppSpacing.md),
            RisegTextField(label: l10n.registrarDeudaCampoCat, controller: tarjetaCatCtrl, keyboardType: TextInputType.number),
            const SizedBox(height: AppSpacing.md),
            RisegSelect<bool?>(
              label: l10n.registrarDeudaCampoCatIncluyeIva,
              value: tarjetaCatIncluyeIva,
              items: [
                RisegSelectItem(value: null, label: l10n.registrarDeudaIvaNoEspecificado),
                RisegSelectItem(value: false, label: l10n.registrarDeudaIvaSinIva),
                RisegSelectItem(value: true, label: l10n.registrarDeudaIvaConIva),
              ],
              onChanged: (v) => setState(() => tarjetaCatIncluyeIva = v),
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
}
