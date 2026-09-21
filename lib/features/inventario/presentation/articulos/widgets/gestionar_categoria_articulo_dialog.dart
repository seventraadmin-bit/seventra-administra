import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/inventario/data/tables/categoria_articulo_table.dart' show AplicacionEspecializadaCategoriaArticulo;
import 'package:riseg_one/features/inventario/domain/usecases/actualizar_categoria_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/archivar_categoria_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_categoria_articulo_usecase.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

import '../articulos_controller.dart';
import 'eliminar_categoria_articulo_fisicamente_dialog.dart';

/// Catálogo administrable de categorías de artículo (Etapa 7A) — solo
/// alta y archivado, mismo criterio simple que `CategoriasListScreen`
/// de Finanzas, pero como diálogo (Inventario no dedica una pestaña
/// propia a categorías).
class GestionarCategoriaArticuloDialog extends ConsumerStatefulWidget {
  const GestionarCategoriaArticuloDialog({super.key});

  @override
  ConsumerState<GestionarCategoriaArticuloDialog> createState() => _GestionarCategoriaArticuloDialogState();
}

class _GestionarCategoriaArticuloDialogState extends ConsumerState<GestionarCategoriaArticuloDialog> {
  final _nombreCtrl = TextEditingController();
  bool _guardando = false;

  String? _editandoId;
  final _editarNombreCtrl = TextEditingController();
  AplicacionEspecializadaCategoriaArticulo? _editarAplicacion;
  bool _editarGuardando = false;

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _editarNombreCtrl.dispose();
    super.dispose();
  }

  Future<void> _agregar() async {
    final l10n = AppLocalizations.of(context)!;
    if (_nombreCtrl.text.trim().isEmpty) {
      RisegFeedback.showError(context, l10n.categoriaArticuloErrorNombreRequerido);
      return;
    }
    setState(() => _guardando = true);
    final resultado = await ref.read(articulosControllerProvider.notifier).crearCategoria(_nombreCtrl.text.trim());
    if (!mounted) return;
    setState(() => _guardando = false);

    switch (resultado) {
      case CrearCategoriaArticuloExitoso():
        _nombreCtrl.clear();
      case CrearCategoriaArticuloNombreRequerido():
        RisegFeedback.showError(context, l10n.categoriaArticuloErrorNombreRequerido);
      case CrearCategoriaArticuloErrorInesperado():
        RisegFeedback.showError(context, l10n.categoriaArticuloErrorInesperado);
    }
  }

  Future<void> _archivar(String categoriaId) async {
    final l10n = AppLocalizations.of(context)!;
    final resultado = await ref.read(articulosControllerProvider.notifier).archivarCategoria(categoriaId);
    if (!mounted) return;

    switch (resultado) {
      case ArchivarCategoriaArticuloExitoso():
        break;
      case ArchivarCategoriaArticuloNoExiste():
      case ArchivarCategoriaArticuloErrorInesperado():
        RisegFeedback.showError(context, l10n.categoriaArticuloErrorInesperado);
    }
  }

  Future<void> _eliminarFisicamente(String categoriaId) async {
    final eliminado = await mostrarDialogoEliminarCategoriaArticuloFisicamente(context, ref, categoriaId);
    if (eliminado) ref.read(articulosControllerProvider.notifier).recargar();
  }

  void _iniciarEdicion(String categoriaId, String nombreActual, String? aplicacionActual) {
    setState(() {
      _editandoId = categoriaId;
      _editarNombreCtrl.text = nombreActual;
      _editarAplicacion = AplicacionEspecializadaCategoriaArticulo.values
          .where((v) => v.name == aplicacionActual)
          .firstOrNull;
    });
  }

  void _cancelarEdicion() {
    setState(() => _editandoId = null);
  }

  Future<void> _guardarEdicion(String categoriaId) async {
    final l10n = AppLocalizations.of(context)!;
    if (_editarNombreCtrl.text.trim().isEmpty) {
      RisegFeedback.showError(context, l10n.categoriaArticuloErrorNombreRequerido);
      return;
    }
    setState(() => _editarGuardando = true);
    final resultado = await ref.read(articulosControllerProvider.notifier).actualizarCategoria(
          categoriaId: categoriaId,
          nombre: _editarNombreCtrl.text.trim(),
          aplicacionEspecializada: _editarAplicacion,
          limpiarAplicacionEspecializada: _editarAplicacion == null,
        );
    if (!mounted) return;
    setState(() => _editarGuardando = false);

    switch (resultado) {
      case ActualizarCategoriaArticuloExitoso():
        setState(() => _editandoId = null);
      case ActualizarCategoriaArticuloNombreRequerido():
        RisegFeedback.showError(context, l10n.categoriaArticuloErrorNombreRequerido);
      case ActualizarCategoriaArticuloNoExiste():
      case ActualizarCategoriaArticuloErrorInesperado():
        RisegFeedback.showError(context, l10n.categoriaArticuloErrorInesperado);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final categorias = ref.watch(articulosControllerProvider).categorias;
    final esMaestro = ref.watch(sesionControllerProvider)?.esMaestro ?? false;

    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.categoriaArticuloDialogoTitulo, style: AppTypography.heading2.copyWith(color: colors.textPrimary)),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: RisegTextField(label: l10n.categoriaArticuloCampoNombre, controller: _nombreCtrl, autofocus: true),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  RisegButton(
                    label: l10n.categoriaArticuloBotonAgregar,
                    variant: RisegButtonVariant.secondary,
                    loading: _guardando,
                    onPressed: _agregar,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              if (categorias.isEmpty)
                Text(l10n.categoriaArticuloVacioMensaje, style: AppTypography.body.copyWith(color: colors.textMuted))
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final c in categorias)
                        if (_editandoId == c.id)
                          Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                RisegTextField(label: l10n.categoriaArticuloCampoNombre, controller: _editarNombreCtrl),
                                const SizedBox(height: AppSpacing.xs),
                                RisegSelect<AplicacionEspecializadaCategoriaArticulo?>(
                                  label: l10n.categoriaArticuloCampoAplicacionEspecializada,
                                  value: _editarAplicacion,
                                  items: [
                                    RisegSelectItem(value: null, label: l10n.categoriaArticuloAplicacionGenerica),
                                    RisegSelectItem(
                                      value: AplicacionEspecializadaCategoriaArticulo.telefonia,
                                      label: l10n.categoriaArticuloAplicacionTelefonia,
                                    ),
                                  ],
                                  onChanged: (v) => setState(() => _editarAplicacion = v),
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    RisegButton(
                                      label: l10n.categoriaArticuloBotonCancelar,
                                      variant: RisegButtonVariant.secondary,
                                      onPressed: _cancelarEdicion,
                                    ),
                                    const SizedBox(width: AppSpacing.sm),
                                    RisegButton(
                                      label: l10n.categoriaArticuloBotonGuardar,
                                      variant: RisegButtonVariant.primary,
                                      loading: _editarGuardando,
                                      onPressed: () => _guardarEdicion(c.id),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      Flexible(child: Text(c.nombre, overflow: TextOverflow.ellipsis)),
                                      if (c.aplicacionEspecializada == AplicacionEspecializadaCategoriaArticulo.telefonia.name) ...[
                                        const SizedBox(width: AppSpacing.xxs),
                                        Icon(Icons.phone_iphone, size: 14, color: colors.textMuted),
                                      ],
                                    ],
                                  ),
                                ),
                                // Etapa 18: mismo patrón de menú ⋯ que
                                // Categorías financieras — antes eran 3
                                // IconButton permanentes por fila.
                                RisegActionsMenu(
                                  menuKey: Key('categoria_articulo_menu_acciones_${c.id}'),
                                  actions: [
                                    RisegMenuAction(
                                      key: Key('categoria_articulo_accion_editar_${c.id}'),
                                      label: l10n.categoriaArticuloBotonEditar,
                                      icon: Icons.edit_outlined,
                                      onTap: () => _iniciarEdicion(c.id, c.nombre, c.aplicacionEspecializada),
                                    ),
                                    RisegMenuAction(
                                      key: Key('categoria_articulo_accion_archivar_${c.id}'),
                                      label: l10n.articuloBotonArchivar,
                                      icon: Icons.archive_outlined,
                                      onTap: () => _archivar(c.id),
                                    ),
                                    if (esMaestro)
                                      RisegMenuAction(
                                        key: Key('categoria_articulo_accion_eliminar_${c.id}'),
                                        label: l10n.eliminacionFisicaAccionMenu,
                                        icon: Icons.delete_forever_outlined,
                                        destructive: true,
                                        onTap: () => _eliminarFisicamente(c.id),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                    ],
                  ),
                ),
              const SizedBox(height: AppSpacing.lg),
              Align(
                alignment: Alignment.centerRight,
                child: RisegButton(
                  label: l10n.categoriaArticuloBotonCerrar,
                  variant: RisegButtonVariant.primary,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
