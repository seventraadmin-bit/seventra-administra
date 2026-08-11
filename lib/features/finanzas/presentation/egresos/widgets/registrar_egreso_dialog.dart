import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/data/tables/categoria_financiera_table.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_egreso_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/servicio_repository.dart';

import '../../../../organizacion/organizacion_providers.dart';
import '../../../finanzas_providers.dart';
import '../../ingresos/widgets/ingreso_monto_utils.dart';
import '../../pagos/pagos_list_screen.dart' show formaPagoLabel;

/// Diálogo "Registrar egreso" (Etapa 4K.1) — 100% captura manual, sin
/// ninguna fuente automática todavía (Nómina/Compras no existen).
///
/// Devuelve `true` si el registro tuvo éxito.
Future<bool> mostrarDialogoRegistrarEgreso(
  BuildContext context,
  WidgetRef ref, {
  required List<ServicioListItem> servicios,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final montoController = TextEditingController();
  DateTime? fechaSeleccionada;
  final conceptoController = TextEditingController();
  final beneficiarioController = TextEditingController();
  final observacionesController = TextEditingController();
  final cuentaCajaController = TextEditingController();
  FormaPago formaSeleccionada = FormaPago.transferencia;
  String? categoriaId;
  String? servicioId;
  String? sucursalId;
  String? areaId;
  String? errorMonto;
  String? errorFecha;
  String? errorConcepto;

  final categorias = await ref.read(categoriaFinancieraRepositoryProvider).listar(tipo: TipoCategoriaFinanciera.egreso.name);
  final sucursales = await ref.read(sucursalRepositoryProvider).listarActivas();
  final areas = await ref.read(areaRepositoryProvider).listarActivas();

  if (!context.mounted) return false;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.registrarEgresoDialogoTitulo,
    confirmLabel: l10n.registrarEgresoBotonConfirmar,
    cancelLabel: l10n.registrarEgresoBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RisegTextField(
              label: l10n.egresoCampoMonto,
              controller: montoController,
              keyboardType: TextInputType.number,
              errorText: errorMonto,
              onChanged: (_) => setState(() => errorMonto = null),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegDateField(
              label: l10n.egresoCampoFecha,
              value: fechaSeleccionada,
              errorText: errorFecha,
              onChanged: (valor) => setState(() {
                fechaSeleccionada = valor;
                errorFecha = null;
              }),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(
              label: l10n.egresoCampoConcepto,
              controller: conceptoController,
              errorText: errorConcepto,
              onChanged: (_) => setState(() => errorConcepto = null),
            ),
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
          ],
        );
      },
    ),
    onConfirm: () async {
      final monto = centavosDesdeTexto(montoController.text);
      if (monto == null || monto <= 0) {
        errorMonto = l10n.egresoErrorMontoInvalido;
        return false;
      }
      if (fechaSeleccionada == null) {
        errorFecha = l10n.egresoCampoFecha;
        return false;
      }
      if (conceptoController.text.trim().isEmpty) {
        errorConcepto = l10n.egresoErrorConceptoRequerido;
        return false;
      }
      final resultado = await ref.read(registrarEgresoUseCaseProvider).ejecutar(
            monto: monto,
            fecha: fechaSeleccionada!,
            categoriaFinancieraId: categoriaId,
            servicioId: servicioId,
            sucursalId: sucursalId,
            areaId: areaId,
            cuentaCaja: cuentaCajaController.text.trim().isEmpty ? null : cuentaCajaController.text.trim(),
            formaPago: formaSeleccionada.name,
            beneficiario: beneficiarioController.text.trim().isEmpty ? null : beneficiarioController.text.trim(),
            concepto: conceptoController.text.trim(),
            observaciones: observacionesController.text.trim().isEmpty ? null : observacionesController.text.trim(),
          );

      if (!context.mounted) return false;

      switch (resultado) {
        case RegistrarEgresoExitoso():
          RisegFeedback.showSuccess(context, l10n.registrarEgresoExito);
          return true;
        case RegistrarEgresoMontoInvalido():
          RisegFeedback.showError(context, l10n.egresoErrorMontoInvalido);
          return false;
        case RegistrarEgresoConceptoRequerido():
          RisegFeedback.showError(context, l10n.egresoErrorConceptoRequerido);
          return false;
        case RegistrarEgresoErrorInesperado():
          RisegFeedback.showError(context, l10n.registrarEgresoErrorInesperado);
          return false;
      }
    },
  );

  montoController.dispose();
  conceptoController.dispose();
  beneficiarioController.dispose();
  observacionesController.dispose();
  cuentaCajaController.dispose();
  return resultado ?? false;
}
