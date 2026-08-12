import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import '../notificaciones_controller.dart';
import 'notification_panel.dart';

const _grupoAncla = 'notification_bell_tap_region';

/// Campana de la barra superior (Etapa 14B) — reemplaza
/// `_NotificationsButton` decorativo. Mismo patrón de overlay que
/// `GlobalSearchField` (Búsqueda global, 14A): `CompositedTransformTarget`/
/// `OverlayPortal` anclado, `TapRegion` para cerrar al tocar fuera. Sin
/// modo compacto — la campana siempre cabe como ícono, a diferencia
/// del campo de búsqueda.
class NotificationBell extends ConsumerStatefulWidget {
  const NotificationBell({super.key});

  @override
  ConsumerState<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends ConsumerState<NotificationBell> {
  final _layerLink = LayerLink();
  final _overlayController = OverlayPortalController();

  void _alternar() {
    if (_overlayController.isShowing) {
      _overlayController.hide();
    } else {
      ref.read(notificacionesControllerProvider.notifier).recargar();
      _overlayController.show();
    }
  }

  void _seleccionar(String ruta) {
    _overlayController.hide();
    context.go(ruta);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final total = ref.watch(notificacionesControllerProvider.select((s) => s.total));
    final colors = context.colors;

    return TapRegion(
      groupId: _grupoAncla,
      onTapOutside: (_) => _overlayController.hide(),
      child: CompositedTransformTarget(
        link: _layerLink,
        child: OverlayPortal(
          controller: _overlayController,
          overlayChildBuilder: (context) => CompositedTransformFollower(
            link: _layerLink,
            targetAnchor: Alignment.bottomRight,
            followerAnchor: Alignment.topRight,
            offset: const Offset(0, 4),
            child: TapRegion(
              groupId: _grupoAncla,
              child: Align(
                alignment: Alignment.topRight,
                child: Material(
                  elevation: 4,
                  borderRadius: AppRadius.mdRadius,
                  color: colors.surface,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 300, maxWidth: 340),
                    child: NotificationPanel(onSelect: _seleccionar),
                  ),
                ),
              ),
            ),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                key: const Key('top_bar_notifications'),
                tooltip: l10n.shellNotificationsTooltip,
                icon: const Icon(Icons.notifications_outlined),
                onPressed: _alternar,
              ),
              if (total > 0)
                Positioned(
                  right: 4,
                  top: 4,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      constraints: const BoxConstraints(minWidth: 16),
                      decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                      child: Text(
                        total > 9 ? '9+' : '$total',
                        key: const Key('notification_bell_badge'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
