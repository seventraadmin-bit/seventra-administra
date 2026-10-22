// Integration Foundation IF-3 — el motor de la Company activa.
//
// NO SE SIMULA NADA PROPIO: el gestor habla con el `CompanyApi` real, que habla con
// el `ApiClientAutenticado` real de IF-2, que pide el token a un `GestorDeSesion`
// real, que se autenticó contra el mismo `MockClient`. Lo único sustituido es el
// transporte y la preferencia local.
//
// LO QUE SE DEFIENDE, y por qué cada cosa es corrección y no comodidad:
//
//  · **el `companyId` sale SIEMPRE de la lista del servidor**. Una preferencia
//    guardada es una pista, nunca una fuente: si se usara sin confirmarla, una
//    preferencia dejada por otra persona en el mismo equipo abriría una empresa a la
//    que esta Identity no tiene acceso;
//  · **el cambio es todo o nada**. Publicar B antes de confirmar su contexto dejaría
//    la interfaz mostrando una empresa que el servidor no autorizó;
//  · **una respuesta vieja no puede pisar una selección nueva**. Cambiar a B y
//    enseguida a C deja la respuesta de B viajando; publicarla devolvería al usuario
//    a la empresa que ya descartó, y persistirla la reabriría mañana;
//  · **un bache de red no es una revocación**. Confundirlos cambiaría de empresa —o
//    borraría la preferencia— por un timeout.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riseg_one/core/api/api_client.dart';
import 'package:riseg_one/core/api/api_client_autenticado.dart';
import 'package:riseg_one/core/auth/almacen_sesion_remota.dart';
import 'package:riseg_one/core/auth/auth_api.dart';
import 'package:riseg_one/core/auth/gestor_de_sesion.dart';
import 'package:riseg_one/core/auth/sesion_remota.dart';
import 'package:riseg_one/core/company/almacen_company_recordada.dart';
import 'package:riseg_one/core/company/company_api.dart';
import 'package:riseg_one/core/company/company_remota.dart';
import 'package:riseg_one/core/company/gestor_de_company.dart';
import 'package:riseg_one/core/config/api_config.dart';
import 'package:riseg_one/core/error/failure.dart';
import 'package:riseg_one/core/error/result.dart';
import 'package:riseg_one/core/logging/app_logger.dart';

class _AlmacenSesionEnMemoria implements AlmacenSesionRemota {
  CredencialRemota? guardada;

  @override
  Future<CredencialRemota?> leer() async => guardada;

  @override
  Future<void> escribir(CredencialRemota credencial) async =>
      guardada = credencial;

  @override
  Future<void> borrar() async => guardada = null;
}

/// La preferencia local, en memoria, con contadores para poder afirmar **cuándo** se
/// escribe y no sólo qué queda escrito.
class _PreferenciaEnMemoria implements AlmacenCompanyRecordada {
  _PreferenciaEnMemoria([this.recordada]);

  String? recordada;
  int escrituras = 0;
  int borrados = 0;

  @override
  Future<String?> leer() async => recordada;

  @override
  Future<void> escribir(String companyId) async {
    escrituras++;
    recordada = companyId;
  }

  @override
  Future<void> borrar() async {
    borrados++;
    recordada = null;
  }
}

/// Una preferencia que no funciona: `shared_preferences` puede fallar, y eso no debe
/// tumbar una empresa que el servidor ya confirmó.
class _PreferenciaQueFalla implements AlmacenCompanyRecordada {
  @override
  Future<String?> leer() async => throw StateError('preferencias caídas');

  @override
  Future<void> escribir(String companyId) async =>
      throw StateError('preferencias caídas');

  @override
  Future<void> borrar() async => throw StateError('preferencias caídas');
}

void main() {
  final config = ApiConfig.resolve(
    raw: 'http://localhost:5199',
  ).when(ok: (c) => c, failure: (f) => throw StateError(f.message));

  final t0 = DateTime.utc(2026, 9, 28, 12);

  const empresaA = '0193f0a0-0000-7000-8000-00000000000a';
  const empresaB = '0193f0a0-0000-7000-8000-00000000000b';
  const empresaC = '0193f0a0-0000-7000-8000-00000000000c';
  const ajena = '0193f0a0-0000-7000-8000-00000000ffff';
  const organizationId = '0193f0a0-0000-7000-8000-0000000000ff';

  String cuerpoDeSesion() => jsonEncode({
    'accessToken': 'at_1',
    'accessExpiresAt': t0.add(const Duration(minutes: 30)).toIso8601String(),
    'refreshToken': 'rt_1',
    'refreshExpiresAt': t0.add(const Duration(days: 14)).toIso8601String(),
    'identityId': '0193f0a0-0000-7000-8000-00000000cafe',
    'sessionId': '0193f0a0-0000-7000-8000-00000000aaaa',
    'displayName': 'Ana Torres',
    'email': 'ana@seventra.mx',
  });

  Map<String, Object?> companyJson(
    String id,
    String nombre, {
    String organizacion = 'Grupo RISEG',
  }) => {
    'companyId': id,
    'organizationId': organizationId,
    'companyName': nombre,
    'organizationName': organizacion,
    'role': 'maestro',
  };

  String contextoDe(String id, {String nombre = 'Empresa'}) => jsonEncode({
    'companyId': id,
    'organizationId': organizationId,
    'companyName': nombre,
    'companyStatus': 'activa',
    'organizationName': 'Grupo RISEG',
    'role': 'maestro',
    'isMaestro': true,
    'enabledModules': ['personal'],
    'effectivePermissions': ['personal.read'],
    'restricted': false,
  });

  /// Devuelve el `companyId` de una ruta `/api/v1/companies/{id}/context`.
  String companyDeLaRuta(Uri url) => url.pathSegments[3];

  Future<
    ({
      GestorDeCompany gestor,
      GestorDeSesion sesion,
      _PreferenciaEnMemoria preferencia,
      List<http.Request> vistas,
    })
  >
  construir(
    Future<http.Response> Function(http.Request) responder, {
    String? recordada,
    AlmacenCompanyRecordada? preferenciaAlterna,
  }) async {
    final vistas = <http.Request>[];
    final preferencia = _PreferenciaEnMemoria(recordada);

    final desnudo = ApiClient(
      config: config,
      cliente: MockClient((peticion) async {
        if (peticion.url.path.endsWith('/auth/login')) {
          return http.Response(cuerpoDeSesion(), 200);
        }

        vistas.add(peticion);
        return responder(peticion);
      }),
      logger: AppLogger.console(),
    );

    final sesion = GestorDeSesion(
      api: AuthApi(desnudo),
      almacen: _AlmacenSesionEnMemoria(),
      logger: AppLogger.console(),
      ahora: () => t0,
    );
    addTearDown(sesion.dispose);

    await sesion.iniciarSesion(email: 'ana@seventra.mx', password: 'x');

    final gestor = GestorDeCompany(
      api: CompanyApi(ApiClientAutenticado(cliente: desnudo, gestor: sesion)),
      almacen: preferenciaAlterna ?? preferencia,
      logger: AppLogger.console(),
    );
    addTearDown(gestor.dispose);

    return (
      gestor: gestor,
      sesion: sesion,
      preferencia: preferencia,
      vistas: vistas,
    );
  }

  /// Un servidor corriente: la lista dada y el contexto de cualquiera de ellas.
  Future<http.Response> Function(http.Request) servidorCon(
    List<Map<String, Object?>> lista,
  ) => (peticion) async {
    if (peticion.url.path.endsWith('/context')) {
      return http.Response(contextoDe(companyDeLaRuta(peticion.url)), 200);
    }

    return http.Response(jsonEncode(lista), 200);
  };

  int cuantasListas(List<http.Request> vistas) =>
      vistas.where((p) => p.url.path == '/api/v1/companies').length;

  int cuantosContextos(List<http.Request> vistas) =>
      vistas.where((p) => p.url.path.endsWith('/context')).length;

  Failure exigirFallo(Result<Object?> resultado) => resultado.when(
    ok: (_) => fail('Se esperaba un fallo y la operación salió bien'),
    failure: (failure) => failure,
  );

  // =========================================================================
  group('Descubrimiento', () {
    test('una sola empresa se selecciona sola, sin preguntar', () async {
      final armado = await construir(
        servidorCon([companyJson(empresaA, 'Seguridad RISEG')]),
      );

      final estado = await armado.gestor.resolver();

      expect(estado, isA<CompanyActiva>());
      expect(armado.gestor.companyIdActiva, empresaA);
      expect(cuantosContextos(armado.vistas), 1);
    });

    test('varias sin preferencia exigen elegir', () async {
      final armado = await construir(
        servidorCon([
          companyJson(empresaA, 'Alfa'),
          companyJson(empresaB, 'Beta'),
        ]),
      );

      final estado = await armado.gestor.resolver();

      expect(estado, isA<SeleccionDeCompanyRequerida>());
      expect((estado as SeleccionDeCompanyRequerida).disponibles, hasLength(2));
      expect(
        cuantosContextos(armado.vistas),
        0,
        reason: 'no se abre ninguna empresa por su cuenta',
      );
      expect(armado.gestor.companyIdActiva, isNull);
    });

    test('cero empresas: SinAccesoACompanies, y NO es un fallo', () async {
      final armado = await construir(servidorCon([]));

      expect(await armado.gestor.resolver(), isA<SinAccesoACompanies>());
      expect(
        armado.sesion.estado,
        isA<Autenticado>(),
        reason: 'la Identity sigue siendo válida: lo que falta es un acceso',
      );
    });

    test('cero empresas limpia la preferencia: ya no puede valer', () async {
      final armado = await construir(servidorCon([]), recordada: empresaA);

      await armado.gestor.resolver();

      expect(armado.gestor.estado, isA<SinAccesoACompanies>());
      expect(armado.preferencia.recordada, isNull);
    });

    test('una empresa que NO está en la lista no se puede abrir', () async {
      // Es el caso de un acceso revocado o de una Company/Organization desactivada:
      // el servidor no las devuelve con otro estado, DESAPARECEN de la lista.
      final armado = await construir(
        servidorCon([companyJson(empresaB, 'Beta')]),
        recordada: empresaA,
      );

      await armado.gestor.resolver();

      expect(armado.gestor.companyIdActiva, empresaB, reason: 'quedaba una');
      expect(armado.preferencia.recordada, empresaB);
    });

    test('empresas de dos Organizations conviven en una sola lista', () async {
      final armado = await construir(
        servidorCon([
          companyJson(empresaA, 'Alfa', organizacion: 'Grupo A'),
          companyJson(empresaB, 'Beta', organizacion: 'Grupo B'),
        ]),
      );

      final estado =
          await armado.gestor.resolver() as SeleccionDeCompanyRequerida;

      expect(
        estado.disponibles.map((c) => c.organizationName).toSet(),
        {'Grupo A', 'Grupo B'},
        reason: 'no hace falta un selector de Organization',
      );
    });

    test('la lista se conserva para quien la necesite después', () async {
      final armado = await construir(
        servidorCon([
          companyJson(empresaA, 'Alfa'),
          companyJson(empresaB, 'Beta'),
        ]),
      );

      await armado.gestor.resolver();

      expect(armado.gestor.disponibles, hasLength(2));
    });

    test('dos resoluciones simultáneas hacen UN descubrimiento', () async {
      final armado = await construir(
        servidorCon([companyJson(empresaA, 'Alfa')]),
      );

      await Future.wait([armado.gestor.resolver(), armado.gestor.resolver()]);

      expect(cuantasListas(armado.vistas), 1);
      expect(cuantosContextos(armado.vistas), 1);
    });
  });

  // =========================================================================
  group('Selección con preferencia', () {
    test(
      'varias + recordada válida: PREGUNTA, y la marca en vez de entrar',
      () async {
        // ⚠️ ESTA PRUEBA AFIRMABA LO CONTRARIO HASTA EL 21 DE OCTUBRE DE 2026, y
        // decía: «varias + recordada válida: se restaura sin preguntar».
        //
        // La conducta cambió por decisión del dueño (E1-B), y por dos razones que
        // apuntan al mismo sitio: entrar a trabajar en una empresa sin haberlo pedido
        // es la misma clase de sorpresa que hizo retirar la lista de Organización ›
        // Empresa, y la insignia «Última vez» de la pantalla de selección **no se
        // podía ver nunca** — cuando había memoria no había pantalla.
        //
        // Lo que la preferencia hace ahora es ORDENAR Y MARCAR, no decidir. Y eso es
        // lo que se afirma aquí, porque es lo que sustituye a lo anterior: si el
        // estado no llevara la recordada, la pantalla no podría marcar nada y el
        // cambio habría sido sólo quitar una función.
        final armado = await construir(
          servidorCon([
            companyJson(empresaA, 'Alfa'),
            companyJson(empresaB, 'Beta'),
          ]),
          recordada: empresaB,
        );

        final estado = await armado.gestor.resolver();

        expect(estado, isA<SeleccionDeCompanyRequerida>());
        expect((estado as SeleccionDeCompanyRequerida).recordada, empresaB);

        // NO SE ABRIÓ NINGUNA: no hay empresa activa y no se pidió ningún contexto.
        // Con una llamada de contexto, alguien habría entrado sin pedirlo.
        expect(armado.gestor.companyIdActiva, isNull);
        expect(cuantosContextos(armado.vistas), 0);

        // Y LA PREFERENCIA SIGUE ESCRITA. Preguntar no es olvidar: si se borrara, la
        // insignia aparecería una vez y no volvería.
        expect(armado.preferencia.recordada, empresaB);
      },
    );

    test('con UNA empresa la recordada no se consulta: hay una, se abre', () async {
      // El caso frecuente, y el que NO cambió: con una sola empresa nadie pregunta
      // nada. Se afirma además que la preferencia no hizo falta para resolver —vale
      // otra cosa y aun así se entra en la única que hay—, que es la diferencia entre
      // «se abre la recordada» y «se abre la única».
      final armado = await construir(
        servidorCon([companyJson(empresaA, 'Alfa')]),
        recordada: ajena,
      );

      expect(await armado.gestor.resolver(), isA<CompanyActiva>());
      expect(armado.gestor.companyIdActiva, empresaA);
    });

    test('varias + recordada obsoleta: exige elegir y la descarta', () async {
      final armado = await construir(
        servidorCon([
          companyJson(empresaA, 'Alfa'),
          companyJson(empresaB, 'Beta'),
        ]),
        recordada: ajena,
      );

      expect(
        await armado.gestor.resolver(),
        isA<SeleccionDeCompanyRequerida>(),
      );
      expect(armado.preferencia.recordada, isNull);
      expect(cuantosContextos(armado.vistas), 0);
    });

    test('un id recordado AJENO nunca se usa', () async {
      // `shared_preferences` es por MÁQUINA, no por Identity: otra persona pudo
      // dejar ahí su empresa. No hace falta indexar por Identity porque el id sólo
      // se usa si aparece en la lista de ESTA Identity.
      final armado = await construir(
        servidorCon([
          companyJson(empresaA, 'Alfa'),
          companyJson(empresaB, 'Beta'),
        ]),
        recordada: ajena,
      );

      await armado.gestor.resolver();

      for (final peticion in armado.vistas) {
        expect(peticion.url.path, isNot(contains(ajena)));
      }
    });

    test('con UNA empresa, la preferencia ajena es irrelevante', () async {
      final armado = await construir(
        servidorCon([companyJson(empresaA, 'Alfa')]),
        recordada: ajena,
      );

      await armado.gestor.resolver();

      expect(armado.gestor.companyIdActiva, empresaA);
    });

    test('la selección resuelta se persiste', () async {
      final armado = await construir(
        servidorCon([companyJson(empresaA, 'Alfa')]),
      );

      await armado.gestor.resolver();

      expect(armado.preferencia.recordada, empresaA);
      expect(armado.preferencia.escrituras, 1);
    });

    test('una preferencia ilegible no impide resolver', () async {
      final armado = await construir(
        servidorCon([companyJson(empresaA, 'Alfa')]),
        preferenciaAlterna: _PreferenciaQueFalla(),
      );

      expect(await armado.gestor.resolver(), isA<CompanyActiva>());
      expect(armado.gestor.companyIdActiva, empresaA);
    });
  });

  // =========================================================================
  group('Contexto', () {
    test('la ruta lleva exactamente la empresa elegida', () async {
      // LA EMPRESA SE ELIGE, y antes esta prueba la dejaba elegir a la preferencia
      // recordada: resolvía con `recordada: empresaB` y afirmaba que el contexto
      // pedido era el de B. Desde E1-B eso ya no ocurre —con varias se pregunta
      // siempre—, así que la elección se hace por donde se hace de verdad:
      // `cambiarA`, que es lo que llama la tarjeta que alguien pulsa.
      //
      // Lo que la prueba afirma no cambió: **el contexto que se pide es el de la
      // empresa elegida y no el de la otra**. Era el 50 % de acertar por casualidad.
      final armado = await construir(
        servidorCon([
          companyJson(empresaA, 'Alfa'),
          companyJson(empresaB, 'Beta'),
        ]),
      );

      await armado.gestor.resolver();
      await armado.gestor.cambiarA(empresaB);

      final contexto = armado.vistas.firstWhere(
        (p) => p.url.path.endsWith('/context'),
      );

      expect(contexto.url.path, '/api/v1/companies/$empresaB/context');
      expect(contexto.url.path, isNot(contains(empresaA)));
    });

    test(
      'los cuatro campos de autorización se CONSERVAN sin aplicarse',
      () async {
        final armado = await construir((peticion) async {
          if (peticion.url.path.endsWith('/context')) {
            return http.Response(
              jsonEncode({
                'companyId': empresaA,
                'organizationId': organizationId,
                'companyName': 'Alfa',
                'companyStatus': 'activa',
                'organizationName': 'Grupo RISEG',
                'role': 'user',
                'isMaestro': false,
                'enabledModules': ['personal', 'payroll'],
                'effectivePermissions': ['personal.read'],
                'restricted': true,
              }),
              200,
            );
          }

          return http.Response(
            jsonEncode([companyJson(empresaA, 'Alfa')]),
            200,
          );
        });

        final estado = await armado.gestor.resolver() as CompanyActiva;

        expect(estado.contexto.isMaestro, isFalse);
        expect(estado.contexto.restricted, isTrue);
        expect(estado.contexto.enabledModules, {'personal', 'payroll'});
        expect(estado.contexto.effectivePermissions, {'personal.read'});
        expect(
          armado.gestor.companyIdActiva,
          empresaA,
          reason: 'restricted NO impide tener la empresa activa: se lee igual',
        );
      },
    );

    test('un contexto malformado deja CompanyNoResuelta', () async {
      final armado = await construir((peticion) async {
        if (peticion.url.path.endsWith('/context')) {
          return http.Response('<html>proxy</html>', 200);
        }

        return http.Response(jsonEncode([companyJson(empresaA, 'Alfa')]), 200);
      });

      final estado = await armado.gestor.resolver();

      expect(estado, isA<CompanyNoResuelta>());
      expect(
        (estado as CompanyNoResuelta).motivo,
        isA<ApiJsonInvalidoFailure>(),
      );
      expect(armado.gestor.companyIdActiva, isNull);
    });
  });

  // =========================================================================
  group('404 empresa_no_disponible — autoritativo', () {
    test('durante la resolución: descarta, redescubre y resuelve', () async {
      // Carrera real: la empresa estaba en la lista y dejó de estar disponible
      // antes de pedir su contexto.
      var listas = 0;

      final armado = await construir((peticion) async {
        if (peticion.url.path.endsWith('/context')) {
          final id = companyDeLaRuta(peticion.url);

          if (id == empresaA) {
            return http.Response('{"code":"empresa_no_disponible"}', 404);
          }

          return http.Response(contextoDe(id), 200);
        }

        listas++;
        return http.Response(
          jsonEncode(
            listas == 1
                ? [companyJson(empresaA, 'Alfa')]
                : [companyJson(empresaB, 'Beta')],
          ),
          200,
        );
      }, recordada: empresaA);

      final estado = await armado.gestor.resolver();

      expect(estado, isA<CompanyActiva>());
      expect(armado.gestor.companyIdActiva, empresaB);
      expect(listas, 2, reason: 'volvió a descubrir una sola vez');
    });

    test('no entra en bucle: como máximo un redescubrimiento', () async {
      var listas = 0;

      final armado = await construir((peticion) async {
        if (peticion.url.path.endsWith('/context')) {
          return http.Response('{"code":"empresa_no_disponible"}', 404);
        }

        listas++;
        return http.Response(jsonEncode([companyJson(empresaA, 'Alfa')]), 200);
      });

      final estado = await armado.gestor.resolver();

      expect(estado, isA<CompanyNoResuelta>());
      expect(listas, 2, reason: 'un reintento, no infinitos');
      expect(armado.preferencia.recordada, isNull);
    });

    test(
      'revalidar una empresa revocada la sustituye por la que queda',
      () async {
        var revocada = false;
        var listas = 0;

        final armado = await construir((peticion) async {
          if (peticion.url.path.endsWith('/context')) {
            final id = companyDeLaRuta(peticion.url);

            if (id == empresaA && revocada) {
              return http.Response('{"code":"empresa_no_disponible"}', 404);
            }

            return http.Response(contextoDe(id), 200);
          }

          listas++;
          return http.Response(
            jsonEncode(
              revocada
                  ? [companyJson(empresaB, 'Beta')]
                  : [companyJson(empresaA, 'Alfa')],
            ),
            200,
          );
        });

        await armado.gestor.resolver();
        expect(armado.gestor.companyIdActiva, empresaA);

        revocada = true;
        final estado = await armado.gestor.revalidar();

        expect(estado, isA<CompanyActiva>());
        expect(armado.gestor.companyIdActiva, empresaB);
        expect(listas, 2);
        expect(
          armado.sesion.estado,
          isA<Autenticado>(),
          reason:
              'perder el acceso a una empresa NO es dejar de ser quien eres',
        );
      },
    );

    test('revalidar sin ninguna empresa queda: SinAccesoACompanies', () async {
      var revocada = false;

      final armado = await construir((peticion) async {
        if (peticion.url.path.endsWith('/context')) {
          return revocada
              ? http.Response('{"code":"empresa_no_disponible"}', 404)
              : http.Response(contextoDe(companyDeLaRuta(peticion.url)), 200);
        }

        return http.Response(
          jsonEncode(revocada ? [] : [companyJson(empresaA, 'Alfa')]),
          200,
        );
      });

      await armado.gestor.resolver();
      revocada = true;

      expect(await armado.gestor.revalidar(), isA<SinAccesoACompanies>());
      expect(armado.preferencia.recordada, isNull);
      expect(armado.sesion.estado, isA<Autenticado>());
    });
  });

  // =========================================================================
  group('402 — restricción comercial, NO revocación', () {
    test('se representa el fallo y NO se borra la preferencia', () async {
      final armado = await construir((peticion) async {
        if (peticion.url.path.endsWith('/context')) {
          return http.Response('{"code":"subscription_restricted"}', 402);
        }

        return http.Response(jsonEncode([companyJson(empresaA, 'Alfa')]), 200);
      }, recordada: empresaA);

      final estado = await armado.gestor.resolver();

      expect(estado, isA<CompanyNoResuelta>());
      expect(
        ((estado as CompanyNoResuelta).motivo as ApiHttpFailure).statusCode,
        402,
      );
      expect(
        armado.preferencia.recordada,
        empresaA,
        reason: 'una restricción comercial no descarta la empresa',
      );
      expect(
        armado.gestor.disponibles,
        hasLength(1),
        reason: 'sigue siendo accesible: no se quita de la lista',
      );
    });

    test('un 402 no redescubre: no es un cambio de acceso', () async {
      var listas = 0;

      final armado = await construir((peticion) async {
        if (peticion.url.path.endsWith('/context')) {
          return http.Response('{"code":"subscription_restricted"}', 402);
        }

        listas++;
        return http.Response(jsonEncode([companyJson(empresaA, 'Alfa')]), 200);
      });

      await armado.gestor.resolver();

      expect(listas, 1);
    });
  });

  // =========================================================================
  group('Fallos de red', () {
    test(
      'sin red al descubrir: CompanyNoResuelta y preferencia intacta',
      () async {
        final armado = await construir(
          (_) async => throw http.ClientException('sin red'),
          recordada: empresaA,
        );

        final estado = await armado.gestor.resolver();

        expect(estado, isA<CompanyNoResuelta>());
        expect(
          (estado as CompanyNoResuelta).motivo,
          isA<ApiSinConexionFailure>(),
        );
        expect(armado.preferencia.recordada, empresaA);
        expect(armado.preferencia.borrados, 0);
      },
    );

    test('NO se confunde con «no tienes empresas»', () async {
      final armado = await construir(
        (_) async => throw http.ClientException('sin red'),
      );

      expect(await armado.gestor.resolver(), isNot(isA<SinAccesoACompanies>()));
    });

    test('revalidar sin red CONSERVA la empresa activa', () async {
      var caido = false;

      final armado = await construir((peticion) async {
        if (caido) throw http.ClientException('sin red');

        if (peticion.url.path.endsWith('/context')) {
          return http.Response(contextoDe(companyDeLaRuta(peticion.url)), 200);
        }

        return http.Response(jsonEncode([companyJson(empresaA, 'Alfa')]), 200);
      });

      await armado.gestor.resolver();
      caido = true;

      expect(await armado.gestor.revalidar(), isA<CompanyActiva>());
      expect(armado.gestor.companyIdActiva, empresaA);
      expect(armado.preferencia.recordada, empresaA);
    });

    test('resolver de nuevo sin red CONSERVA la empresa activa', () async {
      // Defecto encontrado en el repaso de esta etapa: publicar `CompanyNoResuelta`
      // con A ya activa la degradaría, y quien observara el estado vería algo peor
      // que la realidad. Un bache de red no cambia de empresa.
      var caido = false;

      final armado = await construir((peticion) async {
        if (caido) throw http.ClientException('sin red');

        if (peticion.url.path.endsWith('/context')) {
          return http.Response(contextoDe(companyDeLaRuta(peticion.url)), 200);
        }

        return http.Response(jsonEncode([companyJson(empresaA, 'Alfa')]), 200);
      });

      await armado.gestor.resolver();
      caido = true;

      expect(await armado.gestor.resolver(), isA<CompanyActiva>());
      expect(armado.gestor.companyIdActiva, empresaA);
      expect(armado.preferencia.recordada, empresaA);
    });

    test('un 402 con empresa activa tampoco la degrada', () async {
      var restringida = false;

      final armado = await construir((peticion) async {
        if (peticion.url.path.endsWith('/context')) {
          return restringida
              ? http.Response('{"code":"subscription_restricted"}', 402)
              : http.Response(contextoDe(companyDeLaRuta(peticion.url)), 200);
        }

        return http.Response(jsonEncode([companyJson(empresaA, 'Alfa')]), 200);
      });

      await armado.gestor.resolver();
      restringida = true;

      expect(await armado.gestor.resolver(), isA<CompanyActiva>());
      expect(armado.gestor.companyIdActiva, empresaA);
    });

    test('un 5xx tampoco cambia de empresa', () async {
      var caido = false;

      final armado = await construir((peticion) async {
        if (caido) return http.Response('', 500);

        if (peticion.url.path.endsWith('/context')) {
          return http.Response(contextoDe(companyDeLaRuta(peticion.url)), 200);
        }

        return http.Response(jsonEncode([companyJson(empresaA, 'Alfa')]), 200);
      });

      await armado.gestor.resolver();
      caido = true;
      await armado.gestor.revalidar();

      expect(armado.gestor.companyIdActiva, empresaA);
      expect(armado.preferencia.recordada, empresaA);
    });
  });

  // =========================================================================
  group('Cambio de empresa — todo o nada', () {
    Future<
      ({
        GestorDeCompany gestor,
        GestorDeSesion sesion,
        _PreferenciaEnMemoria preferencia,
        List<http.Request> vistas,
      })
    >
    conDosEmpresas({Set<String> contextoFalla = const {}}) async {
      final armado = await construir((peticion) async {
        if (peticion.url.path.endsWith('/context')) {
          final id = companyDeLaRuta(peticion.url);

          if (contextoFalla.contains(id)) {
            return http.Response('', 500);
          }

          return http.Response(contextoDe(id), 200);
        }

        return http.Response(
          jsonEncode([
            companyJson(empresaA, 'Alfa'),
            companyJson(empresaB, 'Beta'),
          ]),
          200,
        );
      });

      await armado.gestor.resolver();

      // SE ABRE A EXPLÍCITAMENTE, y antes la abría la preferencia: este ayudante
      // resolvía con `recordada: empresaA` y el gestor entraba solo. Desde E1-B, con
      // varias empresas se pregunta siempre, así que lo que deja a A activa es lo que
      // la deja activa de verdad —alguien pulsando su tarjeta—, no una preferencia.
      //
      // Y no es un detalle de montaje: estas pruebas afirman que **A sigue activa**
      // cuando el cambio a B falla. Sin una A de partida, afirmarían que nada sigue
      // siendo nada.
      await armado.gestor.cambiarA(empresaA);

      return armado;
    }

    test('A→B correcto: publica B y la persiste', () async {
      final armado = await conDosEmpresas();

      final resultado = await armado.gestor.cambiarA(empresaB);

      expect(resultado.isOk, isTrue);
      expect(armado.gestor.companyIdActiva, empresaB);
      expect(armado.preferencia.recordada, empresaB);
    });

    test('si el contexto de B falla, A SIGUE activa', () async {
      final armado = await conDosEmpresas(contextoFalla: {empresaB});

      final resultado = await armado.gestor.cambiarA(empresaB);

      expect(resultado.isFailure, isTrue);
      expect(armado.gestor.companyIdActiva, empresaA);
      expect(
        armado.preferencia.recordada,
        empresaA,
        reason: 'nada se persiste sin contexto confirmado',
      );
    });

    test('NO se publica ningún estado intermedio con B activa', () async {
      final armado = await conDosEmpresas(contextoFalla: {empresaB});

      final vistos = <EstadoCompany>[];
      armado.gestor.estadoObservable.addListener(
        () => vistos.add(armado.gestor.estado),
      );

      await armado.gestor.cambiarA(empresaB);

      expect(vistos, isEmpty, reason: 'el fallo no movió el estado');
    });

    test('la preferencia se escribe SÓLO tras confirmar el contexto', () async {
      final armado = await conDosEmpresas(contextoFalla: {empresaB});
      final escriturasAntes = armado.preferencia.escrituras;

      await armado.gestor.cambiarA(empresaB);
      expect(armado.preferencia.escrituras, escriturasAntes);

      await armado.gestor.cambiarA(empresaA);
      expect(armado.preferencia.escrituras, escriturasAntes + 1);
    });

    test(
      'dos cambios simultáneos a la MISMA empresa comparten la petición',
      () async {
        final armado = await conDosEmpresas();
        final contextosAntes = cuantosContextos(armado.vistas);

        await Future.wait([
          armado.gestor.cambiarA(empresaB),
          armado.gestor.cambiarA(empresaB),
        ]);

        expect(cuantosContextos(armado.vistas) - contextosAntes, 1);
        expect(armado.gestor.companyIdActiva, empresaB);
      },
    );

    test('un cambio a otra empresa NO reutiliza el Future anterior', () async {
      final armado = await conDosEmpresas();
      final contextosAntes = cuantosContextos(armado.vistas);

      await Future.wait([
        armado.gestor.cambiarA(empresaB),
        armado.gestor.cambiarA(empresaC),
      ]);

      expect(cuantosContextos(armado.vistas) - contextosAntes, 2);
    });

    test('una empresa mal formada no llega a salir', () async {
      final armado = await conDosEmpresas();
      final vistasAntes = armado.vistas.length;

      final fallo = exigirFallo(await armado.gestor.cambiarA('empresa-b'));

      expect(fallo, isA<ApiConfigFailure>());
      expect(armado.vistas, hasLength(vistasAntes));
      expect(armado.gestor.companyIdActiva, empresaA);
    });
  });

  // =========================================================================
  group('Concurrencia: una respuesta vieja no pisa la selección nueva', () {
    test('A→B→C: la respuesta de B se descarta', () async {
      final llegoB = Completer<void>();
      final compuerta = Completer<void>();

      final armado = await construir((peticion) async {
        if (peticion.url.path.endsWith('/context')) {
          final id = companyDeLaRuta(peticion.url);

          if (id == empresaB) {
            if (!llegoB.isCompleted) llegoB.complete();
            await compuerta.future;
          }

          return http.Response(contextoDe(id), 200);
        }

        return http.Response(
          jsonEncode([
            companyJson(empresaA, 'Alfa'),
            companyJson(empresaB, 'Beta'),
            companyJson(empresaC, 'Gamma'),
          ]),
          200,
        );
      }, recordada: empresaA);

      await armado.gestor.resolver();

      final cambioB = armado.gestor.cambiarA(empresaB);
      await llegoB.future;

      final cambioC = await armado.gestor.cambiarA(empresaC);
      expect(cambioC.isOk, isTrue);
      expect(armado.gestor.companyIdActiva, empresaC);

      compuerta.complete();

      expect(
        exigirFallo(await cambioB),
        isA<CompanySeleccionSuperadaFailure>(),
      );
      expect(
        armado.gestor.companyIdActiva,
        empresaC,
        reason: 'B no puede devolver al usuario a la empresa que descartó',
      );
      expect(
        armado.preferencia.recordada,
        empresaC,
        reason: 'B no puede reabrirse mañana',
      );
    });

    test('una resolución vieja no pisa un cambio nuevo', () async {
      final llegoLista = Completer<void>();
      final compuerta = Completer<void>();

      final armado = await construir((peticion) async {
        if (peticion.url.path.endsWith('/context')) {
          return http.Response(contextoDe(companyDeLaRuta(peticion.url)), 200);
        }

        if (!llegoLista.isCompleted) {
          llegoLista.complete();
          await compuerta.future;
        }

        return http.Response(
          jsonEncode([
            companyJson(empresaA, 'Alfa'),
            companyJson(empresaB, 'Beta'),
          ]),
          200,
        );
      });

      final resolucion = armado.gestor.resolver();
      await llegoLista.future;

      await armado.gestor.cambiarA(empresaB);
      compuerta.complete();
      await resolucion;

      expect(armado.gestor.companyIdActiva, empresaB);
    });
  });

  // =========================================================================
  group('Persistencia que falla después de confirmar el contexto', () {
    test('la empresa confirmada SIGUE activa', () async {
      // El usuario pidió B y el servidor confirmó B. Devolverlo a A por un fallo de
      // disco contradiría las dos autoridades reales; lo único que se pierde es
      // abrirla directamente en el próximo arranque.
      final armado = await construir((peticion) async {
        if (peticion.url.path.endsWith('/context')) {
          return http.Response(contextoDe(companyDeLaRuta(peticion.url)), 200);
        }

        return http.Response(jsonEncode([companyJson(empresaA, 'Alfa')]), 200);
      }, preferenciaAlterna: _PreferenciaQueFalla());

      final estado = await armado.gestor.resolver();

      expect(estado, isA<CompanyActiva>());
      expect(armado.gestor.companyIdActiva, empresaA);
    });
  });

  // =========================================================================
  group('Estado observable y ciclo de vida', () {
    test('empieza sin resolver y avisa de cada cambio', () async {
      final armado = await construir(
        servidorCon([companyJson(empresaA, 'Alfa')]),
      );

      expect(armado.gestor.estado, isA<CompanySinResolver>());

      final vistos = <EstadoCompany>[];
      armado.gestor.estadoObservable.addListener(
        () => vistos.add(armado.gestor.estado),
      );

      await armado.gestor.resolver();

      expect(vistos.map((e) => e.runtimeType).toList(), [CompanyActiva]);
    });

    test('olvidarSeleccion vuelve al inicio y borra la preferencia', () async {
      final armado = await construir(
        servidorCon([companyJson(empresaA, 'Alfa')]),
      );

      await armado.gestor.resolver();
      await armado.gestor.olvidarSeleccion();

      expect(armado.gestor.estado, isA<CompanySinResolver>());
      expect(armado.gestor.companyIdActiva, isNull);
      expect(armado.preferencia.recordada, isNull);
      expect(
        armado.sesion.estado,
        isA<Autenticado>(),
        reason: 'olvidar la empresa no cierra la sesión',
      );
    });

    test(
      'una resolución que vuelve tras desechar el gestor no revienta',
      () async {
        final compuerta = Completer<void>();
        final llego = Completer<void>();

        final armado = await construir((peticion) async {
          if (!llego.isCompleted) llego.complete();
          await compuerta.future;

          return http.Response(
            jsonEncode([companyJson(empresaA, 'Alfa')]),
            200,
          );
        });

        final resolucion = armado.gestor.resolver();
        await llego.future;

        armado.gestor.dispose();
        compuerta.complete();

        await resolucion;

        expect(armado.gestor.dispose, returnsNormally);
      },
    );
  });

  // =========================================================================
  group('Sesión e identidad', () {
    test('ningún fallo de empresa cierra la sesión', () async {
      for (final responder in <Future<http.Response> Function(http.Request)>[
        (_) async => http.Response('{"code":"empresa_no_disponible"}', 404),
        (_) async => http.Response('{"code":"subscription_restricted"}', 402),
        (_) async => http.Response('', 500),
      ]) {
        final armado = await construir(responder);

        await armado.gestor.resolver();

        expect(armado.sesion.estado, isA<Autenticado>());
        expect(armado.sesion.hayCredencial, isTrue);
      }
    });

    test(
      'las peticiones de empresa van firmadas por el motor de sesión',
      () async {
        final armado = await construir(
          servidorCon([companyJson(empresaA, 'Alfa')]),
        );

        await armado.gestor.resolver();

        for (final peticion in armado.vistas) {
          expect(peticion.headers['Authorization'], 'Bearer at_1');
        }
      },
    );

    test('sin empresa activa no se inventa ningún inquilino', () async {
      final armado = await construir(servidorCon([]));

      await armado.gestor.resolver();

      expect(armado.gestor.companyIdActiva, isNull);
      expect(armado.gestor.contextoActivo, isNull);
    });
  });
}
