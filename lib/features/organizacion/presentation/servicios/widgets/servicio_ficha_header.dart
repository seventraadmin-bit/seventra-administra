import 'dart:io';

import 'package:flutter/material.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';

/// Cabecera de identidad operacional del Servicio (Etapa 16, ficha
/// operacional) — logo del Cliente dueño + nombre del Servicio +
/// "Cliente · Código" + ubicación + badge de estatus, con [acciones]
/// opcionales debajo (solo en consulta). Mismo criterio que
/// `ClienteFichaHeader`/`FichaCorporativaHeader`.
class ServicioFichaHeader extends StatelessWidget {
  const ServicioFichaHeader({
    required this.servicio,
    required this.clienteNombre,
    required this.estatusBadge,
    this.logoPath,
    this.ubicacion,
    this.acciones,
    this.onTapCliente,
    super.key,
  });

  final ServicioData servicio;
  final String clienteNombre;
  final Widget estatusBadge;
  final String? logoPath;

  /// Texto legible de la Dirección operativa activa — `null` si el
  /// Servicio todavía no tiene una capturada.
  final String? ubicacion;

  final Widget? acciones;

  /// Navegación encadenada Servicio → Cliente (Etapa 16) — cuando se
  /// provee, "Cliente · Código" se vuelve un enlace real hacia el
  /// expediente del Cliente dueño, en vez de solo texto.
  final VoidCallback? onTapCliente;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final archivo = logoPath == null ? null : File(logoPath!);
    final existeLogo = archivo != null && archivo.existsSync();

    return RisegCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            children: [
              ClipRRect(
                borderRadius: AppRadius.mdRadius,
                child: Container(
                  width: 56,
                  height: 56,
                  color: existeLogo ? colors.surface : colors.accentSoftBg,
                  padding: existeLogo ? const EdgeInsets.all(AppSpacing.xxs) : EdgeInsets.zero,
                  alignment: Alignment.center,
                  child: existeLogo
                      ? Image.file(archivo, fit: BoxFit.contain)
                      : Text(
                          inicialesDe(clienteNombre),
                          style: AppTypography.label.copyWith(color: colors.accentText, fontSize: 18),
                        ),
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 200),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(servicio.nombre, style: AppTypography.heading2.copyWith(color: colors.textPrimary)),
                    const SizedBox(height: 2),
                    if (onTapCliente != null)
                      InkWell(
                        key: const Key('servicio_ficha_boton_ir_a_cliente'),
                        onTap: onTapCliente,
                        child: Text(
                          '$clienteNombre · ${servicio.codigo}',
                          style: AppTypography.body.copyWith(color: colors.accentText, decoration: TextDecoration.underline),
                        ),
                      )
                    else
                      Text(
                        '$clienteNombre · ${servicio.codigo}',
                        style: AppTypography.body.copyWith(color: colors.textMuted),
                      ),
                    if (ubicacion != null && ubicacion!.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(ubicacion!, style: AppTypography.caption.copyWith(color: colors.textMuted)),
                    ],
                  ],
                ),
              ),
              estatusBadge,
            ],
          ),
          if (acciones != null) ...[
            const SizedBox(height: AppSpacing.md),
            Align(alignment: Alignment.centerRight, child: acciones!),
          ],
        ],
      ),
    );
  }
}
