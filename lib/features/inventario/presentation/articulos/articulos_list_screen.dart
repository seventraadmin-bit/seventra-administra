import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_list_screen.dart' show formatoCentavosPago;
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

import 'articulos_controller.dart';
import 'articulos_state.dart';
import 'widgets/gestionar_articulo_dialog.dart';
import 'widgets/gestionar_categoria_articulo_dialog.dart';

String articuloTipoLabel(AppLocalizations l10n, ArticuloResumen r) {
  return articuloTipoLabelDe(l10n, r.articulo.manejaSerie);
}

/// Misma etiqueta que [articuloTipoLabel], sin necesitar un
/// `ArticuloResumen` completo — reutilizada por el expediente.
String articuloTipoLabelDe(AppLocalizations l10n, bool manejaSerie) {
  return manejaSerie ? l10n.articuloTipoSerie : l10n.articuloTipoCantidad;
}

/// Catálogo + existencia de Artículos (Etapa 7A) — la pantalla
/// principal de Inventario. Existencia y catálogo viven en la misma
/// tabla a propósito: son casi siempre la misma pregunta vista
/// distinto ("qué tengo" y "cuánto tengo").
class ArticulosListScreen extends ConsumerStatefulWidget {
  const ArticulosListScreen({super.key});

  @override
  ConsumerState<ArticulosListScreen> createState() => _ArticulosListScreenState();
}

class _ArticulosListScreenState extends ConsumerState<ArticulosListScreen> {
  final _buscarCtrl = TextEditingController();

  @override
  void dispose() {
    _buscarCtrl.dispose();
    super.dispose();
  }

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
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ref = this.ref;
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

    final colors = context.colors;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RisegSectionHeader(
            title: l10n.inventarioListadoTitulo,
            description: l10n.inventarioListadoSubtitulo,
            primaryAction: RisegButton(
              key: const Key('inventario_boton_nuevo_articulo'),
              label: l10n.inventarioBotonNuevoArticulo,
              icon: Icons.add,
              onPressed: ref.watch(permissionServiceProvider).hasCode('inventario.crear')
                  ? () => _nuevoArticulo(context, ref)
                  : null,
            ),
            secondaryAction: RisegButton(
              key: const Key('inventario_boton_categorias'),
              label: l10n.inventarioBotonCategorias,
              icon: Icons.category_outlined,
              variant: RisegButtonVariant.ghost,
              onPressed: () => _gestionarCategorias(context),
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
                  label: l10n.inventarioResumenArticulosRegistrados,
                  value: '${state.resumenArticulosRegistrados}',
                ),
              ),
              SizedBox(
                width: 190,
                child: RisegStatCard(
                  dense: true,
                  label: l10n.inventarioResumenUnidadesTotales,
                  value: '${state.resumenUnidadesTotales}',
                ),
              ),
              SizedBox(
                width: 190,
                child: RisegStatCard(
                  dense: true,
                  label: l10n.inventarioResumenUnidadesDisponibles,
                  value: '${state.resumenUnidadesDisponibles}',
                ),
              ),
              SizedBox(
                width: 190,
                child: RisegStatCard(
                  dense: true,
                  label: l10n.inventarioResumenUnidadesAsignadas,
                  value: '${state.resumenUnidadesAsignadas}',
                ),
              ),
              SizedBox(
                width: 190,
                child: RisegStatCard(
                  dense: true,
                  label: l10n.inventarioResumenDanadasPerdidas,
                  value: '${state.resumenUnidadesDanadasPerdidas}',
                  deltaTone: state.resumenUnidadesDanadasPerdidas > 0 ? RisegStatusTone.warning : RisegStatusTone.success,
                ),
              ),
              // "Unidades totales" incluye lo que está en lavandería o
              // reparación (sigue siendo de RISEG). Sin este KPI, el
              // total no cuadraría con las cubetas de al lado.
              SizedBox(
                width: 190,
                child: RisegStatCard(
                  dense: true,
                  label: l10n.inventarioResumenUnidadesEnProceso,
                  value: '${state.resumenUnidadesEnProceso}',
                  delta: state.resumenUnidadesEnProceso > 0 ? l10n.inventarioResumenUnidadesEnProcesoNota : null,
                  deltaTone: state.resumenUnidadesEnProceso > 0 ? RisegStatusTone.warning : null,
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
                width: 240,
                child: RisegSearchField(
                  hint: l10n.inventarioBuscar,
                  controller: _buscarCtrl,
                  onChanged: (valor) => notifier.aplicarFiltros(texto: valor, limpiarTexto: valor.isEmpty),
                ),
              ),
              SizedBox(
                width: 190,
                child: RisegSelect<String?>(
                  label: l10n.inventarioFiltroCategoria,
                  value: state.categoriaId,
                  items: [
                    RisegSelectItem(value: null, label: l10n.inventarioFiltroCategoriaTodas),
                    for (final c in state.categorias) RisegSelectItem(value: c.id, label: c.nombre),
                  ],
                  onChanged: (valor) => notifier.aplicarFiltros(categoriaId: valor, limpiarCategoriaId: valor == null),
                ),
              ),
              SizedBox(
                width: 170,
                child: RisegSelect<FiltroTipoArticulo>(
                  label: l10n.inventarioFiltroTipo,
                  value: state.tipo,
                  items: [
                    RisegSelectItem(value: FiltroTipoArticulo.todos, label: l10n.inventarioFiltroTipoTodos),
                    RisegSelectItem(value: FiltroTipoArticulo.cantidad, label: l10n.inventarioFiltroTipoCantidad),
                    RisegSelectItem(value: FiltroTipoArticulo.serie, label: l10n.inventarioFiltroTipoSerie),
                  ],
                  onChanged: (valor) => notifier.aplicarFiltros(tipo: valor),
                ),
              ),
              SizedBox(
                width: 190,
                child: RisegSelect<FiltroEstadoExistencia>(
                  label: l10n.inventarioFiltroEstadoExistencia,
                  value: state.estadoExistencia,
                  items: [
                    RisegSelectItem(value: FiltroEstadoExistencia.todos, label: l10n.inventarioFiltroEstadoTodos),
                    RisegSelectItem(
                      value: FiltroEstadoExistencia.conDisponibilidad,
                      label: l10n.inventarioFiltroEstadoConDisponibilidad,
                    ),
                    RisegSelectItem(
                      value: FiltroEstadoExistencia.sinDisponibilidad,
                      label: l10n.inventarioFiltroEstadoSinDisponibilidad,
                    ),
                    RisegSelectItem(
                      value: FiltroEstadoExistencia.conAsignaciones,
                      label: l10n.inventarioFiltroEstadoConAsignaciones,
                    ),
                    RisegSelectItem(
                      value: FiltroEstadoExistencia.danadoPerdido,
                      label: l10n.inventarioFiltroEstadoDanadoPerdido,
                    ),
                  ],
                  onChanged: (valor) => notifier.aplicarFiltros(estadoExistencia: valor),
                ),
              ),
              RisegButton(
                label: l10n.inventarioLimpiarFiltros,
                variant: RisegButtonVariant.ghost,
                onPressed: state.hayFiltrosActivos
                    ? () {
                        _buscarCtrl.clear();
                        notifier.limpiarTodosLosFiltros();
                      }
                    : null,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          RisegTableBase<ArticuloResumen>(
            loading: state.cargando,
            rows: state.visibles,
            onRowTap: (r) => context.go('/inventario/articulos/${r.articulo.id}'),
            emptyState: RisegEmptyState(
              title: l10n.inventarioListadoVacioTitulo,
              message: l10n.inventarioListadoVacioMensaje,
            ),
            hoverColor: colors.accentSoftBg,
            rowVerticalPadding: AppSpacing.sm + AppSpacing.xxs,
            rowActionsBuilder: (_) => Icon(Icons.chevron_right, size: AppSizes.iconMd, color: colors.textMuted),
            actionsWidth: 40,
            columns: [
              // Etapa 18, evolución visual: Folio + Nombre se fusionan en
              // una identidad — el nombre domina, el folio queda como
              // dato secundario (mismo criterio ya usado por Nómina,
              // Categoría financiera, etc.).
              RisegColumn<ArticuloResumen>(
                label: l10n.inventarioColumnaNombre,
                cellBuilder: (r) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(r.articulo.nombre, style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(r.articulo.folio, style: AppTypography.caption.copyWith(color: colors.textMuted)),
                  ],
                ),
              ),
              RisegColumn<ArticuloResumen>(
                label: l10n.inventarioColumnaCategoria,
                width: 150,
                cellBuilder: (r) => Text(r.categoriaNombre),
              ),
              RisegColumn<ArticuloResumen>(
                label: l10n.inventarioColumnaTipo,
                width: 120,
                cellBuilder: (r) => Text(articuloTipoLabel(l10n, r)),
              ),
              RisegColumn<ArticuloResumen>(
                label: l10n.inventarioColumnaTotal,
                width: 80,
                alignment: TextAlign.right,
                cellBuilder: (r) => Text(r.existencia.total.toString(), style: AppTypography.body.copyWith(color: colors.textMuted)),
              ),
              // Etapa 18: Disponible gana jerarquía sobre Total — es la
              // pregunta operativa real ("¿tengo para asignar?"). Si no
              // hay disponibilidad pero sí existencia/asignación, un
              // tratamiento de atención (badge de estado real, nunca un
              // estado persistido nuevo).
              RisegColumn<ArticuloResumen>(
                label: l10n.inventarioColumnaDisponible,
                width: 110,
                alignment: TextAlign.right,
                cellBuilder: (r) {
                  final sinDisponibilidad = r.existencia.disponible == 0 && r.existencia.total > 0;
                  return Text(
                    r.existencia.disponible.toString(),
                    style: AppTypography.bodyStrong.copyWith(color: sinDisponibilidad ? colors.warning : colors.textPrimary),
                  );
                },
              ),
              RisegColumn<ArticuloResumen>(
                label: l10n.inventarioColumnaAsignado,
                width: 100,
                alignment: TextAlign.right,
                cellBuilder: (r) => Text(r.existencia.asignado.toString()),
              ),
              RisegColumn<ArticuloResumen>(
                label: l10n.inventarioColumnaEnProceso,
                width: 110,
                alignment: TextAlign.right,
                cellBuilder: (r) => Text(r.existencia.enProceso.toString()),
              ),
              RisegColumn<ArticuloResumen>(
                label: l10n.inventarioColumnaDanado,
                width: 130,
                alignment: TextAlign.right,
                cellBuilder: (r) => Text((r.existencia.danado + r.existencia.perdido).toString()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Reexportado para uso en el expediente (formato de moneda).
String formatoCosto(int centavos) => formatoCentavosPago(centavos);
