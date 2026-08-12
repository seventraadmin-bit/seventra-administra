import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/tokens/app_color_scheme.dart';
import '../../../core/design_system/tokens/app_spacing.dart';
import '../../../core/design_system/tokens/app_typography.dart';
import '../../../features/busqueda/presentation/widgets/global_search_field.dart';
import '../../../features/notificaciones/presentation/widgets/notification_bell.dart';
import '../../../features/usuarios/presentation/sesion_controller.dart';
import '../../theme/theme_mode_controller.dart';
import '../shell_breakpoints.dart';
import 'app_breadcrumb.dart';

/// Barra superior fija del Shell.
///
/// Orden de prioridad en anchos reducidos (de más a menos protegido):
/// 1. Breadcrumb/contexto — nunca se oculta, solo trunca con elipsis.
/// 2. Acciones esenciales — ninguna todavía en esta etapa.
/// 3. Selector de tema — siempre visible, ya es un ícono mínimo.
/// 4. Notificaciones — siempre visible, ya es un ícono mínimo.
/// 5. Perfil — oculta el nombre primero, conserva el avatar.
/// 6. Búsqueda — la primera en sacrificarse: se reduce a un botón de ícono.
class AppTopBar extends ConsumerWidget {
  const AppTopBar({required this.breadcrumbSegments, super.key});

  final List<BreadcrumbSegment> breadcrumbSegments;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final themeMode = ref.watch(themeModeControllerProvider);

    return Container(
      key: const Key('app_top_bar'),
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compactSearch = constraints.maxWidth < ShellBreakpoints.topBarSearchCompact;
          final compactProfile = constraints.maxWidth < ShellBreakpoints.topBarProfileCompact;

          return Row(
            children: [
              Expanded(child: AppBreadcrumb(segments: breadcrumbSegments)),
              const SizedBox(width: AppSpacing.md),
              GlobalSearchField(compact: compactSearch),
              const SizedBox(width: AppSpacing.xs),
              _ThemeSelector(
                mode: themeMode,
                onChanged: (mode) => ref.read(themeModeControllerProvider.notifier).setThemeMode(mode),
              ),
              const SizedBox(width: AppSpacing.xxs),
              const NotificationBell(),
              const SizedBox(width: AppSpacing.xxs),
              _ProfileChip(compact: compactProfile),
            ],
          );
        },
      ),
    );
  }
}

class _ThemeSelector extends StatelessWidget {
  const _ThemeSelector({required this.mode, required this.onChanged});

  final ThemeMode mode;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final icon = switch (mode) {
      ThemeMode.light => Icons.light_mode_outlined,
      ThemeMode.dark => Icons.dark_mode_outlined,
      ThemeMode.system => Icons.brightness_auto_outlined,
    };

    return PopupMenuButton<ThemeMode>(
      key: const Key('top_bar_theme_selector'),
      tooltip: l10n.themeModeLabel,
      icon: Icon(icon),
      initialValue: mode,
      onSelected: onChanged,
      itemBuilder: (context) => [
        PopupMenuItem(value: ThemeMode.light, child: Text(l10n.themeModeLight)),
        PopupMenuItem(value: ThemeMode.dark, child: Text(l10n.themeModeDark)),
        PopupMenuItem(value: ThemeMode.system, child: Text(l10n.themeModeSystem)),
      ],
    );
  }
}

/// Muestra el usuario autenticado (Etapa 11A) — antes mostraba un
/// nombre de relleno fijo (`shellProfilePlaceholderName`), ahora lee la
/// sesión real. `sesion` solo es `null` en el instante entre perder la
/// sesión y que el `redirect` del router complete la navegación a
/// `/login`, así que el relleno queda como último recurso, no como el
/// caso normal.
class _ProfileChip extends ConsumerWidget {
  const _ProfileChip({required this.compact});

  final bool compact;

  void _cerrarSesion(BuildContext context, WidgetRef ref) {
    ref.read(sesionControllerProvider.notifier).logout();
    context.go('/login');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).extension<AppColorScheme>()!;
    final sesion = ref.watch(sesionControllerProvider);
    final nombre = sesion?.nombre ?? l10n.shellProfilePlaceholderName;

    return PopupMenuButton<void>(
      key: const Key('top_bar_profile'),
      tooltip: l10n.shellProfileTooltip,
      // `itemBuilder` recibe su propio `BuildContext` (el de la ruta
      // efímera del menú emergente, que Flutter cierra apenas `onTap`
      // retorna) — deliberadamente descartado aquí (`_`) para no
      // sombrear el `context` estable de `_ProfileChip` mismo. Un
      // intento anterior de esta misma etapa hizo `_cerrarSesion` async
      // (esperando a que "Recuérdame en este equipo" terminara de
      // limpiarse) usando ese contexto efímero — para cuando el `await`
      // se resolvía, ya estaba desmontado y la navegación a `/login`
      // nunca ocurría (bug real, encontrado por la suite). La limpieza
      // de la sesión recordada ahora es best-effort en segundo plano
      // (ver `SesionController.logout`), así que `_cerrarSesion` volvió
      // a ser síncrono, pero se conserva el contexto estable de todas
      // formas — es la referencia correcta aquí, sea síncrono o no.
      itemBuilder: (_) => [
        PopupMenuItem<void>(
          key: const Key('top_bar_cerrar_sesion'),
          onTap: () => _cerrarSesion(context, ref),
          child: Text(l10n.shellCerrarSesion),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircleAvatar(radius: 16, child: Icon(Icons.person_outline, size: 18)),
            if (!compact) ...[
              const SizedBox(width: AppSpacing.xs),
              Text(
                nombre,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
