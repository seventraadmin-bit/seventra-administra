// UN ERROR AL LEER LA RESPUESTA ACABA EN EL ESTADO DE ERROR, NUNCA EN CARGA INFINITA.
//
// ===========================================================================
// POR QUÉ EXISTE, Y ES LA PANTALLA ROTA DEL 11 DE NOVIEMBRE DE 2026 (D-74)
// ===========================================================================
//
// `ClienteEnLista.deJson` leía `createdAt`, que la FICHA publicaba y la FILA no. Al leer
// el listado, el `as String` sobre un nulo **lanzaba**.
//
// 🚫 **Y lanzar dentro de la rama `ok:` de un `Result` no produce un fallo: rompe la
// cadena del `await`.** El `setState(() => _cargando = false)` de la pantalla **nunca se
// ejecuta**, así que lo que se ve no es un error: es un indicador de carga que **no se
// apaga nunca**. Parece lentitud, invita a esperar, y no hay nada que leer.
//
// ===========================================================================
// LO QUE SE FIJA AQUÍ
// ===========================================================================
//
// Dos propiedades, y hacen falta las dos:
//
//  1. **el repositorio devuelve un `Result.failure`** cuando la respuesta no cuadra con el
//     modelo — nunca lanza;
//  2. **la pantalla lo pinta**: el estado de error con su botón, no el indicador de carga.
//
// La (1) sola no bastaría: un fallo que ninguna pantalla pinta es un fallo invisible. Y la
// (2) sola tampoco: mide una pantalla y deja las otras nueve.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riseg_one/app/shell/apartados_web.dart' show CapacidadesDeModulo;
import 'package:riseg_one/core/api/api_client.dart';
import 'package:riseg_one/core/api/api_client_autenticado.dart';
import 'package:riseg_one/core/api/lectura_del_contrato.dart';
import 'package:riseg_one/core/auth/almacen_sesion_remota.dart';
import 'package:riseg_one/core/auth/auth_api.dart';
import 'package:riseg_one/core/auth/gestor_de_sesion.dart';
import 'package:riseg_one/core/auth/sesion_remota.dart';
import 'package:riseg_one/core/config/api_config.dart';
import 'package:riseg_one/core/error/failure.dart';
import 'package:riseg_one/core/logging/app_logger.dart';
import 'package:riseg_one/core/trabajo_sin_guardar/guardia_de_salida.dart';
import 'package:riseg_one/features/comercial/web/datos/clientes_repositorio_http.dart';
import 'package:riseg_one/features/comercial/web/datos/servicios_repositorio_http.dart';
import 'package:riseg_one/features/comercial/web/presentation/clientes_web_screen.dart';
import 'package:riseg_one/features/personal/web/datos/empleados_repositorio_http.dart';
import 'package:riseg_one/features/usuarios/web/marca_seventra.dart';

class _Almacen implements AlmacenSesionRemota {
  CredencialRemota? guardada;

  @override
  Future<CredencialRemota?> leer() async => guardada;

  @override
  Future<void> escribir(CredencialRemota credencial) async =>
      guardada = credencial;

  @override
  Future<void> borrar() async => guardada = null;
}

void main() {
  final config = ApiConfig.resolve(
    raw: 'http://localhost:5199',
  ).when(ok: (c) => c, failure: (f) => throw StateError(f.message));

  final t0 = DateTime.utc(2026, 11, 11, 12);

  const empresa = '0193f0a0-0000-7000-8000-000000000001';
  const cliente = '0193f0a0-0000-7000-8000-0000000000c1';
  const servicio = '0193f0a0-0000-7000-8000-0000000000a1';

  /// Un cliente **al que le falta `createdAt`**: exactamente el cuerpo que el ensayo
  /// devolvía el 11-nov-2026.
  const filaSinCreatedAt = {
    'id': cliente,
    'code': 'CLI-000004',
    'commercialName': 'Sportium',
    'status': 'active',
    'startedOn': '2025-03-01',
    'notes': null,
    'updatedAt': '2026-10-20T18:00:00Z',
    'location': null,
    'activeServices': 0,
    'suspendedServices': 0,
    'logoFileId': null,
  };

  Future<ApiClientAutenticado> cliente_(
    http.Response Function(http.BaseRequest p) responder,
  ) async {
    final desnudo = ApiClient(
      config: config,
      cliente: MockClient((p) async {
        if (p.url.path.endsWith('/auth/login')) {
          return http.Response(
            jsonEncode({
              'accessToken': 'at_1',
              'accessExpiresAt': t0
                  .add(const Duration(minutes: 30))
                  .toIso8601String(),
              'refreshToken': 'rt_1',
              'refreshExpiresAt': t0
                  .add(const Duration(days: 14))
                  .toIso8601String(),
              'sessionId': '0193f0a0-0000-7000-8000-00000000aaaa',
              'identityId': '0193f0a0-0000-7000-8000-00000000bbbb',
              'displayName': 'Ana Torres',
              'email': 'ana@seventra.mx',
            }),
            200,
          );
        }

        return responder(p);
      }),
      logger: AppLogger.console(),
    );

    final gestor = GestorDeSesion(
      api: AuthApi(desnudo),
      almacen: _Almacen(),
      logger: AppLogger.console(),
      ahora: () => t0,
    );

    addTearDown(gestor.dispose);
    await gestor.iniciarSesion(email: 'ana@seventra.mx', password: 'x');

    return ApiClientAutenticado(cliente: desnudo, gestor: gestor);
  }

  // =========================================================================
  group('el ayudante', () {
    test('un `as` que falla se convierte en FALLO, no en excepción', () {
      // ⚠️ SE ATRAPA `Object` Y NO `Exception`, y aquí se mide: un `as` que falla lanza
      // un `TypeError`, que es un `Error` y **no** un `Exception`. Atrapar sólo
      // `Exception` habría dejado pasar exactamente el fallo que esto existe para cazar.
      final resultado = leyendo<String>(
        'una cosa',
        () => (null as Object?) as String,
      );

      expect(
        resultado.when(ok: (_) => null, failure: (f) => f),
        isA<ApiJsonInvalidoFailure>(),
      );
    });

    test('lo que se lee bien pasa intacto', () {
      expect(
        leyendo('un número', () => 42).when(ok: (v) => v, failure: (_) => null),
        42,
      );
    });

    test('el mensaje dice QUÉ se estaba leyendo', () {
      final mensaje = leyendo<String>('el listado de clientes', () {
        throw StateError('x');
      }).when(ok: (_) => '', failure: (f) => f.message);

      expect(mensaje, contains('el listado de clientes'));
      expect(mensaje, contains('desactualizada'));
    });
  });

  // =========================================================================
  group('los repositorios devuelven FALLO y no lanzan', () {
    test('el listado de clientes sin `createdAt` — el caso real', () async {
      final api = await cliente_(
        (_) => http.Response(
          jsonEncode({'items': [filaSinCreatedAt], 'nextCursor': null}),
          200,
        ),
      );

      final resultado = await ClientesRepositorioHttp(api).listar(empresa);

      expect(
        resultado.when(ok: (_) => null, failure: (f) => f),
        isA<ApiJsonInvalidoFailure>(),
      );
    });

    test('la ficha de un cliente mal formada', () async {
      final api = await cliente_(
        (_) => http.Response(jsonEncode({'id': cliente}), 200),
      );

      final resultado = await ClientesRepositorioHttp(
        api,
      ).ver(empresaId: empresa, clienteId: cliente);

      expect(
        resultado.when(ok: (_) => null, failure: (f) => f),
        isA<ApiJsonInvalidoFailure>(),
      );
    });

    test('el listado de servicios mal formado', () async {
      final api = await cliente_(
        (_) => http.Response(
          jsonEncode({
            'items': [
              {'id': servicio},
            ],
            'nextCursor': null,
          }),
          200,
        ),
      );

      final resultado = await ServiciosRepositorioHttp(api).listar(empresa);

      expect(
        resultado.when(ok: (_) => null, failure: (f) => f),
        isA<ApiJsonInvalidoFailure>(),
      );
    });

    test('la ficha de un servicio mal formada', () async {
      final api = await cliente_(
        (_) => http.Response(jsonEncode({'id': servicio}), 200),
      );

      final resultado = await ServiciosRepositorioHttp(
        api,
      ).ver(empresaId: empresa, servicioId: servicio);

      expect(
        resultado.when(ok: (_) => null, failure: (f) => f),
        isA<ApiJsonInvalidoFailure>(),
      );
    });

    test('los tipos de servicio mal formados', () async {
      final api = await cliente_(
        (_) => http.Response(
          jsonEncode([
            {'id': servicio},
          ]),
          200,
        ),
      );

      final resultado = await ServiciosRepositorioHttp(
        api,
      ).tipos(empresa, usados: null);

      expect(
        resultado.when(ok: (_) => null, failure: (f) => f),
        isA<ApiJsonInvalidoFailure>(),
      );
    });

    test('los empleados del selector de supervisor mal formados', () async {
      final api = await cliente_(
        (_) => http.Response(
          jsonEncode({
            'items': [
              {'id': servicio},
            ],
            'nextCursor': null,
          }),
          200,
        ),
      );

      final resultado = await EmpleadosRepositorioHttp(api).activos(empresa);

      expect(
        resultado.when(ok: (_) => null, failure: (f) => f),
        isA<ApiJsonInvalidoFailure>(),
      );
    });
  });

  // =========================================================================
  group('y la pantalla lo PINTA', () {
    testWidgets('el listado de Clientes enseña su error, no el indicador', (
      tester,
    ) async {
      // ⚠️ **LA PROPIEDAD QUE EL DUEÑO VIO ROTA EN PANTALLA.** Un fallo que ninguna
      // pantalla pinta sigue siendo invisible, así que no basta con que el repositorio
      // devuelva `failure`.
      tester.view.physicalSize = const Size(1600, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final api = await cliente_(
        (_) => http.Response(
          jsonEncode({'items': [filaSinCreatedAt], 'nextCursor': null}),
          200,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: MarcaSeventra.tema(),
          home: ClientesWebScreen(
            repositorio: ClientesRepositorioHttp(api),
            empresaId: empresa,
            guardia: GuardiaDeSalida(),
            capacidades: const CapacidadesDeModulo(
              puedeVer: true,
              puedeCrear: true,
              puedeModificar: true,
              puedeArchivar: true,
            ),
            alAbrirExpediente: (_) {},
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 🚫 **NI UN INDICADOR DE CARGA**: ésa es la falla entera.
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // Y se dice que la aplicación puede estar desactualizada, que es lo accionable.
      expect(find.textContaining('desactualizada'), findsOneWidget);
    });
  });
}
