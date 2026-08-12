import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Almacén del token de "Recuérdame en este equipo" (Etapa 15) — misma
/// abstracción que `AlmacenClaveCifrado` (`core/security/credential_cipher.dart`)
/// para poder inyectar una implementación en memoria en pruebas, pero
/// **deliberadamente una clase distinta, con su propia entrada** en el
/// Almacén de Credenciales de Windows: la sesión recordada nunca debe
/// mezclarse con la clave de cifrado de Telefonía/Bóveda, ni
/// conceptualmente ni en almacenamiento.
abstract class AlmacenSesionRecordada {
  Future<String?> leer();
  Future<void> escribir(String valor);
  Future<void> borrar();
}

/// Implementación real — Almacén de Credenciales de Windows vía
/// `flutter_secure_storage` (DPAPI), nombre de clave independiente del
/// de `AlmacenClaveSeguraWindows`.
class AlmacenSesionRecordadaWindows implements AlmacenSesionRecordada {
  const AlmacenSesionRecordadaWindows({FlutterSecureStorage? almacen}) : _almacen = almacen ?? const FlutterSecureStorage();

  final FlutterSecureStorage _almacen;

  static const _nombreClave = 'riseg_one_sesion_recordada_token_v1';

  @override
  Future<String?> leer() => _almacen.read(key: _nombreClave);

  @override
  Future<void> escribir(String valor) => _almacen.write(key: _nombreClave, value: valor);

  @override
  Future<void> borrar() => _almacen.delete(key: _nombreClave);
}

/// Token aleatorio de 32 bytes (mismo generador que `CredentialCipher`),
/// codificado base64url — nunca la contraseña, nunca derivado de ella.
String generarTokenSesion() {
  final random = Random.secure();
  final bytes = Uint8List.fromList(List.generate(32, (_) => random.nextInt(256)));
  return base64Url.encode(bytes);
}

/// Hash del token para guardarlo en SQLite — SHA-256 simple, no PBKDF2:
/// el token ya es aleatorio de alta entropía (no una contraseña humana
/// elegida), así que el costo de PBKDF2 no aporta nada aquí, a
/// diferencia de `PasswordHasher`.
String hashTokenSesion(String token) => sha256.convert(utf8.encode(token)).toString();
