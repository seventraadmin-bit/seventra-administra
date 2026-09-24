import 'dart:io';

import 'package:convert/convert.dart' show AccumulatorSink;
import 'package:crypto/crypto.dart';

/// SHA-256 de un archivo, leído **por partes**.
///
/// Se hace así y no con `readAsBytes()` por dos razones que importan
/// cuando los adjuntos pesen de verdad: no se carga un archivo entero en
/// memoria, y cada trozo cede el control al bucle de eventos, así que la
/// interfaz sigue respondiendo mientras se calcula. No hay isolate de
/// por medio — el proyecto no usa ninguno, y meter el primero aquí, con
/// `sqlite3` y plugins de por medio, sería introducir un riesgo mayor
/// que el problema que resuelve.
Future<String> sha256DeArchivo(File archivo) async {
  final salida = AccumulatorSink<Digest>();
  final entrada = sha256.startChunkedConversion(salida);
  await for (final trozo in archivo.openRead()) {
    entrada.add(trozo);
  }
  entrada.close();
  final digest = salida.events.single;
  salida.close();
  return digest.toString();
}
