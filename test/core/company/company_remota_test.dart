// Integration Foundation IF-3 — los modelos de Company y sus estados.
//
// Dos cosas se defienden aquí. La primera es la FIDELIDAD al contrato del backend:
// cinco campos en la lista, diez en el contexto, ni uno inventado ni uno perdido —
// descartar un campo obligaría a IF-4 a volver a pedir lo que ya vino en la misma
// llamada. La segunda es que los cinco estados NO se colapsen: «el servidor dice que
// no tienes empresas» y «no pudimos hablar con el servidor» se parecen en pantalla y
// son opuestos en consecuencias.

import 'package:flutter_test/flutter_test.dart';
import 'package:riseg_one/core/company/company_remota.dart';
import 'package:riseg_one/core/error/failure.dart';
import 'package:riseg_one/core/error/result.dart';

void main() {
  const companyId = '0193f0a0-0000-7000-8000-000000000001';
  const organizationId = '0193f0a0-0000-7000-8000-0000000000ff';

  Map<String, Object?> listaJson({
    String? role = 'maestro',
    String? nombre = 'Seguridad RISEG',
  }) => {
    'companyId': companyId,
    'organizationId': organizationId,
    'companyName': nombre,
    'organizationName': 'Grupo RISEG',
    'role': role,
  };

  Map<String, Object?> contextoJson({
    Object? enabledModules = const ['personal', 'clients_services'],
    Object? effectivePermissions = const ['personal.read', 'personal.manage'],
    Object? isMaestro = true,
    Object? restricted = false,
  }) => {
    'companyId': companyId,
    'organizationId': organizationId,
    'companyName': 'Seguridad RISEG',
    'companyStatus': 'activa',
    'organizationName': 'Grupo RISEG',
    'role': 'maestro',
    'isMaestro': isMaestro,
    'enabledModules': enabledModules,
    'effectivePermissions': effectivePermissions,
    'restricted': restricted,
  };

  T exigirOk<T>(Result<T> resultado) => resultado.when(
    ok: (valor) => valor,
    failure: (f) => fail('Se esperaba un valor y llegó: ${f.message}'),
  );

  Failure exigirFallo(Result<Object?> resultado) => resultado.when(
    ok: (_) => fail('Se esperaba un fallo y se leyó correctamente'),
    failure: (failure) => failure,
  );

  group('CompanyDisponible — lo justo para elegir', () {
    test('lee los cinco campos', () {
      final company = exigirOk(CompanyDisponible.desdeJson(listaJson()));

      expect(company.companyId, companyId);
      expect(company.organizationId, organizationId);
      expect(company.companyName, 'Seguridad RISEG');
      expect(company.organizationName, 'Grupo RISEG');
      expect(company.role, 'maestro');
    });

    test('NO tiene status, y no es un olvido', () {
      // `GET /companies` sólo devuelve filas con acceso, Company y Organization
      // activos: una empresa inactiva no aparece con otro estado, DESAPARECE. Un
      // campo aquí valdría siempre lo mismo e invitaría a ramificar sobre nada.
      final texto =
          exigirOk(CompanyDisponible.desdeJson(listaJson())).toString();

      expect(texto, isNot(contains('status')));
    });

    test('falta un campo: se nombra el campo', () {
      for (final ausente in [
        'companyId',
        'organizationId',
        'companyName',
        'organizationName',
        'role',
      ]) {
        final json = listaJson()..remove(ausente);

        expect(
          exigirFallo(CompanyDisponible.desdeJson(json)).message,
          contains(ausente),
        );
      }
    });

    test('un campo vacío cuenta como ausente', () {
      expect(
        exigirFallo(CompanyDisponible.desdeJson(listaJson(nombre: '   '))),
        isA<ApiRespuestaInesperadaFailure>(),
      );
    });

    test('dos con los mismos datos son iguales', () {
      expect(
        exigirOk(CompanyDisponible.desdeJson(listaJson())),
        exigirOk(CompanyDisponible.desdeJson(listaJson())),
      );
    });

    group('la razón social (E1-B)', () {
      test('se lee cuando viene', () {
        final json = listaJson()
          ..['legalName'] = 'Seguridad Privada RISEG S.A. de C.V.';

        expect(
          exigirOk(CompanyDisponible.desdeJson(json)).razonSocial,
          'Seguridad Privada RISEG S.A. de C.V.',
        );
      });

      test('NULA, VACÍA y AUSENTE son lo mismo: no hay razón social', () {
        // LAS TRES LLEGAN DE VERDAD, y por eso las tres se prueban juntas:
        //
        //  · **ausente** la manda un servidor anterior a E1-B. Exigirla habría roto
        //    el INICIO DE SESIÓN contra un servidor viejo, que es un precio
        //    desproporcionado para un dato de presentación;
        //  · **nula** es el caso normal de una empresa recién aprovisionada: Tenancy
        //    la crea con un nombre y nada más, y `company.legal_name` es nullable en
        //    la base justo por eso;
        //  · **en blanco** no debería ocurrir, y si ocurriera «   » no es una razón
        //    social.
        //
        // Y NINGUNA es un fallo de lectura: la tarjeta enseña una línea menos.
        // *Ausencia nunca es cero*, y tampoco es una cadena vacía que la pantalla
        // pintaría como un renglón en blanco.
        final ausente = listaJson();
        final nula = listaJson()..['legalName'] = null;
        final blanca = listaJson()..['legalName'] = '   ';

        for (final json in [ausente, nula, blanca]) {
          expect(exigirOk(CompanyDisponible.desdeJson(json)).razonSocial, isNull);
        }
      });

      test('ENTRA EN LA IGUALDAD: cambiarla repinta la lista', () {
        // La tarjeta la pinta, así que dos listas que difieran sólo en la razón social
        // **no son la misma lista**. Sin esto, llenar el expediente no repintaría nada
        // —es el mismo fallo que tuvo el nombre en la barra inferior: el estado viaja
        // en un `ValueNotifier`, que sólo notifica si el valor cambió—.
        final con = exigirOk(
          CompanyDisponible.desdeJson(listaJson()..['legalName'] = 'RISEG S.A.'),
        );
        final sin = exigirOk(CompanyDisponible.desdeJson(listaJson()));

        expect(con, isNot(sin));
      });

      test('conNombre conserva la razón social si no se da otra', () {
        // Quien sólo cambió el nombre comercial no ha dicho nada de la razón social,
        // y borrarla haría desaparecer una línea de la tarjeta al renombrar.
        final original = exigirOk(
          CompanyDisponible.desdeJson(listaJson()..['legalName'] = 'RISEG S.A.'),
        );

        expect(original.conNombre('Otro nombre').razonSocial, 'RISEG S.A.');
        expect(
          original.conNombre('Otro', razonSocial: 'Nueva S.A.').razonSocial,
          'Nueva S.A.',
        );
      });
    });
  });

  group('CompanyContext — los diez campos exactos', () {
    test('los lee todos', () {
      final contexto = exigirOk(CompanyContext.desdeJson(contextoJson()));

      expect(contexto.companyId, companyId);
      expect(contexto.organizationId, organizationId);
      expect(contexto.companyName, 'Seguridad RISEG');
      expect(contexto.companyStatus, 'activa');
      expect(contexto.organizationName, 'Grupo RISEG');
      expect(contexto.role, 'maestro');
      expect(contexto.isMaestro, isTrue);
      expect(contexto.restricted, isFalse);
      expect(contexto.enabledModules, {'personal', 'clients_services'});
      expect(contexto.effectivePermissions, {
        'personal.read',
        'personal.manage',
      });
    });

    test('los códigos son conjuntos: la pregunta es «¿contiene?»', () {
      final contexto = exigirOk(
        CompanyContext.desdeJson(
          contextoJson(
            effectivePermissions: const [
              'personal.read',
              'personal.read',
              'payroll.read',
            ],
          ),
        ),
      );

      expect(contexto.effectivePermissions, hasLength(2));
      expect(contexto.effectivePermissions.contains('payroll.read'), isTrue);
    });

    test('conserva restricted true sin recortar permisos', () {
      // `restricted` es una dimensión SEPARADA: alguien puede poseer
      // `personal.manage` y recibir 402 al mutar. Recortarlo mentiría sobre lo que
      // tiene y haría que la interfaz pareciera una degradación de permisos en vez
      // de un problema de cobro.
      final contexto = exigirOk(
        CompanyContext.desdeJson(contextoJson(restricted: true)),
      );

      expect(contexto.restricted, isTrue);
      expect(contexto.effectivePermissions, contains('personal.manage'));
    });

    test('listas vacías son válidas: una empresa sin módulos existe', () {
      final contexto = exigirOk(
        CompanyContext.desdeJson(
          contextoJson(
            enabledModules: const <String>[],
            effectivePermissions: const <String>[],
          ),
        ),
      );

      expect(contexto.enabledModules, isEmpty);
      expect(contexto.effectivePermissions, isEmpty);
    });

    test('lo que no es texto dentro de una lista se ignora', () {
      final contexto = exigirOk(
        CompanyContext.desdeJson(
          contextoJson(enabledModules: const ['personal', 7, null, '']),
        ),
      );

      expect(contexto.enabledModules, {'personal'});
    });

    test('falta un campo obligatorio: se nombra', () {
      for (final ausente in [
        'companyId',
        'organizationId',
        'companyName',
        'companyStatus',
        'organizationName',
        'role',
        'isMaestro',
        'restricted',
        'enabledModules',
        'effectivePermissions',
      ]) {
        final json = contextoJson()..remove(ausente);

        expect(
          exigirFallo(CompanyContext.desdeJson(json)).message,
          contains(ausente),
          reason: 'debe señalar «$ausente»',
        );
      }
    });

    test('un booleano que llega como texto cuenta como ausente', () {
      expect(
        exigirFallo(
          CompanyContext.desdeJson(contextoJson(isMaestro: 'true')),
        ).message,
        contains('isMaestro'),
      );
    });

    test('companyStatus se conserva aunque hoy sólo pueda ser activa', () {
      // Fidelidad al contrato: el servidor lo envía. Pero ramificar sobre él sería
      // código muerto, porque `/context` exige los tres `status = activa`.
      expect(
        exigirOk(CompanyContext.desdeJson(contextoJson())).companyStatus,
        'activa',
      );
    });
  });

  group('Los cinco estados no se colapsan', () {
    test('cada uno es distinguible', () {
      const contexto = CompanyContext(
        companyId: companyId,
        organizationId: organizationId,
        companyName: 'X',
        companyStatus: 'activa',
        organizationName: 'Y',
        role: 'user',
        isMaestro: false,
        restricted: false,
        enabledModules: {},
        effectivePermissions: {},
      );

      final estados = <EstadoCompany>[
        const CompanySinResolver(),
        const SinAccesoACompanies(),
        const SeleccionDeCompanyRequerida([]),
        const CompanyActiva(contexto),
        const CompanyNoResuelta(ApiSinConexionFailure('sin red')),
      ];

      expect(estados.map((e) => e.runtimeType).toSet(), hasLength(5));
    });

    test('«no tienes empresas» NO es «no pudimos preguntar»', () {
      // El servidor respondiendo una lista vacía es un hecho; un timeout no dice
      // nada. Tratarlos igual haría que una wifi intermitente le dijera al usuario
      // que le quitaron todas sus empresas.
      expect(
        const SinAccesoACompanies(),
        isNot(const CompanyNoResuelta(ApiTimeoutFailure('tardó'))),
      );
    });

    test('«sin resolver» NO es «hay que elegir»', () {
      expect(
        const CompanySinResolver(),
        isNot(const SeleccionDeCompanyRequerida([])),
      );
    });

    test('CompanyNoResuelta conserva el motivo para poder explicarlo', () {
      const estado = CompanyNoResuelta(
        ApiHttpFailure(
          statusCode: 402,
          codigo: 'subscription_restricted',
          message: 'x',
        ),
      );

      expect((estado.motivo as ApiHttpFailure).statusCode, 402);
      expect(estado.toString(), contains('ApiHttpFailure'));
    });

    // =====================================================================
    // La igualdad de CompanyActiva, que decide si el marco se repinta
    // =====================================================================

    const base = CompanyContext(
      companyId: companyId,
      organizationId: organizationId,
      companyName: 'X',
      companyStatus: 'activa',
      organizationName: 'Y',
      role: 'user',
      isMaestro: false,
      restricted: false,
      enabledModules: {'personal'},
      effectivePermissions: {'personal.read'},
    );

    test('un contexto IDÉNTICO es igual: revalidar no repinta por nada', () {
      // Hace falta para que el estado observable no notifique cuando una revalidación
      // devuelve exactamente lo mismo.
      //
      // ⚠️ Y SE COMPARAN DOS INSTANCIAS DISTINTAS CON EL MISMO CONTENIDO, no la misma
      // dos veces. La versión anterior de esta prueba pasaba `uno` en los dos lados,
      // así que no distinguía «mismo contenido» de «misma referencia» ni de «mismo
      // id» — y la implementación comparaba SÓLO el id. La prueba pedía la propiedad
      // correcta y una implementación equivocada la satisfacía.
      const otraInstancia = CompanyContext(
        companyId: companyId,
        organizationId: organizationId,
        companyName: 'X',
        companyStatus: 'activa',
        organizationName: 'Y',
        role: 'user',
        isMaestro: false,
        restricted: false,
        enabledModules: {'personal'},
        effectivePermissions: {'personal.read'},
      );

      expect(const CompanyActiva(base), const CompanyActiva(otraInstancia));
      expect(
        const CompanyActiva(base).hashCode,
        const CompanyActiva(otraInstancia).hashCode,
      );
    });

    test('⚠️ el NOMBRE cambiado hace el estado DISTINTO', () {
      // **ESTE ES EL DEFECTO QUE SE VIO EN PANTALLA** el 21 de octubre de 2026: se
      // renombró la empresa, la ficha decía el nombre nuevo y **la barra inferior
      // seguía con el viejo** hasta recargar.
      //
      // La causa estaba aquí: `CompanyActiva` comparaba sólo por `companyId`, y el
      // estado viaja en un `ValueNotifier`, que **sólo notifica si el valor cambió**.
      // Así que el contexto nuevo se consideraba igual al viejo, no se notificaba, y
      // el marco —que pinta `contexto.companyName` al pie— no se repintaba.
      final renombrada = CompanyActiva(
        _conNombre(base, 'SEGURIDAD PRIVADA RISEG'),
      );

      expect(renombrada, isNot(const CompanyActiva(base)));
    });

    test('⚠️ los PERMISOS cambiados también, y era el síntoma mayor', () {
      // El nombre se ve; esto no. Con la igualdad por id, revalidar tras un cambio de
      // permisos no repintaba nada, así que el menú seguía ofreciendo lo de antes
      // —apartados incluidos— hasta recargar.
      final conMas = CompanyActiva(
        _conPermisos(base, {'personal.read', 'personal.manage'}),
      );

      expect(conMas, isNot(const CompanyActiva(base)));
    });

    test('un Set con los mismos permisos en otro orden NO es un cambio', () {
      // LA OTRA MITAD: comparar los conjuntos por identidad habría hecho que cada
      // revalidación repintara, que es justo el ruido que la igualdad por id quería
      // evitar — reintroducido por la puerta de atrás.
      final mismosAlReves = CompanyActiva(
        _conPermisos(base, {'personal.read'}.toSet()),
      );

      expect(mismosAlReves, const CompanyActiva(base));
    });
  });
}

/// El mismo contexto con otro nombre. **Sólo para las pruebas**: en producción el
/// contexto lo entrega el servidor entero y nunca se compone a mano.
CompanyContext _conNombre(CompanyContext c, String nombre) => CompanyContext(
  companyId: c.companyId,
  organizationId: c.organizationId,
  companyName: nombre,
  companyStatus: c.companyStatus,
  organizationName: c.organizationName,
  role: c.role,
  isMaestro: c.isMaestro,
  restricted: c.restricted,
  enabledModules: c.enabledModules,
  effectivePermissions: c.effectivePermissions,
);

CompanyContext _conPermisos(CompanyContext c, Set<String> permisos) => CompanyContext(
  companyId: c.companyId,
  organizationId: c.organizationId,
  companyName: c.companyName,
  companyStatus: c.companyStatus,
  organizationName: c.organizationName,
  role: c.role,
  isMaestro: c.isMaestro,
  restricted: c.restricted,
  enabledModules: c.enabledModules,
  effectivePermissions: permisos,
);
