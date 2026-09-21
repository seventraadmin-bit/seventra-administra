import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

/// --- Alturas de panel ---
///
/// Una gráfica temporal necesita altura para que la escala signifique
/// algo; una composición de dos categorías no. Forzar la misma altura a
/// las dos dejaba la mitad de la tarjeta vacía, que es justo lo que
/// hacía ver Reportes como una lista de huecos.
///
/// Cada panel declara la altura que necesita y la fila se queda con la
/// mayor: así el alto se adapta al contenido **sin** perder la
/// alineación entre paneles vecinos, que es lo que hace que una fila se
/// lea como una unidad.

/// Serie temporal: necesita rango vertical para que las barras se
/// comparen entre sí.
const double alturaSerieTemporal = 200;

/// Barras sobre pocas categorías fijas (altas/reingresos/bajas): no
/// gana nada con más alto.
const double alturaBarrasCategoricas = 150;

/// Un bloque de una sola cifra grande con su nota.
const double alturaCifraDestacada = 110;

/// Altura de un panel hecho de [renglones] de [RenglonHecho].
double alturaRenglonesHecho(int renglones) => renglones <= 0 ? 72 : (renglones * 24.0).clamp(72.0, 260.0);

/// Altura de un panel hecho de [datos] de [DatoCompacto].
double alturaDatosCompactos(int datos) => datos <= 0 ? 72 : (datos * 42.0).clamp(72.0, 260.0);

/// La altura que comparten todos los paneles de una misma fila: la
/// mayor de las que cada uno pidió.
double alturaDeFila(List<double> alturas) => alturas.isEmpty ? 72 : alturas.reduce(math.max);


/// Un panel dentro de una fila analítica, con su peso relativo.
class PanelAnalitico {
  const PanelAnalitico({required this.child, this.flex = 1, this.minAncho = 320});

  final Widget child;

  /// Cuánto espacio toma frente a sus vecinos cuando caben lado a lado.
  final int flex;

  /// Por debajo de este ancho el panel deja de ser legible y la fila se
  /// apila.
  final double minAncho;
}

/// Fila de paneles que se apila cuando deja de caber.
///
/// Es el reemplazo de la tarjeta de ancho completo por dato: arriba de
/// cierto ancho dos o tres paneles conviven en la misma línea —que es
/// lo que da densidad sin saturar—, y por debajo se apilan en el orden
/// declarado, sin desbordar ni encoger el contenido hasta hacerlo
/// ilegible.
///
/// El umbral no es un breakpoint fijo: se deriva de la suma de los
/// `minAncho` que declara cada panel, porque una fila de dos gráficas
/// necesita más aire que una de dos listas.
class FilaPaneles extends StatelessWidget {
  const FilaPaneles({required this.paneles, this.espaciado = AppSpacing.md, super.key});

  final List<PanelAnalitico> paneles;
  final double espaciado;

  @override
  Widget build(BuildContext context) {
    if (paneles.isEmpty) return const SizedBox.shrink();
    if (paneles.length == 1) return paneles.single.child;

    final minTotal = paneles.fold<double>(0, (a, p) => a + p.minAncho) + espaciado * (paneles.length - 1);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.maxWidth.isFinite || constraints.maxWidth < minTotal) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < paneles.length; i++) ...[
                if (i > 0) SizedBox(height: espaciado),
                paneles[i].child,
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < paneles.length; i++) ...[
              if (i > 0) SizedBox(width: espaciado),
              Expanded(flex: paneles[i].flex, child: paneles[i].child),
            ],
          ],
        );
      },
    );
  }
}

/// Renglón de una lista compacta de hechos — el "foco de atención" o el
/// dato informativo que no merece una tarjeta propia.
class RenglonHecho extends StatelessWidget {
  const RenglonHecho({required this.texto, required this.tono, this.icono, super.key});

  final String texto;
  final RisegStatusTone tono;
  final IconData? icono;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = switch (tono) {
      RisegStatusTone.success => colors.success,
      RisegStatusTone.warning => colors.warning,
      RisegStatusTone.error => colors.error,
      RisegStatusTone.info => colors.info,
      RisegStatusTone.neutral => colors.neutralText,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono ?? Icons.circle, size: icono == null ? 8 : AppSizes.iconSm, color: color),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(texto, style: AppTypography.caption.copyWith(color: colors.textPrimary)),
          ),
        ],
      ),
    );
  }
}

/// Par etiqueta/valor compacto — sustituye a una `RisegStatCard` de
/// ancho completo cuando el dato es informativo y no merece jerarquía
/// de KPI.
class DatoCompacto extends StatelessWidget {
  const DatoCompacto({required this.etiqueta, required this.valor, this.nota, super.key});

  final String etiqueta;
  final String valor;
  final String? nota;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(etiqueta, style: AppTypography.caption.copyWith(color: colors.textMuted)),
                if (nota != null)
                  Text(nota!, style: AppTypography.caption.copyWith(color: colors.textDisabled, fontSize: 10)),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(valor, style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary)),
        ],
      ),
    );
  }
}
