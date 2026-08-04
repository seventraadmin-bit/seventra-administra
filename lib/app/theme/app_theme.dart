import 'package:flutter/material.dart';

import '../../core/design_system/tokens/app_color_scheme.dart';
import '../../core/design_system/tokens/app_radius.dart';
import '../../core/design_system/tokens/app_sizes.dart';
import '../../core/design_system/tokens/app_typography.dart';

/// Tema visual definitivo de RISEG ONE — Etapa 3A.
///
/// Toda la paleta, tipografía y forma viven en
/// `lib/core/design_system/tokens/`; este archivo solo las ensambla en un
/// `ThemeData`. Ningún color se declara aquí directamente.
abstract final class AppTheme {
  static ThemeData light() => _build(AppColorScheme.light());

  static ThemeData dark() => _build(AppColorScheme.dark());

  static ThemeData _build(AppColorScheme colors) {
    final brightness = colors.canvas.computeLuminance() > 0.5 ? Brightness.light : Brightness.dark;
    final onAccent = Colors.white;

    final colorScheme = brightness == Brightness.light
        ? ColorScheme.light(
            primary: colors.accent,
            onPrimary: onAccent,
            primaryContainer: colors.accentSoftBg,
            onPrimaryContainer: colors.accentText,
            secondary: colors.accent,
            onSecondary: onAccent,
            error: colors.error,
            onError: onAccent,
            surface: colors.surface,
            onSurface: colors.textPrimary,
            onSurfaceVariant: colors.textMuted,
            outline: colors.borderInteractive,
            outlineVariant: colors.borderSubtle,
            surfaceContainerHighest: colors.surfaceSunken,
          )
        : ColorScheme.dark(
            primary: colors.accentText,
            onPrimary: colors.canvas,
            primaryContainer: colors.accentSoftBg,
            onPrimaryContainer: colors.accentText,
            secondary: colors.accentText,
            onSecondary: colors.canvas,
            error: colors.error,
            onError: colors.canvas,
            surface: colors.surface,
            onSurface: colors.textPrimary,
            onSurfaceVariant: colors.textMuted,
            outline: colors.borderInteractive,
            outlineVariant: colors.borderSubtle,
            surfaceContainerHighest: colors.surfaceSunken,
          );

    final textTheme = AppTypography.buildTextTheme(
      textPrimary: colors.textPrimary,
      textMuted: colors.textMuted,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: colors.canvas,
      colorScheme: colorScheme.copyWith(surfaceTint: Colors.transparent),
      extensions: [colors],
      fontFamily: AppTypography.fontFamily,
      textTheme: textTheme,
      dividerColor: colors.borderSubtle,
      dividerTheme: DividerThemeData(color: colors.borderSubtle, thickness: 1, space: 1),
      appBarTheme: AppBarTheme(
        surfaceTintColor: Colors.transparent,
        backgroundColor: colors.surface,
        foregroundColor: colors.textPrimary,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        surfaceTintColor: Colors.transparent,
        color: colors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.lgRadius,
          side: BorderSide(color: colors.borderSubtle),
        ),
      ),
      focusColor: colors.focusRing.withValues(alpha: 0.16),
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceSunken,
        hintStyle: TextStyle(color: colors.textMuted),
        labelStyle: TextStyle(color: colors.textMuted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: AppRadius.mdRadius,
          borderSide: BorderSide(color: colors.borderInteractive),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdRadius,
          borderSide: BorderSide(color: colors.borderInteractive),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdRadius,
          borderSide: BorderSide(color: colors.focusRing, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdRadius,
          borderSide: BorderSide(color: colors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdRadius,
          borderSide: BorderSide(color: colors.error, width: 2),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdRadius,
          borderSide: BorderSide(color: colors.borderSubtle),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.accent,
          foregroundColor: onAccent,
          disabledBackgroundColor: colors.borderSubtle,
          disabledForegroundColor: colors.textDisabled,
          minimumSize: const Size(64, AppSizes.controlMd),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdRadius),
          textStyle: AppTypography.bodyStrong,
        ).copyWith(
          side: _focusRingSide(colors),
          overlayColor: _focusOverlay(colors, onAccent),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.textPrimary,
          disabledForegroundColor: colors.textDisabled,
          side: BorderSide(color: colors.borderInteractive),
          minimumSize: const Size(64, AppSizes.controlMd),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdRadius),
          textStyle: AppTypography.bodyStrong,
        ).copyWith(
          side: _focusRingSide(colors, fallback: BorderSide(color: colors.borderInteractive)),
          overlayColor: _focusOverlay(colors, colors.textPrimary),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colors.accentText,
          disabledForegroundColor: colors.textDisabled,
          minimumSize: const Size(48, AppSizes.controlMd),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdRadius),
          textStyle: AppTypography.bodyStrong,
        ).copyWith(
          side: _focusRingSide(colors),
          overlayColor: _focusOverlay(colors, colors.accentText),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: colors.textMuted,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdRadius),
        ).copyWith(
          // `side` no se dibuja en el `IconButton()` estándar de Material 3
          // (solo en `IconButton.outlined`) — verificado en vivo: el
          // borde no aparecía. Se usa un tinte de acento en el estado de
          // foco en su lugar, distinto del gris de hover/press.
          overlayColor: _focusOverlay(colors, colors.textMuted),
        ),
      ),
      iconTheme: IconThemeData(color: colors.textMuted, size: AppSizes.iconDefault),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: colors.textPrimary, borderRadius: AppRadius.smRadius),
        textStyle: AppTypography.caption.copyWith(color: colors.surface),
      ),
    );
  }

  /// Anillo de foco de teclado — 2px, color de acento, siempre visible.
  ///
  /// Sin esto, el foco por Tab en botones e íconos de Flutter es
  /// prácticamente imperceptible por defecto (solo un tinte de fondo muy
  /// sutil) — no cumple "contraste visible y claro para foco de teclado".
  /// [fallback] permite conservar un borde no enfocado (ej. `OutlinedButton`)
  /// en vez de quitarlo cuando el control no tiene el foco.
  static WidgetStateProperty<BorderSide?> _focusRingSide(
    AppColorScheme colors, {
    BorderSide? fallback,
  }) {
    return WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.focused)) {
        return BorderSide(color: colors.focusRing, width: 2);
      }
      return fallback;
    });
  }

  /// Relleno de estado — el foco usa el color de acento (más fuerte y de
  /// tono distinto), para que Tab nunca se confunda visualmente con el
  /// gris neutro de hover/press. Necesario en `IconButton()` estándar,
  /// donde `side` no se dibuja (ver nota en `iconButtonTheme`).
  static WidgetStateProperty<Color?> _focusOverlay(AppColorScheme colors, Color base) {
    return WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.focused)) {
        return colors.focusRing.withValues(alpha: 0.28);
      }
      if (states.contains(WidgetState.pressed)) {
        return base.withValues(alpha: 0.12);
      }
      if (states.contains(WidgetState.hovered)) {
        return base.withValues(alpha: 0.08);
      }
      return null;
    });
  }
}
