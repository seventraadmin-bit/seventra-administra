import 'package:flutter/material.dart';

import '../theme_context.dart';
import '../tokens/app_spacing.dart';
import '../tokens/app_typography.dart';

/// Selector de hora de RISEG ONE — usado por Horario (Sucursal/Servicio) y
/// cualquier futuro módulo que necesite capturar una hora del día.
///
/// Compone sobre `showTimePicker` (el diálogo nativo de Material, no un
/// reloj propio) detrás de un campo de solo-lectura con el mismo look de
/// `RisegTextField` — evita reinventar un selector de hora custom cuando
/// Flutter ya trae uno accesible (navegable por teclado, localizado).
class RisegTimeField extends StatelessWidget {
  const RisegTimeField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.helperText,
    this.errorText,
    this.enabled = true,
    super.key,
  });

  final String label;
  final TimeOfDay? value;
  final ValueChanged<TimeOfDay> onChanged;
  final String? helperText;
  final String? errorText;
  final bool enabled;

  Future<void> _abrirSelector(BuildContext context) async {
    final seleccionada = await showTimePicker(
      context: context,
      initialTime: value ?? const TimeOfDay(hour: 9, minute: 0),
    );
    if (seleccionada != null) onChanged(seleccionada);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texto = value == null ? '' : value!.format(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: AppTypography.label.copyWith(color: colors.textMuted)),
        const SizedBox(height: AppSpacing.xxs),
        TextFormField(
          key: ValueKey('$label-$texto'),
          initialValue: texto,
          readOnly: true,
          enabled: enabled,
          onTap: enabled ? () => _abrirSelector(context) : null,
          style: AppTypography.body.copyWith(color: colors.textPrimary),
          decoration: InputDecoration(
            hintText: '--:--',
            helperText: helperText,
            errorText: errorText,
            suffixIcon: const Icon(Icons.access_time_outlined, size: 20),
          ),
        ),
      ],
    );
  }
}
