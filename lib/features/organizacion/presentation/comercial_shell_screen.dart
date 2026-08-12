import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import 'agenda/agenda_list_screen.dart';
import 'clientes/clientes_list_screen.dart';
import 'servicios/servicios_list_screen.dart';

/// Pestaña activa dentro de Comercial. Orden fijo — Clientes, Servicios,
/// Agenda — desde la Etapa 4F.1 (mismo criterio que `OrganizacionTab`),
/// Agenda añadida en la Etapa 4I.1.
enum ComercialTab { clientes, servicios, agenda }

/// Subnavegación de Comercial — `RisegTabs` sobre las pestañas estables
/// de Comercial. `/comercial` en sí no muestra ninguna pestaña por
/// defecto: redirige a `/comercial/clientes` (ver `createAppRouter`;
/// mismo patrón que `OrganizacionShellScreen` desde la Etapa 15).
class ComercialShellScreen extends StatelessWidget {
  const ComercialShellScreen({required this.tab, super.key});

  final ComercialTab tab;

  static const _rutasPorIndice = ['/comercial/clientes', '/comercial/servicios', '/comercial/agenda'];

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
              RisegTabItem(label: l10n.comercialTabAgenda),
            ],
            selectedIndex: tab.index,
            onChanged: (index) => context.go(_rutasPorIndice[index]),
          ),
        ),
        Expanded(
          child: switch (tab) {
            ComercialTab.clientes => const ClientesListScreen(),
            ComercialTab.servicios => const ServiciosListScreen(),
            ComercialTab.agenda => const AgendaListScreen(),
          },
        ),
      ],
    );
  }
}
