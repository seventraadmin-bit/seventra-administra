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
  const FichaCorporativaHeader({required this.empresa, this.acciones, super.key});

  final EmpresaData empresa;

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
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 56, maxWidth: 140),
                child: Image.asset('assets/images/logo.png', fit: BoxFit.contain),
              ),
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
