import 'package:flutter/material.dart';

import 'tokens/app_color_scheme.dart';

/// Atajo de acceso a los tokens de color: `context.colors.textMuted`, etc.
extension AppThemeContext on BuildContext {
  AppColorScheme get colors => Theme.of(this).extension<AppColorScheme>()!;
}
