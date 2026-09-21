import 'dart:io';

import 'package:flutter/material.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

/// Cabecera de identidad del expediente de Empleado (Etapa 17) — foto
/// grande + nombre + "No. de empleado · Puesto" + Servicio actual (si
/// existe) + badge de estado laboral + una línea de ingreso/antigüedad,
/// con [acciones] (Editar + menú ⋯) debajo. Mismo criterio estructural
/// que `ClienteFichaHeader`/`ServicioFichaHeader` (`RisegCard` +
/// `Wrap` de avatar/identidad/badge + acciones alineadas a la derecha),
/// adaptado a foto de persona (circular) en vez de logo institucional.
class EmpleadoFichaHeader extends StatelessWidget {
  const EmpleadoFichaHeader({
    required this.nombreCompleto,
    required this.subtitulo,
    required this.estatusBadge,
    required this.ingresoAntiguedad,
    this.fotografiaPath,
    this.servicioActual,
    this.onTapFoto,
    this.acciones,
    super.key,
  });

  final String nombreCompleto;

  /// "No. de empleado · Puesto" — ya resuelto por el llamador.
  final String subtitulo;
  final Widget estatusBadge;

  /// "Ingresó el {fecha} · {antigüedad}" — ya resuelto por el llamador
  /// (mismo formato compacto que "Plantilla activa").
  final String ingresoAntiguedad;

  final String? fotografiaPath;

  /// Nombre del Servicio vigente, si existe — texto simple aquí (la
  /// navegación real al expediente del Servicio vive en la sección
  /// "Asignación a Servicio", no duplicada en la cabecera).
  final String? servicioActual;

  final VoidCallback? onTapFoto;
  final Widget? acciones;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final archivo = fotografiaPath == null ? null : File(fotografiaPath!);
    final existeFoto = archivo != null && archivo.existsSync();

    return RisegCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            children: [
              GestureDetector(
                onTap: onTapFoto,
                child: CircleAvatar(
                  radius: 40,
                  backgroundColor: colors.accentSoftBg,
                  backgroundImage: existeFoto ? FileImage(archivo) : null,
                  child: existeFoto ? null : Icon(Icons.person, size: 40, color: colors.accentText),
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 200),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(nombreCompleto, style: AppTypography.heading2.copyWith(color: colors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(subtitulo, style: AppTypography.body.copyWith(color: colors.textMuted)),
                    if (servicioActual != null) ...[
                      const SizedBox(height: 2),
                      Text(servicioActual!, style: AppTypography.caption.copyWith(color: colors.textMuted)),
                    ],
                  ],
                ),
              ),
              estatusBadge,
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(ingresoAntiguedad, style: AppTypography.caption.copyWith(color: colors.textMuted)),
          if (acciones != null) ...[
            const SizedBox(height: AppSpacing.md),
            Align(alignment: Alignment.centerRight, child: acciones!),
          ],
        ],
      ),
    );
  }
}
