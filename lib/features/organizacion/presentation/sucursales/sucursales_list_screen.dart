import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/data/tables/sucursal_table.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/catalogo_repository.dart';

import '../../organizacion_providers.dart';
import 'sucursales_list_controller.dart';

/// Listado de Sucursales — buscador (código/nombre/tipo), tabla y alta
/// vía diálogo (solo nombre + tipo; el resto se captura en el expediente
/// recién creado).
class SucursalesListScreen extends ConsumerStatefulWidget {
  const SucursalesListScreen({super.key});

  @override
  ConsumerState<SucursalesListScreen> createState() => _SucursalesListScreenState();
}

class _SucursalesListScreenState extends ConsumerState<SucursalesListScreen> {
  final _busquedaController = TextEditingController();

  @override
  void dispose() {
    _busquedaController.dispose();
    super.dispose();
  }

  Future<void> _mostrarDialogoAlta(List<CatalogoItem> tipos) async {
    final l10n = AppLocalizations.of(context)!;
    var nombreActual = '';
    String? tipoSeleccionado;

    final creada = await RisegDialog.showForm<SucursalData?>(
      context: context,
      title: l10n.sucursalAltaTitulo,
      confirmLabel: l10n.sucursalAltaBotonCrear,
      cancelLabel: l10n.sucursalAltaBotonCancelar,
      contentBuilder: (_) => _AltaSucursalForm(
        tipos: tipos,
        onNombreChanged: (valor) => nombreActual = valor,
        onTipoChanged: (valor) => tipoSeleccionado = valor,
      ),
      onConfirm: () async {
        final nombre = nombreActual.trim();
        final tipo = tipoSeleccionado;
        if (nombre.isEmpty || tipo == null) return null;

        final resultado = await ref.read(crearSucursalAutorizadoProvider)(nombre: nombre, tipoSucursalId: tipo);
        return resultado.when(ok: (s) => s, failure: (_) => null);
      },
    );

    if (!mounted) return;

    if (creada != null) {
      ref.read(sucursalesListControllerProvider.notifier).recargar();
      RisegFeedback.showSuccess(context, l10n.sucursalCrearExito);
      context.push('/organizacion/sucursales/${creada.id}');
    } else {
      RisegFeedback.showError(context, l10n.sucursalCrearError);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(sucursalesListControllerProvider);
    final notifier = ref.read(sucursalesListControllerProvider.notifier);

    if (state.errorCarga != null && state.sucursales.isEmpty) {
      return RisegEmptyState(
        icon: Icons.error_outline,
        title: l10n.sucursalesListadoCargaErrorTitulo,
        message: l10n.sucursalesListadoCargaErrorMensaje,
        primaryAction: RisegButton(
          key: const Key('sucursales_boton_reintentar'),
          label: l10n.sucursalesListadoBotonReintentar,
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
            title: l10n.sucursalesListadoTitulo,
            primaryAction: RisegButton(
              key: const Key('sucursales_boton_nueva'),
              label: l10n.sucursalesListadoBotonNueva,
              onPressed: () => _mostrarDialogoAlta(state.tipos),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          RisegSearchField(
            hint: l10n.sucursalesListadoBuscarHint,
            controller: _busquedaController,
            onChanged: notifier.actualizarBusqueda,
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: RisegTableBase<SucursalData>(
              loading: state.cargando,
              rows: state.sucursalesFiltradas,
              onRowTap: (sucursal) => context.push('/organizacion/sucursales/${sucursal.id}'),
              emptyState: RisegEmptyState(
                title: l10n.sucursalesListadoVacioTitulo,
                message: l10n.sucursalesListadoVacioMensaje,
              ),
              columns: [
                RisegColumn<SucursalData>(label: l10n.sucursalesColumnaCodigo, width: 120, cellBuilder: (s) => Text(s.codigo)),
                RisegColumn<SucursalData>(label: l10n.sucursalesColumnaNombre, cellBuilder: (s) => Text(s.nombre)),
                RisegColumn<SucursalData>(
                  label: l10n.sucursalesColumnaTipo,
                  cellBuilder: (s) => Text(state.nombreTipo(s.tipoSucursalId) ?? ''),
                ),
                RisegColumn<SucursalData>(
                  label: l10n.sucursalesColumnaEstado,
                  width: 180,
                  cellBuilder: (s) => RisegStatusBadge(
                    label: s.estadoOperativo == EstadoOperativoSucursal.operando.name
                        ? l10n.sucursalEstadoOperativoOperando
                        : l10n.sucursalEstadoOperativoCerradaTemporalmente,
                    tone: s.estadoOperativo == EstadoOperativoSucursal.operando.name
                        ? RisegStatusTone.success
                        : RisegStatusTone.warning,
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

/// Contenido del diálogo de alta — un `StatefulWidget` propio (no una
/// pareja `TextEditingController` + `StatefulBuilder` en el método que
/// abre el diálogo) para que el `TextEditingController` se cree y se
/// destruya con el ciclo de vida real del widget. Deshacerlo a mano justo
/// después de `await RisegDialog.showForm(...)` competía con la animación
/// de salida del diálogo (el campo podía seguir montado un frame más),
/// lanzando "TextEditingController usado después de dispose()" — un bug
/// real encontrado al escribir las pruebas de este flujo.
class _AltaSucursalForm extends StatefulWidget {
  const _AltaSucursalForm({required this.tipos, required this.onNombreChanged, required this.onTipoChanged});

  final List<CatalogoItem> tipos;
  final ValueChanged<String> onNombreChanged;
  final ValueChanged<String?> onTipoChanged;

  @override
  State<_AltaSucursalForm> createState() => _AltaSucursalFormState();
}

class _AltaSucursalFormState extends State<_AltaSucursalForm> {
  final _nombreController = TextEditingController();
  String? _tipoSeleccionado;

  @override
  void dispose() {
    _nombreController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RisegTextField(
          label: l10n.sucursalAltaCampoNombre,
          controller: _nombreController,
          autofocus: true,
          onChanged: widget.onNombreChanged,
        ),
        const SizedBox(height: AppSpacing.md),
        RisegSelect<String>(
          label: l10n.sucursalAltaCampoTipo,
          value: _tipoSeleccionado,
          items: [for (final tipo in widget.tipos) RisegSelectItem(value: tipo.id, label: tipo.nombre)],
          onChanged: (valor) {
            setState(() => _tipoSeleccionado = valor);
            widget.onTipoChanged(valor);
          },
        ),
      ],
    );
  }
}
