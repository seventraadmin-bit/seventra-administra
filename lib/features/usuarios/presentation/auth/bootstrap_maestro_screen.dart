import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import '../../../respaldo/presentation/widgets/recuperar_portable_accion.dart';
import '../../domain/usecases/crear_primer_maestro_usecase.dart';
import '../../usuarios_providers.dart';
import 'widgets/auth_identity_panel.dart';

const _anchoDosZonas = 900.0;

/// Alta del primer Usuario Maestro (Etapa 11A, rediseño Etapa 15) —
/// solo alcanzable mientras la base de datos no tiene ningún Usuario
/// (ver el `redirect` de `createAppRouter`); una vez creado, esta ruta
/// queda bloqueada permanentemente. Sin contraseña hardcodeada: la
/// persona frente al teclado la define aquí mismo. Comparte la
/// identidad visual del Login (`AuthIdentityPanel`) pero **nunca**
/// lleva "Recuérdame en este equipo" — es alta, no inicio de sesión;
/// las dos pantallas siguen siendo flujos separados.
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

    final formulario = RisegCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
            Text(l10n.bootstrapMaestroTitulo, style: AppTypography.heading2.copyWith(color: colors.textPrimary)),
            const SizedBox(height: AppSpacing.xs),
            Text(l10n.bootstrapMaestroSubtitulo, style: AppTypography.body.copyWith(color: colors.textMuted)),
            const SizedBox(height: AppSpacing.xl),
            RisegTextField(
              key: const Key('bootstrap_campo_nombre'),
              label: l10n.bootstrapMaestroCampoNombre,
              controller: _nombreCtrl,
              prefixIcon: Icons.badge_outlined,
              autofocus: true,
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(
              key: const Key('bootstrap_campo_usuario'),
              label: l10n.loginCampoUsuario,
              controller: _usuarioCtrl,
              prefixIcon: Icons.person_outline,
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(
              key: const Key('bootstrap_campo_password'),
              label: l10n.loginCampoContrasena,
              controller: _passwordCtrl,
              prefixIcon: Icons.lock_outline,
              obscureText: true,
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(
              key: const Key('bootstrap_campo_confirmar_password'),
              label: l10n.bootstrapMaestroCampoConfirmarContrasena,
              controller: _confirmarCtrl,
              prefixIcon: Icons.lock_outline,
              obscureText: true,
              onSubmitted: _creando ? null : (_) => _crear(),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(_error!, style: AppTypography.caption.copyWith(color: colors.error)),
            ],
            const SizedBox(height: AppSpacing.xl),
            RisegButton(
              key: const Key('bootstrap_boton_crear'),
              label: l10n.bootstrapMaestroBotonCrear,
              loading: _creando,
              onPressed: _creando ? null : _crear,
            ),
            // La otra salida de esta pantalla (Etapa 4D).
            //
            // Aquí llega alguien cuya computadora se destruyó: la
            // instalación está vacía, no hay ningún usuario, y lo único
            // que trae es su respaldo portable. Si esto no estuviera
            // aquí, tendría que crear un Maestro para poder entrar a
            // Configuración y recuperar — y entonces la instalación ya no
            // estaría vacía, con lo que la recuperación reemplazaría
            // datos recién creados. Se ofrece antes de crear nada.
            const SizedBox(height: AppSpacing.xxl),
            Divider(color: colors.borderSubtle),
            const SizedBox(height: AppSpacing.lg),
            Text(l10n.portableBienvenidaYaTeniasTitulo, style: AppTypography.bodyStrong),
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.portableBienvenidaYaTeniasMensaje,
              style: AppTypography.body.copyWith(color: colors.textMuted),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegButton(
              key: const Key('bootstrap_boton_recuperar_portable'),
              label: l10n.portableBienvenidaBotonRecuperar,
              variant: RisegButtonVariant.secondary,
              onPressed: _creando ? null : () => recuperarDesdePaquetePortable(context, ref),
            ),
        ],
      ),
    );

    return Scaffold(
      key: const Key('bootstrap_maestro_screen'),
      backgroundColor: colors.surface,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= _anchoDosZonas) {
              return Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: AuthIdentityPanel(
                      bienvenidaTitulo: l10n.bootstrapBienvenidaTitulo,
                      bienvenidaMensaje: l10n.bootstrapBienvenidaMensaje,
                    ),
                  ),
                  Expanded(
                    flex: 5,
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(AppSpacing.xxl),
                        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: formulario),
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
                    Image.asset('assets/images/logo.png', height: 56, fit: BoxFit.contain),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      l10n.appTitle,
                      textAlign: TextAlign.center,
                      style: AppTypography.heading2.copyWith(color: colors.textPrimary),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
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
