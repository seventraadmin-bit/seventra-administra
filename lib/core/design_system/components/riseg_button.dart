import 'package:flutter/material.dart';

import '../theme_context.dart';
import '../tokens/app_color_scheme.dart';
import '../tokens/app_sizes.dart';
import '../tokens/app_spacing.dart';

/// Variante visual de [RisegButton].
enum RisegButtonVariant { primary, secondary, ghost, danger }

/// Tamaño de [RisegButton]. `compact` es para acciones dentro de tablas o
/// barras, no para el flujo principal de un formulario.
enum RisegButtonSize { standard, compact }

/// Botón de acción de RISEG ONE.
///
/// Compone directamente sobre `ElevatedButton`/`OutlinedButton`/`TextButton`
/// — su estilo (relleno, borde, foco de teclado, estados hover/press/
/// disabled) ya está resuelto en `AppTheme`; este widget solo decide qué
/// Material subyacente usar y agrega el estado `loading`, que Material no
/// tiene de forma nativa.
class RisegButton extends StatelessWidget {
  const RisegButton({
    required this.label,
    required this.onPressed,
    this.variant = RisegButtonVariant.primary,
    this.size = RisegButtonSize.standard,
    this.icon,
    this.loading = false,
    super.key,
  });

  final String label;

  /// `null` deshabilita el botón permanentemente (distinto de [loading],
  /// que lo deshabilita temporalmente sin oscurecer su color).
  final VoidCallback? onPressed;
  final RisegButtonVariant variant;
  final RisegButtonSize size;
  final IconData? icon;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final height = size == RisegButtonSize.compact ? AppSizes.controlSm : AppSizes.controlMd;
    final minWidth = size == RisegButtonSize.compact ? 56.0 : 64.0;

    // Deshabilitado "de verdad" (onPressed nulo) atenúa el color, como
    // cualquier control inactivo. Deshabilitado por `loading` NO debe
    // atenuarse — el usuario ya inició la acción, oscurecerlo leería como
    // un error, no como progreso — por eso los dos casos usan colores
    // `disabled*` distintos más abajo.
    final trulyDisabled = onPressed == null && !loading;
    final effectiveOnPressed = (onPressed == null || loading) ? null : onPressed;

    final foreground = _foregroundColor(colors);
    final content = _RisegButtonContent(label: label, icon: icon, loading: loading, spinnerColor: foreground);

    switch (variant) {
      case RisegButtonVariant.primary:
        return ElevatedButton(
          onPressed: effectiveOnPressed,
          style: ElevatedButton.styleFrom(
            minimumSize: Size(minWidth, height),
            disabledBackgroundColor: trulyDisabled ? colors.borderSubtle : colors.accent,
            disabledForegroundColor: trulyDisabled ? colors.textDisabled : Colors.white,
          ),
          child: content,
        );
      case RisegButtonVariant.secondary:
        return OutlinedButton(
          onPressed: effectiveOnPressed,
          style: OutlinedButton.styleFrom(
            minimumSize: Size(minWidth, height),
            disabledForegroundColor: trulyDisabled ? colors.textDisabled : colors.textPrimary,
          ).copyWith(
            // Reemplaza `side` por completo, así que replicamos aquí el
            // anillo de foco de `AppTheme._focusRingSide` en vez de perderlo
            // — un `BorderSide` plano borraría el foco de teclado.
            side: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.focused)) {
                return BorderSide(color: colors.focusRing, width: 2);
              }
              if (states.contains(WidgetState.disabled)) {
                return BorderSide(color: trulyDisabled ? colors.borderSubtle : colors.borderInteractive);
              }
              return BorderSide(color: colors.borderInteractive);
            }),
          ),
          child: content,
        );
      case RisegButtonVariant.ghost:
        return TextButton(
          onPressed: effectiveOnPressed,
          style: TextButton.styleFrom(
            minimumSize: Size(minWidth, height),
            disabledForegroundColor: trulyDisabled ? colors.textDisabled : colors.accentText,
          ),
          child: content,
        );
      case RisegButtonVariant.danger:
        return ElevatedButton(
          onPressed: effectiveOnPressed,
          style: ElevatedButton.styleFrom(
            minimumSize: Size(minWidth, height),
            backgroundColor: colors.error,
            foregroundColor: Colors.white,
            disabledBackgroundColor: trulyDisabled ? colors.borderSubtle : colors.error,
            disabledForegroundColor: trulyDisabled ? colors.textDisabled : Colors.white,
          ),
          child: content,
        );
    }
  }

  Color _foregroundColor(AppColorScheme colors) {
    switch (variant) {
      case RisegButtonVariant.primary:
      case RisegButtonVariant.danger:
        return Colors.white;
      case RisegButtonVariant.secondary:
        return colors.textPrimary;
      case RisegButtonVariant.ghost:
        return colors.accentText;
    }
  }
}

class _RisegButtonContent extends StatelessWidget {
  const _RisegButtonContent({
    required this.label,
    required this.icon,
    required this.loading,
    required this.spinnerColor,
  });

  final String label;
  final IconData? icon;
  final bool loading;
  final Color spinnerColor;

  @override
  Widget build(BuildContext context) {
    final leading = loading
        ? SizedBox(
            width: AppSizes.iconSm,
            height: AppSizes.iconSm,
            child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(spinnerColor)),
          )
        : (icon != null ? Icon(icon, size: AppSizes.iconSm) : null);

    if (leading == null) return Text(label);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        leading,
        const SizedBox(width: AppSpacing.xs),
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}
