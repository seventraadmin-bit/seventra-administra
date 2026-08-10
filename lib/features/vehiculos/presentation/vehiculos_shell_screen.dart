import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import 'alertas/alertas_vehiculos_screen.dart';
import 'vehiculos_list_screen.dart';

/// Pestaña activa dentro de Vehículos (Etapa 8C) — Flotilla (Etapa 8A)
/// y Alertas (Etapa 8C), mismo patrón `RisegTabs` que
/// `InventarioShellScreen`. `/vehiculos` en sí redirige a
/// `/vehiculos/flotilla` (ver `createAppRouter`) — restructuración
/// deliberadamente pospuesta hasta que existiera una segunda sección
/// real (mismo criterio que Inventario, que se mantuvo de una sola
/// pantalla desde 7A hasta que 7D agregó Reportes).
enum VehiculosTab { flotilla, alertas }

class VehiculosShellScreen extends StatelessWidget {
  const VehiculosShellScreen({required this.tab, super.key});

  final VehiculosTab tab;

  static const _rutasPorIndice = ['/vehiculos/flotilla', '/vehiculos/alertas'];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: RisegTabs(
            tabs: [
              RisegTabItem(label: l10n.vehiculosTabFlotilla),
              RisegTabItem(label: l10n.vehiculosTabAlertas),
            ],
            selectedIndex: tab.index,
            onChanged: (index) => context.go(_rutasPorIndice[index]),
          ),
        ),
        Expanded(
          child: switch (tab) {
            VehiculosTab.flotilla => const VehiculosListScreen(),
            VehiculosTab.alertas => const AlertasVehiculosScreen(),
          },
        ),
      ],
    );
  }
}
