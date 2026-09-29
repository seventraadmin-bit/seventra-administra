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
    final colors = Theme.of(context).extension<AppColorScheme>()!;
    final themeMode = ref.watch(themeModeControllerProvider);

    // Etapa 16, evolución visual: la barra superior es la única
    // superficie de RISEG ONE que se pinta con el azul institucional
    // como FONDO — identidad de marca reconocible aun sin el logotipo
    // (visible en el sidebar). Sin borde inferior: el bloque de color en
    // sí ya separa la barra del sidebar/área de contenido, un divisor
    // encima solo competiría con el azul.
    return Container(
      key: const Key('app_top_bar'),
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      // Superficie neutra. El Azul Administra se reserva para acciones y
      // estados seleccionados; vestir con él toda la barra pertenecía a la
      // identidad anterior.
      color: colors.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compactSearch = constraints.maxWidth < ShellBreakpoints.topBarSearchCompact;
          final compactProfile = constraints.maxWidth < ShellBreakpoints.topBarProfileCompact;

          return Row(
            children: [
              Expanded(
                child: AppBreadcrumb(
                  segments: breadcrumbSegments,
                  activeColor: colors.textPrimary,
                  mutedColor: colors.textMuted,
                ),
              ),
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
    final colors = Theme.of(context).extension<AppColorScheme>()!;
    final icon = switch (mode) {
      ThemeMode.light => Icons.light_mode_outlined,
      ThemeMode.dark => Icons.dark_mode_outlined,
      ThemeMode.system => Icons.brightness_auto_outlined,
    };

    // El menú emergente en sí queda con su Material blanco/oscuro normal
    // (no vive "sobre" la barra azul, flota encima) — solo el ícono
    // disparador necesita los tokens de Shell.
    return PopupMenuButton<ThemeMode>(
      key: const Key('top_bar_theme_selector'),
      tooltip: l10n.themeModeLabel,
      icon: Icon(icon, color: colors.textMuted),
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

  // IF-5 — «Cambiar mi contraseña» se retiró de este menú.
  //
  // Tras el cutover la identidad de la sesión NO tiene contraseña local: su
  // fila proyectada guarda un centinela que ningún verificador acepta. Un
  // control que escribiera un hash local seguiría existiendo y no serviría para
  // entrar, que es la peor clase de control — el que parece funcionar.
  //
  // La contraseña vive en el backend y se cambia por el enlace «¿Olvidaste tu
  // contraseña?» del propio login, que usa el ciclo de correo ya probado.

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).extension<AppColorScheme>()!;
    final sesion = ref.watch(sesionControllerProvider);
    final nombre = sesion?.nombre ?? l10n.shellProfilePlaceholderName;
    // Para un Maestro se dice el tipo de cuenta, discretamente; para el
    // resto, su nombre de usuario. Nunca se inventa un puesto que la
    // sesión no trae.
    final subtitulo = sesion == null
        ? null
        : (sesion.esMaestro ? l10n.shellCuentaMaestro : sesion.nombreUsuario);

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
        // Encabezado de identidad (Etapa "Usuarios, permisos y UX de
        // seguridad"): el menú anterior era un popup suelto con una sola
        // línea, sin decir siquiera de quién era la sesión. `enabled:
        // false` lo vuelve puramente informativo — no es una acción.
        PopupMenuItem<void>(
          key: const Key('top_bar_identidad'),
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(nombre, style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary), overflow: TextOverflow.ellipsis),
              if (subtitulo != null)
                Text(subtitulo, style: AppTypography.caption.copyWith(color: colors.textMuted), overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<void>(
          key: const Key('top_bar_cerrar_sesion'),
          onTap: () => _cerrarSesion(context, ref),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.logout_outlined, size: 18, color: colors.textMuted),
              const SizedBox(width: AppSpacing.xs),
              Flexible(child: Text(l10n.shellCerrarSesion, overflow: TextOverflow.ellipsis)),
            ],
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: colors.accentSoftBg,
              child: Icon(Icons.person_outline, size: 18, color: colors.accentText),
            ),
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
