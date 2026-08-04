import 'package:flutter/material.dart';

import '../theme_context.dart';
import '../tokens/app_spacing.dart';
import '../tokens/app_typography.dart';

/// Agrupa campos relacionados dentro de un formulario, sin envolverlos en
/// una card — el formulario completo ya vive dentro de una superficie
/// (pantalla o diálogo); esto solo aporta estructura y espaciado.
class RisegFormSection extends StatelessWidget {
  const RisegFormSection({
    required this.title,
    required this.children,
    this.description,
    this.collapsible = false,
    this.initiallyExpanded = true,
    super.key,
  });

  final String title;
  final String? description;
  final List<Widget> children;
  final bool collapsible;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
        if (description != null) ...[
          const SizedBox(height: 2),
          Text(description!, style: AppTypography.caption.copyWith(color: colors.textMuted)),
        ],
      ],
    );

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final child in children) Padding(padding: const EdgeInsets.only(top: AppSpacing.md), child: child)],
    );

    if (!collapsible) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [header, body],
      );
    }

    // Se anula `dividerColor` localmente: `ExpansionTile` dibuja una
    // línea arriba/abajo al expandirse por defecto, y la Filosofía de
    // Diseño ya evita divisores pesados donde el espaciado alcanza.
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        iconColor: colors.textMuted,
        collapsedIconColor: colors.textMuted,
        title: header,
        children: [body],
      ),
    );
  }
}
