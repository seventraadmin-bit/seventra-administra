import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';

import '../../organizacion_providers.dart';
import '../../domain/usecases/guardar_area_resultado.dart';
import '../../domain/usecases/desactivar_area_usecase.dart';
import 'areas_list_controller.dart';

/// Listado de Áreas — sin buscador (fuera de alcance), alta/edición vía
/// el mismo diálogo, y activar/desactivar por fila. Desactivar primero
/// llama al caso de uso: si bloquea por Puestos activos, muestra el
/// error directo sin ningún diálogo de confirmación; si no bloquea,
/// entonces sí pide confirmación antes de aplicar el cambio.
class AreasListScreen extends ConsumerWidget {
  const AreasListScreen({super.key});

  Future<void> _mostrarDialogoAltaEdicion(BuildContext context, WidgetRef ref, {AreaData? area}) async {
    final l10n = AppLocalizations.of(context)!;
    var nombre = area?.nombre ?? '';
    var descripcion = area?.descripcion ?? '';

    final resultado = await RisegDialog.showForm<GuardarAreaResultado>(
      context: context,
      title: area == null ? l10n.areaDialogoTituloAlta : l10n.areaDialogoTituloEdicion,
      confirmLabel: l10n.areaDialogoBotonGuardar,
      cancelLabel: l10n.areaDialogoBotonCancelar,
      contentBuilder: (_) => _AreaForm(
        nombreInicial: nombre,
        descripcionInicial: descripcion,
        onCambio: (n, d) {
          nombre = n;
          descripcion = d;
        },
      ),
      onConfirm: () async {
        if (area == null) {
          return ref.read(crearAreaAutorizadoProvider)(nombre: nombre, descripcion: descripcion);
        }
        return ref.read(actualizarAreaAutorizadoProvider)(id: area.id, nombre: nombre, descripcion: descripcion);
      },
    );

    if (!context.mounted) return;

    switch (resultado) {
      case GuardarAreaExitoso():
        ref.read(areasListControllerProvider.notifier).recargar();
        RisegFeedback.showSuccess(context, l10n.areaGuardadoExito);
      case GuardarAreaNombreRequerido():
      case GuardarAreaErrorInesperado():
        RisegFeedback.showError(context, l10n.areaGuardadoError);
      case null:
        break;
    }
  }

  Future<void> _activar(BuildContext context, WidgetRef ref, AreaData area) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmado = await RisegDialog.showConfirmation(
      context: context,
      title: l10n.areaConfirmarActivarTitulo,
      message: l10n.areaConfirmarActivarMensaje,
      confirmLabel: l10n.sucursalConfirmarAceptar,
      cancelLabel: l10n.sucursalConfirmarCancelar,
    );
    if (confirmado != true) return;

    final actualizada = await ref.read(activarAreaAutorizadoProvider)(area.id);
    if (!context.mounted) return;
    if (actualizada == null) {
      RisegFeedback.showError(context, l10n.accesoDenegadoAccionMensaje);
      return;
    }
    ref.read(areasListControllerProvider.notifier).recargar();
    RisegFeedback.showSuccess(context, l10n.areaCicloVidaCambiadoExito);
  }

  Future<void> _desactivar(BuildContext context, WidgetRef ref, AreaData area) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmado = await RisegDialog.showConfirmation(
      context: context,
      title: l10n.areaConfirmarDesactivarTitulo,
      message: l10n.areaConfirmarDesactivarMensaje,
      confirmLabel: l10n.sucursalConfirmarAceptar,
      cancelLabel: l10n.sucursalConfirmarCancelar,
      destructive: true,
    );
    if (confirmado != true) return;

    final resultado = await ref.read(desactivarAreaAutorizadoProvider)(area.id);

    if (!context.mounted) return;

    if (resultado is DesactivarAreaBloqueadaPorPuestosActivos) {
      RisegFeedback.showError(context, l10n.areaDesactivarBloqueadaError(resultado.cantidad));
      return;
    }
    if (resultado is DesactivarAreaErrorInesperado) {
      RisegFeedback.showError(context, l10n.accesoDenegadoAccionMensaje);
      return;
    }

    ref.read(areasListControllerProvider.notifier).recargar();
    RisegFeedback.showSuccess(context, l10n.areaCicloVidaCambiadoExito);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
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
            primaryAction: RisegButton(
              key: const Key('areas_boton_nueva'),
              label: l10n.areasListadoBotonNueva,
              onPressed: () => _mostrarDialogoAltaEdicion(context, ref),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: RisegTableBase<AreaData>(
              loading: state.cargando,
              rows: state.areas,
              emptyState: RisegEmptyState(
                title: l10n.areasListadoVacioTitulo,
                message: l10n.areasListadoVacioMensaje,
              ),
              columns: [
                RisegColumn<AreaData>(label: l10n.areasColumnaCodigo, width: 110, cellBuilder: (a) => Text(a.codigo)),
                RisegColumn<AreaData>(label: l10n.areasColumnaNombre, cellBuilder: (a) => Text(a.nombre)),
                RisegColumn<AreaData>(
                  label: l10n.areasColumnaEstado,
                  width: 140,
                  cellBuilder: (a) => RisegStatusBadge(
                    label: a.activo ? l10n.areaEstadoActivo : l10n.areaEstadoInactivo,
                    tone: a.activo ? RisegStatusTone.success : RisegStatusTone.neutral,
                  ),
                ),
              ],
              rowActionsBuilder: (area) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: l10n.areaDialogoBotonGuardar,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _mostrarDialogoAltaEdicion(context, ref, area: area),
                  ),
                  IconButton(
                    tooltip: area.activo ? l10n.areaBotonDesactivar : l10n.areaBotonActivar,
                    icon: Icon(area.activo ? Icons.toggle_on_outlined : Icons.toggle_off_outlined, size: 18),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => area.activo ? _desactivar(context, ref, area) : _activar(context, ref, area),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Contenido del diálogo de alta/edición — `StatefulWidget` propio para
/// que sus `TextEditingController` vivan y mueran con el ciclo de vida
/// real del widget.
class _AreaForm extends StatefulWidget {
  const _AreaForm({required this.nombreInicial, required this.descripcionInicial, required this.onCambio});

  final String nombreInicial;
  final String descripcionInicial;
  final void Function(String nombre, String descripcion) onCambio;

  @override
  State<_AreaForm> createState() => _AreaFormState();
}

class _AreaFormState extends State<_AreaForm> {
  late final _nombreController = TextEditingController(text: widget.nombreInicial);
  late final _descripcionController = TextEditingController(text: widget.descripcionInicial);

  @override
  void dispose() {
    _nombreController.dispose();
    _descripcionController.dispose();
    super.dispose();
  }

  void _notificar() => widget.onCambio(_nombreController.text, _descripcionController.text);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RisegTextField(
          label: l10n.areaCampoNombre,
          controller: _nombreController,
          autofocus: true,
          onChanged: (_) => _notificar(),
        ),
        const SizedBox(height: AppSpacing.md),
        RisegTextField(
          label: l10n.areaCampoDescripcion,
          controller: _descripcionController,
          onChanged: (_) => _notificar(),
        ),
      ],
    );
  }
}
