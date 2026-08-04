/// Breakpoints de propósito general para formularios y contenido.
///
/// **No confundir con `ShellBreakpoints`** (`lib/app/shell/shell_breakpoints.dart`):
/// - `ShellBreakpoints` es exclusivo de decisiones del cascarón — cuándo el
///   sidebar se colapsa, cuándo el Top Bar reduce la búsqueda/perfil. Nadie
///   fuera del Shell debería leerlo.
/// - `AppBreakpoints` es para todo lo demás: formularios que pasan de dos
///   columnas a una, contenido que se reorganiza dentro del área de
///   trabajo, etc. — lo usan los módulos (Organización y los que sigan).
///
/// Son dos sistemas con responsabilidades distintas, no dos intentos de
/// resolver lo mismo. Si en el futuro la evidencia real muestra que deberían
/// converger, se unifican entonces — no de forma preventiva.
abstract final class AppBreakpoints {
  /// Una sola columna, controles apilados.
  static const double compact = 600;

  /// Layout intermedio — ej. formulario de 2 columnas empieza a apretarse.
  static const double medium = 1000;

  // Por encima de `medium` se considera "expanded": espacio completo.
}
