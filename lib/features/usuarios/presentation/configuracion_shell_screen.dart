import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import 'auditoria/auditoria_screen.dart';
import 'usuarios_list_screen.dart';

/// Pestaña activa dentro de Configuración (Etapa 11D) — Usuarios (Etapa
/// 11A) y Auditoría (Etapa 11D), mismo patrón `RisegTabs` que
/// `VehiculosShellScreen`/`InventarioShellScreen`. `/configuracion` en
/// sí redirige a `/configuracion/usuarios` (ver `createAppRouter`).
enum ConfiguracionTab { usuarios, auditoria }

class ConfiguracionShellScreen extends StatelessWidget {
  const ConfiguracionShellScreen({required this.tab, super.key});

  final ConfiguracionTab tab;

  static const _rutasPorIndice = ['/configuracion/usuarios', '/configuracion/auditoria'];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: RisegTabs(
            tabs: [
              RisegTabItem(label: l10n.configuracionTabUsuarios),
              RisegTabItem(label: l10n.configuracionTabAuditoria),
            ],
            selectedIndex: tab.index,
            onChanged: (index) => context.go(_rutasPorIndice[index]),
          ),
        ),
        Expanded(
          child: switch (tab) {
            ConfiguracionTab.usuarios => const UsuariosListScreen(),
            ConfiguracionTab.auditoria => const AuditoriaScreen(),
          },
        ),
      ],
    );
  }
}
