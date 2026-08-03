import 'package:flutter/material.dart';

/// Tema visual de RISEG ONE.
///
/// **PROVISIONAL.** Este `ThemeData` es neutral y funcional únicamente para
/// esta etapa de infraestructura. La paleta oficial de RISEG ONE (derivada
/// de la Filosofía de Diseño ya aprobada) se define en la fase de Design
/// System — no se debe tomar ningún color de aquí como definitivo.
abstract final class AppTheme {
  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blueGrey,
        brightness: Brightness.light,
      ),
    );
  }

  static ThemeData dark() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blueGrey,
        brightness: Brightness.dark,
      ),
    );
  }
}
