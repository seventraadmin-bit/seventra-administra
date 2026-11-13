/// **Una opción que se ve seleccionable, y que se ve seleccionada.**
///
/// ## Por qué existe
///
/// El dueño probando C2 el 12 de noviembre de 2026, sobre el diálogo de elegir una razón
/// social: *«muestra la opción como texto plano: no parece seleccionable»*. Era un
/// `ListTile` pelado —sin borde, sin realce al pasar el ratón y sin marca— y el único
/// indicio de que se podía pulsar era que, al pulsarlo, pasaba algo.
///
/// 🚫 **Y ELEGIR NO ES DECIDIR.** Aquel diálogo además **confirmaba con el toque**: un
/// clic en la fila asignaba y cerraba, así que no había forma de mirar las opciones sin
/// comprometerse ni de arrepentirse antes de soltar el botón. Aquí la fila **marca**, y
/// quien decide es un botón con nombre —«Asignar»—, que es lo que el dueño pidió.
///
/// ## Lo que dice de sí misma
///
/// Tres cosas, y ninguna depende sólo del color:
///
///  · **un círculo** a la izquierda, lleno con una palomita cuando está marcada —así se
///    lee también en blanco y negro, que es la misma regla que `RisegStatusBadge`—;
///  · **un borde** que cambia a color de acento al marcarse;
///  · **realce al pasar el ratón**, que es lo que dice «esto se puede pulsar» antes de
///    pulsarlo.
library;

import 'package:flutter/material.dart';

import '../theme_context.dart';
import '../tokens/app_radius.dart';
import '../tokens/app_spacing.dart';
import '../tokens/app_typography.dart';

class RisegOpcion extends StatefulWidget {
  const RisegOpcion({
    required this.titulo,
    required this.marcada,
    required this.alPulsar,
    this.subtitulo,
    this.alFinal,
    super.key,
  });

  final String titulo;

  /// La segunda línea: el número de empleado, el RFC. Nula si no hay.
  final String? subtitulo;

  final bool marcada;
  final VoidCallback alPulsar;

  /// Una insignia a la derecha —«Baja», «Archivada»—, si hace falta.
  final Widget? alFinal;

  @override
  State<RisegOpcion> createState() => _RisegOpcionState();
}

class _RisegOpcionState extends State<RisegOpcion> {
  bool _encima = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _encima = true),
        onExit: (_) => setState(() => _encima = false),
        child: GestureDetector(
          onTap: widget.alPulsar,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: widget.marcada
                  ? colors.accentSoftBg
                  : (_encima ? colors.surfaceSunken : colors.surface),
              borderRadius: AppRadius.mdRadius,
              border: Border.all(
                color: widget.marcada ? colors.accent : colors.borderSubtle,
                width: widget.marcada ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                // EL CÍRCULO, Y NO SÓLO EL COLOR: un estado dicho únicamente con color no
                // lo dice para quien no distingue esos colores.
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.marcada ? colors.accent : Colors.transparent,
                    border: Border.all(
                      color: widget.marcada
                          ? colors.accent
                          : colors.borderInteractive,
                    ),
                  ),
                  child: widget.marcada
                      ? Icon(Icons.check, size: 14, color: colors.surface)
                      : null,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.titulo,
                        style: widget.marcada
                            ? AppTypography.bodyStrong
                            : AppTypography.body,
                      ),
                      if (widget.subtitulo case final s?)
                        Text(
                          s,
                          style: AppTypography.caption.copyWith(
                            color: colors.textMuted,
                          ),
                        ),
                    ],
                  ),
                ),
                if (widget.alFinal case final a?) a,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
