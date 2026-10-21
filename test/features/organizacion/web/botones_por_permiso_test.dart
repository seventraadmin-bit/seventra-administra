// LO QUE NO SE PUEDE HACER NO SE MUESTRA, en las tres pantallas de la estructura.
//
// ## El defecto que esto vino a cazar, dicho con precisión
//
// Se probó en pantalla con un usuario de rol **Usuario y CERO permisos**. El servidor
// bloqueaba bien las escrituras —403 en cada `POST` y cada `PATCH`— pero la pantalla le
// ofrecía «Nueva sucursal», «Nuevo puesto», «Nueva área», «Tipos de sucursal», «Cerrar
// temporalmente» y los interruptores. Pulsar cualquiera llevaba a un formulario
// completo que al guardar contestaba 403.
//
// La raíz eran dos cosas distintas:
//
//  · Áreas y Puestos recibían **sólo `esMaestro`**, que gobierna el botón de ELIMINAR,
//    y el botón de alta no estaba atado a nada en absoluto;
//  · Sucursales recibía un `puedeEditarExpedientes` que gobernaba **sólo el
//    expediente**, así que las otras cuatro acciones de la pantalla quedaban abiertas.
//
// `esMaestro` era falso para esa persona, así que si los botones hubieran colgado del
// rol ya habrían estado ocultos. No colgaban de nada.
//
// ## Por qué cada prueba lleva su contrapunto
//
// Una prueba que sólo afirma «no aparece Nueva área» pasaría también si la pantalla no
// pintara NADA —si fallara al cargar, si el widget cambiara de nombre, si el `find` se
// escribiera mal—. Cada caso de «sin permiso» va junto al mismo caso **con** permiso,
// donde lo mismo sí aparece. Así, un falso verde tendría que mentir dos veces en
// direcciones opuestas.
//
// **FILTRAR NO ES AUTORIZAR.** Esto no sustituye al 403 del servidor, que tiene sus
// propias pruebas; evita ofrecer una puerta que va a cerrarse en la cara.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riseg_one/app/shell/apartados_web.dart';
import 'package:riseg_one/core/api/api_client.dart';
import 'package:riseg_one/core/api/api_client_autenticado.dart';
import 'package:riseg_one/core/auth/almacen_sesion_remota.dart';
import 'package:riseg_one/core/auth/auth_api.dart';
import 'package:riseg_one/core/auth/gestor_de_sesion.dart';
import 'package:riseg_one/core/auth/sesion_remota.dart';
import 'package:riseg_one/core/config/api_config.dart';
import 'package:riseg_one/core/logging/app_logger.dart';
import 'package:riseg_one/features/organizacion/web/datos/areas_repositorio_http.dart';
import 'package:riseg_one/features/organizacion/web/datos/expedientes_repositorio_http.dart';
import 'package:riseg_one/features/organizacion/web/datos/puestos_repositorio_http.dart';
import 'package:riseg_one/features/organizacion/web/datos/sucursales_repositorio_http.dart';
import 'package:riseg_one/features/organizacion/web/presentation/areas_web_screen.dart';
import 'package:riseg_one/features/organizacion/web/presentation/puestos_web_screen.dart';
import 'package:riseg_one/features/organizacion/web/presentation/sucursales_web_screen.dart';
import 'package:riseg_one/features/usuarios/web/marca_seventra.dart';

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

void main() {
  final config = ApiConfig.resolve(
    raw: 'http://localhost:5199',
  ).when(ok: (c) => c, failure: (f) => throw StateError(f.message));

  final t0 = DateTime.utc(2026, 10, 21, 12);

  const empresa = '0193f0a0-0000-7000-8000-000000000001';
  const areaId = '0193f0a0-0000-7000-8000-0000000000a1';
  const puestoId = '0193f0a0-0000-7000-8000-0000000000b1';
  const sucursalId = '0193f0a0-0000-7000-8000-0000000000c1';
  const tipoId = '0193f0a0-0000-7000-8000-0000000000d1';

  /// Una ventana ALTA, y hace falta de verdad: en los 600×800 por omisión de
  /// `flutter_test` los botones del pie de un panel caen fuera de la vista, y un
  /// `find` sobre algo que no se ve se comporta distinto de lo que se quiere medir.
  /// Es el mismo tropiezo que ya costó media docena de pruebas en el expediente.
  void ventanaAlta(WidgetTester tester) {
    tester.view.physicalSize = const Size(1400, 4000);
    tester.view.devicePixelRatio = 1;

    addTearDown(tester.view.reset);
  }

  String cuerpoDeSesion() => jsonEncode({
    'accessToken': 'at_1',
    'accessExpiresAt': t0.add(const Duration(minutes: 30)).toIso8601String(),
    'refreshToken': 'rt_1',
    'refreshExpiresAt': t0.add(const Duration(days: 14)).toIso8601String(),
    'identityId': '0193f0a0-0000-7000-8000-00000000cafe',
    'sessionId': '0193f0a0-0000-7000-8000-00000000aaaa',
    'displayName': 'Beto Ruiz',
    'email': 'beto@ejemplo.mx',
  });

  /// Un cliente autenticado que responde a cada `GET` con lo que se le diga.
  ///
  /// Las escrituras **no se simulan a propósito**: estas pruebas van de que no haya
  /// por dónde pedirlas. Si una llegara, el `MockClient` devolvería 404 y la prueba
  /// lo notaría.
  Future<ApiClientAutenticado> clienteQue(
    Map<String, Object?> Function(String ruta) listaDe,
  ) async {
    final desnudo = ApiClient(
      config: config,
      cliente: MockClient((peticion) async {
        if (peticion.url.path.endsWith('/auth/login')) {
          return http.Response(cuerpoDeSesion(), 200);
        }

        if (peticion.method != 'GET') {
          return http.Response('{"code":"no_deberia_pedirse"}', 404);
        }

        final cuerpo = listaDe(peticion.url.path);
        return http.Response(jsonEncode(cuerpo['datos']), 200);
      }),
      logger: AppLogger.console(),
    );

    final sesion = GestorDeSesion(
      api: AuthApi(desnudo),
      almacen: _AlmacenEnMemoria(),
      logger: AppLogger.console(),
      ahora: () => t0,
    );

    addTearDown(sesion.dispose);
    await sesion.iniciarSesion(email: 'beto@ejemplo.mx', password: 'x');

    return ApiClientAutenticado(cliente: desnudo, gestor: sesion);
  }

  Map<String, Object?> lista(Object? datos) => {'datos': datos};

  /// Las capacidades de las pruebas: todo o nada.
  ///
  /// Que cada permiso gobierne SU acción por separado —crear sin modificar, archivar
  /// sin modificar— lo fija `capacidades_y_emparejado_test.dart` sobre la pieza, que
  /// es donde la propiedad vive. Aquí se mide la PANTALLA, y lo que importa es el
  /// contraste: con permisos enseña, sin permisos no.
  CapacidadesDeModulo caps({required bool puede}) => puede
      ? const CapacidadesDeModulo(
          puedeVer: true,
          puedeCrear: true,
          puedeModificar: true,
          puedeArchivar: true,
        )
      : const CapacidadesDeModulo(
          puedeVer: true,
          puedeCrear: false,
          puedeModificar: false,
          puedeArchivar: false,
        );

  /// El campo que lleva esta etiqueta.
  ///
  /// `RisegTextField` pinta un `Text(label)` y debajo su campo, los dos en la misma
  /// `Column`; así que del texto se sube a esa `Column` —la más cercana— y de ahí se
  /// baja al campo. Es lo que permite preguntar por UN campo concreto en vez de por
  /// todos los de la pantalla, que incluyen el buscador de la lista de detrás.
  TextField campoDe(WidgetTester tester, String etiqueta) => tester.widget<TextField>(
    find
        .descendant(
          of: find
              .ancestor(of: find.text(etiqueta), matching: find.byType(Column))
              .first,
          matching: find.byType(TextField),
        )
        .first,
  );

  final unArea = {
    'id': areaId,
    'code': 'OPERACIONES',
    'name': 'Operaciones',
    'status': 'activa',
  };

  final unPuesto = {
    'id': puestoId,
    'areaId': areaId,
    'code': 'PUE-0001',
    'name': 'Supervisor',
    'kind': 'operativo',
    'hierarchyLevel': 3,
    'description': null,
    'status': 'activa',
  };

  final unTipo = {
    'id': tipoId,
    'code': 'MAT',
    'name': 'Matriz',
    'status': 'activa',
  };

  final unaSucursal = {
    'id': sucursalId,
    'code': 'SUC-0001',
    'name': 'Centro',
    'branchTypeId': tipoId,
    'status': 'activa',
    'operationalStatus': 'operando',
  };

  // =========================================================================
  // Áreas
  // =========================================================================

  group('Áreas', () {
    Future<void> montar(WidgetTester tester, {required bool puedeEditar}) async {
      ventanaAlta(tester);

      final cliente = await clienteQue((_) => lista([unArea]));

      await tester.pumpWidget(
        MaterialApp(
          theme: MarcaSeventra.tema(),
          home: AreasWebScreen(
            repositorio: AreasRepositorioHttp(cliente),
            empresaId: empresa,
            esMaestro: false,
            capacidades: caps(puede: puedeEditar),
          ),
        ),
      );

      await tester.pumpAndSettle();
    }

    testWidgets('con sólo consultar NO hay botón de alta', (tester) async {
      await montar(tester, puedeEditar: false);

      expect(find.text('Nueva área'), findsNothing);

      // La lista SÍ se ve: consultar es justamente lo que esta persona puede hacer.
      expect(find.text('Operaciones'), findsOneWidget);
    });

    testWidgets('con el permiso SÍ hay botón de alta', (tester) async {
      // EL CONTRAPUNTO. Sin él, la prueba de arriba pasaría con una pantalla que no
      // pintara nada.
      await montar(tester, puedeEditar: true);

      expect(find.text('Nueva área'), findsOneWidget);
    });

    testWidgets('con sólo consultar la fila abre una FICHA, no un formulario', (
      tester,
    ) async {
      await montar(tester, puedeEditar: false);

      await tester.tap(find.text('Operaciones'));
      await tester.pumpAndSettle();

      // El título no promete lo que no se puede.
      expect(find.text('Área'), findsOneWidget);
      expect(find.text('Editar área'), findsNothing);

      // Ni guardar ni cancelar: se cierra.
      expect(find.text('Guardar'), findsNothing);
      expect(find.text('Cancelar'), findsNothing);
      expect(find.text('Cerrar'), findsOneWidget);

      // El interruptor se ve —el estado es dato— pero no se mueve.
      final interruptor = tester.widget<Switch>(find.byType(Switch).last);
      expect(interruptor.onChanged, isNull);

      // Y los campos del PANEL no se escriben.
      //
      // ⚠️ SE BUSCA EL CAMPO POR SU ETIQUETA, no todos los `TextField` de la
      // pantalla. La primera versión de esta prueba hacía lo segundo y fallaba con
      // razón: el buscador de la lista sigue montado detrás del panel y está
      // habilitado, como debe. Afirmar «ningún campo se escribe» era afirmar algo
      // falso sobre una pantalla correcta.
      expect(campoDe(tester, 'Nombre').enabled, isFalse);
      expect(campoDe(tester, 'Código').enabled, isFalse);
    });

    testWidgets('con el permiso la fila abre el FORMULARIO', (tester) async {
      await montar(tester, puedeEditar: true);

      await tester.tap(find.text('Operaciones'));
      await tester.pumpAndSettle();

      expect(find.text('Editar área'), findsOneWidget);
      expect(find.text('Guardar'), findsOneWidget);
      expect(find.text('Cerrar'), findsNothing);

      final interruptor = tester.widget<Switch>(find.byType(Switch).last);
      expect(interruptor.onChanged, isNotNull);

      // EL CONTRAPUNTO DE LOS CAMPOS: con permiso, el nombre sí se escribe. El
      // código sigue bloqueado al editar, que es otra regla y ya tiene su prueba.
      expect(campoDe(tester, 'Nombre').enabled, isTrue);
    });

    testWidgets('el VACÍO sin permiso no invita a crear', (tester) async {
      // EL ESTADO VACÍO TIENE SU PROPIO BOTÓN DE ALTA, aparte del encabezado. Se me
      // habría escapado mirando sólo el encabezado, y es donde más invita: una
      // pantalla sin nada con un botón grande en medio.
      ventanaAlta(tester);

      final cliente = await clienteQue((_) => lista(const []));

      await tester.pumpWidget(
        MaterialApp(
          theme: MarcaSeventra.tema(),
          home: AreasWebScreen(
            repositorio: AreasRepositorioHttp(cliente),
            empresaId: empresa,
            esMaestro: false,
            capacidades: caps(puede: false),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.textContaining('Todavía no hay áreas'), findsOneWidget);
      expect(find.text('Nueva área'), findsNothing);
    });
  });

  // =========================================================================
  // Puestos
  // =========================================================================

  group('Puestos', () {
    Future<void> montar(WidgetTester tester, {required bool puedeEditar}) async {
      ventanaAlta(tester);

      final cliente = await clienteQue(
        (ruta) => lista(ruta.endsWith('/areas') ? [unArea] : [unPuesto]),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: MarcaSeventra.tema(),
          home: PuestosWebScreen(
            repositorio: PuestosRepositorioHttp(cliente),
            repositorioDeAreas: AreasRepositorioHttp(cliente),
            empresaId: empresa,
            esMaestro: false,
            capacidades: caps(puede: puedeEditar),
          ),
        ),
      );

      await tester.pumpAndSettle();
    }

    testWidgets('con sólo consultar NO hay botón de alta', (tester) async {
      await montar(tester, puedeEditar: false);

      expect(find.text('Nuevo puesto'), findsNothing);
      expect(find.text('Supervisor'), findsOneWidget);
    });

    testWidgets('con el permiso SÍ hay botón de alta', (tester) async {
      await montar(tester, puedeEditar: true);

      expect(find.text('Nuevo puesto'), findsOneWidget);
    });

    testWidgets('con sólo consultar la fila abre una FICHA', (tester) async {
      await montar(tester, puedeEditar: false);

      await tester.tap(find.text('Supervisor'));
      await tester.pumpAndSettle();

      expect(find.text('Puesto'), findsOneWidget);
      expect(find.text('Editar puesto'), findsNothing);
      expect(find.text('Guardar'), findsNothing);
      expect(find.text('Cerrar'), findsOneWidget);
    });
  });

  // =========================================================================
  // Sucursales
  // =========================================================================

  group('Sucursales', () {
    /// El expediente de la sucursal, **que ahora hace falta en este archivo**: desde
    /// el 21 de octubre de 2026 tocar la fila abre el expediente en vez de un panel,
    /// así que la pantalla pide su `/profile` y sin respuesta se vería un error.
    final elExpediente = {
      'branchId': sucursalId,
      'code': 'SUC-0001',
      'name': 'Centro',
      'branchTypeId': tipoId,
      'address': null,
      'schedule': <Object?>[],
      'profileVersion': 1,
    };

    Future<void> montar(WidgetTester tester, {required bool puedeEditar}) async {
      ventanaAlta(tester);

      final cliente = await clienteQue(
        (ruta) => lista(
          ruta.endsWith('/profile')
              ? elExpediente
              : ruta.endsWith('/branch-types')
              ? [unTipo]
              : [unaSucursal],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: MarcaSeventra.tema(),
          home: SucursalesWebScreen(
            repositorio: SucursalesRepositorioHttp(cliente),
            repositorioDeExpedientes: ExpedientesRepositorioHttp(cliente),
            empresaId: empresa,
            esMaestro: false,
            capacidades: caps(puede: puedeEditar),
            // EL EXPEDIENTE VA APARTE: otra familia de permisos.
            puedeEditarExpedientes: puedeEditar,
          ),
        ),
      );

      await tester.pumpAndSettle();
    }

    testWidgets('con sólo consultar NO hay alta, pero el catálogo se ve', (
      tester,
    ) async {
      await montar(tester, puedeEditar: false);

      expect(find.text('Nueva sucursal'), findsNothing);

      // ⚠️ ESTA PRUEBA AFIRMABA QUE «TIPOS DE SUCURSAL» TAMPOCO SE VEÍA, cuando el
      // único permiso que existía era `company.settings.manage` y no había forma de
      // distinguir leer de escribir. Con el mapa del dueño —los tipos siguen el
      // mismo que el resto de la estructura— el catálogo es una LISTA: entrar es
      // `organizacion.ver`, y dentro cada acción vuelve a pedir la suya.
      //
      // Que dentro no haya ni un botón de escritura lo fija
      // `guardia_web_de_permisos_test.dart`, que monta esa pantalla con capacidades
      // vacías.
      expect(find.text('Tipos de sucursal'), findsOneWidget);

      expect(find.text('Centro'), findsOneWidget);
    });

    testWidgets('con el permiso SÍ hay alta y catálogo de tipos', (
      tester,
    ) async {
      await montar(tester, puedeEditar: true);

      expect(find.text('Nueva sucursal'), findsOneWidget);
      expect(find.text('Tipos de sucursal'), findsOneWidget);
    });

    testWidgets(
      'con sólo consultar se VE si está operando y no se puede cambiar',
      (tester) async {
        // ⚠️ ESTA PRUEBA ABRÍA UN PANEL —esperaba el título «Sucursal» y la ausencia
        // de «Editar sucursal»— y ese panel ya no existe para editar. Tocar la fila
        // abre el expediente, que es **el único lugar** donde se edita una sucursal.
        await montar(tester, puedeEditar: false);

        await tester.tap(find.text('Centro'));
        await tester.pumpAndSettle();

        // LAS INSIGNIAS SE QUEDAN Y LOS BOTONES SE VAN: «Operando» y «Activa» son
        // datos de la sucursal, y consultarlos es justo lo que se puede hacer sin
        // permiso de escritura.
        expect(find.text('Operando'), findsOneWidget);
        expect(find.text('Activa'), findsOneWidget);

        expect(find.text('Cerrar temporalmente'), findsNothing);
        expect(find.text('Reabrir'), findsNothing);
        expect(find.text('Desactivar'), findsNothing);
        expect(find.text('Eliminar'), findsNothing);

        // Y NO SE PUEDE GUARDAR: aquí no hay ninguna de las dos familias de permisos.
        expect(find.text('Guardar expediente'), findsNothing);
      },
    );

    testWidgets('con el permiso sí se puede cerrar temporalmente y guardar', (
      tester,
    ) async {
      await montar(tester, puedeEditar: true);

      await tester.tap(find.text('Centro'));
      await tester.pumpAndSettle();

      expect(find.text('Operando'), findsOneWidget);
      expect(find.text('Cerrar temporalmente'), findsOneWidget);
      expect(find.text('Desactivar'), findsOneWidget);
      expect(find.text('Guardar expediente'), findsOneWidget);

      // ELIMINAR NO, porque `montar` monta con `esMaestro: false`: hacen falta las
      // dos autoridades, y ésta es la que falta.
      expect(find.text('Eliminar'), findsNothing);
    });

    testWidgets('el alta sigue teniendo su panel, y sólo el alta', (
      tester,
    ) async {
      // EL PANEL SOBREVIVE PARA CREAR, y no es una excepción a «un solo lugar por
      // sucursal»: una sucursal que todavía no existe no tiene expediente que abrir.
      await montar(tester, puedeEditar: true);

      await tester.tap(find.text('Nueva sucursal'));
      await tester.pumpAndSettle();

      expect(find.text('Nueva sucursal'), findsWidgets);
      expect(find.text('Código'), findsOneWidget);

      // Y EL PANEL DEL ALTA NO TIENE ESTADO NI ELIMINAR: una sucursal nueva nace
      // activa y operando, y lo que no existe no se cierra ni se borra.
      expect(find.text('Cerrar temporalmente'), findsNothing);
      expect(find.text('Desactivar'), findsNothing);
      expect(find.text('Eliminar'), findsNothing);
    });
  });
}
