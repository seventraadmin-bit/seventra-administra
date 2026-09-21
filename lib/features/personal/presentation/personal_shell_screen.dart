import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/core/permissions/permission_service.dart';
import 'package:riseg_one/features/descuentos_personal/presentation/descuentos_personal_list_screen.dart';
import 'package:riseg_one/features/nomina/presentation/nominas/nominas_list_screen.dart';
import 'package:riseg_one/features/reportes/reportes_permisos.dart';
import 'package:riseg_one/features/tiempos_extra/presentation/tiempos_extra_list_screen.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

import 'empleados/empleados_list_screen.dart';

/// Pestaña activa dentro de Personal (Etapa 6C) — Empleados (Etapa 5A),
/// Nómina (Etapa 6C), Descuentos (Etapa 15: préstamos + botas +
/// futuros tipos — "Descuentos" en vez de "Préstamos" porque cubre más
/// de un concepto) y Tiempos Extra (cobertura operativa por ausencia,
/// pedido explícito de Marlon), mismo patrón `RisegTabs` que
/// `FinanzasShellScreen`/`ComercialShellScreen`. `/personal` en sí
/// redirige a `/personal/empleados` (ver `createAppRouter`).
enum PersonalTab { empleados, nomina, descuentos, tiemposExtra }

/// Etapa 0 (auditoría de consistencia transversal): el router solo
/// exige `personal.ver` para todo `/personal/**` (ver
/// `permisoRequeridoParaRuta`) — sin este filtro, un usuario con
/// `personal.ver` pero sin `nomina.ver` veía la pestaña Nómina igual.
/// Esto es solo la capa cosmética (mismo patrón que
/// `ReportesShellScreen._visiblePara`); la barrera real vive en
/// `NominasController.tieneNomina`/`DescuentosPersonalController.tieneDescuentos`,
/// que protegen también el acceso directo por ruta. Etapa 1 (rediseño
/// granular de permisos): mismo criterio aplicado ahora a Descuentos —
/// antes se mostraba siempre, sin `descuentos.ver` ni existir todavía.
bool _visiblePara(PersonalTab tab, PermissionService permissionService) => switch (tab) {
      PersonalTab.empleados => true,
      PersonalTab.nomina => permissionService.hasCode('nomina.ver'),
      PersonalTab.descuentos => permissionService.hasCode('descuentos.ver'),
      PersonalTab.tiemposExtra => true,
    };

class PersonalShellScreen extends ConsumerWidget {
  const PersonalShellScreen({required this.tab, this.filtroInicialSinAsignar = false, super.key});

  final PersonalTab tab;

  /// Deep-link real desde el Dashboard (Etapa 20, "Sin asignar") —
  /// solo tiene efecto cuando [tab] es [PersonalTab.empleados].
  final bool filtroInicialSinAsignar;

  static const _rutasPorIndice = [
    '/personal/empleados',
    '/personal/nomina',
    '/personal/descuentos',
    '/personal/tiempos-extra',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final permissionService = ref.watch(permissionServiceProvider);

    String etiqueta(PersonalTab t) => switch (t) {
          PersonalTab.empleados => l10n.personalTabEmpleados,
          PersonalTab.nomina => l10n.personalTabNomina,
          PersonalTab.descuentos => l10n.personalTabDescuentos,
          PersonalTab.tiemposExtra => l10n.personalTabTiemposExtra,
        };

    final filtradas = filtrarPestanasPorPermiso<PersonalTab>(
      todas: PersonalTab.values,
      visiblePara: _visiblePara,
      permissionService: permissionService,
      activa: tab,
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: RisegTabs(
            tabs: [for (final t in filtradas.visibles) RisegTabItem(label: etiqueta(t))],
            selectedIndex: filtradas.indiceActivo,
            onChanged: (index) => context.go(_rutasPorIndice[filtradas.visibles[index].index]),
          ),
        ),
        Expanded(
          child: switch (tab) {
            PersonalTab.empleados => EmpleadosListScreen(filtroInicialSinAsignar: filtroInicialSinAsignar),
            PersonalTab.nomina => const NominasListScreen(),
            PersonalTab.descuentos => const DescuentosPersonalListScreen(),
            PersonalTab.tiemposExtra => const TiemposExtraListScreen(),
          },
        ),
      ],
    );
  }
}
