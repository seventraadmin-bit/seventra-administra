/// Etapa 4D — el validador de la base ya instalada.
///
/// Este archivo nació de un quiebre deliberado que **sobrevivió**: al
/// desactivar a mano la comprobación de `integrity_check` en
/// [ValidadorBaseRestaurada], la suite entera seguía en verde. Las
/// pruebas del coordinador inyectan un validador de mentira —así deben
/// ser, miden el orden de los pasos— y nadie estaba ejercitando el
/// validador real. Una base restaurada estructuralmente dañada habría
/// pasado por sana.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/security/credential_cipher.dart';
import 'package:riseg_one/features/respaldo/domain/portable/validador_base_restaurada.dart';

class _AlmacenClave implements AlmacenClaveCifrado {
  _AlmacenClave(this.valor);
  String? valor;
  @override
  Future<String?> leer() async => valor;
  @override
  Future<void> escribir(String v) async => valor = v;
}

void main() {
  late Directory raiz;
  late String rutaBase;
  late Uint8List clave;

  /// Una clave AES de 32 bytes, fija y distinta según [semilla]. No es
  /// aleatoria a propósito: las pruebas deben ser reproducibles.
  Uint8List claveDe(int semilla) => Uint8List.fromList(List<int>.generate(32, (i) => (i * 7 + semilla) & 0xff));

  AppDatabase abrirCon(Uint8List k) =>
      AppDatabase(openAppDatabaseConnection(rutaBase), almacenClaveCifrado: _AlmacenClave(base64.encode(k)));

  ValidadorBaseRestaurada validadorCon(Uint8List k) => ValidadorBaseRestaurada(abrirBase: () => abrirCon(k));

  setUp(() async {
    raiz = Directory.systemTemp.createTempSync('riseg_valid_');
    rutaBase = p.join(raiz.path, 'riseg_one.sqlite');
    clave = claveDe(1);

    // Una base real, migrada al esquema actual.
    final db = abrirCon(clave);
    await db.customSelect('SELECT 1').get();
    await db.close();
  });

  tearDown(() {
    try {
      raiz.deleteSync(recursive: true);
    } on FileSystemException {
      // En Windows el archivo puede quedar tomado un instante más.
    }
  });

  /// Siembra una credencial de Bóveda cifrada con [k].
  Future<void> sembrarBoveda(Uint8List k, String secreto) async {
    final db = abrirCon(k);
    final cifrado = await CredentialCipher(almacen: _AlmacenClave(base64.encode(k))).cifrar(secreto);
    await db.customStatement(
      'INSERT INTO boveda_credencial (id, nombre, tipo, secreto_cifrado, ciclo_vida_registro, created_at, updated_at) '
      "VALUES ('bc-1', 'Portal SAT', 'portal', '$cifrado', 'activo', 1700000000, 1700000000)",
    );
    await db.close();
  }

  group('validar()', () {
    test('una base recién migrada está sana', () async {
      final r = await validadorCon(clave).validar();
      expect(r.sana, isTrue, reason: r.detalle);
    });

    test('un esquema que no es el actual NO es sano', () async {
      // Se fuerza `user_version` hacia atrás después de migrar: es lo que
      // vería un arranque cuya migración no llegó a terminar.
      //
      // El camino real no es la comparación de versiones sino la migración
      // en sí, que revienta al no encontrar de dónde partir. Da igual: lo
      // que importa es que de aquí no salga "sana", y que el validador
      // trate la excepción como lo que es —una base con la que no se puede
      // trabajar— en vez de dejarla escapar hacia el arranque.
      final db = abrirCon(clave);
      await db.customSelect('SELECT 1').get();
      await db.customStatement('PRAGMA user_version = 1');
      await db.close();

      final r = await validadorCon(clave).validar();
      expect(r.sana, isFalse);
      expect(r.detalle, isNotNull, reason: 'un rechazo sin motivo no se puede diagnosticar');
    });

    test('UNA BASE ESTRUCTURALMENTE DAÑADA no es sana — este es el caso que faltaba', () async {
      // Se garabatea la ÚLTIMA página. La elección no es casual: probé
      // antes a ensuciar el medio del archivo y a truncarlo, y en ambos
      // casos SQLite ni siquiera abría, con lo que la prueba pasaba por el
      // camino de la excepción y no habría notado que la comprobación de
      // integridad estuviera desconectada. Con la última página, la base
      // abre, migra y responde `user_version`; lo único que la delata es
      // `integrity_check`.
      final archivo = File(rutaBase);
      final bytes = Uint8List.fromList(archivo.readAsBytesSync());
      expect(bytes.length, greaterThan(8192), reason: 'hace falta más de una página para poder romper una');
      for (var i = bytes.length - 4096; i < bytes.length; i++) {
        bytes[i] = 0x5a;
      }
      archivo.writeAsBytesSync(bytes, flush: true);

      final r = await validadorCon(clave).validar();
      expect(r.sana, isFalse, reason: 'una base dañada jamás puede declararse sana');
      expect(
        r.detalle,
        'integrity_check',
        reason: 'tiene que rechazarla POR la integridad, no de rebote por una excepción al abrir',
      );
    });

    test('una referencia colgando no es sano', () async {
      final db = abrirCon(clave);
      await db.customSelect('SELECT 1').get();
      // Con las llaves apagadas se puede grabar lo que la aplicación
      // nunca grabaría: un archivo que abre bien y cuyos datos se
      // contradicen.
      await db.customStatement('PRAGMA foreign_keys = OFF');
      await db.customStatement(
        'INSERT INTO cliente_portal (id, cliente_id, nombre, tipo, ciclo_vida_registro, created_at, updated_at) '
        "VALUES ('cp-huerfano', 'cliente-que-no-existe', 'Portal', 'facturacion', 'activo', 1700000000, 1700000000)",
      );
      await db.close();

      final r = await validadorCon(clave).validar();
      expect(r.sana, isFalse);
      expect(r.detalle, contains('foreign_key_check'));
    });

    test('si la base no se puede abrir, el detalle es el tipo del fallo y nunca su contenido', () async {
      File(rutaBase).writeAsStringSync('esto no es una base de datos');
      final r = await validadorCon(clave).validar();
      expect(r.sana, isFalse);
      expect(r.detalle, isNot(contains('esto no es')));
    });
  });

  group('claveAbreLoRestaurado()', () {
    test('la clave correcta abre lo restaurado', () async {
      await sembrarBoveda(clave, 'contrasena-del-portal-SAT');
      expect(await validadorCon(clave).claveAbreLoRestaurado(clave), isTrue);
    });

    test('UNA CLAVE AJENA NO abre lo restaurado', () async {
      await sembrarBoveda(clave, 'contrasena-del-portal-SAT');
      // El escenario que convierte "restauración" en "recuperación
      // total": la base llegó completa pero el paquete traía otra clave.
      expect(await validadorCon(clave).claveAbreLoRestaurado(claveDe(99)), isFalse);
    });

    test('sin datos cifrados no se afirma ni se desmiente nada: pasa', () async {
      expect(await validadorCon(clave).claveAbreLoRestaurado(clave), isTrue);
    });

    test('comprobar la clave NO la instala como principal', () async {
      await sembrarBoveda(clave, 'contrasena-del-portal-SAT');
      final almacen = _AlmacenClave(base64.encode(clave));
      final validador = ValidadorBaseRestaurada(
        abrirBase: () => AppDatabase(openAppDatabaseConnection(rutaBase), almacenClaveCifrado: almacen),
      );

      expect(await validador.claveAbreLoRestaurado(claveDe(42)), isFalse);
      expect(
        almacen.valor,
        base64.encode(clave),
        reason: 'probar una clave ajena no puede haber tocado la clave de este equipo',
      );
    });
  });
}
