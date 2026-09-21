import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/dashboard/presentation/dashboard_controller.dart';
import 'package:riseg_one/features/finanzas/data/tables/deuda_table.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/calcular_fecha_tarjeta_usecase.dart';
import 'package:riseg_one/features/finanzas/presentation/planeacion/planeacion_financiera_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/resumen/resumen_financiero_controller.dart';

import 'deudas_credito_controller.dart';
import 'widgets/registrar_deuda_dialog.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');
final _formatoMoneda = NumberFormat.currency(locale: 'es_MX', symbol: r'$');

/// Trunca a medianoche — mismo patrón que `_soloFecha`/`soloFecha` ya
/// usado en otros módulos (`linea_comercial_con_vigencia.dart`,
/// `calcular_fechas_cobro_usecase.dart`, `periodo_dashboard.dart`,
/// etc.), nunca una segunda convención de normalización de fecha.
DateTime _soloFecha(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

String formatoCentavosDeuda(int centavos) => _formatoMoneda.format(centavos / 100);

/// KPI "Próximos vencimientos" — cuenta las Deudas ACTIVAS cuyo próximo
/// pago (`proximaFechaPagoDeuda`, misma fuente de verdad para TDC y
/// deuda fija — nunca una segunda lógica) cae dentro de los próximos
/// 30 días naturales, AMBOS extremos incluidos: `hoySinHora <=
/// proximoPago <= hoySinHora + 30 días` — un vencimiento exactamente
/// hoy o exactamente en el día 30 sí cuenta.
///
/// Bug real corregido: antes se comparaba `proximoPago` (siempre a
/// medianoche) contra `ahora.add(Duration(days: 30))` SIN truncar la
/// hora — el resultado dependía de la hora del reloj al cargar la
/// pantalla (un vencimiento del día 30 solo contaba si la pantalla se
/// abría después de medianoche de ese mismo día, que es casi siempre,
/// pero no de forma explícita/estable). Ambos extremos de la
/// comparación se truncan a medianoche con [_soloFecha] antes de
/// comparar, así el resultado es el mismo sin importar la hora exacta
/// en que se ejecute.
int contarProximosVencimientos(List<DeudaData> deudas, DateTime ahora) {
  final hoySinHora = _soloFecha(ahora);
  final limite = hoySinHora.add(const Duration(days: 30));
  return deudas.where((d) {
    if (d.estatus != EstatusDeuda.activa.name) return false;
    final proximoPago = proximaFechaPagoDeuda(d, ahora);
    if (proximoPago == null) return false;
    final proximoPagoSinHora = _soloFecha(proximoPago);
    return !proximoPagoSinHora.isBefore(hoySinHora) && !proximoPagoSinHora.isAfter(limite);
  }).length;
}

String deudaTipoLabel(AppLocalizations l10n, String tipo) {
  return switch (TipoDeuda.values.byName(tipo)) {
    TipoDeuda.tarjetaCredito => l10n.deudaTipoTarjetaCredito,
    TipoDeuda.prestamo => l10n.deudaTipoPrestamo,
    TipoDeuda.financiamiento => l10n.deudaTipoFinanciamiento,
    TipoDeuda.otro => l10n.deudaTipoOtro,
  };
}

String deudaEstatusLabel(AppLocalizations l10n, String estatus) {
  return switch (EstatusDeuda.values.byName(estatus)) {
    EstatusDeuda.activa => l10n.deudaEstatusActiva,
    EstatusDeuda.liquidada => l10n.deudaEstatusLiquidada,
    EstatusDeuda.cancelada => l10n.deudaEstatusCancelada,
  };
}

RisegStatusTone deudaEstatusTono(String estatus) {
  return switch (EstatusDeuda.values.byName(estatus)) {
    EstatusDeuda.activa => RisegStatusTone.info,
    EstatusDeuda.liquidada => RisegStatusTone.success,
    EstatusDeuda.cancelada => RisegStatusTone.neutral,
  };
}

/// Listado de Deudas y crédito (Etapa 19) — tarjetas de crédito,
/// préstamos y financiamientos empresariales, con saldo, historial y
/// pagos propios (nunca una `CategoriaFinanciera` más). Los KPIs se
/// derivan en memoria sobre la página ya cargada (filtrada) — mismo
/// criterio que Compras/Cuentas por cobrar.
class DeudasCreditoListScreen extends ConsumerStatefulWidget {
  const DeudasCreditoListScreen({super.key});

  @override
  ConsumerState<DeudasCreditoListScreen> createState() => _DeudasCreditoListScreenState();
}

class _DeudasCreditoListScreenState extends ConsumerState<DeudasCreditoListScreen> {
  final _busquedaCtrl = TextEditingController();

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    super.dispose();
  }

  Future<void> _registrarDeuda() async {
    final registrada = await mostrarDialogoRegistrarDeuda(context, ref);
    if (registrada && mounted) {
      ref.read(deudasCreditoControllerProvider.notifier).reintentarCarga();
      // El alta de una Deuda cambia "Deuda financiera total" del
      // Resumen (as-of-hoy, ver ese controlador) — bug real corregido:
      // sin esto, el Resumen seguía mostrando el total viejo hasta
      // cambiar de pestaña.
      ref.invalidate(resumenFinancieroControllerProvider);
      ref.invalidate(planeacionFinancieraControllerProvider);
      // Etapa 20 (hueco real encontrado): una tarjeta nueva con
      // utilización alta o pago próximo debe poder aparecer de
      // inmediato en "Requiere atención" del Dashboard.
      ref.invalidate(dashboardControllerProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final state = ref.watch(deudasCreditoControllerProvider);
    final notifier = ref.read(deudasCreditoControllerProvider.notifier);

    if (state.errorCarga != null && state.deudas.isEmpty) {
      return RisegEmptyState(
        icon: Icons.error_outline,
        title: l10n.deudasCreditoListadoCargaErrorTitulo,
        message: l10n.deudasCreditoListadoCargaErrorMensaje,
        primaryAction: RisegButton(
          key: const Key('deudas_credito_boton_reintentar'),
          label: l10n.deudasCreditoListadoBotonReintentar,
          onPressed: notifier.reintentarCarga,
        ),
      );
    }

    final deudas = state.deudas;
    final hoy = DateTime.now();
    final totalActual = deudas.fold<int>(0, (acc, d) => acc + d.saldoActual);
    final activas = deudas.where((d) => d.estatus == EstatusDeuda.activa.name).length;
    final proximosVencimientos = contarProximosVencimientos(deudas, hoy);
    final creditoDisponible = deudas
        .where((d) => d.tipo == TipoDeuda.tarjetaCredito.name && d.estatus == EstatusDeuda.activa.name && d.tarjetaLimiteCredito != null)
        .fold<int>(0, (acc, d) => acc + creditoDisponibleTarjeta(limiteCredito: d.tarjetaLimiteCredito, saldoActual: d.saldoActual)!);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RisegSectionHeader(
            title: l10n.deudasCreditoListadoTitulo,
            description: l10n.deudasCreditoListadoSubtitulo,
            primaryAction: RisegButton(
              key: const Key('deudas_credito_boton_registrar'),
              label: l10n.deudasCreditoBotonRegistrar,
              onPressed: _registrarDeuda,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final columnas = constraints.maxWidth < AppBreakpoints.compact ? 2 : 4;
              final ancho = (constraints.maxWidth - (AppSpacing.md * (columnas - 1))) / columnas;
              return Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  SizedBox(
                    width: ancho,
                    child: RisegStatCard(label: l10n.deudasCreditoKpiTotalActual, value: formatoCentavosDeuda(totalActual), dense: true),
                  ),
                  SizedBox(
                    width: ancho,
                    child: RisegStatCard(label: l10n.deudasCreditoKpiActivas, value: '$activas', dense: true),
                  ),
                  SizedBox(
                    width: ancho,
                    child: RisegStatCard(label: l10n.deudasCreditoKpiProximosVencimientos, value: '$proximosVencimientos', dense: true),
                  ),
                  SizedBox(
                    width: ancho,
                    child: RisegStatCard(
                      label: l10n.deudasCreditoKpiCreditoDisponible,
                      value: formatoCentavosDeuda(creditoDisponible),
                      dense: true,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 220,
                child: RisegSearchField(
                  hint: l10n.deudasCreditoFiltroBusqueda,
                  controller: _busquedaCtrl,
                  onChanged: (valor) =>
                      notifier.aplicarFiltros(busqueda: valor.trim().isEmpty ? null : valor, limpiarBusqueda: valor.trim().isEmpty),
                ),
              ),
              SizedBox(
                width: 190,
                child: RisegSelect<String?>(
                  label: l10n.deudasCreditoFiltroTipo,
                  value: state.tipo,
                  items: [
                    RisegSelectItem(value: null, label: l10n.deudasCreditoFiltroTipoTodos),
                    for (final t in TipoDeuda.values) RisegSelectItem(value: t.name, label: deudaTipoLabel(l10n, t.name)),
                  ],
                  onChanged: (valor) => notifier.aplicarFiltros(tipo: valor, limpiarTipo: valor == null),
                ),
              ),
              SizedBox(
                width: 190,
                child: RisegSelect<String?>(
                  label: l10n.deudasCreditoFiltroEstatus,
                  value: state.estatus,
                  items: [
                    RisegSelectItem(value: null, label: l10n.deudasCreditoFiltroEstatusTodos),
                    for (final e in EstatusDeuda.values) RisegSelectItem(value: e.name, label: deudaEstatusLabel(l10n, e.name)),
                  ],
                  onChanged: (valor) => notifier.aplicarFiltros(estatus: valor, limpiarEstatus: valor == null),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: RisegTableBase<DeudaData>(
              loading: state.cargando,
              rows: deudas,
              onRowTap: (d) => context.push('/finanzas/deudas-y-credito/${d.id}'),
              emptyState: RisegEmptyState(
                title: l10n.deudasCreditoListadoVacioTitulo,
                message: l10n.deudasCreditoListadoVacioMensaje,
              ),
              hoverColor: colors.accentSoftBg,
              rowVerticalPadding: AppSpacing.sm + AppSpacing.xxs,
              rowActionsBuilder: (_) => Icon(Icons.chevron_right, size: AppSizes.iconMd, color: colors.textMuted),
              actionsWidth: 40,
              columns: [
                RisegColumn<DeudaData>(
                  label: l10n.deudasCreditoColumnaDeuda,
                  width: 190,
                  cellBuilder: (d) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(d.nombre, style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary), overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(d.folio, style: AppTypography.caption.copyWith(color: colors.textMuted)),
                    ],
                  ),
                ),
                RisegColumn<DeudaData>(label: l10n.deudasCreditoColumnaTipo, width: 130, cellBuilder: (d) => Text(deudaTipoLabel(l10n, d.tipo))),
                RisegColumn<DeudaData>(label: l10n.deudasCreditoColumnaAcreedor, cellBuilder: (d) => Text(d.acreedor ?? '-')),
                RisegColumn<DeudaData>(
                  label: l10n.deudasCreditoColumnaImporteOriginal,
                  width: 130,
                  alignment: TextAlign.right,
                  cellBuilder: (d) => Text(
                    d.importeOriginal == null ? l10n.deudaTarjetaSinDato : formatoCentavosDeuda(d.importeOriginal!),
                    style: AppTypography.caption.copyWith(color: colors.textMuted),
                  ),
                ),
                RisegColumn<DeudaData>(
                  label: l10n.deudasCreditoColumnaPagado,
                  width: 130,
                  alignment: TextAlign.right,
                  cellBuilder: (d) => Text(formatoCentavosDeuda(state.pagadoPorDeudaId[d.id] ?? 0)),
                ),
                RisegColumn<DeudaData>(
                  label: l10n.deudasCreditoColumnaSaldoActual,
                  width: 140,
                  alignment: TextAlign.right,
                  cellBuilder: (d) => Text(
                    formatoCentavosDeuda(d.saldoActual),
                    style: AppTypography.bodyStrong.copyWith(color: d.saldoActual > 0 ? colors.textPrimary : colors.textMuted),
                  ),
                ),
                RisegColumn<DeudaData>(
                  label: l10n.deudasCreditoColumnaVencimiento,
                  width: 150,
                  cellBuilder: (d) {
                    final proximoPago = proximaFechaPagoDeuda(d, hoy);
                    if (proximoPago != null) return Text(_formatoFecha.format(proximoPago));
                    final esTarjeta = d.tipo == TipoDeuda.tarjetaCredito.name;
                    return Text(esTarjeta ? l10n.deudasCreditoSinConfigurar : l10n.deudasCreditoSinVencimiento);
                  },
                ),
                RisegColumn<DeudaData>(
                  label: l10n.deudasCreditoColumnaEstatus,
                  width: 130,
                  cellBuilder: (d) => RisegStatusBadge(label: deudaEstatusLabel(l10n, d.estatus), tone: deudaEstatusTono(d.estatus)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
