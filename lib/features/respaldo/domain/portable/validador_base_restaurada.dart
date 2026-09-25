import 'dart:convert';
import 'dart:typed_data';

import '../../../../core/database/app_database.dart';
import '../../../../core/security/credential_cipher.dart';
import '../salud_base_datos.dart';
import 'coordinador_restauracion_portable.dart';

/// Comprueba que la base recién instalada sirve, y que la clave que viene
/// con ella **de verdad abre lo que contiene** (Etapa 4D).
///
/// La segunda parte es la que convierte "restauración" en "recuperación
/// total". Sin ella, PC B terminaría con la base completa, los adjuntos
/// completos y una Bóveda que no se abre — y nadie sabría por qué hasta
/// el día que alguien intentara leer una contraseña.
class ValidadorBaseRestaurada {
  const ValidadorBaseRestaurada({required AppDatabase Function() abrirBase}) : _abrirBase = abrirBase;

  /// Abre la base ya instalada. Se inyecta porque abrir la conexión real
  /// es responsabilidad del arranque.
  final AppDatabase Function() _abrirBase;

  /// Abre, migra y pregunta por su salud: esquema esperado,
  /// `integrity_check` y `foreign_key_check`.
  Future<ResultadoSaludBaseRestaurada> validar() async {
    final db = _abrirBase();
    try {
      // Drift migra de forma perezosa: sin una consulta real no ocurre
      // nada, y confirmar aquí sería confirmar que se pudo abrir un
      // archivo.
      await db.customSelect('SELECT 1').get();

      final salud = await revisarSaludBaseDatos((sql) async {
        final filas = await db.customSelect(sql).get();
        return filas.map((f) => f.data.values.toList()).toList();
      });

      if (salud.userVersion != db.schemaVersion) {
        return ResultadoSaludBaseRestaurada(
          sana: false,
          detalle: 'el esquema quedó en ${salud.userVersion} y se esperaba ${db.schemaVersion}',
        );
      }
      if (!salud.integridadOk) return const ResultadoSaludBaseRestaurada(sana: false, detalle: 'integrity_check');
      if (!salud.referenciasOk) return const ResultadoSaludBaseRestaurada(sana: false, detalle: 'foreign_key_check');

      return const ResultadoSaludBaseRestaurada(sana: true);
    } catch (e) {
      return ResultadoSaludBaseRestaurada(sana: false, detalle: e.runtimeType.toString());
    } finally {
      await db.close();
    }
  }

  /// `true` si [clave] descifra una muestra de cada dominio que tenga
  /// datos cifrados: Bóveda, Telefonía y Portal del Cliente.
  ///
  /// Un dominio sin registros no prueba ni desmiente nada y se considera
  /// correcto. Uno con texto cifrado que no abre es un fallo: significa
  /// que el paquete traía la clave equivocada.
  ///
  /// **Nunca** se registra el texto descifrado ni la clave, ni en logs ni
  /// en el resultado: lo único que sale de aquí es un booleano.
  Future<bool> claveAbreLoRestaurado(Uint8List clave) async {
    final db = _abrirBase();
    try {
      final cipher = CredentialCipher(almacen: _AlmacenFijo(clave));

      for (final consulta in [
        'SELECT secreto_cifrado AS c FROM boveda_credencial WHERE secreto_cifrado IS NOT NULL LIMIT 1',
        'SELECT contrasena_cifrada AS c FROM equipo_telefonico_credencial WHERE contrasena_cifrada IS NOT NULL LIMIT 1',
        'SELECT contrasena_cifrada AS c FROM cliente_portal WHERE contrasena_cifrada IS NOT NULL LIMIT 1',
      ]) {
        final fila = await db.customSelect(consulta).getSingleOrNull();
        final cifrado = fila?.data['c'] as String?;
        if (cifrado == null) continue; // ese dominio no tiene nada que probar

        try {
          await cipher.descifrar(cifrado);
        } catch (_) {
          return false;
        }
      }
      return true;
    } catch (_) {
      return false;
    } finally {
      await db.close();
    }
  }
}

/// Almacén de una sola clave, en memoria, para poder probar el descifrado
/// con la clave del paquete **sin** haberla instalado todavía como
/// principal. Es justo lo que permite comprobar antes de promover.
class _AlmacenFijo implements AlmacenClaveCifrado {
  _AlmacenFijo(this._clave);
  final Uint8List _clave;

  @override
  Future<String?> leer() async => base64.encode(_clave);

  @override
  Future<void> escribir(String valor) async {
    throw StateError('este almacén es de sólo lectura: comprobar una clave no puede instalarla');
  }
}
