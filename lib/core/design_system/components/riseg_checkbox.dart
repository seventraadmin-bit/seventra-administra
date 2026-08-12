import 'package:flutter/material.dart';

import '../theme_context.dart';
import '../tokens/app_radius.dart';
import '../tokens/app_spacing.dart';
import '../tokens/app_typography.dart';

/// Casilla de verificación de RISEG ONE — primer control de este tipo
/// en el Design System (Etapa 15, "Recuérdame en este equipo"). Compone
/// sobre `Checkbox` de Material solo para el cuadro en sí; la etiqueta y
/// el área táctil (todo el renglón, no solo el cuadro) son propias.
class RisegCheckbox extends StatelessWidget {
  const RisegCheckbox({required this.label, required this.value, required this.onChanged, super.key});

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return InkWell(
      borderRadius: AppRadius.smRadius,
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Checkbox(
              value: value,
              onChanged: (v) => onChanged(v ?? false),
              activeColor: colors.accent,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: AppSpacing.xs),
            // `Expanded` (no `mainAxisSize.min`) a propósito: la
            // etiqueta debe poder ajustarse a dos líneas en un
            // contenedor angosto en vez de desbordar — mismo criterio
            // que el resto del Design System (ver el fix de
            // `RisegButton` en la misma etapa).
            Expanded(child: Text(label, style: AppTypography.body.copyWith(color: colors.textPrimary))),
          ],
        ),
      ),
    );
  }
}
