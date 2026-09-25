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
    required this.shellSurface,
    required this.shellForeground,
    required this.shellForegroundMuted,
    required this.shellOverlaySubtle,
    required this.shellOverlayStrong,
    required this.shellSearchBg,
    required this.shellSearchBorder,
    required this.shellFocusRing,
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

  /// ## Identidad del App Shell (Etapa 16, evolución visual)
  /// La barra superior es la única superficie de la app que se pinta con
  /// el azul institucional (`accent`) como FONDO — el resto de RISEG ONE
  /// usa azul solo como acento sobre superficies neutras. Estos 7 tokens
  /// son deliberadamente los MISMOS en claro/oscuro (igual que `accent`):
  /// la identidad de marca no debe cambiar con el tema del usuario.
  ///
  /// Texto/ícono principal sobre el azul institucional — blanco, mismo
  /// contraste ya validado para texto de botón sobre `accent` (5.51:1).
  /// Superficie del sidebar y del panel de identidad: tinta, en los dos
  /// temas. Es marca, no tema — el sidebar no se aclara en modo claro.
  final Color shellSurface;

  final Color shellForeground;

  /// Texto/ícono secundario sobre el azul institucional (ej. separador
  /// de breadcrumb, placeholder del buscador) — un blanco-azulado, nunca
  /// alpha sobre blanco puro: el contraste debe quedar fijo y predecible,
  /// no depender de qué tan saturado esté el azul de fondo.
  final Color shellForegroundMuted;

  /// Fondo hover de un ícono/botón que vive sobre la barra azul (tema,
  /// notificaciones, perfil) — velo blanco translúcido sutil, nunca un
  /// segundo azul.
  final Color shellOverlaySubtle;

  /// Igual que [shellOverlaySubtle] pero más marcado — presionado, o un
  /// ítem de menú activo (ej. el modo de tema vigente).
  final Color shellOverlayStrong;

  /// Relleno del buscador global sobre la barra azul — superficie
  /// translúcida derivada del propio azul (nunca vidrio/blur — solo un
  /// velo plano), para que siga leyéndose como parte de la barra y no
  /// como un campo blanco flotando encima.
  final Color shellSearchBg;

  /// Borde del buscador global sobre la barra azul.
  final Color shellSearchBorder;

  /// Anillo de foco de teclado para controles que viven sobre la barra
  /// azul — nunca [focusRing] (es del mismo azul institucional: sería
  /// invisible contra este fondo).
  final Color shellFocusRing;

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
      shellSurface: AppColors.tinta,
      shellForeground: AppColors.shellForeground,
      shellForegroundMuted: AppColors.shellForegroundMuted,
      shellOverlaySubtle: AppColors.shellOverlaySubtle,
      shellOverlayStrong: AppColors.shellOverlayStrong,
      shellSearchBg: AppColors.shellSearchBg,
      shellSearchBorder: AppColors.shellSearchBorder,
      shellFocusRing: AppColors.shellFocusRing,
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
      shellSurface: AppColors.tinta,
      shellForeground: AppColors.shellForeground,
      shellForegroundMuted: AppColors.shellForegroundMuted,
      shellOverlaySubtle: AppColors.shellOverlaySubtle,
      shellOverlayStrong: AppColors.shellOverlayStrong,
      shellSearchBg: AppColors.shellSearchBg,
      shellSearchBorder: AppColors.shellSearchBorder,
      shellFocusRing: AppColors.shellFocusRing,
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
    Color? shellSurface,
    Color? shellForeground,
    Color? shellForegroundMuted,
    Color? shellOverlaySubtle,
    Color? shellOverlayStrong,
    Color? shellSearchBg,
    Color? shellSearchBorder,
    Color? shellFocusRing,
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
      shellSurface: shellSurface ?? this.shellSurface,
      shellForeground: shellForeground ?? this.shellForeground,
      shellForegroundMuted: shellForegroundMuted ?? this.shellForegroundMuted,
      shellOverlaySubtle: shellOverlaySubtle ?? this.shellOverlaySubtle,
      shellOverlayStrong: shellOverlayStrong ?? this.shellOverlayStrong,
      shellSearchBg: shellSearchBg ?? this.shellSearchBg,
      shellSearchBorder: shellSearchBorder ?? this.shellSearchBorder,
      shellFocusRing: shellFocusRing ?? this.shellFocusRing,
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
      shellSurface: c(shellSurface, other.shellSurface),
      shellForeground: c(shellForeground, other.shellForeground),
      shellForegroundMuted: c(shellForegroundMuted, other.shellForegroundMuted),
      shellOverlaySubtle: c(shellOverlaySubtle, other.shellOverlaySubtle),
      shellOverlayStrong: c(shellOverlayStrong, other.shellOverlayStrong),
      shellSearchBg: c(shellSearchBg, other.shellSearchBg),
      shellSearchBorder: c(shellSearchBorder, other.shellSearchBorder),
      shellFocusRing: c(shellFocusRing, other.shellFocusRing),
    );
  }
}
