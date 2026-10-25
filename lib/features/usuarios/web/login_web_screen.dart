import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextInput;
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../core/auth/gestor_de_sesion.dart';
import '../../../core/design_system/design_system_web.dart';
import '../../../core/branding/marca_producto.dart';
import '../presentation/auth/widgets/auth_identity_panel.dart';
import 'mensajes_humanos.dart';

/// Ancho mínimo para la composición de dos zonas. **El mismo número que el login
/// del escritorio**, por el mismo motivo: por debajo, la zona decorativa se oculta
/// entera en vez de encogerse hasta no decir nada.
const double _anchoDosZonas = 900;

/// La entrada a Administra en el navegador.
///
/// ⚠️ **ES EL LOGIN DEL ESCRITORIO, NO UNO PARECIDO.** La primera versión de esta
/// pantalla componía su propia puerta —tarjeta centrada, logotipo propio, verde de
/// SEVENTRA— y estaba mal: el producto ya tenía una puerta diseñada, y la web tiene
/// que verse **igual**, no parecida.
///
/// Lo que se reutiliza tal cual:
///
///  · **[AuthIdentityPanel]**, el panel oscuro con la palomita recortada contra el
///    borde y el logotipo «SEVENTRA Administra» en blanco. Es un `StatelessWidget`
///    puro que recibe dos textos, así que se reutiliza sin tocarlo;
///  · **los textos**, de `AppLocalizations`: «Bienvenido a Seventra Administra»,
///    «Iniciar sesión», «Correo electrónico»… Los mismos literales, no copias que
///    con el tiempo divergen;
///  · **los componentes del Design System** para la tarjeta y los campos;
///  · **la proporción 4 : 5** entre el panel y el formulario, y el ancho máximo de
///    380 del formulario.
///
/// LO QUE NO SE TRAE, y es deliberado:
///
///  · 🚫 **«Recuperar desde un respaldo portable».** Lee un archivo del disco con
///    `dart:io`; en el navegador no existe ese camino, y además el respaldo
///    desaparece en la nube —respalda la base del servidor—;
///  · ⏳(D-29) **«¿Olvidaste tu contraseña?»**, que sigue pendiente de engancharse;
///  · 🚫 **«Recuérdame en este equipo»**, por la misma razón que la cookie `HttpOnly`
///    sigue pendiente: alargar la sesión en un navegador sin ella sería ampliar la
///    ventana de un token que JavaScript puede leer.
class LoginWebScreen extends StatefulWidget {
  const LoginWebScreen({required this.gestor, super.key});

  /// Se **recibe** por constructor y no se construye aquí: el trabajo de esta
  /// pantalla es recoger dos campos y mostrar el resultado.
  final GestorDeSesion gestor;

  @override
  State<LoginWebScreen> createState() => _LoginWebScreenState();
}

class _LoginWebScreenState extends State<LoginWebScreen> {
  final _correo = TextEditingController();
  final _contrasena = TextEditingController();
  final _focoContrasena = FocusNode();

  /// El mensaje de error, ya traducido a lenguaje de negocio. **Nunca un `Failure`**:
  /// si el estado guardara el fallo, el siguiente que pinte estaría a un `toString()`
  /// de filtrar un mensaje técnico a la pantalla.
  String? _error;
  String? _errorCorreo;
  String? _errorContrasena;

  bool _entrando = false;
  bool _verContrasena = false;

  @override
  void dispose() {
    // LIBERAR LOS CONTROLLERS NO ES OPCIONAL. En este proyecto ya costó una vez, y
    // `Future.delayed(300ms)` para «esperar la animación» está PROHIBIDO.
    _correo.dispose();
    _contrasena.dispose();
    _focoContrasena.dispose();
    super.dispose();
  }

  void _alternarContrasena() =>
      setState(() => _verContrasena = !_verContrasena);

  Future<void> _entrar() async {
    final l10n = AppLocalizations.of(context)!;
    final correo = _correo.text.trim();
    final contrasena = _contrasena.text;

    // LA VALIDACIÓN LOCAL NO ADIVINA SI EL CORREO EXISTE, sólo si hay algo escrito.
    // Mandar dos campos vacíos gastaría un viaje y consumiría cuota del limitador.
    final sinCorreo = correo.isEmpty;
    final sinContrasena = contrasena.isEmpty;

    if (sinCorreo || sinContrasena) {
      setState(() {
        _error = null;
        _errorCorreo = sinCorreo ? l10n.loginErrorUsuarioRequerido : null;
        _errorContrasena = sinContrasena
            ? l10n.loginErrorContrasenaRequerida
            : null;
      });
      return;
    }

    setState(() {
      _entrando = true;
      _error = null;
      _errorCorreo = null;
      _errorContrasena = null;
    });

    final resultado = await widget.gestor.iniciarSesion(
      email: correo,
      password: contrasena,
    );

    if (!mounted) return;

    resultado.when(
      // NO SE NAVEGA DESDE AQUÍ. El gestor publica `Autenticado` y el portón, que
      // observa ese estado, decide qué sigue.
      ok: (_) {
        // Lo que hace que el navegador ofrezca guardar la contraseña: en web el
        // motor mantiene un formulario oculto para el `AutofillGroup`, y esta
        // llamada es la que lo cierra. Va ANTES de limpiar el campo.
        TextInput.finishAutofillContext();
        _contrasena.clear();
        setState(() => _entrando = false);
      },
      failure: (fallo) => setState(() {
        _entrando = false;
        _error = MensajesHumanos.deLogin(fallo);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.surface,
      body: LayoutBuilder(
        builder: (context, limites) {
          final dosZonas = limites.maxWidth >= _anchoDosZonas;

          final formulario = ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: _Formulario(estado: this, l10n: l10n, colors: colors),
          );

          if (dosZonas) {
            return Row(
              children: [
                // LA MISMA PROPORCIÓN QUE EL ESCRITORIO: 4 de panel, 5 de
                // formulario. No es casual que el formulario sea el lado ancho.
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
                      child: formulario,
                    ),
                  ),
                ),
              ],
            );
          }

          // Angosto: el panel decorativo se va entero y queda el logotipo arriba,
          // igual que en el escritorio.
          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: limites.maxHeight - AppSpacing.xl * 2,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const LogotipoProducto(key: Key('login_logo'), ancho: 260),
                  const SizedBox(height: AppSpacing.xxl),
                  formulario,
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Formulario extends StatelessWidget {
  const _Formulario({
    required this.estado,
    required this.l10n,
    required this.colors,
  });

  final _LoginWebScreenState estado;
  final AppLocalizations l10n;
  final AppColorScheme colors;

  @override
  Widget build(BuildContext context) => AutofillGroup(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.loginTitulo, style: AppTypography.heading2),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          l10n.loginSubtitulo,
          style: AppTypography.body.copyWith(color: colors.textMuted),
        ),
        const SizedBox(height: AppSpacing.xl),

        RisegTextField(
          label: l10n.loginCampoUsuario,
          controller: estado._correo,
          enabled: !estado._entrando,
          errorText: estado._errorCorreo,
          prefixIcon: Icons.alternate_email,
          autofillHints: const [AutofillHints.username],
          // Enter en el correo baja a la contraseña, no envía: enviar con la
          // contraseña vacía produciría un error que nadie provocó.
          onSubmitted: (_) => estado._focoContrasena.requestFocus(),
        ),
        const SizedBox(height: AppSpacing.md),

        RisegTextField(
          label: l10n.loginCampoContrasena,
          controller: estado._contrasena,
          enabled: !estado._entrando,
          errorText: estado._errorContrasena,
          focusNode: estado._focoContrasena,
          obscureText: !estado._verContrasena,
          prefixIcon: Icons.lock_outline,
          autofillHints: const [AutofillHints.password],
          onSubmitted: (_) {
            if (!estado._entrando) estado._entrar();
          },
          suffixAction: IconButton(
            tooltip: estado._verContrasena
                ? l10n.loginOcultarContrasena
                : l10n.loginMostrarContrasena,
            icon: Icon(
              estado._verContrasena ? Icons.visibility_off : Icons.visibility,
              size: 20,
            ),
            onPressed: estado._alternarContrasena,
          ),
        ),

        if (estado._error != null) ...[
          const SizedBox(height: AppSpacing.md),
          _Aviso(mensaje: estado._error!, colors: colors),
        ],

        const SizedBox(height: AppSpacing.xl),
        // `RisegButton` no se estira solo: el ancho lo da quien lo coloca, igual
        // que en el formulario del escritorio.
        SizedBox(
          width: double.infinity,
          child: RisegButton(
            label: l10n.loginBotonEntrar,
            onPressed: estado._entrando ? null : estado._entrar,
            loading: estado._entrando,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Center(
          child: Text(
            l10n.loginAccesoProtegido,
            style: AppTypography.caption.copyWith(color: colors.textMuted),
          ),
        ),
      ],
    ),
  );
}

/// El aviso de que algo falló.
///
/// **Sin icono de alarma ni fondo rojo saturado.** «Correo o contraseña
/// incorrectos» es el error más común de cualquier login y no es una catástrofe;
/// pintarlo como tal convierte una errata en un sobresalto.
class _Aviso extends StatelessWidget {
  const _Aviso({required this.mensaje, required this.colors});

  final String mensaje;
  final AppColorScheme colors;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.sm,
    ),
    decoration: BoxDecoration(
      color: colors.errorBg,
      borderRadius: BorderRadius.circular(AppRadius.md),
    ),
    child: Text(
      mensaje,
      style: AppTypography.body.copyWith(color: colors.error),
    ),
  );
}
