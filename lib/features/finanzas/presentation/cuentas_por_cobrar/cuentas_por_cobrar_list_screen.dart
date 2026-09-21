import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/domain/contraparte_cobro.dart';
import 'package:riseg_one/features/finanzas/data/tables/cuenta_por_cobrar_table.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cuenta_por_cobrar_antiguedad.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart' show TipoDocumentoCobro;

import '../../../organizacion/organizacion_providers.dart';
import 'cuentas_por_cobrar_controller.dart';
import 'cuentas_por_cobrar_state.dart';
import 'cuentas_por_cobrar_resumen.dart';
import 'widgets/cuenta_por_cobrar_detalle_dialog.dart';
import 'widgets/cuentas_por_cobrar_resumen_row.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');
final _formatoMoneda = NumberFormat.currency(locale: 'es_MX', symbol: r'$');

String formatoCentavosCuentaPorCobrar(int centavos) => _formatoMoneda.format(centavos / 100);

/// Listado de Cuentas por cobrar (Etapa 4J.1) — filtros por
/// Cliente/estatus/vencidas. Sin acción de creación: nace 100%
/// automática cuando un `DocumentoPorEmitir` llega a
/// `procesadoAceptado` (Resolución A de Marlon), nunca por botón.
class CuentasPorCobrarListScreen extends ConsumerStatefulWidget {
  const CuentasPorCobrarListScreen({super.key});

  @override
  ConsumerState<CuentasPorCobrarListScreen> createState() => _CuentasPorCobrarListScreenState();
}

class _CuentasPorCobrarListScreenState extends ConsumerState<CuentasPorCobrarListScreen> {
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
    // Navegación encadenada Cliente → Cuentas por cobrar (Etapa 17) —
    // `clienteId` llega como query param real de la ruta
    // (`/finanzas/cuentas-por-cobrar?clienteId=...`, botón "Ver cuentas
    // por cobrar" del expediente de Cliente); se aplica una sola vez al
    // entrar, nunca se vuelve a leer en cada rebuild.
    if (!_filtroClienteDesdeRutaAplicado) {
      _filtroClienteDesdeRutaAplicado = true;
      // `GoRouterState.of` exige un `GoRouter` ancestro real — esta
      // pantalla también se monta sin uno en pruebas de widget que la
      // insertan directo bajo `MaterialApp` (ej. el `IndexedStack` de
      // Agenda↔CxC), así que la lectura debe ser silenciosa cuando no
      // aplica, nunca lanzar.
      String? clienteId;
      try {
        clienteId = GoRouterState.of(context).uri.queryParameters['clienteId'];
      } catch (_) {
        clienteId = null;
      }
      if (clienteId != null) {
        Future.microtask(
          () => ref.read(cuentasPorCobrarControllerProvider.notifier).aplicarFiltros(clienteId: clienteId),
        );
      }
    }
  }

  /// Nunca devuelve un UUID: si la contraparte no se resuelve, el
  /// guion largo dice "no se sabe". Los nombres vienen ya resueltos en
  /// lote desde el controlador.
  String _contraparteNombre(CuentasPorCobrarState estado, CuentaPorCobrarData cuenta) =>
      estado.nombres.de(contraparteDeCuenta(cuenta));

  String _estatusLabel(AppLocalizations l10n, String estatus) {
    return switch (EstatusCuentaPorCobrar.values.byName(estatus)) {
      EstatusCuentaPorCobrar.pendiente => l10n.cuentasPorCobrarEstatusPendiente,
      EstatusCuentaPorCobrar.parcial => l10n.cuentasPorCobrarEstatusParcial,
      EstatusCuentaPorCobrar.pagada => l10n.cuentasPorCobrarEstatusPagada,
      EstatusCuentaPorCobrar.cancelada => l10n.cuentasPorCobrarEstatusCancelada,
    };
  }

  RisegStatusTone _estatusTono(String estatus) {
    return switch (EstatusCuentaPorCobrar.values.byName(estatus)) {
      EstatusCuentaPorCobrar.pendiente => RisegStatusTone.info,
      EstatusCuentaPorCobrar.parcial => RisegStatusTone.warning,
      EstatusCuentaPorCobrar.pagada => RisegStatusTone.success,
      EstatusCuentaPorCobrar.cancelada => RisegStatusTone.neutral,
    };
  }

  String _tipoDocumentoLabel(AppLocalizations l10n, String valor) {
    return switch (TipoDocumentoCobro.values.byName(valor)) {
      TipoDocumentoCobro.cfdi => l10n.servicioCobroTipoDocumentoCfdi,
      TipoDocumentoCobro.reciboDePago => l10n.servicioCobroTipoDocumentoReciboDePago,
    };
  }

  Future<void> _mostrarDetalle(CuentaPorCobrarData cuenta) async {
    await showDialog<void>(
      context: context,
      builder: (_) => CuentaPorCobrarDetalleDialog(cuentaPorCobrarId: cuenta.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(cuentasPorCobrarControllerProvider);
    final notifier = ref.read(cuentasPorCobrarControllerProvider.notifier);
    final hoy = DateTime.now();
    final filas = notifier.cuentasVisibles(hoy);

    if (state.errorCarga != null && state.cuentas.isEmpty) {
      return RisegEmptyState(
        icon: Icons.error_outline,
        title: l10n.cuentasPorCobrarListadoCargaErrorTitulo,
        message: l10n.cuentasPorCobrarListadoCargaErrorMensaje,
        primaryAction: RisegButton(
          key: const Key('cuentas_por_cobrar_boton_reintentar'),
          label: l10n.cuentasPorCobrarListadoBotonReintentar,
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
            title: l10n.cuentasPorCobrarListadoTitulo,
            description: l10n.cuentasPorCobrarListadoSubtitulo,
          ),
          const SizedBox(height: AppSpacing.md),
          CuentasPorCobrarResumenRow(resumen: calcularResumenCuentasPorCobrar(filas, hoy)),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 220,
                child: RisegSelect<String?>(
                  label: l10n.cuentasPorCobrarFiltroCliente,
                  value: state.clienteId,
                  items: [
                    RisegSelectItem(value: null, label: l10n.cuentasPorCobrarFiltroClienteTodos),
                    for (final c in _clientes) RisegSelectItem(value: c.id, label: c.nombreComercial),
                  ],
                  onChanged: (valor) => notifier.aplicarFiltros(clienteId: valor, limpiarClienteId: valor == null),
                ),
              ),
              SizedBox(
                width: 190,
                child: RisegSelect<String?>(
                  label: l10n.cuentasPorCobrarFiltroEstatus,
                  value: state.estatus,
                  items: [
                    RisegSelectItem(value: null, label: l10n.cuentasPorCobrarFiltroEstatusTodos),
                    for (final e in EstatusCuentaPorCobrar.values)
                      RisegSelectItem(value: e.name, label: _estatusLabel(l10n, e.name)),
                  ],
                  onChanged: (valor) => notifier.aplicarFiltros(estatus: valor, limpiarEstatus: valor == null),
                ),
              ),
              FilterChip(
                label: Text(l10n.cuentasPorCobrarFiltroSoloVencidas),
                selected: state.soloVencidas,
                onSelected: (valor) => notifier.aplicarFiltros(soloVencidas: valor),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: RisegTableBase<CuentaPorCobrarData>(
              loading: state.cargando,
              rows: filas,
              onRowTap: _mostrarDetalle,
              emptyState: RisegEmptyState(
                title: l10n.cuentasPorCobrarListadoVacioTitulo,
                message: l10n.cuentasPorCobrarListadoVacioMensaje,
              ),
              hoverColor: colors.accentSoftBg,
              rowVerticalPadding: AppSpacing.sm + AppSpacing.xxs,
              rowActionsBuilder: (_) => Icon(Icons.chevron_right, size: AppSizes.iconMd, color: colors.textMuted),
              actionsWidth: 40,
              columns: [
                RisegColumn<CuentaPorCobrarData>(
                  label: l10n.cuentasPorCobrarColumnaFolio,
                  width: 170,
                  cellBuilder: (c) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        c.folioDocumento ?? c.documentoPorEmitirId ?? c.id,
                        style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(_tipoDocumentoLabel(l10n, c.tipoDocumento), style: AppTypography.caption.copyWith(color: colors.textMuted)),
                    ],
                  ),
                ),
                RisegColumn<CuentaPorCobrarData>(
                  label: l10n.cuentasPorCobrarColumnaCliente,
                  cellBuilder: (c) => Text(_contraparteNombre(state, c), overflow: TextOverflow.ellipsis),
                ),
                RisegColumn<CuentaPorCobrarData>(
                  label: l10n.cuentasPorCobrarColumnaSaldoOriginal,
                  width: 120,
                  alignment: TextAlign.right,
                  cellBuilder: (c) => Text(
                    formatoCentavosCuentaPorCobrar(c.saldoOriginal),
                    style: AppTypography.caption.copyWith(color: colors.textMuted),
                  ),
                ),
                RisegColumn<CuentaPorCobrarData>(
                  label: l10n.cuentasPorCobrarColumnaSaldoPendiente,
                  width: 140,
                  alignment: TextAlign.right,
                  cellBuilder: (c) => Text(
                    formatoCentavosCuentaPorCobrar(c.saldoPendiente),
                    style: AppTypography.bodyStrong.copyWith(
                      color: c.saldoPendiente > 0 ? colors.textPrimary : colors.textMuted,
                    ),
                  ),
                ),
                RisegColumn<CuentaPorCobrarData>(
                  label: l10n.cuentasPorCobrarColumnaVencimiento,
                  width: 160,
                  cellBuilder: (c) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        c.fechaVencimiento == null
                            ? l10n.cuentasPorCobrarSinVencimiento
                            : _formatoFecha.format(c.fechaVencimiento!),
                      ),
                      if (estaVencida(c, hoy)) ...[
                        const SizedBox(width: AppSpacing.xxs),
                        Tooltip(
                          message: l10n.cuentasPorCobrarEtiquetaVencida,
                          child: const Icon(Icons.warning_amber_rounded, size: 16, color: Colors.orange),
                        ),
                      ],
                    ],
                  ),
                ),
                RisegColumn<CuentaPorCobrarData>(
                  label: l10n.cuentasPorCobrarColumnaEstatus,
                  width: 140,
                  cellBuilder: (c) => RisegStatusBadge(
                    label: _estatusLabel(l10n, c.estatus),
                    tone: _estatusTono(c.estatus),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
