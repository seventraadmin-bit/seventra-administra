import 'package:flutter/material.dart';

import '../theme_context.dart';
import '../tokens/app_radius.dart';
import '../tokens/app_sizes.dart';
import '../tokens/app_spacing.dart';
import '../tokens/app_typography.dart';

/// Significado semántico de un [RisegStatusBadge] — nunca un color suelto.
enum RisegStatusTone { success, warning, error, info, neutral }

/// Insignia de estado (activo, vencido, suspendido, ...).
///
/// Combina color, texto y (opcionalmente) ícono deliberadamente — nunca
/// debe depender solo del color para comunicar el estado.
class RisegStatusBadge extends StatelessWidget {
  const RisegStatusBadge({
    required this.label,
    required this.tone,
    this.icon,
    super.key,
  });

  final String label;
  final RisegStatusTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (fg, bg) = switch (tone) {
      RisegStatusTone.success => (colors.success, colors.successBg),
      RisegStatusTone.warning => (colors.warning, colors.warningBg),
      RisegStatusTone.error => (colors.error, colors.errorBg),
      RisegStatusTone.info => (colors.info, colors.infoBg),
      RisegStatusTone.neutral => (colors.neutralText, colors.neutralBg),
    };

    return Semantics(
      label: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
        decoration: BoxDecoration(color: bg, borderRadius: AppRadius.fullRadius),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: AppSizes.iconSm, color: fg),
              const SizedBox(width: AppSpacing.xxs),
            ],
            // `Flexible` + `ellipsis` — sin esto, una columna de tabla
            // angosta (ej. 130px en `RisegTableBase`) con una etiqueta
            // larga ("Registrado") producía "BOTTOM OVERFLOWED" (Etapa
            // 15, hallazgo real en Egresos). Sin efecto visual cuando
            // hay espacio suficiente: `mainAxisSize.min` sigue
            // ajustándose al contenido.
            Flexible(
              child: Text(label, style: AppTypography.label.copyWith(color: fg), overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}
