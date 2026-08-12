import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import 'areas/areas_list_screen.dart';
import 'empresa/empresa_expediente_screen.dart';
import 'puestos/puestos_list_screen.dart';
import 'sucursales/sucursales_list_screen.dart';

/// Pestaña activa dentro de Organización. Orden fijo aprobado en la
/// Etapa 4D — Empresa, Sucursales, Puestos, Áreas — y debe permanecer
/// estable para futuras etapas (no reordenar ni insertar en medio).
enum OrganizacionTab { empresa, sucursales, puestos, areas }

/// Subnavegación de Organización — `RisegTabs` sobre las 4 pestañas
/// estables de la Etapa 4D. `/organizacion` redirige a
/// `/organizacion/empresa` (Etapa 15, corrección de la pestaña activa) —
/// mismo patrón que `/comercial`/`/finanzas`/`/personal`/`/inventario`:
/// las 4 pestañas son rutas hermanas planas bajo un padre que solo
/// redirige, nunca un padre con contenido propio + hijas anidadas (esa
/// forma hacía que go_router mantuviera vivas varias instancias de esta
/// pantalla a la vez — una por nivel de la ruta — y la que quedaba
/// visible no siempre era la misma cuyo `RisegTabs` se había
/// actualizado, desincronizando la pestaña marcada del contenido real).
class OrganizacionShellScreen extends StatelessWidget {
  const OrganizacionShellScreen({required this.tab, super.key});

  final OrganizacionTab tab;

  static const _rutasPorIndice = [
    '/organizacion/empresa',
    '/organizacion/sucursales',
    '/organizacion/puestos',
    '/organizacion/areas',
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
              RisegTabItem(label: l10n.organizacionTabEmpresa),
              RisegTabItem(label: l10n.organizacionTabSucursales),
              RisegTabItem(label: l10n.organizacionTabPuestos),
              RisegTabItem(label: l10n.organizacionTabAreas),
            ],
            selectedIndex: tab.index,
            onChanged: (index) => context.go(_rutasPorIndice[index]),
          ),
        ),
        Expanded(
          child: switch (tab) {
            OrganizacionTab.empresa => const EmpresaExpedienteScreen(),
            OrganizacionTab.sucursales => const SucursalesListScreen(),
            OrganizacionTab.puestos => const PuestosListScreen(),
            OrganizacionTab.areas => const AreasListScreen(),
          },
        ),
      ],
    );
  }
}
