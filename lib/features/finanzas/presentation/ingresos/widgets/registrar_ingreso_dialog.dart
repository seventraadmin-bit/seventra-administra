import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/data/tables/categoria_financiera_table.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_ingreso_manual_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/servicio_repository.dart';

import '../../../../organizacion/organizacion_providers.dart';
import '../../../finanzas_providers.dart';
import '../../pagos/pagos_list_screen.dart' show formaPagoLabel;
import 'ingreso_monto_utils.dart';

/// Diálogo "Registrar ingreso" manual (Etapa 4K.1) — dinero recibido
/// que nunca pasó por una Cuenta por cobrar. El Ingreso automático de
/// un Pago no usa este diálogo, se compone dentro de `PagoRepositoryImpl`.
///
/// Devuelve `true` si el registro tuvo éxito.
Future<bool> mostrarDialogoRegistrarIngreso(
  BuildContext context,
  WidgetRef ref, {
  required List<ServicioListItem> servicios,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final montoController = TextEditingController();
  DateTime? fechaSeleccionada;
  final conceptoController = TextEditingController();
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

  final categorias = await ref.read(categoriaFinancieraRepositoryProvider).listar(tipo: TipoCategoriaFinanciera.ingreso.name);
  final sucursales = await ref.read(sucursalRepositoryProvider).listarActivas();
  final areas = await ref.read(areaRepositoryProvider).listarActivas();

  if (!context.mounted) return false;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.registrarIngresoDialogoTitulo,
    confirmLabel: l10n.registrarIngresoBotonConfirmar,
    cancelLabel: l10n.registrarIngresoBotonCancelar,
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
              errorText: errorFecha,
              onChanged: (valor) => setState(() {
                fechaSeleccionada = valor;
                errorFecha = null;
              }),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(
              label: l10n.ingresoCampoConcepto,
              controller: conceptoController,
              errorText: errorConcepto,
              onChanged: (_) => setState(() => errorConcepto = null),
            ),
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
            RisegTextField(label: l10n.ingresoCampoObservaciones, controller: observacionesController),
          ],
        );
      },
    ),
    onConfirm: () async {
      final monto = centavosDesdeTexto(montoController.text);
      if (monto == null || monto <= 0) {
        errorMonto = l10n.ingresoErrorMontoInvalido;
        return false;
      }
      if (fechaSeleccionada == null) {
        errorFecha = l10n.ingresoCampoFecha;
        return false;
      }
      if (conceptoController.text.trim().isEmpty) {
        errorConcepto = l10n.ingresoErrorConceptoRequerido;
        return false;
      }
      final resultado = await ref.read(registrarIngresoManualUseCaseProvider).ejecutar(
            monto: monto,
            fecha: fechaSeleccionada!,
            categoriaFinancieraId: categoriaId,
            servicioId: servicioId,
            sucursalId: sucursalId,
            areaId: areaId,
            cuentaCaja: cuentaCajaController.text.trim().isEmpty ? null : cuentaCajaController.text.trim(),
            formaPago: formaSeleccionada.name,
            concepto: conceptoController.text.trim(),
            observaciones: observacionesController.text.trim().isEmpty ? null : observacionesController.text.trim(),
          );

      if (!context.mounted) return false;

      switch (resultado) {
        case RegistrarIngresoManualExitoso():
          RisegFeedback.showSuccess(context, l10n.registrarIngresoExito);
          return true;
        case RegistrarIngresoManualMontoInvalido():
          RisegFeedback.showError(context, l10n.ingresoErrorMontoInvalido);
          return false;
        case RegistrarIngresoManualConceptoRequerido():
          RisegFeedback.showError(context, l10n.ingresoErrorConceptoRequerido);
          return false;
        case RegistrarIngresoManualErrorInesperado():
          RisegFeedback.showError(context, l10n.registrarIngresoErrorInesperado);
          return false;
      }
    },
  );

  montoController.dispose();
  conceptoController.dispose();
  observacionesController.dispose();
  cuentaCajaController.dispose();
  return resultado ?? false;
}
