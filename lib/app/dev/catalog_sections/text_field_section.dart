import 'package:flutter/material.dart';

import '../../../core/design_system/design_system.dart';
import 'catalog_section_scaffold.dart';

class TextFieldCatalogSection extends StatefulWidget {
  const TextFieldCatalogSection({super.key});

  @override
  State<TextFieldCatalogSection> createState() => _TextFieldCatalogSectionState();
}

class _TextFieldCatalogSectionState extends State<TextFieldCatalogSection> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return CatalogSection(
      children: [
        const CatalogSubsection(
          title: 'RisegTextField — caso de dominio',
          description: 'Campo RFC con ayuda y validación visual',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RisegTextField(label: 'RFC', hint: 'AAAA000101AAA', helperText: '12-13 caracteres'),
              SizedBox(height: AppSpacing.md),
              RisegTextField(
                label: 'RFC',
                hint: 'AAAA000101AAA',
                errorText: 'El RFC capturado no es válido',
              ),
            ],
          ),
        ),
        const CatalogSubsection(
          title: 'Estados',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RisegTextField(label: 'Nombre del cliente', hint: 'Ej. Sportium'),
              SizedBox(height: AppSpacing.md),
              RisegTextField(label: 'Campo deshabilitado', enabled: false, hint: 'No editable'),
              SizedBox(height: AppSpacing.md),
              RisegTextField(
                label: 'Solo lectura',
                readOnly: true,
                hint: 'Valor fijo',
              ),
            ],
          ),
        ),
        CatalogSubsection(
          title: 'Prefijo / sufijo',
          description: 'Ícono inicial y acción final (ej. mostrar contraseña)',
          child: RisegTextField(
            label: 'Contraseña',
            prefixIcon: Icons.lock_outline,
            obscureText: _obscure,
            suffixAction: IconButton(
              icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        const CatalogSubsection(
          title: 'RisegSearchField',
          description: 'Densidad distinta al TextField — pensado para barras, no formularios',
          child: RisegSearchField(hint: 'Buscar cliente, contrato o servicio'),
        ),
      ],
    );
  }
}
