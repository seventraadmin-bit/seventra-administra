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
  String? _tipoSeleccionado = 'oficina';
  TimeOfDay? _hora = const TimeOfDay(hour: 8, minute: 0);

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
        CatalogSubsection(
          title: 'RisegSelect',
          description: 'Selector oficial — mismo look que RisegTextField, con lista cerrada de opciones',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RisegSelect<String>(
                label: 'Tipo de Sucursal',
                value: _tipoSeleccionado,
                items: const [
                  RisegSelectItem(value: 'oficina', label: 'Oficina Administrativa'),
                  RisegSelectItem(value: 'base', label: 'Base Operativa'),
                  RisegSelectItem(value: 'bodega', label: 'Bodega'),
                ],
                onChanged: (value) => setState(() => _tipoSeleccionado = value),
              ),
              const SizedBox(height: AppSpacing.md),
              const RisegSelect<String>(
                label: 'Con error',
                value: null,
                items: [RisegSelectItem(value: 'a', label: 'Opción A')],
                onChanged: null,
                errorText: 'Selecciona una opción',
              ),
            ],
          ),
        ),
        CatalogSubsection(
          title: 'RisegTimeField',
          description: 'Hora del día vía el selector nativo — usado por Horario',
          child: RisegTimeField(
            label: 'Hora de inicio',
            value: _hora,
            onChanged: (value) => setState(() => _hora = value),
          ),
        ),
      ],
    );
  }
}
