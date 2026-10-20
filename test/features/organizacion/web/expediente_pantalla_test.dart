// Las dos pantallas de expediente, montadas de verdad sobre el tema de la web.
//
// La pila es real menos el transporte, igual que en el resto de la web: la pantalla
// habla con el repositorio de verdad, que habla con el `ApiClientAutenticado` de
// verdad. Lo único simulado es lo que contestaría el servidor.
//
// SE MONTAN BAJO `MarcaSeventra.tema()` Y NO BAJO UN `ThemeData` PELADO, porque el
// Design System lee sus colores con `extension<AppColorScheme>()!` y la primera línea
// del build de cualquier pantalla reventaría. Ya pasó una vez, al abrir Áreas.

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
import 'package:riseg_one/features/organizacion/web/datos/expedientes_repositorio_http.dart';
import 'package:riseg_one/features/organizacion/web/presentation/empresa_web_screen.dart';
import 'package:riseg_one/features/organizacion/web/presentation/expediente_sucursal_web_screen.dart';
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
  const sucursalId = '0193f0a0-0000-7000-8000-0000000000b1';

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

  Future<({ExpedientesRepositorioHttp repo, List<http.Request> vistas})>
  construir(Future<http.Response> Function(http.Request) responder) async {
    final vistas = <http.Request>[];

    final desnudo = ApiClient(
      config: config,
      cliente: MockClient((peticion) async {
        vistas.add(peticion);

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
    vistas.clear();

    return (
      repo: ExpedientesRepositorioHttp(
        ApiClientAutenticado(cliente: desnudo, gestor: sesion),
      ),
      vistas: vistas,
    );
  }

  String empresaJson({
    int version = 2,
    String? razonSocial = 'Seguridad Privada RISEG S.A. de C.V.',
    String? rfc = 'SPR950101AB1',
    Map<String, dynamic>? direccion,
    bool tarjetaLista = false,
  }) => jsonEncode({
    'companyId': empresa,
    'name': 'RISEG',
    'legalName': razonSocial,
    'taxId': rfc,
    'legalRep': 'Juan Pérez',
    'slogan': null,
    'fiscalRegimeCode': '601',
    'address': direccion,
    'contact': null,
    'profileVersion': version,
    'fiscalCardReady': tarjetaLista,
  });

  String catalogoJson() => jsonEncode([
    {
      'code': '601',
      'name': 'General de Ley Personas Morales',
      'personaFisica': false,
      'personaMoral': true,
      'selectable': true,
    },
    {
      'code': '612',
      'name': 'Personas Físicas con Actividades Empresariales',
      'personaFisica': true,
      'personaMoral': false,
      'selectable': true,
    },
  ]);

  String sucursalJson({
    int version = 1,
    List<Map<String, dynamic>> horario = const [],
  }) => jsonEncode({
    'branchId': sucursalId,
    'code': 'MATRIZ',
    'name': 'Matriz',
    'address': null,
    'schedule': horario,
    'profileVersion': version,
  });

  /// Una ventana ALTA, y hace falta de verdad.
  ///
  /// El expediente es un formulario largo —quince campos la empresa, diez más siete
  /// días la sucursal— y en los 600×800 por omisión de `flutter_test` el botón de
  /// guardar y la sección de horario caen fuera de la vista. `tester.tap` sobre algo
  /// que no se ve **no hace nada y no se queja**, así que sin esto media docena de
  /// pruebas pasarían sin haber pulsado nada. Costó encontrarlo una vez.
  void ventanaAlta(WidgetTester tester) {
    tester.view.physicalSize = const Size(1400, 4000);
    tester.view.devicePixelRatio = 1;

    addTearDown(tester.view.reset);
  }

  Future<void> montarEmpresa(
    WidgetTester tester,
    ExpedientesRepositorioHttp repo, {
    bool puedeEditar = true,
  }) async {
    ventanaAlta(tester);

    await tester.pumpWidget(
      MaterialApp(
        theme: MarcaSeventra.tema(),
        home: Scaffold(
          body: EmpresaWebScreen(
            repositorio: repo,
            empresaId: empresa,
            puedeEditar: puedeEditar,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
  }

  Future<void> montarSucursal(
    WidgetTester tester,
    ExpedientesRepositorioHttp repo, {
    bool puedeEditar = true,
  }) async {
    ventanaAlta(tester);

    await tester.pumpWidget(
      MaterialApp(
        theme: MarcaSeventra.tema(),
        home: Scaffold(
          body: ExpedienteSucursalWebScreen(
            repositorio: repo,
            empresaId: empresa,
            sucursalId: sucursalId,
            puedeEditar: puedeEditar,
            onVolver: () {},
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
  }

  // =========================================================================
  // 1 · EL EXPEDIENTE DE LA EMPRESA
  // =========================================================================

  group('Expediente de la empresa', () {
    testWidgets('carga sin pantalla roja y muestra lo que llegó', (tester) async {
      // LO PRIMERO QUE SE MIDE ES QUE NO REVIENTE. Es el fallo que ya costó una
      // sesión: un `TypeError` del tema no menciona ni el tema ni la extensión.
      final (repo: repo, vistas: _) = await construir((p) async {
        if (p.url.path.endsWith('/fiscal-regimes')) {
          return http.Response(catalogoJson(), 200);
        }

        return http.Response(empresaJson(), 200);
      });

      await montarEmpresa(tester, repo);

      expect(tester.takeException(), isNull);
      expect(find.text('RISEG'), findsOneWidget);
      expect(
        find.text('Seguridad Privada RISEG S.A. de C.V.'),
        findsOneWidget,
      );
    });

    testWidgets('dice QUÉ FALTA para los datos fiscales, no sólo que faltan', (
      tester,
    ) async {
      // «Faltan datos» obliga a adivinar cuál de los tres. Y la lista de
      // indispensables la decide el SERVIDOR con `fiscalCardReady`; aquí sólo se
      // nombra lo que está vacío.
      final (repo: repo, vistas: _) = await construir((p) async {
        if (p.url.path.endsWith('/fiscal-regimes')) {
          return http.Response(catalogoJson(), 200);
        }

        return http.Response(empresaJson(rfc: null), 200);
      });

      await montarEmpresa(tester, repo);

      expect(
        find.textContaining('falta el RFC, el domicilio'),
        findsOneWidget,
      );
    });

    testWidgets('con la tarjeta lista NO pide nada y lo dice', (tester) async {
      final (repo: repo, vistas: _) = await construir((p) async {
        if (p.url.path.endsWith('/fiscal-regimes')) {
          return http.Response(catalogoJson(), 200);
        }

        return http.Response(
          empresaJson(
            tarjetaLista: true,
            direccion: const {
              'street': 'Av. Independencia',
              'exteriorNumber': '100',
              'interiorNumber': null,
              'neighborhood': 'Centro',
              'municipality': 'Toluca',
              'city': null,
              'state': 'Estado de México',
              'postalCode': '50000',
              'country': null,
              'landmarks': null,
            },
          ),
          200,
        );
      });

      await montarEmpresa(tester, repo);

      expect(find.textContaining('están completos'), findsOneWidget);

      // SE NIEGA EL AVISO CONCRETO, no la palabra «falta»: la ayuda del domicilio dice
      // «hacen falta calle, número exterior…» y un `textContaining('falta')` la
      // cazaría a ella, haciendo fallar la prueba por un texto que es correcto.
      expect(
        find.textContaining('Para los datos fiscales completos falta'),
        findsNothing,
      );
    });

    testWidgets('EL 409 recarga y avisa, en vez de guardar encima', (tester) async {
      // ES LA PIEZA DEL CANDADO. Alguien más guardó mientras el formulario estaba
      // abierto; guardar encima borraría su trabajo sin que ninguno se enterara.
      var guardados = 0;
      var lecturas = 0;

      final (repo: repo, vistas: _) = await construir((p) async {
        if (p.url.path.endsWith('/fiscal-regimes')) {
          return http.Response(catalogoJson(), 200);
        }

        if (p.method == 'PUT') {
          guardados++;

          return http.Response(
            jsonEncode({
              'code': 'expediente_desactualizado',
              'message': 'Alguien más guardó este expediente.',
            }),
            409,
          );
        }

        lecturas++;

        // LA SEGUNDA LECTURA TRAE LA VERSIÓN NUEVA, como la traería de verdad.
        return http.Response(
          empresaJson(version: lecturas == 1 ? 2 : 7),
          200,
        );
      });

      await montarEmpresa(tester, repo);

      await tester.tap(find.text('Guardar expediente'));
      await tester.pumpAndSettle();

      // EL AVISO EXPLICA QUÉ PASÓ Y QUÉ HACER, y no ofrece «forzar»: el trabajo del
      // otro no es un obstáculo que esta pantalla pueda apartar.
      expect(find.text('Alguien más guardó este expediente'), findsOneWidget);
      expect(find.textContaining('no se guardó nada'), findsOneWidget);
      expect(find.textContaining('Forzar'), findsNothing);

      await tester.tap(find.text('Cargar lo más reciente'));
      await tester.pumpAndSettle();

      expect(guardados, 1, reason: 'No debe reintentar el guardado por su cuenta.');
      expect(lecturas, 2, reason: 'Debe releer para traer la versión nueva.');
    });

    testWidgets('los errores de campo se muestran TODOS a la vez', (tester) async {
      // El servidor los reúne a propósito; mostrarlos de uno en uno obligaría a
      // descubrirlos con un guardado por cada uno.
      final (repo: repo, vistas: _) = await construir((p) async {
        if (p.url.path.endsWith('/fiscal-regimes')) {
          return http.Response(catalogoJson(), 200);
        }

        if (p.method == 'PUT') {
          return http.Response(
            jsonEncode({
              'code': 'entrada_invalida',
              'message': 'Hay datos que no se pueden guardar.',
              'fields': [
                {'field': 'taxId', 'message': 'El RFC no tiene la forma correcta.'},
                {
                  'field': 'address.postalCode',
                  'message': 'El código postal son cinco dígitos.',
                },
              ],
            }),
            400,
          );
        }

        return http.Response(empresaJson(), 200);
      });

      await montarEmpresa(tester, repo);

      await tester.tap(find.text('Guardar expediente'));
      await tester.pumpAndSettle();

      expect(find.text('El RFC no tiene la forma correcta.'), findsOneWidget);
      expect(
        find.text('El código postal son cinco dígitos.'),
        findsOneWidget,
      );
    });

    testWidgets('la ayuda del régimen cambia con la LONGITUD del RFC', (
      tester,
    ) async {
      // EL FILTRO AVISA, NO BLOQUEA, y la ayuda no debe prometer un filtro que no se
      // aplicó: decir «la lista está acotada» con un RFC a medio escribir haría
      // pensar que un régimen que falta no existe.
      final (repo: repo, vistas: _) = await construir((p) async {
        if (p.url.path.endsWith('/fiscal-regimes')) {
          return http.Response(catalogoJson(), 200);
        }

        return http.Response(empresaJson(rfc: null), 200);
      });

      await montarEmpresa(tester, repo);

      // Sin RFC: no promete nada.
      expect(find.textContaining('Escribe el RFC'), findsOneWidget);

      await tester.enterText(
        find.byType(TextField).at(1),
        'SPR950101AB1',
      );
      await tester.pumpAndSettle();

      // SE BUSCA LA FRASE COMPLETA DE LA AYUDA, no «persona moral» a secas: el nombre
      // de un régimen del catálogo —«General de Ley Personas Morales»— también la
      // contendría, y la prueba pasaría o fallaría según qué regímenes estén sembrados.
      expect(
        find.textContaining('la lista muestra los de persona moral'),
        findsOneWidget,
      );

      await tester.enterText(
        find.byType(TextField).at(1),
        'RIMA900101AB1',
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('la lista muestra los de persona física'),
        findsOneWidget,
      );
    });

    testWidgets('sin permiso NO ofrece guardar, y lo explica', (tester) async {
      // FILTRAR NO ES AUTORIZAR: el servidor vuelve a decidir. Lo que se evita es
      // ofrecer una puerta que se va a cerrar en la cara.
      final (repo: repo, vistas: _) = await construir((p) async {
        if (p.url.path.endsWith('/fiscal-regimes')) {
          return http.Response(catalogoJson(), 200);
        }

        return http.Response(empresaJson(), 200);
      });

      await montarEmpresa(tester, repo, puedeEditar: false);

      expect(find.text('Guardar expediente'), findsNothing);
      expect(find.textContaining('Sólo puedes consultar'), findsOneWidget);
    });

    testWidgets('si el CATÁLOGO falla, el resto del formulario sigue vivo', (
      tester,
    ) async {
      // No dejar guardar un teléfono porque un catálogo del SAT no cargó sería
      // castigar a la persona por una avería que no es suya.
      final (repo: repo, vistas: _) = await construir((p) async {
        if (p.url.path.endsWith('/fiscal-regimes')) {
          return http.Response('{"code":"boom","message":"No se pudo."}', 500);
        }

        return http.Response(empresaJson(), 200);
      });

      await montarEmpresa(tester, repo);

      expect(tester.takeException(), isNull);
      expect(find.text('Guardar expediente'), findsOneWidget);
      expect(
        find.textContaining('No se pudo cargar el catálogo del SAT'),
        findsOneWidget,
      );
    });
  });

  // =========================================================================
  // 2 · EL EXPEDIENTE DE LA SUCURSAL
  // =========================================================================

  group('Expediente de la sucursal', () {
    testWidgets('un día SIN tramos se muestra como Cerrado', (tester) async {
      // CERRADO ES LA AUSENCIA DE TRAMOS, no un tramo en ceros, y la pantalla lo
      // dice así: los siete días aparecen, y los siete dicen «Cerrado».
      final (repo: repo, vistas: _) = await construir(
        (_) async => http.Response(sucursalJson(), 200),
      );

      await montarSucursal(tester, repo);

      expect(tester.takeException(), isNull);
      expect(find.text('Cerrado'), findsNWidgets(7));
      expect(find.text('Lunes'), findsOneWidget);
      expect(find.text('Domingo'), findsOneWidget);
    });

    testWidgets('DOS tramos en un día se pintan los dos', (tester) async {
      // LO QUE EL ESCRITORIO NO PODÍA EXPRESAR: siete filas fijas con un tramo cada
      // una no admiten abrir 9–14 y 16–20.
      final (repo: repo, vistas: _) = await construir(
        (_) async => http.Response(
          sucursalJson(
            horario: const [
              {
                'dayOfWeek': 1,
                'startMinute': 540,
                'endMinute': 840,
                'crossesMidnight': false,
              },
              {
                'dayOfWeek': 1,
                'startMinute': 960,
                'endMinute': 1200,
                'crossesMidnight': false,
              },
            ],
          ),
          200,
        ),
      );

      await montarSucursal(tester, repo);

      // Dos tramos = dos pares de campos de hora, y el lunes dice «Abierto».
      expect(find.text('Abierto'), findsOneWidget);
      expect(find.text('Cerrado'), findsNWidgets(6));
      expect(find.text('Desde'), findsNWidgets(2));
      expect(find.text('Hasta'), findsNWidgets(2));
    });

    testWidgets('APAGAR un día quita sus tramos, y encenderlo pone uno', (
      tester,
    ) async {
      final (repo: repo, vistas: _) = await construir(
        (_) async => http.Response(sucursalJson(), 200),
      );

      await montarSucursal(tester, repo);

      expect(find.text('Desde'), findsNothing);

      // El primer interruptor es el del lunes.
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();

      expect(find.text('Abierto'), findsOneWidget);
      expect(find.text('Desde'), findsOneWidget);

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();

      // Y AL APAGARLO NO QUEDA UN TRAMO HUÉRFANO: cerrado es no tener ninguno.
      expect(find.text('Desde'), findsNothing);
      expect(find.text('Cerrado'), findsNWidgets(7));
    });

    testWidgets('«Agregar tramo» añade uno que EMPIEZA donde terminó el anterior', (
      tester,
    ) async {
      // ASÍ EL CASO COMÚN NO NACE SOLAPADO. Un segundo tramo que empezara otra vez a
      // las 9 chocaría con el primero y el motor lo rechazaría en el guardado, con
      // la persona sin entender qué hizo mal.
      final (repo: repo, vistas: _) = await construir(
        (_) async => http.Response(
          sucursalJson(
            horario: const [
              {
                'dayOfWeek': 1,
                'startMinute': 540,
                'endMinute': 840,
                'crossesMidnight': false,
              },
            ],
          ),
          200,
        ),
      );

      await montarSucursal(tester, repo);

      await tester.tap(find.text('Agregar tramo'));
      await tester.pumpAndSettle();

      expect(find.text('Desde'), findsNWidgets(2));

      // SE COMPARAN LOS VALORES, NO EL TEXTO EN PANTALLA. `RisegTimeField` formatea
      // con la configuración regional del widget, así que en la prueba sale «2:00 PM»
      // y no «14:00»: afirmar el texto ataría esta prueba a un formato que no es el
      // hecho que importa. Lo que importa es que el tramo nuevo EMPIECE donde terminó
      // el anterior.
      final horas = tester
          .widgetList<RisegTimeField>(find.byType(RisegTimeField))
          .map((c) => c.value)
          .toList();

      expect(horas.length, 4, reason: 'Dos tramos son cuatro campos de hora.');

      final finDelPrimero = horas[1]!;
      final inicioDelSegundo = horas[2]!;

      expect(inicioDelSegundo.hour, finDelPrimero.hour);
      expect(inicioDelSegundo.minute, finDelPrimero.minute);
      expect(finDelPrimero.hour, 14);
    });

    testWidgets('agregar un tramo a un día YA abierto 24 h no rompe la pantalla', (
      tester,
    ) async {
      // EL BORDE DEL CÁLCULO DE «empieza donde terminó el anterior»: si el día ya
      // cubre de 00:00 a 24:00, no queda hueco, y el tramo nuevo nace pisando al
      // primero. **Eso lo rechaza el motor con su mensaje** —no la pantalla—, que es
      // la decisión de todo el horario: una sola regla, la del servidor.
      //
      // Lo que esta prueba fija es que la pantalla NO reviente y NO invente horas
      // imposibles mientras tanto: sin el caso del 1440, el cálculo habría intentado
      // empezar en el minuto 1440 de un día que sólo tiene 1440.
      final (repo: repo, vistas: _) = await construir(
        (_) async => http.Response(
          sucursalJson(
            horario: const [
              {
                'dayOfWeek': 1,
                'startMinute': 0,
                'endMinute': 1440,
                'crossesMidnight': false,
              },
            ],
          ),
          200,
        ),
      );

      await montarSucursal(tester, repo);

      await tester.tap(find.text('Agregar tramo'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      final horas = tester
          .widgetList<RisegTimeField>(find.byType(RisegTimeField))
          .map((c) => c.value!)
          .toList();

      // Las cuatro horas son horas de reloj válidas: nada de un minuto 1440 metido en
      // un `TimeOfDay`, que es lo que habría pasado sin el caso del 1440.
      for (final h in horas) {
        expect(h.hour, inInclusiveRange(0, 23));
        expect(h.minute, inInclusiveRange(0, 59));
      }
    });

    testWidgets('un cierre a MEDIANOCHE se explica como 24:00', (tester) async {
      // «00:00» en la columna de cierre se leería como el principio del día. Y el
      // selector de hora no puede devolver 24:00, así que la pantalla lo dice.
      final (repo: repo, vistas: _) = await construir(
        (_) async => http.Response(
          sucursalJson(
            horario: const [
              {
                'dayOfWeek': 1,
                'startMinute': 0,
                'endMinute': 1440,
                'crossesMidnight': false,
              },
            ],
          ),
          200,
        ),
      );

      await montarSucursal(tester, repo);

      expect(find.textContaining('Cierra a medianoche (24:00)'), findsOneWidget);
    });

    testWidgets('y un tramo que CRUZA la medianoche también se explica', (
      tester,
    ) async {
      final (repo: repo, vistas: _) = await construir(
        (_) async => http.Response(
          sucursalJson(
            horario: const [
              {
                'dayOfWeek': 7,
                'startMinute': 1200,
                'endMinute': 420,
                'crossesMidnight': true,
              },
            ],
          ),
          200,
        ),
      );

      await montarSucursal(tester, repo);

      expect(
        find.textContaining('cierra al día siguiente'),
        findsOneWidget,
      );
    });

    testWidgets('EL SOLAPE lo dice el servidor y se muestra tal cual', (
      tester,
    ) async {
      // LA PANTALLA NO LO ADELANTA con una comprobación propia: serían dos reglas
      // para un mismo hecho, y la de aquí se quedaría atrás.
      final (repo: repo, vistas: _) = await construir((p) async {
        if (p.method == 'PUT') {
          return http.Response(
            jsonEncode({
              'code': 'horario_se_solapa',
              'message':
                  'Dos tramos del mismo día se enciman. Revisa las horas.',
            }),
            422,
          );
        }

        return http.Response(sucursalJson(), 200);
      });

      await montarSucursal(tester, repo);

      await tester.tap(find.text('Guardar expediente'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Dos tramos del mismo día se enciman'),
        findsOneWidget,
      );
    });

    testWidgets('sin permiso no ofrece guardar ni agregar tramos', (tester) async {
      final (repo: repo, vistas: _) = await construir(
        (_) async => http.Response(
          sucursalJson(
            horario: const [
              {
                'dayOfWeek': 1,
                'startMinute': 540,
                'endMinute': 840,
                'crossesMidnight': false,
              },
            ],
          ),
          200,
        ),
      );

      await montarSucursal(tester, repo, puedeEditar: false);

      expect(find.text('Guardar expediente'), findsNothing);
      expect(find.text('Agregar tramo'), findsNothing);

      // PERO EL HORARIO SE VE: consultar no es editar, y esconderlo dejaría a quien
      // sólo lee sin saber a qué hora abre su sucursal.
      expect(find.text('Desde'), findsOneWidget);
    });
  });
}
