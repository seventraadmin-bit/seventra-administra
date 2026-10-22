/// Quién tiene trabajo sin guardar ahora mismo.
///
/// ## El problema que resuelve
///
/// Cambiar de empresa cambia **todo**: menú, permisos, datos y la barra inferior. Si la
/// pantalla de encima tiene un formulario a medio llenar, ese trabajo se pierde — y el
/// cambio se dispara desde la barra, que no sabe nada de la pantalla.
///
/// Hasta E1-B la pregunta vivía **dentro** de la pantalla de Empresa, que era la única
/// que podía provocar el cambio. Con la barra como único camino, la pregunta tiene que
/// poder hacerse desde arriba.
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
///    la primera vez que alguien pierde algo, y se arregla;
///  · un guardia que **se quede pegado** tras un `dispose` respondería «sí hay cambios»
///    para siempre, y entonces **no se podría volver a cambiar de empresa en toda la
///    sesión**. Parecería un cuelgue, no un descuido, y nadie sabría dónde mirar.
///
/// Por eso [liberar] exige la misma función que [registrar] recibió: así una pantalla
/// que se desmonta **después** de que otra se registrara no borra el guardia de la
/// nueva. Ese orden ocurre de verdad en Flutter —el `initState` del siguiente corre
/// antes del `dispose` del anterior— y sin la comprobación dejaría la pantalla nueva sin
/// protección, que es el peor de los dos mundos: silencioso.
class GuardiaDeSalida {
  bool Function()? _hayCambios;

  /// Registra quién responde. El último en registrarse manda.
  void registrar(bool Function() hayCambios) => _hayCambios = hayCambios;

  /// Libera **sólo si el guardia sigue siendo éste**.
  void liberar(bool Function() hayCambios) {
    if (_hayCambios == hayCambios) _hayCambios = null;
  }

  /// ¿Se perdería algo si se cambiara de empresa ahora?
  ///
  /// Una función que lance se trata como **«no hay cambios»**: una pantalla rota no
  /// puede dejar el producto sin poder cambiar de empresa.
  bool get hayCambiosSinGuardar {
    final preguntar = _hayCambios;
    if (preguntar == null) return false;

    try {
      return preguntar();
    } catch (_) {
      return false;
    }
  }
}
