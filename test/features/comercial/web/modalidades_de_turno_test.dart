// La pantalla del catálogo de MODALIDADES DE TURNO, que no existía.
//
// ## Por qué esta prueba existe
//
// 🚫 **La ruta del servidor y el método del repositorio estaban desde C3; la pantalla no.**
// Los otros dos catálogos de la familia —tipos de servicio y tipos de sucursal— sí la
// tenían, y el tercero se quedó sin ella **sin que nadie lo decidiera**. El dueño lo
// encontró el 18 de noviembre de 2026 probando el ensayo: «Modalidad de turno» sólo ofrecía
// «Sin modalidad», su empresa no tenía ni una fila y **no había forma de dárselas desde la
// aplicación**.
//
// Lo que se afirma aquí:
//
//  1. **el catálogo vacío dice qué se rompe sin él** y ofrece agregar las recomendadas;
//  2. **la lista enseña las tres respuestas** de una modalidad: su explicación, si la plaza
//     es fija de día o de noche, y **cómo se captura su horario**;
//  3. **editar manda la forma de captura y la duración**, y pasar a una captura semanal
//     **quita** la duración mandando cero — porque un nulo significa «no la toques»;
//  4. **sin permiso de escribir no hay botones**.

import 'dart:convert';

import 'package:flutter/material.dart';
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
import 'package:riseg_one/core/trabajo_sin_guardar/guardia_de_salida.dart';
import 'package:riseg_one/features/comercial/web/datos/condiciones_repositorio_http.dart';
import 'package:riseg_one/features/comercial/web/presentation/modalidades_de_turno_web_screen.dart';
import 'package:riseg_one/features/usuarios/web/marca_seventra.dart';

class _Almacen implements AlmacenSesionRemota {
  CredencialRemota? guardada;

  @override
  Future<CredencialRemota?> leer() async => guardada;

  @override
  Future<void> escribir(CredencialRemota credencial) async => guardada = credencial;

  @override
  Future<void> borrar() async => guardada = null;
}

class _Pedida {
  _Pedida(this.metodo, this.url, this.cuerpo);

  final String metodo;
  final Uri url;
  final String cuerpo;
}

void main() {
  const empresa = '0193f0cc-0000-7000-8000-000000000001';
  const rotativa = '0193f0cc-0000-7000-8000-00000000000a';
  const oficina = '0193f0cc-0000-7000-8000-00000000000b';

  final t0 = DateTime.utc(2026, 1, 15, 18);

  final config = ApiConfig.resolve(
    raw: 'http://localhost:5199',
  ).when(ok: (c) => c, failure: (f) => throw StateError(f.message));

  final catalogo = [
    {
      'id': rotativa,
      'code': '24X24',
      'name': '24 × 24',
      'description': 'Un día de trabajo y uno de descanso. '
          'Para cubrir 24/7 se necesitan 2 personas.',
      'requiresPeriod': false,
      'scheduleStyle': 'hora_de_cambio',
      'shiftMinutes': 1440,
      'status': 'activa',
      'updatedAt': '2026-01-01T18:00:00Z',
    },
    {
      'id': oficina,
      'code': 'LUN_VIE_8',
      'name': 'Lunes a viernes, 8 horas',
      'description': 'Jornada administrativa de ocho horas.',
      'requiresPeriod': false,
      'scheduleStyle': 'semanal_precargada',
      'shiftMinutes': null,
      'status': 'activa',
      'updatedAt': '2026-01-01T18:00:00Z',
    },
  ];

  Future<(ApiClientAutenticado, List<_Pedida>)> cliente({
    required http.Response? Function(_Pedida pedida) responder,
  }) async {
    final pedidas = <_Pedida>[];

    final desnudo = ApiClient(
      config: config,
      cliente: MockClient((p) async {
        if (p.url.path.endsWith('/auth/login')) {
          return http.Response(
            jsonEncode({
              'accessToken': 'at_1',
              'accessExpiresAt': t0.add(const Duration(minutes: 30)).toIso8601String(),
              'refreshToken': 'rt_1',
              'refreshExpiresAt': t0.add(const Duration(days: 14)).toIso8601String(),
              'sessionId': '0193f0cc-0000-7000-8000-00000000aaaa',
              'identityId': '0193f0cc-0000-7000-8000-00000000bbbb',
              'displayName': 'Ana Torres',
              'email': 'ana@seventra.mx',
            }),
            200,
          );
        }

        final pedida = _Pedida(p.method, p.url, p.body);
        pedidas.add(pedida);

        return responder(pedida) ?? http.Response(jsonEncode(const []), 200);
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

  Future<void> montar(
    WidgetTester tester, {
    required ApiClientAutenticado api,
    bool puedeModificar = true,
  }) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: MarcaSeventra.tema(),
        home: ModalidadesDeTurnoWebScreen(
          repositorio: CondicionesRepositorioHttp(api),
          empresaId: empresa,
          capacidades: puedeModificar
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
                ),
          guardia: GuardiaDeSalida(),
          onVolver: () {},
        ),
      ),
    );

    await tester.pumpAndSettle();
  }

  testWidgets('el catálogo VACÍO dice qué se rompe y ofrece las recomendadas', (
    tester,
  ) async {
    var agregadas = false;

    final (api, pedidas) = await cliente(
      responder: (p) {
        if (p.url.path.endsWith('/shift-modalities/recommended')) {
          agregadas = true;

          return http.Response(jsonEncode(catalogo), 200);
        }

        if (p.url.path.endsWith('/shift-modalities')) {
          return http.Response(jsonEncode(agregadas ? catalogo : const []), 200);
        }

        return null;
      },
    );

    await montar(tester, api: api);

    expect(find.text('Todavía no hay modalidades'), findsOneWidget);

    // 🚫 SE DICE QUÉ SE ROMPE SIN ELLAS, que es lo que el dueño vivió.
    expect(
      find.textContaining('no se puede capturar una condición comercial'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('modalidades-recomendadas')));
    await tester.pumpAndSettle();

    expect(
      pedidas.any((p) => p.metodo == 'POST' && p.url.path.endsWith('/recommended')),
      isTrue,
    );

    expect(find.text('24 × 24'), findsOneWidget);
    expect(find.text('Lunes a viernes, 8 horas'), findsOneWidget);
  });

  testWidgets('la lista dice la explicación y CÓMO se captura el horario', (
    tester,
  ) async {
    final (api, _) = await cliente(
      responder: (p) => p.url.path.endsWith('/shift-modalities')
          ? http.Response(jsonEncode(catalogo), 200)
          : null,
    );

    await montar(tester, api: api);

    // La explicación, con su cuenta de personas dentro.
    expect(find.textContaining('se necesitan 2 personas'), findsOneWidget);

    // Y la forma de captura, con la duración cuando se conoce: es lo que decide qué
    // pregunta ve quien captura una condición.
    expect(
      find.textContaining('Se captura la hora de cambio de turno · turnos de 24 h'),
      findsOneWidget,
    );

    expect(
      find.textContaining('nace con lunes a viernes puesto'),
      findsOneWidget,
    );
  });

  testWidgets('editar manda la captura, y pasar a semanal QUITA la duración', (
    tester,
  ) async {
    String? cuerpo;

    final (api, _) = await cliente(
      responder: (p) {
        if (p.metodo == 'PATCH') {
          cuerpo = p.cuerpo;

          return http.Response(jsonEncode(catalogo.first), 200);
        }

        if (p.url.path.endsWith('/shift-modalities')) {
          return http.Response(jsonEncode(catalogo), 200);
        }

        return null;
      },
    );

    await montar(tester, api: api);

    await tester.tap(find.byKey(const Key('modalidad-editar-$rotativa')));
    await tester.pumpAndSettle();

    expect(find.text('Editar la modalidad'), findsOneWidget);

    // Se pasa de «hora de cambio» a horario semanal.
    final captura = find.descendant(
      of: find.byKey(clavesDeModalidad.captura),
      matching: find.byWidgetPredicate((w) => w is DropdownButtonFormField),
    );

    await tester.ensureVisible(captura);
    await tester.pumpAndSettle();
    await tester.tap(captura);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Horario semanal, día por día').last);
    await tester.pumpAndSettle();

    // Y el campo de la duración desaparece con el cambio.
    expect(find.byKey(clavesDeModalidad.duracion), findsNothing);

    await tester.tap(find.byKey(clavesDeModalidad.guardar));
    await tester.pumpAndSettle();

    final enviado = jsonDecode(cuerpo!) as Map<String, dynamic>;

    expect(enviado['scheduleStyle'], 'semanal_vacia');

    // 🚫 **CERO, NO AUSENTE:** un nulo significa «no la toques», así que sin esto la
    // modalidad se quedaría con una duración huérfana y el servidor rechazaría la petición
    // entera por su propia restricción.
    expect(enviado['shiftMinutes'], 0);
  });

  testWidgets('sin permiso de escribir no hay ningún botón que escriba', (
    tester,
  ) async {
    final (api, _) = await cliente(
      responder: (p) => p.url.path.endsWith('/shift-modalities')
          ? http.Response(jsonEncode(catalogo), 200)
          : null,
    );

    await montar(tester, api: api, puedeModificar: false);

    expect(find.text('24 × 24'), findsOneWidget);
    expect(find.byKey(const Key('modalidades-recomendadas')), findsNothing);
    expect(find.byKey(const Key('modalidades-nueva')), findsNothing);
    expect(find.byKey(const Key('modalidad-editar-$rotativa')), findsNothing);
  });
}
