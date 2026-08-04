import 'package:flutter/material.dart';

import '../../../core/design_system/design_system.dart';
import 'catalog_section_scaffold.dart';

class MiscCatalogSection extends StatefulWidget {
  const MiscCatalogSection({super.key});

  @override
  State<MiscCatalogSection> createState() => _MiscCatalogSectionState();
}

class _MiscCatalogSectionState extends State<MiscCatalogSection> {
  int _tabIndex = 0;

  static const _tabs = [
    RisegTabItem(label: 'General', icon: Icons.info_outline),
    RisegTabItem(label: 'Direcciones', icon: Icons.place_outlined),
    RisegTabItem(label: 'Contactos', icon: Icons.contacts_outlined),
    RisegTabItem(label: 'Documentos', icon: Icons.description_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return CatalogSection(
      children: [
        CatalogSubsection(
          title: 'RisegSectionHeader',
          child: RisegSectionHeader(
            title: 'Contratos de Sportium',
            description: '4 contratos registrados, 1 por vencer',
            primaryAction: RisegButton(label: 'Nuevo contrato', icon: Icons.add, onPressed: () {}),
          ),
        ),
        const CatalogSubsection(
          title: 'RisegFormSection',
          description: 'Con estado colapsable',
          child: RisegFormSection(
            title: 'Datos fiscales',
            description: 'Requeridos para timbrado',
            collapsible: true,
            children: [
              RisegTextField(label: 'RFC', hint: 'AAAA000101AAA'),
              SizedBox(height: AppSpacing.md),
              RisegTextField(label: 'Razón social', hint: 'Nombre fiscal completo'),
            ],
          ),
        ),
        CatalogSubsection(
          title: 'RisegTabs',
          description: 'Base visual para una futura vista de expediente con pestañas',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RisegTabs(tabs: _tabs, selectedIndex: _tabIndex, onChanged: (i) => setState(() => _tabIndex = i)),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Pestaña seleccionada: ${_tabs[_tabIndex].label}',
                style: AppTypography.body.copyWith(color: context.colors.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
