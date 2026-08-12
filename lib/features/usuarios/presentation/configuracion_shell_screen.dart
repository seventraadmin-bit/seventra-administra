import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/respaldo/presentation/respaldo_screen.dart';

import 'auditoria/auditoria_screen.dart';
import 'sesion_controller.dart';
import 'usuarios_list_screen.dart';

/// Pestaña activa dentro de Configuración (Etapa 11D: Usuarios,
/// Auditoría; Etapa 14C: Respaldo) — mismo patrón `RisegTabs` que
/// `VehiculosShellScreen`/`InventarioShellScreen`. `/configuracion` en
/// sí redirige a `/configuracion/usuarios` (ver `createAppRouter`).
/// `respaldo` solo se muestra al Usuario Maestro — crear/restaurar
/// reemplaza datos de toda la aplicación, ningún permiso dinámico de
/// `PermisoUsuario` la otorga (mismo criterio que la eliminación física
/// de la Etapa 11D, `exigirMaestro`).
enum ConfiguracionTab { usuarios, auditoria, respaldo }

class ConfiguracionShellScreen extends ConsumerWidget {
  const ConfiguracionShellScreen({required this.tab, super.key});

  final ConfiguracionTab tab;

  static const _rutasPorIndice = ['/configuracion/usuarios', '/configuracion/auditoria', '/configuracion/respaldo'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final esMaestro = ref.watch(sesionControllerProvider)?.esMaestro ?? false;

    final tabsVisibles = [ConfiguracionTab.usuarios, ConfiguracionTab.auditoria, if (esMaestro) ConfiguracionTab.respaldo];
    final indiceSeleccionado = tabsVisibles.indexOf(tab);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: RisegTabs(
            tabs: [
              for (final t in tabsVisibles)
                RisegTabItem(
                  label: switch (t) {
                    ConfiguracionTab.usuarios => l10n.configuracionTabUsuarios,
                    ConfiguracionTab.auditoria => l10n.configuracionTabAuditoria,
                    ConfiguracionTab.respaldo => l10n.configuracionTabRespaldo,
                  },
                ),
            ],
            selectedIndex: indiceSeleccionado < 0 ? 0 : indiceSeleccionado,
            onChanged: (index) => context.go(_rutasPorIndice[tabsVisibles[index].index]),
          ),
        ),
        Expanded(
          child: switch (tab) {
            ConfiguracionTab.usuarios => const UsuariosListScreen(),
            ConfiguracionTab.auditoria => const AuditoriaScreen(),
            ConfiguracionTab.respaldo => const RespaldoScreen(),
          },
        ),
      ],
    );
  }
}
