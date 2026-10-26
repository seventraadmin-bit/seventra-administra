// LA DIRECCIÓN DICE DÓNDE ESTÁS, Y LA PANTALLA OBEDECE (D-39).
//
// ## Qué deuda cierra esto, dicho con precisión
//
// «Tipos de sucursal» y el expediente de una sucursal **no son pestañas**: viven dentro
// de Sucursales, detrás de un botón. Hasta C1 eran un `bool` y un `Sucursal?` de estado
// local, y como el portón es quien dibuja el rastro y no se enteraba de que se había
// entrado ahí, la pantalla tenía que **avisar hacia arriba con un callback**.
//
// La vía estaba bien escrita —un solo método la tocaba— y lo que estaba mal era que
// existiera. Se demostró el 22 de octubre de 2026 en el ensayo, con la otra pantalla que
// hacía lo mismo: arriba se leía «Organización › Empresa › Editar» estando en la
// administración de empresas, porque un sitio cambiaba la vista sin anunciarla.
//
// ## Qué se afirma aquí, y qué no
//
// Aquí se afirma **la mitad de la pantalla**: que recibir la dirección abre lo que la
// dirección dice —que es exactamente lo que hace un enlace pegado o un «atrás»— y que
// tocar un botón PIDE la dirección correcta en vez de moverse por su cuenta.
//
// Lo que NO está aquí, a propósito:
//
//  · que la dirección se lea y se vuelva a juntar bien → `rutas_web_test.dart`;
//  · que el guardia no toque lo de dentro → `router_web_test.dart`;
//  · qué botones se ofrecen con qué permiso → `botones_por_permiso_test.dart`.

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
import 'package:riseg_one/features/organizacion/web/datos/expedientes_repositorio_http.dart';
import 'package:riseg_one/features/organizacion/web/datos/sucursales_repositorio_http.dart';
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

  final t0 = DateTime.utc(2026, 10, 25, 12);

  const empresa = '0193f0a0-0000-7000-8000-000000000001';
  const sucursalId = '0193f0a0-0000-7000-8000-0000000000c1';
  const tipoId = '0193f0a0-0000-7000-8000-0000000000d1';

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

  final elExpediente = {
    'branchId': sucursalId,
    'code': 'SUC-0001',
    'name': 'Centro',
    'branchTypeId': tipoId,
    'address': null,
    'schedule': <Object?>[],
    'profileVersion': 1,
  };

  /// Una ventana ALTA, y hace falta: el expediente es un formulario largo y un `tap`
  /// sobre algo que no se ve **no hace nada y no se queja**.
  void ventanaAlta(WidgetTester tester) {
    tester.view.physicalSize = const Size(1400, 4000);
    tester.view.devicePixelRatio = 1;

    addTearDown(tester.view.reset);
  }

  Future<ApiClientAutenticado> cliente({required List<Object?> sucursales}) async {
    final desnudo = ApiClient(
      config: config,
      cliente: MockClient((peticion) async {
        if (peticion.url.path.endsWith('/auth/login')) {
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
              'identityId': '0193f0a0-0000-7000-8000-00000000cafe',
              'sessionId': '0193f0a0-0000-7000-8000-00000000aaaa',
              'displayName': 'Beto Ruiz',
              'email': 'beto@ejemplo.mx',
            }),
            200,
          );
        }

        final ruta = peticion.url.path;

        if (ruta.endsWith('/profile')) {
          return http.Response(jsonEncode(elExpediente), 200);
        }

        if (ruta.endsWith('/branch-types')) {
          return http.Response(jsonEncode([unTipo]), 200);
        }

        return http.Response(jsonEncode(sucursales), 200);
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

  const todo = CapacidadesDeModulo(
    puedeVer: true,
    puedeCrear: true,
    puedeModificar: true,
    puedeArchivar: true,
  );

  /// Lo que la pantalla PIDIÓ, en orden: `tipos`, el id de un expediente, o nulo para
  /// volver a la lista.
  ///
  /// Es la dirección que el portón habría construido. Se recoge en lugar de navegar de
  /// verdad porque lo que se mide aquí es la pantalla: que el `context.go` del portón
  /// cuelgue el segmento donde debe lo fija el propio portón.
  late List<String?> pedidas;

  /// Y cómo se llama la fila que la pantalla cargó, para el rastro.
  late List<String> nombres;

  /// Monta Sucursales **como si la dirección ya dijera** lo que se le pasa.
  ///
  /// `StatefulBuilder` hace de dirección: la pantalla pide, esto lo guarda y vuelve a
  /// construirla con el valor nuevo. Es el mismo círculo que cierra el portón con un
  /// `context.go`, sin montar el router.
  Future<void> montar(
    WidgetTester tester, {
    bool viendoTipos = false,
    String? expedienteDe,
    List<Object?>? sucursales,
  }) async {
    ventanaAlta(tester);

    pedidas = [];
    nombres = [];

    final api = await cliente(sucursales: sucursales ?? [unaSucursal]);

    var tipos = viendoTipos;
    var expediente = expedienteDe;

    await tester.pumpWidget(
      MaterialApp(
        theme: MarcaSeventra.tema(),
        home: StatefulBuilder(
          builder: (_, repintar) => SucursalesWebScreen(
            repositorio: SucursalesRepositorioHttp(api),
            repositorioDeExpedientes: ExpedientesRepositorioHttp(api),
            empresaId: empresa,
            esMaestro: false,
            capacidades: todo,
            puedeEditarExpedientes: true,
            viendoTipos: tipos,
            expedienteDe: expediente,
            alVerTipos: (viendo) => repintar(() {
              tipos = viendo;
              pedidas.add(viendo ? 'tipos' : null);
            }),
            alVerExpediente: (sucursal) => repintar(() {
              expediente = sucursal?.id;
              pedidas.add(sucursal?.id);
            }),
            alConocerElNombre: (_, nombre) => nombres.add(nombre),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
  }

  group('la dirección abre lo de dentro, sin tocar nada', () {
    testWidgets('con «tipos» se entra al catálogo', (tester) async {
      // ES EL ENLACE PEGADO Y EL «ATRÁS» DEL NAVEGADOR: nadie pulsa nada, la dirección
      // ya lo decía. Antes esto era imposible — el `bool` nacía en falso y sólo un
      // botón lo movía.
      await montar(tester, viendoTipos: true);

      expect(find.text('Tipos de sucursal'), findsWidgets);

      // Y NO SE VE LA LISTA DE DETRÁS: su buscador es lo que quedaría si la pantalla
      // ignorara la dirección y pintara la lista.
      expect(find.text('Buscar por nombre o código'), findsNothing);
    });

    testWidgets('con el id de una sucursal se abre SU expediente', (tester) async {
      await montar(tester, expedienteDe: sucursalId);

      // LA SUCURSAL QUE LA DIRECCIÓN NOMBRA, con lo que el servidor devolvió de ella.
      expect(find.text('Guardar expediente'), findsOneWidget);
      expect(find.text('Centro'), findsWidgets);
    });

    testWidgets('y el nombre sube para el rastro, de los DATOS y no de la URL', (
      tester,
    ) async {
      // ⚠️ **LA URL LLEVA SÓLO EL ID**, decisión del dueño del 25 de octubre de 2026: el
      // nombre ahí sería estado disfrazado de dirección, y quedaría viejo en cuanto
      // alguien renombrara la sucursal. Así que el rastro dice «Expediente» mientras
      // carga y «Expediente de Centro» cuando la fila está en memoria.
      await montar(tester);

      await tester.tap(find.text('Centro'));
      await tester.pumpAndSettle();

      expect(nombres, contains('Centro'));
    });
  });

  group('la pantalla PIDE la dirección, no se mueve sola', () {
    testWidgets('el botón del catálogo pide «tipos», y volver pide la lista', (
      tester,
    ) async {
      await montar(tester);

      await tester.tap(find.text('Tipos de sucursal'));
      await tester.pumpAndSettle();

      expect(pedidas, ['tipos']);

      // EL REGRESO ES EL «‹ Sucursales» de arriba a la izquierda del catálogo, que no
      // es una pestaña: sin él no habría forma de salir.
      await tester.tap(find.text('Sucursales'));
      await tester.pumpAndSettle();

      // NULO ES «LA LISTA», que es la dirección de la pestaña a secas.
      expect(pedidas.last, isNull);
    });

    testWidgets('tocar una fila pide el expediente de ESA sucursal', (tester) async {
      await montar(tester);

      await tester.tap(find.text('Centro'));
      await tester.pumpAndSettle();

      expect(pedidas, [sucursalId]);
    });
  });

  group('una dirección que promete algo que no está', () {
    testWidgets('un id que no está en la lista devuelve a la lista', (tester) async {
      // ⚠️ PASA CON UN ENLACE VIEJO —la sucursal se eliminó— Y CON UN ID ESCRITO A MANO.
      // Sin esto se vería la lista con la dirección y el rastro prometiendo un
      // expediente que no existe, y «atrás» sería la única salida.
      //
      // **Y SÓLO SE PUEDE DECIDIR CUANDO LA LISTA LLEGA**: con la lista a medio traer,
      // un id desconocido y un id que todavía no ha llegado se ven igual.
      await montar(
        tester,
        expedienteDe: '0193f0a0-0000-7000-8000-0000000000ff',
      );

      expect(pedidas, [isNull]);

      // Y SE VE LA LISTA, no un hueco ni un error.
      expect(find.text('Buscar por nombre o código'), findsOneWidget);
      expect(find.text('Centro'), findsOneWidget);
    });

    testWidgets('con la sucursal presente NO devuelve a nadie', (tester) async {
      // EL CONTRAPUNTO, y no sobra: una corrección que se disparara siempre cerraría
      // todos los expedientes al terminar de cargar la lista, y la prueba de arriba
      // seguiría pasando.
      await montar(tester, expedienteDe: sucursalId);

      expect(pedidas, isEmpty);
    });
  });
}
