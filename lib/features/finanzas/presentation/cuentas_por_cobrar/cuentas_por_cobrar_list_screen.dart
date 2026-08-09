import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/data/tables/cuenta_por_cobrar_table.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cuenta_por_cobrar_antiguedad.dart';

import '../../../organizacion/organizacion_providers.dart';
import 'cuentas_por_cobrar_controller.dart';
import 'widgets/cuenta_por_cobrar_detalle_dialog.dart';

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

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final clientes = await ref.read(clienteRepositoryProvider).listarActivos();
      if (mounted) setState(() => _clientes = clientes);
    });
  }

  String _clienteNombre(String clienteId) {
    for (final c in _clientes) {
      if (c.id == clienteId) return c.nombreComercial;
    }
    return clienteId;
  }

  String _estatusLabel(AppLocalizations l10n, String estatus) {
    return switch (EstatusCuentaPorCobrar.values.byName(estatus)) {
      EstatusCuentaPorCobrar.pendiente => l10n.cuentasPorCobrarEstatusPendiente,
      EstatusCuentaPorCobrar.parcial => l10n.cuentasPorCobrarEstatusParcial,
      EstatusCuentaPorCobrar.pagada => l10n.cuentasPorCobrarEstatusPagada,
    };
  }

  RisegStatusTone _estatusTono(String estatus) {
    return switch (EstatusCuentaPorCobrar.values.byName(estatus)) {
      EstatusCuentaPorCobrar.pendiente => RisegStatusTone.info,
      EstatusCuentaPorCobrar.parcial => RisegStatusTone.warning,
      EstatusCuentaPorCobrar.pagada => RisegStatusTone.success,
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

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RisegSectionHeader(title: l10n.cuentasPorCobrarListadoTitulo),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
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
              const SizedBox(width: AppSpacing.md),
              Expanded(
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
              const SizedBox(width: AppSpacing.md),
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
              columns: [
                RisegColumn<CuentaPorCobrarData>(
                  label: l10n.cuentasPorCobrarColumnaFolio,
                  width: 130,
                  cellBuilder: (c) => Text(c.folioDocumento ?? c.documentoPorEmitirId),
                ),
                RisegColumn<CuentaPorCobrarData>(
                  label: l10n.cuentasPorCobrarColumnaCliente,
                  cellBuilder: (c) => Text(_clienteNombre(c.clienteId)),
                ),
                RisegColumn<CuentaPorCobrarData>(
                  label: l10n.cuentasPorCobrarColumnaSaldoOriginal,
                  width: 130,
                  alignment: TextAlign.right,
                  cellBuilder: (c) => Text(formatoCentavosCuentaPorCobrar(c.saldoOriginal)),
                ),
                RisegColumn<CuentaPorCobrarData>(
                  label: l10n.cuentasPorCobrarColumnaSaldoPendiente,
                  width: 130,
                  alignment: TextAlign.right,
                  cellBuilder: (c) => Text(formatoCentavosCuentaPorCobrar(c.saldoPendiente)),
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
