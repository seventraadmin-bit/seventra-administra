import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import 'categorias/categorias_list_screen.dart';
import 'complementos/complementos_list_screen.dart';
import 'cuentas_financieras/cuentas_financieras_list_screen.dart';
import 'cuentas_por_cobrar/cuentas_por_cobrar_list_screen.dart';
import 'deudas_credito/deudas_credito_list_screen.dart';
import 'egresos/egresos_list_screen.dart';
import 'ingresos/ingresos_list_screen.dart';
import 'pagos/pagos_list_screen.dart';
import 'planeacion/planeacion_financiera_screen.dart';
import 'resumen/resumen_financiero_screen.dart';

/// Pestaña activa dentro de Finanzas (Etapa 4J.1/4J.2/4J.3/4K.1) —
/// dominio nuevo, separado de Organización/Comercial (Resolución B de
/// Marlon, explícita). Bancos, Conciliación y Reportes financieros
/// completos vivirán aquí como pestañas futuras — mismo criterio ya
/// usado por `ComercialTab`. `resumen` (Etapa 17) es la portada
/// ejecutiva; las demás siguen siendo los libros/detalles operativos.
/// `deudasYCredito` (Etapa 19) se agrega al final para no correr los
/// índices de las pestañas ya existentes. `cuentasFinancieras` (Etapa
/// 19C) se agrega después, mismo criterio.
enum FinanzasTab {
  resumen,
  cuentasPorCobrar,
  pagos,
  complementos,
  ingresos,
  egresos,
  categorias,
  deudasYCredito,
  cuentasFinancieras,
  planeacion,
}

/// Subnavegación de Finanzas — mismo patrón `RisegTabs` que
/// `ComercialShellScreen`/`OrganizacionShellScreen`. `/finanzas` en sí
/// redirige a `/finanzas/cuentas-por-cobrar` (ver `createAppRouter`).
class FinanzasShellScreen extends StatelessWidget {
  const FinanzasShellScreen({required this.tab, super.key});

  final FinanzasTab tab;

  static const _rutasPorIndice = [
    '/finanzas/resumen',
    '/finanzas/cuentas-por-cobrar',
    '/finanzas/pagos',
    '/finanzas/complementos',
    '/finanzas/ingresos',
    '/finanzas/egresos',
    '/finanzas/categorias',
    '/finanzas/deudas-y-credito',
    '/finanzas/cuentas-financieras',
    '/finanzas/planeacion',
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
              RisegTabItem(label: l10n.finanzasTabResumen),
              RisegTabItem(label: l10n.finanzasTabCuentasPorCobrar),
              RisegTabItem(label: l10n.finanzasTabPagos),
              RisegTabItem(label: l10n.finanzasTabComplementos),
              RisegTabItem(label: l10n.finanzasTabIngresos),
              RisegTabItem(label: l10n.finanzasTabEgresos),
              RisegTabItem(label: l10n.finanzasTabCategorias),
              RisegTabItem(label: l10n.finanzasTabDeudasYCredito),
              RisegTabItem(label: l10n.finanzasTabCuentasFinancieras),
              RisegTabItem(label: l10n.finanzasTabPlaneacion),
            ],
            selectedIndex: tab.index,
            onChanged: (index) => context.go(_rutasPorIndice[index]),
          ),
        ),
        Expanded(
          child: switch (tab) {
            FinanzasTab.resumen => const ResumenFinancieroScreen(),
            FinanzasTab.cuentasPorCobrar => const CuentasPorCobrarListScreen(),
            FinanzasTab.pagos => const PagosListScreen(),
            FinanzasTab.complementos => const ComplementosListScreen(),
            FinanzasTab.ingresos => const IngresosListScreen(),
            FinanzasTab.egresos => const EgresosListScreen(),
            FinanzasTab.categorias => const CategoriasListScreen(),
            FinanzasTab.deudasYCredito => const DeudasCreditoListScreen(),
            FinanzasTab.cuentasFinancieras => const CuentasFinancierasListScreen(),
            FinanzasTab.planeacion => const PlaneacionFinancieraScreen(),
          },
        ),
      ],
    );
  }
}
