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
    this.alLimpiar,
    this.helperText,
    this.helperMaxLines,
    this.errorText,
    this.enabled = true,
    this.firstDate,
    this.lastDate,
    super.key,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onChanged;

  /// **Quitar la fecha**, para los campos donde «sin fecha» es un valor legítimo.
  ///
  /// 🚫 **EXISTE PORQUE UNA AYUDA PROMETÍA ALGO QUE EL CAMPO NO PODÍA HACER** (lo pidió el
  /// dueño el 25-nov-2026): el «Hasta (opcional)» de una condición comercial dice *«Déjalo
  /// vacío si no tiene fecha de fin»* y, en cuanto tenía valor, **no había forma de
  /// vaciarlo** — `onChanged` sólo se llama cuando el selector devuelve una fecha—. El
  /// servidor sí acepta nulo ahí, así que lo que faltaba era la pantalla.
  ///
  /// ⚠️ **Es OPCIONAL a propósito:** sin este callback el campo se comporta como siempre y
  /// **no** ofrece quitar nada, que es lo correcto donde la fecha es obligatoria —un inicio,
  /// un último día que cobra—. Ofrecer «quitar» donde el servidor lo rechaza sería un botón
  /// que sólo sirve para recibir un 400.
  final VoidCallback? alLimpiar;

  final String? helperText;

  /// Cuántas líneas admite la ayuda.
  ///
  /// 🚫 **EXISTE PORQUE SIN ÉL LA AYUDA SE CORTABA.** Flutter recorta el `helperText` a
  /// **una** línea por omisión, así que una ayuda de tres salía con puntos suspensivos —lo
  /// encontró el dueño el 18-nov-2026, en el campo «Hasta» de una condición comercial—. El
  /// campo de texto del sistema de diseño ya lo exponía; este no, y por eso sólo se cortaba
  /// aquí.
  final int? helperMaxLines;

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
            helperMaxLines: helperMaxLines,
            errorText: errorText,
            // EL ASPA SÓLO APARECE CUANDO HAY ALGO QUE QUITAR y el campo lo admite: un
            // botón de limpiar sobre un campo vacío es ruido, y sobre un campo obligatorio
            // es una trampa.
            suffixIcon: alLimpiar != null && value != null && enabled
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        key: const Key('riseg-date-field-limpiar'),
                        icon: const Icon(Icons.close, size: 18),
                        tooltip: 'Quitar la fecha',
                        onPressed: alLimpiar,
                      ),
                      const Padding(
                        padding: EdgeInsets.only(right: AppSpacing.sm),
                        child: Icon(Icons.calendar_today_outlined, size: 20),
                      ),
                    ],
                  )
                : const Icon(Icons.calendar_today_outlined, size: 20),
          ),
        ),
      ],
    );
  }
}
