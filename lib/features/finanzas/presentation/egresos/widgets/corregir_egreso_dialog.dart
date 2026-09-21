import 'package:riseg_one/features/finanzas/presentation/mensaje_saldo_insuficiente.dart';
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
import '../../ingresos/widgets/ingreso_monto_utils.dart';
import '../../pagos/pagos_list_screen.dart' show formaPagoLabel;
import '../../widgets/origen_financiero_select.dart';
import '../egresos_controller.dart';

/// Diálogo para corregir un Egreso MANUAL (Etapa 4K.1; `monto`
/// agregado en la etapa "Ingresos y Egresos" — antes solo metadatos).
/// Solo se abre para un Egreso manual — uno automático (Compra/Nómina/
/// Tiempo Extra/pago de Deuda) nunca llega aquí (`CorregirEgresoUseCase`
/// lo bloquearía de todas formas, pero el botón que abre este diálogo
/// ya está oculto en `EgresoDetalleDialog` para ese caso).
///
/// Etapa "Origen financiero de Egresos manuales: Cuenta vs. TDC" — la
/// corrección incluye el ORIGEN, cubriendo las 6 transiciones reales
/// (Cuenta→misma/otra Cuenta, TDC→misma/otra TDC, Cuenta→TDC,
/// TDC→Cuenta). Es la vía por la que se arregla un gasto capturado
/// contra la cuenta equivocada cuando en realidad se pagó con tarjeta
/// —el caso real que motivó la etapa— y la única: el Egreso de un
/// gasto manual no tiene otra entidad de origen desde la cual
/// corregirse.
///
/// Devuelve `true` si la corrección tuvo éxito.
Future<bool> mostrarDialogoCorregirEgreso(BuildContext context, WidgetRef ref, EgresoData egreso) async {
  final l10n = AppLocalizations.of(context)!;
  final montoController = TextEditingController(text: (egreso.monto / 100).toStringAsFixed(2));
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
  ClaveOrigenFinanciero? origenFinanciero = claveOrigenDeEgreso(egreso);
  final motivoController = TextEditingController();
  String? errorMonto;
  String? errorMotivo;

  final categorias = await ref.read(categoriaFinancieraRepositoryProvider).listar(tipo: TipoCategoriaFinanciera.egreso.name);
  final servicios = await ref.read(servicioRepositoryProvider).listar();
  final sucursales = await ref.read(sucursalRepositoryProvider).listarActivas();
  final areas = await ref.read(areaRepositoryProvider).listarActivas();
  final cuentasFinancieras = await ref.read(cuentaFinancieraRepositoryProvider).listar(soloActivas: true);
  final tarjetasActivas = await ref.read(deudaRepositoryProvider).listarTarjetasActivas();

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
            // Mismo selector exacto que el alta (Etapa "Origen
            // financiero de Egresos manuales") — cuentas Y tarjetas.
            // Cambiar aquí de cuenta a TDC (o al revés) reasigna el
            // financiamiento completo del gasto en una sola
            // transacción; el gasto operativo no cambia por eso.
            RisegOrigenFinancieroSelect(
              cuentas: cuentasFinancieras,
              tarjetas: tarjetasActivas,
              value: origenFinanciero,
              onChanged: (valor) => setState(() => origenFinanciero = valor),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(label: l10n.egresoCampoObservaciones, controller: observacionesController),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(
              label: l10n.corregirEgresoCampoMotivo,
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
        errorMonto = l10n.egresoErrorMontoInvalido;
        return null;
      }
      if (motivoController.text.trim().isEmpty) {
        errorMotivo = l10n.corregirEgresoErrorMotivoRequerido;
        return null;
      }

      // Corregir también puede quedarse sin saldo (subir el importe, o
      // mover la salida a otra cuenta). Mismo mensaje central, y el
      // formulario sigue abierto con lo capturado.
      final resultado = await ejecutarMostrandoSaldoInsuficiente(
        context,
        l10n,
        () => ref.read(egresosControllerProvider.notifier).corregir(
            egresoId: egreso.id,
            monto: monto,
            fecha: fechaSeleccionada,
            categoriaFinancieraId: categoriaId,
            servicioId: servicioId,
            sucursalId: sucursalId,
            areaId: areaId,
            cuentaCaja: cuentaCajaController.text.trim().isEmpty ? null : cuentaCajaController.text.trim(),
            origen: origenDesdeClave(origenFinanciero),
            // El diálogo siempre envía el origen completo (aunque no
            // haya cambiado), así que `limpiarOrigen` traduce "el
            // operador dejó Sin asignar" — nunca "no vino nada".
            limpiarOrigen: origenFinanciero == null,
            formaPago: formaSeleccionada.name,
            beneficiario: beneficiarioController.text.trim().isEmpty ? null : beneficiarioController.text.trim(),
            concepto: conceptoController.text.trim(),
            observaciones: observacionesController.text.trim().isEmpty ? null : observacionesController.text.trim(),
            motivo: motivoController.text.trim(),
          ),
      );
      if (resultado == null) return null;

      if (!context.mounted) return false;

      switch (resultado) {
        case CorregirEgresoExitoso():
          RisegFeedback.showSuccess(context, l10n.corregirEgresoExito);
          return true;
        case CorregirEgresoCancelado():
          RisegFeedback.showError(context, l10n.corregirEgresoErrorCancelado);
          return false;
        case CorregirEgresoOrigenAutomatico():
          RisegFeedback.showError(context, l10n.corregirEgresoErrorOrigenAutomatico);
          return false;
        case CorregirEgresoMotivoRequerido():
          errorMotivo = l10n.corregirEgresoErrorMotivoRequerido;
          return null;
        case CorregirEgresoMontoInvalido():
          errorMonto = l10n.egresoErrorMontoInvalido;
          return null;
        case CorregirEgresoTarjetaInvalida(:final error, :final disponible):
          RisegFeedback.showError(context, mensajeErrorOrigenTarjeta(l10n, error, disponible));
          return false;
        case CorregirEgresoNoExiste():
        case CorregirEgresoErrorInesperado():
          RisegFeedback.showError(context, l10n.corregirEgresoErrorInesperado);
          return false;
      }
    },
  );

  montoController.dispose();
  conceptoController.dispose();
  beneficiarioController.dispose();
  observacionesController.dispose();
  cuentaCajaController.dispose();
  motivoController.dispose();
  return resultado ?? false;
}
