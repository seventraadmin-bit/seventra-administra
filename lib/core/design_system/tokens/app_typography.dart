import 'package:flutter/material.dart';

/// Tipografía definitiva de RISEG ONE: Segoe UI.
///
/// Nativa de Windows — no se distribuyen archivos de fuente en el
/// repositorio, cero riesgo de licenciamiento, refuerza la sensación de
/// aplicación de escritorio. Para folios/fechas/montos se usa la misma
/// Segoe UI con [dataFeatures] (cifras tabulares) en vez de una fuente
/// monoespaciada aparte — solo se incorporará una si un caso real lo exige.
abstract final class AppTypography {
  static const fontFamily = 'Segoe UI';

  static const List<FontFeature> dataFeatures = [FontFeature.tabularFigures()];

  static const heading1 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 26,
    fontWeight: FontWeight.w700,
    height: 1.25,
    letterSpacing: -0.2,
  );

  static const heading2 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  static const heading3 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.35,
  );

  static const body = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  static const bodyStrong = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.5,
  );

  static const caption = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12.5,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );

  /// Para etiquetas de campo y encabezados de tabla — se espera usar en
  /// mayúsculas desde el widget que la consuma (esta clase no transforma
  /// texto).
  static const label = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.4,
    height: 1.3,
  );

  /// Códigos (`EMP-000001`), fechas, montos — cifras tabulares para que
  /// alineen en columna.
  static const data = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.4,
    fontFeatures: dataFeatures,
  );

  /// Construye el `TextTheme` de Material a partir de la escala anterior,
  /// para que los widgets estándar (AppBar, botones, etc.) hereden la
  /// misma tipografía sin que cada Riseg component tenga que fijarla a
  /// mano.
  static TextTheme buildTextTheme({
    required Color textPrimary,
    required Color textMuted,
  }) {
    TextStyle c(TextStyle style, Color color) => style.copyWith(color: color);

    return TextTheme(
      headlineSmall: c(heading1, textPrimary),
      titleLarge: c(heading2, textPrimary),
      titleMedium: c(heading3, textPrimary),
      bodyMedium: c(body, textPrimary),
      bodyLarge: c(bodyStrong, textPrimary),
      bodySmall: c(caption, textMuted),
      labelLarge: c(label, textMuted),
    );
  }
}
