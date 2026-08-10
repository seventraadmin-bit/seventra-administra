import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_list_screen.dart' show formatoCentavosPago;

import 'articulos_controller.dart';
import 'articulos_state.dart';
import 'widgets/gestionar_articulo_dialog.dart';
import 'widgets/gestionar_categoria_articulo_dialog.dart';

String articuloTipoLabel(AppLocalizations l10n, ArticuloResumen r) {
  return r.articulo.manejaSerie ? l10n.articuloTipoSerie : l10n.articuloTipoCantidad;
}

/// Catálogo + existencia de Artículos (Etapa 7A) — la pantalla
/// principal de Inventario. Existencia y catálogo viven en la misma
/// tabla a propósito: son casi siempre la misma pregunta vista
/// distinto ("qué tengo" y "cuánto tengo").
class ArticulosListScreen extends ConsumerWidget {
  const ArticulosListScreen({super.key});

  Future<void> _nuevoArticulo(BuildContext context, WidgetRef ref) async {
    if (ref.read(articulosControllerProvider).categorias.isEmpty) {
      await showDialog<void>(context: context, builder: (_) => const GestionarCategoriaArticuloDialog());
      if (!context.mounted) return;
    }
    await mostrarDialogoGestionarArticulo(context, ref);
  }

  Future<void> _gestionarCategorias(BuildContext context) async {
    await showDialog<void>(context: context, builder: (_) => const GestionarCategoriaArticuloDialog());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(articulosControllerProvider);
    final notifier = ref.read(articulosControllerProvider.notifier);

    if (state.errorCarga != null && state.articulos.isEmpty) {
      return RisegEmptyState(
        icon: Icons.error_outline,
        title: l10n.inventarioListadoCargaErrorTitulo,
        message: l10n.inventarioListadoCargaErrorMensaje,
        primaryAction: RisegButton(
          key: const Key('inventario_boton_reintentar'),
          label: l10n.inventarioListadoBotonReintentar,
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
            title: l10n.inventarioListadoTitulo,
            primaryAction: RisegButton(
              key: const Key('inventario_boton_nuevo_articulo'),
              label: l10n.inventarioBotonNuevoArticulo,
              onPressed: () => _nuevoArticulo(context, ref),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerRight,
            child: RisegButton(
              key: const Key('inventario_boton_categorias'),
              label: l10n.inventarioBotonCategorias,
              variant: RisegButtonVariant.ghost,
              onPressed: () => _gestionarCategorias(context),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: RisegTableBase<ArticuloResumen>(
              loading: state.cargando,
              rows: state.articulos,
              onRowTap: (r) => context.go('/inventario/articulos/${r.articulo.id}'),
              emptyState: RisegEmptyState(
                title: l10n.inventarioListadoVacioTitulo,
                message: l10n.inventarioListadoVacioMensaje,
              ),
              columns: [
                RisegColumn<ArticuloResumen>(
                  label: l10n.inventarioColumnaFolio,
                  width: 110,
                  cellBuilder: (r) => Text(r.articulo.folio),
                ),
                RisegColumn<ArticuloResumen>(
                  label: l10n.inventarioColumnaNombre,
                  cellBuilder: (r) => Text(r.articulo.nombre),
                ),
                RisegColumn<ArticuloResumen>(
                  label: l10n.inventarioColumnaCategoria,
                  cellBuilder: (r) => Text(r.categoriaNombre),
                ),
                RisegColumn<ArticuloResumen>(
                  label: l10n.inventarioColumnaTipo,
                  width: 130,
                  cellBuilder: (r) => Text(articuloTipoLabel(l10n, r)),
                ),
                RisegColumn<ArticuloResumen>(
                  label: l10n.inventarioColumnaTotal,
                  width: 90,
                  alignment: TextAlign.right,
                  cellBuilder: (r) => Text(r.existencia.total.toString()),
                ),
                RisegColumn<ArticuloResumen>(
                  label: l10n.inventarioColumnaDisponible,
                  width: 110,
                  alignment: TextAlign.right,
                  cellBuilder: (r) => Text(r.existencia.disponible.toString()),
                ),
                RisegColumn<ArticuloResumen>(
                  label: l10n.inventarioColumnaDanado,
                  width: 130,
                  alignment: TextAlign.right,
                  cellBuilder: (r) => Text((r.existencia.danado + r.existencia.perdido).toString()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Reexportado para uso en el expediente (formato de moneda).
String formatoCosto(int centavos) => formatoCentavosPago(centavos);
