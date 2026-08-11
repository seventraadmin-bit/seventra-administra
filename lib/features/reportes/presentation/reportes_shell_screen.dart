import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/core/permissions/permission_service.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

import '../reportes_permisos.dart';
import 'finanzas/reportes_finanzas_screen.dart';
import 'general/reportes_general_screen.dart';
import 'personal_nomina/reportes_personal_nomina_screen.dart';

/// Pestaña activa dentro de Reportes (Etapa 12A/12B) — General,
/// Finanzas y Personal·Nómina por ahora; Compras·Inventario,
/// Vehículos·Telefonía y Comercial llegan en 12C (mismo criterio ya
/// usado por `FinanzasTab`/`VehiculosTab`: el enum solo lista lo que
/// ya existe, nunca pestañas futuras a medio construir).
enum ReportesTab { general, finanzas, personalNomina }

/// Subnavegación de Reportes — mismo patrón `RisegTabs` que
/// `FinanzasShellScreen`, con una diferencia estructural nueva en el
/// proyecto: las pestañas se filtran por permiso (`reportes.ver` ya
/// exigido por el router para entrar al módulo; cada pestaña de
/// dominio exige además su propio `xxx.ver`, ver `reportes_permisos.dart`).
/// Esto es solo la capa cosmética — la barrera real vive en el
/// controller de cada pestaña, que vuelve a verificar el permiso antes
/// de consultar cualquier repositorio.
class ReportesShellScreen extends ConsumerWidget {
  const ReportesShellScreen({required this.tab, super.key});

  final ReportesTab tab;

  static const _rutasPorTab = {
    ReportesTab.general: '/reportes/general',
    ReportesTab.finanzas: '/reportes/finanzas',
    ReportesTab.personalNomina: '/reportes/personal-nomina',
  };

  /// "Personal · Nómina" se muestra si la sesión puede ver al menos una
  /// de sus dos subsecciones — cada una vuelve a gatearse por separado
  /// dentro de `ReportesPersonalNominaController`.
  static bool _visiblePara(ReportesTab tab, PermissionService permissionService) => switch (tab) {
        ReportesTab.general => true,
        ReportesTab.finanzas => permissionService.hasCode('finanzas.ver'),
        ReportesTab.personalNomina =>
          permissionService.hasCode('personal.ver') || permissionService.hasCode('nomina.ver'),
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final permissionService = ref.watch(permissionServiceProvider);

    String etiqueta(ReportesTab t) => switch (t) {
          ReportesTab.general => l10n.reportesTabGeneral,
          ReportesTab.finanzas => l10n.reportesTabFinanzas,
          ReportesTab.personalNomina => l10n.reportesTabPersonalNomina,
        };

    final filtradas = filtrarPestanasPorPermiso<ReportesTab>(
      todas: ReportesTab.values,
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
            onChanged: (index) => context.go(_rutasPorTab[filtradas.visibles[index]]!),
          ),
        ),
        Expanded(
          child: switch (tab) {
            ReportesTab.general => const ReportesGeneralScreen(),
            ReportesTab.finanzas => const ReportesFinanzasScreen(),
            ReportesTab.personalNomina => const ReportesPersonalNominaScreen(),
          },
        ),
      ],
    );
  }
}
