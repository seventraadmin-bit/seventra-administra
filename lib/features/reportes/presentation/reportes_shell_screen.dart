import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

import '../reportes_permisos.dart';
import 'finanzas/reportes_finanzas_screen.dart';
import 'general/reportes_general_screen.dart';

/// Pestaña activa dentro de Reportes (Etapa 12A) — solo General y
/// Finanzas por ahora; Personal·Nómina, Compras·Inventario,
/// Vehículos·Telefonía y Comercial llegan en 12B/12C (mismo criterio ya
/// usado por `FinanzasTab`/`VehiculosTab`: el enum solo lista lo que
/// ya existe, nunca pestañas futuras a medio construir).
enum ReportesTab { general, finanzas }

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
  };

  static String? _permisoPara(ReportesTab tab) => switch (tab) {
        ReportesTab.general => null,
        ReportesTab.finanzas => 'finanzas.ver',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final permissionService = ref.watch(permissionServiceProvider);

    String etiqueta(ReportesTab t) => switch (t) {
          ReportesTab.general => l10n.reportesTabGeneral,
          ReportesTab.finanzas => l10n.reportesTabFinanzas,
        };

    final filtradas = filtrarPestanasPorPermiso<ReportesTab>(
      todas: ReportesTab.values,
      permisoPara: _permisoPara,
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
          },
        ),
      ],
    );
  }
}
