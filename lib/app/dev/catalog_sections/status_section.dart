import 'package:flutter/material.dart';

import '../../../core/design_system/design_system.dart';
import 'catalog_section_scaffold.dart';

class StatusCatalogSection extends StatelessWidget {
  const StatusCatalogSection({super.key});

  @override
  Widget build(BuildContext context) {
    return CatalogSection(
      children: [
        const CatalogSubsection(
          title: 'RisegStatusBadge — ejemplos de dominio',
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              RisegStatusBadge(label: 'Cliente activo', tone: RisegStatusTone.success, icon: Icons.check_circle_outline),
              RisegStatusBadge(label: 'Contrato vencido', tone: RisegStatusTone.error, icon: Icons.error_outline),
              RisegStatusBadge(label: 'Servicio suspendido', tone: RisegStatusTone.warning, icon: Icons.pause_circle_outline),
              RisegStatusBadge(label: 'Pendiente de revisión', tone: RisegStatusTone.info),
              RisegStatusBadge(label: 'Sin asignar', tone: RisegStatusTone.neutral),
            ],
          ),
        ),
        CatalogSubsection(
          title: 'RisegEmptyState — estado vacío de servicios',
          child: RisegEmptyState(
            title: 'Este cliente aún no tiene servicios',
            message: 'Cuando se asigne un servicio a este cliente, aparecerá listado aquí.',
            icon: Icons.miscellaneous_services_outlined,
            primaryAction: RisegButton(label: 'Asignar servicio', icon: Icons.add, onPressed: () {}),
          ),
        ),
      ],
    );
  }
}
