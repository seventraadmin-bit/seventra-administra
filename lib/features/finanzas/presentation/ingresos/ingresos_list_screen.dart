import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/data/tables/ingreso_table.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/servicio_repository.dart';

import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;

import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

import '../../../organizacion/organizacion_providers.dart';
import '../cuentas_financieras/cuentas_financieras_controller.dart';
import '../pagos/pagos_list_screen.dart' show formaPagoLabel, formatoCentavosPago;
import '../planeacion/planeacion_financiera_controller.dart';
import '../resumen/resumen_financiero_controller.dart';
import 'ingresos_controller.dart';
import 'ingresos_resumen.dart';
import 'ingresos_state.dart';
import 'widgets/ingreso_detalle_dialog.dart';
import 'widgets/ingresos_resumen_row.dart';
import 'widgets/registrar_ingreso_dialog.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');

String ingresoEstatusLabel(AppLocalizations l10n, String valor) {
  return switch (EstatusIngreso.values.byName(valor)) {
    EstatusIngreso.registrado => l10n.ingresoEstatusRegistrado,
    EstatusIngreso.cancelado => l10n.ingresoEstatusCancelado,
  };
}

RisegStatusTone ingresoEstatusTono(String valor) {
  return switch (EstatusIngreso.values.byName(valor)) {
    EstatusIngreso.registrado => RisegStatusTone.success,
    EstatusIngreso.cancelado => RisegStatusTone.neutral,
  };
}

/// Listado de Ingresos (Etapa 4K.1) — filtros por Servicio/estatus. El
/// botón "Registrar" crea un Ingreso manual (sin `Pago` de por medio);
/// el Ingreso automático de un Pago se ve aquí pero nunca se crea desde
/// esta pantalla (Resolución de Marlon).
class IngresosListScreen extends ConsumerStatefulWidget {
  const IngresosListScreen({super.key});

  @override
  ConsumerState<IngresosListScreen> createState() => _IngresosListScreenState();
}

class _IngresosListScreenState extends ConsumerState<IngresosListScreen> {
  List<ServicioListItem> _servicios = const [];

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final servicios = await ref.read(servicioRepositoryProvider).listar();
      if (mounted) setState(() => _servicios = servicios);
    });
  }

  String? _servicioNombre(String? servicioId) {
    if (servicioId == null) return null;
    for (final s in _servicios) {
      if (s.servicio.id == servicioId) return s.servicio.nombre;
    }
    return servicioId;
  }

  Future<void> _registrar() async {
    final registro = await mostrarDialogoRegistrarIngreso(context, ref, servicios: _servicios);
    if (registro) {
      ref.read(ingresosControllerProvider.notifier).recargar();
      // Etapa 19C: un Ingreso manual puede llevar una Cuenta
      // financiera y siempre afecta el Resumen (Ingresos del
      // periodo) — ninguno de los dos se entera sin invalidar aquí
      // (mismo hallazgo ya corregido para Deudas/Compras).
      ref.invalidate(cuentasFinancierasControllerProvider);
      ref.invalidate(resumenFinancieroControllerProvider);
      ref.invalidate(planeacionFinancieraControllerProvider);
    }
  }

  Future<void> _mostrarDetalle(IngresoData ingreso) async {
    await showDialog<void>(context: context, builder: (_) => IngresoDetalleDialog(ingresoId: ingreso.id));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(ingresosControllerProvider);
    final notifier = ref.read(ingresosControllerProvider.notifier);

    if (state.errorCarga != null && state.ingresos.isEmpty) {
      return RisegEmptyState(
        icon: Icons.error_outline,
        title: l10n.ingresosListadoCargaErrorTitulo,
        message: l10n.ingresosListadoCargaErrorMensaje,
        primaryAction: RisegButton(
          key: const Key('ingresos_boton_reintentar'),
          label: l10n.ingresosListadoBotonReintentar,
          onPressed: notifier.reintentarCarga,
        ),
      );
    }

    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RisegSectionHeader(
            title: l10n.ingresosListadoTitulo,
            description: l10n.ingresosListadoSubtitulo,
            primaryAction: RisegButton(
              key: const Key('ingresos_boton_registrar'),
              label: l10n.ingresosListadoBotonRegistrar,
              icon: Icons.add,
              onPressed: ref.watch(permissionServiceProvider).hasCode('ingresos.crear') ? _registrar : null,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          IngresosResumenRow(resumen: calcularResumenIngresos(state.ingresos)),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 190,
                child: RisegSelect<String?>(
                  label: l10n.ingresosFiltroServicio,
                  value: state.servicioId,
                  items: [
                    RisegSelectItem(value: null, label: l10n.ingresosFiltroServicioTodos),
                    for (final s in _servicios) RisegSelectItem(value: s.servicio.id, label: s.servicio.nombre),
                  ],
                  onChanged: (valor) => notifier.aplicarFiltros(servicioId: valor, limpiarServicioId: valor == null),
                ),
              ),
              SizedBox(
                width: 160,
                child: RisegSelect<String?>(
                  label: l10n.ingresosFiltroEstatus,
                  value: state.estatus,
                  items: [
                    RisegSelectItem(value: null, label: l10n.ingresosFiltroEstatusTodos),
                    for (final e in EstatusIngreso.values)
                      RisegSelectItem(value: e.name, label: ingresoEstatusLabel(l10n, e.name)),
                  ],
                  onChanged: (valor) => notifier.aplicarFiltros(estatus: valor, limpiarEstatus: valor == null),
                ),
              ),
              SizedBox(
                width: 170,
                child: RisegSelect<FiltroOrigenIngreso>(
                  label: l10n.ingresosFiltroOrigen,
                  value: state.origen,
                  items: [
                    RisegSelectItem(value: FiltroOrigenIngreso.todos, label: l10n.ingresosFiltroOrigenTodos),
                    RisegSelectItem(value: FiltroOrigenIngreso.automatico, label: l10n.ingresosOrigenAutomatico),
                    RisegSelectItem(value: FiltroOrigenIngreso.manual, label: l10n.ingresosOrigenManual),
                  ],
                  onChanged: (valor) => notifier.aplicarFiltrosLocales(origen: valor ?? FiltroOrigenIngreso.todos),
                ),
              ),
              SizedBox(
                width: 190,
                child: RisegSelect<String?>(
                  label: l10n.ingresosFiltroFormaPago,
                  value: state.formaPago,
                  items: [
                    RisegSelectItem(value: null, label: l10n.ingresosFiltroFormaPagoTodas),
                    for (final f in FormaPago.values) RisegSelectItem(value: f.name, label: formaPagoLabel(l10n, f.name)),
                  ],
                  onChanged: (valor) => notifier.aplicarFiltrosLocales(formaPago: valor, limpiarFormaPago: valor == null),
                ),
              ),
              SizedBox(
                width: 150,
                child: RisegDateField(
                  label: l10n.ingresosFiltroDesde,
                  value: state.rangoInicio,
                  onChanged: (valor) => notifier.aplicarFiltros(rangoInicio: valor),
                ),
              ),
              SizedBox(
                width: 150,
                child: RisegDateField(
                  label: l10n.ingresosFiltroHasta,
                  value: state.rangoFin,
                  onChanged: (valor) => notifier.aplicarFiltros(rangoFin: valor),
                ),
              ),
              RisegButton(
                label: l10n.personalActivoLimpiarFiltros,
                variant: RisegButtonVariant.ghost,
                onPressed: state.hayFiltrosActivos
                    ? () => notifier.aplicarFiltros(limpiarEstatus: true, limpiarServicioId: true, limpiarRango: true)
                        .then((_) => notifier.aplicarFiltrosLocales(origen: FiltroOrigenIngreso.todos, limpiarFormaPago: true))
                    : null,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: RisegTableBase<IngresoData>(
              loading: state.cargando,
              rows: state.ingresosFiltrados,
              onRowTap: _mostrarDetalle,
              emptyState: RisegEmptyState(
                title: l10n.ingresosListadoVacioTitulo,
                message: l10n.ingresosListadoVacioMensaje,
              ),
              hoverColor: colors.accentSoftBg,
              rowVerticalPadding: AppSpacing.sm + AppSpacing.xxs,
              rowActionsBuilder: (_) => Icon(Icons.chevron_right, size: AppSizes.iconMd, color: colors.textMuted),
              actionsWidth: 40,
              columns: [
                RisegColumn<IngresoData>(
                  label: l10n.ingresosColumnaFolio,
                  width: 150,
                  cellBuilder: (i) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        i.pagoId != null ? l10n.ingresosIdentidadPagoRecibido : i.folioIngreso,
                        style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        i.pagoId != null ? (state.folioPagoPorIngreso[i.id] ?? i.folioIngreso) : l10n.ingresosOrigenManual,
                        style: AppTypography.caption.copyWith(color: colors.textMuted),
                      ),
                    ],
                  ),
                ),
                RisegColumn<IngresoData>(
                  label: l10n.ingresosColumnaFecha,
                  width: 110,
                  cellBuilder: (i) => Text(_formatoFecha.format(i.fecha)),
                ),
                RisegColumn<IngresoData>(
                  label: l10n.ingresosColumnaServicio,
                  cellBuilder: (i) => Text(_servicioNombre(i.servicioId) ?? ''),
                ),
                RisegColumn<IngresoData>(label: l10n.ingresosColumnaConcepto, cellBuilder: (i) => Text(i.concepto)),
                RisegColumn<IngresoData>(
                  label: l10n.ingresosColumnaFormaPago,
                  width: 130,
                  cellBuilder: (i) => Text(formaPagoLabel(l10n, i.formaPago)),
                ),
                RisegColumn<IngresoData>(
                  label: l10n.ingresosColumnaMonto,
                  width: 130,
                  alignment: TextAlign.right,
                  cellBuilder: (i) => Text(
                    formatoCentavosPago(i.monto),
                    style: AppTypography.bodyStrong.copyWith(color: colors.success),
                  ),
                ),
                RisegColumn<IngresoData>(
                  label: l10n.ingresosColumnaEstatus,
                  width: 130,
                  cellBuilder: (i) =>
                      RisegStatusBadge(label: ingresoEstatusLabel(l10n, i.estatus), tone: ingresoEstatusTono(i.estatus)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
