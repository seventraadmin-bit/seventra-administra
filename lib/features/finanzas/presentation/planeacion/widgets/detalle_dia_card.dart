import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/obtener_proyeccion_caja_usecase.dart';
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_list_screen.dart' show formatoCentavosPago;

final _formatoFechaLarga = DateFormat('EEEE d \'de\' MMMM', 'es_MX');

/// Detalle de un día del calendario financiero (Etapa 19D) — Entradas/
/// Salidas del día seleccionado + balance, cada renglón navega a su
/// expediente real vía [onAbrirCompromiso] (siempre por FK/id real,
/// nunca por texto).
class DetalleDiaCard extends StatelessWidget {
  const DetalleDiaCard({
    required this.dia,
    required this.compromisosDelDia,
    required this.onAbrirCompromiso,
    super.key,
  });

  final DateTime dia;
  final List<CompromisoFinanciero> compromisosDelDia;
  final void Function(CompromisoFinanciero compromiso) onAbrirCompromiso;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    final entradas = compromisosDelDia.where((c) => c.tipo == TipoCompromiso.entrada).toList();
    final salidas = compromisosDelDia.where((c) => c.tipo == TipoCompromiso.salida).toList();
    final balance = entradas.fold<int>(0, (s, c) => s + c.importe) - salidas.fold<int>(0, (s, c) => s + c.importe);

    return RisegCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _capitalizar(_formatoFechaLarga.format(dia)),
            style: AppTypography.heading3.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.md),
          if (compromisosDelDia.isEmpty)
            Text(l10n.planeacionDetalleDiaVacio, style: AppTypography.body.copyWith(color: colors.textMuted, fontStyle: FontStyle.italic))
          else ...[
            if (entradas.isNotEmpty) ...[
              Text(l10n.planeacionDetalleDiaEntradas, style: AppTypography.label.copyWith(color: colors.textMuted)),
              const SizedBox(height: AppSpacing.xs),
              for (final c in entradas) _FilaCompromiso(compromiso: c, onTap: () => onAbrirCompromiso(c)),
              const SizedBox(height: AppSpacing.sm),
            ],
            if (salidas.isNotEmpty) ...[
              Text(l10n.planeacionDetalleDiaSalidas, style: AppTypography.label.copyWith(color: colors.textMuted)),
              const SizedBox(height: AppSpacing.xs),
              for (final c in salidas) _FilaCompromiso(compromiso: c, onTap: () => onAbrirCompromiso(c)),
              const SizedBox(height: AppSpacing.sm),
            ],
            const Divider(),
            const SizedBox(height: AppSpacing.xs),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l10n.planeacionDetalleDiaBalance, style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary)),
                Text(
                  formatoCentavosPago(balance),
                  style: AppTypography.bodyStrong.copyWith(color: balance < 0 ? colors.error : colors.success),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _capitalizar(String texto) => texto.isEmpty ? texto : '${texto[0].toUpperCase()}${texto.substring(1)}';
}

class _FilaCompromiso extends StatelessWidget {
  const _FilaCompromiso({required this.compromiso, required this.onTap});

  final CompromisoFinanciero compromiso;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final esEntrada = compromiso.tipo == TipoCompromiso.entrada;

    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.smRadius,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(compromiso.concepto, style: AppTypography.body.copyWith(color: colors.textPrimary), overflow: TextOverflow.ellipsis),
                  ),
                  if (compromiso.vencida) ...[
                    const SizedBox(width: AppSpacing.xxs),
                    Icon(Icons.history_toggle_off, size: AppSizes.iconSm, color: colors.warning),
                  ],
                ],
              ),
            ),
            Text(
              formatoCentavosPago(compromiso.importe),
              style: AppTypography.bodyStrong.copyWith(color: esEntrada ? colors.success : colors.error),
            ),
            const SizedBox(width: AppSpacing.xxs),
            Icon(Icons.chevron_right, size: AppSizes.iconSm, color: colors.textMuted),
          ],
        ),
      ),
    );
  }
}
