import 'package:flutter/widgets.dart';

/// Radios de esquina de RISEG ONE.
abstract final class AppRadius {
  static const double sm = 6; // badges, chips pequeños
  static const double md = 8; // botones, inputs, cards
  static const double lg = 12; // diálogos, cards grandes
  static const double full = 999; // píldoras, avatares

  static const BorderRadius smRadius = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdRadius = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgRadius = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius fullRadius = BorderRadius.all(Radius.circular(full));
}
