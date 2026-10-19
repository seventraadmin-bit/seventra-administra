import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:riseg_one/features/usuarios/web/modelos/capacidad_de_accesos.dart';
import 'package:riseg_one/features/usuarios/web/modelos/miembro_de_empresa.dart';
import 'package:riseg_one/features/usuarios/web/modelos/permiso_de_empresa.dart';

/// Los tres modelos de la pantalla de Usuarios, contra las respuestas **reales** del
/// servidor.
///
/// POR QUÉ CON JSON LITERAL Y NO CON OBJETOS CONSTRUIDOS A MANO: lo que puede romperse
/// aquí es el **nombre de un campo**, y un objeto construido en Dart no lo ejerce. El
/// JSON de estas pruebas está copiado de los contratos del backend —
/// `CompanyAccessMemberResponse`, el catálogo de `platform_permission` y
/// `AccessCapacityResponse`—, así que si alguien renombra `permissionCount` o
/// `maestroAutoGrant`, esto se cae aquí y no en el navegador.
void main() {
  group('MiembroDeEmpresa.deJson', () {
    // La fila tal como la manda `GET /companies/{id}/access`.
    const maestro = '''
      {
        "accessId": "01a15071-2e91-798d-aa4e-44c09ff69d1e",
        "identityId": "01a15071-0001-7000-8000-000000000001",
        "email": "marlon@ejemplo.mx",
        "displayName": "Marlon Rios",
        "role": "maestro",
        "grantedAt": "2026-10-18T19:00:00+00:00",
        "permissionCount": 6
      }
    ''';

    test('lee los campos del contrato', () {
      final m = MiembroDeEmpresa.deJson(
        jsonDecode(maestro) as Map<String, dynamic>,
      );

      expect(m.accesoId, '01a15071-2e91-798d-aa4e-44c09ff69d1e');
      expect(m.identidadId, '01a15071-0001-7000-8000-000000000001');
      expect(m.correo, 'marlon@ejemplo.mx');
      expect(m.nombre, 'Marlon Rios');
      expect(m.permisos, 6);
    });

    test('«es Maestro» se DERIVA del rol, no es un campo', () {
      // El servidor manda `role`, y lo que la pantalla pregunta es si esta persona
      // administra la empresa. Un booleano aparte serían dos verdades.
      expect(
        MiembroDeEmpresa.deJson(jsonDecode(maestro) as Map<String, dynamic>)
            .esMaestro,
        isTrue,
      );

      final usuario = jsonDecode(maestro) as Map<String, dynamic>
        ..['role'] = 'user';

      expect(MiembroDeEmpresa.deJson(usuario).esMaestro, isFalse);
    });

    test('un rol DESCONOCIDO no se toma por Maestro', () {
      // Si el servidor añadiera un rol nuevo, lo peligroso sería que la pantalla lo
      // pintara como administrador. Se pide `== maestro`, no `!= user`.
      final raro = jsonDecode(maestro) as Map<String, dynamic>
        ..['role'] = 'supervisor';

      expect(MiembroDeEmpresa.deJson(raro).esMaestro, isFalse);
    });

    test('sin nombre se muestra el correo, que nunca falta', () {
      final sinNombre = jsonDecode(maestro) as Map<String, dynamic>
        ..['displayName'] = '   ';

      expect(
        MiembroDeEmpresa.deJson(sinNombre).nombreVisible,
        'marlon@ejemplo.mx',
      );
    });
  });

  group('PermisoDeEmpresa.deJson', () {
    const corriente = '''
      {
        "code": "personal.ver",
        "name": "Ver personal",
        "moduleCode": "personal",
        "maestroAutoGrant": true
      }
    ''';

    const protegido = '''
      {
        "code": "personal.sueldo.ver",
        "name": "Ver sueldo",
        "moduleCode": "personal",
        "maestroAutoGrant": false
      }
    ''';

    const delNucleo = '''
      {
        "code": "company.audit.read",
        "name": "Leer la auditoría de la empresa",
        "moduleCode": null,
        "maestroAutoGrant": true
      }
    ''';

    test('«protegido» es la NEGACIÓN de maestroAutoGrant', () {
      // Es fácil leerlo al revés, y leerlo al revés enseñaría como protegidos los 97
      // que no lo son —y como corrientes los seis que sí—.
      expect(
        PermisoDeEmpresa.deJson(
          jsonDecode(corriente) as Map<String, dynamic>,
        ).protegido,
        isFalse,
      );

      expect(
        PermisoDeEmpresa.deJson(
          jsonDecode(protegido) as Map<String, dynamic>,
        ).protegido,
        isTrue,
      );
    });

    test('un módulo nulo es DEL NÚCLEO, no un módulo llamado «null»', () {
      final p = PermisoDeEmpresa.deJson(
        jsonDecode(delNucleo) as Map<String, dynamic>,
      );

      expect(p.modulo, isNull);
      expect(p.esDelNucleo, isTrue);
      expect(p.nombre, 'Leer la auditoría de la empresa');
    });

    test('el nombre viene del servidor y no se reescribe aquí', () {
      // El catálogo es del servidor. Si esta prueba empezara a afirmar un texto
      // propio, sería la señal de que alguien replicó el catálogo en el cliente.
      expect(
        PermisoDeEmpresa.deJson(
          jsonDecode(corriente) as Map<String, dynamic>,
        ).nombre,
        'Ver personal',
      );
    });
  });

  group('CapacidadDeAccesos.deJson', () {
    // `GET /companies/{id}/access-capacity` con el plan `large`: 15 accesos, 0
    // adicionales, 4 en uso.
    const respuesta = '''
      {
        "companyId": "01a15071-2e91-798d-aa4e-44c09ff69d1e",
        "included": 15,
        "extra": 0,
        "total": 15,
        "usage": 4,
        "remaining": 11
      }
    ''';

    test('lee las cinco cifras', () {
      final c = CapacidadDeAccesos.deJson(
        jsonDecode(respuesta) as Map<String, dynamic>,
      );

      expect(c.delPlan, 15);
      expect(c.adicionales, 0);
      expect(c.total, 15);
      expect(c.usados, 4);
      expect(c.libres, 11);
    });

    test('el TOTAL es el del servidor, no una suma hecha aquí', () {
      // Si el cliente recalculara, habría dos cuentas del mismo número. Se comprueba
      // con un cuerpo deliberadamente incoherente: el modelo tiene que reflejarlo tal
      // cual, no «corregirlo».
      final incoherente = jsonDecode(respuesta) as Map<String, dynamic>
        ..['total'] = 99;

      expect(CapacidadDeAccesos.deJson(incoherente).total, 99);
    });

    test('sin adicionales NO se explica el origen del total', () {
      // «15 del plan + 0 adicionales» es ruido. El origen sólo aparece cuando hay
      // algo que explicar.
      expect(
        CapacidadDeAccesos.deJson(
          jsonDecode(respuesta) as Map<String, dynamic>,
        ).origenDelTotal,
        isNull,
      );
    });

    test('con adicionales se explica, y en singular cuando es uno', () {
      final conDos = jsonDecode(respuesta) as Map<String, dynamic>
        ..['extra'] = 2
        ..['total'] = 17;

      expect(
        CapacidadDeAccesos.deJson(conDos).origenDelTotal,
        '15 del plan + 2 adicionales',
      );

      final conUno = jsonDecode(respuesta) as Map<String, dynamic>
        ..['extra'] = 1
        ..['total'] = 16;

      expect(
        CapacidadDeAccesos.deJson(conUno).origenDelTotal,
        '15 del plan + 1 adicional',
      );
    });

    test('cero libres es un DATO, y se lee tal cual', () {
      // Un plan al tope responde `remaining: 0`, y eso no es «no se pudo averiguar».
      // La pantalla distingue las dos cosas porque la segunda es `null` arriba, no un
      // cero aquí.
      final alTope = jsonDecode(respuesta) as Map<String, dynamic>
        ..['usage'] = 15
        ..['remaining'] = 0;

      final c = CapacidadDeAccesos.deJson(alTope);

      expect(c.usados, 15);
      expect(c.libres, 0);
    });
  });

  group('MiembroDeEmpresa.alcanceVisible', () {
    MiembroDeEmpresa miembro({required bool esMaestro, required int permisos}) =>
        MiembroDeEmpresa(
          accesoId: 'a',
          identidadId: 'i',
          correo: 'x@ejemplo.mx',
          nombre: 'X',
          esMaestro: esMaestro,
          permisos: permisos,
        );

    test('un Maestro tiene «Todos los permisos», y es literal', () {
      // Ejerce todos los ordinarios por su rol, no porque alguien se los concediera.
      expect(
        miembro(esMaestro: true, permisos: 6).alcanceVisible,
        'Todos los permisos',
      );
      expect(
        miembro(esMaestro: true, permisos: 0).alcanceVisible,
        'Todos los permisos',
      );
    });

    test('NO dice «N protegidos», porque el número no lo sostiene', () {
      // `permissionCount` cuenta TODAS las concesiones, no sólo las protegidas. Para
      // el primer Maestro coincide hoy; si alguien le concediera un ordinario por
      // API, «7 protegidos» sería falso. El número se queda en el panel, que sí sabe
      // cuáles son.
      final texto = miembro(esMaestro: true, permisos: 7).alcanceVisible;

      expect(texto, isNot(contains('7')));
      expect(texto, isNot(contains('protegid')));
    });

    test('a los demás se les cuentan sus permisos, con el singular bien', () {
      expect(miembro(esMaestro: false, permisos: 1).alcanceVisible, '1 permiso');
      expect(miembro(esMaestro: false, permisos: 4).alcanceVisible, '4 permisos');
    });

    test('cero permisos se dice, no se calla', () {
      // Alguien con acceso y sin permisos entra y no puede hacer nada: es un estado
      // real y la lista tiene que delatarlo.
      expect(miembro(esMaestro: false, permisos: 0).alcanceVisible, '0 permisos');
    });

    test('y en ningún caso aparece jerga', () {
      // El texto anterior era «6 + su rol»: sólo se entendía sabiendo que los
      // permisos de un Maestro no son filas.
      for (final m in [
        miembro(esMaestro: true, permisos: 6),
        miembro(esMaestro: false, permisos: 3),
      ]) {
        expect(m.alcanceVisible, isNot(contains('rol')));
        expect(m.alcanceVisible, isNot(contains('+')));
      }
    });
  });
}
