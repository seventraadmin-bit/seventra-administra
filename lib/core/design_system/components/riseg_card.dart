import 'package:flutter/material.dart';

import '../theme_context.dart';
import '../tokens/app_radius.dart';
import '../tokens/app_spacing.dart';

/// Variante estructural de [RisegCard].
enum RisegCardVariant {
  /// Superficie elevada con borde sutil — el caso general.
  standard,

  /// Fondo hundido sin borde, para agrupar contenido secundario dentro de
  /// otra superficie (ej. una card dentro de otra sección).
  subtle,

  /// Como [standard], pero reacciona a hover/foco/tap. Solo tiene sentido
  /// junto con [RisegCard.onTap].
  interactive,
}

/// Superficie estructural de RISEG ONE — agrupa contenido relacionado, no
/// es una tarjeta decorativa. Sin sombra pesada: la separación es por
/// borde y color de superficie, como el resto del Shell.
class RisegCard extends StatefulWidget {
  const RisegCard({
    required this.child,
    this.variant = RisegCardVariant.standard,
    this.onTap,
    this.padding,
    super.key,
  });

  final Widget child;
  final RisegCardVariant variant;

  /// Solo tiene efecto cuando `variant == interactive`.
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;

  @override
  State<RisegCard> createState() => _RisegCardState();
}

class _RisegCardState extends State<RisegCard> {
  final _focusNode = FocusNode();
  bool _focused = false;
  bool _hovered = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final padding = widget.padding ?? const EdgeInsets.all(AppSpacing.md);

    if (widget.variant == RisegCardVariant.subtle) {
      return Container(
        padding: padding,
        decoration: BoxDecoration(color: colors.surfaceSunken, borderRadius: AppRadius.lgRadius),
        child: widget.child,
      );
    }

    if (widget.variant == RisegCardVariant.standard) {
      return Container(
        padding: padding,
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: AppRadius.lgRadius,
          border: Border.all(color: colors.borderSubtle),
        ),
        child: widget.child,
      );
    }

    // interactive: mismo aspecto que `standard` en reposo, más hover y un
    // anillo de foco pintado a mano — igual al patrón ya usado en
    // `_SidebarItem`, porque `Card`/`Container` no traen esos estados.
    // `InkWell` (no un `GestureDetector` a mano) porque ya activa con
    // Enter/Espacio al enfocarse por teclado, no solo con mouse; se
    // desactivan sus propios overlays porque el color ya lo controla el
    // `Container` de abajo según `_hovered`/`_focused`.
    final borderColor = _focused ? colors.focusRing : colors.borderSubtle;
    final borderWidth = _focused ? 2.0 : 1.0;
    final backgroundColor = _hovered ? colors.surfaceSunken : colors.surface;

    return Semantics(
      button: true,
      child: InkWell(
        focusNode: _focusNode,
        onFocusChange: (value) => setState(() => _focused = value),
        onHover: (value) => setState(() => _hovered = value),
        onTap: widget.onTap,
        borderRadius: AppRadius.lgRadius,
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: AppRadius.lgRadius,
            border: Border.all(color: borderColor, width: borderWidth),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
