import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/core/auth/auth_providers.dart';
import 'package:riseg_one/core/branding/marca_producto.dart';
import 'package:riseg_one/core/design_system/design_system.dart';

import '../../../respaldo/presentation/widgets/recuperar_portable_accion.dart';

import '../sesion_controller.dart';
import '../../domain/login_resultado.dart';
import 'widgets/auth_identity_panel.dart';

/// Ancho mínimo para la composición de dos zonas (identidad + login).
/// Por debajo de esto la zona decorativa se oculta por completo — mismo
/// criterio de `AppBreakpoints` (uso general, no `ShellBreakpoints`,
/// exclusivo del Shell autenticado).
const _anchoDosZonas = 900.0;

/// Pantalla de inicio de sesión (Etapa 11A, rediseño Etapa 15) — fuera
/// del Shell, sin sidebar. Errores de credenciales siempre muestran el
/// mismo mensaje genérico (ver `LoginCredencialesInvalidas`): nunca se
/// revela si el usuario existe o si fue la contraseña la que falló.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _usuarioCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _passwordVisible = false;
  String? _error;
  bool _entrando = false;

  @override
  void dispose() {
    _usuarioCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _entrar([String? _]) async {
    final l10n = AppLocalizations.of(context)!;

    if (_usuarioCtrl.text.trim().isEmpty) {
      setState(() => _error = l10n.loginErrorUsuarioRequerido);
      return;
    }
    if (_passwordCtrl.text.isEmpty) {
      setState(() => _error = l10n.loginErrorContrasenaRequerida);
      return;
    }

    setState(() {
      _entrando = true;
      _error = null;
    });

    final resultado = await ref.read(sesionControllerProvider.notifier).login(
          correo: _usuarioCtrl.text,
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
      case LoginUsuarioInactivo(:final mensaje):
        setState(() {
          _entrando = false;
          // El backend distingue «verifica tu correo» de «cuenta suspendida» y
          // de «demasiados intentos», y esa distinción sólo le llega a quien ya
          // acertó su contraseña. Se muestra tal cual la redacta el servidor.
          _error = mensaje ?? l10n.loginErrorUsuarioInactivo;
        });
      case LoginSinCompany():
        setState(() {
          _entrando = false;
          _error = l10n.loginSinCompany;
        });
      case LoginErrorInesperado():
        setState(() {
          _entrando = false;
          _error = l10n.loginErrorInesperado;
        });
    }
  }

  /// Dispara el correo de restablecimiento que ya existe en el backend.
  ///
  /// No abre un navegador ni reconstruye nada: el enlace, la página y el token
  /// de un solo uso son los de Identity Completion. Esto sólo pide el envío, y
  /// responde SIEMPRE lo mismo —exista o no la cuenta—, porque el servidor
  /// también responde siempre lo mismo y contradecirlo aquí convertiría la
  /// pantalla en el oráculo que él evita.
  Future<void> _recuperarContrasena() async {
    final l10n = AppLocalizations.of(context)!;

    if (_usuarioCtrl.text.trim().isEmpty) {
      setState(() => _error = l10n.loginErrorUsuarioRequerido);
      return;
    }

    setState(() {
      _entrando = true;
      _error = null;
    });

    await ref.read(authApiProvider).solicitarRestablecimiento(email: _usuarioCtrl.text.trim());
    if (!mounted) return;

    setState(() => _entrando = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: const Key('login_recuperacion_enviada'),
        content: Text(l10n.loginRecuperacionEnviada),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    return Scaffold(
      key: const Key('login_screen'),
      backgroundColor: colors.surface,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final dosZonas = constraints.maxWidth >= _anchoDosZonas;
            final formulario = _LoginForm(
              usuarioCtrl: _usuarioCtrl,
              passwordCtrl: _passwordCtrl,
              passwordVisible: _passwordVisible,
              onTogglePasswordVisible: () => setState(() => _passwordVisible = !_passwordVisible),
              error: _error,
              entrando: _entrando,
              onSubmit: _entrar,
              onOlvideContrasena: _recuperarContrasena,
              onRecuperarPortable: (ctx) => recuperarDesdePaquetePortable(ctx, ref),
            );

            if (dosZonas) {
              return Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: AuthIdentityPanel(
                      bienvenidaTitulo: l10n.loginBienvenidaTitulo,
                      bienvenidaMensaje: l10n.loginBienvenidaMensaje,
                    ),
                  ),
                  Expanded(
                    flex: 5,
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(AppSpacing.xxl),
                        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 380), child: formulario),
                      ),
                    ),
                  ),
                ],
              );
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - AppSpacing.xl * 2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const LogotipoProducto(key: Key('login_logo'), ancho: 260),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      l10n.appSubtitle,
                      textAlign: TextAlign.center,
                      style: AppTypography.body.copyWith(color: colors.textMuted),
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    formulario,
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _LoginForm extends StatelessWidget {
  const _LoginForm({
    required this.usuarioCtrl,
    required this.passwordCtrl,
    required this.passwordVisible,
    required this.onTogglePasswordVisible,
    required this.error,
    required this.entrando,
    required this.onSubmit,
    required this.onOlvideContrasena,
    required this.onRecuperarPortable,
  });

  final TextEditingController usuarioCtrl;
  final TextEditingController passwordCtrl;
  final bool passwordVisible;
  final VoidCallback onTogglePasswordVisible;
  final String? error;
  final bool entrando;
  final ValueChanged<String> onSubmit;
  final VoidCallback onOlvideContrasena;
  final void Function(BuildContext) onRecuperarPortable;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    return RisegCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.loginTitulo, style: AppTypography.heading2.copyWith(color: colors.textPrimary)),
            const SizedBox(height: AppSpacing.xxs),
            // Un poco más de contraste que `textMuted` (mezcla con
            // `textPrimary`, sin introducir un color nuevo a la
            // paleta) — pedido explícito de Marlon tras revisar el
            // Login real.
            Text(l10n.loginSubtitulo, style: AppTypography.body.copyWith(color: colors.textPrimary.withValues(alpha: 0.75))),
            const SizedBox(height: AppSpacing.xl),
            RisegTextField(
              key: const Key('login_campo_usuario'),
              label: l10n.loginCampoUsuario,
              controller: usuarioCtrl,
              prefixIcon: Icons.person_outline,
              autofocus: true,
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(
              key: const Key('login_campo_password'),
              label: l10n.loginCampoContrasena,
              controller: passwordCtrl,
              prefixIcon: Icons.lock_outline,
              obscureText: !passwordVisible,
              onSubmitted: entrando ? null : onSubmit,
              suffixAction: IconButton(
                key: const Key('login_boton_mostrar_password'),
                tooltip: passwordVisible ? l10n.loginOcultarContrasena : l10n.loginMostrarContrasena,
                icon: Icon(passwordVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
                onPressed: onTogglePasswordVisible,
              ),
            ),
            // IF-5 — «Recuérdame en este equipo» desapareció, y no porque se
            // quitara la comodidad: el token de refresco se guarda SIEMPRE
            // cifrado en el almacén del sistema, así que la casilla ya no
            // decidía nada. Dejarla habría sido un control que miente.
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const Key('login_olvide_contrasena'),
                onPressed: entrando ? null : onOlvideContrasena,
                child: Text(l10n.loginOlvideContrasena, style: AppTypography.caption),
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(error!, style: AppTypography.caption.copyWith(color: colors.error)),
            ],
            const SizedBox(height: AppSpacing.lg),
            RisegButton(
              key: const Key('login_boton_entrar'),
              label: l10n.loginBotonEntrar,
              loading: entrando,
              onPressed: entrando ? null : () => onSubmit(passwordCtrl.text),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              l10n.loginAccesoProtegido,
              textAlign: TextAlign.center,
              style: AppTypography.caption.copyWith(color: colors.textMuted),
            ),
            // RECUPERACIÓN PORTABLE — la única puerta en un equipo nuevo.
            //
            // Vivía en el alta del primer Maestro, que IF-5 retiró. Sin moverla
            // aquí, la etapa 4D habría quedado inservible para lo único que se
            // construyó: la computadora se destruyó, no hay sesión que iniciar, y
            // la sección de Configuración exige precisamente una sesión.
            //
            // El login es su sitio natural desde el cutover: es LA pantalla que se
            // ve sin sesión.
            //
            // Va con su explicación, no sólo con el botón: quien acaba de perder
            // una computadora no sabe qué es «un respaldo portable», y un botón
            // suelto con ese nombre no le dice que puede recuperar su empresa.
            const SizedBox(height: AppSpacing.lg),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.md),
            Text(
              l10n.portableBienvenidaYaTeniasTitulo,
              style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              l10n.portableBienvenidaYaTeniasMensaje,
              style: AppTypography.caption.copyWith(color: colors.textMuted),
            ),
            const SizedBox(height: AppSpacing.sm),
            RisegButton(
              key: const Key('bootstrap_boton_recuperar_portable'),
              label: l10n.portableBienvenidaBotonRecuperar,
              variant: RisegButtonVariant.secondary,
              onPressed: entrando ? null : () => onRecuperarPortable(context),
            ),
        ],
      ),
    );
  }
}
