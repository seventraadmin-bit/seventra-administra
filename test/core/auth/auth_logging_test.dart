// Integration Foundation IF-2 — la redacción de los registros de autenticación.
//
// ESTAS PRUEBAS EXISTEN ANTES DE QUE HAYA UNA FUGA, no después. La capa de sesión
// es el sitio del proyecto donde más fácil se filtra un secreto por registro: pasan
// por ella una contraseña, un token de acceso y un token de refresco que vale
// catorce días. Un `logger.debug('$respuesta')` de diagnóstico puesto un martes deja
// cualquiera de los tres copiado en un archivo que nadie revisa.
//
// Se capturan los registros REALES con `Logger.addOutputListener`, así que lo que se
// afirma es lo que de verdad sale, no lo que el código pretende escribir.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logger/logger.dart';
import 'package:riseg_one/core/api/api_client.dart';
import 'package:riseg_one/core/api/api_client_autenticado.dart';
import 'package:riseg_one/core/auth/almacen_sesion_remota.dart';
import 'package:riseg_one/core/auth/auth_api.dart';
import 'package:riseg_one/core/auth/gestor_de_sesion.dart';
import 'package:riseg_one/core/auth/sesion_remota.dart';
import 'package:riseg_one/core/config/api_config.dart';
import 'package:riseg_one/core/logging/app_logger.dart';

const String _password = 'Sup3rSecretaDeAna!';
const String _acceso = 'at_TOKEN_DE_ACCESO_SECRETO';
const String _refresco = 'rt_TOKEN_DE_REFRESCO_SECRETO';

class _AlmacenEnMemoria implements AlmacenSesionRemota {
  CredencialRemota? guardada;

  @override
  Future<CredencialRemota?> leer() async => guardada;

  @override
  Future<void> escribir(CredencialRemota credencial) async =>
      guardada = credencial;

  @override
  Future<void> borrar() async => guardada = null;
}

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

  final t0 = DateTime.utc(2026, 9, 28, 12);

  late List<String> capturado;
  late OutputCallback escucha;

  setUp(() {
    capturado = [];
    escucha = (evento) => capturado.addAll(evento.lines);
    Logger.addOutputListener(escucha);
  });

  tearDown(() => Logger.removeOutputListener(escucha));

  String todoLoRegistrado() => capturado.join('\n');

  void noSeFiltraNingunSecreto() {
    final registro = todoLoRegistrado();

    expect(registro, isNot(contains(_password)), reason: 'la contraseña');
    expect(registro, isNot(contains(_acceso)), reason: 'el token de acceso');
    expect(
      registro,
      isNot(contains(_refresco)),
      reason: 'el token de refresco',
    );
    expect(
      registro,
      isNot(contains('Bearer ')),
      reason: 'el encabezado firmado',
    );
  }

  String cuerpoDeSesion({
    String accessToken = _acceso,
    String refreshToken = _refresco,
    Duration accesoDura = const Duration(minutes: 30),
  }) => jsonEncode({
    'accessToken': accessToken,
    'accessExpiresAt': t0.add(accesoDura).toIso8601String(),
    'refreshToken': refreshToken,
    'refreshExpiresAt': t0.add(const Duration(days: 14)).toIso8601String(),
    'sessionId': '0193f0a0-0000-7000-8000-000000000001',
    'displayName': 'Ana Torres',
    'email': 'ana@seventra.mx',
  });

  ({GestorDeSesion gestor, ApiClientAutenticado cliente}) construir(
    Future<http.Response> Function(http.Request) responder, {
    AlmacenSesionRemota? almacen,
  }) {
    final desnudo = ApiClient(
      config: config,
      cliente: MockClient(responder),
      logger: AppLogger.console(),
    );

    final gestor = GestorDeSesion(
      api: AuthApi(desnudo),
      almacen: almacen ?? _AlmacenEnMemoria(),
      logger: AppLogger.console(),
      ahora: () => t0,
    );

    addTearDown(gestor.dispose);

    return (
      gestor: gestor,
      cliente: ApiClientAutenticado(cliente: desnudo, gestor: gestor),
    );
  }

  test('Un login correcto no deja ni la contraseña ni los tokens', () async {
    final armado = construir((_) async => http.Response(cuerpoDeSesion(), 200));

    await armado.gestor.iniciarSesion(
      email: 'ana@seventra.mx',
      password: _password,
    );

    // Sí se registra que hubo login, con su ruta y su status: eso es lo que hace
    // falta para diagnosticar.
    expect(todoLoRegistrado(), contains('/auth/login'));
    expect(todoLoRegistrado(), contains('200'));
    noSeFiltraNingunSecreto();
  });

  test('Un login FALLIDO tampoco deja la contraseña', () async {
    // Es el caso más peligroso: al depurar un «no puedo entrar» la tentación es
    // registrar lo que se envió.
    final armado = construir(
      (_) async => http.Response('{"code":"credenciales_invalidas"}', 401),
    );

    await armado.gestor.iniciarSesion(
      email: 'ana@seventra.mx',
      password: _password,
    );

    expect(todoLoRegistrado(), contains('401'));
    noSeFiltraNingunSecreto();
  });

  test('El refresco no deja ninguno de los dos tokens', () async {
    final armado = construir((peticion) async {
      if (peticion.url.path.endsWith('/auth/refresh')) {
        return http.Response(
          cuerpoDeSesion(
            accessToken: 'at_SEGUNDO_SECRETO',
            refreshToken: 'rt_SEGUNDO_SECRETO',
          ),
          200,
        );
      }

      return http.Response(
        cuerpoDeSesion(accesoDura: const Duration(seconds: 10)),
        200,
      );
    });

    await armado.gestor.iniciarSesion(email: 'a@b.mx', password: _password);
    await armado.gestor.tokenDeAccesoVigente();

    expect(todoLoRegistrado(), contains('/auth/refresh'));
    noSeFiltraNingunSecreto();
    expect(todoLoRegistrado(), isNot(contains('at_SEGUNDO_SECRETO')));
    expect(todoLoRegistrado(), isNot(contains('rt_SEGUNDO_SECRETO')));
  });

  test('Un refresco rechazado registra el cierre sin el token', () async {
    final armado = construir((peticion) async {
      if (peticion.url.path.endsWith('/auth/refresh')) {
        return http.Response('{"code":"refresh_reutilizado"}', 401);
      }

      return http.Response(
        cuerpoDeSesion(accesoDura: const Duration(seconds: 10)),
        200,
      );
    });

    await armado.gestor.iniciarSesion(email: 'a@b.mx', password: _password);
    await armado.gestor.tokenDeAccesoVigente();

    expect(todoLoRegistrado(), contains('refresco'));
    noSeFiltraNingunSecreto();
  });

  test(
    'El cierre de sesión no registra el token con el que se firmó',
    () async {
      final armado = construir((peticion) async {
        if (peticion.url.path.endsWith('/auth/logout')) {
          return http.Response('', 204);
        }

        return http.Response(cuerpoDeSesion(), 200);
      });

      await armado.gestor.iniciarSesion(email: 'a@b.mx', password: _password);
      await armado.gestor.cerrarSesion();
      await armado.gestor.avisoDeCierreEnVuelo;

      expect(todoLoRegistrado(), contains('/auth/logout'));
      noSeFiltraNingunSecreto();
    },
  );

  test(
    'El identificador de sesión SÍ se registra: hace falta y no es un secreto',
    () async {
      // Es lo que permite correlacionar con la auditoría de seguridad del backend.
      // No sirve para autenticarse.
      final armado = construir(
        (_) async => http.Response(cuerpoDeSesion(), 200),
      );

      await armado.gestor.iniciarSesion(email: 'a@b.mx', password: _password);

      expect(
        todoLoRegistrado(),
        contains('0193f0a0-0000-7000-8000-000000000001'),
      );
    },
  );

  test(
    'Una petición firmada no registra su encabezado Authorization',
    () async {
      final armado = construir(
        (peticion) async =>
            peticion.url.path.endsWith('/auth/login')
                ? http.Response(cuerpoDeSesion(), 200)
                : http.Response('{}', 200),
      );

      await armado.gestor.iniciarSesion(email: 'a@b.mx', password: _password);
      await armado.cliente.get('/companies/abc/employees');

      expect(todoLoRegistrado(), contains('/companies/abc/employees'));
      noSeFiltraNingunSecreto();
    },
  );

  test('El reintento tras un 401 no filtra ningún token', () async {
    var rechazado = false;

    final armado = construir((peticion) async {
      if (peticion.url.path.endsWith('/auth/login')) {
        return http.Response(cuerpoDeSesion(), 200);
      }

      if (peticion.url.path.endsWith('/auth/refresh')) {
        return http.Response(
          cuerpoDeSesion(
            accessToken: 'at_TERCERO_SECRETO',
            refreshToken: 'rt_TERCERO_SECRETO',
          ),
          200,
        );
      }

      if (!rechazado) {
        rechazado = true;
        return http.Response('{"code":"sesion_invalida"}', 401);
      }

      return http.Response('{}', 200);
    });

    await armado.gestor.iniciarSesion(email: 'a@b.mx', password: _password);
    await armado.cliente.get('/companies');

    noSeFiltraNingunSecreto();
    expect(todoLoRegistrado(), isNot(contains('at_TERCERO_SECRETO')));
    expect(todoLoRegistrado(), isNot(contains('rt_TERCERO_SECRETO')));
  });

  test('Un almacén que falla se registra SIN la credencial', () async {
    final armado = construir(
      (_) async => http.Response(cuerpoDeSesion(), 200),
      almacen: _AlmacenQueFalla(),
    );

    await armado.gestor.iniciarSesion(email: 'a@b.mx', password: _password);

    expect(todoLoRegistrado(), contains('No se pudo guardar'));
    noSeFiltraNingunSecreto();
  });
}
