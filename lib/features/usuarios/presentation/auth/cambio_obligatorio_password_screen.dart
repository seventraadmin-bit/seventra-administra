import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import '../../domain/usecases/cambiar_contrasena_usuario_usecase.dart';
import '../sesion_controller.dart';

/// Cambio obligatorio de contraseña (Etapa "Usuarios, permisos y UX de
/// seguridad") — la única pantalla alcanzable mientras
/// `SesionUsuario.debeCambiarPassword` sea `true`.
///
/// Vive FUERA del `StatefulShellRoute`, igual que `/login`: no hay
/// sidebar, ni barra superior, ni forma de navegar a otra parte. El
/// candado real no es esta pantalla sino el `redirect` del router, que
/// devuelve aquí cualquier otra ruta — así ninguna pantalla del sistema
/// llega siquiera a construirse con una contraseña que conoce alguien
/// más.
///
/// Salidas posibles, ambas deliberadas:
///  - cambiar la contraseña (sigue a `/dashboard`);
///  - cerrar sesión (vuelve a `/login`) — nunca se deja a alguien
///    atrapado sin poder salir.
class CambioObligatorioPasswordScreen extends ConsumerStatefulWidget {
  const CambioObligatorioPasswordScreen({super.key});

  @override
  ConsumerState<CambioObligatorioPasswordScreen> createState() => _CambioObligatorioPasswordScreenState();
}

class _CambioObligatorioPasswordScreenState extends ConsumerState<CambioObligatorioPasswordScreen> {
  final _passwordCtrl = TextEditingController();
  final _confirmarCtrl = TextEditingController();
  String? _errorPassword;
  String? _errorConfirmar;
  bool _guardando = false;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmarCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final l10n = AppLocalizations.of(context)!;

    if (_passwordCtrl.text.length < 8) {
      setState(() => _errorPassword = l10n.cambioObligatorioErrorCorta);
      return;
    }
    if (_passwordCtrl.text != _confirmarCtrl.text) {
      setState(() => _errorConfirmar = l10n.usuarioErrorContrasenasNoCoinciden);
      return;
    }

    setState(() {
      _guardando = true;
      _errorPassword = null;
      _errorConfirmar = null;
    });

    final resultado = await ref.read(cambiarMiContrasenaProvider)(_passwordCtrl.text);
    if (!mounted) return;

    switch (resultado) {
      case CambiarContrasenaUsuarioExitoso():
        // `cambiarMiContrasenaProvider` ya apagó el candado en la sesión
        // viva, así que el `redirect` deja pasar a partir de aquí.
        context.go('/dashboard');
      case CambiarContrasenaUsuarioInvalida():
        setState(() {
          _guardando = false;
          _errorPassword = l10n.cambioObligatorioErrorCorta;
        });
      case CambiarContrasenaUsuarioNoExiste():
      case CambiarContrasenaUsuarioErrorInesperado():
        setState(() => _guardando = false);
        RisegFeedback.showError(context, l10n.usuarioErrorInesperado);
    }
  }

  void _cerrarSesion() {
    ref.read(sesionControllerProvider.notifier).logout();
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.canvas,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: RisegCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.lock_reset_outlined, size: 22, color: colors.warning),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(l10n.cambioObligatorioTitulo, style: AppTypography.heading2),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    l10n.cambioObligatorioMensaje,
                    style: AppTypography.body.copyWith(color: colors.textMuted),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  RisegTextField(
                    key: const Key('cambio_obligatorio_nueva'),
                    label: l10n.cambioObligatorioCampoNueva,
                    controller: _passwordCtrl,
                    obscureText: true,
                    autofocus: true,
                    errorText: _errorPassword,
                    onChanged: (_) => setState(() => _errorPassword = null),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  RisegTextField(
                    key: const Key('cambio_obligatorio_confirmar'),
                    label: l10n.cambioObligatorioCampoConfirmar,
                    controller: _confirmarCtrl,
                    obscureText: true,
                    errorText: _errorConfirmar,
                    onChanged: (_) => setState(() => _errorConfirmar = null),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  // `Wrap` y no `Row`: a 500px de ancho las dos acciones
                  // pasan a dos renglones en vez de desbordar.
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    children: [
                      RisegButton(
                        key: const Key('cambio_obligatorio_cerrar_sesion'),
                        label: l10n.shellCerrarSesion,
                        variant: RisegButtonVariant.ghost,
                        onPressed: _guardando ? null : _cerrarSesion,
                      ),
                      RisegButton(
                        key: const Key('cambio_obligatorio_guardar'),
                        label: l10n.cambioObligatorioBoton,
                        onPressed: _guardando ? null : _guardar,
                      ),
                    ],
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
