import 'package:flutter/material.dart';

import '../theme_context.dart';
import '../tokens/app_radius.dart';
import '../tokens/app_spacing.dart';
import '../tokens/app_typography.dart';

/// Un componente de un total: cuánto aporta y con qué color se
/// identifica.
class RisegComposicionItem {
  const RisegComposicionItem({required this.label, required this.valor, required this.color});

  final String label;
  final int valor;
  final Color color;
}

/// "¿De qué se compone este total?" — barra apilada horizontal más una
/// leyenda con importe y porcentaje.
///
/// Es barra apilada y no dona a propósito: ocupa una fracción de la
/// altura, permite comparar segmentos pequeños (que en una dona son
/// rebanadas indistinguibles) y no necesita leyenda flotante para
/// entenderse. Una sola forma cubre composición del gasto, egresos por
/// origen, inventario por estado, motivos de baja y plantilla operativa
/// vs administrativa — en vez de cinco widgets casi iguales.
///
/// Los componentes negativos (un origen que en el periodo netea a favor
/// por cancelaciones) no se dibujan en la barra —una barra apilada no
/// puede representarlos sin mentir— pero **sí aparecen en la leyenda**
/// con su importe real. Ocultarlos haría que la suma de la leyenda no
/// cuadrara con el KPI.
class RisegCompositionChart extends StatelessWidget {
  const RisegCompositionChart({
    required this.items,
    required this.total,
    required this.formatoValor,
    this.altoBarra = 14,
    this.etiquetaSinPorcentaje,
    super.key,
  });

  final List<RisegComposicionItem> items;

  /// Total contra el que se calculan los porcentajes. Lo provee el
  /// llamador —y siempre es el mismo número que muestra el KPI— en vez
  /// de sumarlo aquí: así el porcentaje nunca se calcula contra un
  /// total distinto del que el usuario está viendo.
  final int total;

  final String Function(int) formatoValor;
  final double altoBarra;

  /// Texto a mostrar en lugar del porcentaje cuando [total] es cero.
  final String? etiquetaSinPorcentaje;

  /// Alto de un renglón de leyenda, incluida su separación.
  static const double altoRenglon = 24;

  /// Altura que este gráfico necesita para [items] categorías, sin
  /// sobrarle ni faltarle.
  ///
  /// Existe para que una composición de dos categorías no ocupe el
  /// mismo alto que una gráfica temporal: el contenedor pide esta
  /// medida en vez de un número fijo. El tope evita que una lista larga
  /// empuje el resto de la pantalla — a partir de ahí la leyenda
  /// desplaza dentro de su propia tarjeta.
  static double alturaPara(int items, {double altoBarra = 14, double maximo = 260}) {
    if (items <= 0) return 72;
    final alto = altoBarra + AppSpacing.sm + items * altoRenglon;
    return alto.clamp(72.0, maximo);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (items.isEmpty) return const SizedBox.shrink();

    final positivos = [for (final i in items) if (i.valor > 0) i];
    final sumaPositivos = positivos.fold<int>(0, (acc, i) => acc + i.valor);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (sumaPositivos > 0)
          ClipRRect(
            borderRadius: AppRadius.smRadius,
            child: SizedBox(
              height: altoBarra,
              child: Row(
                children: [
                  for (final item in positivos)
                    Expanded(
                      // Los `flex` son enteros: se escala a diezmilésimas
                      // para que un componente del 0.3 % siga teniendo un
                      // segmento visible en vez de colapsar a cero.
                      flex: ((item.valor / sumaPositivos) * 10000).round().clamp(1, 10000),
                      child: Tooltip(
                        message: '${item.label}: ${formatoValor(item.valor)}',
                        child: ColoredBox(color: item.color, child: const SizedBox.expand()),
                      ),
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final porcentaje = total == 0 ? null : (item.valor / total) * 100;
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: item.color, borderRadius: AppRadius.smRadius),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        item.label,
                        style: AppTypography.caption.copyWith(color: colors.textPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      formatoValor(item.valor),
                      style: AppTypography.caption.copyWith(color: colors.textPrimary),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    SizedBox(
                      width: 46,
                      child: Text(
                        porcentaje == null
                            ? (etiquetaSinPorcentaje ?? '')
                            : '${porcentaje.toStringAsFixed(porcentaje.abs() < 10 ? 1 : 0)} %',
                        textAlign: TextAlign.right,
                        style: AppTypography.caption.copyWith(color: colors.textMuted),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
