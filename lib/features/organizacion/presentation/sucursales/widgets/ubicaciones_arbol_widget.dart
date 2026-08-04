import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/data/tables/ubicacion_table.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/ubicacion_repository.dart';

import '../ubicaciones_arbol_controller.dart';

const _tiposCreables = [
  TipoUbicacion.oficina,
  TipoUbicacion.almacen,
  TipoUbicacion.taller,
  TipoUbicacion.resguardo,
  TipoUbicacion.bajaTemporal,
];

String _nombreTipo(AppLocalizations l10n, TipoUbicacion tipo) {
  return switch (tipo) {
    TipoUbicacion.oficina => l10n.ubicacionesTipoOficina,
    TipoUbicacion.almacen => l10n.ubicacionesTipoAlmacen,
    TipoUbicacion.taller => l10n.ubicacionesTipoTaller,
    TipoUbicacion.resguardo => l10n.ubicacionesTipoResguardo,
    TipoUbicacion.bajaTemporal => l10n.ubicacionesTipoBajaTemporal,
    TipoUbicacion.sucursal => l10n.sucursalSeccionUbicacionesTitulo,
    TipoUbicacion.servicio || TipoUbicacion.areaInternaServicio => tipo.name,
  };
}

IconData _iconoTipo(TipoUbicacion tipo) {
  return switch (tipo) {
    TipoUbicacion.sucursal => Icons.store_outlined,
    TipoUbicacion.oficina => Icons.business_outlined,
    TipoUbicacion.almacen => Icons.warehouse_outlined,
    TipoUbicacion.taller => Icons.build_outlined,
    TipoUbicacion.resguardo => Icons.inventory_2_outlined,
    TipoUbicacion.bajaTemporal => Icons.block_outlined,
    TipoUbicacion.servicio || TipoUbicacion.areaInternaServicio => Icons.place_outlined,
  };
}

/// Recolecta los ids de un nodo y todos sus descendientes — para excluir
/// al nodo que se está moviendo (y su propio subárbol) de la lista de
/// posibles nuevos padres.
Set<String> _idsDelSubarbol(UbicacionArbol nodo) {
  final ids = <String>{nodo.nodo.id};
  for (final hijo in nodo.hijos) {
    ids.addAll(_idsDelSubarbol(hijo));
  }
  return ids;
}

List<({String id, String etiqueta})> _opcionesDeDestino(
  AppLocalizations l10n,
  UbicacionArbol raiz,
  Set<String> excluidos,
) {
  final opciones = <({String id, String etiqueta})>[];

  void recorrer(UbicacionArbol nodo, int profundidad) {
    if (!excluidos.contains(nodo.nodo.id)) {
      final sangria = '  ' * profundidad;
      opciones.add((id: nodo.nodo.id, etiqueta: '$sangria${nodo.nodo.nombre}'));
    }
    for (final hijo in nodo.hijos) {
      recorrer(hijo, profundidad + 1);
    }
  }

  recorrer(raiz, 0);
  return opciones;
}

/// Árbol de Ubicaciones de una Sucursal — expandir/colapsar todo,
/// agregar un nodo hijo, mover un nodo existente. Vive fuera del ciclo
/// consulta/edición del expediente: sus acciones son inmediatas, no
/// forman parte del "Guardar" del formulario.
class UbicacionesArbolWidget extends ConsumerWidget {
  const UbicacionesArbolWidget({required this.sucursalId, super.key});

  final String sucursalId;

  Future<void> _mostrarDialogoAgregar(BuildContext context, WidgetRef ref, String parentId) async {
    final l10n = AppLocalizations.of(context)!;
    var nombreActual = '';
    var tipoSeleccionado = _tiposCreables.first;

    final confirmado = await RisegDialog.showForm<bool>(
      context: context,
      title: l10n.ubicacionesAltaTitulo,
      confirmLabel: l10n.ubicacionesAltaBotonCrear,
      cancelLabel: l10n.ubicacionesAltaBotonCancelar,
      contentBuilder: (_) => _AltaUbicacionForm(
        onNombreChanged: (valor) => nombreActual = valor,
        onTipoChanged: (valor) => tipoSeleccionado = valor,
      ),
      onConfirm: () async {
        final nombre = nombreActual.trim();
        if (nombre.isEmpty) return false;
        return ref
            .read(ubicacionesArbolControllerProvider(sucursalId).notifier)
            .agregarUbicacion(parentId: parentId, nombre: nombre, tipo: tipoSeleccionado);
      },
    );

    if (!context.mounted) return;
    if (confirmado == true) {
      RisegFeedback.showSuccess(context, l10n.ubicacionAgregarExito);
    } else {
      RisegFeedback.showError(context, l10n.ubicacionAgregarError);
    }
  }

  Future<void> _mostrarDialogoMover(
    BuildContext context,
    WidgetRef ref,
    UbicacionArbol raiz,
    UbicacionArbol nodo,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final excluidos = _idsDelSubarbol(nodo);
    final opciones = _opcionesDeDestino(l10n, raiz, excluidos);
    String? destinoSeleccionado;

    final confirmado = await RisegDialog.showForm<bool>(
      context: context,
      title: l10n.ubicacionesMoverTitulo,
      confirmLabel: l10n.ubicacionesMoverBotonConfirmar,
      cancelLabel: l10n.ubicacionesMoverBotonCancelar,
      contentBuilder: (_) => StatefulBuilder(
        builder: (context, setState) => RisegSelect<String>(
          label: l10n.ubicacionesMoverSeleccionarDestino,
          value: destinoSeleccionado,
          items: [for (final o in opciones) RisegSelectItem(value: o.id, label: o.etiqueta)],
          onChanged: (valor) => setState(() => destinoSeleccionado = valor),
        ),
      ),
      onConfirm: () async {
        final destino = destinoSeleccionado;
        if (destino == null) return false;
        return ref
            .read(ubicacionesArbolControllerProvider(sucursalId).notifier)
            .moverUbicacion(ubicacionId: nodo.nodo.id, nuevoParentId: destino);
      },
    );

    if (!context.mounted) return;
    if (confirmado == true) {
      RisegFeedback.showSuccess(context, l10n.ubicacionMoverExito);
    } else {
      RisegFeedback.showError(context, l10n.ubicacionMoverError);
    }
  }

  Widget _construirNodo(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    UbicacionArbol raiz,
    UbicacionArbol nodo,
    int profundidad,
    Set<String> expandidos,
  ) {
    final colors = context.colors;
    final tipo = TipoUbicacion.values.byName(nodo.nodo.tipoUbicacion);
    final tieneHijos = nodo.hijos.isNotEmpty;
    final expandido = expandidos.contains(nodo.nodo.id);
    final esRaiz = nodo.nodo.parentId == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: profundidad * AppSpacing.lg, top: AppSpacing.xs, bottom: AppSpacing.xs),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: tieneHijos
                    ? IconButton(
                        padding: EdgeInsets.zero,
                        icon: Icon(expandido ? Icons.expand_more : Icons.chevron_right, size: 20),
                        onPressed: () => ref
                            .read(ubicacionesArbolControllerProvider(sucursalId).notifier)
                            .alternarExpandido(nodo.nodo.id),
                      )
                    : null,
              ),
              Icon(_iconoTipo(tipo), size: AppSizes.iconSm, color: colors.textMuted),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text('${nodo.nodo.nombre} · ${nodo.nodo.codigo}',
                    style: AppTypography.body.copyWith(color: colors.textPrimary)),
              ),
              IconButton(
                tooltip: l10n.ubicacionesBotonAgregar,
                icon: const Icon(Icons.add, size: 20),
                onPressed: () => _mostrarDialogoAgregar(context, ref, nodo.nodo.id),
              ),
              if (!esRaiz)
                IconButton(
                  tooltip: l10n.ubicacionesBotonMover,
                  icon: const Icon(Icons.drive_file_move_outline, size: 20),
                  onPressed: () => _mostrarDialogoMover(context, ref, raiz, nodo),
                ),
            ],
          ),
        ),
        if (tieneHijos && expandido)
          for (final hijo in nodo.hijos)
            _construirNodo(context, ref, l10n, raiz, hijo, profundidad + 1, expandidos),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(ubicacionesArbolControllerProvider(sucursalId));
    final notifier = ref.read(ubicacionesArbolControllerProvider(sucursalId).notifier);

    if (state.errorCarga != null && state.arbol == null) {
      return RisegEmptyState(
        icon: Icons.error_outline,
        title: l10n.sucursalExpedienteCargaErrorTitulo,
        message: l10n.sucursalExpedienteCargaErrorMensaje,
        primaryAction: RisegButton(label: l10n.sucursalExpedienteBotonReintentar, onPressed: notifier.reintentarCarga),
      );
    }

    final arbol = state.arbol;

    return RisegFormSection(
      title: l10n.sucursalSeccionUbicacionesTitulo,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            RisegButton(
              label: l10n.ubicacionesBotonExpandirTodo,
              variant: RisegButtonVariant.ghost,
              size: RisegButtonSize.compact,
              onPressed: arbol == null ? null : notifier.expandirTodo,
            ),
            const SizedBox(width: AppSpacing.xs),
            RisegButton(
              label: l10n.ubicacionesBotonColapsarTodo,
              variant: RisegButtonVariant.ghost,
              size: RisegButtonSize.compact,
              onPressed: arbol == null ? null : notifier.colapsarTodo,
            ),
          ],
        ),
        if (arbol == null)
          const SizedBox(height: AppSpacing.md, child: LinearProgressIndicator())
        else
          _construirNodo(context, ref, l10n, arbol, arbol, 0, state.expandidos),
      ],
    );
  }
}

/// Contenido del diálogo de alta de Ubicación — `StatefulWidget` propio
/// (mismo motivo que `_AltaSucursalForm`): el `TextEditingController`
/// debe vivir y morir con el ciclo de vida real del widget, no con un
/// `dispose()` manual justo después de `await RisegDialog.showForm(...)`,
/// que compite con la animación de salida del diálogo.
class _AltaUbicacionForm extends StatefulWidget {
  const _AltaUbicacionForm({required this.onNombreChanged, required this.onTipoChanged});

  final ValueChanged<String> onNombreChanged;
  final ValueChanged<TipoUbicacion> onTipoChanged;

  @override
  State<_AltaUbicacionForm> createState() => _AltaUbicacionFormState();
}

class _AltaUbicacionFormState extends State<_AltaUbicacionForm> {
  final _nombreController = TextEditingController();
  TipoUbicacion _tipoSeleccionado = _tiposCreables.first;

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
          label: l10n.ubicacionesAltaCampoNombre,
          controller: _nombreController,
          autofocus: true,
          onChanged: widget.onNombreChanged,
        ),
        const SizedBox(height: AppSpacing.md),
        RisegSelect<TipoUbicacion>(
          label: l10n.ubicacionesAltaCampoTipo,
          value: _tipoSeleccionado,
          items: [for (final tipo in _tiposCreables) RisegSelectItem(value: tipo, label: _nombreTipo(l10n, tipo))],
          onChanged: (valor) {
            if (valor == null) return;
            setState(() => _tipoSeleccionado = valor);
            widget.onTipoChanged(valor);
          },
        ),
      ],
    );
  }
}
