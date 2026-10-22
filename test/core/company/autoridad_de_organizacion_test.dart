// E2.5 — la autoridad de ORGANIZACIÓN en la web.
//
// LO QUE ESTAS PRUEBAS DEFIENDEN es una trampa concreta y silenciosa: **el Owner llega
// con la lista de permisos VACÍA**, porque el backend no le materializa filas —su
// autoridad es intrínseca al rol—. Una comprobación escrita en el orden natural
// —«¿tiene el permiso?»— dejaría al dueño de la organización sin la pantalla de
// administración, y el síntoma sería «no me aparece la pestaña», que no apunta a nada.

import 'package:flutter_test/flutter_test.dart';
import 'package:riseg_one/core/company/autoridad_de_organizacion.dart';
import 'package:riseg_one/core/error/failure.dart';

void main() {
  const org = '0193f0a0-0000-7000-8000-0000000000aa';

  AutoridadDeOrganizacion exigir(Map<String, Object?> json) =>
      AutoridadDeOrganizacion.desdeJson(org, json).when(
        ok: (a) => a,
        failure: (f) => fail('Se esperaba una autoridad y llegó: ${f.message}'),
      );

  group('El Owner', () {
    test('⚠️ con la lista VACÍA puede administrar Y eliminar', () {
      // Es el caso real: el backend NO le concede filas de permiso, a propósito.
      final owner = exigir({'role': 'owner', 'permissions': <String>[]});

      expect(owner.esOwner, isTrue);
      expect(owner.puedeAdministrarEmpresas, isTrue);
      expect(owner.puedeEliminarEmpresas, isTrue);
    });

    test('sin el campo `permissions` tampoco pierde nada', () {
      final owner = exigir({'role': 'owner'});

      expect(owner.puedeAdministrarEmpresas, isTrue);
      expect(owner.puedeEliminarEmpresas, isTrue);
    });
  });

  group('El Admin', () {
    test('SIN el permiso no administra', () {
      final admin = exigir({'role': 'admin', 'permissions': <String>[]});

      expect(admin.puedeAdministrarEmpresas, isFalse);
      expect(admin.puedeEliminarEmpresas, isFalse);
    });

    test('CON el permiso administra, y sigue SIN poder eliminar', () {
      // LA FRONTERA DE E2, y es lo que más importa de este modelo: eliminar es del
      // Owner. Un Admin con `companies.manage` crea, desactiva y reactiva — y no borra.
      final admin = exigir({
        'role': 'admin',
        'permissions': ['companies.manage'],
      });

      expect(admin.puedeAdministrarEmpresas, isTrue);
      expect(admin.puedeEliminarEmpresas, isFalse);
    });

    test('otro permiso de organización NO le sirve para esto', () {
      // `subscription.manage` autoriza comprometer gasto, no dar de alta empresas. Un
      // permiso no se ensancha.
      final admin = exigir({
        'role': 'admin',
        'permissions': ['subscription.manage'],
      });

      expect(admin.puedeAdministrarEmpresas, isFalse);
    });
  });

  group('Lo que llega mal', () {
    test('sin rol es un fallo, y el fallo NOMBRA el campo', () {
      final fallo = AutoridadDeOrganizacion.desdeJson(org, {'permissions': <String>[]})
          .when(ok: (_) => fail('Se esperaba un fallo'), failure: (f) => f);

      expect(fallo, isA<ApiRespuestaInesperadaFailure>());
      expect(fallo.message, contains('role'));
    });

    test('un permiso que no es texto se ignora, y los demás se conservan', () {
      // Tolerar la basura de UNA entrada sin perder las otras: el permiso que importa
      // puede venir detrás.
      final admin = exigir({
        'role': 'admin',
        'permissions': [42, 'companies.manage', '', '   '],
      });

      expect(admin.permisos, {'companies.manage'});
      expect(admin.puedeAdministrarEmpresas, isTrue);
    });

    test('un rol desconocido NO hereda nada', () {
      // Si el catálogo del backend creciera, un rol que esta versión no conoce no puede
      // acabar administrando por parecerse a `admin`.
      final raro = exigir({'role': 'supervisor', 'permissions': <String>[]});

      expect(raro.esOwner, isFalse);
      expect(raro.puedeAdministrarEmpresas, isFalse);
      expect(raro.puedeEliminarEmpresas, isFalse);
    });
  });

  test('la igualdad compara los permisos por CONTENIDO', () {
    // El estado viaja en un `ValueNotifier` cuando la pantalla lo observe: comparar por
    // identidad haría que cada lectura repintara, y comparar sólo el rol se tragaría un
    // permiso recién concedido.
    final a = exigir({'role': 'admin', 'permissions': ['companies.manage', 'x.y']});
    final b = exigir({'role': 'admin', 'permissions': ['x.y', 'companies.manage']});
    final c = exigir({'role': 'admin', 'permissions': ['x.y']});

    expect(a, b);
    expect(a, isNot(c));
  });
}
