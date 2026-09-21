import 'package:flutter/material.dart';

import '../tokens/app_spacing.dart';

/// Rejilla de métricas con columnas reales — la respuesta al problema
/// que tenía Reportes: cada dato en una tarjeta de ancho completo,
/// metros de scroll y ninguna jerarquía.
///
/// Se diferencia de un `Wrap` suelto en dos cosas que importan:
///
///  1. **Todas las tarjetas de una fila miden lo mismo.** Un `Wrap` deja
///     que cada tarjeta tome su ancho intrínseco, así que la fila queda
///     dentada y la vista se lee como una lista, no como un tablero.
///  2. **El número de columnas se deriva del ancho disponible**, no de
///     un valor fijo — entre [minAnchoTarjeta] y [maxColumnas]. A 1536 px
///     caben cinco; a 500 px baja a una sola sin desbordar.
///
/// No dibuja nada: es puro layout. Las tarjetas siguen siendo
/// `RisegStatCard` — este componente no introduce una segunda tarjeta
/// de métrica al Design System.
class RisegKpiGrid extends StatelessWidget {
  const RisegKpiGrid({
    required this.children,
    this.minAnchoTarjeta = 210,
    this.maxColumnas = 5,
    this.espaciado = AppSpacing.md,
    super.key,
  });

  final List<Widget> children;

  /// Ancho mínimo legible de una tarjeta de métrica. Por debajo de esto
  /// el importe se trunca y el KPI deja de servir.
  final double minAnchoTarjeta;

  /// Tope duro de columnas. Más de cinco métricas en una fila dejan de
  /// leerse de un vistazo, que es justo para lo que existe la rejilla.
  final int maxColumnas;

  final double espaciado;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final ancho = constraints.maxWidth;
        // `isFinite`: dentro de un scroll horizontal el ancho puede ser
        // infinito; ahí una sola columna es lo único seguro.
        final cabenPorAncho = ancho.isFinite ? ((ancho + espaciado) / (minAnchoTarjeta + espaciado)).floor() : 1;
        final columnas = cabenPorAncho.clamp(1, maxColumnas).clamp(1, children.length);
        final anchoTarjeta = ancho.isFinite ? (ancho - espaciado * (columnas - 1)) / columnas : minAnchoTarjeta;

        return Wrap(
          spacing: espaciado,
          runSpacing: espaciado,
          children: [
            for (final child in children)
              SizedBox(
                // `- 0.01` evita que un redondeo de punto flotante haga
                // que la última tarjeta de la fila no quepa por una
                // fracción de píxel y salte de línea.
                width: (anchoTarjeta - 0.01).clamp(0.0, double.infinity),
                child: child,
              ),
          ],
        );
      },
    );
  }
}
