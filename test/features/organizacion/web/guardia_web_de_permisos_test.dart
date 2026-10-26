// EL GUARDIA WEB, gemelo de la matriz del servidor.
//
// ## Por qué hace falta uno en cada lado
//
// En el servidor, una ruta que no declara qué permiso exige **rompe** —lo vigila
// `MatrizDePermisosTests`, que recorre las rutas reales—. En la web no había nada
// equivalente: un botón sin gatear no rompía nada, y así fue como tres pantallas
// enseñaron «Nueva área», «Nuevo puesto», «Nueva sucursal», «Tipos de sucursal»,
// «Cerrar temporalmente» y los interruptores a un usuario con CERO permisos.
//
// Esta prueba es la mitad que faltaba: **monta cada pantalla con capacidades vacías y
// exige que no quede ni un botón de acción**. Y la lista de pantallas vive aquí, así que
// añadir una pantalla nueva al módulo y olvidarse de gatearla se nota al añadir su fila
// —que es una línea— en vez de no notarse nunca.
//
// ## Cómo decide qué es «un botón de acción»
//
// Por su ETIQUETA, contra una lista de verbos que escriben. Es deliberadamente tosco y
// es lo que lo hace genérico: no necesita saber nada de cada pantalla. Un botón de
// escritura que no se llame como ninguno de esos verbos se le escaparía, y por eso cada
// pantalla tiene además su prueba nombrada en `botones_por_permiso_test.dart`; esto es
// la red de debajo, no el único control.
//
// Lo que NO se cuenta como acción: «Cerrar» y «Volver» —que sólo navegan—, «Intentar de
// nuevo» —que recarga una lectura fallida— y el buscador.

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
import 'package:riseg_one/core/trabajo_sin_guardar/guardia_de_salida.dart';
import 'package:riseg_one/core/config/api_config.dart';
import 'package:riseg_one/core/design_system/design_system_web.dart';
import 'package:riseg_one/core/logging/app_logger.dart';
import 'package:riseg_one/features/organizacion/web/datos/areas_repositorio_http.dart';
import 'package:riseg_one/features/organizacion/web/datos/expedientes_repositorio_http.dart';
import 'package:riseg_one/features/organizacion/web/datos/puestos_repositorio_http.dart';
import 'package:riseg_one/features/organizacion/web/datos/sucursales_repositorio_http.dart';
import 'package:riseg_one/features/organizacion/web/presentation/areas_web_screen.dart';
import 'package:riseg_one/features/organizacion/web/presentation/puestos_web_screen.dart';
import 'package:riseg_one/features/organizacion/web/presentation/sucursales_web_screen.dart';
import 'package:riseg_one/features/organizacion/web/presentation/tipos_de_sucursal_web_screen.dart';
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

/// Los verbos que escriben. Si la etiqueta de un botón empieza por uno de éstos, ese
/// botón ofrece una escritura.
const _verbosQueEscriben = [
  'Nueva',
  'Nuevo',
  'Guardar',
  'Crear',
  'Agregar',
  'Eliminar',
  'Cerrar temporalmente',
  'Reabrir',
  'Desactivar',
  'Activar',
  'Editar',
  'Tipos de sucursal',
];

void main() {
  final config = ApiConfig.resolve(
    raw: 'http://localhost:5199',
  ).when(ok: (c) => c, failure: (f) => throw StateError(f.message));

  final t0 = DateTime.utc(2026, 10, 21, 12);
  const empresa = '0193f0a0-0000-7000-8000-000000000001';

  String cuerpoDeSesion() => jsonEncode({
    'accessToken': 'at_1',
    'accessExpiresAt': t0.add(const Duration(minutes: 30)).toIso8601String(),
    'refreshToken': 'rt_1',
    'refreshExpiresAt': t0.add(const Duration(days: 14)).toIso8601String(),
    'identityId': '0193f0a0-0000-7000-8000-00000000cafe',
    'sessionId': '0193f0a0-0000-7000-8000-00000000aaaa',
    'displayName': 'Sin Permisos',
    'email': 'sinpermisos@ejemplo.mx',
  });

  /// Un cliente cuyas lecturas devuelven **una fila**, para que las pantallas tengan
  /// algo que pintar: con la lista vacía saldría el estado vacío, que es otro caso y
  /// tiene su propia prueba.
  Future<ApiClientAutenticado> cliente() async {
    final desnudo = ApiClient(
      config: config,
      cliente: MockClient((peticion) async {
        if (peticion.url.path.endsWith('/auth/login')) {
          return http.Response(cuerpoDeSesion(), 200);
        }

        // NINGUNA ESCRITURA SE SIMULA: esta prueba va de que no haya por dónde
        // pedirlas. Si llegara una, el 404 lo notaría.
        if (peticion.method != 'GET') {
          return http.Response('{"code":"no_deberia_pedirse"}', 404);
        }

        final ruta = peticion.url.path;

        if (ruta.endsWith('/areas')) {
          return http.Response(
            jsonEncode([
              {
                'id': '0193f0a0-0000-7000-8000-0000000000a1',
                'code': 'OPE',
                'name': 'Operaciones',
                'status': 'activa',
              },
            ]),
            200,
          );
        }

        if (ruta.endsWith('/positions')) {
          return http.Response(
            jsonEncode([
              {
                'id': '0193f0a0-0000-7000-8000-0000000000b1',
                'areaId': '0193f0a0-0000-7000-8000-0000000000a1',
                'code': 'PUE-0001',
                'name': 'Supervisor',
                'kind': 'operativo',
                'hierarchyLevel': 3,
                'description': null,
                'status': 'activa',
              },
            ]),
            200,
          );
        }

        if (ruta.endsWith('/branch-types')) {
          return http.Response(
            jsonEncode([
              {
                'id': '0193f0a0-0000-7000-8000-0000000000d1',
                'code': 'MAT',
                'name': 'Matriz',
                'status': 'activa',
              },
            ]),
            200,
          );
        }

        if (ruta.endsWith('/branches')) {
          return http.Response(
            jsonEncode([
              {
                'id': '0193f0a0-0000-7000-8000-0000000000c1',
                'code': 'SUC-0001',
                'name': 'Centro',
                'branchTypeId': '0193f0a0-0000-7000-8000-0000000000d1',
                'status': 'activa',
                'operationalStatus': 'operando',
              },
            ]),
            200,
          );
        }

        return http.Response('[]', 200);
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
    await sesion.iniciarSesion(email: 'sinpermisos@ejemplo.mx', password: 'x');

    return ApiClientAutenticado(cliente: desnudo, gestor: sesion);
  }

  /// Las pantallas del módulo, cada una con cómo se construye.
  ///
  /// **AÑADIR UNA PANTALLA ES AÑADIR UNA FILA.** Es el precio de que el guardia sea
  /// web: no hay un `EndpointDataSource` de pantallas que recorrer, así que la lista
  /// es explícita y su ausencia se nota al escribirla.
  final pantallas = <String, Widget Function(ApiClientAutenticado, CapacidadesDeModulo)>{
    'Áreas': (c, caps) => AreasWebScreen(
      repositorio: AreasRepositorioHttp(c),
      empresaId: empresa,
      esMaestro: false,
      capacidades: caps,
    ),
    'Puestos': (c, caps) => PuestosWebScreen(
      repositorio: PuestosRepositorioHttp(c),
      repositorioDeAreas: AreasRepositorioHttp(c),
      empresaId: empresa,
      esMaestro: false,
      capacidades: caps,
    ),
    'Sucursales': (c, caps) => SucursalesWebScreen(
      repositorio: SucursalesRepositorioHttp(c),
      repositorioDeExpedientes: ExpedientesRepositorioHttp(c),
      empresaId: empresa,
      esMaestro: false,
      capacidades: caps,
      puedeEditarExpedientes: false,
      // D-56 · UNO PROPIO: aquí se mide qué botones se ofrecen con qué permiso.
      guardia: GuardiaDeSalida(),
      // D-39 · LA LISTA, QUE ES LO QUE ESTA PRUEBA MIRA. Lo de dentro lo dice la
      // dirección, y aquí no hay ninguna abierta.
      viendoTipos: false,
      expedienteDe: null,
      alVerTipos: (_) {},
      alVerExpediente: (_) {},
    ),
    'Tipos de sucursal': (c, caps) => TiposDeSucursalWebScreen(
      repositorio: SucursalesRepositorioHttp(c),
      empresaId: empresa,
      esMaestro: false,
      capacidades: caps,
    ),
  };

  /// Las etiquetas de botón que la pantalla está enseñando ahora mismo.
  List<String> botonesVisibles(WidgetTester tester) => tester
      .widgetList<RisegButton>(find.byType(RisegButton))
      .map((b) => b.label)
      .toList();

  Future<void> montar(
    WidgetTester tester,
    Widget Function(ApiClientAutenticado, CapacidadesDeModulo) construir,
    CapacidadesDeModulo caps,
  ) async {
    tester.view.physicalSize = const Size(1400, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final c = await cliente();

    await tester.pumpWidget(
      MaterialApp(theme: MarcaSeventra.tema(), home: construir(c, caps)),
    );

    await tester.pumpAndSettle();
  }

  group('Con CERO capacidades, ninguna pantalla ofrece una escritura', () {
    for (final entrada in pantallas.entries) {
      testWidgets(entrada.key, (tester) async {
        await montar(tester, entrada.value, const CapacidadesDeModulo.ninguna());

        final ofrecidos = botonesVisibles(tester)
            .where(
              (etiqueta) =>
                  _verbosQueEscriben.any((v) => etiqueta.startsWith(v)),
            )
            .toList();

        expect(
          ofrecidos,
          isEmpty,
          reason:
              '${entrada.key} ofrece escrituras a quien no puede hacerlas: $ofrecidos',
        );
      });
    }
  });

  group('Con TODAS las capacidades, sí las ofrece', () {
    // ⚠️ EL CONTRAPUNTO, Y SIN ÉL ESTE GUARDIA NO VALE NADA. El grupo de arriba
    // pasaría igual si las pantallas no pintaran ni un botón nunca —si fallaran al
    // cargar, si `RisegButton` cambiara de nombre, si `botonesVisibles` devolviera
    // siempre vacío—. Aquí se exige que las mismas pantallas, con permisos, sí
    // ofrezcan algo.
    const todas = CapacidadesDeModulo(
      puedeVer: true,
      puedeCrear: true,
      puedeModificar: true,
      puedeArchivar: true,
    );

    for (final entrada in pantallas.entries) {
      testWidgets(entrada.key, (tester) async {
        await montar(tester, entrada.value, todas);

        final ofrecidos = botonesVisibles(tester)
            .where(
              (etiqueta) =>
                  _verbosQueEscriben.any((v) => etiqueta.startsWith(v)),
            )
            .toList();

        expect(
          ofrecidos,
          isNotEmpty,
          reason:
              '${entrada.key} no ofrece ninguna escritura ni con todos los '
              'permisos: o la pantalla no cargó, o el guardia mide mal',
        );
      });
    }
  });

  testWidgets('con sólo CONSULTAR tampoco hay escrituras', (tester) async {
    // EL CASO QUE EL DUEÑO VA A PROBAR CON BETO: «sólo Consultar». Ver la lista sí,
    // tocar nada.
    const soloVer = CapacidadesDeModulo(
      puedeVer: true,
      puedeCrear: false,
      puedeModificar: false,
      puedeArchivar: false,
    );

    await montar(tester, pantallas['Áreas']!, soloVer);

    expect(find.text('Operaciones'), findsOneWidget);
    expect(find.text('Nueva área'), findsNothing);
  });
}
