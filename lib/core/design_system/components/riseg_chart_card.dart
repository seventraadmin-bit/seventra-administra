import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme_context.dart';
import '../tokens/app_radius.dart';
import '../tokens/app_spacing.dart';
import '../tokens/app_typography.dart';
import 'riseg_card.dart';

/// Una entrada de leyenda: el color que identifica una serie y su
/// nombre.
class RisegChartLegendItem {
  const RisegChartLegendItem({required this.label, required this.color, this.linea = false});

  final String label;
  final Color color;

  /// `true` dibuja una línea en vez de un cuadro — para series que la
  /// gráfica pinta como trazo, no como barra.
  final bool linea;
}

/// Contenedor único de toda gráfica del sistema: título, pregunta que
/// responde, leyenda, altura y estado vacío.
///
/// Existe para que no haya cinco maneras distintas de enmarcar una
/// gráfica. La regla de producto que encapsula es que **cada gráfica
/// debe responder una pregunta concreta**: por eso [subtitle] no es
/// decorativo, es donde se escribe esa pregunta, y por eso el estado
/// vacío es parte del contenedor y no algo que cada pantalla resuelva
/// a su manera.
///
/// Un periodo sin datos no muestra una gráfica plana con ejes vacíos
/// —que se lee como un error—, sino un mensaje explícito.
class RisegChartCard extends StatelessWidget {
  const RisegChartCard({
    required this.title,
    required this.height,
    required this.child,
    this.subtitle,
    this.legend = const [],
    this.trailing,
    this.vacio = false,
    this.mensajeVacio,
    this.iconoVacio = Icons.insights_outlined,
    super.key,
  });

  final String title;

  /// La pregunta que la gráfica contesta, en una línea.
  final String? subtitle;

  final List<RisegChartLegendItem> legend;

  /// Acción o dato al extremo del encabezado (ej. el total del periodo).
  final Widget? trailing;

  final double height;
  final Widget child;

  final bool vacio;
  final String? mensajeVacio;
  final IconData iconoVacio;

  /// Alto mínimo del estado vacío.
  ///
  /// El alto normal de la tarjeta lo deriva el llamador de SU contenido
  /// (cuántas categorías, cuántas cubetas). Cuando no hay datos ese
  /// cálculo da lo mínimo —cero categorías— pero el mensaje de vacío
  /// sigue ocupando un ícono y dos o tres renglones de texto. Sin este
  /// piso, un panel sin datos desbordaba por abajo justo en los anchos
  /// donde el mensaje pasa a tres líneas (hallazgo real de este pase,
  /// visto a 700 px y a 1024 px).
  static const double alturaMinimaVacio = 124;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return RisegCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
                    if (subtitle != null) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(subtitle!, style: AppTypography.caption.copyWith(color: colors.textMuted)),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: AppSpacing.sm),
                // `Flexible` y no un ancho fijo: a 500 px el total del
                // periodo tiene que poder encogerse en vez de desbordar.
                Flexible(child: Align(alignment: Alignment.topRight, child: trailing)),
              ],
            ],
          ),
          if (legend.isNotEmpty && !vacio) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.xxs,
              children: [for (final item in legend) _Leyenda(item: item)],
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          if (vacio)
            SizedBox(
              height: math.max(height, alturaMinimaVacio),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(iconoVacio, size: 28, color: colors.textDisabled),
                    if (mensajeVacio != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                        child: Text(
                          mensajeVacio!,
                          textAlign: TextAlign.center,
                          // Tope duro: un mensaje largo en un panel
                          // angosto no puede empujar la tarjeta.
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.caption.copyWith(color: colors.textMuted),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            )
          else
            SizedBox(height: height, child: child),
        ],
      ),
    );
  }
}

class _Leyenda extends StatelessWidget {
  const _Leyenda({required this.item});

  final RisegChartLegendItem item;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (item.linea)
          Container(width: 12, height: 2, color: item.color)
        else
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: item.color, borderRadius: AppRadius.smRadius),
          ),
        const SizedBox(width: AppSpacing.xxs),
        Flexible(
          child: Text(
            item.label,
            style: AppTypography.caption.copyWith(color: context.colors.textMuted),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
