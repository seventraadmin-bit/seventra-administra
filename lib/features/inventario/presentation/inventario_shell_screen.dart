import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import 'articulos/articulos_list_screen.dart';
import 'reportes/reportes_screen.dart';

/// Pestaña activa dentro de Inventario (Etapa 7D) — Artículos (Etapa
/// 7A) y Reportes (Etapa 7D), mismo patrón `RisegTabs` que
/// `PersonalShellScreen`/`FinanzasShellScreen`. `/inventario` en sí
/// redirige a `/inventario/articulos` (ver `createAppRouter`).
enum InventarioTab { articulos, reportes }

class InventarioShellScreen extends StatelessWidget {
  const InventarioShellScreen({required this.tab, super.key});

  final InventarioTab tab;

  static const _rutasPorIndice = ['/inventario/articulos', '/inventario/reportes'];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: RisegTabs(
            tabs: [
              RisegTabItem(label: l10n.inventarioTabArticulos),
              RisegTabItem(label: l10n.inventarioTabReportes),
            ],
            selectedIndex: tab.index,
            onChanged: (index) => context.go(_rutasPorIndice[index]),
          ),
        ),
        Expanded(
          child: switch (tab) {
            InventarioTab.articulos => const ArticulosListScreen(),
            InventarioTab.reportes => const ReportesScreen(),
          },
        ),
      ],
    );
  }
}
