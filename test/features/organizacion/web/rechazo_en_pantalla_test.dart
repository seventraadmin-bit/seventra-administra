// Dónde se muestra el rechazo del servidor, en la PANTALLA.
//
// Es la mitad que las pruebas del repositorio no cubren: el repositorio devuelve el
// fallo con su `code`, y lo que esta prueba vigila es que la pantalla lo ponga donde se
// puede arreglar.
//
// ## El error que esto vino a cazar, dicho con precisión
//
// Hasta M3, el panel de edición hacía esto al fallar:
//
// ```dart
// if (f case ApiHttpFailure(statusCode: 409)) {
//   _errorDeCodigo = f.message;          // ← todo 409 iba al campo del código
// }
// ```
//
// Y tenía sentido mientras el único 409 posible fuera el código duplicado. La 0049 trajo
// `desactivacion_bloqueada`, que **sí llega por el mismo `PATCH`** —desactivar es
// editar—, así que al desactivar un área con puestos activos la pantalla ponía
// «No se puede desactivar: 1 puesto(s) activo(s) en esta área» **debajo del campo del
// código**, deshabilitado y perfectamente correcto. La persona se quedaba mirando un
// código que no tenía nada de malo.
//
// En los REPOSITORIOS el mismo patrón existía y NO era alcanzable: su reescritura exige
// `codigo != null`, y el código sólo se pasa al crear. Medido, no supuesto: se revirtió
// la condición en `AreasRepositorioHttp` y las pruebas siguieron verdes. Aquí, en
// cambio, la mutación sí mata la prueba.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riseg_one/core/api/api_client.dart';
import 'package:riseg_one/core/api/api_client_autenticado.dart';
import 'package:riseg_one/core/auth/almacen_sesion_remota.dart';
import 'package:riseg_one/core/auth/auth_api.dart';
import 'package:riseg_one/core/auth/gestor_de_sesion.dart';
import 'package:riseg_one/core/auth/sesion_remota.dart';
import 'package:riseg_one/core/config/api_config.dart';
import 'package:riseg_one/core/design_system/design_system_web.dart';
import 'package:riseg_one/core/logging/app_logger.dart';
import 'package:riseg_one/features/organizacion/web/datos/areas_repositorio_http.dart';
import 'package:riseg_one/features/organizacion/web/presentation/areas_web_screen.dart';
import 'package:riseg_one/features/usuarios/web/marca_seventra.dart';

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

void main() {
  final config = ApiConfig.resolve(
    raw: 'http://localhost:5199',
  ).when(ok: (c) => c, failure: (f) => throw StateError(f.message));

  final t0 = DateTime.utc(2026, 10, 19, 12);

  const empresa = '0193f0a0-0000-7000-8000-000000000001';
  const areaId = '0193f0a0-0000-7000-8000-0000000000a1';

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

  Future<AreasRepositorioHttp> repositorioQue(
    Future<http.Response> Function(http.Request) responder,
  ) async {
    final desnudo = ApiClient(
      config: config,
      cliente: MockClient((peticion) async {
        if (peticion.url.path.endsWith('/auth/login')) {
          return http.Response(cuerpoDeSesion(), 200);
        }

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

    return AreasRepositorioHttp(
      ApiClientAutenticado(cliente: desnudo, gestor: sesion),
    );
  }

  /// Un área activa en la lista, y el `PATCH` responde lo que se le diga.
  Future<void> montar(
    WidgetTester tester, {
    required http.Response alModificar,
  }) async {
    final repositorio = await repositorioQue((peticion) async {
      if (peticion.method == 'GET') {
        return http.Response(
          jsonEncode([
            {
              'id': areaId,
              'code': 'OPERACIONES',
              'name': 'Operaciones',
              'status': 'activa',
            },
          ]),
          200,
        );
      }

      return alModificar;
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: MarcaSeventra.tema(),
        home: AreasWebScreen(
          repositorio: repositorio,
          empresaId: empresa,
          esMaestro: true,
        ),
      ),
    );

    await tester.pumpAndSettle();
  }

  /// Abre el panel de edición del área y apaga su interruptor.
  Future<void> desactivarDesdeElPanel(WidgetTester tester) async {
    await tester.tap(find.text('Operaciones'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch).last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
  }

  /// El `errorText` que está puesto bajo el campo del Código, si hay alguno.
  ///
  /// **Se lee del `RisegTextField`, no del `TextField` de dentro**, y la primera versión
  /// de este ayudante lo hizo mal: buscaba un `TextField` cuyo `decoration.labelText`
  /// fuera `'Código'`, y `RisegTextField` **no usa `labelText`** — pinta la etiqueta
  /// como un `Text` aparte encima del campo. Así que no encontraba ninguno y devolvía
  /// `null` siempre.
  ///
  /// La consecuencia fue un **verde falso**: la prueba de «no va bajo el código» pasaba
  /// con o sin el arreglo. Lo delató que la prueba hermana —la que espera que SÍ vaya—
  /// fallara, y es la razón de que las dos vivan juntas: una sola de las dos no se
  /// puede comprobar a sí misma.
  String? errorDelCampoDeCodigo(WidgetTester tester) {
    final campos = tester.widgetList<RisegTextField>(
      find.byType(RisegTextField),
    );

    final codigo = campos.where((c) => c.label == 'Código');

    expect(
      codigo,
      isNotEmpty,
      reason:
          'No se encontró el campo «Código». Si cambió la etiqueta, esta prueba '
          'dejaría de comprobar nada sin fallar.',
    );

    return codigo.first.errorText;
  }

  testWidgets(
    'un 409 de desactivacion_bloqueada NO se muestra bajo el campo del código',
    (tester) async {
      await montar(
        tester,
        alModificar: http.Response(
          jsonEncode({
            'code': 'desactivacion_bloqueada',
            'message':
                'No se puede desactivar: 1 puesto(s) activo(s) en esta área. '
                'Desactiva primero esos puestos.',
          }),
          409,
        ),
      );

      await desactivarDesdeElPanel(tester);

      // AQUÍ ESTÁ LA AFIRMACIÓN QUE IMPORTA. El campo del código está deshabilitado y
      // su valor es correcto; colgarle un error es decirle a la persona que arregle
      // algo que no está roto.
      expect(errorDelCampoDeCodigo(tester), isNull);

      // Y EL MENSAJE SÍ SE VE, en el aviso: no basta con no ponerlo mal, hay que
      // ponerlo. Con el conteo, que es lo que cambia qué hace la persona.
      expect(find.textContaining('1 puesto(s) activo(s)'), findsOneWidget);
    },
  );

  testWidgets('tras eliminar, la LISTA se recarga y la fila desaparece', (
    tester,
  ) async {
    // LA REGLA DE REACTIVIDAD DEL PROYECTO, aplicada a la web: «una mutación
    // confirmada → persistencia → invalidación de sus consumidores → UI visible
    // actualizada». Nació de un bug real del escritorio —borrar un Tiempo Extra lo
    // quitaba de la base y dejaba el renglón en la tabla hasta cambiar de pestaña— y
    // hay un guardián estático para él.
    //
    // ESE GUARDIÁN NO ALCANZA A LA WEB: busca declaraciones llamadas
    // `mostrarDialogo…Fisicamente`, y aquí el borrado va por `_eliminar` dentro del
    // panel. Antes que ensanchar una guarda estática —que mide la forma— se prueba el
    // COMPORTAMIENTO, que es lo que de verdad importaba: después de borrar, la fila ya
    // no está en pantalla.
    var vecesQueSeListo = 0;

    final repositorio = await repositorioQue((peticion) async {
      if (peticion.method == 'GET') {
        vecesQueSeListo++;

        // LA SEGUNDA LECTURA DEVUELVE LA LISTA VACÍA, que es lo que el servidor
        // contestaría después del borrado. Si la pantalla no volviera a preguntar, se
        // quedaría pintando la primera respuesta.
        return http.Response(
          jsonEncode(
            vecesQueSeListo == 1
                ? [
                    {
                      'id': areaId,
                      'code': 'OPERACIONES',
                      'name': 'Operaciones',
                      'status': 'activa',
                    },
                  ]
                : [],
          ),
          200,
        );
      }

      // El DELETE devuelve la fila borrada.
      return http.Response(
        jsonEncode({
          'id': areaId,
          'code': 'OPERACIONES',
          'name': 'Operaciones',
          'status': 'activa',
        }),
        200,
      );
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: MarcaSeventra.tema(),
        home: AreasWebScreen(
          repositorio: repositorio,
          empresaId: empresa,
          esMaestro: true,
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Operaciones'), findsOneWidget);

    // Abrir el panel, pulsar Eliminar, escribir el motivo y confirmar.
    await tester.tap(find.text('Operaciones'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Eliminar definitivamente'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('dialogo_motivo_campo')),
      'Se capturó por error.',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Eliminar'));
    await tester.pumpAndSettle();

    // SE VOLVIÓ A PREGUNTAR, y la fila ya no está.
    expect(vecesQueSeListo, 2);
    expect(find.text('Operaciones'), findsNothing);
  });

  testWidgets('sin motivo, el diálogo NO borra y se queda abierto', (
    tester,
  ) async {
    // El motivo es obligatorio, y el diálogo lo exige antes de gastar un viaje a la
    // red. Que no llegue ningún DELETE es la parte que importa: una validación que
    // «avisa» pero deja pasar la petición no es una validación.
    var huboDelete = false;

    final repositorio = await repositorioQue((peticion) async {
      if (peticion.method == 'DELETE') huboDelete = true;

      if (peticion.method == 'GET') {
        return http.Response(
          jsonEncode([
            {
              'id': areaId,
              'code': 'OPERACIONES',
              'name': 'Operaciones',
              'status': 'activa',
            },
          ]),
          200,
        );
      }

      return http.Response('{}', 200);
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: MarcaSeventra.tema(),
        home: AreasWebScreen(
          repositorio: repositorio,
          empresaId: empresa,
          esMaestro: true,
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.text('Operaciones'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Eliminar definitivamente'));
    await tester.pumpAndSettle();

    // Confirmar con el campo vacío.
    await tester.tap(find.text('Eliminar'));
    await tester.pumpAndSettle();

    expect(huboDelete, isFalse);
    expect(find.textContaining('Falta el motivo'), findsOneWidget);
  });

  testWidgets('a quien NO es Maestro no se le ofrece el botón de eliminar', (
    tester,
  ) async {
    // ES CORTESÍA, NO SEGURIDAD, y conviene que esté dicho: la autorización la decide
    // el servidor, que exige rol de Maestro en la propia empresa. Esconder el botón
    // sólo evita ofrecer algo que va a fallar.
    final repositorio = await repositorioQue(
      (_) async => http.Response(
        jsonEncode([
          {
            'id': areaId,
            'code': 'OPERACIONES',
            'name': 'Operaciones',
            'status': 'activa',
          },
        ]),
        200,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: MarcaSeventra.tema(),
        home: AreasWebScreen(
          repositorio: repositorio,
          empresaId: empresa,
          esMaestro: false,
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.text('Operaciones'));
    await tester.pumpAndSettle();

    expect(find.text('Eliminar definitivamente'), findsNothing);

    // Y EL PANEL SÍ SE ABRIÓ: si no, la afirmación de arriba sería vacía y pasaría
    // igual con el botón presente.
    expect(find.text('Editar área'), findsOneWidget);
  });

  testWidgets(
    'y un 409 de code_conflict SÍ se muestra bajo el campo del código',
    (tester) async {
      // LA OTRA MITAD: el arreglo no debía apagar lo que ya funcionaba. Un choque de
      // código es lo único que se arregla sin salir del formulario, así que su sitio es
      // el campo.
      //
      // Llega por el PATCH para que las dos pruebas recorran el mismo camino y la
      // diferencia sea sólo el `code` — si una fuera por `crear` y la otra por
      // `modificar`, la prueba no estaría comparando lo mismo.
      await montar(
        tester,
        alModificar: http.Response(
          jsonEncode({
            'code': 'code_conflict',
            'message': "Ya existe un área con el código 'OPERACIONES'.",
          }),
          409,
        ),
      );

      await desactivarDesdeElPanel(tester);

      expect(errorDelCampoDeCodigo(tester), contains('Ya existe un área'));
    },
  );
}
