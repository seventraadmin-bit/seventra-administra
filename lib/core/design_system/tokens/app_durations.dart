import 'package:flutter/animation.dart';

/// Duraciones y curvas de animación de RISEG ONE.
///
/// Cortas y sin rebote a propósito ("rapidez sin prisa" de la Filosofía de
/// Diseño): confirman que algo respondió, nunca hacen esperar al usuario
/// ni llaman la atención sobre sí mismas.
abstract final class AppDurations {
  static const fast = Duration(milliseconds: 100); // hover, press
  static const base = Duration(milliseconds: 180); // colapsos, expansiones
  static const slow = Duration(milliseconds: 240); // diálogos, overlays

  static const enterCurve = Curves.easeOut;
  static const exitCurve = Curves.easeIn;
}
