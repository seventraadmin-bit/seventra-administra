// Integration Foundation IF-2 — el motor de la sesión remota.
//
// NO SE SIMULA NADA PROPIO: el gestor habla con el `AuthApi` real, que habla con
// el `ApiClient` real, que habla con un `MockClient`. Lo único sustituido es el
// transporte y el almacén del sistema. Así, contar las peticiones que llegan al
// transporte es una afirmación sobre el comportamiento verdadero y no sobre un
// doble de prueba que yo mismo escribí.
//
// LO QUE SE DEFIENDE, y por qué cada cosa es correción y no comodidad:
//
//  · **un solo refresco en vuelo**. El backend rota el token en cada canje y
//    responde a la reutilización REVOCANDO LA SESIÓN COMPLETA, así que dos
//    refrescos en paralelo expulsan al usuario;
//  · **se persiste antes de despertar a nadie**. Desde que el servidor rota, el
//    único token que sirve es el nuevo; si el disco conservara el viejo, el
//    siguiente arranque lo canjearía y el backend cerraría la sesión;
//  · **un refresco que llega después de cerrar sesión se tira**. Guardarlo
//    resucitaría mañana la sesión que el usuario cerró hoy;
//  · **un bache de red no cierra la sesión**. Tirar la credencial por un timeout
//    es la forma más rápida de que nadie confíe en la aplicación.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riseg_one/core/api/api_client.dart';
import 'package:riseg_one/core/auth/almacen_sesion_remota.dart';
import 'package:riseg_one/core/auth/auth_api.dart';
import 'package:riseg_one/core/auth/gestor_de_sesion.dart';
import 'package:riseg_one/core/auth/sesion_remota.dart';
import 'package:riseg_one/core/config/api_config.dart';
import 'package:riseg_one/core/error/failure.dart';
import 'package:riseg_one/core/error/result.dart';
import 'package:riseg_one/core/logging/app_logger.dart';

/// El almacén del sistema, en memoria. Misma abstracción que usa producción; el
/// formato real del blob se prueba aparte, en `almacen_sesion_remota_test`.
class _AlmacenEnMemoria implements AlmacenSesionRemota {
  CredencialRemota? guardada;
  int escrituras = 0;
  int borrados = 0;

  @override
  Future<CredencialRemota?> leer() async => guardada;

  @override
  Future<void> escribir(CredencialRemota credencial) async {
    escrituras++;
    guardada = credencial;
  }

  @override
  Future<void> borrar() async {
    borrados++;
    guardada = null;
  }
}

/// Un almacén que no funciona: el Almacén de Credenciales de Windows puede
/// negarse, y eso no debe tumbar la aplicación.
class _AlmacenQueFalla implements AlmacenSesionRemota {
  @override
  Future<CredencialRemota?> leer() async => throw StateError('almacén caído');

  @override
  Future<void> escribir(CredencialRemota credencial) async =>
      throw StateError('almacén caído');

  @override
  Future<void> borrar() async => throw StateError('almacén caído');
}

void main() {
  final config = ApiConfig.resolve(
    raw: 'http://localhost:5199',
  ).when(ok: (c) => c, failure: (f) => throw StateError(f.message));

  /// El instante base de todas las pruebas. El reloj del gestor se inyecta, así
  /// que nada depende del reloj de la máquina.
  final t0 = DateTime.utc(2026, 9, 28, 12);

  late DateTime reloj;

  setUp(() => reloj = t0);

  String cuerpoDeSesion({
    required String accessToken,
    required String refreshToken,
    Duration accesoDura = const Duration(minutes: 30),
    Duration refrescoDura = const Duration(days: 14),
    String? email = 'ana@seventra.mx',
    String? displayName = 'Ana Torres',
  }) => jsonEncode({
    'accessToken': accessToken,
    'accessExpiresAt': reloj.add(accesoDura).toIso8601String(),
    'refreshToken': refreshToken,
    'refreshExpiresAt': reloj.add(refrescoDura).toIso8601String(),
    'identityId': '0193f0a0-0000-7000-8000-00000000cafe',
    'sessionId': '0193f0a0-0000-7000-8000-000000000001',
    'displayName': displayName,
    'email': email,
  });

  ({
    GestorDeSesion gestor,
    _AlmacenEnMemoria almacen,
    List<http.Request> vistas,
  })
  construir(
    Future<http.Response> Function(http.Request) responder, {
    CredencialRemota? guardada,
    AlmacenSesionRemota? almacenAlterno,
  }) {
    final vistas = <http.Request>[];
    final almacen = _AlmacenEnMemoria()..guardada = guardada;

    final cliente = ApiClient(
      config: config,
      cliente: MockClient((peticion) async {
        vistas.add(peticion);
        return responder(peticion);
      }),
      logger: AppLogger.console(),
    );

    final gestor = GestorDeSesion(
      api: AuthApi(cliente),
      almacen: almacenAlterno ?? almacen,
      logger: AppLogger.console(),
      ahora: () => reloj,
    );

    addTearDown(gestor.dispose);

    return (gestor: gestor, almacen: almacen, vistas: vistas);
  }

  int cuantas(List<http.Request> vistas, String ruta) =>
      vistas.where((p) => p.url.path == '/api/v1$ruta').length;

  CredencialRemota credencialGuardada({
    String refreshToken = 'rt_1',
    Duration caducaEn = const Duration(days: 7),
  }) => CredencialRemota(
    identityId: 'i-1',
    refreshToken: refreshToken,
    refreshExpiresAt: t0.add(caducaEn),
    sessionId: '0193f0a0-0000-7000-8000-000000000001',
    email: 'ana@seventra.mx',
    displayName: 'Ana Torres',
  );

  String exigirToken(Result<String> resultado) => resultado.when(
    ok: (token) => token,
    failure: (f) => fail('Se esperaba un token y llegó: ${f.message}'),
  );

  Failure exigirFallo(Result<Object?> resultado) => resultado.when(
    ok: (_) => fail('Se esperaba un fallo y la operación salió bien'),
    failure: (failure) => failure,
  );

  // =========================================================================
  group('Entrar', () {
    test('un login correcto deja sesión y credencial guardada', () async {
      final armado = construir(
        (_) async => http.Response(
          cuerpoDeSesion(accessToken: 'at_1', refreshToken: 'rt_1'),
          200,
        ),
      );

      final sesion = await armado.gestor.iniciarSesion(
        email: 'ana@seventra.mx',
        password: 'Sup3rSecreta!',
      );

      expect(sesion.isOk, isTrue);
      expect(armado.gestor.estado, isA<Autenticado>());
      expect(
        (armado.gestor.estado as Autenticado).sesion.email,
        'ana@seventra.mx',
      );
      expect(armado.almacen.guardada?.refreshToken, 'rt_1');
    });

    test('el token de ACCESO no se guarda en ninguna parte', () async {
      final armado = construir(
        (_) async => http.Response(
          cuerpoDeSesion(accessToken: 'at_1', refreshToken: 'rt_1'),
          200,
        ),
      );

      await armado.gestor.iniciarSesion(email: 'a@b.mx', password: 'x');

      // El objeto persistido no tiene ni un campo donde ponerlo, y lo que sí se
      // guardó es el de refresco.
      expect(armado.almacen.guardada!.aTexto(), isNot(contains('at_1')));
      expect(armado.almacen.guardada!.aTexto(), contains('rt_1'));
    });

    test('la CONTRASEÑA no se guarda en ninguna parte', () async {
      final armado = construir(
        (_) async => http.Response(
          cuerpoDeSesion(accessToken: 'at_1', refreshToken: 'rt_1'),
          200,
        ),
      );

      await armado.gestor.iniciarSesion(
        email: 'a@b.mx',
        password: 'Sup3rSecreta!',
      );

      expect(
        armado.almacen.guardada!.aTexto(),
        isNot(contains('Sup3rSecreta')),
      );
    });

    test(
      'si el backend no reenvía el correo, vale el que se escribió',
      () async {
        final armado = construir(
          (_) async => http.Response(
            cuerpoDeSesion(
              accessToken: 'at_1',
              refreshToken: 'rt_1',
              email: null,
            ),
            200,
          ),
        );

        await armado.gestor.iniciarSesion(
          email: 'ana@seventra.mx',
          password: 'x',
        );

        expect(armado.almacen.guardada?.email, 'ana@seventra.mx');
      },
    );

    test('un login fallido NO cambia el estado ni guarda nada', () async {
      final armado = construir(
        (_) async => http.Response('{"code":"credenciales_invalidas"}', 401),
      );

      final resultado = await armado.gestor.iniciarSesion(
        email: 'a@b.mx',
        password: 'mala',
      );

      expect(exigirFallo(resultado), isA<ApiHttpFailure>());
      expect(armado.gestor.estado, isA<AutenticacionSinResolver>());
      expect(armado.almacen.guardada, isNull);
      expect(armado.gestor.hayCredencial, isFalse);
    });

    test('un login fallido desde una sesión abierta NO la cierra', () async {
      var fallar = false;

      final armado = construir((_) async {
        if (fallar) return http.Response('{"code":"cuenta_bloqueada"}', 423);
        return http.Response(
          cuerpoDeSesion(accessToken: 'at_1', refreshToken: 'rt_1'),
          200,
        );
      });

      await armado.gestor.iniciarSesion(email: 'a@b.mx', password: 'x');
      fallar = true;
      await armado.gestor.iniciarSesion(email: 'otra@b.mx', password: 'mala');

      expect(armado.gestor.estado, isA<Autenticado>());
      expect(armado.almacen.guardada?.refreshToken, 'rt_1');
    });

    test('un almacén que falla NO invalida la sesión recién emitida', () async {
      // Sigue siendo usable en esta ejecución; lo que se pierde es restaurarla
      // mañana. Convertirlo en fallo tiraría una sesión buena.
      final armado = construir(
        (_) async => http.Response(
          cuerpoDeSesion(accessToken: 'at_1', refreshToken: 'rt_1'),
          200,
        ),
        almacenAlterno: _AlmacenQueFalla(),
      );

      final resultado = await armado.gestor.iniciarSesion(
        email: 'a@b.mx',
        password: 'x',
      );

      expect(resultado.isOk, isTrue);
      expect(armado.gestor.estado, isA<Autenticado>());
      expect(exigirToken(await armado.gestor.tokenDeAccesoVigente()), 'at_1');
    });
  });

  // =========================================================================
  group('Refresco preventivo', () {
    test('con más de 60 s por delante NO se refresca', () async {
      final armado = construir(
        (_) async => http.Response(
          cuerpoDeSesion(accessToken: 'at_1', refreshToken: 'rt_1'),
          200,
        ),
      );

      await armado.gestor.iniciarSesion(email: 'a@b.mx', password: 'x');

      expect(exigirToken(await armado.gestor.tokenDeAccesoVigente()), 'at_1');
      expect(cuantas(armado.vistas, '/auth/refresh'), 0);
    });

    test('a 61 s todavía se usa el token que hay', () async {
      final armado = construir(
        (_) async => http.Response(
          cuerpoDeSesion(
            accessToken: 'at_1',
            refreshToken: 'rt_1',
            accesoDura: const Duration(seconds: 61),
          ),
          200,
        ),
      );

      await armado.gestor.iniciarSesion(email: 'a@b.mx', password: 'x');

      expect(exigirToken(await armado.gestor.tokenDeAccesoVigente()), 'at_1');
      expect(cuantas(armado.vistas, '/auth/refresh'), 0);
    });

    test('a 60 s exactos SÍ se refresca: el borde no se usa', () async {
      var numero = 1;

      final armado = construir((peticion) async {
        if (peticion.url.path.endsWith('/auth/refresh')) {
          numero++;
          return http.Response(
            cuerpoDeSesion(
              accessToken: 'at_$numero',
              refreshToken: 'rt_$numero',
            ),
            200,
          );
        }

        return http.Response(
          cuerpoDeSesion(
            accessToken: 'at_1',
            refreshToken: 'rt_1',
            accesoDura: const Duration(seconds: 60),
          ),
          200,
        );
      });

      await armado.gestor.iniciarSesion(email: 'a@b.mx', password: 'x');

      expect(exigirToken(await armado.gestor.tokenDeAccesoVigente()), 'at_2');
      expect(cuantas(armado.vistas, '/auth/refresh'), 1);
      expect(
        GestorDeSesion.ventanaDeRefrescoPreventivo,
        const Duration(seconds: 60),
      );
    });

    test('el paso del tiempo mete al token en la ventana', () async {
      var numero = 1;

      final armado = construir((peticion) async {
        if (peticion.url.path.endsWith('/auth/refresh')) {
          numero++;
          return http.Response(
            cuerpoDeSesion(
              accessToken: 'at_$numero',
              refreshToken: 'rt_$numero',
            ),
            200,
          );
        }

        return http.Response(
          cuerpoDeSesion(accessToken: 'at_1', refreshToken: 'rt_1'),
          200,
        );
      });

      await armado.gestor.iniciarSesion(email: 'a@b.mx', password: 'x');
      expect(exigirToken(await armado.gestor.tokenDeAccesoVigente()), 'at_1');

      // Veintinueve minutos y medio después, al acceso le quedan 30 segundos.
      reloj = t0.add(const Duration(minutes: 29, seconds: 30));

      expect(exigirToken(await armado.gestor.tokenDeAccesoVigente()), 'at_2');
      expect(armado.almacen.guardada?.refreshToken, 'rt_2');
    });
  });

  // =========================================================================
  group('Un solo refresco en vuelo', () {
    /// Un gestor con la sesión abierta y el acceso ya dentro de la ventana, más
    /// un servidor que numera cada refresco.
    Future<
      ({
        GestorDeSesion gestor,
        _AlmacenEnMemoria almacen,
        List<http.Request> vistas,
      })
    >
    conAccesoPorCaducar() async {
      var numero = 1;

      final armado = construir((peticion) async {
        if (peticion.url.path.endsWith('/auth/refresh')) {
          numero++;
          return http.Response(
            cuerpoDeSesion(
              accessToken: 'at_$numero',
              refreshToken: 'rt_$numero',
            ),
            200,
          );
        }

        return http.Response(
          cuerpoDeSesion(
            accessToken: 'at_1',
            refreshToken: 'rt_1',
            accesoDura: const Duration(seconds: 10),
          ),
          200,
        );
      });

      await armado.gestor.iniciarSesion(email: 'a@b.mx', password: 'x');

      return armado;
    }

    test(
      'diez peticiones simultáneas producen EXACTAMENTE un refresco',
      () async {
        final armado = await conAccesoPorCaducar();

        final tokens = await Future.wait(
          List.generate(10, (_) => armado.gestor.tokenDeAccesoVigente()),
        );

        expect(
          cuantas(armado.vistas, '/auth/refresh'),
          1,
          reason:
              'diez canjes del mismo token de refresco harían que el backend '
              'revocara la sesión completa',
        );
        expect(tokens.map(exigirToken).toSet(), {'at_2'});
      },
    );

    test(
      'el token rotado YA está en el almacén cuando despierta cada waiter',
      () async {
        final armado = await conAccesoPorCaducar();

        // Cada continuación mira el disco en el instante en que se reanuda. Si la
        // escritura ocurriera después de liberar a los que esperan, esto fallaría.
        final futuros = List.generate(
          5,
          (_) => armado.gestor.tokenDeAccesoVigente().then((resultado) {
            expect(armado.almacen.guardada?.refreshToken, 'rt_2');
            return resultado;
          }),
        );

        await Future.wait(futuros);

        expect(
          armado.almacen.escrituras,
          2,
          reason: 'login y un solo refresco',
        );
      },
    );

    test(
      'después del refresco, un nuevo lote usa el token nuevo sin refrescar',
      () async {
        final armado = await conAccesoPorCaducar();

        await armado.gestor.tokenDeAccesoVigente();
        final segundo = exigirToken(await armado.gestor.tokenDeAccesoVigente());

        expect(segundo, 'at_2');
        expect(cuantas(armado.vistas, '/auth/refresh'), 1);
      },
    );

    test('diez 401 en paralelo también producen un solo refresco', () async {
      // Es el otro camino al mismo peligro: no el reloj, sino el servidor
      // rechazando el mismo token diez veces.
      final armado = await conAccesoPorCaducar();

      final primero = exigirToken(await armado.gestor.tokenDeAccesoVigente());
      final refrescosAntes = cuantas(armado.vistas, '/auth/refresh');

      final renovados = await Future.wait(
        List.generate(10, (_) => armado.gestor.renovarTrasRechazo(primero)),
      );

      expect(cuantas(armado.vistas, '/auth/refresh') - refrescosAntes, 1);
      expect(renovados.map(exigirToken).toSet(), hasLength(1));
    });

    test('un 401 con un token ya sustituido NO pide otro refresco', () async {
      final armado = await conAccesoPorCaducar();

      final nuevo = exigirToken(await armado.gestor.tokenDeAccesoVigente());
      final refrescosAntes = cuantas(armado.vistas, '/auth/refresh');

      // Llega el 401 de una petición que salió con el token VIEJO.
      final renovado = await armado.gestor.renovarTrasRechazo('at_1');

      expect(exigirToken(renovado), nuevo);
      expect(cuantas(armado.vistas, '/auth/refresh'), refrescosAntes);
    });
  });

  // =========================================================================
  group('La generación: un refresco que llega tarde no resucita nada', () {
    test(
      'cerrar sesión mientras el refresco viaja descarta su resultado',
      () async {
        final llego = Completer<void>();
        final compuerta = Completer<void>();

        final armado = construir((peticion) async {
          if (peticion.url.path.endsWith('/auth/refresh')) {
            if (!llego.isCompleted) llego.complete();
            await compuerta.future;
            return http.Response(
              cuerpoDeSesion(accessToken: 'at_2', refreshToken: 'rt_2'),
              200,
            );
          }

          if (peticion.url.path.endsWith('/auth/logout')) {
            return http.Response('', 204);
          }

          return http.Response(
            cuerpoDeSesion(
              accessToken: 'at_1',
              refreshToken: 'rt_1',
              accesoDura: const Duration(seconds: 10),
            ),
            200,
          );
        });

        await armado.gestor.iniciarSesion(email: 'a@b.mx', password: 'x');

        final refresco = armado.gestor.tokenDeAccesoVigente();
        await llego.future;

        await armado.gestor.cerrarSesion();
        compuerta.complete();

        final resultado = await refresco;

        expect(
          exigirFallo(resultado),
          isA<ApiSinSesionFailure>(),
          reason: 'el token rotado pertenece a una sesión que ya no existe',
        );
        expect(armado.gestor.estado, isA<NoAutenticado>());
        expect(
          armado.almacen.guardada,
          isNull,
          reason: 'guardarlo haría que el próximo arranque entrara solo',
        );
        expect(armado.gestor.hayCredencial, isFalse);
      },
    );

    test(
      'un login nuevo mientras el refresco viaja también lo descarta',
      () async {
        final llego = Completer<void>();
        final compuerta = Completer<void>();

        final armado = construir((peticion) async {
          if (peticion.url.path.endsWith('/auth/refresh')) {
            if (!llego.isCompleted) llego.complete();
            await compuerta.future;
            return http.Response(
              cuerpoDeSesion(
                accessToken: 'at_viejo_2',
                refreshToken: 'rt_viejo_2',
              ),
              200,
            );
          }

          return http.Response(
            cuerpoDeSesion(
              accessToken: llego.isCompleted ? 'at_nuevo' : 'at_1',
              refreshToken: llego.isCompleted ? 'rt_nuevo' : 'rt_1',
              accesoDura: const Duration(seconds: 10),
            ),
            200,
          );
        });

        await armado.gestor.iniciarSesion(email: 'a@b.mx', password: 'x');

        final refresco = armado.gestor.tokenDeAccesoVigente();
        await llego.future;

        await armado.gestor.iniciarSesion(email: 'otra@b.mx', password: 'x');
        compuerta.complete();

        expect(exigirFallo(await refresco), isA<ApiSinSesionFailure>());
        expect(
          armado.almacen.guardada?.refreshToken,
          'rt_nuevo',
          reason: 'el refresco de la sesión anterior no puede pisar la nueva',
        );
      },
    );

    test(
      'el apunte del refresco se limpia: el siguiente lote pide uno nuevo',
      () async {
        var numero = 1;

        final armado = construir((peticion) async {
          if (peticion.url.path.endsWith('/auth/refresh')) {
            numero++;
            return http.Response(
              cuerpoDeSesion(
                accessToken: 'at_$numero',
                refreshToken: 'rt_$numero',
                accesoDura: const Duration(seconds: 10),
              ),
              200,
            );
          }

          return http.Response(
            cuerpoDeSesion(
              accessToken: 'at_1',
              refreshToken: 'rt_1',
              accesoDura: const Duration(seconds: 10),
            ),
            200,
          );
        });

        await armado.gestor.iniciarSesion(email: 'a@b.mx', password: 'x');

        // Cada llamada encuentra el acceso ya dentro de la ventana, así que cada
        // una debe provocar su propio refresco: el «single-flight» agrupa lo
        // simultáneo, no lo sucesivo.
        expect(exigirToken(await armado.gestor.tokenDeAccesoVigente()), 'at_2');
        expect(exigirToken(await armado.gestor.tokenDeAccesoVigente()), 'at_3');
        expect(cuantas(armado.vistas, '/auth/refresh'), 2);
      },
    );
  });

  // =========================================================================
  group('Cuando el backend rechaza el refresco', () {
    test('un 401 reutilizado cierra la sesión y borra la credencial', () async {
      final armado = construir((peticion) async {
        if (peticion.url.path.endsWith('/auth/refresh')) {
          return http.Response(
            '{"code":"refresh_reutilizado","message":"La sesión se cerró por seguridad."}',
            401,
          );
        }

        return http.Response(
          cuerpoDeSesion(
            accessToken: 'at_1',
            refreshToken: 'rt_1',
            accesoDura: const Duration(seconds: 10),
          ),
          200,
        );
      });

      await armado.gestor.iniciarSesion(email: 'a@b.mx', password: 'x');

      final fallo = exigirFallo(await armado.gestor.tokenDeAccesoVigente());

      expect((fallo as ApiHttpFailure).codigo, 'refresh_reutilizado');
      expect(armado.gestor.estado, isA<NoAutenticado>());
      expect(armado.almacen.guardada, isNull);
      expect(armado.almacen.borrados, greaterThan(0));
    });

    test('un 401 invalido también cierra: no hay nada que salvar', () async {
      final armado = construir((peticion) async {
        if (peticion.url.path.endsWith('/auth/refresh')) {
          return http.Response('{"code":"refresh_invalido"}', 401);
        }

        return http.Response(
          cuerpoDeSesion(
            accessToken: 'at_1',
            refreshToken: 'rt_1',
            accesoDura: const Duration(seconds: 10),
          ),
          200,
        );
      });

      await armado.gestor.iniciarSesion(email: 'a@b.mx', password: 'x');
      await armado.gestor.tokenDeAccesoVigente();

      expect(armado.gestor.estado, isA<NoAutenticado>());
      expect(armado.almacen.guardada, isNull);
    });

    test('un 500 NO cierra la sesión: no dice nada del token', () async {
      final armado = construir((peticion) async {
        if (peticion.url.path.endsWith('/auth/refresh')) {
          return http.Response('', 500);
        }

        return http.Response(
          cuerpoDeSesion(
            accessToken: 'at_1',
            refreshToken: 'rt_1',
            accesoDura: const Duration(seconds: 10),
          ),
          200,
        );
      });

      await armado.gestor.iniciarSesion(email: 'a@b.mx', password: 'x');
      await armado.gestor.tokenDeAccesoVigente();

      expect(armado.gestor.estado, isA<Autenticado>());
      expect(armado.almacen.guardada?.refreshToken, 'rt_1');
    });

    test('un 429 del limitador tampoco cierra la sesión', () async {
      final armado = construir((peticion) async {
        if (peticion.url.path.endsWith('/auth/refresh')) {
          return http.Response('Too Many Requests', 429);
        }

        return http.Response(
          cuerpoDeSesion(
            accessToken: 'at_1',
            refreshToken: 'rt_1',
            accesoDura: const Duration(seconds: 10),
          ),
          200,
        );
      });

      await armado.gestor.iniciarSesion(email: 'a@b.mx', password: 'x');
      await armado.gestor.tokenDeAccesoVigente();

      expect(armado.gestor.estado, isA<Autenticado>());
      expect(armado.almacen.guardada, isNotNull);
    });
  });

  // =========================================================================
  group('Un fallo de red NO destruye la credencial', () {
    test(
      'sin conexión, la credencial sigue guardada y la sesión no se cierra',
      () async {
        var caido = false;

        final armado = construir((peticion) async {
          if (caido) throw http.ClientException('sin red');

          return http.Response(
            cuerpoDeSesion(
              accessToken: 'at_1',
              refreshToken: 'rt_1',
              accesoDura: const Duration(seconds: 10),
            ),
            200,
          );
        });

        await armado.gestor.iniciarSesion(email: 'a@b.mx', password: 'x');
        caido = true;

        final fallo = exigirFallo(await armado.gestor.tokenDeAccesoVigente());

        expect(fallo, isA<ApiSinConexionFailure>());
        expect(
          armado.almacen.guardada?.refreshToken,
          'rt_1',
          reason: 'tirarla convertiría un bache de red en un cierre de sesión',
        );
        expect(armado.gestor.estado, isA<Autenticado>());
        expect(armado.gestor.hayCredencial, isTrue);
      },
    );

    test('cuando vuelve la red, el mismo gestor se recupera solo', () async {
      var caido = true;
      var numero = 1;

      final armado = construir((peticion) async {
        if (peticion.url.path.endsWith('/auth/refresh')) {
          if (caido) throw http.ClientException('sin red');
          numero++;
          return http.Response(
            cuerpoDeSesion(
              accessToken: 'at_$numero',
              refreshToken: 'rt_$numero',
            ),
            200,
          );
        }

        return http.Response(
          cuerpoDeSesion(
            accessToken: 'at_1',
            refreshToken: 'rt_1',
            accesoDura: const Duration(seconds: 10),
          ),
          200,
        );
      });

      await armado.gestor.iniciarSesion(email: 'a@b.mx', password: 'x');
      expect((await armado.gestor.tokenDeAccesoVigente()).isFailure, isTrue);

      caido = false;

      expect(exigirToken(await armado.gestor.tokenDeAccesoVigente()), 'at_2');
      expect(armado.gestor.estado, isA<Autenticado>());
    });
  });

  // =========================================================================
  group('Restaurar', () {
    test('sin nada guardado: NoAutenticado y ni una petición', () async {
      final armado = construir((_) async => http.Response('', 500));

      expect(await armado.gestor.restaurar(), isA<NoAutenticado>());
      expect(armado.vistas, isEmpty);
    });

    test(
      'con una credencial caducada: se descarta sin preguntar al servidor',
      () async {
        // Pedir un refresco con esto sólo puede acabar en 401.
        final armado = construir(
          (_) async => http.Response('', 500),
          guardada: credencialGuardada(caducaEn: const Duration(days: -1)),
        );

        expect(await armado.gestor.restaurar(), isA<NoAutenticado>());
        expect(armado.vistas, isEmpty);
        expect(armado.almacen.guardada, isNull);
      },
    );

    test('con una credencial buena: la CONFIRMA contra el servidor', () async {
      final armado = construir(
        (_) async => http.Response(
          cuerpoDeSesion(
            accessToken: 'at_2',
            refreshToken: 'rt_2',
            email: null,
            displayName: null,
          ),
          200,
        ),
        guardada: credencialGuardada(),
      );

      final estado = await armado.gestor.restaurar();

      expect(estado, isA<Autenticado>());
      expect(cuantas(armado.vistas, '/auth/refresh'), 1);
      expect(armado.almacen.guardada?.refreshToken, 'rt_2');
      expect(exigirToken(await armado.gestor.tokenDeAccesoVigente()), 'at_2');
    });

    test(
      'la identidad guardada sobrevive a un refresco que no la reenvía',
      () async {
        final armado = construir(
          (_) async => http.Response(
            cuerpoDeSesion(
              accessToken: 'at_2',
              refreshToken: 'rt_2',
              email: null,
              displayName: null,
            ),
            200,
          ),
          guardada: credencialGuardada(),
        );

        final estado = await armado.gestor.restaurar() as Autenticado;

        expect(estado.sesion.email, 'ana@seventra.mx');
        expect(estado.sesion.displayName, 'Ana Torres');
      },
    );

    test(
      'si el backend la rechaza: NoAutenticado y se borra el rastro',
      () async {
        final armado = construir(
          (_) async => http.Response('{"code":"refresh_invalido"}', 401),
          guardada: credencialGuardada(),
        );

        expect(await armado.gestor.restaurar(), isA<NoAutenticado>());
        expect(armado.almacen.guardada, isNull);
      },
    );

    test(
      'sin red: SesionRemotaSinConfirmar, y la credencial NO se toca',
      () async {
        final armado = construir(
          (_) async => throw http.ClientException('sin red'),
          guardada: credencialGuardada(),
        );

        final estado = await armado.gestor.restaurar();

        expect(estado, isA<SesionRemotaSinConfirmar>());
        expect(
          (estado as SesionRemotaSinConfirmar).motivo,
          isA<ApiSinConexionFailure>(),
        );
        expect(armado.almacen.guardada?.refreshToken, 'rt_1');
        expect(
          armado.gestor.hayCredencial,
          isTrue,
          reason: 'el siguiente intento la volverá a usar',
        );
      },
    );

    test('dos restauraciones simultáneas producen UN solo canje', () async {
      // El mismo peligro que el refresco, por otra puerta: las dos leerían el
      // mismo token del disco y lo canjearían dos veces, y el backend lee eso
      // como reutilización y revoca la sesión completa.
      final armado = construir(
        (_) async => http.Response(
          cuerpoDeSesion(accessToken: 'at_2', refreshToken: 'rt_2'),
          200,
        ),
        guardada: credencialGuardada(),
      );

      final estados = await Future.wait([
        armado.gestor.restaurar(),
        armado.gestor.restaurar(),
      ]);

      expect(cuantas(armado.vistas, '/auth/refresh'), 1);
      expect(estados.every((e) => e is Autenticado), isTrue);
    });

    test('restaurar de nuevo DESPUÉS sí vuelve a preguntar', () async {
      // Agrupa lo simultáneo, no lo sucesivo.
      var numero = 1;

      final armado = construir((_) async {
        numero++;
        return http.Response(
          cuerpoDeSesion(accessToken: 'at_$numero', refreshToken: 'rt_$numero'),
          200,
        );
      }, guardada: credencialGuardada());

      await armado.gestor.restaurar();
      await armado.gestor.restaurar();

      expect(cuantas(armado.vistas, '/auth/refresh'), 2);
    });

    test(
      'un almacén que no se puede leer se trata como «no hay nada»',
      () async {
        final armado = construir(
          (_) async => http.Response('', 500),
          almacenAlterno: _AlmacenQueFalla(),
        );

        expect(await armado.gestor.restaurar(), isA<NoAutenticado>());
        expect(armado.vistas, isEmpty);
      },
    );
  });

  // =========================================================================
  group('Cerrar sesión', () {
    test(
      'deja NoAutenticado, borra la credencial y avisa al backend',
      () async {
        final armado = construir((peticion) async {
          if (peticion.url.path.endsWith('/auth/logout')) {
            return http.Response('', 204);
          }

          return http.Response(
            cuerpoDeSesion(accessToken: 'at_1', refreshToken: 'rt_1'),
            200,
          );
        });

        await armado.gestor.iniciarSesion(email: 'a@b.mx', password: 'x');
        await armado.gestor.cerrarSesion();

        expect(armado.gestor.estado, isA<NoAutenticado>());
        expect(armado.almacen.guardada, isNull);

        await armado.gestor.avisoDeCierreEnVuelo;

        expect(cuantas(armado.vistas, '/auth/logout'), 1);
        expect(
          armado.vistas.last.headers['Authorization'],
          'Bearer at_1',
          reason: 'el backend necesita saber QUÉ sesión cerrar',
        );
      },
    );

    test('con el backend caído, el cierre local se completa igual', () async {
      var caido = false;

      final armado = construir((peticion) async {
        if (caido) throw http.ClientException('caído');

        return http.Response(
          cuerpoDeSesion(accessToken: 'at_1', refreshToken: 'rt_1'),
          200,
        );
      });

      await armado.gestor.iniciarSesion(email: 'a@b.mx', password: 'x');
      caido = true;

      await armado.gestor.cerrarSesion();

      expect(armado.gestor.estado, isA<NoAutenticado>());
      expect(armado.almacen.guardada, isNull);

      // El aviso falla y no pasa nada: sin cola de revocación. El token de
      // acceso caduca solo y el de refresco ya no existe en este equipo.
      await armado.gestor.avisoDeCierreEnVuelo;

      expect(armado.gestor.estado, isA<NoAutenticado>());
    });

    test(
      'con un almacén que no puede borrar, el cierre TAMBIÉN se completa',
      () async {
        final armado = construir(
          (_) async => http.Response(
            cuerpoDeSesion(accessToken: 'at_1', refreshToken: 'rt_1'),
            200,
          ),
          almacenAlterno: _AlmacenQueFalla(),
        );

        await armado.gestor.iniciarSesion(email: 'a@b.mx', password: 'x');
        await armado.gestor.cerrarSesion();

        expect(armado.gestor.estado, isA<NoAutenticado>());
        expect(armado.gestor.hayCredencial, isFalse);
      },
    );

    test('después de cerrar, no se puede firmar nada', () async {
      final armado = construir(
        (_) async => http.Response(
          cuerpoDeSesion(accessToken: 'at_1', refreshToken: 'rt_1'),
          200,
        ),
      );

      await armado.gestor.iniciarSesion(email: 'a@b.mx', password: 'x');
      await armado.gestor.cerrarSesion();

      expect(
        exigirFallo(await armado.gestor.tokenDeAccesoVigente()),
        isA<ApiSinSesionFailure>(),
      );
      expect(
        exigirFallo(await armado.gestor.renovarTrasRechazo('at_1')),
        isA<ApiSinSesionFailure>(),
      );
    });

    test('cerrar sin sesión abierta no rompe ni llama a nadie', () async {
      final armado = construir((_) async => http.Response('', 204));

      await armado.gestor.cerrarSesion();

      expect(armado.gestor.estado, isA<NoAutenticado>());
      expect(armado.vistas, isEmpty);
    });
  });

  // =========================================================================
  group('Sin sesión no se pide nada al servidor', () {
    test('tokenDeAccesoVigente falla antes de enviar', () async {
      final armado = construir((_) async => http.Response('', 200));

      expect(
        exigirFallo(await armado.gestor.tokenDeAccesoVigente()),
        isA<ApiSinSesionFailure>(),
      );
      expect(
        armado.vistas,
        isEmpty,
        reason: 'un viaje para cosechar un 401 gasta cuota del limitador',
      );
    });
  });

  // =========================================================================
  group('El estado observable', () {
    test('empieza sin resolver y avisa de cada cambio', () async {
      final armado = construir(
        (_) async => http.Response(
          cuerpoDeSesion(accessToken: 'at_1', refreshToken: 'rt_1'),
          200,
        ),
      );

      final vistos = <EstadoAutenticacion>[];
      armado.gestor.estadoObservable.addListener(
        () => vistos.add(armado.gestor.estado),
      );

      expect(armado.gestor.estado, isA<AutenticacionSinResolver>());

      await armado.gestor.iniciarSesion(email: 'a@b.mx', password: 'x');
      await armado.gestor.cerrarSesion();

      expect(vistos.map((e) => e.runtimeType).toList(), [
        Autenticado,
        NoAutenticado,
      ]);
    });

    test(
      'un refresco que vuelve tras desechar el gestor no revienta',
      () async {
        // Escribir en un `ValueNotifier` desechado lanza, y hacerlo desde una
        // continuación asíncrona produce un error sin relación visible con su
        // causa. Es mejor que el resultado tardío no se publique.
        final llego = Completer<void>();
        final compuerta = Completer<void>();

        final armado = construir((peticion) async {
          if (peticion.url.path.endsWith('/auth/refresh')) {
            if (!llego.isCompleted) llego.complete();
            await compuerta.future;
            return http.Response(
              cuerpoDeSesion(accessToken: 'at_2', refreshToken: 'rt_2'),
              200,
            );
          }

          return http.Response(
            cuerpoDeSesion(
              accessToken: 'at_1',
              refreshToken: 'rt_1',
              accesoDura: const Duration(seconds: 10),
            ),
            200,
          );
        });

        await armado.gestor.iniciarSesion(email: 'a@b.mx', password: 'x');

        final refresco = armado.gestor.tokenDeAccesoVigente();
        await llego.future;

        armado.gestor.dispose();
        compuerta.complete();

        expect(exigirToken(await refresco), 'at_2');
      },
    );

    test('desechar dos veces no lanza', () async {
      final armado = construir((_) async => http.Response('', 204));

      armado.gestor.dispose();

      expect(armado.gestor.dispose, returnsNormally);
    });

    test('tiene valor actual: quien llega tarde no espera un evento', () async {
      final armado = construir(
        (_) async => http.Response(
          cuerpoDeSesion(accessToken: 'at_1', refreshToken: 'rt_1'),
          200,
        ),
      );

      await armado.gestor.iniciarSesion(email: 'a@b.mx', password: 'x');

      expect(armado.gestor.estadoObservable.value, isA<Autenticado>());
    });
  });

  // =========================================================================
  test(
    'La maquinaria remota se autentica, refresca y restaura SOLA: sin base de '
    'datos, sin Usuario y sin ProviderScope',
    () async {
      // Es la demostración del criterio de cierre de IF-2: el motor remoto no
      // necesita nada del producto local para funcionar, y por eso puede existir
      // completo antes de que exista el relevo del portón.
      var numero = 1;
      final disco = _AlmacenEnMemoria();

      final cliente = ApiClient(
        config: config,
        cliente: MockClient((peticion) async {
          if (peticion.url.path.endsWith('/auth/refresh')) {
            numero++;
            return http.Response(
              cuerpoDeSesion(
                accessToken: 'at_$numero',
                refreshToken: 'rt_$numero',
                email: null,
                displayName: null,
              ),
              200,
            );
          }

          return http.Response(
            cuerpoDeSesion(accessToken: 'at_1', refreshToken: 'rt_1'),
            200,
          );
        }),
        logger: AppLogger.console(),
      );

      final primero = GestorDeSesion(
        api: AuthApi(cliente),
        almacen: disco,
        logger: AppLogger.console(),
        ahora: () => reloj,
      );

      await primero.iniciarSesion(email: 'ana@seventra.mx', password: 'x');
      expect(primero.estado, isA<Autenticado>());
      primero.dispose();

      // Otro arranque: un gestor nuevo, el mismo disco.
      final segundo = GestorDeSesion(
        api: AuthApi(cliente),
        almacen: disco,
        logger: AppLogger.console(),
        ahora: () => reloj,
      );
      addTearDown(segundo.dispose);

      final estado = await segundo.restaurar();

      expect(estado, isA<Autenticado>());
      expect((estado as Autenticado).sesion.email, 'ana@seventra.mx');
      expect(exigirToken(await segundo.tokenDeAccesoVigente()), 'at_2');
    },
  );
}
