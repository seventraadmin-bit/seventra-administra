/// Quién tiene trabajo sin guardar ahora mismo, y **cómo se llama lo que se perdería**.
///
/// ## Qué resuelve
///
/// Hay cuatro formas de tirar lo que alguien escribió, y ninguna pasa por el formulario:
/// **cambiar de empresa** —que cambia menú, permisos, datos y barra—, **el botón «atrás»
/// del navegador**, **recargar** y **cerrar la pestaña**. Las cuatro se disparan desde
/// fuera de la pantalla, así que la pregunta tiene que poder hacerse desde arriba.
///
/// Hasta E1-B vivía **dentro** de la pantalla de Empresa, que era la única que podía
/// provocar el cambio. Con la barra como único camino —y después con la dirección como
/// estado— eso dejó de alcanzar.
///
/// **Este guardia no pregunta: responde.** Quién pregunta son tres sitios, cada uno en su
/// capa, y está dicho en `docs/diseno-d56-trabajo-sin-guardar.md` §2: el `onExit` del
/// router para un cambio de dirección, el portón para un cambio de empresa, y el aviso
/// `beforeunload` del navegador para recargar o cerrar.
///
/// ## Por qué así, y no con un estado global
///
/// La pantalla **se registra al montarse y se libera al desmontarse**, igual que un
/// `TextEditingController`. Es la misma forma que E1 ya usaba con `alVigilarCambios`,
/// subida un nivel.
///
/// ⚠️ **SIN NADIE REGISTRADO, NO HAY CAMBIOS**, y la postura segura es ésta y no la
/// contraria. Los dos descuidos posibles no cuestan lo mismo:
///
///  · una pantalla que **olvide registrarse** deja su formulario sin proteger: se nota
///    la primera vez que alguien pierde algo, y se arregla — y desde D-56 hay un candado
///    que lo caza antes: `test/app/shell/guardia_cubre_los_formularios_test.dart`, que
///    implementa la regla «toda pantalla con Guardar se registra»;
///  · un registro que **se quede pegado** tras un `dispose` responderían «sí hay cambios»
///    para siempre, y entonces **cada navegación preguntaría** por un formulario que ya
///    no existe. Parecería un cuelgue, no un descuido, y nadie sabría dónde mirar.
///
/// Por eso [liberar] exige la misma función que [registrar] recibió: así una pantalla que
/// se desmonta **después** de que otra se registrara no borra el registro de la nueva. Ese
/// orden ocurre de verdad en Flutter —el `initState` del siguiente corre antes del
/// `dispose` del anterior— y sin la comprobación dejaría la pantalla nueva sin protección,
/// que es el peor de los dos mundos: silencioso.
///
/// ## ⚠️ VARIOS REGISTRADOS, y no es una generalización por si acaso
///
/// Hasta D-56 guardaba **uno**, y con la regla «toda pantalla con Guardar se registra» eso
/// se rompe en el primer caso real: **un panel de alta abierto encima de una pantalla**.
/// Los dos están montados, los dos tienen algo que perder, y con un solo hueco cerrar el
/// panel —que libera el suyo— **dejaba a la pantalla de debajo sin protección**, porque su
/// registro ya había sido sobrescrito.
///
/// Así que se guardan todos los que estén montados. [hayCambiosSinGuardar] es «alguno», y
/// [queSePierde] nombra **el último que se registró de los que tienen cambios**: el de
/// encima, que es el que la persona está mirando.
library;

/// Un formulario montado que puede tener algo que perder.
class _Registrado {
  const _Registrado(this.hayCambios, this.queSePierde);

  final bool Function() hayCambios;
  final String Function() queSePierde;
}

class GuardiaDeSalida {
  /// En orden de registro: el último es el de encima.
  final List<_Registrado> _registrados = [];

  /// Registra quién responde.
  ///
  /// [queSePierde] es **una frase que completa la pregunta**, no un título: «el expediente
  /// de la empresa», «el expediente de la sucursal Centro». Es una función y no un texto
  /// porque **el nombre puede no conocerse todavía** cuando el formulario se monta — la
  /// sucursal llega con la fila cargada, igual que el rastro de D-39.
  void registrar(
    bool Function() hayCambios, {
    required String Function() queSePierde,
  }) => _registrados.add(_Registrado(hayCambios, queSePierde));

  /// Libera **el registro de esta función**, y sólo ése.
  void liberar(bool Function() hayCambios) {
    // SE QUITA EL ÚLTIMO QUE CASE, no el primero: si la misma función estuviera dos veces
    // —no debería, pero un `initState` repetido lo haría—, quitar el primero dejaría al
    // que sigue montado sin su registro y al desmontado con uno.
    for (var i = _registrados.length - 1; i >= 0; i--) {
      if (_registrados[i].hayCambios == hayCambios) {
        _registrados.removeAt(i);

        return;
      }
    }
  }

  /// ¿Se perdería algo si se saliera ahora?
  ///
  /// Una función que lance se trata como **«no hay cambios»**: una pantalla rota no puede
  /// dejar el producto preguntando en cada navegación.
  bool get hayCambiosSinGuardar => _conCambios().isNotEmpty;

  /// Cómo se llama lo que se perdería, para nombrarlo en la pregunta.
  ///
  /// **El de encima**, que es el que la persona está mirando. Nulo si no hay nada que
  /// perder — y también si el nombre no se pudo calcular, y entonces quien pregunta usa
  /// una frase genérica: **un nombre roto no puede impedir la pregunta**, que es lo que
  /// de verdad protege el trabajo.
  String? get queSePierde {
    final conCambios = _conCambios();
    if (conCambios.isEmpty) return null;

    try {
      final nombre = conCambios.last.queSePierde().trim();

      return nombre.isEmpty ? null : nombre;
    } catch (_) {
      return null;
    }
  }

  List<_Registrado> _conCambios() => [
    for (final r in _registrados)
      if (_pregunta(r)) r,
  ];

  bool _pregunta(_Registrado r) {
    try {
      return r.hayCambios();
    } catch (_) {
      return false;
    }
  }
}
