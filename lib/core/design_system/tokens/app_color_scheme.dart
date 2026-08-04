import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Tokens de color con significado semántico — la única forma en que un
/// componente Riseg debe leer color.
///
/// Se consume vía `Theme.of(context).extension<AppColorScheme>()!`, nunca
/// leyendo [AppColors] directamente. Ver `context.colors` en
/// `design_system.dart` para el atajo de acceso.
///
/// ## Por qué neutros cálidos frente a un azul frío
/// Es la misma pareja de contraste que RISEG ya usa en su propio material
/// de negocio serio (fondo cálido/blanco + azul de confianza) — le da al
/// sistema personalidad propia sin necesitar azul en todas partes.
///
/// ## Por qué `accent` y `accentText` son valores distintos
/// `accent` (`#2E6DA0`) es el relleno de botón — funciona igual en ambos
/// temas porque el texto blanco encima siempre tiene contraste suficiente
/// (5.51:1). Pero ese mismo azul, usado como *texto* directamente sobre el
/// fondo oscuro, cae a 3.10:1 — no pasa AA. Por eso `accentText` en oscuro
/// usa un azul más claro (`#7FB3E0`, 7.66:1) reservado para texto/íconos
/// sin superficie de botón detrás.
///
/// ## Por qué hay dos tokens de borde
/// `borderSubtle` es decorativo (divisores entre secciones) y no necesita
/// cumplir el contraste no-textual de WCAG (1.35:1 en claro, 1.47:1 en
/// oscuro — aceptable porque no identifica un componente interactivo).
/// `borderInteractive` es el borde de inputs/botones — estos sí deben
/// distinguirse del fondo (≥3:1) para que alguien identifique dónde puede
/// interactuar; por eso son colores más oscuros/saturados que el divisor.
@immutable
class AppColorScheme extends ThemeExtension<AppColorScheme> {
  const AppColorScheme({
    required this.canvas,
    required this.surface,
    required this.surfaceSunken,
    required this.borderSubtle,
    required this.borderInteractive,
    required this.textPrimary,
    required this.textMuted,
    required this.textDisabled,
    required this.accent,
    required this.accentHover,
    required this.accentPressed,
    required this.accentText,
    required this.accentSoftBg,
    required this.focusRing,
    required this.info,
    required this.infoBg,
    required this.success,
    required this.successBg,
    required this.warning,
    required this.warningBg,
    required this.error,
    required this.errorBg,
    required this.neutralText,
    required this.neutralBg,
  });

  /// Fondo de página.
  final Color canvas;

  /// Superficie elevada (cards, sidebar, top bar, diálogos).
  final Color surface;

  /// Superficie hundida (fondo de inputs, franja de tabla).
  final Color surfaceSunken;

  /// Divisor decorativo — no requiere contraste no-textual.
  final Color borderSubtle;

  /// Borde de componentes interactivos (inputs, botones outline) — cumple
  /// contraste no-textual ≥3:1.
  final Color borderInteractive;

  final Color textPrimary;
  final Color textMuted;

  /// Deliberadamente por debajo de AA — WCAG exime el texto de componentes
  /// deshabilitados, y un contraste demasiado alto haría que "deshabilitado"
  /// se confundiera visualmente con "habilitado".
  final Color textDisabled;

  /// Relleno de botón primario — igual en ambos temas.
  final Color accent;
  final Color accentHover;
  final Color accentPressed;

  /// Texto/ícono de acento sin superficie de botón detrás (ver nota de
  /// clase: distinto de [accent] por contraste, no por gusto).
  final Color accentText;

  /// Fondo suave para ítems seleccionados/badges de marca.
  final Color accentSoftBg;

  /// Color del anillo de foco de teclado.
  final Color focusRing;

  final Color info;
  final Color infoBg;
  final Color success;
  final Color successBg;
  final Color warning;
  final Color warningBg;
  final Color error;
  final Color errorBg;

  /// Badge de estado neutral/inactivo (ej. borrador, sin asignar).
  final Color neutralText;
  final Color neutralBg;

  factory AppColorScheme.light() {
    return const AppColorScheme(
      canvas: AppColors.neutral0,
      surface: Colors.white,
      surfaceSunken: AppColors.neutral50,
      borderSubtle: AppColors.neutral200,
      borderInteractive: AppColors.neutral500,
      textPrimary: AppColors.neutral900,
      textMuted: AppColors.neutral600,
      textDisabled: AppColors.neutral500,
      accent: AppColors.accent500,
      accentHover: AppColors.accent600,
      accentPressed: AppColors.accent700,
      accentText: AppColors.accent600,
      accentSoftBg: AppColors.accentSoftBgLight,
      focusRing: AppColors.accent500,
      info: AppColors.infoTextLight,
      infoBg: AppColors.infoBgLight,
      success: AppColors.successTextLight,
      successBg: AppColors.successBgLight,
      warning: AppColors.warningTextLight,
      warningBg: AppColors.warningBgLight,
      error: AppColors.errorTextLight,
      errorBg: AppColors.errorBgLight,
      neutralText: AppColors.neutral600,
      neutralBg: AppColors.neutral100,
    );
  }

  factory AppColorScheme.dark() {
    return const AppColorScheme(
      canvas: AppColors.darkCanvas,
      surface: AppColors.darkSurface,
      surfaceSunken: AppColors.darkSurfaceSunken,
      borderSubtle: AppColors.darkBorderSubtle,
      borderInteractive: AppColors.darkBorderInteractive,
      textPrimary: AppColors.darkTextPrimary,
      textMuted: AppColors.darkTextMuted,
      textDisabled: AppColors.darkTextDisabled,
      accent: AppColors.accent500,
      accentHover: AppColors.accentTextDark,
      accentPressed: AppColors.accentTextDark,
      accentText: AppColors.accentTextDark,
      accentSoftBg: AppColors.accentSoftBgDark,
      focusRing: AppColors.accentTextDark,
      info: AppColors.infoTextDark,
      infoBg: AppColors.infoBgDark,
      success: AppColors.successTextDark,
      successBg: AppColors.successBgDark,
      warning: AppColors.warningTextDark,
      warningBg: AppColors.warningBgDark,
      error: AppColors.errorTextDark,
      errorBg: AppColors.errorBgDark,
      neutralText: AppColors.darkTextMuted,
      neutralBg: AppColors.darkSurfaceSunken,
    );
  }

  @override
  AppColorScheme copyWith({
    Color? canvas,
    Color? surface,
    Color? surfaceSunken,
    Color? borderSubtle,
    Color? borderInteractive,
    Color? textPrimary,
    Color? textMuted,
    Color? textDisabled,
    Color? accent,
    Color? accentHover,
    Color? accentPressed,
    Color? accentText,
    Color? accentSoftBg,
    Color? focusRing,
    Color? info,
    Color? infoBg,
    Color? success,
    Color? successBg,
    Color? warning,
    Color? warningBg,
    Color? error,
    Color? errorBg,
    Color? neutralText,
    Color? neutralBg,
  }) {
    return AppColorScheme(
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      surfaceSunken: surfaceSunken ?? this.surfaceSunken,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      borderInteractive: borderInteractive ?? this.borderInteractive,
      textPrimary: textPrimary ?? this.textPrimary,
      textMuted: textMuted ?? this.textMuted,
      textDisabled: textDisabled ?? this.textDisabled,
      accent: accent ?? this.accent,
      accentHover: accentHover ?? this.accentHover,
      accentPressed: accentPressed ?? this.accentPressed,
      accentText: accentText ?? this.accentText,
      accentSoftBg: accentSoftBg ?? this.accentSoftBg,
      focusRing: focusRing ?? this.focusRing,
      info: info ?? this.info,
      infoBg: infoBg ?? this.infoBg,
      success: success ?? this.success,
      successBg: successBg ?? this.successBg,
      warning: warning ?? this.warning,
      warningBg: warningBg ?? this.warningBg,
      error: error ?? this.error,
      errorBg: errorBg ?? this.errorBg,
      neutralText: neutralText ?? this.neutralText,
      neutralBg: neutralBg ?? this.neutralBg,
    );
  }

  @override
  AppColorScheme lerp(ThemeExtension<AppColorScheme>? other, double t) {
    if (other is! AppColorScheme) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColorScheme(
      canvas: c(canvas, other.canvas),
      surface: c(surface, other.surface),
      surfaceSunken: c(surfaceSunken, other.surfaceSunken),
      borderSubtle: c(borderSubtle, other.borderSubtle),
      borderInteractive: c(borderInteractive, other.borderInteractive),
      textPrimary: c(textPrimary, other.textPrimary),
      textMuted: c(textMuted, other.textMuted),
      textDisabled: c(textDisabled, other.textDisabled),
      accent: c(accent, other.accent),
      accentHover: c(accentHover, other.accentHover),
      accentPressed: c(accentPressed, other.accentPressed),
      accentText: c(accentText, other.accentText),
      accentSoftBg: c(accentSoftBg, other.accentSoftBg),
      focusRing: c(focusRing, other.focusRing),
      info: c(info, other.info),
      infoBg: c(infoBg, other.infoBg),
      success: c(success, other.success),
      successBg: c(successBg, other.successBg),
      warning: c(warning, other.warning),
      warningBg: c(warningBg, other.warningBg),
      error: c(error, other.error),
      errorBg: c(errorBg, other.errorBg),
      neutralText: c(neutralText, other.neutralText),
      neutralBg: c(neutralBg, other.neutralBg),
    );
  }
}
