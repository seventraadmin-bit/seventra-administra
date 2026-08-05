import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import 'clientes/clientes_list_screen.dart';
import 'servicios/servicios_list_screen.dart';

/// Pestaña activa dentro de Comercial. Orden fijo — Clientes, Servicios
/// — desde la Etapa 4F.1 (mismo criterio que `OrganizacionTab`).
enum ComercialTab { clientes, servicios }

/// Subnavegación de Comercial — `RisegTabs` sobre las 2 pestañas
/// estables de la Etapa 4F.1. A diferencia de `OrganizacionShellScreen`,
/// `/comercial` en sí no muestra ninguna pestaña por defecto: redirige
/// a `/comercial/clientes` (ver `createAppRouter`).
class ComercialShellScreen extends StatelessWidget {
  const ComercialShellScreen({required this.tab, super.key});

  final ComercialTab tab;

  static const _rutasPorIndice = ['/comercial/clientes', '/comercial/servicios'];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: RisegTabs(
            tabs: [
              RisegTabItem(label: l10n.comercialTabClientes),
              RisegTabItem(label: l10n.comercialTabServicios),
            ],
            selectedIndex: tab.index,
            onChanged: (index) => context.go(_rutasPorIndice[index]),
          ),
        ),
        Expanded(
          child: switch (tab) {
            ComercialTab.clientes => const ClientesListScreen(),
            ComercialTab.servicios => const ServiciosListScreen(),
          },
        ),
      ],
    );
  }
}
