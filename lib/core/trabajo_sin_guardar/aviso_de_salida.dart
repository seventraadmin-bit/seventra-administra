/// El aviso antes de **recargar o cerrar la pestaña**, que es el tercer camino de D-56.
///
/// ## Por qué hace falta un tercer mecanismo
///
/// Los otros dos caminos los cubre código nuestro: un cambio de dirección pasa por el
/// `onExit` del router, y un cambio de empresa pasa por el portón. **Recargar y cerrar la
/// pestaña no pasan por ninguno**: los decide el navegador, y después de decidirlos no
/// corre ni una línea de Dart. Lo único que el navegador consulta antes es
/// `beforeunload`.
///
/// ## Tres cosas que el navegador manda, y no se negocian
///
///  · **El texto es suyo**, genérico, y no se puede cambiar. Nuestro mensaje no aparece —
///    así que la frase de [GuardiaDeSalida.queSePierde] aquí no se usa, a diferencia del
///    `onExit`;
///  · **hace falta que la persona haya interactuado** con la página para que el diálogo
///    salga. Quien escribió en un formulario cumple, así que en nuestro caso se da
///    siempre: no hay un escenario donde haya algo que perder y no haya habido una tecla;
///  · **no es cancelable por nosotros**: si dice «salir», la página se va.
///
/// ## Qué parte se puede probar, y por qué está aquí y no en el archivo del navegador
///
/// La instalación vive en `aviso_de_salida_web.dart`, detrás de `dart:js_interop`, y la
/// suite corre en la VM: **ese archivo no se puede ejecutar en una prueba**. Así que la
/// **decisión** —frenar o dejar ir— vive aquí, fuera del interop, donde una prueba la
/// alcanza. Es una línea a propósito: lo que puede equivocarse no es el cableado del
/// `addEventListener`, es el sentido de la respuesta, y eso es exactamente lo que
/// [hayQueFrenarLaSalida] fija.
library;

import 'guardia_de_salida.dart';

/// Lo que el portón le entrega al navegador: cómo preguntar si hay algo que perder.
typedef HayTrabajoSinGuardar = bool Function();

/// Cómo se suelta el aviso. Se llama en el `dispose` de quien lo instaló.
typedef SoltarAvisoDeSalida = void Function();

/// ¿Debe el navegador frenar la salida?
///
/// **Sin nada registrado, no se frena**, que es la misma postura del guardia: de los dos
/// descuidos, el barato es no avisar de algo que nadie declaró; el caro sería que no se
/// pudiera recargar la página en toda la sesión.
bool hayQueFrenarLaSalida(GuardiaDeSalida guardia) =>
    guardia.hayCambiosSinGuardar;
