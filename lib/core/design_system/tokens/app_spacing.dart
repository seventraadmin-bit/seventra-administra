/// Escala de espaciado de RISEG ONE — base de 4px.
///
/// Ningún componente debe usar un número suelto para padding/gap/margen;
/// siempre uno de estos valores. Es "espacio como herramienta de
/// organización": un espacio mayor entre grupos que dentro de un grupo
/// comunica estructura sin necesitar líneas divisorias.
abstract final class AppSpacing {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 20.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const xxxl = 40.0;
  static const huge = 48.0;
  static const massive = 64.0;
}
