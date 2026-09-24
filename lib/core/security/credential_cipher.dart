import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as encrypt_pkg;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Almacén de la clave maestra de cifrado — abstracción mínima sobre
/// dónde vive la clave, para que `CredentialCipher` no dependa
/// directamente de `FlutterSecureStorage` (esa clase usa canales de
/// plataforma reales, que no responden bajo `flutter test` sin un
/// dispositivo/emulador real — mismo tipo de frontera de SO que ya
/// existe con `path_provider` en otras partes del proyecto). Producción
/// usa `AlmacenClaveSeguraWindows`; las pruebas inyectan una
/// implementación en memoria.
abstract class AlmacenClaveCifrado {
  Future<String?> leer();
  Future<void> escribir(String valor);
}

/// Este equipo no tiene la clave con la que se cifró el dato.
///
/// Es el caso de una base restaurada en otra computadora: el texto
/// cifrado viaja en el respaldo, la clave no (vive en el Almacén de
/// Credenciales de Windows). No es un error del programa ni un dato
/// corrupto — es información que aquí no se puede recuperar, y hay que
/// decirlo con esas palabras en vez de mostrar una excepción.
class ClaveCifradoNoDisponible implements Exception {
  const ClaveCifradoNoDisponible();

  @override
  String toString() => 'ClaveCifradoNoDisponible';
}

/// Implementación real (Etapa 9D) — Almacén de Credenciales de Windows
/// vía `flutter_secure_storage` (DPAPI). La clave nunca toca el archivo
/// `.sqlite` ni el código fuente.
class AlmacenClaveSeguraWindows implements AlmacenClaveCifrado {
  const AlmacenClaveSeguraWindows({FlutterSecureStorage? almacen}) : _almacen = almacen ?? const FlutterSecureStorage();

  final FlutterSecureStorage _almacen;

  static const _nombreClave = 'riseg_one_credencial_cifrado_clave_v1';

  @override
  Future<String?> leer() => _almacen.read(key: _nombreClave);

  @override
  Future<void> escribir(String valor) => _almacen.write(key: _nombreClave, value: valor);
}

/// Cifrado reversible de credenciales (Etapa 9D) — AES-256-GCM (paquete
/// `encrypt`, envuelve PointyCastle; nunca criptografía propia). A
/// diferencia de `PasswordHasher` (Etapa 11A, unidireccional), esto
/// existe específicamente para datos que sí necesitan recuperarse en
/// texto plano — la contraseña de la cuenta de un teléfono.
///
/// La clave maestra se genera una sola vez (`Random.secure()`, 32
/// bytes) y se guarda vía [AlmacenClaveCifrado] (en producción, el
/// Almacén de Credenciales de Windows). **Decisión ya confirmada con
/// Marlon**: si Windows se reinstala o la aplicación se mueve a otra
/// máquina sin esa entrada, las contraseñas cifradas quedan
/// irrecuperables — hay que volver a capturarlas. El resto de un
/// respaldo de base de datos restaura con normalidad; solo el secreto
/// cifrado se pierde. No se construye infraestructura de recuperación de
/// clave.
///
/// Formato de almacenamiento autodescriptivo (mismo espíritu que
/// `PasswordHasher`): `'aesgcm$1$<ivBase64>$<ciphertextBase64>'` — el
/// `1` es la versión del formato, por si el algoritmo cambia en el
/// futuro sin invalidar lo ya cifrado.
class CredentialCipher {
  CredentialCipher({AlmacenClaveCifrado? almacen}) : _almacen = almacen ?? const AlmacenClaveSeguraWindows();

  final AlmacenClaveCifrado _almacen;

  static const _algoritmo = 'aesgcm';
  static const _version = 1;
  static const _longitudClave = 32;
  static const _longitudIv = 12; // recomendado para GCM

  encrypt_pkg.Key? _claveCacheada;

  Future<String> cifrar(String textoPlano) async {
    final clave = await _obtenerOCrearClave();
    final iv = encrypt_pkg.IV(_generarBytesAleatorios(_longitudIv));
    final cifrador = encrypt_pkg.Encrypter(encrypt_pkg.AES(clave, mode: encrypt_pkg.AESMode.gcm));
    final cifrado = cifrador.encrypt(textoPlano, iv: iv);
    return '$_algoritmo\$$_version\$${base64.encode(iv.bytes)}\$${cifrado.base64}';
  }

  /// Lanza [ClaveCifradoNoDisponible] si este equipo no tiene la clave.
  ///
  /// **Descifrar nunca crea una clave** (Etapa 4B). Antes sí lo hacía,
  /// compartiendo camino con cifrar, y el efecto era el peor posible:
  /// abrir una credencial restaurada de otra computadora generaba en
  /// silencio una clave nueva, fallaba igual, y dejaba la base con
  /// textos cifrados bajo dos claves distintas sin nada que los
  /// distinguiera. "No tengo la llave" y "la llave no abre" son
  /// respuestas distintas y ahora se dan por separado.
  Future<String> descifrar(String almacenado) async {
    final partes = almacenado.split(r'$');
    if (partes.length != 4 || partes[0] != _algoritmo) {
      throw const FormatException('Formato de credencial cifrada no reconocido.');
    }

    final clave = await _obtenerClave();
    if (clave == null) throw const ClaveCifradoNoDisponible();

    final iv = encrypt_pkg.IV(base64.decode(partes[2]));
    final cifrador = encrypt_pkg.Encrypter(encrypt_pkg.AES(clave, mode: encrypt_pkg.AESMode.gcm));
    return cifrador.decrypt64(partes[3], iv: iv);
  }

  /// La clave de este equipo, o `null` si no hay ninguna. Nunca crea.
  Future<encrypt_pkg.Key?> _obtenerClave() async {
    final cacheada = _claveCacheada;
    if (cacheada != null) return cacheada;

    final existente = await _almacen.leer();
    if (existente == null) return null;

    final clave = encrypt_pkg.Key(base64.decode(existente));
    _claveCacheada = clave;
    return clave;
  }

  /// Sólo para CIFRAR: si el equipo todavía no tiene clave, se genera.
  /// Es el momento correcto para crearla — se está guardando algo nuevo,
  /// no intentando leer algo que ya existía.
  Future<encrypt_pkg.Key> _obtenerOCrearClave() async {
    final existente = await _obtenerClave();
    if (existente != null) return existente;

    final nuevaClave = _generarBytesAleatorios(_longitudClave);
    await _almacen.escribir(base64.encode(nuevaClave));
    final clave = encrypt_pkg.Key(nuevaClave);
    _claveCacheada = clave;
    return clave;
  }

  Uint8List _generarBytesAleatorios(int longitud) {
    final random = Random.secure();
    return Uint8List.fromList(List.generate(longitud, (_) => random.nextInt(256)));
  }
}
