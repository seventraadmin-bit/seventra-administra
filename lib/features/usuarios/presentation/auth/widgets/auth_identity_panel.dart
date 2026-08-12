import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

/// Panel izquierdo de identidad, compartido por Login y por el
/// bootstrap del primer Maestro (Etapa 15) — mismo logotipo real
/// (`assets/images/logo.png`, ya usado en el sidebar) y mismo fondo
/// (degradado azul institucional + un par de formas geométricas muy
/// sutiles), sin ninguna imagen generada ni fotografía. Cada pantalla
/// aporta su propio mensaje de bienvenida — el panel nunca decide *qué*
/// se está haciendo, solo *quién* es RISEG ONE.
class AuthIdentityPanel extends StatelessWidget {
  const AuthIdentityPanel({required this.bienvenidaTitulo, required this.bienvenidaMensaje, super.key});

  final String bienvenidaTitulo;
  final String bienvenidaMensaje;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.accent700, AppColors.accent500],
        ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: -80,
            right: -80,
            child: _formaDecorativa(220),
          ),
          Positioned(
            bottom: -100,
            left: -60,
            child: _formaDecorativa(260),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.max,
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: const BoxDecoration(color: Colors.white, borderRadius: AppRadius.mdRadius),
                  child: Image.asset('assets/images/logo.png', key: const Key('auth_logo'), height: 52, fit: BoxFit.contain),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(l10n.appTitle, style: AppTypography.heading1.copyWith(color: Colors.white)),
                const SizedBox(height: AppSpacing.xxs),
                Text(l10n.appSubtitle, style: AppTypography.body.copyWith(color: Colors.white.withValues(alpha: 0.85))),
                const Spacer(),
                Text(bienvenidaTitulo, style: AppTypography.heading2.copyWith(color: Colors.white)),
                const SizedBox(height: AppSpacing.xs),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Text(bienvenidaMensaje, style: AppTypography.body.copyWith(color: Colors.white.withValues(alpha: 0.85))),
                ),
                // Margen inferior extra, solo para el bloque de
                // bienvenida — el resto del panel no cambia.
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _formaDecorativa(double diametro) {
    return IgnorePointer(
      child: Container(
        width: diametro,
        height: diametro,
        decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.06)),
      ),
    );
  }
}
