import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_list_screen.dart' show formaPagoLabel;
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

/// Texto de la celda "Artículos comprados" (Etapa 19.1) — nombre real +
/// cantidad REAL de cada renglón (nunca un conteo agregado, nunca
/// unidades confundidas con renglones). Trunca a lo sumo
/// [_maxArticulosMostrados] elementos y cierra con "+N más" cuando
/// sobran — evita filas de alto/ancho indefinido con Compras de muchos
/// renglones.
const _maxArticulosMostrados = 2;

String _textoArticulosComprados(
  AppLocalizations l10n,
  List<({String articuloId, int cantidad})> renglones,
  Map<String, String> nombrePorArticuloId,
) {
  String etiqueta(({String articuloId, int cantidad}) r) => '${nombrePorArticuloId[r.articuloId] ?? r.articuloId} ×${r.cantidad}';
  final mostrados = renglones.take(_maxArticulosMostrados).map(etiqueta).join(' · ');
  final restantes = renglones.length - _maxArticulosMostrados;
  return restantes > 0 ? '$mostrados · ${l10n.comprasArticulosMasTexto(restantes)}' : mostrados;
}

/// Listado de Compras (Etapa 10, pasada UX/UI Etapa 19) — filtros
/// combinables (rango de fechas, folio, proveedor, artículo, estatus,
/// forma de pago) + un resumen KPI derivado de las Compras ya cargadas
/// (nunca una consulta nueva por indicador, ver el doc comment de
/// `ComprasState`). Sin pestañas todavía — una sola pantalla, mismo
/// criterio que Inventario 7A/Vehículos 8A/Telefonía 9A.
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

  void _limpiarFiltros(ComprasController notifier) {
    _folioController.clear();
    _proveedorController.clear();
    notifier.limpiarTodosLosFiltros();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(comprasControllerProvider);
    final notifier = ref.read(comprasControllerProvider.notifier);
    final colors = context.colors;
    // Derivado de `_articulos` (ya cargado en bloque para el filtro de
    // Artículo) — nunca una consulta nueva para resolver nombres.
    final nombrePorArticuloId = {for (final a in _articulos) a.id: a.nombre};

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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RisegSectionHeader(
            title: l10n.comprasListadoTitulo,
            description: l10n.comprasListadoSubtitulo,
            primaryAction: RisegButton(
              key: const Key('compras_boton_registrar'),
              label: l10n.comprasListadoBotonRegistrar,
              icon: Icons.add,
              onPressed: _registrar,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              SizedBox(
                width: 190,
                child: RisegStatCard(
                  dense: true,
                  label: l10n.comprasResumenComprasDelPeriodo,
                  value: '${state.resumenComprasDelPeriodo}',
                ),
              ),
              SizedBox(
                width: 190,
                child: RisegStatCard(
                  dense: true,
                  label: l10n.comprasResumenTotalComprado,
                  value: formatoCosto(state.resumenTotalComprado),
                ),
              ),
              SizedBox(
                width: 190,
                child: RisegStatCard(
                  dense: true,
                  label: l10n.comprasResumenArticulosAdquiridos,
                  value: '${state.resumenArticulosAdquiridos}',
                ),
              ),
              SizedBox(
                width: 190,
                child: RisegStatCard(
                  dense: true,
                  label: l10n.comprasResumenProveedores,
                  value: '${state.resumenProveedoresDistintos}',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 150,
                child: RisegDateField(
                  label: l10n.comprasFiltroDesde,
                  value: state.desde,
                  onChanged: (valor) => notifier.aplicarFiltros(desde: valor),
                ),
              ),
              SizedBox(
                width: 150,
                child: RisegDateField(
                  label: l10n.comprasFiltroHasta,
                  value: state.hasta,
                  onChanged: (valor) => notifier.aplicarFiltros(hasta: valor),
                ),
              ),
              SizedBox(
                width: 170,
                child: RisegTextField(
                  label: l10n.comprasFiltroFolio,
                  controller: _folioController,
                  onChanged: (valor) => notifier.aplicarFiltros(folio: valor, limpiarFolio: valor.trim().isEmpty),
                ),
              ),
              SizedBox(
                width: 200,
                child: RisegTextField(
                  label: l10n.comprasFiltroProveedor,
                  controller: _proveedorController,
                  onChanged: (valor) =>
                      notifier.aplicarFiltros(proveedor: valor, limpiarProveedor: valor.trim().isEmpty),
                ),
              ),
              SizedBox(
                width: 190,
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
              SizedBox(
                width: 160,
                child: RisegSelect<String?>(
                  label: l10n.comprasFiltroFormaPago,
                  value: state.formaPago,
                  items: [
                    RisegSelectItem(value: null, label: l10n.comprasFiltroFormaPagoTodas),
                    for (final f in FormaPago.values) RisegSelectItem(value: f.name, label: formaPagoLabel(l10n, f.name)),
                  ],
                  onChanged: (valor) => notifier.aplicarFiltros(formaPago: valor, limpiarFormaPago: valor == null),
                ),
              ),
              SizedBox(
                width: 150,
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
              RisegButton(
                label: l10n.comprasLimpiarFiltros,
                variant: RisegButtonVariant.ghost,
                onPressed: state.hayFiltrosActivos ? () => _limpiarFiltros(notifier) : null,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          RisegTableBase<CompraData>(
            loading: state.cargando,
            rows: state.compras,
            onRowTap: (c) => context.push('/compras/${c.id}'),
            emptyState: state.hayFiltrosActivos
                ? RisegEmptyState(title: l10n.comprasListadoVacioFiltradoTitulo, message: l10n.comprasListadoVacioFiltradoMensaje)
                : RisegEmptyState(title: l10n.comprasListadoVacioTitulo, message: l10n.comprasListadoVacioMensaje),
            hoverColor: colors.accentSoftBg,
            rowVerticalPadding: AppSpacing.sm + AppSpacing.xxs,
            rowActionsBuilder: (_) => Icon(Icons.chevron_right, size: AppSizes.iconMd, color: colors.textMuted),
            actionsWidth: 40,
            columns: [
              // Etapa 19: Folio fusionado con Fecha en una identidad —
              // el folio domina, la fecha queda como dato secundario
              // (mismo criterio ya usado por Inventario/Nómina). Ancho
              // fijo (Etapa 19.1): "Artículos comprados" es ahora la
              // columna flexible/dominante, no esta.
              RisegColumn<CompraData>(
                label: l10n.comprasColumnaCompra,
                width: 140,
                cellBuilder: (c) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(c.folioCompra, style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(_formatoFecha.format(c.fecha), style: AppTypography.caption.copyWith(color: colors.textMuted)),
                  ],
                ),
              ),
              // Etapa 19.1: reemplaza la columna "Artículos" (conteo de
              // renglones) — ahora muestra QUÉ se compró: nombre real +
              // cantidad real de cada renglón `destino == inventario`,
              // truncado a `_maxArticulosMostrados` con "+N más" y
              // tooltip con la lista completa. Proveedor/establecimiento
              // se retira de la tabla (sigue en filtro/formulario/
              // expediente) — este es ahora el ancho que libera.
              RisegColumn<CompraData>(
                label: l10n.comprasColumnaArticulos,
                cellBuilder: (c) {
                  final renglones = state.articulosPorCompra[c.id] ?? const [];
                  if (renglones.isEmpty) {
                    return Text(l10n.comprasArticulosSinRenglones, style: AppTypography.body.copyWith(color: colors.textMuted));
                  }
                  final texto = _textoArticulosComprados(l10n, renglones, nombrePorArticuloId);
                  final textoWidget = Text(texto, maxLines: 1, overflow: TextOverflow.ellipsis);
                  if (renglones.length <= _maxArticulosMostrados) return textoWidget;
                  final completo = renglones
                      .map((r) => '${nombrePorArticuloId[r.articuloId] ?? r.articuloId} ×${r.cantidad}')
                      .join(' · ');
                  return Tooltip(message: completo, child: textoWidget);
                },
              ),
              RisegColumn<CompraData>(
                label: l10n.comprasColumnaTotal,
                width: 130,
                alignment: TextAlign.right,
                cellBuilder: (c) => Text(
                  formatoCosto(state.totalesPorCompra[c.id] ?? 0),
                  style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary),
                ),
              ),
              RisegColumn<CompraData>(
                label: l10n.comprasColumnaFormaPago,
                width: 150,
                cellBuilder: (c) {
                  final tarjeta = state.tarjetaPorCompra[c.id];
                  if (tarjeta == null) return Text(formaPagoLabel(l10n, c.formaPago));
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(formaPagoLabel(l10n, c.formaPago)),
                      Text(
                        '${tarjeta.nombre} · •••• ${tarjeta.ultimosDigitos ?? '----'}',
                        style: AppTypography.caption.copyWith(color: colors.textMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  );
                },
              ),
              RisegColumn<CompraData>(
                label: l10n.comprasColumnaEstatus,
                width: 130,
                cellBuilder: (c) =>
                    RisegStatusBadge(label: compraEstatusLabel(l10n, c.estatus), tone: compraEstatusTono(c.estatus)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
