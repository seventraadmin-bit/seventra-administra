import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import '../busqueda_controller.dart';
import 'global_search_dialog.dart';
import 'global_search_results_list.dart';

const _grupoAncla = 'global_search_tap_region';

/// Campo de Búsqueda global de la barra superior (Etapa 14A) —
/// reemplaza el `RisegSearchField` decorativo. Ancla un overlay de
/// resultados debajo del campo (`CompositedTransformTarget`/
/// `OverlayPortal`) mientras hay foco y al menos 2 caracteres; en modo
/// compacto (ventana angosta, sin espacio para el campo) el ícono abre
/// `GlobalSearchDialog` en su lugar.
class GlobalSearchField extends ConsumerStatefulWidget {
  const GlobalSearchField({required this.compact, super.key});

  final bool compact;

  @override
  ConsumerState<GlobalSearchField> createState() => _GlobalSearchFieldState();
}

class _GlobalSearchFieldState extends ConsumerState<GlobalSearchField> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _layerLink = LayerLink();
  final _overlayController = OverlayPortalController();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _seleccionar(String ruta) {
    _overlayController.hide();
    _controller.clear();
    _focusNode.unfocus();
    ref.read(busquedaControllerProvider.notifier).limpiar();
    context.go(ruta);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (widget.compact) {
      return IconButton(
        key: const Key('top_bar_search'),
        tooltip: l10n.shellSearchTooltip,
        icon: const Icon(Icons.search),
        onPressed: () => showDialog<void>(context: context, builder: (_) => const GlobalSearchDialog()),
      );
    }

    ref.listen(busquedaControllerProvider, (previous, next) {
      final debeMostrarse = next.texto.trim().length >= 2;
      if (debeMostrarse && !_overlayController.isShowing) {
        _overlayController.show();
      } else if (!debeMostrarse && _overlayController.isShowing) {
        _overlayController.hide();
      }
    });

    final colors = context.colors;
    final border = OutlineInputBorder(borderRadius: AppRadius.mdRadius, borderSide: BorderSide(color: colors.borderSubtle));

    return TapRegion(
      groupId: _grupoAncla,
      onTapOutside: (_) => _overlayController.hide(),
      child: CompositedTransformTarget(
        link: _layerLink,
        child: OverlayPortal(
          controller: _overlayController,
          overlayChildBuilder: (context) => CompositedTransformFollower(
            link: _layerLink,
            targetAnchor: Alignment.bottomLeft,
            followerAnchor: Alignment.topLeft,
            offset: const Offset(0, 4),
            child: TapRegion(
              groupId: _grupoAncla,
              child: Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 4,
                  borderRadius: AppRadius.mdRadius,
                  color: colors.surface,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 300, maxWidth: 320),
                    child: GlobalSearchResultsList(onSelect: _seleccionar),
                  ),
                ),
              ),
            ),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300, minWidth: 160),
            child: SizedBox(
              height: 36,
              child: TextField(
                key: const Key('top_bar_search'),
                controller: _controller,
                focusNode: _focusNode,
                style: AppTypography.body.copyWith(color: colors.textMuted),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 18, color: colors.textMuted),
                  prefixIconConstraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                  contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  hintText: l10n.shellSearchTooltip,
                  hintStyle: AppTypography.body.copyWith(color: colors.textMuted),
                  filled: false,
                  border: border,
                  enabledBorder: border,
                ),
                onChanged: (texto) => ref.read(busquedaControllerProvider.notifier).actualizarTexto(texto),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
