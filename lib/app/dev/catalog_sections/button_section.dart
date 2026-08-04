import 'package:flutter/material.dart';

import '../../../core/design_system/design_system.dart';
import 'catalog_section_scaffold.dart';

class ButtonCatalogSection extends StatefulWidget {
  const ButtonCatalogSection({super.key});

  @override
  State<ButtonCatalogSection> createState() => _ButtonCatalogSectionState();
}

class _ButtonCatalogSectionState extends State<ButtonCatalogSection> {
  bool _loading = false;

  Future<void> _simulateLoad() async {
    setState(() => _loading = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return CatalogSection(
      children: [
        CatalogSubsection(
          title: 'Variantes',
          description: 'primary, secondary, ghost, danger',
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              RisegButton(label: 'Guardar cliente', variant: RisegButtonVariant.primary, onPressed: () {}),
              RisegButton(label: 'Cancelar', variant: RisegButtonVariant.secondary, onPressed: () {}),
              RisegButton(label: 'Ver detalle', variant: RisegButtonVariant.ghost, onPressed: () {}),
              RisegButton(label: 'Eliminar contrato', variant: RisegButtonVariant.danger, onPressed: () {}),
            ],
          ),
        ),
        CatalogSubsection(
          title: 'Con ícono',
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              RisegButton(label: 'Nuevo servicio', icon: Icons.add, onPressed: () {}),
              RisegButton(
                label: 'Exportar',
                icon: Icons.download_outlined,
                variant: RisegButtonVariant.secondary,
                onPressed: () {},
              ),
            ],
          ),
        ),
        CatalogSubsection(
          title: 'Tamaño compacto',
          description: 'Para acciones dentro de tablas o barras densas',
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              RisegButton(label: 'Editar', size: RisegButtonSize.compact, onPressed: () {}),
              RisegButton(
                label: 'Quitar',
                size: RisegButtonSize.compact,
                variant: RisegButtonVariant.danger,
                onPressed: () {},
              ),
            ],
          ),
        ),
        CatalogSubsection(
          title: 'Estados',
          description: 'disabled y loading — nótese que loading no atenúa el color',
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              const RisegButton(label: 'Deshabilitado', onPressed: null),
              RisegButton(label: 'Guardando...', loading: _loading, onPressed: _simulateLoad),
            ],
          ),
        ),
      ],
    );
  }
}
