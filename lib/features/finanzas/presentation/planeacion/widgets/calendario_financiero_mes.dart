import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/obtener_proyeccion_caja_usecase.dart';

final _formatoMonedaCompacta = NumberFormat.compactCurrency(locale: 'es_MX', symbol: r'$');

String _formatoCompacto(int centavos) => _formatoMonedaCompacta.format(centavos / 100);

DateTime _sinHora(DateTime fecha) => DateTime(fecha.year, fecha.month, fecha.day);

/// Calendario financiero mensual (Etapa 19D) — lunes a domingo, días
/// fuera del mes atenuados, hoy/seleccionado resaltados con tokens del
/// Design System. Cada celda prioriza 3 datos (nunca la lista completa
/// de movimientos): total de entradas, total de salidas, número de
/// compromisos — el detalle completo vive en `DetalleDiaCard`, aparte.
class CalendarioFinancieroMes extends StatelessWidget {
  const CalendarioFinancieroMes({
    required this.mesVisible,
    required this.compromisos,
    required this.hoy,
    required this.diaSeleccionado,
    required this.onDiaSeleccionado,
    super.key,
  });

  final DateTime mesVisible;
  final List<CompromisoFinanciero> compromisos;
  final DateTime hoy;
  final DateTime? diaSeleccionado;
  final ValueChanged<DateTime> onDiaSeleccionado;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    final primerDiaMes = DateTime(mesVisible.year, mesVisible.month, 1);
    final ultimoDiaMes = DateTime(mesVisible.year, mesVisible.month + 1, 0);
    final inicioGrid = primerDiaMes.subtract(Duration(days: primerDiaMes.weekday - 1));
    final diasHastaFinDeMes = ultimoDiaMes.difference(inicioGrid).inDays + 1;
    final semanas = (diasHastaFinDeMes / 7).ceil();

    final porDia = <DateTime, List<CompromisoFinanciero>>{};
    for (final c in compromisos) {
      porDia.putIfAbsent(_sinHora(c.fecha), () => []).add(c);
    }

    final hoySinHora = _sinHora(hoy);
    final diaSeleccionadoSinHora = diaSeleccionado == null ? null : _sinHora(diaSeleccionado!);

    final etiquetasDias = [
      l10n.calendarioFinancieroDiaLun,
      l10n.calendarioFinancieroDiaMar,
      l10n.calendarioFinancieroDiaMie,
      l10n.calendarioFinancieroDiaJue,
      l10n.calendarioFinancieroDiaVie,
      l10n.calendarioFinancieroDiaSab,
      l10n.calendarioFinancieroDiaDom,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (final etiqueta in etiquetasDias)
              Expanded(
                child: Center(
                  child: Text(etiqueta, style: AppTypography.caption.copyWith(color: colors.textMuted)),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        for (var fila = 0; fila < semanas; fila++)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  for (var col = 0; col < 7; col++)
                    Expanded(
                      child: _CeldaDia(
                        dia: inicioGrid.add(Duration(days: fila * 7 + col)),
                        mesVisible: mesVisible,
                        compromisosDelDia: porDia[inicioGrid.add(Duration(days: fila * 7 + col))] ?? const [],
                        esHoy: inicioGrid.add(Duration(days: fila * 7 + col)) == hoySinHora,
                        seleccionado: inicioGrid.add(Duration(days: fila * 7 + col)) == diaSeleccionadoSinHora,
                        onTap: () => onDiaSeleccionado(inicioGrid.add(Duration(days: fila * 7 + col))),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _CeldaDia extends StatelessWidget {
  const _CeldaDia({
    required this.dia,
    required this.mesVisible,
    required this.compromisosDelDia,
    required this.esHoy,
    required this.seleccionado,
    required this.onTap,
  });

  final DateTime dia;
  final DateTime mesVisible;
  final List<CompromisoFinanciero> compromisosDelDia;
  final bool esHoy;
  final bool seleccionado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fueraDeMes = dia.month != mesVisible.month;

    final entradas =
        compromisosDelDia.where((c) => c.tipo == TipoCompromiso.entrada).fold<int>(0, (s, c) => s + c.importe);
    final salidas = compromisosDelDia.where((c) => c.tipo == TipoCompromiso.salida).fold<int>(0, (s, c) => s + c.importe);

    final Color fondo;
    final Color borde;
    if (seleccionado) {
      fondo = colors.accentSoftBg;
      borde = colors.accent;
    } else if (esHoy) {
      fondo = colors.accentSoftBg.withValues(alpha: 0.4);
      borde = colors.accent.withValues(alpha: 0.5);
    } else {
      fondo = colors.surface;
      borde = colors.borderSubtle;
    }

    return GestureDetector(
      onTap: fueraDeMes ? null : onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 62),
        margin: const EdgeInsets.all(1),
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
        decoration: BoxDecoration(
          color: fueraDeMes ? colors.surface.withValues(alpha: 0.4) : fondo,
          border: Border.all(color: borde, width: seleccionado ? 1.5 : 1),
          borderRadius: AppRadius.smRadius,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${dia.day}',
              style: AppTypography.caption.copyWith(
                color: fueraDeMes ? colors.textMuted.withValues(alpha: 0.5) : (esHoy ? colors.accent : colors.textPrimary),
                fontWeight: esHoy ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            if (!fueraDeMes && compromisosDelDia.isNotEmpty) ...[
              if (entradas > 0)
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text('+${_formatoCompacto(entradas)}', style: AppTypography.caption.copyWith(color: colors.success, fontSize: 10)),
                ),
              if (salidas > 0)
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text('-${_formatoCompacto(salidas)}', style: AppTypography.caption.copyWith(color: colors.error, fontSize: 10)),
                ),
              Text('${compromisosDelDia.length}', style: AppTypography.caption.copyWith(color: colors.textMuted, fontSize: 9)),
            ],
          ],
        ),
      ),
    );
  }
}
