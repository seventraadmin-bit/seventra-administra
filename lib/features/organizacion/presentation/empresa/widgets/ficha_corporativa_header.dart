import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';

/// Cabecera de identidad corporativa de Empresa (Etapa 16, tercera
/// pasada visual) — logo protagónico + nombre comercial + razón social
/// + "código · RFC" + badge de estatus, con [acciones] (Tarjeta fiscal/
/// Editar) opcionales debajo. Sustituye la extinta tarjeta separada
/// "Logotipo institucional": el logo ya vive aquí, con protagonismo
/// real, nunca duplicado en dos lugares de la misma pantalla.
class FichaCorporativaHeader extends StatelessWidget {
  const FichaCorporativaHeader({required this.empresa, this.logoPath, this.acciones, super.key});

  final EmpresaData empresa;

  /// Ruta en disco del logotipo vigente de la Empresa (Etapa 5B.2).
  ///
  /// `null`, o un archivo que ya no está, cae a las iniciales — **nunca** al
  /// escudo que el producto traía dentro. Que el producto no tenga logotipo
  /// de reserva es justamente lo que impide que una Empresa nueva aparezca
  /// con la identidad de otra.
  final String? logoPath;

  /// `null` en modo edición — ahí "Guardar"/"Cancelar" ya viven en el
  /// `RisegSectionHeader` de la pantalla; duplicarlos aquí sería
  /// redundante. Solo en consulta la cabecera trae sus propias acciones
  /// (Tarjeta fiscal/Editar), tal como pide el pedido.
  final Widget? acciones;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    return RisegCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            children: [
              _LogotipoEmpresa(empresa: empresa, logoPath: logoPath),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 200),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(empresa.nombreComercial, style: AppTypography.heading2.copyWith(color: colors.textPrimary)),
                    if (empresa.razonSocial != null && empresa.razonSocial!.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(empresa.razonSocial!, style: AppTypography.body.copyWith(color: colors.textMuted)),
                    ],
                    const SizedBox(height: 2),
                    Text(
                      empresa.rfc == null || empresa.rfc!.trim().isEmpty
                          ? empresa.codigo
                          : '${empresa.codigo} · RFC ${empresa.rfc}',
                      style: AppTypography.caption.copyWith(color: colors.textMuted),
                    ),
                  ],
                ),
              ),
              if (empresa.cicloVidaRegistro == 'activo')
                RisegStatusBadge(label: l10n.empresaFichaEstatusActiva, tone: RisegStatusTone.success),
            ],
          ),
          if (empresa.eslogan != null && empresa.eslogan!.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              empresa.eslogan!,
              style: AppTypography.body.copyWith(color: colors.textMuted, fontStyle: FontStyle.italic),
            ),
          ],
          if (acciones != null) ...[
            const SizedBox(height: AppSpacing.md),
            Align(alignment: Alignment.centerRight, child: acciones!),
          ],
        ],
      ),
    );
  }
}

/// El logotipo de la Empresa, o sus iniciales.
///
/// Mismo criterio y mismas medidas que `ClienteFichaHeader`: si el archivo
/// no está, se muestran iniciales sobre el azul suave. No hay estado de
/// error visible — un logotipo que falta no es una avería.
class _LogotipoEmpresa extends StatelessWidget {
  const _LogotipoEmpresa({required this.empresa, required this.logoPath});

  final EmpresaData empresa;
  final String? logoPath;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final archivo = logoPath == null ? null : File(logoPath!);
    final existe = archivo != null && archivo.existsSync();

    return ClipRRect(
      borderRadius: AppRadius.mdRadius,
      child: Container(
        width: 56,
        height: 56,
        color: existe ? colors.surface : colors.accentSoftBg,
        padding: existe ? const EdgeInsets.all(AppSpacing.xxs) : EdgeInsets.zero,
        alignment: Alignment.center,
        child: existe
            ? Image.file(archivo, fit: BoxFit.contain, key: const Key('empresa_logo_imagen'))
            : Text(
                inicialesDe(empresa.nombreComercial),
                key: const Key('empresa_logo_iniciales'),
                style: AppTypography.label.copyWith(color: colors.accentText, fontSize: 18),
              ),
      ),
    );
  }
}
