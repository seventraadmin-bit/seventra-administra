import 'package:flutter/material.dart';

import '../theme_context.dart';
import '../tokens/app_color_scheme.dart';
import '../tokens/app_radius.dart';
import '../tokens/app_spacing.dart';
import '../tokens/app_typography.dart';

/// Una serie de barras: su nombre, su color y un valor por categoría.
///
/// [valores] debe tener exactamente la misma longitud que las etiquetas
/// del eje — la gráfica no rellena huecos por su cuenta, porque una
/// serie más corta casi siempre significa que el llamador perdió datos
/// en el camino, no que quiera un hueco.
class RisegBarSeries {
  const RisegBarSeries({required this.label, required this.color, required this.valores});

  final String label;
  final Color color;
  final List<int> valores;
}

/// Barras verticales agrupadas sobre un eje de categorías — para
/// "¿cómo evolucionó esto en el tiempo?".
///
/// `CustomPainter` propio, como el resto de gráficas del proyecto: no
/// se agrega ninguna dependencia de gráficas. Soporta una o dos series;
/// más de dos deja de leerse y ese caso se resuelve con
/// `RisegCompositionChart`, no apretando barras aquí.
///
/// Los valores negativos se dibujan bajo la línea base — un mes en que
/// una cancelación supera al gasto del periodo es un dato real, no un
/// cero.
class RisegBarChart extends StatefulWidget {
  const RisegBarChart({
    required this.etiquetas,
    required this.series,
    required this.formatoValor,
    this.onCategoriaSeleccionada,
    this.mostrarEjeY = true,
    super.key,
  });

  /// Etiqueta corta de cada categoría (ej. "3/09", "sem 12", "ene").
  final List<String> etiquetas;

  final List<RisegBarSeries> series;

  /// Cómo se escribe un valor en el eje y en el tooltip. La gráfica no
  /// sabe si son pesos, litros o personas.
  final String Function(int) formatoValor;

  final ValueChanged<int>? onCategoriaSeleccionada;

  final bool mostrarEjeY;

  @override
  State<RisegBarChart> createState() => _RisegBarChartState();
}

class _RisegBarChartState extends State<RisegBarChart> {
  int? _indiceActivo;
  Offset? _posicionPuntero;

  void _actualizarIndice(Offset posicionLocal, double ancho) {
    if (widget.etiquetas.isEmpty) return;
    final anchoColumna = ancho / widget.etiquetas.length;
    if (anchoColumna <= 0) return;
    setState(() {
      _indiceActivo = (posicionLocal.dx / anchoColumna).floor().clamp(0, widget.etiquetas.length - 1);
      _posicionPuntero = posicionLocal;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (widget.etiquetas.isEmpty || widget.series.isEmpty) return const SizedBox.shrink();

    final todos = widget.series.expand((s) => s.valores);
    final maximo = todos.fold<int>(0, (m, v) => v > m ? v : m);
    final minimo = todos.fold<int>(0, (m, v) => v < m ? v : m);

    return LayoutBuilder(
      builder: (context, constraints) {
        return MouseRegion(
          onHover: (e) => _actualizarIndice(e.localPosition, constraints.maxWidth),
          onExit: (_) => setState(() {
            _indiceActivo = null;
            _posicionPuntero = null;
          }),
          child: GestureDetector(
            onTapDown: (d) {
              _actualizarIndice(d.localPosition, constraints.maxWidth);
              final i = _indiceActivo;
              if (i != null) widget.onCategoriaSeleccionada?.call(i);
            },
            child: Stack(
              children: [
                CustomPaint(
                  size: Size(constraints.maxWidth, constraints.maxHeight),
                  painter: _BarChartPainter(
                    etiquetas: widget.etiquetas,
                    series: widget.series,
                    maximo: maximo,
                    minimo: minimo,
                    indiceActivo: _indiceActivo,
                    mostrarEjeY: widget.mostrarEjeY,
                    formatoValor: widget.formatoValor,
                    colors: colors,
                  ),
                ),
                if (_indiceActivo != null && _posicionPuntero != null)
                  _TooltipBarras(
                    posicion: _posicionPuntero!,
                    anchoDisponible: constraints.maxWidth,
                    titulo: widget.etiquetas[_indiceActivo!],
                    filas: [
                      for (final s in widget.series)
                        if (_indiceActivo! < s.valores.length)
                          (s.label, s.color, widget.formatoValor(s.valores[_indiceActivo!])),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TooltipBarras extends StatelessWidget {
  const _TooltipBarras({
    required this.posicion,
    required this.anchoDisponible,
    required this.titulo,
    required this.filas,
  });

  final Offset posicion;
  final double anchoDisponible;
  final String titulo;
  final List<(String, Color, String)> filas;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    const anchoCaja = 180.0;
    // Se voltea al otro lado del cursor cuando no cabe a la derecha —
    // sin esto, en la última columna el tooltip se corta.
    final izquierda = (posicion.dx + AppSpacing.sm + anchoCaja > anchoDisponible)
        ? posicion.dx - anchoCaja - AppSpacing.sm
        : posicion.dx + AppSpacing.sm;

    return Positioned(
      left: izquierda.clamp(0, (anchoDisponible - anchoCaja).clamp(0, double.infinity)),
      top: 0,
      child: IgnorePointer(
        child: Container(
          width: anchoCaja,
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: AppRadius.mdRadius,
            border: Border.all(color: colors.borderSubtle),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(titulo, style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary)),
              const SizedBox(height: AppSpacing.xxs),
              for (final (label, color, valor) in filas)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(color: color, borderRadius: AppRadius.smRadius),
                      ),
                      const SizedBox(width: AppSpacing.xxs),
                      Expanded(
                        child: Text(
                          label,
                          style: AppTypography.caption.copyWith(color: colors.textMuted),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xxs),
                      Text(valor, style: AppTypography.caption.copyWith(color: colors.textPrimary)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarChartPainter extends CustomPainter {
  _BarChartPainter({
    required this.etiquetas,
    required this.series,
    required this.maximo,
    required this.minimo,
    required this.indiceActivo,
    required this.mostrarEjeY,
    required this.formatoValor,
    required this.colors,
  });

  final List<String> etiquetas;
  final List<RisegBarSeries> series;
  final int maximo;
  final int minimo;
  final int? indiceActivo;
  final bool mostrarEjeY;
  final String Function(int) formatoValor;
  final AppColorScheme colors;

  static const _altoEjeX = 16.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (etiquetas.isEmpty || size.width <= 0 || size.height <= 0) return;

    final anchoEjeY = mostrarEjeY ? _medirAnchoEjeY() : 0.0;
    final areaAlto = (size.height - _altoEjeX).clamp(1.0, double.infinity);
    final areaAncho = (size.width - anchoEjeY).clamp(1.0, double.infinity);
    final origenX = anchoEjeY;

    // La línea base es el 0, no el mínimo: comprimir la escala para que
    // arranque en el valor más chico exagera diferencias pequeñas y es
    // la forma más común de mentir con una gráfica de barras.
    final tope = maximo <= 0 ? 1 : maximo;
    final piso = minimo < 0 ? minimo : 0;
    final rango = tope - piso;
    double yDe(num valor) => areaAlto - ((valor - piso) / rango) * areaAlto;
    final yCero = yDe(0);

    final gridPaint = Paint()
      ..color = colors.borderSubtle
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final valor = piso + rango * (3 - i) / 3;
      final y = yDe(valor);
      canvas.drawLine(Offset(origenX, y), Offset(size.width, y), gridPaint);
      if (mostrarEjeY) {
        _texto(
          canvas,
          formatoValor(valor.round()),
          Offset(0, y - 6),
          colors.textDisabled,
          maxAncho: anchoEjeY - AppSpacing.xxs,
        );
      }
    }

    final anchoColumna = areaAncho / etiquetas.length;
    // Cuántas etiquetas caben sin encimarse. Mostrar una de cada N es
    // preferible a rotarlas: se sigue leyendo de un vistazo.
    final paso = (28 / anchoColumna).ceil().clamp(1, etiquetas.length);

    for (var i = 0; i < etiquetas.length; i++) {
      final xColumna = origenX + i * anchoColumna;

      if (i == indiceActivo) {
        canvas.drawRect(Rect.fromLTWH(xColumna, 0, anchoColumna, areaAlto), Paint()..color = colors.accentSoftBg);
      }

      final n = series.length;
      final anchoTotalBarras = anchoColumna * 0.62;
      final anchoBarra = (anchoTotalBarras / n).clamp(2.0, 40.0);
      final inicio = xColumna + (anchoColumna - anchoBarra * n) / 2;

      for (var s = 0; s < n; s++) {
        final valores = series[s].valores;
        if (i >= valores.length) continue;
        final valor = valores[i];
        final y = yDe(valor);
        final alto = (y - yCero).abs();
        final rect = Rect.fromLTWH(inicio + anchoBarra * s, valor >= 0 ? y : yCero, anchoBarra, alto.clamp(0.0, areaAlto));
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            rect,
            topLeft: valor >= 0 ? const Radius.circular(2) : Radius.zero,
            topRight: valor >= 0 ? const Radius.circular(2) : Radius.zero,
            bottomLeft: valor < 0 ? const Radius.circular(2) : Radius.zero,
            bottomRight: valor < 0 ? const Radius.circular(2) : Radius.zero,
          ),
          Paint()..color = series[s].color,
        );
      }

      if (i % paso == 0) {
        _texto(
          canvas,
          etiquetas[i],
          Offset(xColumna, areaAlto + 2),
          i == indiceActivo ? colors.textPrimary : colors.textDisabled,
          maxAncho: anchoColumna * paso,
        );
      }
    }

    // Línea del cero, visible solo cuando hay valores negativos — si
    // todo es positivo coincide con la base y sería ruido.
    if (piso < 0) {
      canvas.drawLine(
        Offset(origenX, yCero),
        Offset(size.width, yCero),
        Paint()
          ..color = colors.textMuted
          ..strokeWidth = 1,
      );
    }
  }

  double _medirAnchoEjeY() {
    final tp = TextPainter(
      text: TextSpan(text: formatoValor(maximo), style: AppTypography.caption.copyWith(fontSize: 10)),
      textDirection: TextDirection.ltr,
    )..layout();
    // Tope de 64 px: con importes muy grandes el eje se comería la
    // gráfica, y el valor exacto siempre está en el tooltip.
    return (tp.width + AppSpacing.xs).clamp(0.0, 64.0);
  }

  void _texto(Canvas canvas, String texto, Offset offset, Color color, {required double maxAncho}) {
    if (maxAncho <= 0) return;
    final tp = TextPainter(
      text: TextSpan(text: texto, style: AppTypography.caption.copyWith(fontSize: 10, color: color)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxAncho);
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter old) {
    return old.indiceActivo != indiceActivo ||
        old.maximo != maximo ||
        old.minimo != minimo ||
        old.etiquetas != etiquetas ||
        old.series != series ||
        old.colors != colors;
  }
}
