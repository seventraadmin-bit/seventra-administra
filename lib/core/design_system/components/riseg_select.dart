import 'package:flutter/material.dart';

import '../theme_context.dart';
import '../tokens/app_spacing.dart';
import '../tokens/app_typography.dart';

/// Una opción seleccionable de [RisegSelect].
class RisegSelectItem<T> {
  const RisegSelectItem({required this.value, required this.label});

  final T value;
  final String label;
}

/// Selector oficial de RISEG ONE — reemplaza cualquier necesidad futura de
/// un dropdown hand-rolled.
///
/// Compone sobre `DropdownButtonFormField<T>` para heredar automáticamente
/// el mismo `InputDecorationTheme` (bordes, color de foco, de error) que ya
/// usa `RisegTextField`, con la misma etiqueta estática arriba del campo en
/// vez del label flotante de Material — misma API reducida que
/// `RisegTextField` (label/errorText/enabled), para que ambos se sientan
/// como el mismo sistema.
class RisegSelect<T> extends StatelessWidget {
  const RisegSelect({
    required this.label,
    required this.items,
    required this.value,
    required this.onChanged,
    this.hint,
    this.helperText,
    this.errorText,
    this.enabled = true,
    super.key,
  });

  final String label;
  final List<RisegSelectItem<T>> items;
  final T? value;

  /// `null` cuando [enabled] es `false` deshabilita el control — mismo
  /// convenio que el resto del Design System (ver `RisegButton.onPressed`).
  final ValueChanged<T?>? onChanged;
  final String? hint;
  final String? helperText;
  final String? errorText;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: AppTypography.label.copyWith(color: colors.textMuted)),
        const SizedBox(height: AppSpacing.xxs),
        DropdownButtonFormField<T>(
          value: value,
          isExpanded: true,
          style: AppTypography.body.copyWith(color: colors.textPrimary),
          decoration: InputDecoration(hintText: hint, helperText: helperText, errorText: errorText),
          items: [
            for (final item in items) DropdownMenuItem(value: item.value, child: Text(item.label)),
          ],
          onChanged: enabled ? onChanged : null,
        ),
      ],
    );
  }
}
