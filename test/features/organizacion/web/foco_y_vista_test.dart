// Que **la vista siga a donde se fue la atención** en un formulario más alto que la
// pantalla.
//
// Las dos propiedades que fija este archivo salieron de MEDIR la pantalla, no de
// suponerla, y las dos estaban roto:
//
//  1. `Tab` da la vuelta al final del formulario y la vista se queda abajo: el foco
//     volvía al enlace de regreso en `y = -910` con el desplazamiento quieto en 934.
//     Dos `Tab` más y se escribía a ciegas en un campo que no se veía.
//  2. Guardar desde abajo con un error arriba: el error se pintaba y el
//     desplazamiento se quedaba en 962, así que para la persona el botón no había
//     hecho nada.
//
// ⚠️ **LA VENTANA DE ESTAS PRUEBAS ES ALTA PERO NO INFINITA.** Las demás pruebas del
// expediente montan 1400×4000 para que todo quepa y `tap` nunca falle; aquí lo que se
// mide ES el desplazamiento, así que con todo visible no habría nada que medir y las
// dos pruebas pasarían sin mirar nada.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:riseg_one/features/organizacion/web/datos/expedientes_repositorio_http.dart';
import 'package:riseg_one/features/organizacion/web/datos/sucursales_repositorio_http.dart';
import 'package:riseg_one/features/organizacion/web/modelos/sucursal.dart';
import 'package:riseg_one/features/organizacion/web/modelos/tipo_de_sucursal.dart';
import 'package:riseg_one/features/organizacion/web/presentation/expediente_sucursal_web_screen.dart';
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

  final t0 = DateTime.utc(2026, 10, 21, 12);

  const empresa = '0193f0a0-0000-7000-8000-000000000001';
  const sucursalId = '0193f0a0-0000-7000-8000-0000000000b1';
  const tipoId = '0193f0a0-0000-7000-8000-0000000000d1';

  String sesion() => jsonEncode({
    'accessToken': 'at_1',
    'accessExpiresAt': t0.add(const Duration(minutes: 30)).toIso8601String(),
    'refreshToken': 'rt_1',
    'refreshExpiresAt': t0.add(const Duration(days: 14)).toIso8601String(),
    'sessionId': '0193f0a0-0000-7000-8000-00000000aaaa',
    'identityId': '0193f0a0-0000-7000-8000-00000000bbbb',
    'displayName': 'Ana Torres',
    'email': 'ana@seventra.mx',
  });

  String expedienteJson() => jsonEncode({
    'branchId': sucursalId,
    'code': 'SUC-0001',
    'name': 'Centro',
    'branchTypeId': tipoId,
    'address': {
      'street': 'Hidalgo',
      'exteriorNumber': '10',
      'interiorNumber': null,
      'neighborhood': 'Centro',
      'municipality': 'Toluca',
      'city': null,
      'state': 'Estado de México',
      'postalCode': '50000',
      'country': null,
      'landmarks': null,
    },
    'schedule': const [
      {
        'dayOfWeek': 1,
        'startMinute': 540,
        'endMinute': 1080,
        'crossesMidnight': false,
      },
    ],
    'profileVersion': 1,
  });

  Future<ApiClientAutenticado> cliente(
    Future<http.Response> Function(http.Request) responder,
  ) async {
    final desnudo = ApiClient(
      config: config,
      cliente: MockClient((p) async {
        if (p.url.path.endsWith('/auth/login')) {
          return http.Response(sesion(), 200);
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

  /// La ventana donde el formulario **no cabe**: 900 px de alto contra 1862 de
  /// contenido. Es la condición de las dos propiedades.
  void ventanaQueNoAlcanza(WidgetTester tester) {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;

    addTearDown(tester.view.reset);
  }

  Future<void> montar(WidgetTester tester, ApiClientAutenticado api) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: MarcaSeventra.tema(),
        home: ExpedienteSucursalWebScreen(
          repositorio: ExpedientesRepositorioHttp(api),
          repositorioDeSucursales: SucursalesRepositorioHttp(api),
          empresaId: empresa,
          sucursal: const Sucursal(
            id: sucursalId,
            codigo: 'SUC-0001',
            nombre: 'Centro',
            activa: true,
            tipoId: tipoId,
            estadoOperativo: 'operando',
          ),
          tipos: const [
            TipoDeSucursal(
              id: tipoId,
              codigo: 'OFI',
              nombre: 'Oficina',
              activo: true,
            ),
          ],
          capacidades: const CapacidadesDeModulo(
            puedeVer: true,
            puedeCrear: true,
            puedeModificar: true,
            puedeArchivar: true,
          ),
          esMaestro: true,
          puedeEditarExpedientes: true,
          onVolver: () {},
        ),
      ),
    );

    await tester.pumpAndSettle();
  }

  ScrollPosition posicionDe(WidgetTester tester) =>
      Scrollable.of(tester.element(find.byType(Column).first)).position;

  /// ¿Se ve entero lo que tiene el foco?
  bool elFocoSeVe(WidgetTester tester) {
    final contexto = FocusManager.instance.primaryFocus?.context;
    if (contexto == null) return false;

    final caja = contexto.findRenderObject();
    if (caja is! RenderBox || !caja.hasSize) return false;

    final arriba = caja.localToGlobal(Offset.zero).dy;

    return arriba >= 0 && arriba + caja.size.height <= 900;
  }

  group('El recorrido con Tab', () {
    testWidgets('al dar la vuelta, la vista SUBE con el foco', (tester) async {
      ventanaQueNoAlcanza(tester);

      await montar(
        tester,
        await cliente((_) async => http.Response(expedienteJson(), 200)),
      );

      // SE TABULA HASTA EL ÚLTIMO, que es el botón de guardar. No se cuenta un número
      // fijo de `Tab`: el formulario puede ganar un campo mañana y la prueba se
      // quedaría a medias sin fallar.
      var vueltas = 0;

      while (vueltas < 60) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        vueltas++;

        final foco = FocusManager.instance.primaryFocus?.context?.widget;
        final texto = foco == null
            ? const <String>[]
            : find
                  .descendant(
                    of: find.byWidget(foco),
                    matching: find.byType(Text),
                    skipOffstage: false,
                  )
                  .evaluate()
                  .map((e) => (e.widget as Text).data)
                  .whereType<String>()
                  .toList();

        if (texto.contains('Guardar expediente')) break;
      }

      expect(
        vueltas,
        lessThan(60),
        reason: 'Nunca llegó el foco al botón de guardar.',
      );

      // AL FINAL DEL FORMULARIO LA VISTA ESTÁ ABAJO, que es la condición del defecto.
      expect(posicionDe(tester).pixels, greaterThan(500));

      // Y UN `Tab` MÁS DA LA VUELTA: el foco se va arriba, **y la vista con él**.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();

      expect(
        posicionDe(tester).pixels,
        lessThan(100),
        reason:
            'La vuelta de Tab dejó la vista abajo: el foco está arriba y no se ve. '
            'Es el defecto medido el 21 de octubre de 2026.',
      );

      expect(elFocoSeVe(tester), isTrue);
    });

    testWidgets('NO desplaza cuando lo enfocado ya se ve', (tester) async {
      // LA OTRA MITAD DE LA PROPIEDAD, y sin ella el arreglo sería peor que el
      // defecto: llevar el campo enfocado siempre a la misma altura convertiría
      // recorrer un formulario en una sucesión de saltos.
      ventanaQueNoAlcanza(tester);

      await montar(
        tester,
        await cliente((_) async => http.Response(expedienteJson(), 200)),
      );

      // LOS PRIMEROS CAMPOS CABEN TODOS EN LA VENTANA: medido, el sexto está en
      // `y = 428` de 900. Así que estos `Tab` no deben mover nada.
      for (var i = 0; i < 6; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();

        expect(
          posicionDe(tester).pixels,
          0,
          reason: 'El Tab número ${i + 1} desplazó la vista sin necesidad.',
        );
      }
    });
  });

  group('Un guardado que falla', () {
    testWidgets('lleva la vista Y el cursor al campo señalado', (tester) async {
      ventanaQueNoAlcanza(tester);

      await montar(
        tester,
        await cliente((p) async {
          if (p.method == 'GET') return http.Response(expedienteJson(), 200);

          // EL SERVIDOR SEÑALA EL NOMBRE, que está arriba. El botón está abajo.
          return http.Response(
            jsonEncode({
              'code': 'entrada_invalida',
              'message': 'Revisa los campos señalados.',
              'fields': [
                {'field': 'name', 'message': 'El nombre es obligatorio.'},
              ],
            }),
            400,
          );
        }),
      );

      // SE BAJA HASTA EL BOTÓN, como hace la persona de verdad.
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -1000));
      await tester.pumpAndSettle();

      expect(posicionDe(tester).pixels, greaterThan(500));

      await tester.tap(find.text('Guardar expediente'));
      await tester.pumpAndSettle();

      // 1 · EL ERROR SE VE. Antes se pintaba fuera de la vista y para la persona el
      // botón no había hecho nada.
      final error = find.text('El nombre es obligatorio.');

      expect(error, findsOneWidget);
      expect(
        tester.getTopLeft(error).dy,
        allOf(greaterThanOrEqualTo(0), lessThanOrEqualTo(900)),
        reason: 'El error existe pero quedó fuera de la ventana.',
      );

      // 2 · Y EL CURSOR ESTÁ DENTRO DEL CAMPO: ver el error y poder corregirlo son
      // dos cosas, y la persona quiere las dos sin volver a pulsar.
      expect(elFocoSeVe(tester), isTrue);

      final enfocado = FocusManager.instance.primaryFocus?.context;
      expect(
        enfocado?.findAncestorWidgetOfExactType<TextField>()?.controller?.text,
        'Centro',
        reason: 'El foco no quedó en el campo del nombre.',
      );
    });

    testWidgets('el error del HORARIO se trae por su sección', (tester) async {
      // EL HORARIO NO ES UN CAMPO DE TEXTO —son siete filas de interruptores— así que
      // no se puede enfocar. Se llega a él por su sitio.
      ventanaQueNoAlcanza(tester);

      await montar(
        tester,
        await cliente((p) async {
          if (p.method == 'GET') return http.Response(expedienteJson(), 200);

          return http.Response(
            jsonEncode({
              'code': 'entrada_invalida',
              'message': 'Revisa los campos señalados.',
              'fields': [
                {
                  'field': 'schedule[0]',
                  'message': 'La hora de fin va de 00:01 a 24:00.',
                },
              ],
            }),
            400,
          );
        }),
      );

      // SE EMPIEZA ARRIBA y el horario está al final, así que la vista tiene que BAJAR.
      expect(posicionDe(tester).pixels, 0);

      // El botón no se ve desde arriba, así que se baja, se pulsa y se vuelve arriba
      // para medir el movimiento de verdad.
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -1000));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar expediente'));
      await tester.pumpAndSettle();

      final mensaje = find.textContaining('La hora de fin va de 00:01');

      expect(mensaje, findsOneWidget);
      expect(
        tester.getTopLeft(mensaje).dy,
        allOf(greaterThanOrEqualTo(0), lessThanOrEqualTo(900)),
        reason: 'El error del horario quedó fuera de la ventana.',
      );
    });
  });
}
