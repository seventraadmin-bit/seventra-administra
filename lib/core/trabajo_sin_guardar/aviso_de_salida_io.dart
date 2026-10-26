import 'aviso_de_salida.dart';

/// El aviso antes de salir **en el escritorio: no hay pestaña que cerrar**.
///
/// **Y ES CORRECTO, NO UN HUECO.** `beforeunload` es del navegador: en Windows no existe
/// ni recargar la página ni cerrar una pestaña. Lo que sí existe —cerrar la ventana de la
/// aplicación— es otro mecanismo del sistema, y el escritorio tiene sus propios diálogos
/// de confirmación desde antes de la mudanza.
///
/// Y esto es lo que la **suite** usa, porque corre en la VM: así las pruebas montan el
/// portón sin tocar `dart:js_interop`. Lo que sí se prueba de este camino es la
/// **decisión**, que vive aparte en `aviso_de_salida.dart` justo para eso.
///
/// La contraparte real está en `aviso_de_salida_web.dart`.
SoltarAvisoDeSalida instalarAvisoDeSalida(HayTrabajoSinGuardar hayTrabajo) => () {};
