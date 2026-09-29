// Integration Foundation IF-3 — la preferencia de última empresa.
//
// Se prueba la implementación REAL sobre el mock de plataforma de
// `shared_preferences`, así que el mapa que se inspecciona es lo que de verdad
// quedaría en el perfil del equipo. Eso permite afirmar lo importante: qué se guarda
// y, sobre todo, **qué no**.

import 'package:flutter_test/flutter_test.dart';
import 'package:riseg_one/core/company/almacen_company_recordada.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const companyId = '0193f0a0-0000-7000-8000-000000000001';
  const almacen = AlmacenCompanyRecordadaPreferencias();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<Map<String, Object?>> loGuardado() async {
    final prefs = await SharedPreferences.getInstance();

    return {for (final clave in prefs.getKeys()) clave: prefs.get(clave)};
  }

  test('Sin nada guardado devuelve null y no crea la clave', () async {
    expect(await almacen.leer(), isNull);
    expect(await loGuardado(), isEmpty);
  });

  test('Guarda UNA clave, con la convención del proyecto', () async {
    await almacen.escribir(companyId);

    expect(await loGuardado(), {'riseg_one.company_activa': companyId});
    expect(
      AlmacenCompanyRecordadaPreferencias.nombreClave,
      'riseg_one.company_activa',
    );
  });

  test('Ida y vuelta', () async {
    await almacen.escribir(companyId);

    expect(await almacen.leer(), companyId);
  });

  test('Guarda SÓLO el identificador: nada del contexto', () async {
    // El nombre, la Organization, los módulos, los permisos y `restricted` son
    // autoridad del servidor: cachearlos como verdad produciría una interfaz que
    // muestra permisos de ayer.
    await almacen.escribir(companyId);

    final contenido = (await loGuardado()).values.join('|');

    expect(contenido, companyId);
    expect(contenido.toLowerCase(), isNot(contains('name')));
    expect(contenido.toLowerCase(), isNot(contains('organization')));
    expect(contenido.toLowerCase(), isNot(contains('permis')));
    expect(contenido.toLowerCase(), isNot(contains('restricted')));
    expect(contenido.toLowerCase(), isNot(contains('module')));
  });

  test('Escribir de nuevo SUSTITUYE, no acumula', () async {
    await almacen.escribir(companyId);
    await almacen.escribir('0193f0a0-0000-7000-8000-000000000002');

    expect(await loGuardado(), hasLength(1));
    expect(await almacen.leer(), '0193f0a0-0000-7000-8000-000000000002');
  });

  test('Borrar deja el perfil sin la clave', () async {
    await almacen.escribir(companyId);
    await almacen.borrar();

    expect(await loGuardado(), isEmpty);
    expect(await almacen.leer(), isNull);
  });

  test('Borrar lo que no existe no rompe nada', () async {
    await almacen.borrar();

    expect(await almacen.leer(), isNull);
  });

  test('Un valor en blanco se lee como ausente', () async {
    SharedPreferences.setMockInitialValues({'riseg_one.company_activa': '   '});

    expect(await almacen.leer(), isNull);
  });

  test('NO colisiona con las claves que ya existían', () async {
    SharedPreferences.setMockInitialValues({
      'riseg_one.theme_mode': 'dark',
      'riseg_one.sqlite': 'algo',
    });

    await almacen.escribir(companyId);

    final guardado = await loGuardado();

    expect(guardado['riseg_one.theme_mode'], 'dark');
    expect(guardado['riseg_one.sqlite'], 'algo');
    expect(guardado['riseg_one.company_activa'], companyId);
  });
}
