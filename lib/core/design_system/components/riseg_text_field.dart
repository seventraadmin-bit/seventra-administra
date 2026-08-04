import 'package:flutter/material.dart';

import '../theme_context.dart';
import '../tokens/app_spacing.dart';
import '../tokens/app_typography.dart';

/// Campo de texto de RISEG ONE.
///
/// Compone sobre `TextFormField` — bordes, color de foco y de error ya
/// están resueltos en `InputDecorationTheme`; este widget solo agrega la
/// etiqueta estática arriba del campo (en vez del label flotante de
/// Material) y una API reducida a lo que los formularios de RISEG
/// necesitan de verdad.
class RisegTextField extends StatelessWidget {
  const RisegTextField({
    required this.label,
    this.controller,
    this.hint,
    this.helperText,
    this.errorText,
    this.enabled = true,
    this.readOnly = false,
    this.prefixIcon,
    this.suffixAction,
    this.keyboardType,
    this.obscureText = false,
    this.onChanged,
    this.focusNode,
    this.autofocus = false,
    super.key,
  });

  final String label;
  final TextEditingController? controller;
  final String? hint;
  final String? helperText;

  /// No nulo activa el estado visual de error del borde/label, sin
  /// importar el resultado de ningún `Form` — el llamador decide cuándo
  /// mostrarlo.
  final String? errorText;
  final bool enabled;
  final bool readOnly;
  final IconData? prefixIcon;

  /// Acción al final del campo (ej. limpiar, mostrar contraseña) — un
  /// widget completo y no solo un ícono, para que el llamador controle su
  /// propio `onTap`/tooltip/estado.
  final Widget? suffixAction;
  final TextInputType? keyboardType;
  final bool obscureText;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: AppTypography.label.copyWith(color: colors.textMuted)),
        const SizedBox(height: AppSpacing.xxs),
        TextFormField(
          controller: controller,
          enabled: enabled,
          readOnly: readOnly,
          keyboardType: keyboardType,
          obscureText: obscureText,
          onChanged: onChanged,
          focusNode: focusNode,
          autofocus: autofocus,
          style: AppTypography.body.copyWith(color: colors.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            helperText: helperText,
            errorText: errorText,
            prefixIcon: prefixIcon == null ? null : Icon(prefixIcon, size: 20),
            suffixIcon: suffixAction,
          ),
        ),
      ],
    );
  }
}
