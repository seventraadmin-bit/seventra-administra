import 'package:flutter/widgets.dart';

/// Rampas de color crudas de RISEG ONE.
///
/// **Nunca se usan directamente en pantallas ni componentes.** Son la única
/// fuente de valores hexadecimales del sistema — [AppColorScheme] les da
/// significado semántico (texto, fondo, borde, estado). Un componente que
/// necesite un color siempre pasa por `context.colors`, jamás por
/// `AppColors` ni por un `Color(0x...)` suelto.
///
/// Neutros deliberadamente cálidos (no grises azulados) — ver
/// `AppColorScheme` para la justificación completa y las verificaciones de
/// contraste WCAG de cada combinación real.
abstract final class AppColors {
  // Neutros — claro
  static const neutral0 = Color(0xFFFAF9F7);
  static const neutral50 = Color(0xFFF5F3F0);
  static const neutral100 = Color(0xFFECE9E5);
  static const neutral200 = Color(0xFFDDD8D2);
  static const neutral500 = Color(0xFF8A8074);
  static const neutral600 = Color(0xFF6B6156);
  static const neutral700 = Color(0xFF4F473F);
  static const neutral900 = Color(0xFF221E1A); // carbón institucional (claro)

  // Neutros — oscuro (carbón elegante, calidez mínima — no sepia)
  static const darkCanvas = Color(0xFF1C1C1A);
  static const darkSurface = Color(0xFF242421);
  static const darkSurfaceSunken = Color(0xFF2C2B27);
  static const darkBorderSubtle = Color(0xFF3A3934);
  static const darkBorderInteractive = Color(0xFF726B5F);
  static const darkTextPrimary = Color(0xFFF0EEEA);
  static const darkTextMuted = Color(0xFFA8A29A);
  static const darkTextDisabled = Color(0xFF6B655D);

  // Azul corporativo unificado
  static const accent500 = Color(0xFF2E6DA0); // relleno de botón (ambos temas)
  static const accent600 = Color(0xFF24587F); // texto/enlace sobre claro, hover
  static const accent700 = Color(0xFF1B4363); // presionado
  static const accentSoftBgLight = Color(0xFFEAF1F8);
  static const accentTextDark = Color(0xFF7FB3E0); // texto/ícono sobre oscuro
  static const accentSoftBgDark = Color(0xFF1E2E3E);

  // Semánticos — claro
  static const infoBgLight = Color(0xFFE8F1FB);
  static const infoTextLight = Color(0xFF1E5C96);
  static const successBgLight = Color(0xFFE9F5EE);
  static const successTextLight = Color(0xFF2F7A52);
  static const warningBgLight = Color(0xFFFBF2E1);
  static const warningTextLight = Color(0xFF8A5A12);
  static const errorBgLight = Color(0xFFFBEAEA);
  static const errorTextLight = Color(0xFFA23B3B);

  // Semánticos — oscuro
  static const infoBgDark = Color(0xFF1B2A3A);
  static const infoTextDark = Color(0xFF8FC1EC);
  static const successBgDark = Color(0xFF1B2E22);
  static const successTextDark = Color(0xFF86C79E);
  static const warningBgDark = Color(0xFF332A15);
  static const warningTextDark = Color(0xFFE0AE5C);
  static const errorBgDark = Color(0xFF33201F);
  static const errorTextDark = Color(0xFFE2918F);

  // Identidad del App Shell (Etapa 16) — mismos valores en ambos temas,
  // ver el doc comment de `AppColorScheme` para la justificación.
  // --- Paleta categórica de gráficas ---
  //
  // Existe porque los tokens semánticos NO sirven para distinguir
  // categorías: `accent` (#2E6DA0) e `info` (#1E5C96) son prácticamente
  // el mismo azul, y usarlos juntos dejaba "Renuncia" e "Inasistencias"
  // pintadas igual en una composición 50/50.
  //
  // Criterios: azul corporativo primero (es la identidad), después
  // matices sobrios y bien separados entre sí. **El rojo no está en la
  // rotación**: queda reservado para riesgo/desfavorable, y usarlo como
  // "categoría 5" haría que un dato neutro se leyera como alarma. El
  // verde va deliberadamente tarde en el orden, para que una
  // composición de dos categorías (motivos de baja, por ejemplo) no
  // pinte una de ellas de verde "aprobatorio".
  static const categoricaLight = <Color>[
    Color(0xFF2E6DA0), // azul corporativo
    Color(0xFFB07A1E), // ámbar
    Color(0xFF2E7D82), // teal
    Color(0xFF6B6156), // gris cálido
    Color(0xFF7A5C8A), // ciruela
    Color(0xFF2F7A52), // verde
    Color(0xFF4F473F), // carbón
    Color(0xFF8C4A3F), // terracota — 8a categoría (Telefonía)
    Color(0xFF6E7B2E), // oliva — 9a categoría (Servicios Eventuales)
  ];

  /// Mismos matices, aclarados para leerse sobre el lienzo oscuro.
  static const categoricaDark = <Color>[
    Color(0xFF7FB3E0), // azul corporativo
    Color(0xFFE0AE5C), // ámbar
    Color(0xFF7CC4C9), // teal
    Color(0xFFA8A29A), // gris cálido
    Color(0xFFBFA0CC), // ciruela
    Color(0xFF86C79E), // verde
    Color(0xFFCFC7BC), // arena
    Color(0xFFD79A8E), // terracota clara — 8a categoría (Telefonía)
    Color(0xFFBCC77A), // oliva clara — 9a categoría (Servicios Eventuales)
  ];

  static const shellForeground = Color(0xFFFFFFFF);
  static const shellForegroundMuted = Color(0xFFD7E4EF); // blanco-azulado, contraste fijo
  static const shellOverlaySubtle = Color(0x1FFFFFFF); // blanco @ ~12%
  static const shellOverlayStrong = Color(0x33FFFFFF); // blanco @ ~20%
  static const shellSearchBg = Color(0x24FFFFFF); // blanco @ ~14%
  static const shellSearchBorder = Color(0x47FFFFFF); // blanco @ ~28%
  static const shellFocusRing = Color(0xFFFFFFFF);
}
