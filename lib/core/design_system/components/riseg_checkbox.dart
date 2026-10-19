import 'package:flutter/material.dart';

import '../theme_context.dart';
import '../tokens/app_radius.dart';
import '../tokens/app_spacing.dart';
import '../tokens/app_typography.dart';

/// Casilla de verificación de RISEG ONE — primer control de este tipo
/// en el Design System (Etapa 15, "Recuérdame en este equipo"). Compone
/// sobre `Checkbox` de Material solo para el cuadro en sí; la etiqueta y
/// el área táctil (todo el renglón, no solo el cuadro) son propias.
///
/// `enabled` y `nota` llegaron con la pantalla de Usuarios en la web, donde
/// hay casillas que están marcadas y **no se pueden desmarcar**: los
/// permisos que un Maestro ejerce por su rol. Los dos parámetros son
/// OPCIONALES y el comportamiento sin ellos no cambió, así que ninguna
/// pantalla del escritorio se entera.
class RisegCheckbox extends StatelessWidget {
  const RisegCheckbox({
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.nota,
    super.key,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  /// ¿Se puede tocar? Cuando es `false` **el renglón entero deja de
  /// responder** —no solo el cuadro—, porque una etiqueta que acepta el clic
  /// y no hace nada se siente como un fallo.
  final bool enabled;

  /// El por qué, al lado, en gris pequeño. Existe para que una casilla
  /// deshabilitada **diga su razón donde se ve**: una marcada que no se
  /// puede quitar sin explicación parece un error de la pantalla.
  final String? nota;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return InkWell(
      borderRadius: AppRadius.smRadius,
      onTap: enabled ? () => onChanged(!value) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Checkbox(
              value: value,
              // `null` es lo que Material entiende por deshabilitada, y pinta
              // el cuadro en gris él solo.
              onChanged: enabled ? (v) => onChanged(v ?? false) : null,
              activeColor: colors.accent,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: AppSpacing.xs),
            // `Expanded` (no `mainAxisSize.min`) a propósito: la
            // etiqueta debe poder ajustarse a dos líneas en un
            // contenedor angosto en vez de desbordar — mismo criterio
            // que el resto del Design System (ver el fix de
            // `RisegButton` en la misma etapa).
            Expanded(
              child: Text(
                label,
                style: AppTypography.body.copyWith(
                  color: enabled ? colors.textPrimary : colors.textDisabled,
                ),
              ),
            ),
            if (nota case final n?) ...[
              const SizedBox(width: AppSpacing.xs),
              Text(n, style: AppTypography.caption.copyWith(color: colors.textMuted)),
            ],
          ],
        ),
      ),
    );
  }
}
