import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/nomina/presentation/nominas/nominas_list_screen.dart';

import 'empleados/empleados_list_screen.dart';

/// Pestaña activa dentro de Personal (Etapa 6C) — Empleados (Etapa 5A) y
/// Nómina (Etapa 6C), mismo patrón `RisegTabs` que
/// `FinanzasShellScreen`/`ComercialShellScreen`. `/personal` en sí
/// redirige a `/personal/empleados` (ver `createAppRouter`).
enum PersonalTab { empleados, nomina }

class PersonalShellScreen extends StatelessWidget {
  const PersonalShellScreen({required this.tab, super.key});

  final PersonalTab tab;

  static const _rutasPorIndice = ['/personal/empleados', '/personal/nomina'];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: RisegTabs(
            tabs: [
              RisegTabItem(label: l10n.personalTabEmpleados),
              RisegTabItem(label: l10n.personalTabNomina),
            ],
            selectedIndex: tab.index,
            onChanged: (index) => context.go(_rutasPorIndice[index]),
          ),
        ),
        Expanded(
          child: switch (tab) {
            PersonalTab.empleados => const EmpleadosListScreen(),
            PersonalTab.nomina => const NominasListScreen(),
          },
        ),
      ],
    );
  }
}
