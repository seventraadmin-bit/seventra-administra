import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import '../agenda_resumen_periodo.dart';

final _formatoMoneda = NumberFormat.currency(locale: 'es_MX', symbol: r'$');

/// Resumen del periodo seleccionado en la Agenda (Etapa 16, centro de
/// trabajo) — Por emitir | Por vencer/para hoy | Enviados | Procesados
/// | Importe esperado, en tarjetas compactas. Se reorganiza 5→3→2
/// columnas según el ancho disponible (nunca a 1: a diferencia de
/// Cliente/Servicio/Empresa, esta pantalla no es enteramente
/// desplazable — apilar 5 tarjetas en una sola columna empujaba la
/// tabla fuera del viewport a ~500px, hallazgo real de la validación
/// responsive de esta etapa).
class AgendaResumenPeriodoRow extends StatelessWidget {
  const AgendaResumenPeriodoRow({required this.resumen, super.key});

  final AgendaResumenPeriodo resumen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    final tarjetas = [
      RisegStatCard(label: l10n.agendaResumenPorEmitir, value: '${resumen.porEmitir}', dense: true),
      RisegStatCard(
        label: l10n.agendaResumenPorVencerHoy,
        value: '${resumen.porVencerHoy}',
        dense: true,
        deltaTone: resumen.porVencerHoy > 0 ? RisegStatusTone.warning : null,
      ),
      RisegStatCard(label: l10n.agendaResumenEnviados, value: '${resumen.enviados}', dense: true),
      RisegStatCard(label: l10n.agendaResumenProcesados, value: '${resumen.procesados}', dense: true),
      RisegStatCard(
        label: l10n.agendaResumenImporteEsperado,
        value: _formatoMoneda.format(resumen.importeEsperado / 100),
        dense: true,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columnas = constraints.maxWidth < AppBreakpoints.compact
            ? 2
            : constraints.maxWidth < AppBreakpoints.wide
                ? 3
                : 5;
        final ancho = (constraints.maxWidth - (AppSpacing.md * (columnas - 1))) / columnas;

        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [for (final tarjeta in tarjetas) SizedBox(width: ancho, child: tarjeta)],
        );
      },
    );
  }
}
