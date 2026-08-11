import 'package:flutter/material.dart';

import '../theme_context.dart';
import '../tokens/app_spacing.dart';
import '../tokens/app_typography.dart';

/// Encabezado de una sección de formulario, listado o expediente.
///
/// Responsive por construcción (Etapa 9D, corrección de overflow en
/// componente compartido — auditado contra sus 41 usos reales antes de
/// cambiarlo): con ancho suficiente, título a la izquierda y acciones
/// a la derecha, en una sola línea — igual que siempre. Con ancho
/// reducido, el grupo de acciones completo (nunca un botón suelto,
/// nunca truncado ni escondido) baja a una segunda línea propia; si ni
/// así cupieran todas las acciones en una sola línea, se reparten en
/// más líneas dentro de ese mismo grupo. Un título excepcionalmente
/// largo se envuelve en varias líneas antes de robarle espacio a las
/// acciones, nunca al revés. Mismo cuidado que ya resolvió el
/// desbordamiento del breadcrumb en la Etapa 2, generalizado aquí con
/// `Wrap` en vez de `Row`+`Expanded` (que solo podía encoger el
/// título, nunca las acciones — la causa real del desbordamiento que
/// esto reemplaza).
class RisegSectionHeader extends StatelessWidget {
  const RisegSectionHeader({
    required this.title,
    this.description,
    this.primaryAction,
    this.secondaryAction,
    super.key,
  });

  final String title;
  final String? description;

  /// Un [RisegButton] suelto o un grupo (ej. `Wrap` de varios) — ambos
  /// casos ya conviven hoy en el proyecto; el llamador decide.
  final Widget? primaryAction;
  final Widget? secondaryAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasActions = primaryAction != null || secondaryAction != null;

    final titleColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: AppTypography.heading2.copyWith(color: colors.textPrimary)),
        if (description != null) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(description!, style: AppTypography.body.copyWith(color: colors.textMuted)),
        ],
      ],
    );

    if (!hasActions) return titleColumn;

    // Grupo de acciones como una sola unidad `Wrap`: si `secondaryAction`
    // ya es en sí mismo un grupo de varios botones (ej. Archivar +
    // Eliminar físicamente), sigue pudiendo reacomodarse internamente
    // sin que este nivel tenga que saber nada de eso.
    final actionsGroup = Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        if (secondaryAction != null) secondaryAction!,
        if (primaryAction != null) primaryAction!,
      ],
    );

    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.start,
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.sm,
      children: [titleColumn, actionsGroup],
    );
  }
}
