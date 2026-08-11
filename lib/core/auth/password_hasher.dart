import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Hashing de contraseñas (Etapa 11A) — PBKDF2-HMAC-SHA256 con salt
/// aleatorio por usuario. Nunca se guarda ni se compara la contraseña en
/// texto plano en ningún punto.
///
/// Formato de almacenamiento autodescriptivo:
/// `'pbkdf2$<iteraciones>$<saltBase64>$<hashBase64>'` — los parámetros
/// viajan junto al hash, así que subir el costo (iteraciones) en el
/// futuro no invalida los hashes ya guardados: `verify` siempre relee los
/// parámetros de la cadena almacenada en vez de asumir una constante fija.
class PasswordHasher {
  const PasswordHasher({this.iteraciones = 100000});

  final int iteraciones;

  static const _algoritmo = 'pbkdf2';
  static const _longitudSalt = 16;
  static const _longitudClave = 32;

  String hash(String password) {
    final salt = _generarSalt();
    final clave = _derivar(password: password, salt: salt, iteraciones: iteraciones);
    return _formatear(iteraciones: iteraciones, salt: salt, clave: clave);
  }

  bool verify(String password, String stored) {
    final partes = stored.split(r'$');
    if (partes.length != 4 || partes[0] != _algoritmo) return false;

    final iteracionesGuardadas = int.tryParse(partes[1]);
    if (iteracionesGuardadas == null || iteracionesGuardadas <= 0) return false;

    final Uint8List salt;
    final Uint8List claveGuardada;
    try {
      salt = base64.decode(partes[2]);
      claveGuardada = base64.decode(partes[3]);
    } on FormatException {
      return false;
    }

    final claveCalculada = _derivar(password: password, salt: salt, iteraciones: iteracionesGuardadas);
    return _iguales(claveCalculada, claveGuardada);
  }

  Uint8List _generarSalt() {
    final random = Random.secure();
    return Uint8List.fromList(List.generate(_longitudSalt, (_) => random.nextInt(256)));
  }

  Uint8List _derivar({required String password, required Uint8List salt, required int iteraciones}) {
    final hmac = Hmac(sha256, utf8.encode(password));
    var bloque = Uint8List.fromList(hmac.convert([...salt, 0, 0, 0, 1]).bytes);
    final resultado = Uint8List.fromList(bloque);
    for (var i = 1; i < iteraciones; i++) {
      bloque = Uint8List.fromList(hmac.convert(bloque).bytes);
      for (var j = 0; j < resultado.length; j++) {
        resultado[j] ^= bloque[j];
      }
    }
    return resultado.sublist(0, _longitudClave);
  }

  String _formatear({required int iteraciones, required Uint8List salt, required Uint8List clave}) {
    return '$_algoritmo\$$iteraciones\$${base64.encode(salt)}\$${base64.encode(clave)}';
  }

  /// Comparación en tiempo constante — evita filtrar por temporización en
  /// qué byte difiere un hash incorrecto.
  bool _iguales(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
