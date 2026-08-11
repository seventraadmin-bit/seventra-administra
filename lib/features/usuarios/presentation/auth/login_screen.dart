import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import '../sesion_controller.dart';
import '../../domain/usecases/login_usecase.dart';

/// Pantalla de inicio de sesión (Etapa 11A) — fuera del Shell, sin
/// sidebar. Errores de credenciales siempre muestran el mismo mensaje
/// genérico (ver `LoginCredencialesInvalidas`): nunca se revela si el
/// usuario existe o si fue la contraseña la que falló.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _usuarioCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  String? _error;
  bool _entrando = false;

  @override
  void dispose() {
    _usuarioCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _entrando = true;
      _error = null;
    });

    final resultado = await ref.read(sesionControllerProvider.notifier).login(
          nombreUsuario: _usuarioCtrl.text,
          password: _passwordCtrl.text,
        );
    if (!mounted) return;

    switch (resultado) {
      case LoginExitoso():
        context.go('/dashboard');
      case LoginCredencialesInvalidas():
        setState(() {
          _entrando = false;
          _error = l10n.loginErrorCredencialesInvalidas;
        });
      case LoginUsuarioInactivo():
        setState(() {
          _entrando = false;
          _error = l10n.loginErrorUsuarioInactivo;
        });
      case LoginErrorInesperado():
        setState(() {
          _entrando = false;
          _error = l10n.loginErrorInesperado;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    return Scaffold(
      key: const Key('login_screen'),
      backgroundColor: colors.surface,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: RisegCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.appTitle,
                    textAlign: TextAlign.center,
                    style: AppTypography.heading2.copyWith(color: colors.textPrimary),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  RisegTextField(
                    key: const Key('login_campo_usuario'),
                    label: l10n.loginCampoUsuario,
                    controller: _usuarioCtrl,
                    autofocus: true,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  RisegTextField(
                    key: const Key('login_campo_password'),
                    label: l10n.loginCampoContrasena,
                    controller: _passwordCtrl,
                    obscureText: true,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(_error!, style: AppTypography.caption.copyWith(color: colors.error)),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  RisegButton(
                    key: const Key('login_boton_entrar'),
                    label: l10n.loginBotonEntrar,
                    onPressed: _entrando ? null : _entrar,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
