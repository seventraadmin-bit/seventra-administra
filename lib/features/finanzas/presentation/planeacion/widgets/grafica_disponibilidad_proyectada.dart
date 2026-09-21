import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/calcular_serie_disponibilidad_usecase.dart';
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_list_screen.dart' show formatoCentavosPago;

final _formatoFechaCorta = DateFormat('d/MM');

/// "Disponibilidad proyectada" (Etapa 19D, pedido §4) — widget propio
/// (`CustomPainter`), mismo patrón exacto que
/// `grafica_financiera.dart` (Dashboard): sin agregar ninguna
/// dependencia de gráficas nueva al proyecto. Línea única (el saldo
/// proyectado diario, ya calculado por `calcularSerieDisponibilidad` —
/// esta pantalla no recalcula nada), línea de referencia en $0, y el
/// punto de saldo mínimo resaltado. Hover/tap muestra el detalle exacto
/// del día en una tarjeta flotante.
class GraficaDisponibilidadProyectada extends StatefulWidget {
  const GraficaDisponibilidadProyectada({required this.serie, this.onDiaSeleccionado, super.key});

  final List<PuntoDisponibilidadDiaria> serie;
  final ValueChanged<PuntoDisponibilidadDiaria>? onDiaSeleccionado;

  @override
  State<GraficaDisponibilidadProyectada> createState() => _GraficaDisponibilidadProyectadaState();
}

class _GraficaDisponibilidadProyectadaState extends State<GraficaDisponibilidadProyectada> {
  int? _indiceActivo;
  Offset? _posicionPuntero;

  void _actualizarIndice(Offset posicionLocal, double ancho) {
    if (widget.serie.isEmpty) return;
    final anchoColumna = ancho / widget.serie.length;
    final indice = (posicionLocal.dx / anchoColumna).floor().clamp(0, widget.serie.length - 1);
    setState(() {
      _indiceActivo = indice;
      _posicionPuntero = posicionLocal;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    if (widget.serie.isEmpty) {
      return RisegEmptyState(icon: Icons.show_chart, title: l10n.planeacionGraficaVaciaTitulo, message: l10n.planeacionGraficaVaciaMensaje);
    }

    final minimo = encontrarMinimo(widget.serie)!;
    final indiceMinimo = widget.serie.indexOf(minimo);
    final maxAbs = widget.serie.fold<int>(0, (m, p) => p.saldo.abs() > m ? p.saldo.abs() : m);

    final activo = _indiceActivo != null ? widget.serie[_indiceActivo!] : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.xxs,
          children: [
            _Leyenda(color: colors.textPrimary, label: l10n.planeacionGraficaLeyendaDisponible, linea: true),
            _Leyenda(color: colors.error, label: l10n.planeacionGraficaLeyendaMinimo),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 200,
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
                    if (_indiceActivo != null) widget.onDiaSeleccionado?.call(widget.serie[_indiceActivo!]);
                  },
                  child: Stack(
                    children: [
                      CustomPaint(
                        size: Size(constraints.maxWidth, constraints.maxHeight),
                        painter: _GraficaDisponibilidadPainter(
                          serie: widget.serie,
                          maxAbs: maxAbs == 0 ? 1 : maxAbs,
                          indiceActivo: _indiceActivo,
                          indiceMinimo: indiceMinimo,
                          colorLinea: colors.textPrimary,
                          colorMinimo: colors.error,
                          colorCero: colors.borderSubtle,
                          colorNegativo: colors.error,
                          colorActivo: colors.accentSoftBg,
                        ),
                      ),
                      if (activo != null && _posicionPuntero != null)
                        _TooltipFlotante(
                          posicion: _posicionPuntero!,
                          anchoDisponible: constraints.maxWidth,
                          fecha: _formatoFechaCorta.format(activo.fecha),
                          disponible: formatoCentavosPago(activo.saldo),
                          entradas: formatoCentavosPago(activo.entradasDelDia),
                          salidas: formatoCentavosPago(activo.salidasDelDia),
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
    required this.disponible,
    required this.entradas,
    required this.salidas,
  });

  final Offset posicion;
  final double anchoDisponible;
  final String fecha;
  final String disponible;
  final String entradas;
  final String salidas;

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
              Text(l10n.planeacionGraficaTooltipDisponible(disponible), style: AppTypography.caption.copyWith(color: colors.textPrimary)),
              Text(l10n.planeacionGraficaTooltipEntradas(entradas), style: AppTypography.caption.copyWith(color: colors.success)),
              Text(l10n.planeacionGraficaTooltipSalidas(salidas), style: AppTypography.caption.copyWith(color: colors.error)),
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
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: AppSpacing.xxs),
        Flexible(
          child: Text(label, style: AppTypography.caption.copyWith(color: context.colors.textMuted), overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

class _GraficaDisponibilidadPainter extends CustomPainter {
  _GraficaDisponibilidadPainter({
    required this.serie,
    required this.maxAbs,
    required this.indiceActivo,
    required this.indiceMinimo,
    required this.colorLinea,
    required this.colorMinimo,
    required this.colorCero,
    required this.colorNegativo,
    required this.colorActivo,
  });

  final List<PuntoDisponibilidadDiaria> serie;
  final int maxAbs;
  final int? indiceActivo;
  final int indiceMinimo;
  final Color colorLinea;
  final Color colorMinimo;
  final Color colorCero;
  final Color colorNegativo;
  final Color colorActivo;

  @override
  void paint(Canvas canvas, Size size) {
    if (serie.isEmpty) return;
    final anchoColumna = size.width / serie.length;

    // Escala: 0 al centro cuando hay valores negativos, si no, cerca
    // de la base — misma técnica que `grafica_financiera.dart`.
    final hayNegativos = serie.any((p) => p.saldo < 0);
    double y(int saldo) {
      if (hayNegativos) return size.height * (0.5 - (saldo / maxAbs) * 0.45);
      return size.height * (1 - (saldo / maxAbs) * 0.9);
    }

    final yCero = y(0);
    final ceroPaint = Paint()
      ..color = colorCero
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, yCero), Offset(size.width, yCero), ceroPaint);

    if (indiceActivo != null) {
      final xColumna = indiceActivo! * anchoColumna;
      canvas.drawRect(Rect.fromLTWH(xColumna, 0, anchoColumna, size.height), Paint()..color = colorActivo);
    }

    final puntos = <Offset>[];
    for (var i = 0; i < serie.length; i++) {
      final centro = i * anchoColumna + anchoColumna / 2;
      puntos.add(Offset(centro, y(serie[i].saldo)));
    }

    final lineaPaint = Paint()
      ..color = colorLinea
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    final path = Path()..moveTo(puntos.first.dx, puntos.first.dy);
    for (final p in puntos.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, lineaPaint);

    // Tramo bajo cero resaltado en el color de salida — sobrio (solo el
    // trazo, sin relleno agresivo), visible pero no ruidoso.
    for (var i = 0; i < serie.length; i++) {
      if (serie[i].saldo < 0) {
        canvas.drawCircle(puntos[i], i == indiceActivo ? 3.5 : 2, Paint()..color = colorNegativo);
      }
    }

    canvas.drawCircle(puntos[indiceMinimo], indiceMinimo == indiceActivo ? 5 : 4, Paint()..color = colorMinimo);

    for (var i = 0; i < puntos.length; i++) {
      if (i == indiceMinimo || serie[i].saldo < 0) continue;
      canvas.drawCircle(puntos[i], i == indiceActivo ? 3.5 : 2, Paint()..color = colorLinea);
    }
  }

  @override
  bool shouldRepaint(covariant _GraficaDisponibilidadPainter oldDelegate) {
    return oldDelegate.serie != serie || oldDelegate.indiceActivo != indiceActivo || oldDelegate.maxAbs != maxAbs;
  }
}
