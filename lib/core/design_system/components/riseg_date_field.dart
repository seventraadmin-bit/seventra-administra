import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme_context.dart';
import '../tokens/app_spacing.dart';
import '../tokens/app_typography.dart';

/// Selector de fecha de RISEG ONE — usado por cualquier módulo que
/// necesite capturar una fecha del calendario (sin hora).
///
/// Compone sobre `showDatePicker` (el diálogo nativo de Material, no un
/// calendario propio) detrás de un campo de solo-lectura con el mismo
/// look de `RisegTextField` — mismo criterio que `RisegTimeField`: evita
/// reinventar un selector cuando Flutter ya trae uno accesible
/// (navegable por teclado, localizado según `Localizations.localeOf`).
class RisegDateField extends StatelessWidget {
  const RisegDateField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.helperText,
    this.errorText,
    this.enabled = true,
    this.firstDate,
    this.lastDate,
    super.key,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final String? helperText;
  final String? errorText;
  final bool enabled;

  /// Por defecto, un rango amplio (1900 hasta 50 años en el futuro desde
  /// hoy) — suficiente para cualquier fecha de negocio real de RISEG sin
  /// que cada llamador tenga que definir un rango propio.
  final DateTime? firstDate;
  final DateTime? lastDate;

  Future<void> _abrirSelector(BuildContext context) async {
    final ahora = DateTime.now();
    final seleccionada = await showDatePicker(
      context: context,
      initialDate: value ?? ahora,
      firstDate: firstDate ?? DateTime(1900),
      lastDate: lastDate ?? DateTime(ahora.year + 50),
    );
    if (seleccionada != null) onChanged(seleccionada);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final locale = Localizations.localeOf(context).toString();
    final texto = value == null ? '' : DateFormat.yMMMd(locale).format(value!);

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
            hintText: 'dd/mm/aaaa',
            helperText: helperText,
            errorText: errorText,
            suffixIcon: const Icon(Icons.calendar_today_outlined, size: 20),
          ),
        ),
      ],
    );
  }
}
