import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/data/tables/categoria_financiera_table.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/corregir_ingreso_usecase.dart';

import '../../../../organizacion/organizacion_providers.dart';
import '../../../finanzas_providers.dart';
import '../../pagos/pagos_list_screen.dart' show formaPagoLabel;
import '../ingresos_controller.dart';
import 'ingreso_monto_utils.dart';

/// Diálogo para corregir un Ingreso MANUAL (Etapa 4K.1; `monto`
/// agregado en la etapa "Ingresos y Egresos" — antes solo metadatos).
/// Solo se abre para un Ingreso manual — uno automático (`pagoId !=
/// null`) nunca llega aquí (`CorregirIngresoUseCase` lo bloquearía de
/// todas formas, pero el botón que abre este diálogo ya está oculto en
/// `IngresoDetalleDialog` para ese caso).
///
/// Devuelve `true` si la corrección tuvo éxito.
Future<bool> mostrarDialogoCorregirIngreso(BuildContext context, WidgetRef ref, IngresoData ingreso) async {
  final l10n = AppLocalizations.of(context)!;
  final montoController = TextEditingController(text: (ingreso.monto / 100).toStringAsFixed(2));
  DateTime fechaSeleccionada = ingreso.fecha;
  final conceptoController = TextEditingController(text: ingreso.concepto);
  final observacionesController = TextEditingController(text: ingreso.observaciones ?? '');
  final cuentaCajaController = TextEditingController(text: ingreso.cuentaCaja ?? '');
  FormaPago formaSeleccionada = FormaPago.values.byName(ingreso.formaPago);
  String? categoriaId = ingreso.categoriaFinancieraId;
  String? servicioId = ingreso.servicioId;
  String? sucursalId = ingreso.sucursalId;
  String? areaId = ingreso.areaId;
  String? cuentaFinancieraId = ingreso.cuentaFinancieraId;
  final motivoController = TextEditingController();
  String? errorMonto;
  String? errorMotivo;

  final categorias = await ref.read(categoriaFinancieraRepositoryProvider).listar(tipo: TipoCategoriaFinanciera.ingreso.name);
  final servicios = await ref.read(servicioRepositoryProvider).listar();
  final sucursales = await ref.read(sucursalRepositoryProvider).listarActivas();
  final areas = await ref.read(areaRepositoryProvider).listarActivas();
  final cuentasFinancieras = await ref.read(cuentaFinancieraRepositoryProvider).listar(soloActivas: true);

  if (!context.mounted) return false;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.corregirIngresoDialogoTitulo,
    confirmLabel: l10n.corregirIngresoBotonConfirmar,
    cancelLabel: l10n.corregirIngresoBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RisegTextField(
              label: l10n.ingresoCampoMonto,
              controller: montoController,
              keyboardType: TextInputType.number,
              errorText: errorMonto,
              onChanged: (_) => setState(() => errorMonto = null),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegDateField(
              label: l10n.ingresoCampoFecha,
              value: fechaSeleccionada,
              onChanged: (valor) => setState(() => fechaSeleccionada = valor),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(label: l10n.ingresoCampoConcepto, controller: conceptoController),
            const SizedBox(height: AppSpacing.md),
            RisegSelect<FormaPago>(
              label: l10n.ingresoCampoFormaPago,
              value: formaSeleccionada,
              items: [
                for (final f in FormaPago.values) RisegSelectItem(value: f, label: formaPagoLabel(l10n, f.name)),
              ],
              onChanged: (valor) => setState(() => formaSeleccionada = valor ?? formaSeleccionada),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegSelect<String?>(
              label: l10n.ingresoCampoCategoria,
              value: categoriaId,
              items: [
                RisegSelectItem(value: null, label: l10n.ingresoCampoSinAsignar),
                for (final c in categorias) RisegSelectItem(value: c.id, label: c.nombre),
              ],
              onChanged: (valor) => setState(() => categoriaId = valor),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegSelect<String?>(
              label: l10n.ingresoCampoServicio,
              value: servicioId,
              items: [
                RisegSelectItem(value: null, label: l10n.ingresoCampoSinAsignar),
                for (final s in servicios) RisegSelectItem(value: s.servicio.id, label: s.servicio.nombre),
              ],
              onChanged: (valor) => setState(() => servicioId = valor),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegSelect<String?>(
              label: l10n.ingresoCampoSucursal,
              value: sucursalId,
              items: [
                RisegSelectItem(value: null, label: l10n.ingresoCampoSinAsignar),
                for (final s in sucursales) RisegSelectItem(value: s.id, label: s.nombre),
              ],
              onChanged: (valor) => setState(() => sucursalId = valor),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegSelect<String?>(
              label: l10n.ingresoCampoArea,
              value: areaId,
              items: [
                RisegSelectItem(value: null, label: l10n.ingresoCampoSinAsignar),
                for (final a in areas) RisegSelectItem(value: a.id, label: a.nombre),
              ],
              onChanged: (valor) => setState(() => areaId = valor),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(label: l10n.ingresoCampoCuentaCaja, controller: cuentaCajaController),
            const SizedBox(height: AppSpacing.md),
            RisegSelect<String?>(
              label: l10n.movimientoCampoCuentaFinanciera,
              value: cuentaFinancieraId,
              items: [
                RisegSelectItem(value: null, label: l10n.ingresoCampoSinAsignar),
                for (final c in cuentasFinancieras) RisegSelectItem(value: c.id, label: c.nombre),
              ],
              onChanged: (valor) => setState(() => cuentaFinancieraId = valor),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(label: l10n.ingresoCampoObservaciones, controller: observacionesController),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(
              label: l10n.corregirIngresoCampoMotivo,
              controller: motivoController,
              errorText: errorMotivo,
              onChanged: (_) => setState(() => errorMotivo = null),
            ),
          ],
        );
      },
    ),
    onConfirm: () async {
      final monto = centavosDesdeTexto(montoController.text);
      if (monto == null || monto <= 0) {
        errorMonto = l10n.ingresoErrorMontoInvalido;
        return null;
      }
      if (motivoController.text.trim().isEmpty) {
        errorMotivo = l10n.corregirIngresoErrorMotivoRequerido;
        return null;
      }

      final resultado = await ref.read(ingresosControllerProvider.notifier).corregir(
            ingresoId: ingreso.id,
            monto: monto,
            fecha: fechaSeleccionada,
            categoriaFinancieraId: categoriaId,
            servicioId: servicioId,
            sucursalId: sucursalId,
            areaId: areaId,
            cuentaCaja: cuentaCajaController.text.trim().isEmpty ? null : cuentaCajaController.text.trim(),
            cuentaFinancieraId: cuentaFinancieraId,
            limpiarCuentaFinancieraId: cuentaFinancieraId == null,
            formaPago: formaSeleccionada.name,
            concepto: conceptoController.text.trim(),
            observaciones: observacionesController.text.trim().isEmpty ? null : observacionesController.text.trim(),
            motivo: motivoController.text.trim(),
          );

      if (!context.mounted) return false;

      switch (resultado) {
        case CorregirIngresoExitoso():
          RisegFeedback.showSuccess(context, l10n.corregirIngresoExito);
          return true;
        case CorregirIngresoCancelado():
          RisegFeedback.showError(context, l10n.corregirIngresoErrorCancelado);
          return false;
        case CorregirIngresoPagoAutomatico():
          RisegFeedback.showError(context, l10n.corregirIngresoErrorPagoAutomatico);
          return false;
        case CorregirIngresoMotivoRequerido():
          errorMotivo = l10n.corregirIngresoErrorMotivoRequerido;
          return null;
        case CorregirIngresoMontoInvalido():
          errorMonto = l10n.ingresoErrorMontoInvalido;
          return null;
        case CorregirIngresoNoExiste():
        case CorregirIngresoErrorInesperado():
          RisegFeedback.showError(context, l10n.corregirIngresoErrorInesperado);
          return false;
      }
    },
  );

  conceptoController.dispose();
  observacionesController.dispose();
  cuentaCajaController.dispose();
  motivoController.dispose();
  return resultado ?? false;
}
