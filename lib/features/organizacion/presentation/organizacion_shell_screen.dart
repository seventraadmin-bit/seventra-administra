import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import 'empresa/empresa_expediente_screen.dart';
import 'sucursales/sucursales_list_screen.dart';

/// Pestaña activa dentro de Organización. Se agrega una nueva entrada
/// aquí (y su ruta en `createAppRouter`) conforme 4D/4E/4F añadan más
/// secciones — no antes.
enum OrganizacionTab { empresa, sucursales }

/// Subnavegación de Organización — primera vez que `RisegTabs` se usa
/// fuera del catálogo de desarrollo. `/organizacion` sigue mostrando
/// Empresa por defecto (compatibilidad con la Etapa 4B); `/organizacion/
/// sucursales` es la pestaña nueva de la Etapa 4C.
class OrganizacionShellScreen extends StatelessWidget {
  const OrganizacionShellScreen({required this.tab, super.key});

  final OrganizacionTab tab;

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
            ],
            selectedIndex: tab.index,
            onChanged: (index) {
              context.go(index == 0 ? '/organizacion' : '/organizacion/sucursales');
            },
          ),
        ),
        Expanded(
          child: switch (tab) {
            OrganizacionTab.empresa => const EmpresaExpedienteScreen(),
            OrganizacionTab.sucursales => const SucursalesListScreen(),
          },
        ),
      ],
    );
  }
}
