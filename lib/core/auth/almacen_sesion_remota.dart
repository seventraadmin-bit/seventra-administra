import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'sesion_remota.dart';

/// Dónde vive la credencial de la sesión remota entre dos arranques.
///
/// Misma abstracción que `AlmacenSesionRecordada` y `AlmacenClaveCifrado` para
/// poder inyectar una implementación en memoria en pruebas, pero
/// **deliberadamente una clase distinta con su propia entrada** en el Almacén de
/// Credenciales de Windows.
///
/// NO SE REUTILIZA LA BÓVEDA, y no es por comodidad: la Bóveda empresarial
/// guarda secretos de la empresa —credenciales de portales de clientes, cuentas
/// de teléfonos— bajo una clave maestra que se respalda y se puede recuperar en
/// otro equipo. Una sesión de usuario es lo contrario: es de esta persona y de
/// este equipo, y **no debe viajar en un respaldo**. Mezclarlas haría que
/// restaurar un respaldo portable llevara consigo la sesión de quien lo creó.
abstract class AlmacenSesionRemota {
  Future<CredencialRemota?> leer();

  Future<void> escribir(CredencialRemota credencial);

  Future<void> borrar();
}

/// Implementación real — Almacén de Credenciales de Windows vía
/// `flutter_secure_storage` (DPAPI), con nombre de clave independiente del de
/// `AlmacenSesionRecordadaWindows` y del de `AlmacenClaveSeguraWindows`.
///
/// Deliberadamente delgada: toda la lógica de formato vive en
/// `CredencialRemota.aTexto`/`desdeTexto`, que son funciones puras y sí están
/// cubiertas por pruebas. El canal de plataforma no responde bajo `flutter test`
/// —mismo criterio que `CredentialCipher` y `AlmacenSesionRecordadaWindows`—, así
/// que lo que aquí queda sin probar son tres llamadas al sistema operativo.
class AlmacenSesionRemotaWindows implements AlmacenSesionRemota {
  const AlmacenSesionRemotaWindows({FlutterSecureStorage? almacen})
    : _almacen = almacen ?? const FlutterSecureStorage();

  final FlutterSecureStorage _almacen;

  /// La entrada en el almacén del sistema. Lleva el nombre del producto SaaS y
  /// no el del producto local: son dos sesiones distintas y deben poder
  /// coexistir en el mismo equipo sin pisarse.
  static const String nombreClave = 'seventra_sesion_remota_v1';

  @override
  Future<CredencialRemota?> leer() async {
    final texto = await _almacen.read(key: nombreClave);
    if (texto == null) return null;

    final credencial = CredencialRemota.desdeTexto(texto);

    if (credencial == null) {
      // Había algo y no se pudo interpretar: un blob truncado, de un formato
      // anterior o manipulado. Se tira en el acto en vez de dejarlo ahí para
      // fallar otra vez en el siguiente arranque.
      await borrar();
      return null;
    }

    return credencial;
  }

  @override
  Future<void> escribir(CredencialRemota credencial) =>
      _almacen.write(key: nombreClave, value: credencial.aTexto());

  @override
  Future<void> borrar() => _almacen.delete(key: nombreClave);
}
