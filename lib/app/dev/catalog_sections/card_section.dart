import 'package:flutter/material.dart';

import '../../../core/design_system/design_system.dart';
import 'catalog_section_scaffold.dart';

class CardCatalogSection extends StatelessWidget {
  const CardCatalogSection({super.key});

  @override
  Widget build(BuildContext context) {
    return CatalogSection(
      children: [
        CatalogSubsection(
          title: 'Variantes',
          description: 'standard, subtle, interactive',
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: RisegCard(
                  child: Text('standard', style: AppTypography.body.copyWith(color: context.colors.textPrimary)),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: RisegCard(
                  variant: RisegCardVariant.subtle,
                  child: Text('subtle', style: AppTypography.body.copyWith(color: context.colors.textPrimary)),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: RisegCard(
                  variant: RisegCardVariant.interactive,
                  onTap: () {},
                  child: Text(
                    'interactive (Tab + Enter)',
                    style: AppTypography.body.copyWith(color: context.colors.textPrimary),
                  ),
                ),
              ),
            ],
          ),
        ),
        CatalogSubsection(
          title: 'RisegStatCard',
          description: 'Métricas de Dashboard y resúmenes de módulo',
          child: Row(
            children: [
              const Expanded(
                child: RisegStatCard(label: 'Clientes activos', value: '128', icon: Icons.groups_outlined),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: RisegStatCard(
                  label: 'Contratos por vencer',
                  value: '7',
                  delta: '+2 esta semana',
                  deltaTone: RisegStatusTone.warning,
                  icon: Icons.description_outlined,
                  onTap: () {},
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
