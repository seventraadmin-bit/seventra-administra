import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/tokens/app_color_scheme.dart';
import '../../../core/design_system/tokens/app_radius.dart';
import '../../../core/design_system/tokens/app_spacing.dart';
import '../../../core/design_system/tokens/app_typography.dart';
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
              _SearchControl(compact: compactSearch),
              const SizedBox(width: AppSpacing.xs),
              _ThemeSelector(
                mode: themeMode,
                onChanged: (mode) => ref.read(themeModeControllerProvider.notifier).setThemeMode(mode),
              ),
              const SizedBox(width: AppSpacing.xxs),
              const _NotificationsButton(),
              const SizedBox(width: AppSpacing.xxs),
              _ProfileChip(compact: compactProfile),
            ],
          );
        },
      ),
    );
  }
}

class _SearchControl extends StatelessWidget {
  const _SearchControl({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).extension<AppColorScheme>()!;

    if (compact) {
      return IconButton(
        key: const Key('top_bar_search'),
        tooltip: l10n.shellSearchTooltip,
        icon: const Icon(Icons.search),
        onPressed: () {},
      );
    }

    // Sin relleno, solo un borde sutil: el fondo lleno anterior competía
    // demasiado con el resto de la barra. Discreto no significa oculto —
    // sigue siendo claramente un campo de búsqueda, solo no grita.
    final border = OutlineInputBorder(
      borderRadius: AppRadius.mdRadius,
      borderSide: BorderSide(color: colors.borderSubtle),
    );

    return ConstrainedBox(
      key: const Key('top_bar_search'),
      constraints: const BoxConstraints(maxWidth: 300, minWidth: 160),
      child: SizedBox(
        height: 36,
        child: TextField(
          readOnly: true,
          style: AppTypography.body.copyWith(color: colors.textMuted),
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: Icon(Icons.search, size: 18, color: colors.textMuted),
            prefixIconConstraints: const BoxConstraints(minWidth: 34, minHeight: 34),
            contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            hintText: l10n.shellSearchTooltip,
            hintStyle: AppTypography.body.copyWith(color: colors.textMuted),
            filled: false,
            border: border,
            enabledBorder: border,
          ),
        ),
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

class _NotificationsButton extends StatelessWidget {
  const _NotificationsButton();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return IconButton(
      key: const Key('top_bar_notifications'),
      tooltip: l10n.shellNotificationsTooltip,
      icon: const Icon(Icons.notifications_outlined),
      onPressed: () {},
    );
  }
}

class _ProfileChip extends StatelessWidget {
  const _ProfileChip({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).extension<AppColorScheme>()!;

    return Tooltip(
      message: l10n.shellProfileTooltip,
      child: Container(
        key: const Key('top_bar_profile'),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircleAvatar(radius: 16, child: Icon(Icons.person_outline, size: 18)),
            if (!compact) ...[
              const SizedBox(width: AppSpacing.xs),
              Text(
                l10n.shellProfilePlaceholderName,
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
