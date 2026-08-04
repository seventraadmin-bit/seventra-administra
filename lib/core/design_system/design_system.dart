/// Punto de entrada único del Design System de RISEG ONE.
///
/// Los módulos importan este archivo (no los tokens sueltos) para tener
/// acceso a toda la identidad visual con un solo `import`.
library;

export 'tokens/app_breakpoints.dart';
export 'tokens/app_color_scheme.dart';
export 'tokens/app_colors.dart';
export 'tokens/app_durations.dart';
export 'tokens/app_radius.dart';
export 'tokens/app_shadows.dart';
export 'tokens/app_sizes.dart';
export 'tokens/app_spacing.dart';
export 'tokens/app_typography.dart';
export 'theme_context.dart';

// Los componentes base (RisegButton, RisegCard, ...) se agregan en la
// Etapa 3B, una vez aprobados los tokens.
