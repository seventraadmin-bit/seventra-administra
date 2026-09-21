import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Paleta categórica de gráficas — el color que distingue una categoría
/// de otra cuando ninguna de las dos tiene un significado semántico.
///
/// Se accede por tema, no por token semántico, porque los tokens
/// semánticos NO están pensados para distinguir: `accent` e `info` son
/// dos azules casi idénticos y usarlos juntos hacía indistinguibles dos
/// categorías de la misma composición.
///
/// Reglas de uso:
///
///  - **El rojo no está aquí.** Queda reservado para riesgo, vencido o
///    desfavorable. Una categoría neutra pintada de rojo se lee como
///    alarma.
///  - Cuando una categoría SÍ tiene significado (disponible, vencido,
///    a favor), se usa el token semántico correspondiente, no la
///    paleta.
///  - Es cíclica: con más categorías que colores se repite, lo cual es
///    preferible a generar tonos nuevos que dejen de contrastar.
extension RisegChartPalette on BuildContext {
  List<Color> get paletaCategorica =>
      Theme.of(this).brightness == Brightness.dark ? AppColors.categoricaDark : AppColors.categoricaLight;

  /// Color estable para la categoría [indice] (0-based).
  Color colorCategorico(int indice) {
    final paleta = paletaCategorica;
    return paleta[indice.abs() % paleta.length];
  }
}
