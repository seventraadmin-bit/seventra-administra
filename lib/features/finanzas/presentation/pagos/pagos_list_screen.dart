import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/domain/contraparte_cobro.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart';

import '../../../organizacion/organizacion_providers.dart';
import 'pagos_controller.dart';
import 'pagos_state.dart';
import 'pagos_resumen.dart';
import 'pagos_state.dart' show EstadoComplementoPago;
import 'widgets/pago_detalle_dialog.dart';
import 'widgets/pagos_resumen_row.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');
final _formatoMoneda = NumberFormat.currency(locale: 'es_MX', symbol: r'$');

String formatoCentavosPago(int centavos) => _formatoMoneda.format(centavos / 100);

String formaPagoLabel(AppLocalizations l10n, String valor) {
  return switch (FormaPago.values.byName(valor)) {
    FormaPago.efectivo => l10n.formaPagoEfectivo,
    FormaPago.transferencia => l10n.formaPagoTransferencia,
    FormaPago.cheque => l10n.formaPagoCheque,
    FormaPago.tarjeta => l10n.formaPagoTarjeta,
    FormaPago.otro => l10n.formaPagoOtro,
  };
}

String pagoEstatusLabel(AppLocalizations l10n, String valor) {
  return switch (EstatusPago.values.byName(valor)) {
    EstatusPago.registrado => l10n.pagoEstatusRegistrado,
    EstatusPago.cancelado => l10n.pagoEstatusCancelado,
  };
}

RisegStatusTone pagoEstatusTono(String valor) {
  return switch (EstatusPago.values.byName(valor)) {
    EstatusPago.registrado => RisegStatusTone.success,
    EstatusPago.cancelado => RisegStatusTone.neutral,
  };
}

String _estadoComplementoLabel(AppLocalizations l10n, EstadoComplementoPago estado) {
  return switch (estado) {
    EstadoComplementoPago.noAplica => l10n.pagosComplementoNoAplica,
    EstadoComplementoPago.pendiente => l10n.pagosComplementoPendiente,
    EstadoComplementoPago.realizado => l10n.pagosComplementoRealizado,
  };
}

RisegStatusTone _estadoComplementoTono(EstadoComplementoPago estado) {
  return switch (estado) {
    EstadoComplementoPago.noAplica => RisegStatusTone.neutral,
    EstadoComplementoPago.pendiente => RisegStatusTone.warning,
    EstadoComplementoPago.realizado => RisegStatusTone.success,
  };
}

/// Listado de Pagos (Etapa 4J.2) — filtros por Cliente/forma de pago/
/// estatus. Sin acción de creación aquí: el flujo simplificado de esta
/// etapa registra un Pago desde el detalle de la Cuenta por cobrar que
/// liquida (Resolución de Marlon: interfaz simple, modelo N:M listo
/// para una futura pantalla de distribución).
class PagosListScreen extends ConsumerStatefulWidget {
  const PagosListScreen({super.key});

  @override
  ConsumerState<PagosListScreen> createState() => _PagosListScreenState();
}

class _PagosListScreenState extends ConsumerState<PagosListScreen> {
  List<ClienteData> _clientes = const [];
  bool _filtroClienteDesdeRutaAplicado = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final clientes = await ref.read(clienteRepositoryProvider).listarActivos();
      if (mounted) setState(() => _clientes = clientes);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Navegación encadenada Cliente → Pagos (Etapa 17) — mismo criterio
    // que `CuentasPorCobrarListScreen`.
    if (!_filtroClienteDesdeRutaAplicado) {
      _filtroClienteDesdeRutaAplicado = true;
      // `GoRouterState.of` exige un `GoRouter` ancestro real — ver el
      // mismo razonamiento en `CuentasPorCobrarListScreen`.
      String? clienteId;
      try {
        clienteId = GoRouterState.of(context).uri.queryParameters['clienteId'];
      } catch (_) {
        clienteId = null;
      }
      if (clienteId != null) {
        Future.microtask(() => ref.read(pagosControllerProvider.notifier).aplicarFiltros(clienteId: clienteId));
      }
    }
  }

  /// Nunca devuelve un UUID — ver `NombresContraparte`. Los nombres
  /// vienen ya resueltos en lote desde el controlador.
  String _contraparteNombre(PagosState estado, PagoData pago) => estado.nombres.de(contraparteDePago(pago));


  Future<void> _mostrarDetalle(PagoData pago) async {
    await showDialog<void>(context: context, builder: (_) => PagoDetalleDialog(pagoId: pago.id));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(pagosControllerProvider);
    final notifier = ref.read(pagosControllerProvider.notifier);

    if (state.errorCarga != null && state.pagos.isEmpty) {
      return RisegEmptyState(
        icon: Icons.error_outline,
        title: l10n.pagosListadoCargaErrorTitulo,
        message: l10n.pagosListadoCargaErrorMensaje,
        primaryAction: RisegButton(
          key: const Key('pagos_boton_reintentar'),
          label: l10n.pagosListadoBotonReintentar,
          onPressed: notifier.reintentarCarga,
        ),
      );
    }

    final colors = context.colors;
    final hayFiltrosActivos = state.clienteId != null ||
        state.formaPago != null ||
        state.estatus != null ||
        state.rangoInicio != null ||
        state.rangoFin != null;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RisegSectionHeader(title: l10n.pagosListadoTitulo, description: l10n.pagosListadoSubtitulo),
          const SizedBox(height: AppSpacing.md),
          PagosResumenRow(resumen: calcularResumenPagos(state.pagos)),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 200,
                child: RisegSelect<String?>(
                  label: l10n.pagosFiltroCliente,
                  value: state.clienteId,
                  items: [
                    RisegSelectItem(value: null, label: l10n.pagosFiltroClienteTodos),
                    for (final c in _clientes) RisegSelectItem(value: c.id, label: c.nombreComercial),
                  ],
                  onChanged: (valor) => notifier.aplicarFiltros(clienteId: valor, limpiarClienteId: valor == null),
                ),
              ),
              SizedBox(
                width: 190,
                child: RisegSelect<String?>(
                  label: l10n.pagosFiltroFormaPago,
                  value: state.formaPago,
                  items: [
                    RisegSelectItem(value: null, label: l10n.pagosFiltroFormaPagoTodas),
                    for (final f in FormaPago.values)
                      RisegSelectItem(value: f.name, label: formaPagoLabel(l10n, f.name)),
                  ],
                  onChanged: (valor) => notifier.aplicarFiltros(formaPago: valor, limpiarFormaPago: valor == null),
                ),
              ),
              SizedBox(
                width: 170,
                child: RisegSelect<String?>(
                  label: l10n.pagosFiltroEstatus,
                  value: state.estatus,
                  items: [
                    RisegSelectItem(value: null, label: l10n.pagosFiltroEstatusTodos),
                    for (final e in EstatusPago.values)
                      RisegSelectItem(value: e.name, label: pagoEstatusLabel(l10n, e.name)),
                  ],
                  onChanged: (valor) => notifier.aplicarFiltros(estatus: valor, limpiarEstatus: valor == null),
                ),
              ),
              SizedBox(
                width: 150,
                child: RisegDateField(
                  label: l10n.pagosFiltroDesde,
                  value: state.rangoInicio,
                  onChanged: (valor) => notifier.aplicarFiltros(rangoInicio: valor),
                ),
              ),
              SizedBox(
                width: 150,
                child: RisegDateField(
                  label: l10n.pagosFiltroHasta,
                  value: state.rangoFin,
                  onChanged: (valor) => notifier.aplicarFiltros(rangoFin: valor),
                ),
              ),
              RisegButton(
                label: l10n.personalActivoLimpiarFiltros,
                variant: RisegButtonVariant.ghost,
                onPressed: hayFiltrosActivos
                    ? () => notifier.aplicarFiltros(
                          limpiarClienteId: true,
                          limpiarFormaPago: true,
                          limpiarEstatus: true,
                          limpiarRango: true,
                        )
                    : null,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: RisegTableBase<PagoData>(
              loading: state.cargando,
              rows: state.pagos,
              onRowTap: _mostrarDetalle,
              emptyState: RisegEmptyState(
                title: l10n.pagosListadoVacioTitulo,
                message: l10n.pagosListadoVacioMensaje,
              ),
              hoverColor: colors.accentSoftBg,
              rowVerticalPadding: AppSpacing.sm + AppSpacing.xxs,
              rowActionsBuilder: (_) => Icon(Icons.chevron_right, size: AppSizes.iconMd, color: colors.textMuted),
              actionsWidth: 40,
              columns: [
                RisegColumn<PagoData>(
                  label: l10n.pagosColumnaFolio,
                  width: 140,
                  cellBuilder: (p) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(p.folioPago, style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary)),
                      if (p.referencia != null && p.referencia!.trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(p.referencia!, style: AppTypography.caption.copyWith(color: colors.textMuted), overflow: TextOverflow.ellipsis),
                      ],
                    ],
                  ),
                ),
                RisegColumn<PagoData>(
                  label: l10n.pagosColumnaCliente,
                  cellBuilder: (p) => Text(_contraparteNombre(state, p), overflow: TextOverflow.ellipsis),
                ),
                RisegColumn<PagoData>(
                  label: l10n.pagosColumnaFecha,
                  width: 110,
                  cellBuilder: (p) => Text(_formatoFecha.format(p.fechaPago)),
                ),
                RisegColumn<PagoData>(
                  label: l10n.pagosColumnaMontoTotal,
                  width: 130,
                  alignment: TextAlign.right,
                  cellBuilder: (p) => Text(formatoCentavosPago(p.montoTotal)),
                ),
                RisegColumn<PagoData>(
                  label: l10n.pagosColumnaMontoAplicado,
                  width: 180,
                  cellBuilder: (p) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(formatoCentavosPago(p.montoAplicado)),
                      if (p.montoAplicado < p.montoTotal) ...[
                        const SizedBox(width: AppSpacing.xxs),
                        Tooltip(
                          message: l10n.pagosEtiquetaSaldoDisponible,
                          child: const Icon(Icons.info_outline, size: 16, color: Colors.blue),
                        ),
                      ],
                    ],
                  ),
                ),
                RisegColumn<PagoData>(
                  label: l10n.pagosColumnaFormaPago,
                  width: 130,
                  cellBuilder: (p) => Text(formaPagoLabel(l10n, p.formaPago)),
                ),
                RisegColumn<PagoData>(
                  label: l10n.pagosColumnaEstatus,
                  width: 130,
                  cellBuilder: (p) =>
                      RisegStatusBadge(label: pagoEstatusLabel(l10n, p.estatus), tone: pagoEstatusTono(p.estatus)),
                ),
                RisegColumn<PagoData>(
                  label: l10n.pagosColumnaComplemento,
                  width: 130,
                  cellBuilder: (p) {
                    final estado = state.estadoComplementoPorPago[p.id] ?? EstadoComplementoPago.noAplica;
                    return RisegStatusBadge(label: _estadoComplementoLabel(l10n, estado), tone: _estadoComplementoTono(estado));
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
