import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/data/tables/categoria_financiera_table.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/corregir_egreso_usecase.dart';

import '../../../../organizacion/organizacion_providers.dart';
import '../../../finanzas_providers.dart';
import '../../pagos/pagos_list_screen.dart' show formaPagoLabel;
import '../egresos_controller.dart';

/// Diálogo para corregir metadatos administrativos de un Egreso
/// (Etapa 4K.1) — nunca `monto` (mismo criterio que `Ingreso`/`Pago`).
///
/// Devuelve `true` si la corrección tuvo éxito.
Future<bool> mostrarDialogoCorregirEgreso(BuildContext context, WidgetRef ref, EgresoData egreso) async {
  final l10n = AppLocalizations.of(context)!;
  DateTime fechaSeleccionada = egreso.fecha;
  final conceptoController = TextEditingController(text: egreso.concepto);
  final beneficiarioController = TextEditingController(text: egreso.beneficiario ?? '');
  final observacionesController = TextEditingController(text: egreso.observaciones ?? '');
  final cuentaCajaController = TextEditingController(text: egreso.cuentaCaja ?? '');
  FormaPago formaSeleccionada = FormaPago.values.byName(egreso.formaPago);
  String? categoriaId = egreso.categoriaFinancieraId;
  String? servicioId = egreso.servicioId;
  String? sucursalId = egreso.sucursalId;
  String? areaId = egreso.areaId;
  final motivoController = TextEditingController();

  final categorias = await ref.read(categoriaFinancieraRepositoryProvider).listar(tipo: TipoCategoriaFinanciera.egreso.name);
  final servicios = await ref.read(servicioRepositoryProvider).listar();
  final sucursales = await ref.read(sucursalRepositoryProvider).listarActivas();
  final areas = await ref.read(areaRepositoryProvider).listarActivas();

  if (!context.mounted) return false;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.corregirEgresoDialogoTitulo,
    confirmLabel: l10n.corregirEgresoBotonConfirmar,
    cancelLabel: l10n.corregirEgresoBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RisegDateField(
              label: l10n.egresoCampoFecha,
              value: fechaSeleccionada,
              onChanged: (valor) => setState(() => fechaSeleccionada = valor),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(label: l10n.egresoCampoConcepto, controller: conceptoController),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(label: l10n.egresoCampoBeneficiario, controller: beneficiarioController),
            const SizedBox(height: AppSpacing.md),
            RisegSelect<FormaPago>(
              label: l10n.egresoCampoFormaPago,
              value: formaSeleccionada,
              items: [
                for (final f in FormaPago.values) RisegSelectItem(value: f, label: formaPagoLabel(l10n, f.name)),
              ],
              onChanged: (valor) => setState(() => formaSeleccionada = valor ?? formaSeleccionada),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegSelect<String?>(
              label: l10n.egresoCampoCategoria,
              value: categoriaId,
              items: [
                RisegSelectItem(value: null, label: l10n.egresoCampoSinAsignar),
                for (final c in categorias) RisegSelectItem(value: c.id, label: c.nombre),
              ],
              onChanged: (valor) => setState(() => categoriaId = valor),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegSelect<String?>(
              label: l10n.egresoCampoServicio,
              value: servicioId,
              items: [
                RisegSelectItem(value: null, label: l10n.egresoCampoSinAsignar),
                for (final s in servicios) RisegSelectItem(value: s.servicio.id, label: s.servicio.nombre),
              ],
              onChanged: (valor) => setState(() => servicioId = valor),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegSelect<String?>(
              label: l10n.egresoCampoSucursal,
              value: sucursalId,
              items: [
                RisegSelectItem(value: null, label: l10n.egresoCampoSinAsignar),
                for (final s in sucursales) RisegSelectItem(value: s.id, label: s.nombre),
              ],
              onChanged: (valor) => setState(() => sucursalId = valor),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegSelect<String?>(
              label: l10n.egresoCampoArea,
              value: areaId,
              items: [
                RisegSelectItem(value: null, label: l10n.egresoCampoSinAsignar),
                for (final a in areas) RisegSelectItem(value: a.id, label: a.nombre),
              ],
              onChanged: (valor) => setState(() => areaId = valor),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(label: l10n.egresoCampoCuentaCaja, controller: cuentaCajaController),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(label: l10n.egresoCampoObservaciones, controller: observacionesController),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(label: l10n.corregirEgresoCampoMotivo, controller: motivoController),
          ],
        );
      },
    ),
    onConfirm: () async {
      final resultado = await ref.read(egresosControllerProvider.notifier).corregir(
            egresoId: egreso.id,
            fecha: fechaSeleccionada,
            categoriaFinancieraId: categoriaId,
            servicioId: servicioId,
            sucursalId: sucursalId,
            areaId: areaId,
            cuentaCaja: cuentaCajaController.text.trim().isEmpty ? null : cuentaCajaController.text.trim(),
            formaPago: formaSeleccionada.name,
            beneficiario: beneficiarioController.text.trim().isEmpty ? null : beneficiarioController.text.trim(),
            concepto: conceptoController.text.trim(),
            observaciones: observacionesController.text.trim().isEmpty ? null : observacionesController.text.trim(),
            motivo: motivoController.text.trim(),
          );

      if (!context.mounted) return false;

      if (resultado is CorregirEgresoExitoso) {
        RisegFeedback.showSuccess(context, l10n.corregirEgresoExito);
        return true;
      }
      if (resultado is CorregirEgresoCancelado) {
        RisegFeedback.showError(context, l10n.corregirEgresoErrorCancelado);
        return false;
      }
      RisegFeedback.showError(context, l10n.corregirEgresoErrorInesperado);
      return false;
    },
  );

  conceptoController.dispose();
  beneficiarioController.dispose();
  observacionesController.dispose();
  cuentaCajaController.dispose();
  motivoController.dispose();
  return resultado ?? false;
}
