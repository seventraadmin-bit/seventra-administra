import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

import '../../core/design_system/design_system.dart';

/// Pantalla de bloqueo real (Etapa 11B) — a donde el `redirect` de
/// `createAppRouter` manda cualquier intento de navegar a una ruta cuyo
/// módulo el usuario no tiene permiso para ver. Deliberadamente fuera
/// del Shell (mismo nivel que `/login`): nunca construye ni muestra
/// contenido del módulo protegido, ni brevemente — el `redirect` corre
/// antes de que esa ruta llegue a construirse.
///
/// Único destino de salida: Dashboard, que no tiene permiso propio
/// (cualquier sesión válida entra) — así nunca hay un ciclo de
/// redirects si el usuario no tiene acceso a ningún otro módulo.
class AccesoDenegadoScreen extends StatelessWidget {
  const AccesoDenegadoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    return Scaffold(
      key: const Key('acceso_denegado_screen'),
      backgroundColor: colors.surface,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 48, color: colors.textMuted),
              const SizedBox(height: AppSpacing.md),
              Text(
                l10n.accesoDenegadoTitulo,
                style: AppTypography.heading2.copyWith(color: colors.textPrimary),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                l10n.accesoDenegadoMensaje,
                textAlign: TextAlign.center,
                style: AppTypography.body.copyWith(color: colors.textMuted),
              ),
              const SizedBox(height: AppSpacing.xl),
              RisegButton(
                key: const Key('acceso_denegado_boton_dashboard'),
                label: l10n.accesoDenegadoBotonDashboard,
                onPressed: () => context.go('/dashboard'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
