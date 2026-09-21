import 'package:flutter/material.dart';

import '../theme_context.dart';
import '../tokens/app_radius.dart';
import 'riseg_status_badge.dart';

/// Barra de progreso horizontal con significado semántico — mismo
/// vocabulario de tono que [RisegStatusBadge] (`RisegStatusTone`),
/// nunca un color hardcodeado. Pensada para "N de M cubierto" (Etapa
/// 15, Dashboard gerencial: cobertura operativa), pero genérica para
/// cualquier proporción 0–100%.
class RisegProgressBar extends StatelessWidget {
  const RisegProgressBar({required this.porcentaje, required this.tone, this.height = 8, super.key});

  /// 0–100. Valores fuera de rango se recortan (nunca desborda ni deja
  /// la barra vacía por error de cálculo del llamador).
  final double porcentaje;
  final RisegStatusTone tone;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fg = switch (tone) {
      RisegStatusTone.success => colors.success,
      RisegStatusTone.warning => colors.warning,
      RisegStatusTone.error => colors.error,
      RisegStatusTone.info => colors.info,
      RisegStatusTone.neutral => colors.neutralText,
    };
    final fraccion = (porcentaje / 100).clamp(0.0, 1.0);

    return Semantics(
      value: '${porcentaje.round()}%',
      child: ClipRRect(
        borderRadius: AppRadius.fullRadius,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              children: [
                Container(height: height, width: double.infinity, color: colors.surfaceSunken),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  height: height,
                  width: constraints.maxWidth * fraccion,
                  color: fg,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
