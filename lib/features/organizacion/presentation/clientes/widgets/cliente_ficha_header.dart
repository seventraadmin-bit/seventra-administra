import 'dart:io';

import 'package:flutter/material.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';

/// Cabecera de identidad comercial del Cliente (Etapa 16, pasada visual
/// de Comercial) — logo protagónico + nombre comercial + razón social
/// (solo si es inequívoca) + "código · RFC" + badge de estatus, con
/// [acciones] opcionales debajo (Cambiar estatus/menú, solo en
/// consulta). Mismo criterio que `FichaCorporativaHeader` de Empresa:
/// el logo vive aquí una sola vez, nunca duplicado con la sección
/// "Datos generales".
class ClienteFichaHeader extends StatelessWidget {
  const ClienteFichaHeader({
    required this.cliente,
    required this.estatusBadge,
    this.logoPath,
    this.razonSocial,
    this.rfc,
    this.acciones,
    super.key,
  });

  final ClienteData cliente;
  final Widget estatusBadge;

  /// Ruta real en disco del logo vigente — `null` (o archivo
  /// inexistente) cae al fallback de iniciales, nunca a un error.
  final String? logoPath;

  /// Razón social a mostrar — SOLO cuando el Cliente tiene exactamente
  /// UNA Entidad fiscal activa (sin esa condición, "la" razón social es
  /// ambigua: `EntidadFiscal` no tiene bandera `esPrincipal`). El
  /// llamador resuelve esta condición, este widget solo la muestra.
  final String? razonSocial;

  /// RFC — mismo criterio de ambigüedad que [razonSocial].
  final String? rfc;

  final Widget? acciones;

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
                          inicialesDe(cliente.nombreComercial),
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
                    Text(
                      cliente.nombreComercial,
                      style: AppTypography.heading2.copyWith(color: colors.textPrimary),
                    ),
                    if (razonSocial != null && razonSocial!.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(razonSocial!, style: AppTypography.body.copyWith(color: colors.textMuted)),
                    ],
                    const SizedBox(height: 2),
                    Text(
                      rfc == null || rfc!.trim().isEmpty ? cliente.codigo : '${cliente.codigo} · RFC $rfc',
                      style: AppTypography.caption.copyWith(color: colors.textMuted),
                    ),
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
