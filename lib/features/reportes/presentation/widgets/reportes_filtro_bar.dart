import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import '../reportes_rango_controller.dart';
import 'analitica_labels.dart';

/// Barra de periodo de Reportes.
///
/// Dos cambios de fondo respecto a la versión original:
///
///  1. **Presets.** Ver "este mes" costaba capturar dos fechas. Ahora es
///     un clic, y Desde/Hasta siguen ahí para cualquier rango que los
///     presets no cubran (moverlos deja el periodo en "Personalizado",
///     nunca marcando un preset que ya no describe lo que se ve).
///  2. **El periodo es compartido.** Vive en `ReportesRangoController`,
///     no en cada pestaña: cambiar de General a Finanzas conserva el
///     rango en vez de reiniciarlo al mes en curso.
///
/// `Wrap` en vez de `Row`: con ancho reducido los controles bajan de
/// línea en vez de desbordar.
class ReportesFiltroBar extends ConsumerWidget {
  const ReportesFiltroBar({this.filtrosAdicionales = const [], super.key});

  /// Cada pantalla decide qué filtros propios le aplican — nunca una
  /// barra fija con todos los filtros posibles del sistema.
  final List<Widget> filtrosAdicionales;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final seleccion = ref.watch(reportesRangoControllerProvider);
    final controller = ref.read(reportesRangoControllerProvider.notifier);

    String etiquetaPreset(PresetRangoReportes preset) => switch (preset) {
          PresetRangoReportes.esteMes => l10n.reportesPeriodoEsteMes,
          PresetRangoReportes.mesAnterior => l10n.reportesPeriodoMesAnterior,
          PresetRangoReportes.ultimos30Dias => l10n.reportesPeriodoUltimos30,
          PresetRangoReportes.anioActual => l10n.reportesPeriodoAnioActual,
          PresetRangoReportes.personalizado => l10n.reportesPeriodoPersonalizado,
        };

    final anterior = seleccion.rangoAnterior;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            SizedBox(
              width: 170,
              child: RisegDateField(
                key: const Key('reportes_filtro_desde'),
                label: l10n.reportesFiltroDesde,
                value: seleccion.rango.inicio,
                onChanged: controller.cambiarInicio,
              ),
            ),
            SizedBox(
              width: 170,
              child: RisegDateField(
                key: const Key('reportes_filtro_hasta'),
                label: l10n.reportesFiltroHasta,
                value: seleccion.rango.fin,
                onChanged: controller.cambiarFin,
              ),
            ),
            for (final filtro in filtrosAdicionales) SizedBox(width: 220, child: filtro),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final preset in PresetRangoReportes.values)
              // "Personalizado" no es un botón: es el estado en que
              // queda el filtro al mover una fecha. Se muestra marcado,
              // pero no se puede "aplicar".
              if (preset != PresetRangoReportes.personalizado)
                _ChipPreset(
                  label: etiquetaPreset(preset),
                  seleccionado: seleccion.preset == preset,
                  onTap: () => controller.aplicarPreset(preset),
                )
              else if (seleccion.preset == PresetRangoReportes.personalizado)
                _ChipPreset(label: etiquetaPreset(preset), seleccionado: true, onTap: null),
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.xs),
              child: Text(
                l10n.reportesPeriodoAnteriorRango(
                  etiquetaFechaCorta(anterior.inicio),
                  etiquetaFechaCorta(anterior.fin),
                ),
                style: AppTypography.caption.copyWith(color: colors.textDisabled),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ChipPreset extends StatelessWidget {
  const _ChipPreset({required this.label, required this.seleccionado, required this.onTap});

  final String label;
  final bool seleccionado;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Material(
      color: seleccionado ? colors.accentSoftBg : Colors.transparent,
      borderRadius: AppRadius.smRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.smRadius,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
          decoration: BoxDecoration(
            borderRadius: AppRadius.smRadius,
            border: Border.all(color: seleccionado ? colors.accent : colors.borderSubtle),
          ),
          child: Text(
            label,
            style: AppTypography.caption.copyWith(
              color: seleccionado ? colors.accent : colors.textMuted,
              fontWeight: seleccionado ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}
