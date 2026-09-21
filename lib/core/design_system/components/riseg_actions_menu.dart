import 'package:flutter/material.dart';

import '../theme_context.dart';

/// Una acción dentro de [RisegActionsMenu].
@immutable
class RisegMenuAction {
  const RisegMenuAction({required this.label, required this.onTap, this.icon, this.destructive = false, this.key});

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;

  /// `true` para acciones irreversibles/extraordinarias (ej. "Eliminar
  /// físicamente") — texto e ícono en `colors.error`, mismo criterio
  /// visual que `RisegButtonVariant.danger`.
  final bool destructive;

  final Key? key;
}

/// Menú ⋮ de acciones — envoltura consistente de `PopupMenuButton` para
/// que ninguna pantalla invente su propio menú (Etapa 15, hallazgo de
/// Comercial). Antes de este componente, cada uso de `PopupMenuButton`
/// en el proyecto (Bóveda, fila de Unidad en Artículo) definía su
/// propio estilo ad-hoc.
///
/// Uso previsto: acciones **comunes** (Editar, Cambiar estatus...)
/// siguen siendo botones visibles en el encabezado — este menú es
/// solo para lo **extraordinario** (Eliminar físicamente) o, en filas
/// de tabla angostas, para consolidar todas las acciones de la fila
/// cuando no hay espacio para íconos sueltos.
class RisegActionsMenu extends StatelessWidget {
  const RisegActionsMenu({required this.actions, this.tooltip, this.menuKey, super.key});

  final List<RisegMenuAction> actions;
  final String? tooltip;

  /// `Key` del `PopupMenuButton` en sí (no de sus items) — cada acción
  /// ya lleva la suya propia vía `RisegMenuAction.key`.
  final Key? menuKey;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return PopupMenuButton<VoidCallback>(
      key: menuKey,
      tooltip: tooltip,
      icon: const Icon(Icons.more_vert),
      // Diferida al siguiente frame — bug real encontrado en
      // producción (Agenda > Mirabilia > Eliminar físicamente):
      // `showMenu()` (el mecanismo interno de `PopupMenuButton`)
      // completa su Future y dispara `onSelected` ANTES de que la
      // transición de cierre del propio menú termine. Si la acción
      // abre otro overlay de inmediato (`showDialog`, como cualquier
      // "Eliminar físicamente"), los dos overlays cerrándose/abriendo
      // en el mismo frame corrompen el árbol de Elements y Flutter
      // lanza "InheritedElement: '_dependents.isEmpty': is not true".
      // Esperar un frame deja que el menú termine de desmontarse
      // primero — imperceptible para quien usa la app.
      onSelected: (accion) => WidgetsBinding.instance.addPostFrameCallback((_) => accion()),
      itemBuilder: (_) => [
        for (final accion in actions)
          PopupMenuItem<VoidCallback>(
            key: accion.key,
            value: accion.onTap,
            enabled: accion.onTap != null,
            child: Row(
              children: [
                if (accion.icon != null) ...[
                  Icon(accion.icon, size: 18, color: accion.destructive ? colors.error : colors.textMuted),
                  const SizedBox(width: 12),
                ],
                Flexible(
                  child: Text(
                    accion.label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: accion.destructive ? colors.error : colors.textPrimary),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
