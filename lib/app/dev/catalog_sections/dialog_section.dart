import 'package:flutter/material.dart';

import '../../../core/design_system/design_system.dart';
import 'catalog_section_scaffold.dart';

class DialogCatalogSection extends StatelessWidget {
  const DialogCatalogSection({super.key});

  @override
  Widget build(BuildContext context) {
    return CatalogSection(
      children: [
        CatalogSubsection(
          title: 'Confirmación',
          child: RisegButton(
            label: 'Desactivar cliente',
            variant: RisegButtonVariant.secondary,
            onPressed: () => RisegDialog.showConfirmation(
              context: context,
              title: 'Desactivar cliente',
              message: '¿Confirmas que quieres desactivar a Sportium? Sus servicios activos no se verán afectados.',
              confirmLabel: 'Desactivar',
              cancelLabel: 'Cancelar',
            ),
          ),
        ),
        CatalogSubsection(
          title: 'Destructivo con carga',
          description: 'El botón primario muestra loading mientras onConfirm está pendiente',
          child: RisegButton(
            label: 'Eliminar contrato',
            variant: RisegButtonVariant.danger,
            onPressed: () => RisegDialog.showConfirmation(
              context: context,
              title: 'Eliminar contrato',
              message: 'Esta acción no se puede deshacer. El contrato CTR-000042 se eliminará permanentemente.',
              confirmLabel: 'Eliminar',
              cancelLabel: 'Cancelar',
              destructive: true,
              onConfirm: () => Future.delayed(const Duration(seconds: 2)),
            ),
          ),
        ),
        CatalogSubsection(
          title: 'Informativo',
          child: RisegButton(
            label: 'Ver aviso',
            variant: RisegButtonVariant.ghost,
            onPressed: () => RisegDialog.showInformational(
              context: context,
              title: 'Documento por vencer',
              message: 'La licencia DGSP de este elemento vence en 15 días.',
              dismissLabel: 'Entendido',
            ),
          ),
        ),
        CatalogSubsection(
          title: 'Formulario',
          child: RisegButton(
            label: 'Nuevo puesto',
            onPressed: () => RisegDialog.showForm<String>(
              context: context,
              title: 'Nuevo puesto',
              confirmLabel: 'Crear',
              cancelLabel: 'Cancelar',
              contentBuilder: (context) => const RisegTextField(
                label: 'Nombre del puesto',
                hint: 'Ej. Vigilante nocturno',
                autofocus: true,
              ),
              onConfirm: () => Future.delayed(const Duration(seconds: 1), () => 'ok'),
            ),
          ),
        ),
      ],
    );
  }
}
