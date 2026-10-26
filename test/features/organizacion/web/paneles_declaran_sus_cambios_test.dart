// D-56 · LAS HOJAS MODALES TAMBIÉN DECLARAN LO QUE SE PERDERÍA, Y SE CIERRAN.
//
// ## Por qué los paneles son un caso aparte
//
// El alta y la edición de área, puesto, sucursal y tipo de sucursal **no viven en una
// dirección**: son hojas que `showModalBottomSheet` empuja sobre el `Navigator`, no sobre
// go_router. Eso cambia dos cosas:
//
//  1. **lo que las protege**: `beforeunload` y el cambio de empresa funcionan igual —no
//     miran direcciones—, y el botón «atrás» pregunta por el `onExit` de la ruta de
//     debajo; pero al confirmar, **la hoja se quedaría encima de la pantalla nueva**,
//     porque un cambio de dirección no se lleva lo que no está en el historial;
//  2. **qué es «limpio» al abrir**: estos paneles **no abren vacíos**. El código llega
//     sugerido, y con una sola área o un solo tipo, el selector llega elegido. Comparar
//     contra la cadena vacía haría que **abrir el alta y cerrarla preguntara** por lo que
//     el panel escribió solo — y una pregunta que sale por nada enseña a contestar el
//     diálogo sin leerlo.
//
// Las dos cosas son lo que este archivo fija.
//
// ## Lo que NO está aquí
//
// Que la pregunta salga y que cancelar deje la dirección quieta lo fija
// `test/app/shell/salida_con_trabajo_sin_guardar_test.dart`, con el router de verdad. Que
// ningún formulario de la web se quede sin registrar lo fija
// `test/app/shell/guardia_cubre_los_formularios_test.dart`.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riseg_one/app/shell/apartados_web.dart' show CapacidadesDeModulo;
import 'package:riseg_one/core/api/api_client.dart';
import 'package:riseg_one/core/api/api_client_autenticado.dart';
import 'package:riseg_one/core/auth/almacen_sesion_remota.dart';
import 'package:riseg_one/core/auth/auth_api.dart';
import 'package:riseg_one/core/auth/gestor_de_sesion.dart';
import 'package:riseg_one/core/auth/sesion_remota.dart';
import 'package:riseg_one/core/config/api_config.dart';
import 'package:riseg_one/core/logging/app_logger.dart';
import 'package:riseg_one/core/trabajo_sin_guardar/guardia_de_salida.dart';
import 'package:riseg_one/features/organizacion/web/datos/areas_repositorio_http.dart';
import 'package:riseg_one/features/organizacion/web/presentation/areas_web_screen.dart';
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

  final t0 = DateTime.utc(2026, 10, 26, 12);

  const empresa = '0193f0a0-0000-7000-8000-000000000001';
  const areaId = '0193f0a0-0000-7000-8000-0000000000a1';

  final unArea = {
    'id': areaId,
    'code': 'ARE-0001',
    'name': 'Operaciones',
    'status': 'activa',
  };

  Future<ApiClientAutenticado> cliente() async {
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

        return http.Response(jsonEncode([unArea]), 200);
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

  const todo = CapacidadesDeModulo(
    puedeVer: true,
    puedeCrear: true,
    puedeModificar: true,
    puedeArchivar: true,
  );

  /// Una ventana ALTA, y hace falta: los botones del pie de un panel caen fuera de los
  /// 600×800 por omisión, y un `tap` sobre algo que no se ve **no hace nada y no se queja**.
  void ventanaAlta(WidgetTester tester) {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1;

    addTearDown(tester.view.reset);
  }

  /// Monta Áreas **dentro de un router de verdad**, porque la mitad de lo que se mide aquí
  /// —que la hoja se cierre al cambiar la dirección— no existe sin él.
  ///
  /// Se usa Áreas como representante de los cuatro paneles: los cuatro llevan los mismos
  /// dos mixins, y que ninguno se quede sin ellos lo fija el candado de la regla
  /// permanente. Repetir el montaje cuatro veces mediría el mismo código con otros
  /// nombres.
  Future<GoRouter> montar(
    WidgetTester tester, {
    required GuardiaDeSalida guardia,
  }) async {
    ventanaAlta(tester);

    final api = await cliente();

    final router = GoRouter(
      initialLocation: '/organizacion/areas',
      routes: [
        GoRoute(
          path: '/organizacion/:pestana',
          builder: (_, _) => AreasWebScreen(
            repositorio: AreasRepositorioHttp(api),
            empresaId: empresa,
            esMaestro: true,
            capacidades: todo,
            guardia: guardia,
          ),
        ),
      ],
    );

    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(theme: MarcaSeventra.tema(), routerConfig: router),
    );
    await tester.pumpAndSettle();

    return router;
  }

  /// El campo que lleva esta etiqueta.
  Finder campoDe(String etiqueta) => find
      .descendant(
        of: find
            .ancestor(of: find.text(etiqueta), matching: find.byType(Column))
            .first,
        matching: find.byType(TextField),
      )
      .first;

  group('el alta, que NO abre vacía', () {
    testWidgets('recién abierta no hay nada que perder, con el código sugerido', (
      tester,
    ) async {
      // ⚠️ ES EL CASO QUE SE ME HABRÍA ESCAPADO comparando contra la cadena vacía: el
      // panel abre con `ARE-0002` ya puesto, así que una comparación ingenua diría
      // «sucio» sin que nadie haya escrito nada, y cerrar el panel preguntaría.
      final guardia = GuardiaDeSalida();

      await montar(tester, guardia: guardia);

      await tester.tap(find.text('Nueva área'));
      await tester.pumpAndSettle();

      // EL PANEL ESTÁ ABIERTO con el código sugerido dentro.
      expect(find.text('Nueva área'), findsWidgets);
      expect(campoDe('Código'), findsOneWidget);

      expect(
        guardia.hayCambiosSinGuardar,
        isFalse,
        reason: 'el código sugerido lo escribió el panel, no la persona',
      );
    });

    testWidgets('escribir el nombre SÍ es algo que perder, y se nombra', (
      tester,
    ) async {
      final guardia = GuardiaDeSalida();

      await montar(tester, guardia: guardia);

      await tester.tap(find.text('Nueva área'));
      await tester.pumpAndSettle();

      await tester.enterText(campoDe('Nombre'), 'Vigilancia');
      await tester.pumpAndSettle();

      expect(guardia.hayCambiosSinGuardar, isTrue);
      expect(guardia.queSePierde, 'el área que estás dando de alta');
    });

    testWidgets('y borrarlo vuelve a dejarlo limpio', (tester) async {
      // La misma regla que en los expedientes: se compara contra lo que había, no contra
      // «se tocó algo».
      final guardia = GuardiaDeSalida();

      await montar(tester, guardia: guardia);

      await tester.tap(find.text('Nueva área'));
      await tester.pumpAndSettle();

      await tester.enterText(campoDe('Nombre'), 'Vigilancia');
      await tester.pumpAndSettle();
      expect(guardia.hayCambiosSinGuardar, isTrue);

      await tester.enterText(campoDe('Nombre'), '');
      await tester.pumpAndSettle();

      expect(guardia.hayCambiosSinGuardar, isFalse);
    });
  });

  group('la edición', () {
    testWidgets('abre limpia y nombra el área por su nombre GUARDADO', (
      tester,
    ) async {
      final guardia = GuardiaDeSalida();

      await montar(tester, guardia: guardia);

      await tester.tap(find.text('Operaciones'));
      await tester.pumpAndSettle();

      expect(guardia.hayCambiosSinGuardar, isFalse);

      await tester.enterText(campoDe('Nombre'), 'Operaciones y logística');
      await tester.pumpAndSettle();

      expect(guardia.hayCambiosSinGuardar, isTrue);

      // ⚠️ EL NOMBRE GUARDADO Y NO EL DEL CAMPO: a quien está renombrando, la pregunta le
      // hablaría de un área que todavía no existe con ese nombre.
      expect(guardia.queSePierde, 'el área Operaciones');
    });
  });

  group('la hoja se cierra cuando cambia la dirección', () {
    testWidgets('al cambiar de pestaña, el panel abierto se va', (tester) async {
      // ⚠️ SIN ESTO LA HOJA SE QUEDA ENCIMA DE LA PANTALLA NUEVA, con los campos puestos
      // y un «Guardar» que escribiría en el sitio de antes. Una hoja modal la empuja el
      // `Navigator` y **no vive en el historial del router**, así que un cambio de
      // dirección no se la lleva por sí solo.
      final guardia = GuardiaDeSalida();

      final router = await montar(tester, guardia: guardia);

      await tester.tap(find.text('Nueva área'));
      await tester.pumpAndSettle();

      expect(find.text('Código'), findsOneWidget);

      router.go('/organizacion/puestos');
      await tester.pumpAndSettle();

      // SE PREGUNTA POR LA ETIQUETA «Código», que **sólo existe dentro del panel**. Un
      // `find.byType(TextField)` no serviría: la pantalla de debajo tiene su buscador, así
      // que seguiría encontrando uno y la prueba fallaría sin que nada estuviera mal —me
      // pasó al escribirla.
      expect(
        find.text('Código'),
        findsNothing,
        reason: 'el panel tenía que haberse cerrado con el cambio de dirección',
      );
    });

    testWidgets('y el guardia se queda limpio, porque el panel se desmontó', (
      tester,
    ) async {
      // LA OTRA MITAD, y es la que de verdad importa: si la hoja se fuera sin soltar su
      // registro, **cada navegación siguiente preguntaría** por un formulario que ya no
      // existe. El mixin suelta en el `dispose`, y cerrarse es desmontarse.
      final guardia = GuardiaDeSalida();

      final router = await montar(tester, guardia: guardia);

      await tester.tap(find.text('Nueva área'));
      await tester.pumpAndSettle();

      await tester.enterText(campoDe('Nombre'), 'Vigilancia');
      await tester.pumpAndSettle();
      expect(guardia.hayCambiosSinGuardar, isTrue);

      router.go('/organizacion/puestos');
      await tester.pumpAndSettle();

      expect(guardia.hayCambiosSinGuardar, isFalse);
    });

    testWidgets('sin cambio de dirección, la hoja se queda', (tester) async {
      // EL CONTRAPUNTO, y no sobra: una hoja que se cerrara con cualquier repintado
      // pasaría las dos pruebas de arriba y sería **inusable** — se iría sola mientras
      // alguien escribe.
      final guardia = GuardiaDeSalida();

      await montar(tester, guardia: guardia);

      await tester.tap(find.text('Nueva área'));
      await tester.pumpAndSettle();

      await tester.enterText(campoDe('Nombre'), 'Vigilancia');
      await tester.pumpAndSettle();

      expect(campoDe('Nombre'), findsOneWidget);
      expect(guardia.hayCambiosSinGuardar, isTrue);
    });
  });
}
