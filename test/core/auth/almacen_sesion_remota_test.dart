// Integration Foundation IF-2 — el almacén seguro de la credencial remota.
//
// Se prueba la implementación REAL, no una en memoria: `flutter_secure_storage`
// permite sustituir su plataforma en pruebas, así que el mapa que se le pasa es
// literalmente lo que quedaría en el Almacén de Credenciales de Windows. Eso
// permite afirmar lo importante sobre el ALMACENAMIENTO y no sólo sobre el
// contrato: qué clave se usa, qué hay dentro y —sobre todo— qué NO hay.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riseg_one/core/auth/almacen_sesion_remota.dart';
import 'package:riseg_one/core/auth/sesion_remota.dart';

void main() {
  late Map<String, String> disco;
  late AlmacenSesionRemotaWindows almacen;

  setUp(() {
    disco = <String, String>{};
    FlutterSecureStorage.setMockInitialValues(disco);
    almacen = const AlmacenSesionRemotaWindows();
  });

  CredencialRemota credencial({
    String refreshToken = 'rt_de_refresco_secreto',
  }) => CredencialRemota(
    identityId: 'i-1',
    refreshToken: refreshToken,
    refreshExpiresAt: DateTime.utc(2026, 10, 12),
    sessionId: '0193f0a0-0000-7000-8000-000000000001',
    email: 'ana@seventra.mx',
    displayName: 'Ana Torres',
  );

  test('Escribe UNA entrada, con la clave del producto SaaS', () async {
    await almacen.escribir(credencial());

    expect(disco.keys, ['seventra_sesion_remota_v1']);
    expect(AlmacenSesionRemotaWindows.nombreClave, 'seventra_sesion_remota_v1');
  });

  test('La clave NO es la de la sesión local recordada', () async {
    // Son dos sesiones distintas y tienen que poder coexistir en el mismo
    // equipo: la local es de un `Usuario` de esta instalación, la remota de una
    // Identity del backend. Compartir entrada haría que cerrar una borrara la
    // otra.
    await almacen.escribir(credencial());

    expect(disco.containsKey('riseg_one_sesion_recordada_token_v1'), isFalse);
  });

  test('Ida y vuelta por el almacén real', () async {
    await almacen.escribir(credencial());

    final leida = await almacen.leer();

    expect(leida, isNotNull);
    expect(leida!.refreshToken, 'rt_de_refresco_secreto');
    expect(leida.email, 'ana@seventra.mx');
    expect(leida.displayName, 'Ana Torres');
  });

  test('Sin nada guardado devuelve null y no crea la entrada', () async {
    expect(await almacen.leer(), isNull);
    expect(disco, isEmpty);
  });

  test('Un blob ilegible se descarta Y SE BORRA', () async {
    // Dejarlo ahí haría que el mismo arranque fallara otra vez mañana. Y lanzar
    // desde aquí reventaría el inicio por un archivo que lo correcto es tirar.
    disco['seventra_sesion_remota_v1'] = '{esto no es json';

    expect(await almacen.leer(), isNull);
    expect(
      disco.containsKey('seventra_sesion_remota_v1'),
      isFalse,
      reason: 'la basura no se conserva',
    );
  });

  test('Un blob de otra versión también se descarta y se borra', () async {
    disco['seventra_sesion_remota_v1'] =
        '{"v":99,"rt":"x","rte":"2026-10-12T00:00:00.000Z","sid":"s","em":"a@b.mx"}';

    expect(await almacen.leer(), isNull);
    expect(disco.containsKey('seventra_sesion_remota_v1'), isFalse);
  });

  test('Borrar deja el almacén vacío', () async {
    await almacen.escribir(credencial());
    await almacen.borrar();

    expect(disco, isEmpty);
    expect(await almacen.leer(), isNull);
  });

  test('Escribir de nuevo SUSTITUYE, no acumula', () async {
    await almacen.escribir(credencial());
    await almacen.escribir(credencial(refreshToken: 'rt_rotado'));

    expect(disco, hasLength(1));
    expect((await almacen.leer())!.refreshToken, 'rt_rotado');
  });

  test('En el almacén NO hay token de acceso ni contraseña', () async {
    // La credencial persistida no tiene ni un campo donde ponerlos, y esta
    // prueba lo comprueba sobre el contenido real en lugar de confiar en el
    // tipo.
    await almacen.escribir(credencial());

    final contenido = disco.values.single;

    expect(contenido, contains('rt_de_refresco_secreto'));
    expect(contenido.toLowerCase(), isNot(contains('accesstoken')));
    expect(contenido.toLowerCase(), isNot(contains('password')));
    expect(contenido.toLowerCase(), isNot(contains('contrasena')));
  });
}
