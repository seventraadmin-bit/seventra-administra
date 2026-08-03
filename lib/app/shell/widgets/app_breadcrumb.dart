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
  const AppBreadcrumb({required this.segments, super.key});

  final List<BreadcrumbSegment> segments;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final children = <Widget>[];

    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      final isLast = i == segments.length - 1;

      children.add(
        // Flexible (no solo `overflow: ellipsis` en el Text) es lo que de
        // verdad evita el desborde: sin él, un Row de tamaño mínimo se
        // sigue midiendo por el contenido natural del texto y desborda en
        // vez de encogerse cuando el espacio disponible es menor.
        Flexible(
          child: InkWell(
            onTap: segment.onTap,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                segment.label,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: isLast
                    ? theme.textTheme.titleMedium
                    : theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ),
        ),
      );

      if (!isLast) {
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Icon(Icons.chevron_right, size: 18, color: theme.colorScheme.onSurfaceVariant),
          ),
        );
      }
    }

    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }
}
