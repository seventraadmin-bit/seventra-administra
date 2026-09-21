import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';

import 'areas_list_controller.dart';
import 'widgets/area_form_dialog.dart';

/// Listado de Áreas (Etapa 16, tercera pasada visual) — estructura
/// organizacional, con buscador y métricas reales (Puestos/Personal)
/// por Área. Las acciones destructivas/edición viven en el expediente
/// de cada Área, no como iconos permanentes en cada fila (ver
/// `AreaExpedienteScreen`).
class AreasListScreen extends ConsumerStatefulWidget {
  const AreasListScreen({super.key});

  @override
  ConsumerState<AreasListScreen> createState() => _AreasListScreenState();
}

class _AreasListScreenState extends ConsumerState<AreasListScreen> {
  final _busquedaController = TextEditingController();

  @override
  void dispose() {
    _busquedaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final state = ref.watch(areasListControllerProvider);
    final notifier = ref.read(areasListControllerProvider.notifier);

    if (state.errorCarga != null && state.areas.isEmpty) {
      return RisegEmptyState(
        icon: Icons.error_outline,
        title: l10n.areasListadoCargaErrorTitulo,
        message: l10n.areasListadoCargaErrorMensaje,
        primaryAction: RisegButton(
          key: const Key('areas_boton_reintentar'),
          label: l10n.areasListadoBotonReintentar,
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
            title: l10n.areasListadoTitulo,
            description: l10n.areasListadoSubtitulo,
            primaryAction: RisegButton(
              key: const Key('areas_boton_nueva'),
              label: l10n.areasListadoBotonNueva,
              icon: Icons.add,
              onPressed: () => mostrarDialogoAreaAltaEdicion(context, ref),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: 320,
            child: RisegSearchField(
              hint: l10n.areasListadoBuscarHint,
              controller: _busquedaController,
              onChanged: notifier.actualizarBusqueda,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: RisegTableBase<AreaData>(
              loading: state.cargando,
              rows: state.areasFiltradas,
              onRowTap: (area) => context.push('/organizacion/areas/${area.id}'),
              emptyState: RisegEmptyState(
                title: l10n.areasListadoVacioTitulo,
                message: l10n.areasListadoVacioMensaje,
              ),
              hoverColor: colors.accentSoftBg,
              rowVerticalPadding: AppSpacing.sm + AppSpacing.xxs,
              rowActionsBuilder: (_) => Icon(Icons.chevron_right, size: AppSizes.iconMd, color: colors.textMuted),
              actionsWidth: 40,
              columns: [
                RisegColumn<AreaData>(
                  label: l10n.areasColumnaArea,
                  cellBuilder: (a) => Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.nombre, style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary)),
                      const SizedBox(height: 2),
                      Text(a.codigo, style: AppTypography.caption.copyWith(color: colors.textMuted)),
                    ],
                  ),
                ),
                RisegColumn<AreaData>(
                  label: l10n.areasColumnaPuestos,
                  width: 130,
                  cellBuilder: (a) => Text(l10n.areaCantidadPuestos(state.puestosPorArea[a.id] ?? 0)),
                ),
                RisegColumn<AreaData>(
                  label: l10n.areasColumnaPersonal,
                  width: 130,
                  cellBuilder: (a) => Text(l10n.areaCantidadPersonal(state.personalPorArea[a.id] ?? 0)),
                ),
                RisegColumn<AreaData>(
                  label: l10n.areasColumnaEstado,
                  width: 140,
                  cellBuilder: (a) => RisegStatusBadge(
                    label: a.activo ? l10n.areaEstadoActivo : l10n.areaEstadoInactivo,
                    tone: a.activo ? RisegStatusTone.success : RisegStatusTone.neutral,
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
