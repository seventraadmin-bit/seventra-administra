import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import 'equipos_telefonicos_list_screen.dart';
import 'lineas_telefonicas_list_screen.dart';

/// Pestaña activa dentro de Telefonía (Etapa 9D) — Equipos y Líneas,
/// mismo patrón `RisegTabs` que `VehiculosShellScreen`/
/// `InventarioShellScreen`. `/telefonia` en sí redirige a
/// `/telefonia/equipos` (ver `createAppRouter`) — Equipos pasa a ser la
/// pestaña por defecto porque el expediente del teléfono físico es el
/// punto de entrada natural (Líneas ya existía como pantalla única
/// desde la Etapa 9A y se mueve de ruta sin cambios de contenido).
enum TelefoniaTab { equipos, lineas }

class TelefoniaShellScreen extends StatelessWidget {
  const TelefoniaShellScreen({required this.tab, super.key});

  final TelefoniaTab tab;

  static const _rutasPorIndice = ['/telefonia/equipos', '/telefonia/lineas'];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: RisegTabs(
            tabs: [
              RisegTabItem(label: l10n.telefoniaTabEquipos),
              RisegTabItem(label: l10n.telefoniaTabLineas),
            ],
            selectedIndex: tab.index,
            onChanged: (index) => context.go(_rutasPorIndice[index]),
          ),
        ),
        Expanded(
          child: switch (tab) {
            TelefoniaTab.equipos => const EquiposTelefonicosListScreen(),
            TelefoniaTab.lineas => const LineasTelefonicasListScreen(),
          },
        ),
      ],
    );
  }
}
