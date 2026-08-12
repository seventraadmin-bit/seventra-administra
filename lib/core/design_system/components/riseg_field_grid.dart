import 'package:flutter/material.dart';

import '../tokens/app_breakpoints.dart';
import '../tokens/app_spacing.dart';

/// Distribuye `children` en un grid responsive de campos — pensado para
/// secciones tipo "Datos generales"/"Dirección" (campos de una sola
/// línea, uno por celda), no para listas/repetidores.
///
/// Columnas según el ancho disponible, reutilizando `AppBreakpoints`
/// (nunca un tercer umbral inventado):
/// - `>= AppBreakpoints.medium` (1000): 3 columnas
/// - `>= AppBreakpoints.compact` (600): 2 columnas
/// - si no: 1 columna (mismo `Column` vertical de siempre)
///
/// Se usa `Wrap` con celdas de ancho fijo en vez de `GridView` porque
/// los hijos no comparten una misma altura (un campo con texto de
/// error es más alto que uno sin error) — `GridView` exige una razón
/// de aspecto fija y produciría recortes o huecos.
class RisegFieldGrid extends StatelessWidget {
  const RisegFieldGrid({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columnas = _columnas(constraints.maxWidth);

        if (columnas == 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [for (final child in children) Padding(padding: const EdgeInsets.only(top: AppSpacing.md), child: child)],
          );
        }

        final anchoCelda = (constraints.maxWidth - AppSpacing.md * (columnas - 1)) / columnas;
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [for (final child in children) SizedBox(width: anchoCelda, child: child)],
        );
      },
    );
  }

  static int _columnas(double ancho) {
    if (ancho >= AppBreakpoints.medium) return 3;
    if (ancho >= AppBreakpoints.compact) return 2;
    return 1;
  }
}
