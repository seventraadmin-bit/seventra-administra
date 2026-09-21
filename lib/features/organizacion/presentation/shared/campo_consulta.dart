import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:riseg_one/core/design_system/theme_context.dart';
import 'package:riseg_one/core/design_system/tokens/app_spacing.dart';
import 'package:riseg_one/core/design_system/tokens/app_typography.dart';

/// Par etiqueta/valor de solo lectura para el modo consulta de cualquier
/// expediente de Organización (Empresa, Sucursal, ...) — nunca un
/// `TextField` deshabilitado. Un valor nulo o en blanco siempre se
/// muestra con el mismo texto ("Pendiente de captura"), nunca un guion o
/// un espacio ambiguo.
class CampoConsulta extends StatelessWidget {
  const CampoConsulta({required this.label, required this.value, super.key});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = AppLocalizations.of(context)!;
    final esPendiente = value == null || value!.trim().isEmpty;
    final mostrado = esPendiente ? l10n.organizacionValorPendiente : value!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: AppTypography.label.copyWith(color: colors.textMuted),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          mostrado,
          style: AppTypography.body.copyWith(
            color: esPendiente ? colors.textMuted : colors.textPrimary,
            fontStyle: esPendiente ? FontStyle.italic : FontStyle.normal,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
