import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'credential_cipher.dart';

/// Las tres entradas del Almacén de Credenciales que participan en una
/// restauración portable (Etapa 4D).
enum RanuraClave {
  /// La clave que usa la aplicación.
  principal(NombresRanuraClave.principal),

  /// La clave recuperada de un paquete portable, esperando a que la
  /// restauración se confirme. Si la restauración no llega a buen
  /// puerto, se borra y nadie se entera.
  pendiente(NombresRanuraClave.pendiente),

  /// La clave que este equipo tenía antes de la restauración. Se aparta
  /// aquí **antes** de tocar la principal, y no se borra mientras siga
  /// existiendo el respaldo preventivo con el que forma pareja: sin
  /// ella, restaurar ese preventivo devolvería los datos pero dejaría
  /// la Bóveda ilegible, que es media vuelta atrás y por tanto peor que
  /// ninguna.
  anterior(NombresRanuraClave.anterior);

  const RanuraClave(this.nombre);

  final String nombre;
}

/// Lectura y escritura de las ranuras de clave.
///
/// Se separa de [AlmacenClaveCifrado] a propósito: aquella interfaz
/// describe "la clave de este equipo" y la usan decenas de pruebas;
/// ésta describe el juego completo de ranuras y sólo la necesita la
/// restauración portable. Mezclarlas obligaría a tocar fixtures que no
/// tienen nada que ver con esto.
abstract class AlmacenRanurasClave {
  Future<Uint8List?> leer(RanuraClave ranura);
  Future<void> escribir(RanuraClave ranura, Uint8List clave);
  Future<void> borrar(RanuraClave ranura);
}

/// Implementación real sobre el Almacén de Credenciales de Windows
/// (DPAPI), en el mismo formato base64 que ya usa `CredentialCipher`
/// para la ranura principal — así la clave promovida es indistinguible
/// de una que siempre hubiera estado ahí.
class AlmacenRanurasClaveWindows implements AlmacenRanurasClave {
  const AlmacenRanurasClaveWindows({FlutterSecureStorage? almacen})
    : _almacen = almacen ?? const FlutterSecureStorage();

  final FlutterSecureStorage _almacen;

  @override
  Future<Uint8List?> leer(RanuraClave ranura) async {
    final valor = await _almacen.read(key: ranura.nombre);
    if (valor == null) return null;
    return Uint8List.fromList(base64.decode(valor));
  }

  @override
  Future<void> escribir(RanuraClave ranura, Uint8List clave) {
    return _almacen.write(key: ranura.nombre, value: base64.encode(clave));
  }

  @override
  Future<void> borrar(RanuraClave ranura) => _almacen.delete(key: ranura.nombre);
}
