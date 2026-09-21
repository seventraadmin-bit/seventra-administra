import 'package:flutter/material.dart';

import '../theme_context.dart';
import '../tokens/app_color_scheme.dart';
import '../tokens/app_radius.dart';
import '../tokens/app_spacing.dart';
import '../tokens/app_typography.dart';
import 'riseg_status_badge.dart';

/// Una cubeta de antigüedad: su nombre, su importe y qué tan grave es.
class RisegAgingCubeta {
  const RisegAgingCubeta({required this.label, required this.valor, required this.tono, this.detalle});

  final String label;
  final int valor;

  /// Reutiliza el vocabulario de tono del Design System — `success`
  /// para lo corriente, `error` para lo más vencido. No se inventa una
  /// escala de color propia.
  final RisegStatusTone tono;

  /// Segunda línea opcional (ej. "3 documentos").
  final String? detalle;
}

/// Barras horizontales por cubeta de antigüedad — "¿qué tan vieja es
/// esta exposición?".
///
/// Horizontal y no vertical porque las etiquetas de cubeta son textos
/// ("31 a 60 días"), y en vertical habría que rotarlas o truncarlas. El
/// largo de cada barra es proporcional a la cubeta MAYOR, no al total:
/// lo que se compara aquí es una cubeta contra otra, y normalizar
/// contra el total aplastaría todas las barras cuando una domina.
class RisegAgingBars extends StatelessWidget {
  const RisegAgingBars({required this.cubetas, required this.formatoValor, super.key});

  final List<RisegAgingCubeta> cubetas;
  final String Function(int) formatoValor;

  /// Altura que necesitan [cubetas] barras, con o sin segunda línea de
  /// detalle. Misma razón que en `RisegCompositionChart.alturaPara`: el
  /// contenedor mide el contenido en vez de imponer un alto fijo.
  static double alturaPara(int cubetas, {bool conDetalle = true, double maximo = 260}) {
    if (cubetas <= 0) return 72;
    final alto = cubetas * (conDetalle ? 66.0 : 48.0);
    return alto.clamp(72.0, maximo);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (cubetas.isEmpty) return const SizedBox.shrink();

    final maximo = cubetas.fold<int>(0, (m, c) => c.valor > m ? c.valor : m);

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: cubetas.length,
      itemBuilder: (context, index) {
        final cubeta = cubetas[index];
        final fraccion = maximo <= 0 ? 0.0 : (cubeta.valor / maximo).clamp(0.0, 1.0);
        final color = _colorDeTono(colors, cubeta.tono);

        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      cubeta.label,
                      style: AppTypography.caption.copyWith(color: colors.textMuted),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(formatoValor(cubeta.valor), style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary)),
                ],
              ),
              const SizedBox(height: AppSpacing.xxs),
              ClipRRect(
                borderRadius: AppRadius.smRadius,
                child: Stack(
                  children: [
                    Container(height: 8, color: colors.surfaceSunken),
                    // `FractionallySizedBox` en vez de un ancho calculado:
                    // se adapta solo al ancho real de la tarjeta en cada
                    // breakpoint, sin medir nada.
                    FractionallySizedBox(
                      widthFactor: fraccion == 0 ? 0.0001 : fraccion,
                      child: Container(height: 8, color: color),
                    ),
                  ],
                ),
              ),
              if (cubeta.detalle != null) ...[
                const SizedBox(height: AppSpacing.xxs),
                Text(cubeta.detalle!, style: AppTypography.caption.copyWith(color: colors.textDisabled)),
              ],
            ],
          ),
        );
      },
    );
  }
}

Color _colorDeTono(AppColorScheme colors, RisegStatusTone tono) {
  return switch (tono) {
    RisegStatusTone.success => colors.success,
    RisegStatusTone.warning => colors.warning,
    RisegStatusTone.error => colors.error,
    RisegStatusTone.info => colors.info,
    RisegStatusTone.neutral => colors.neutralText,
  };
}
