import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_list_screen.dart' show formatoCentavosPago;

import '../../domain/usecases/obtener_serie_financiera_usecase.dart';

/// Gráfica Ingresos vs Egresos (Parte H del rediseño gerencial, pulida
/// en v1.1) — widget propio ligero (`CustomPainter`), sin agregar
/// ninguna dependencia de gráficas nueva al proyecto. Tres series:
/// Ingresos/Egresos (barras) y Resultado acumulado (línea, escala
/// propia — un acumulado del periodo puede ser muchas veces más grande
/// que cualquier día individual, mezclarlo en la misma escala aplastaría
/// las barras). Con un solo punto (periodo "Hoy") se muestra como dos
/// barras únicas, sin inventar granularidad horaria.
///
/// Hover/tap sobre una columna muestra el detalle exacto de ese día en
/// una tarjeta flotante; [onDiaSeleccionado] permite navegar a Finanzas
/// filtrado a esa fecha cuando el llamador lo provee.
class GraficaFinanciera extends StatefulWidget {
  const GraficaFinanciera({required this.puntos, this.onDiaSeleccionado, super.key});

  final List<PuntoSerieFinanciera> puntos;
  final ValueChanged<PuntoSerieFinanciera>? onDiaSeleccionado;

  @override
  State<GraficaFinanciera> createState() => _GraficaFinancieraState();
}

class _GraficaFinancieraState extends State<GraficaFinanciera> {
  int? _indiceActivo;
  Offset? _posicionPuntero;

  static final _formatoFechaCorta = DateFormat('d/MM');

  List<int> get _acumulado {
    var corrida = 0;
    return [for (final p in widget.puntos) corrida += p.resultado];
  }

  void _actualizarIndice(Offset posicionLocal, double ancho) {
    if (widget.puntos.isEmpty) return;
    final anchoColumna = ancho / widget.puntos.length;
    final indice = (posicionLocal.dx / anchoColumna).floor().clamp(0, widget.puntos.length - 1);
    setState(() {
      _indiceActivo = indice;
      _posicionPuntero = posicionLocal;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    if (widget.puntos.isEmpty) {
      return RisegEmptyState(icon: Icons.show_chart, title: l10n.dashboardGraficaVaciaTitulo, message: l10n.dashboardGraficaVaciaMensaje);
    }

    final maxValor = widget.puntos.expand((p) => [p.ingresos, p.egresos]).fold<int>(0, (m, v) => v > m ? v : m);
    final acumulado = _acumulado;
    final maxAcumuladoAbs = acumulado.fold<int>(0, (m, v) => v.abs() > m ? v.abs() : m);

    final activo = _indiceActivo != null ? widget.puntos[_indiceActivo!] : null;
    final activoAcumulado = _indiceActivo != null ? acumulado[_indiceActivo!] : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.xxs,
          children: [
            _Leyenda(color: colors.info, label: l10n.dashboardGraficaLeyendaIngresos),
            _Leyenda(color: colors.error, label: l10n.dashboardGraficaLeyendaEgresos),
            _Leyenda(color: colors.textPrimary, label: l10n.dashboardGraficaLeyendaResultadoAcumulado, linea: true),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 180,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return MouseRegion(
                onHover: (event) => _actualizarIndice(event.localPosition, constraints.maxWidth),
                onExit: (_) => setState(() {
                  _indiceActivo = null;
                  _posicionPuntero = null;
                }),
                child: GestureDetector(
                  onTapDown: (details) {
                    _actualizarIndice(details.localPosition, constraints.maxWidth);
                    if (_indiceActivo != null) widget.onDiaSeleccionado?.call(widget.puntos[_indiceActivo!]);
                  },
                  child: Stack(
                    children: [
                      CustomPaint(
                        size: Size(constraints.maxWidth, constraints.maxHeight),
                        painter: _GraficaFinancieraPainter(
                          puntos: widget.puntos,
                          acumulado: acumulado,
                          maxValor: maxValor,
                          maxAcumuladoAbs: maxAcumuladoAbs,
                          indiceActivo: _indiceActivo,
                          colorIngresos: colors.info,
                          colorEgresos: colors.error,
                          colorLineaAcumulado: colors.textPrimary,
                          colorGrid: colors.borderSubtle,
                          colorActivo: colors.accentSoftBg,
                        ),
                      ),
                      if (activo != null && _posicionPuntero != null)
                        _TooltipFlotante(
                          posicion: _posicionPuntero!,
                          anchoDisponible: constraints.maxWidth,
                          fecha: _formatoFechaCorta.format(activo.fecha),
                          ingresos: formatoCentavosPago(activo.ingresos),
                          egresos: formatoCentavosPago(activo.egresos),
                          resultado: formatoCentavosPago(activo.resultado),
                          acumulado: formatoCentavosPago(activoAcumulado!),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TooltipFlotante extends StatelessWidget {
  const _TooltipFlotante({
    required this.posicion,
    required this.anchoDisponible,
    required this.fecha,
    required this.ingresos,
    required this.egresos,
    required this.resultado,
    required this.acumulado,
  });

  final Offset posicion;
  final double anchoDisponible;
  final String fecha;
  final String ingresos;
  final String egresos;
  final String resultado;
  final String acumulado;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    const anchoCaja = 190.0;
    final izquierda = (posicion.dx + AppSpacing.sm + anchoCaja > anchoDisponible) ? posicion.dx - anchoCaja - AppSpacing.sm : posicion.dx + AppSpacing.sm;

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
              Text(fecha, style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary)),
              const SizedBox(height: AppSpacing.xxs),
              Text(l10n.dashboardGraficaTooltipIngresos(ingresos), style: AppTypography.caption.copyWith(color: colors.info)),
              Text(l10n.dashboardGraficaTooltipEgresos(egresos), style: AppTypography.caption.copyWith(color: colors.error)),
              Text(l10n.dashboardGraficaTooltipResultado(resultado), style: AppTypography.caption.copyWith(color: colors.textPrimary)),
              Text(
                '${l10n.dashboardGraficaLeyendaResultadoAcumulado.split(' (').first}: $acumulado',
                style: AppTypography.caption.copyWith(color: colors.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Leyenda extends StatelessWidget {
  const _Leyenda({required this.color, required this.label, this.linea = false});

  final Color color;
  final String label;
  final bool linea;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (linea)
          Container(width: 12, height: 2, color: color)
        else
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: AppRadius.smRadius)),
        const SizedBox(width: AppSpacing.xxs),
        Flexible(
          child: Text(
            label,
            style: AppTypography.caption.copyWith(color: context.colors.textMuted),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _GraficaFinancieraPainter extends CustomPainter {
  _GraficaFinancieraPainter({
    required this.puntos,
    required this.acumulado,
    required this.maxValor,
    required this.maxAcumuladoAbs,
    required this.indiceActivo,
    required this.colorIngresos,
    required this.colorEgresos,
    required this.colorLineaAcumulado,
    required this.colorGrid,
    required this.colorActivo,
  });

  final List<PuntoSerieFinanciera> puntos;
  final List<int> acumulado;
  final int maxValor;
  final int maxAcumuladoAbs;
  final int? indiceActivo;
  final Color colorIngresos;
  final Color colorEgresos;
  final Color colorLineaAcumulado;
  final Color colorGrid;
  final Color colorActivo;

  @override
  void paint(Canvas canvas, Size size) {
    if (puntos.isEmpty) return;
    final anchoColumna = size.width / puntos.length;
    final tope = maxValor == 0 ? 1 : maxValor;
    final topeAcumulado = maxAcumuladoAbs == 0 ? 1 : maxAcumuladoAbs;

    final gridPaint = Paint()
      ..color = colorGrid
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final puntosLinea = <Offset>[];

    for (var i = 0; i < puntos.length; i++) {
      final punto = puntos[i];
      final xColumna = i * anchoColumna;

      if (i == indiceActivo) {
        canvas.drawRect(Rect.fromLTWH(xColumna, 0, anchoColumna, size.height), Paint()..color = colorActivo);
      }

      // Barras más anchas (v1.1) — hasta 60% de la columna en vez del
      // 32% original, sigue dejando espacio para el espacio entre
      // Ingreso/Egreso y la franja de hover.
      final anchoBarra = (anchoColumna * 0.30).clamp(3.0, 42.0);
      final espacio = anchoColumna * 0.06;
      final centro = xColumna + anchoColumna / 2;

      final alturaIngreso = size.height * (punto.ingresos / tope);
      final alturaEgreso = size.height * (punto.egresos / tope);

      canvas.drawRect(
        Rect.fromLTWH(centro - espacio - anchoBarra, size.height - alturaIngreso, anchoBarra, alturaIngreso),
        Paint()..color = colorIngresos,
      );
      canvas.drawRect(
        Rect.fromLTWH(centro + espacio, size.height - alturaEgreso, anchoBarra, alturaEgreso),
        Paint()..color = colorEgresos,
      );

      // Línea de Resultado acumulado — escala propia (independiente de
      // `tope`), centrada verticalmente en 50% cuando el acumulado es 0.
      final proporcion = acumulado[i] / topeAcumulado; // [-1, 1]
      final y = size.height * (0.5 - proporcion * 0.45);
      puntosLinea.add(Offset(centro, y));
    }

    final lineaPaint = Paint()
      ..color = colorLineaAcumulado
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    final path = Path()..moveTo(puntosLinea.first.dx, puntosLinea.first.dy);
    for (final p in puntosLinea.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, lineaPaint);

    for (var i = 0; i < puntosLinea.length; i++) {
      canvas.drawCircle(puntosLinea[i], i == indiceActivo ? 4 : 2.5, Paint()..color = colorLineaAcumulado);
    }
  }

  @override
  bool shouldRepaint(covariant _GraficaFinancieraPainter oldDelegate) {
    return oldDelegate.puntos != puntos ||
        oldDelegate.indiceActivo != indiceActivo ||
        oldDelegate.maxValor != maxValor ||
        oldDelegate.maxAcumuladoAbs != maxAcumuladoAbs ||
        oldDelegate.colorIngresos != colorIngresos ||
        oldDelegate.colorEgresos != colorEgresos ||
        oldDelegate.colorLineaAcumulado != colorLineaAcumulado;
  }
}
