import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import 'categorias/categorias_list_screen.dart';
import 'complementos/complementos_list_screen.dart';
import 'cuentas_por_cobrar/cuentas_por_cobrar_list_screen.dart';
import 'egresos/egresos_list_screen.dart';
import 'ingresos/ingresos_list_screen.dart';
import 'pagos/pagos_list_screen.dart';

/// Pestaña activa dentro de Finanzas (Etapa 4J.1/4J.2/4J.3/4K.1) —
/// dominio nuevo, separado de Organización/Comercial (Resolución B de
/// Marlon, explícita). Bancos, Conciliación y Reportes financieros
/// completos vivirán aquí como pestañas futuras — mismo criterio ya
/// usado por `ComercialTab`.
enum FinanzasTab { cuentasPorCobrar, pagos, complementos, ingresos, egresos, categorias }

/// Subnavegación de Finanzas — mismo patrón `RisegTabs` que
/// `ComercialShellScreen`/`OrganizacionShellScreen`. `/finanzas` en sí
/// redirige a `/finanzas/cuentas-por-cobrar` (ver `createAppRouter`).
class FinanzasShellScreen extends StatelessWidget {
  const FinanzasShellScreen({required this.tab, super.key});

  final FinanzasTab tab;

  static const _rutasPorIndice = [
    '/finanzas/cuentas-por-cobrar',
    '/finanzas/pagos',
    '/finanzas/complementos',
    '/finanzas/ingresos',
    '/finanzas/egresos',
    '/finanzas/categorias',
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: RisegTabs(
            tabs: [
              RisegTabItem(label: l10n.finanzasTabCuentasPorCobrar),
              RisegTabItem(label: l10n.finanzasTabPagos),
              RisegTabItem(label: l10n.finanzasTabComplementos),
              RisegTabItem(label: l10n.finanzasTabIngresos),
              RisegTabItem(label: l10n.finanzasTabEgresos),
              RisegTabItem(label: l10n.finanzasTabCategorias),
            ],
            selectedIndex: tab.index,
            onChanged: (index) => context.go(_rutasPorIndice[index]),
          ),
        ),
        Expanded(
          child: switch (tab) {
            FinanzasTab.cuentasPorCobrar => const CuentasPorCobrarListScreen(),
            FinanzasTab.pagos => const PagosListScreen(),
            FinanzasTab.complementos => const ComplementosListScreen(),
            FinanzasTab.ingresos => const IngresosListScreen(),
            FinanzasTab.egresos => const EgresosListScreen(),
            FinanzasTab.categorias => const CategoriasListScreen(),
          },
        ),
      ],
    );
  }
}
