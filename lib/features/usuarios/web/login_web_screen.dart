import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextInput;

import '../../../core/auth/gestor_de_sesion.dart';
import 'marca_seventra.dart';
import 'mensajes_humanos.dart';

/// La entrada a SEVENTRA en el navegador.
///
/// **DICE SEVENTRA Y NO SE PARECE A RISEG ONE**, y es una decisión de producto, no
/// de estética: quien abre esta dirección está entrando a la plataforma, y dentro
/// puede tener Administra, Opera o Cumple. Una puerta con la marca del producto
/// local prometería una sola cosa — y además habría que rehacerla en cuanto exista
/// la segunda.
///
/// Por eso **no usa el Design System**. No es un olvido ni un atajo: sus
/// componentes llevan la identidad de RISEG ONE, que es justo lo que esta pantalla
/// no debe parecer. La identidad de aquí sale de [MarcaSeventra], y las pantallas
/// de dentro —Áreas y las tres que vienen— sí usan el Design System, porque ahí ya
/// se está dentro del producto.
///
/// LO QUE ESTA ETAPA NO TRAE, y está decidido así:
///
///  · ⏳ **registro de cuenta**. El backend lo tiene, con correo de verificación,
///    pero quién puede crear cuentas en una plataforma que se vende por suscripción
///    es una decisión comercial que no está tomada;
///  · ⏳ **«olvidé mi contraseña»**. `AuthApi.solicitarRestablecimiento` ya existe
///    y el ciclo completo —correo, enlace, página, token de un solo uso— está
///    probado en el backend. Falta sólo engancharlo, y se hace en su propia etapa
///    para no mezclarlo con la del portón.
///
/// Mientras tanto, una cuenta la crea quien administra, y una contraseña perdida se
/// restablece desde el correo que ya envía el backend.
class LoginWebScreen extends StatefulWidget {
  const LoginWebScreen({required this.gestor, super.key});

  /// Se **recibe** por constructor y no se construye aquí. Es lo que mantiene a
  /// esta pantalla fuera del negocio de armar una sesión: su trabajo es recoger dos
  /// campos y mostrar el resultado.
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

  /// Los dos errores de campo, separados del de arriba a propósito: un campo vacío
  /// se arregla en el campo, y el mensaje tiene que estar donde está el problema.
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

  Future<void> _entrar() async {
    // Se vuelve a leer en cada intento: entre un intento y el siguiente el texto
    // pudo cambiar.
    final correo = _correo.text.trim();
    final contrasena = _contrasena.text;

    // LA VALIDACIÓN LOCAL NO ADIVINA SI EL CORREO EXISTE, sólo si hay algo escrito.
    // Mandar dos campos vacíos al servidor gastaría un viaje y, en el grupo de
    // autenticación, consumiría cuota del limitador — que es lo que después deja a
    // alguien esperando sin entender por qué.
    final sinCorreo = correo.isEmpty;
    final sinContrasena = contrasena.isEmpty;

    if (sinCorreo || sinContrasena) {
      setState(() {
        _error = null;
        _errorCorreo = sinCorreo ? 'Escribe tu correo.' : null;
        _errorContrasena = sinContrasena ? 'Escribe tu contraseña.' : null;
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
      // observa ese estado, decide qué sigue. Si esta pantalla empujara una ruta,
      // habría dos sitios decidiendo lo mismo y podrían discrepar.
      ok: (_) {
        // ESTO ES LO QUE HACE QUE EL NAVEGADOR OFREZCA GUARDAR LA CONTRASEÑA, y sin
        // ello el `AutofillGroup` de arriba no sirve de nada: en web el motor de
        // Flutter mantiene un formulario oculto para el grupo, y es esta llamada la
        // que lo cierra. Sin cerrarlo, Chrome nunca pregunta.
        //
        // Va ANTES de limpiar el campo, en ese orden: el navegador lee el valor al
        // cerrar el contexto, así que borrarlo primero le daría una contraseña vacía
        // que guardar.
        TextInput.finishAutofillContext();

        // La contraseña se borra del campo en cuanto deja de hacer falta. No la
        // protege de nada sofisticado —el gestor ya no la guarda en ningún sitio—,
        // pero tampoco la deja escrita en un formulario que puede volver a verse.
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
    return Scaffold(
      backgroundColor: MarcaSeventra.fondo,
      body: Center(
        child: SingleChildScrollView(
          // Con el teclado abierto en una pantalla baja, el formulario tiene que
          // poder desplazarse. Sin esto, el campo enfocado queda debajo del teclado.
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: LogotipoSeventra()),
                const SizedBox(height: 14),
                const Center(
                  child: Text(
                    MarcaSeventra.descripcion,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: MarcaSeventra.suave,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                _Tarjeta(child: _formulario()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// El formulario, dentro de un [AutofillGroup].
  ///
  /// **HACE FALTA PARA QUE EL GESTOR DE CONTRASEÑAS DEL NAVEGADOR FUNCIONE.** Las
  /// `autofillHints` de los dos campos sólo se traducen al atributo que el navegador
  /// lee si hay un grupo que las agrupe; sin él, Chrome no ofrece la contraseña
  /// guardada y tampoco se guarda la nueva. Y una aplicación web donde el gestor de
  /// contraseñas no funciona empuja a usar contraseñas que se puedan recordar.
  Widget _formulario() => AutofillGroup(child: _campos());

  Widget _campos() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Inicia sesión',
        style: TextStyle(
          color: MarcaSeventra.tinta,
          fontSize: 19,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 22),
      _Campo(
        etiqueta: 'Correo',
        controller: _correo,
        error: _errorCorreo,
        habilitado: !_entrando,
        teclado: TextInputType.emailAddress,
        autofill: const [AutofillHints.username],
        // Enter en el correo baja a la contraseña, no envía: enviar con la
        // contraseña vacía produciría un error que el usuario no provocó.
        alEnviar: () => _focoContrasena.requestFocus(),
      ),
      const SizedBox(height: 16),
      _Campo(
        etiqueta: 'Contraseña',
        controller: _contrasena,
        error: _errorContrasena,
        habilitado: !_entrando,
        foco: _focoContrasena,
        oculto: !_verContrasena,
        autofill: const [AutofillHints.password],
        alEnviar: _entrando ? null : _entrar,
        sufijo: IconButton(
          onPressed: () => setState(() => _verContrasena = !_verContrasena),
          icon: Icon(
            _verContrasena ? Icons.visibility_off : Icons.visibility,
            size: 20,
            color: MarcaSeventra.suave,
          ),
          // Lo lee el lector de pantalla, así que dice la ACCIÓN, no el estado.
          tooltip: _verContrasena ? 'Ocultar contraseña' : 'Ver contraseña',
        ),
      ),
      if (_error != null) ...[const SizedBox(height: 18), _Aviso(_error!)],
      const SizedBox(height: 24),
      SizedBox(
        height: 46,
        child: FilledButton(
          onPressed: _entrando ? null : _entrar,
          style: FilledButton.styleFrom(
            backgroundColor: MarcaSeventra.verde,
            foregroundColor: Colors.white,
            disabledBackgroundColor: MarcaSeventra.verde.withValues(alpha: 0.45),
            disabledForegroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          child: _entrando
              // EL BOTÓN NO CAMBIA DE TEXTO MIENTRAS ESPERA. Un botón que pasa de
              // «Entrar» a «Entrando…» cambia de ancho y salta; el indicador va
              // dentro y el tamaño se mantiene.
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Colors.white,
                  ),
                )
              : const Text('Entrar'),
        ),
      ),
    ],
  );
}

/// La tarjeta blanca sobre el fondo. Borde fino y sin sombra: la misma contención
/// que usan las páginas de correo de SEVENTRA.
class _Tarjeta extends StatelessWidget {
  const _Tarjeta({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: MarcaSeventra.borde),
    ),
    child: child,
  );
}

/// Un campo con su etiqueta encima y su error debajo.
///
/// La etiqueta va **fuera** del campo y no como `labelText` flotante: con texto ya
/// escrito, una etiqueta flotante se encoge y pierde legibilidad, y aquí sólo hay
/// dos campos, así que no hay nada que ahorrar.
class _Campo extends StatelessWidget {
  const _Campo({
    required this.etiqueta,
    required this.controller,
    required this.habilitado,
    this.error,
    this.foco,
    this.oculto = false,
    this.teclado,
    this.sufijo,
    this.alEnviar,
    this.autofill,
  });

  final String etiqueta;
  final TextEditingController controller;
  final bool habilitado;
  final String? error;
  final FocusNode? foco;
  final bool oculto;
  final TextInputType? teclado;
  final Widget? sufijo;
  final VoidCallback? alEnviar;
  final List<String>? autofill;

  @override
  Widget build(BuildContext context) {
    final conError = error != null;

    OutlineInputBorder borde(Color color, double grosor) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: color, width: grosor),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          etiqueta,
          style: const TextStyle(
            color: MarcaSeventra.tinta,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 7),
        TextField(
          controller: controller,
          focusNode: foco,
          enabled: habilitado,
          obscureText: oculto,
          keyboardType: teclado,
          autofillHints: autofill,
          textInputAction: TextInputAction.go,
          onSubmitted: alEnviar == null ? null : (_) => alEnviar!(),
          style: const TextStyle(color: MarcaSeventra.tinta, fontSize: 15),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: habilitado ? Colors.white : MarcaSeventra.fondo,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 14,
            ),
            suffixIcon: sufijo,
            enabledBorder: borde(
              conError ? MarcaSeventra.rojo : MarcaSeventra.borde,
              1,
            ),
            focusedBorder: borde(
              conError ? MarcaSeventra.rojo : MarcaSeventra.verde,
              1.6,
            ),
            disabledBorder: borde(MarcaSeventra.borde, 1),
          ),
        ),
        if (conError) ...[
          const SizedBox(height: 6),
          Text(
            error!,
            style: const TextStyle(color: MarcaSeventra.rojo, fontSize: 12.5),
          ),
        ],
      ],
    );
  }
}

/// El aviso de que algo falló.
///
/// **No lleva icono de alarma ni fondo rojo saturado.** «Correo o contraseña
/// incorrectos» es el error más común de cualquier login y no es una catástrofe;
/// pintarlo como tal convierte una errata en un sobresalto.
class _Aviso extends StatelessWidget {
  const _Aviso(this.mensaje);

  final String mensaje;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: const Color(0x0F9A2B2B),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0x339A2B2B)),
    ),
    child: Text(
      mensaje,
      style: const TextStyle(
        color: MarcaSeventra.rojo,
        fontSize: 13.5,
        height: 1.35,
      ),
    ),
  );
}
