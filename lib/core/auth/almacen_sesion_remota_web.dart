import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'sesion_remota.dart';
import 'almacen_sesion_remota.dart';

/// La credencial de sesión, en el navegador.
///
/// **No se reutiliza `AlmacenSesionRemotaWindows`**, y no es por el nombre: es que el
/// modelo de seguridad **no es el mismo y conviene no fingir que lo es**.
///
/// En Windows, `flutter_secure_storage` guarda en el **Almacén de Credenciales del
/// sistema**: otro proceso necesita los permisos del usuario para leerlo. En el
/// navegador no hay llavero; el paquete cifra y guarda en el almacenamiento local del
/// origen, así que:
///
///   · **cualquier script que se ejecute en este origen puede leerlo.** La defensa
///     real no es el cifrado del paquete, es que no haya scripts ajenos — o sea, la
///     CSP y no meter dependencias de terceros en la página;
///   · **se borra si el usuario limpia los datos del sitio**, y entonces hay que
///     volver a entrar. Eso no es un fallo: es lo que hace cualquier aplicación web;
///   · **no viaja entre dispositivos ni entre navegadores.**
///
/// 🚫 **PENDIENTE(D-30) ANTES DEL PILOTO, no antes de producción.** Lo que de verdad reduce
/// el daño si el almacenamiento se filtra es que el *refresh token* viva en una
/// cookie `HttpOnly` que JavaScript no pueda leer — y eso lo decide el **backend**,
/// no esta clase.
///
/// **El límite es el piloto y no producción porque el piloto ya trae datos reales de
/// RISEG**: nombres de empleados, sueldos e INE. Un token robado de este
/// almacenamiento abre una sesión con todo eso detrás, y los dos permisos protegidos
/// —`personal.sueldo.ver` y `personal.sensitive.read`— no defienden de una sesión
/// legítima robada: defienden de un usuario sin permiso.
///
/// Contra el **ensayo**, con datos inventados, el riesgo es aceptable y está escrito.
/// Con datos del piloto dentro, ya no lo es.
class AlmacenSesionRemotaWeb implements AlmacenSesionRemota {
  const AlmacenSesionRemotaWeb({FlutterSecureStorage? almacen})
    : _almacen = almacen ?? const FlutterSecureStorage();

  final FlutterSecureStorage _almacen;

  /// **La misma clave que en escritorio, a propósito.** Son almacenamientos
  /// distintos que nunca se ven entre sí, y usar dos nombres sólo haría que una
  /// búsqueda en el código no encontrara los dos sitios.
  static const String nombreClave = AlmacenSesionRemotaWindows.nombreClave;

  @override
  Future<CredencialRemota?> leer() async {
    // TODA LECTURA PUEDE FALLAR Y NO DEBE TUMBAR EL ARRANQUE. En una ventana privada
    // o con los datos del sitio bloqueados, el acceso lanza. Y una credencial
    // ilegible es exactamente lo mismo que no tener credencial: se pide entrar otra
    // vez, que es lo que el usuario puede resolver.
    try {
      final texto = await _almacen.read(key: nombreClave);

      if (texto == null || texto.isEmpty) return null;

      // `desdeTexto` ya devuelve `null` ante un texto que no entiende: es una
      // función pura y es LA MISMA que usa el almacén de escritorio. Reimplementar
      // el JSON aquí habría creado una segunda forma de leer la misma credencial.
      return CredencialRemota.desdeTexto(texto);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> escribir(CredencialRemota credencial) async {
    try {
      await _almacen.write(key: nombreClave, value: credencial.aTexto());
    } on Object {
      // NO SE PROPAGA: no poder recordar la sesión degrada la comodidad —habrá que
      // entrar de nuevo al recargar— pero no impide trabajar en esta pestaña. Hacer
      // fallar el login por esto sería convertir una molestia en un bloqueo.
    }
  }

  @override
  Future<void> borrar() async {
    try {
      await _almacen.delete(key: nombreClave);
    } on Object {
      // Si no se puede borrar, la sesión ya se invalidó en el servidor: lo que quede
      // aquí no abre nada.
    }
  }
}
