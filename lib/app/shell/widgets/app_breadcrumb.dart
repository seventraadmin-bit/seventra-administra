import 'package:flutter/material.dart';

/// Un segmento de breadcrumb. `onTap` es opcional — el último segmento
/// (la pantalla actual) normalmente no es interactivo.
@immutable
class BreadcrumbSegment {
  const BreadcrumbSegment({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;
}

/// Breadcrumb genérico del Shell.
///
/// Deliberadamente desconoce los 10 módulos actuales: solo renderiza la
/// lista de [segments] que reciba. Hoy quien lo llama arma un solo
/// segmento a partir del destino activo; más adelante, cuando existan
/// rutas anidadas, quien lo llame simplemente pasará más segmentos
/// (ej. "Organización" > "Clientes" > "Sportium") sin tocar este widget.
class AppBreadcrumb extends StatelessWidget {
  const AppBreadcrumb({required this.segments, this.activeColor, this.mutedColor, super.key});

  final List<BreadcrumbSegment> segments;

  /// Sobrescribe el color del último segmento (la pantalla actual).
  /// `null` conserva el color por defecto (`textTheme.titleMedium`, ya
  /// fijo en `textPrimary`) — Etapa 16: la barra superior azul institucional
  /// pasa aquí los tokens `shellForeground`/`shellForegroundMuted`, el
  /// único consumidor de este override hoy.
  final Color? activeColor;

  /// Sobrescribe el color de los segmentos intermedios y del separador
  /// `chevron_right`. `null` conserva `colorScheme.onSurfaceVariant`.
  final Color? mutedColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorMuted = mutedColor ?? theme.colorScheme.onSurfaceVariant;
    final children = <Widget>[];

    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      final isLast = i == segments.length - 1;
      final isInteractive = segment.onTap != null;

      final text = Text(
        segment.label,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
        style: isLast
            ? theme.textTheme.titleMedium?.copyWith(color: activeColor)
            : theme.textTheme.titleMedium?.copyWith(color: colorMuted),
      );

      // Un solo nivel (el caso de hoy: ningún segmento tiene `onTap`) no
      // debe sentirse como un control — sin InkWell ni el padding de
      // objetivo táctil que solo tiene sentido cuando algo es presionable.
      // Cuando existan rutas anidadas, los segmentos intermedios sí
      // llevarán `onTap` y recuperan la envoltura interactiva.
      final segmentWidget = isInteractive
          ? InkWell(
              onTap: segment.onTap,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: text,
              ),
            )
          : text;

      children.add(Flexible(child: segmentWidget));

      if (!isLast) {
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Icon(Icons.chevron_right, size: 18, color: colorMuted),
          ),
        );
      }
    }

    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }
}
