import 'package:flutter/material.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

/// Gráfica de barras verticales "Bajas por mes" (Etapa 15) — sin
/// librería de gráficas externa (el proyecto no tiene ninguna, ver
/// investigación previa): barras dibujadas con `Container` simples,
/// mismo criterio visual discreto del resto del Design System.
class GraficaBarrasVerticales extends StatelessWidget {
  const GraficaBarrasVerticales({required this.datos, this.altura = 96, super.key});

  /// `(etiqueta, valor, detalleTooltip)` — un elemento por barra.
  final List<(String etiqueta, int valor, String detalleTooltip)> datos;

  /// Alto máximo reservado SOLO para la barra — las etiquetas de encima
  /// y debajo se dimensionan solas, nunca dentro de este presupuesto.
  final double altura;

  /// Ancho natural de cada barra (Etapa 15) — fijo, nunca `Expanded`: con
  /// pocos meses en el rango (ej. una sola baja en "Este mes"), una barra
  /// `Expanded` se estira a ocupar el 100% del ancho de la tarjeta,
  /// exactamente la sensación de "barra gigantesca" que Marlon señaló.
  /// Con ancho fijo, la fila se centra y solo crece hacia scroll
  /// horizontal si de verdad no cabe (hasta 12 meses en "Este año").
  static const _anchoBarra = 44.0;

  /// Piso de escala (Etapa 15): con muy pocos datos (ej. 1 baja), el
  /// máximo real de la serie es 1, así que esa única barra llegaría al
  /// 100% del alto — se ve "gigante" aunque el valor sea pequeño. Un
  /// piso de referencia evita esa distorsión sin inventar ningún
  /// indicador nuevo: es una escala visual, no una métrica.
  static const _pisoEscala = 5;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final maximoReal = datos.fold<int>(0, (m, d) => d.$2 > m ? d.$2 : m);
    final maximo = maximoReal < _pisoEscala ? _pisoEscala : maximoReal;

    final barras = [
      for (final dato in datos)
        SizedBox(
          width: _anchoBarra,
          child: Tooltip(
            message: dato.$3,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${dato.$2}', style: AppTypography.caption.copyWith(color: colors.textMuted)),
                const SizedBox(height: AppSpacing.xxs),
                // Causa real del "BOTTOM OVERFLOWED BY 12 PIXELS" (Etapa
                // 15): el contenedor exterior reservaba un presupuesto
                // fijo de `altura + 32` para el contenido completo (barra
                // + 2 líneas de texto + 2 separadores), pero el alto real
                // de esas 2 líneas de `caption` (12.5px, line-height 1.4)
                // más los separadores suma ~43px, no 32. Corrección de
                // raíz: el presupuesto fijo (`altura`) se aplica
                // ÚNICAMENTE al contenedor de la barra; el resto de la
                // columna se dimensiona a su contenido real.
                SizedBox(
                  height: altura,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      height: dato.$2 == 0 ? 2 : (dato.$2 / maximo) * altura,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: colors.accent,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(dato.$1, style: AppTypography.caption.copyWith(color: colors.textMuted)),
              ],
            ),
          ),
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final row = Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [for (final barra in barras) Padding(padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs), child: barra)],
        );
        final anchoNatural = datos.length * (_anchoBarra + AppSpacing.xxs * 2);
        if (anchoNatural <= constraints.maxWidth) return Center(child: row);
        return SingleChildScrollView(scrollDirection: Axis.horizontal, child: row);
      },
    );
  }
}

/// Barra horizontal proporcional con etiqueta + cantidad + porcentaje
/// (Etapa 15) — usada por "Motivos de baja", "Permanencia" y
/// "Servicios con mayor rotación".
class BarraHorizontalConteo extends StatelessWidget {
  const BarraHorizontalConteo({
    required this.etiqueta,
    required this.cantidad,
    required this.porcentaje,
    this.tone = RisegStatusTone.info,
    super.key,
  });

  final String etiqueta;
  final int cantidad;
  final double porcentaje;
  final RisegStatusTone tone;

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

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        children: [
          SizedBox(width: 170, child: Text(etiqueta, style: AppTypography.body.copyWith(color: colors.textPrimary))),
          Expanded(
            child: ClipRRect(
              borderRadius: AppRadius.fullRadius,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    children: [
                      Container(height: 8, width: double.infinity, color: colors.surfaceSunken),
                      Container(height: 8, width: constraints.maxWidth * (porcentaje / 100).clamp(0.0, 1.0), color: fg),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 90,
            child: Text('$cantidad · ${porcentaje.round()}%', textAlign: TextAlign.right, style: AppTypography.caption.copyWith(color: colors.textMuted)),
          ),
        ],
      ),
    );
  }
}
