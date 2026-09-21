import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Deja rastro real de una excepción que un caso de uso convierte en su
/// resultado tipado `...ErrorInesperado` (Etapa "Origen financiero de
/// Egresos manuales", tras el bug real del caso EGR-000035).
///
/// El problema que resuelve: los casos de uso envuelven su escritura en
/// `try { ... } catch (e) { return XErrorInesperado(e.toString()); }`, y
/// la UI traduce ese resultado a un mensaje genérico ("No se pudo
/// corregir el Egreso"). Cuando la excepción real fue un
/// `CircularDependencyError` de Riverpod, `e.toString()` devolvió
/// literalmente `Instance of 'CircularDependencyError'` — ni el mensaje
/// de la UI ni el del resultado decían nada, y el diagnóstico exigió
/// reproducir el caso a mano contra una copia de la base real.
///
/// Qué hace: en DEBUG/PROFILE escribe la excepción COMPLETA con su
/// `StackTrace` a la consola de desarrollo (`dart:developer`, visible en
/// `flutter run`/DevTools). En RELEASE no escribe nada.
///
/// Qué NO hace, deliberadamente: el valor que devuelve es el que
/// termina en el resultado tipado y puede llegar a la UI, así que es
/// SIEMPRE una descripción corta de una línea — nunca el `StackTrace`.
/// Un stack trace jamás se muestra al usuario final, ni siquiera en
/// desarrollo; para eso está la consola.
String diagnosticoErrorInesperado(
  Object error,
  StackTrace stackTrace, {
  required String contexto,
}) {
  if (kDebugMode || kProfileMode) {
    developer.log(
      'Error inesperado en $contexto',
      name: 'riseg.error',
      error: error,
      stackTrace: stackTrace,
      level: 1000,
    );
  }

  // `toString()` de muchas excepciones (las de Riverpod entre ellas) no
  // incluye el tipo — anteponerlo evita el inútil "Instance of '...'".
  final descripcion = error.toString();
  final tipo = error.runtimeType.toString();
  return descripcion.contains(tipo) ? descripcion : '$tipo: $descripcion';
}
