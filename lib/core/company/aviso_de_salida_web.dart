import 'dart:js_interop';

import 'aviso_de_salida.dart';

/// Instala el aviso de `beforeunload` **en el navegador**, y devuelve cómo soltarlo.
///
/// Lo que el navegador pide para enseñar su diálogo son **las dos cosas**, y hay que
/// hacerlas juntas: `preventDefault()` —la forma moderna— y `returnValue = ''` —la que
/// todavía exige alguna versión—. Con una sola, hay navegadores que se van sin preguntar.
///
/// ⚠️ **SE PREGUNTA DENTRO DEL OYENTE, no al instalarlo.** Es el mismo motivo por el que
/// el guardia guarda funciones y no valores: se instala una vez, al arrancar, y lo que
/// hay que perder aparece minutos después. Capturar el valor aquí dejaría el aviso
/// decidido para siempre.
///
/// La contraparte está en `aviso_de_salida_io.dart`.
SoltarAvisoDeSalida instalarAvisoDeSalida(HayTrabajoSinGuardar hayTrabajo) {
  void alIntentarSalir(_EventoDeSalida evento) {
    if (!hayTrabajo()) return;

    evento.preventDefault();
    evento.returnValue = '';
  }

  // LA MISMA REFERENCIA PARA PONER Y QUITAR: `toJS` crea una envoltura nueva en cada
  // llamada, así que quitar el oyente con otra **no quitaría nada** y el aviso se
  // quedaría vivo tras el `dispose`. Es el mismo cuidado que `GuardiaDeSalida.liberar`
  // tiene con su función.
  final oyente = alIntentarSalir.toJS;

  _ventana.addEventListener('beforeunload', oyente);

  return () => _ventana.removeEventListener('beforeunload', oyente);
}

@JS('window')
external _Ventana get _ventana;

extension type _Ventana._(JSObject _) implements JSObject {
  external void addEventListener(String tipo, JSFunction oyente);
  external void removeEventListener(String tipo, JSFunction oyente);
}

extension type _EventoDeSalida._(JSObject _) implements JSObject {
  external void preventDefault();

  /// Obsoleto en el estándar y **todavía necesario**: hay navegadores que sólo frenan si
  /// esto se pone.
  external set returnValue(String valor);
}
