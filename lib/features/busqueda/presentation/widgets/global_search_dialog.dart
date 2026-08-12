import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import '../busqueda_controller.dart';
import 'global_search_results_list.dart';

/// Variante de Búsqueda global para ventanas angostas (Etapa 14A) —
/// donde el campo de la barra superior colapsa a un ícono, sin espacio
/// para anclar un overlay. Reutiliza `GlobalSearchResultsList`, la
/// misma pieza que ya usa el overlay normal — sin duplicar el
/// renderizado de resultados.
class GlobalSearchDialog extends ConsumerStatefulWidget {
  const GlobalSearchDialog({super.key});

  @override
  ConsumerState<GlobalSearchDialog> createState() => _GlobalSearchDialogState();
}

class _GlobalSearchDialogState extends ConsumerState<GlobalSearchDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _seleccionar(String ruta) {
    ref.read(busquedaControllerProvider.notifier).limpiar();
    Navigator.of(context).pop();
    context.go(ruta);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 80),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const Key('global_search_dialog_field'),
                controller: _controller,
                autofocus: true,
                style: AppTypography.body.copyWith(color: colors.textMuted),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 18, color: colors.textMuted),
                  hintText: l10n.shellSearchTooltip,
                ),
                onChanged: (texto) => ref.read(busquedaControllerProvider.notifier).actualizarTexto(texto),
              ),
              const SizedBox(height: AppSpacing.sm),
              GlobalSearchResultsList(onSelect: _seleccionar),
            ],
          ),
        ),
      ),
    );
  }
}
