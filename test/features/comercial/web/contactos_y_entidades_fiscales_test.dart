// C1 · CONTACTOS Y ENTIDADES FISCALES del expediente de un cliente.
//
// ## Qué se fija aquí
//
// Las reglas que el servidor impone y la pantalla **explica**, más las dos que el dueño
// pidió al aprobar que un contacto se elimine en lugar de archivarse:
//
//  1. **un principal POR TIPO**, y el de cobranza no es el comercial: es la razón por la
//     que existe el tercer tipo, porque la factura va al de cobranza;
//  2. **eliminar un contacto pide motivo y la fila se va**; el diálogo lo dice con esas
//     palabras en vez de llamarlo «archivar», que prometería poder recuperarlo;
//  3. **si es responsable de un servicio, el servidor lo bloquea nombrando el servicio**, y
//     ese mensaje sale tal cual: es lo único que dice dónde ir a cambiar el responsable;
//  4. **las entidades fiscales archivadas se siguen viendo**, con sus acciones de edición
//     apagadas y el porqué en el tooltip —escondidas harían pensar que falta un permiso—;
//  5. **el aviso de RFC repetido guarda y avisa**: el panel se queda abierto con el aviso
//     junto al campo y los otros clientes nombrados con su folio;
//  6. **un régimen retirado que ya está puesto se sigue ofreciendo**, porque si no el
//     selector abriría en blanco y lo borraría al guardar.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riseg_one/core/api/api_client.dart';
import 'package:riseg_one/core/api/api_client_autenticado.dart';
import 'package:riseg_one/core/auth/almacen_sesion_remota.dart';
import 'package:riseg_one/core/auth/auth_api.dart';
import 'package:riseg_one/core/auth/gestor_de_sesion.dart';
import 'package:riseg_one/core/auth/sesion_remota.dart';
import 'package:riseg_one/core/config/api_config.dart';
import 'package:riseg_one/core/logging/app_logger.dart';
import 'package:riseg_one/core/trabajo_sin_guardar/guardia_de_salida.dart';
import 'package:riseg_one/features/comercial/web/datos/clientes_repositorio_http.dart';
import 'package:riseg_one/features/comercial/web/presentation/seccion_de_contactos.dart';
import 'package:riseg_one/features/comercial/web/presentation/seccion_de_entidades_fiscales.dart';
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

class _Pedida {
  _Pedida(this.metodo, this.url, this.cuerpo);

  final String metodo;
  final Uri url;
  final String cuerpo;

  Map<String, Object?> get json => jsonDecode(cuerpo) as Map<String, Object?>;
}

void main() {
  final config = ApiConfig.resolve(
    raw: 'http://localhost:5199',
  ).when(ok: (c) => c, failure: (f) => throw StateError(f.message));

  final t0 = DateTime.utc(2026, 10, 26, 12);

  const empresa = '0193f0a0-0000-7000-8000-000000000001';
  const clienteId = '0193f0a0-0000-7000-8000-0000000000c1';
  const contactoId = '0193f0a0-0000-7000-8000-0000000000k1';
  const entidadId = '0193f0a0-0000-7000-8000-0000000000f1';

  /// Un cuerpo de error **con la forma que el servidor manda de verdad**.
  ///
  /// ⚠️ **LA FORMA ES PLANA Y NO `{"error": {...}}`**, y esto es un hallazgo de escribir
  /// estas pruebas: el servidor serializa `ErrorResponse(code, message)` **al nivel
  /// superior**, y `ApiErrorParser` lee `code` y `message` de ahí. Con el sobre `error`, el
  /// parser no los encuentra y compone un mensaje de diagnóstico —«respuesta con campos:
  /// error»—, así que **cualquier prueba de un camino de error probaría menos de lo que
  /// dice** sin fallar. Me pasó en tres archivos.
  String elError(String codigo, String mensaje) =>
      jsonEncode({'code': codigo, 'message': mensaje});

  Map<String, Object?> elContacto({
    String id = contactoId,
    String nombre = 'Ana Torres',
    String tipo = 'comercial',
    String? puesto = 'Compras',
    String? telefono = '5512345678',
    String? correo,
    bool principal = false,
  }) => {
    'id': id,
    'name': nombre,
    'kind': tipo,
    'role': puesto,
    'phone': telefono,
    'email': correo,
    'isPrimary': principal,
    'notes': null,
    'updatedAt': '2026-10-20T18:00:00Z',
  };

  Map<String, Object?> laEntidad({
    String id = entidadId,
    String razon = 'Sportium Club SA de CV',
    String? rfc = 'SPO210101AAA',
    String? regimen = '601',
    String estatus = 'active',
  }) => {
    'id': id,
    'clientId': clienteId,
    'legalName': razon,
    'taxId': rfc,
    'fiscalRegimeCode': regimen,
    'status': estatus,
    'notes': null,
    'updatedAt': '2026-10-20T18:00:00Z',
  };

  Map<String, Object?> elRegimen({
    String codigo = '601',
    String nombre = 'General de Ley Personas Morales',
    bool seleccionable = true,
  }) => {
    'code': codigo,
    'name': nombre,
    'personaFisica': false,
    'personaMoral': true,
    'selectable': seleccionable,
  };

  Future<(ApiClientAutenticado, List<_Pedida>)> cliente({
    List<Map<String, Object?>> contactos = const [],
    List<Map<String, Object?>> entidades = const [],
    List<Map<String, Object?>> regimenes = const [],
    http.Response? Function(_Pedida pedida)? responder,
  }) async {
    final pedidas = <_Pedida>[];

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

        final pedida = _Pedida(p.method, p.url, p.body);
        pedidas.add(pedida);

        if (responder?.call(pedida) case final propia?) return propia;

        final ruta = p.url.path;

        if (ruta.endsWith('/contacts')) {
          return http.Response(jsonEncode(contactos), 200);
        }

        if (ruta.endsWith('/fiscal-entities')) {
          return http.Response(jsonEncode(entidades), 200);
        }

        if (ruta.endsWith('/fiscal-regimes')) {
          return http.Response(jsonEncode(regimenes), 200);
        }

        if (ruta.endsWith('/address')) {
          return http.Response(elError('not_found', 'Sin domicilio.'), 404);
        }

        return http.Response('{}', 200);
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

    return (ApiClientAutenticado(cliente: desnudo, gestor: gestor), pedidas);
  }

  void ventanaAlta(WidgetTester tester) {
    tester.view.physicalSize = const Size(1600, 2600);
    tester.view.devicePixelRatio = 1;

    addTearDown(tester.view.reset);
  }

  /// Monta **una sección sola**, dentro de un router de verdad.
  ///
  /// Se montan solas y no dentro del expediente a propósito: así cada prueba mide una
  /// sección y no cinco peticiones de otra pantalla, y el cableado al expediente ya lo
  /// fija `expediente_cliente_test.dart` —que las pinta—.
  Future<List<_Pedida>> montar(
    WidgetTester tester, {
    required Widget Function(ClientesRepositorioHttp repo, GuardiaDeSalida guardia)
    seccion,
    GuardiaDeSalida? guardia,
    List<Map<String, Object?>> contactos = const [],
    List<Map<String, Object?>> entidades = const [],
    List<Map<String, Object?>> regimenes = const [],
    http.Response? Function(_Pedida pedida)? responder,
  }) async {
    ventanaAlta(tester);

    final (api, pedidas) = await cliente(
      contactos: contactos,
      entidades: entidades,
      regimenes: regimenes,
      responder: responder,
    );

    final elGuardia = guardia ?? GuardiaDeSalida();

    final router = GoRouter(
      initialLocation: '/comercial/clientes/$clienteId',
      routes: [
        GoRoute(
          path: '/comercial/clientes/:id',
          builder: (_, _) => Scaffold(
            body: SingleChildScrollView(
              child: seccion(ClientesRepositorioHttp(api), elGuardia),
            ),
          ),
        ),
      ],
    );

    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(theme: MarcaSeventra.tema(), routerConfig: router),
    );
    await tester.pumpAndSettle();

    return pedidas;
  }

  Future<List<_Pedida>> montarContactos(
    WidgetTester tester, {
    GuardiaDeSalida? guardia,
    List<Map<String, Object?>> contactos = const [],
    bool puedeAdministrar = true,
    http.Response? Function(_Pedida pedida)? responder,
  }) => montar(
    tester,
    guardia: guardia,
    contactos: contactos,
    responder: responder,
    seccion: (repo, g) => SeccionDeContactos(
      repositorio: repo,
      empresaId: empresa,
      clienteId: clienteId,
      puedeAdministrar: puedeAdministrar,
      guardia: g,
    ),
  );

  Future<List<_Pedida>> montarEntidades(
    WidgetTester tester, {
    GuardiaDeSalida? guardia,
    List<Map<String, Object?>> entidades = const [],
    List<Map<String, Object?>> regimenes = const [],
    bool puedeAdministrar = true,
    http.Response? Function(_Pedida pedida)? responder,
  }) => montar(
    tester,
    guardia: guardia,
    entidades: entidades,
    regimenes: regimenes,
    responder: responder,
    seccion: (repo, g) => SeccionDeEntidadesFiscales(
      repositorio: repo,
      empresaId: empresa,
      clienteId: clienteId,
      puedeAdministrar: puedeAdministrar,
      guardia: g,
      alCambiar: () {},
    ),
  );

  /// El campo que lleva esta etiqueta, **dentro de la hoja**.
  Finder campoDe(String etiqueta) => find
      .descendant(
        of: find
            .ancestor(
              of: find.descendant(
                of: find.byType(BottomSheet),
                matching: find.text(etiqueta),
              ),
              matching: find.byType(Column),
            )
            .first,
        matching: find.byType(TextField),
      )
      .first;

  /// El `IconButton` que lleva este tooltip.
  ///
  /// ⚠️ **DOS TRAMPAS, LAS DOS MEDIDAS AQUÍ.** `find.byTooltip` devuelve el `Tooltip` y no
  /// el botón, así que leerlo como `IconButton` estalla con «type 'Tooltip' is not a
  /// subtype of type 'IconButton'». Y el `Tooltip` de un `IconButton` es su
  /// **descendiente**, no su padre, así que se busca el **ancestro** del tooltip.
  IconButton botonConTooltip(WidgetTester tester, String tooltip) =>
      tester.widget<IconButton>(
        find
            .ancestor(
              of: find.byTooltip(tooltip),
              matching: find.byType(IconButton),
            )
            .first,
      );

  /// Elige un valor de un `RisegSelect`: **se abre y después se toca la opción**.
  ///
  /// Sin abrirlo, la opción no existe en el árbol — es un desplegable, no una lista de
  /// radios.
  Future<void> elegirEnElSelector(
    WidgetTester tester, {
    required String abrirCon,
    required String opcion,
  }) async {
    await tester.tap(find.text(abrirCon).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(opcion).last);
    await tester.pumpAndSettle();
  }

  /// Escribe el motivo del último diálogo y confirma con esa etiqueta.
  Future<void> darElMotivo(
    WidgetTester tester,
    String motivo, {
    String confirmar = 'Guardar',
  }) async {
    await tester.enterText(find.byType(TextField).last, motivo);
    await tester.pumpAndSettle();
    await tester.tap(find.text(confirmar).last);
    await tester.pumpAndSettle();
  }

  // =========================================================================
  group('contactos · la lista', () {
    testWidgets('dice el nombre, el tipo, el principal y las vías', (
      tester,
    ) async {
      await montarContactos(
        tester,
        contactos: [
          elContacto(
            nombre: 'Ana Torres',
            tipo: 'cobranza',
            puesto: 'Tesorería',
            correo: 'ana@sportium.mx',
            principal: true,
          ),
        ],
      );

      expect(find.text('Ana Torres'), findsOneWidget);
      expect(find.text('Cobranza'), findsOneWidget);
      expect(find.text('Principal'), findsOneWidget);
      expect(
        find.text('Tesorería — 5512345678 · ana@sportium.mx'),
        findsOneWidget,
      );
    });

    testWidgets('un tipo que esta build no conoce se enseña tal cual', (
      tester,
    ) async {
      // La misma regla que el estatus de un cliente: un `_ => comercial` diría algo falso
      // de un contacto, y nadie lo notaría.
      await montarContactos(
        tester,
        contactos: [elContacto(tipo: 'legal')],
      );

      expect(find.text('legal'), findsOneWidget);
      expect(find.text('Comercial'), findsNothing);
    });

    testWidgets('sin contactos lo dice, y explica qué falta', (tester) async {
      await montarContactos(tester);

      expect(
        find.textContaining('la factura no sabe a quién llegarle'),
        findsOneWidget,
      );
    });

    testWidgets('sin permiso no hay acciones ni botón de añadir', (
      tester,
    ) async {
      await montarContactos(
        tester,
        contactos: [elContacto()],
        puedeAdministrar: false,
      );

      expect(find.text('Añadir contacto'), findsNothing);
      expect(find.byTooltip('Corregir'), findsNothing);
      expect(find.byTooltip('Eliminar'), findsNothing);
    });
  });

  // =========================================================================
  group('contactos · el principal es POR TIPO', () {
    testWidgets('la estrella del que YA es principal no se puede pulsar', (
      tester,
    ) async {
      // Marcar al que ya está no hace nada, y un botón que no hace nada enseña que los
      // botones no hacen nada.
      await montarContactos(
        tester,
        contactos: [elContacto(principal: true)],
      );

      final estrella = botonConTooltip(tester, 'Ya es el principal de su tipo');

      expect(estrella.onPressed, isNull);
    });

    testWidgets('designar va por su propia ruta y SIN motivo', (tester) async {
      // ⚠️ ES UN ACTO CON NOMBRE, no una edición: el servidor pone el motivo solo, y por
      // eso `isPrimary` no existe en el cuerpo del `PATCH`.
      final pedidas = await montarContactos(
        tester,
        contactos: [elContacto(tipo: 'cobranza')],
        responder: (p) => p.metodo == 'POST'
            ? http.Response(
                jsonEncode(elContacto(tipo: 'cobranza', principal: true)),
                200,
              )
            : null,
      );

      await tester.tap(find.byTooltip('Designar principal de cobranza'));
      await tester.pumpAndSettle();

      final designado = pedidas.firstWhere((p) => p.metodo == 'POST');

      expect(designado.url.path, endsWith('/contacts/$contactoId/primary'));
      expect(designado.cuerpo, isEmpty, reason: 'sin cuerpo: el destino lo dice la ruta');

      // Y SE DICE DE QUÉ TIPO: «principal» a secas haría pensar que hay uno solo para
      // todo el cliente.
      expect(find.textContaining('contacto cobranza principal'), findsOneWidget);
    });
  });

  // =========================================================================
  group('contactos · añadir y corregir', () {
    testWidgets('el alta NO pide motivo y manda el tipo', (tester) async {
      final pedidas = await montarContactos(
        tester,
        responder: (p) => p.metodo == 'POST'
            ? http.Response(jsonEncode(elContacto()), 201)
            : null,
      );

      await tester.tap(find.text('Añadir contacto'));
      await tester.pumpAndSettle();

      await tester.enterText(campoDe('Nombre'), 'Beto Ríos');
      await tester.enterText(campoDe('Teléfono'), '5599887766');
      await tester.pumpAndSettle();

      await elegirEnElSelector(
        tester,
        abrirCon: 'Elige para qué es este contacto',
        opcion: 'Operativo',
      );

      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      final alta = pedidas.firstWhere((p) => p.metodo == 'POST');

      expect(alta.json['name'], 'Beto Ríos');
      expect(alta.json['kind'], 'operativo');
      expect(alta.json['phone'], '5599887766');

      // EL MOTIVO ES PARA CORREGIR, NO PARA CREAR.
      expect(alta.json.containsKey('reason'), isFalse);
      expect(find.text('Motivo de la corrección'), findsNothing);
    });

    testWidgets('sin teléfono NI correo se para aquí', (tester) async {
      final pedidas = await montarContactos(tester);

      await tester.tap(find.text('Añadir contacto'));
      await tester.pumpAndSettle();

      await tester.enterText(campoDe('Nombre'), 'Beto Ríos');
      await tester.pumpAndSettle();

      await elegirEnElSelector(
        tester,
        abrirCon: 'Elige para qué es este contacto',
        opcion: 'Operativo',
      );

      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(
        find.text('Hace falta al menos un teléfono o un correo.'),
        findsWidgets,
      );
      expect(pedidas.where((p) => p.metodo == 'POST'), isEmpty);
    });

    testWidgets('corregir pide motivo y manda SÓLO lo que cambió', (
      tester,
    ) async {
      final pedidas = await montarContactos(
        tester,
        contactos: [elContacto()],
        responder: (p) => p.metodo == 'PATCH'
            ? http.Response(jsonEncode(elContacto(nombre: 'Ana T. Ríos')), 200)
            : null,
      );

      await tester.tap(find.byTooltip('Corregir'));
      await tester.pumpAndSettle();

      await tester.enterText(campoDe('Nombre'), 'Ana T. Ríos');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      await darElMotivo(tester, 'Se casó');

      final patch = pedidas.firstWhere((p) => p.metodo == 'PATCH');

      expect(patch.json['name'], 'Ana T. Ríos');
      expect(patch.json['reason'], 'Se casó');

      // NI EL TIPO NI EL TELÉFONO VIAJAN: no se tocaron, y lo que no se manda no se toca.
      expect(patch.json.containsKey('kind'), isFalse);
      expect(patch.json.containsKey('phone'), isFalse);

      // Y `isPrimary` NO EXISTE EN EL CONTRATO de esta ruta.
      expect(patch.json.containsKey('isPrimary'), isFalse);
    });
  });

  // =========================================================================
  group('contactos · eliminar, que NO es archivar', () {
    testWidgets('el diálogo dice que se borra y que no se recupera', (
      tester,
    ) async {
      // ⚠️ LLAMARLO «ARCHIVAR» —como el escritorio— PROMETERÍA PODER VOLVER ATRÁS, y
      // aquí la fila se va.
      await montarContactos(tester, contactos: [elContacto()]);

      await tester.tap(find.byTooltip('Eliminar'));
      await tester.pumpAndSettle();

      expect(find.text('Eliminar el contacto'), findsOneWidget);
      expect(
        find.textContaining('se elimina y no se puede recuperar'),
        findsOneWidget,
      );
      expect(find.textContaining('parcialmente ocultos'), findsOneWidget);
      expect(find.text('Archivar'), findsNothing);
    });

    testWidgets('el motivo viaja en la cadena de consulta', (tester) async {
      // Un cuerpo en un `DELETE` lo descartan algunos intermediarios, y un motivo no es
      // un secreto.
      final pedidas = await montarContactos(
        tester,
        contactos: [elContacto()],
        responder: (p) => p.metodo == 'DELETE'
            ? http.Response('', 204)
            : null,
      );

      await tester.tap(find.byTooltip('Eliminar'));
      await tester.pumpAndSettle();
      await darElMotivo(tester, 'Dejó la empresa', confirmar: 'Eliminar');

      final borrado = pedidas.firstWhere((p) => p.metodo == 'DELETE');

      expect(borrado.url.path, endsWith('/contacts/$contactoId'));
      expect(borrado.url.queryParameters['reason'], 'Dejó la empresa');
    });

    testWidgets('cancelar el motivo no borra nada', (tester) async {
      final pedidas = await montarContactos(
        tester,
        contactos: [elContacto()],
      );

      await tester.tap(find.byTooltip('Eliminar'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancelar').last);
      await tester.pumpAndSettle();

      expect(pedidas.where((p) => p.metodo == 'DELETE'), isEmpty);
    });

    testWidgets(
      'si es responsable de un servicio, el mensaje del servidor NOMBRA el servicio',
      (tester) async {
        // ⚠️ ES LA CONDICIÓN DEL DUEÑO: ni un servicio apuntando a nada ni un error
        // genérico. El servidor bloquea nombrando el servicio, y la pantalla no reescribe
        // ese mensaje — es lo único que dice dónde ir a cambiar el responsable.
        await montarContactos(
          tester,
          contactos: [elContacto()],
          responder: (p) => p.metodo == 'DELETE'
              ? http.Response(
                  elError(
                    'recurso_en_uso',
                    'Este contacto es responsable del servicio SRV-0001 Torre '
                    'Norte. Cambia el responsable antes de eliminarlo.',
                  ),
                  409,
                )
              : null,
        );

        await tester.tap(find.byTooltip('Eliminar'));
        await tester.pumpAndSettle();
        await darElMotivo(tester, 'Ya no trabaja aquí', confirmar: 'Eliminar');

        expect(find.textContaining('SRV-0001 Torre Norte'), findsOneWidget);
        expect(find.textContaining('Cambia el responsable'), findsOneWidget);
      },
    );
  });

  // =========================================================================
  group('contactos · D-56', () {
    testWidgets('el panel recién abierto no tiene nada que perder', (
      tester,
    ) async {
      final guardia = GuardiaDeSalida();

      await montarContactos(
        tester,
        guardia: guardia,
        contactos: [elContacto()],
      );

      await tester.tap(find.byTooltip('Corregir'));
      await tester.pumpAndSettle();

      expect(
        guardia.hayCambiosSinGuardar,
        isFalse,
        reason: 'lo volcado es lo cargado: nadie ha escrito nada',
      );
    });

    testWidgets('escribir sí, y la pregunta nombra al contacto GUARDADO', (
      tester,
    ) async {
      final guardia = GuardiaDeSalida();

      await montarContactos(
        tester,
        guardia: guardia,
        contactos: [elContacto()],
      );

      await tester.tap(find.byTooltip('Corregir'));
      await tester.pumpAndSettle();

      await tester.enterText(campoDe('Nombre'), 'Ana T. Ríos');
      await tester.pumpAndSettle();

      expect(guardia.hayCambiosSinGuardar, isTrue);
      expect(guardia.queSePierde, 'el contacto Ana Torres');
    });
  });

  // =========================================================================
  group('entidades fiscales · la lista', () {
    testWidgets('el régimen sale con su código Y su nombre', (tester) async {
      await montarEntidades(
        tester,
        entidades: [laEntidad()],
        regimenes: [elRegimen()],
      );

      expect(
        find.text('SPO210101AAA · 601 · General de Ley Personas Morales'),
        findsOneWidget,
      );
    });

    testWidgets('sin el catálogo sale el código pelado, no nada', (
      tester,
    ) async {
      // Menos que el nombre y más que nada: es lo que permite reconocer el régimen
      // aunque el catálogo falle.
      await montarEntidades(tester, entidades: [laEntidad()]);

      expect(find.text('SPO210101AAA · 601'), findsOneWidget);
      expect(
        find.textContaining('catálogo de regímenes del SAT no se pudo leer'),
        findsOneWidget,
      );
    });

    testWidgets('lo que falta para facturar se dice en la fila', (tester) async {
      // El RFC y el régimen son opcionales al capturar y obligatorios para EMITIR
      // (CP-13): decirlo aquí evita descubrirlo al intentar facturar.
      await montarEntidades(
        tester,
        entidades: [laEntidad(rfc: null, regimen: null)],
      );

      expect(find.text('Datos incompletos'), findsOneWidget);
      expect(find.text('Sin RFC · Sin régimen fiscal'), findsOneWidget);
    });

    testWidgets('una ARCHIVADA se sigue viendo, y no se puede editar', (
      tester,
    ) async {
      // ⚠️ APAGADAS CON SU PORQUÉ, NO ESCONDIDAS: escondidas harían pensar que falta un
      // permiso. Y el servidor responde 409 a quien lo intente.
      await montarEntidades(
        tester,
        entidades: [laEntidad(estatus: 'archived')],
      );

      expect(find.text('Archivada'), findsOneWidget);

      final editar = botonConTooltip(
        tester,
        'Está archivada: reactívala para poder editarla.',
      );

      expect(editar.onPressed, isNull);

      // Y REACTIVAR SÍ SE PUEDE: es la salida.
      expect(botonConTooltip(tester, 'Reactivar').onPressed, isNotNull);
    });
  });

  // =========================================================================
  group('entidades fiscales · archivar y reactivar', () {
    testWidgets('archivar pide motivo, manda el estatus y dice que NO borra', (
      tester,
    ) async {
      final pedidas = await montarEntidades(
        tester,
        entidades: [laEntidad()],
        responder: (p) => p.metodo == 'PATCH'
            ? http.Response(
                jsonEncode({
                  'fiscalEntity': laEntidad(estatus: 'archived'),
                  'warning': null,
                }),
                200,
              )
            : null,
      );

      await tester.tap(find.byTooltip('Archivar'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Archivar NO la borra'), findsOneWidget);

      await darElMotivo(tester, 'Cambió de razón social', confirmar: 'Archivar');

      final patch = pedidas.firstWhere((p) => p.metodo == 'PATCH');

      expect(patch.json['status'], 'archived');
      expect(patch.json['reason'], 'Cambió de razón social');

      // NADA MÁS VIAJA: archivar no es corregir.
      expect(patch.json.containsKey('legalName'), isFalse);
      expect(patch.json.containsKey('taxId'), isFalse);
    });

    testWidgets('reactivar manda active', (tester) async {
      final pedidas = await montarEntidades(
        tester,
        entidades: [laEntidad(estatus: 'archived')],
        responder: (p) => p.metodo == 'PATCH'
            ? http.Response(
                jsonEncode({'fiscalEntity': laEntidad(), 'warning': null}),
                200,
              )
            : null,
      );

      await tester.tap(find.byTooltip('Reactivar'));
      await tester.pumpAndSettle();
      await darElMotivo(tester, 'Vuelve a facturar', confirmar: 'Reactivar');

      expect(
        pedidas.firstWhere((p) => p.metodo == 'PATCH').json['status'],
        'active',
      );
    });
  });

  // =========================================================================
  group('entidades fiscales · el alta y el aviso de RFC', () {
    testWidgets('el RFC se manda en MAYÚSCULAS', (tester) async {
      // El mismo RFC en minúsculas parecería otro, y el servidor comprueba la forma.
      final pedidas = await montarEntidades(
        tester,
        regimenes: [elRegimen()],
        responder: (p) => p.metodo == 'POST'
            ? http.Response(
                jsonEncode({'fiscalEntity': laEntidad(), 'warning': null}),
                201,
              )
            : null,
      );

      await tester.tap(find.text('Añadir razón social'));
      await tester.pumpAndSettle();

      await tester.enterText(campoDe('Razón social'), 'Sportium Club SA de CV');
      await tester.enterText(campoDe('RFC'), 'spo210101aaa');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      final alta = pedidas.firstWhere((p) => p.metodo == 'POST');

      expect(alta.json['taxId'], 'SPO210101AAA');

      // EL ALTA NO PIDE MOTIVO.
      expect(alta.json.containsKey('reason'), isFalse);
    });

    testWidgets('con el aviso de RFC el panel NO se cierra, y nombra al otro', (
      tester,
    ) async {
      // ⚠️ SE GUARDÓ Y SE AVISA: el mismo RFC en otro cliente es legal —dos marcas de la
      // misma empresa legal— y también es el síntoma de un cliente capturado dos veces.
      // Sólo quien está capturando puede distinguirlo, así que el aviso se lee junto al
      // campo del RFC, con el folio del otro cliente.
      await montarEntidades(
        tester,
        regimenes: [elRegimen()],
        responder: (p) => p.metodo == 'POST'
            ? http.Response(
                jsonEncode({
                  'fiscalEntity': laEntidad(),
                  'warning': {
                    'code': 'rfc_en_otro_cliente',
                    'message':
                        'Ese RFC ya está en otro cliente de esta empresa. Puede ser '
                        'correcto o un cliente capturado dos veces.',
                    'clients': [
                      {
                        'id': '0193f0a0-0000-7000-8000-0000000000c9',
                        'code': 'CLI-000009',
                        'commercialName': 'Sportium Norte',
                      },
                    ],
                  },
                }),
                201,
              )
            : null,
      );

      await tester.tap(find.text('Añadir razón social'));
      await tester.pumpAndSettle();

      await tester.enterText(campoDe('Razón social'), 'Sportium Club SA de CV');
      await tester.enterText(campoDe('RFC'), 'SPO210101AAA');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      // EL PANEL SIGUE ABIERTO, con el aviso dentro.
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('Se guardó, con un aviso'), findsOneWidget);
      expect(find.text('CLI-000009 · Sportium Norte'), findsOneWidget);

      // Y UN SOLO BOTÓN: ya está guardado, así que no hay nada que cancelar.
      expect(find.text('Entendido'), findsOneWidget);
      expect(find.text('Cancelar'), findsNothing);
    });

    testWidgets('un régimen RETIRADO que ya está puesto se sigue ofreciendo', (
      tester,
    ) async {
      // ⚠️ SIN ESTO EL SELECTOR ABRIRÍA EN BLANCO Y LO BORRARÍA AL GUARDAR: `RisegSelect`
      // necesita que su valor esté entre sus opciones. Quien ya lo tenía lo conserva.
      await montarEntidades(
        tester,
        entidades: [laEntidad(regimen: '620')],
        regimenes: [
          elRegimen(),
          elRegimen(
            codigo: '620',
            nombre: 'Sociedades Cooperativas de Producción',
            seleccionable: false,
          ),
        ],
      );

      await tester.tap(find.byTooltip('Corregir'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('620 · Sociedades Cooperativas de Producción'),
        findsWidgets,
      );
      expect(find.textContaining('(retirado)'), findsWidgets);
    });
  });

  // =========================================================================
  group('entidades fiscales · el domicilio fiscal', () {
    testWidgets('va por SU ruta, bajo su entidad', (tester) async {
      final pedidas = await montarEntidades(
        tester,
        entidades: [laEntidad()],
        responder: (p) => p.metodo == 'PUT'
            ? http.Response(
                jsonEncode({
                  'id': '0193f0a0-0000-7000-8000-0000000000d9',
                  'street': 'Av. Reforma',
                  'exteriorNumber': '222',
                  'interiorNumber': null,
                  'neighborhood': 'Juárez',
                  'municipality': 'Cuauhtémoc',
                  'city': null,
                  'state': 'Ciudad de México',
                  'postalCode': '06600',
                  'country': 'México',
                  'landmarks': null,
                  'updatedAt': '2026-10-20T18:00:00Z',
                }),
                200,
              )
            : null,
      );

      await tester.tap(find.byTooltip('Domicilio fiscal'));
      await tester.pumpAndSettle();

      for (final (etiqueta, valor) in const [
        ('Calle', 'Av. Reforma'),
        ('Número exterior', '222'),
        ('Colonia', 'Juárez'),
        ('Municipio', 'Cuauhtémoc'),
        ('Estado', 'Ciudad de México'),
        ('Código postal', '06600'),
      ]) {
        await tester.enterText(campoDe(etiqueta), valor);
      }
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      final put = pedidas.firstWhere((p) => p.metodo == 'PUT');

      expect(
        put.url.path,
        endsWith('/fiscal-entities/$entidadId/address'),
      );
      expect(put.json['street'], 'Av. Reforma');

      // SIN MOTIVO: el servidor no lo pide aquí, y publicar un campo que se ignora es
      // peor que no tenerlo.
      expect(put.json.containsKey('reason'), isFalse);
    });

    testWidgets('vacío no se manda, y se dice qué falta', (tester) async {
      final pedidas = await montarEntidades(
        tester,
        entidades: [laEntidad()],
      );

      await tester.tap(find.byTooltip('Domicilio fiscal'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(pedidas.where((p) => p.metodo == 'PUT'), isEmpty);
      expect(
        find.textContaining('Escribe el domicilio fiscal'),
        findsOneWidget,
      );
    });

    testWidgets('D-56 · el panel del domicilio declara lo que se perdería', (
      tester,
    ) async {
      final guardia = GuardiaDeSalida();

      await montarEntidades(
        tester,
        guardia: guardia,
        entidades: [laEntidad()],
      );

      await tester.tap(find.byTooltip('Domicilio fiscal'));
      await tester.pumpAndSettle();

      expect(guardia.hayCambiosSinGuardar, isFalse);

      await tester.enterText(campoDe('Calle'), 'Av. Reforma');
      await tester.pumpAndSettle();

      expect(guardia.hayCambiosSinGuardar, isTrue);
      expect(
        guardia.queSePierde,
        'el domicilio fiscal de Sportium Club SA de CV',
      );
    });
  });
}
