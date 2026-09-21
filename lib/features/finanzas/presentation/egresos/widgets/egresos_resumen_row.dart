import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import '../../pagos/pagos_list_screen.dart' show formatoCentavosPago;
import '../egresos_state.dart';

/// Resumen del periodo filtrado de Egresos (Etapa 17; "Deuda" agregado
/// en la Etapa 19) — Egresos del periodo | Nómina | Compras | Deuda |
/// Otros, usando los mismos totales de `ClasificarEgresosPorOrigenUseCase`
/// (nunca una segunda suma). Nunca baja a 1 columna (a diferencia de
/// Cliente/Servicio): esta pantalla también trae una barra de filtros
/// de 7 controles, y apilar tarjetas completas encima empujaba la
/// tabla fuera del viewport a ~500px (hallazgo real de la validación
/// responsive de esta etapa, mismo síntoma ya corregido en el resumen
/// de Agenda). Con 5 tarjetas, 2 columnas en la banda `compact..medium`
/// generaba 3 filas (regresión real detectada por
/// `egresos_overflow_widget_test.dart` a 900×560) — se usan 3 columnas
/// en esa banda específicamente para mantener 2 filas.
class EgresosResumenRow extends StatelessWidget {
  const EgresosResumenRow({required this.state, super.key});

  final EgresosState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    final tarjetas = [
      RisegStatCard(label: l10n.egresosResumenPeriodo, value: formatoCentavosPago(state.totalPeriodo), dense: true),
      RisegStatCard(label: l10n.egresosResumenNomina, value: formatoCentavosPago(state.totalNomina), dense: true),
      RisegStatCard(label: l10n.egresosResumenCompras, value: formatoCentavosPago(state.totalCompra), dense: true),
      RisegStatCard(label: l10n.egresosResumenDeuda, value: formatoCentavosPago(state.totalDeuda), dense: true),
      // "Otros" agrupa Manual + Tiempo Extra + Descuento Programado
      // (préstamo) — ninguno gana su propia tarjeta aquí para no
      // reintroducir la regresión de overflow ya documentada arriba (5
      // tarjetas es el máximo verificado responsive); el filtro
      // "Origen" y la columna del listado sí distinguen cada uno con
      // precisión. Debe sumar exacto lo mismo que "Periodo" menos
      // Nómina/Compras/Deuda, o esta fila deja de cuadrar visualmente.
      RisegStatCard(
        label: l10n.egresosResumenOtros,
        value: formatoCentavosPago(state.totalManual + state.totalTiempoExtra + state.totalDescuentoProgramado),
        dense: true,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columnas = constraints.maxWidth < AppBreakpoints.compact ? 2 : 5;
        final ancho = (constraints.maxWidth - (AppSpacing.md * (columnas - 1))) / columnas;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: [for (final tarjeta in tarjetas) SizedBox(width: ancho, child: tarjeta)],
            ),
            // Etapa 19B — informativo, una sola línea (nunca una 6ª
            // tarjeta: ya hubo una regresión de overflow real en esta
            // fila a 900×560 por agregar una tarjeta de más).
            if (state.totalCargadoTarjeta > 0) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                l10n.egresosResumenCargosTarjeta(formatoCentavosPago(state.totalCargadoTarjeta)),
                style: AppTypography.caption.copyWith(color: context.colors.textMuted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        );
      },
    );
  }
}
