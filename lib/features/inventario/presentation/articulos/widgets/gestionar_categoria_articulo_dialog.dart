import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/inventario/domain/usecases/archivar_categoria_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_categoria_articulo_usecase.dart';

import '../articulos_controller.dart';

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

  @override
  void dispose() {
    _nombreCtrl.dispose();
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final categorias = ref.watch(articulosControllerProvider).categorias;

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
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                          child: Row(
                            children: [
                              Expanded(child: Text(c.nombre)),
                              IconButton(
                                tooltip: l10n.articuloBotonArchivar,
                                icon: const Icon(Icons.archive_outlined, size: 18),
                                visualDensity: VisualDensity.compact,
                                onPressed: () => _archivar(c.id),
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
