import 'package:flutter/material.dart';

import '../../../core/design_system/design_system.dart';

/// Envoltura común de cada sección del catálogo: título de subsección +
/// separación consistente, para que las secciones individuales solo
/// declaren contenido.
class CatalogSection extends StatelessWidget {
  const CatalogSection({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [for (final child in children) Padding(padding: const EdgeInsets.only(bottom: AppSpacing.xxl), child: child)],
    );
  }
}

/// Encabezado de subsección dentro de una [CatalogSection] (ej. "Variantes",
/// "Estados"). Deliberadamente más simple que [RisegSectionHeader] — es
/// meta-documentación del catálogo, no parte del Design System mismo.
class CatalogSubsection extends StatelessWidget {
  const CatalogSubsection({required this.title, required this.child, this.description, super.key});

  final String title;
  final String? description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
        if (description != null) ...[
          const SizedBox(height: 2),
          Text(description!, style: AppTypography.caption.copyWith(color: colors.textMuted)),
        ],
        const SizedBox(height: AppSpacing.md),
        child,
      ],
    );
  }
}
