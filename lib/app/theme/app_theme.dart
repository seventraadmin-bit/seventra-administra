import 'package:flutter/material.dart';

/// Tema visual de RISEG ONE.
///
/// **PROVISIONAL.** Este `ThemeData` es neutral y funcional únicamente para
/// esta etapa de infraestructura. La paleta oficial de RISEG ONE (derivada
/// de la Filosofía de Diseño ya aprobada) se define en la fase de Design
/// System — no se debe tomar ningún color de aquí como definitivo.
abstract final class AppTheme {
  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: Colors.blueGrey,
      brightness: Brightness.light,
    ).copyWith(surfaceTint: Colors.transparent);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      appBarTheme: const AppBarTheme(surfaceTintColor: Colors.transparent),
      cardTheme: const CardThemeData(surfaceTintColor: Colors.transparent),
    );
  }

  static ThemeData dark() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: Colors.blueGrey,
      brightness: Brightness.dark,
    ).copyWith(surfaceTint: Colors.transparent);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      appBarTheme: const AppBarTheme(surfaceTintColor: Colors.transparent),
      cardTheme: const CardThemeData(surfaceTintColor: Colors.transparent),
    );
  }
}
