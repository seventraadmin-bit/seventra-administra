import 'package:flutter/material.dart';

import '../../../core/design_system/design_system.dart';
import 'catalog_section_scaffold.dart';

/// Sección dedicada a comprobar navegación por teclado y foco visible —
/// una secuencia de controles interactivos de varios componentes, uno
/// tras otro, pensada para probarse con Tab/Shift+Tab/Enter/Espacio.
class FocusCatalogSection extends StatelessWidget {
  const FocusCatalogSection({super.key});

  @override
  Widget build(BuildContext context) {
    return CatalogSection(
      children: [
        CatalogSubsection(
          title: 'Cómo probar',
          child: Text(
            'Usa Tab / Shift+Tab para recorrer los controles de abajo en orden. '
            'Cada uno debe mostrar un anillo de foco visible (color de acento, 2px). '
            'Los botones y la card interactiva deben activarse con Enter o Espacio, '
            'no solo con el mouse.',
            style: AppTypography.body.copyWith(color: context.colors.textMuted),
          ),
        ),
        CatalogSubsection(
          title: 'Secuencia de foco',
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              RisegButton(label: 'Botón 1', onPressed: () {}),
              RisegButton(label: 'Botón 2', variant: RisegButtonVariant.secondary, onPressed: () {}),
              RisegButton(label: 'Botón 3', variant: RisegButtonVariant.ghost, onPressed: () {}),
              const SizedBox(
                width: 220,
                child: RisegTextField(label: 'Campo de texto', hint: 'Escribe aquí'),
              ),
              SizedBox(
                width: 220,
                child: RisegCard(
                  variant: RisegCardVariant.interactive,
                  onTap: () {},
                  child: const Text('Card interactiva'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
