import 'package:flutter/material.dart';

/// Sombras de RISEG ONE.
///
/// Deliberadamente solo dos niveles, y solo para capas que de verdad
/// flotan sobre el contenido (menús, popovers, diálogos). Cards, botones y
/// el Shell no usan sombra — usan borde. Es la señal visual más
/// reconocible de "Material sin personalizar" que la Filosofía de Diseño
/// pide evitar.
abstract final class AppShadows {
  static List<BoxShadow> popover(Brightness brightness) {
    final opacity = brightness == Brightness.dark ? 0.36 : 0.08;
    return [
      BoxShadow(color: Colors.black.withValues(alpha: opacity), blurRadius: 16, offset: const Offset(0, 4)),
    ];
  }

  static List<BoxShadow> dialog(Brightness brightness) {
    final opacity = brightness == Brightness.dark ? 0.48 : 0.14;
    return [
      BoxShadow(color: Colors.black.withValues(alpha: opacity), blurRadius: 32, offset: const Offset(0, 8)),
    ];
  }
}
