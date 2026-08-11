import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import '../../domain/usecases/crear_primer_maestro_usecase.dart';
import '../../usuarios_providers.dart';

/// Alta del primer Usuario Maestro (Etapa 11A) — solo alcanzable
/// mientras la base de datos no tiene ningún Usuario (ver el `redirect`
/// de `createAppRouter`); una vez creado, esta ruta queda bloqueada
/// permanentemente. Sin contraseña hardcodeada: la persona frente al
/// teclado la define aquí mismo.
class BootstrapMaestroScreen extends ConsumerStatefulWidget {
  const BootstrapMaestroScreen({super.key});

  @override
  ConsumerState<BootstrapMaestroScreen> createState() => _BootstrapMaestroScreenState();
}

class _BootstrapMaestroScreenState extends ConsumerState<BootstrapMaestroScreen> {
  final _nombreCtrl = TextEditingController();
  final _usuarioCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmarCtrl = TextEditingController();
  String? _error;
  bool _creando = false;

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _usuarioCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmarCtrl.dispose();
    super.dispose();
  }

  Future<void> _crear() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _creando = true;
      _error = null;
    });

    final resultado = await ref.read(crearPrimerMaestroUseCaseProvider).ejecutar(
          nombre: _nombreCtrl.text,
          nombreUsuario: _usuarioCtrl.text,
          password: _passwordCtrl.text,
          confirmarPassword: _confirmarCtrl.text,
        );
    if (!mounted) return;

    switch (resultado) {
      case CrearPrimerMaestroExitoso():
        ref.invalidate(contarUsuariosProvider);
        RisegFeedback.showSuccess(context, l10n.bootstrapMaestroExito);
        context.go('/login');
      case CrearPrimerMaestroYaExisteUnUsuario():
        setState(() {
          _creando = false;
          _error = l10n.bootstrapMaestroYaExisteUsuario;
        });
      case CrearPrimerMaestroNombreRequerido():
        setState(() {
          _creando = false;
          _error = l10n.bootstrapMaestroNombreRequerido;
        });
      case CrearPrimerMaestroNombreUsuarioRequerido():
        setState(() {
          _creando = false;
          _error = l10n.bootstrapMaestroNombreUsuarioRequerido;
        });
      case CrearPrimerMaestroContrasenaInvalida():
        setState(() {
          _creando = false;
          _error = l10n.bootstrapMaestroContrasenaInvalida;
        });
      case CrearPrimerMaestroContrasenasNoCoinciden():
        setState(() {
          _creando = false;
          _error = l10n.bootstrapMaestroContrasenasNoCoinciden;
        });
      case CrearPrimerMaestroErrorInesperado():
        setState(() {
          _creando = false;
          _error = l10n.bootstrapMaestroErrorInesperado;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    return Scaffold(
      key: const Key('bootstrap_maestro_screen'),
      backgroundColor: colors.surface,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: RisegCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.bootstrapMaestroTitulo,
                    textAlign: TextAlign.center,
                    style: AppTypography.heading2.copyWith(color: colors.textPrimary),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    l10n.bootstrapMaestroSubtitulo,
                    textAlign: TextAlign.center,
                    style: AppTypography.body.copyWith(color: colors.textMuted),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  RisegTextField(
                    key: const Key('bootstrap_campo_nombre'),
                    label: l10n.bootstrapMaestroCampoNombre,
                    controller: _nombreCtrl,
                    autofocus: true,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  RisegTextField(
                    key: const Key('bootstrap_campo_usuario'),
                    label: l10n.loginCampoUsuario,
                    controller: _usuarioCtrl,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  RisegTextField(
                    key: const Key('bootstrap_campo_password'),
                    label: l10n.loginCampoContrasena,
                    controller: _passwordCtrl,
                    obscureText: true,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  RisegTextField(
                    key: const Key('bootstrap_campo_confirmar_password'),
                    label: l10n.bootstrapMaestroCampoConfirmarContrasena,
                    controller: _confirmarCtrl,
                    obscureText: true,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(_error!, style: AppTypography.caption.copyWith(color: colors.error)),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  RisegButton(
                    key: const Key('bootstrap_boton_crear'),
                    label: l10n.bootstrapMaestroBotonCrear,
                    onPressed: _creando ? null : _crear,
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
