import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/inventario/inventario_providers.dart';

import '../data/tables/compra_table.dart' show EstatusCompra;
import '../../inventario/presentation/articulos/articulos_list_screen.dart' show formatoCosto;
import 'compras_controller.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');

String compraEstatusLabel(AppLocalizations l10n, String valor) {
  return switch (EstatusCompra.values.byName(valor)) {
    EstatusCompra.registrada => l10n.compraEstatusRegistrada,
    EstatusCompra.cancelada => l10n.compraEstatusCancelada,
  };
}

RisegStatusTone compraEstatusTono(String valor) {
  return switch (EstatusCompra.values.byName(valor)) {
    EstatusCompra.registrada => RisegStatusTone.success,
    EstatusCompra.cancelada => RisegStatusTone.neutral,
  };
}

/// Listado de Compras (Etapa 10) — filtros por rango de fechas, folio,
/// proveedor, artículo y estatus, más el total comprado dentro del
/// rango consultado (siempre derivado, mismo criterio que
/// `ReportesController`). Sin pestañas todavía — una sola pantalla,
/// mismo criterio que Inventario 7A/Vehículos 8A/Telefonía 9A.
class ComprasListScreen extends ConsumerStatefulWidget {
  const ComprasListScreen({super.key});

  @override
  ConsumerState<ComprasListScreen> createState() => _ComprasListScreenState();
}

class _ComprasListScreenState extends ConsumerState<ComprasListScreen> {
  List<ArticuloData> _articulos = const [];
  final _folioController = TextEditingController();
  final _proveedorController = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final articulos = await ref.read(articuloRepositoryProvider).listar();
      if (mounted) setState(() => _articulos = articulos);
    });
  }

  @override
  void dispose() {
    _folioController.dispose();
    _proveedorController.dispose();
    super.dispose();
  }

  Future<void> _registrar() async {
    final registrada = await context.push<bool>('/compras/nueva');
    if (registrada == true) ref.read(comprasControllerProvider.notifier).recargar();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(comprasControllerProvider);
    final notifier = ref.read(comprasControllerProvider.notifier);

    if (state.errorCarga != null && state.compras.isEmpty) {
      return RisegEmptyState(
        icon: Icons.error_outline,
        title: l10n.comprasListadoCargaErrorTitulo,
        message: l10n.comprasListadoCargaErrorMensaje,
        primaryAction: RisegButton(
          key: const Key('compras_boton_reintentar'),
          label: l10n.comprasListadoBotonReintentar,
          onPressed: notifier.reintentarCarga,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RisegSectionHeader(
            title: l10n.comprasListadoTitulo,
            primaryAction: RisegButton(
              key: const Key('compras_boton_registrar'),
              label: l10n.comprasListadoBotonRegistrar,
              onPressed: _registrar,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: RisegDateField(
                  label: l10n.comprasFiltroDesde,
                  value: state.desde,
                  onChanged: (valor) => notifier.aplicarFiltros(desde: valor),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: RisegDateField(
                  label: l10n.comprasFiltroHasta,
                  value: state.hasta,
                  onChanged: (valor) => notifier.aplicarFiltros(hasta: valor),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: RisegTextField(
                  label: l10n.comprasFiltroFolio,
                  controller: _folioController,
                  onChanged: (valor) => notifier.aplicarFiltros(folio: valor, limpiarFolio: valor.trim().isEmpty),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: RisegTextField(
                  label: l10n.comprasFiltroProveedor,
                  controller: _proveedorController,
                  onChanged: (valor) =>
                      notifier.aplicarFiltros(proveedor: valor, limpiarProveedor: valor.trim().isEmpty),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: RisegSelect<String?>(
                  label: l10n.comprasFiltroArticulo,
                  value: state.articuloId,
                  items: [
                    RisegSelectItem(value: null, label: l10n.comprasFiltroArticuloTodos),
                    for (final a in _articulos) RisegSelectItem(value: a.id, label: a.nombre),
                  ],
                  onChanged: (valor) => notifier.aplicarFiltros(articuloId: valor, limpiarArticuloId: valor == null),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: RisegSelect<String?>(
                  label: l10n.comprasFiltroEstatus,
                  value: state.estatus,
                  items: [
                    RisegSelectItem(value: null, label: l10n.comprasFiltroEstatusTodos),
                    for (final e in EstatusCompra.values)
                      RisegSelectItem(value: e.name, label: compraEstatusLabel(l10n, e.name)),
                  ],
                  onChanged: (valor) => notifier.aplicarFiltros(estatus: valor, limpiarEstatus: valor == null),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${l10n.comprasTotalEnRango}: ${formatoCosto(state.totalRango)}',
            style: AppTypography.label.copyWith(color: context.colors.textMuted),
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: RisegTableBase<CompraData>(
              loading: state.cargando,
              rows: state.compras,
              onRowTap: (c) => context.go('/compras/${c.id}'),
              emptyState: RisegEmptyState(
                title: l10n.comprasListadoVacioTitulo,
                message: l10n.comprasListadoVacioMensaje,
              ),
              columns: [
                RisegColumn<CompraData>(
                  label: l10n.comprasColumnaFolio,
                  width: 110,
                  cellBuilder: (c) => Text(c.folioCompra),
                ),
                RisegColumn<CompraData>(
                  label: l10n.comprasColumnaFecha,
                  width: 110,
                  cellBuilder: (c) => Text(_formatoFecha.format(c.fecha)),
                ),
                RisegColumn<CompraData>(
                  label: l10n.comprasColumnaProveedor,
                  cellBuilder: (c) => Text(c.proveedor ?? '—'),
                ),
                RisegColumn<CompraData>(
                  label: l10n.comprasColumnaTotal,
                  width: 130,
                  alignment: TextAlign.right,
                  cellBuilder: (c) => Text(formatoCosto(state.totalesPorCompra[c.id] ?? 0)),
                ),
                RisegColumn<CompraData>(
                  label: l10n.comprasColumnaFormaPago,
                  width: 130,
                  cellBuilder: (c) => Text(c.formaPago),
                ),
                RisegColumn<CompraData>(
                  label: l10n.comprasColumnaEstatus,
                  width: 130,
                  cellBuilder: (c) =>
                      RisegStatusBadge(label: compraEstatusLabel(l10n, c.estatus), tone: compraEstatusTono(c.estatus)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
