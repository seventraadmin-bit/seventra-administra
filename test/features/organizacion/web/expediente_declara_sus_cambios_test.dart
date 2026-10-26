// D-56 · EL EXPEDIENTE DE UNA SUCURSAL DECLARA LO QUE SE PERDERÍA, Y LO NOMBRA.
//
// ## Qué agujero cierra esto
//
// ⚠️ **ESTA PANTALLA ERA UN FORMULARIO SIN DETECCIÓN DE CAMBIOS.** Tenía su
// `_compararCon`, pero ése compara **versiones del servidor** para resolver el choque de
// M3 —responde «¿qué tocó el otro?»— y no «¿qué escribí yo?». Nadie se registraba en el
// `GuardiaDeSalida`, así que lo escrito aquí se perdía sin preguntar por los cuatro
// caminos de D-56, **incluido cambiar de empresa**, que preguntaba desde E1-B para la
// pantalla de Empresa y aquí no tenía a quién preguntar.
//
// Lo destapó la regla permanente que el dueño aprobó el 26 de octubre de 2026: **toda
// pantalla con «Guardar» se registra en el guardia**.
//
// ## Lo que se afirma aquí, y lo que no
//
// Aquí se mide **la mitad de la pantalla**: que declara cuándo tiene algo que perder, que
// lo nombra, y que suelta su registro al desmontarse. Que la pregunta salga y que
// cancelar deje la dirección quieta lo fija
// `test/app/shell/salida_con_trabajo_sin_guardar_test.dart`, con el router de verdad.

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
import 'package:riseg_one/core/trabajo_sin_guardar/guardia_de_salida.dart';
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

  final t0 = DateTime.utc(2026, 10, 26, 12);

  const empresa = '0193f0a0-0000-7000-8000-000000000001';
  const sucursalId = '0193f0a0-0000-7000-8000-0000000000b1';
  const tipoId = '0193f0a0-0000-7000-8000-0000000000d1';
  const otroTipoId = '0193f0a0-0000-7000-8000-0000000000d2';

  /// El expediente que el servidor devuelve. **Con domicilio y con un tramo**, para que
  /// los cuatro bloques que el formulario compara tengan algo que comparar.
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
      {
        'dayOfWeek': 2,
        'startMinute': 540,
        'endMinute': 1080,
        'crossesMidnight': false,
      },
    ],
    'profileVersion': 1,
  });

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

        return http.Response(expedienteJson(), 200);
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

  const laSucursal = Sucursal(
    id: sucursalId,
    codigo: 'SUC-0001',
    nombre: 'Centro',
    activa: true,
    tipoId: tipoId,
    estadoOperativo: 'operando',
  );

  /// Una ventana ALTA, y hace falta: el expediente es un formulario largo y un `tap` o un
  /// `enterText` sobre algo que no se ve **no hace nada y no se queja**.
  void ventanaAlta(WidgetTester tester) {
    tester.view.physicalSize = const Size(1400, 4000);
    tester.view.devicePixelRatio = 1;

    addTearDown(tester.view.reset);
  }

  /// Monta el expediente con el guardia que se le pase, **dentro de un interruptor** que
  /// permite desmontarlo sin tirar el árbol: así se puede medir que suelta su registro.
  Future<void> montar(
    WidgetTester tester, {
    required GuardiaDeSalida guardia,
    required ValueNotifier<bool> montado,
  }) async {
    ventanaAlta(tester);

    final api = await cliente();

    await tester.pumpWidget(
      MaterialApp(
        theme: MarcaSeventra.tema(),
        home: ValueListenableBuilder<bool>(
          valueListenable: montado,
          builder: (_, sigue, _) => sigue
              ? Scaffold(
                  body: ExpedienteSucursalWebScreen(
                    repositorio: ExpedientesRepositorioHttp(api),
                    repositorioDeSucursales: SucursalesRepositorioHttp(api),
                    empresaId: empresa,
                    sucursal: laSucursal,
                    tipos: const [
                      TipoDeSucursal(
                        id: tipoId,
                        codigo: 'MAT',
                        nombre: 'Matriz',
                        activo: true,
                      ),
                      TipoDeSucursal(
                        id: otroTipoId,
                        codigo: 'BOD',
                        nombre: 'Bodega',
                        activo: true,
                      ),
                    ],
                    capacidades: todo,
                    esMaestro: false,
                    puedeEditarExpedientes: true,
                    onVolver: () {},
                    guardia: guardia,
                  ),
                )
              : const Scaffold(body: Text('desmontado')),
        ),
      ),
    );

    await tester.pumpAndSettle();
  }

  /// El campo que lleva esta etiqueta.
  ///
  /// `RisegTextField` pinta un `Text(label)` y debajo su campo, los dos en la misma
  /// `Column`; así que del texto se sube a esa `Column` —la más cercana— y de ahí se baja
  /// al campo. Es el mismo recorrido que usa `expediente_pantalla_test`.
  Finder campoDe(String etiqueta) => find
      .descendant(
        of: find
            .ancestor(of: find.text(etiqueta), matching: find.byType(Column))
            .first,
        matching: find.byType(TextField),
      )
      .first;

  testWidgets('recién cargado NO hay nada que perder', (tester) async {
    // ABRIR NO ES ESCRIBIR. Si declarara cambios de entrada, cada vez que alguien
    // consultara un expediente —que es lo que más se hace— saldría la pregunta al salir, y
    // entonces se contestaría sin leerla.
    final guardia = GuardiaDeSalida();

    await montar(tester, guardia: guardia, montado: ValueNotifier(true));

    expect(guardia.hayCambiosSinGuardar, isFalse);
    expect(guardia.queSePierde, isNull);
  });

  group('qué cuenta como un cambio', () {
    testWidgets('el nombre', (tester) async {
      final guardia = GuardiaDeSalida();

      await montar(tester, guardia: guardia, montado: ValueNotifier(true));

      await tester.enterText(campoDe('Nombre'), 'Centro Histórico');
      await tester.pumpAndSettle();

      expect(guardia.hayCambiosSinGuardar, isTrue);
    });

    testWidgets('un campo del domicilio', (tester) async {
      final guardia = GuardiaDeSalida();

      await montar(tester, guardia: guardia, montado: ValueNotifier(true));

      await tester.enterText(campoDe('Calle'), 'Juárez');
      await tester.pumpAndSettle();

      expect(guardia.hayCambiosSinGuardar, isTrue);
    });

    testWidgets('escribir y DESHACER no es un cambio', (tester) async {
      // ⚠️ ES LA REGLA QUE SEPARA ESTO DE UN «SE TOCÓ ALGO», y la razón es de producto:
      // una pregunta que sale porque alguien escribió una letra y la borró enseña a
      // contestar el diálogo sin leerlo, y entonces el día que haya algo de verdad que
      // perder también se contestará sin leer.
      //
      // Por eso se compara contra el expediente CARGADO y no contra un indicador de
      // «tocado».
      final guardia = GuardiaDeSalida();

      await montar(tester, guardia: guardia, montado: ValueNotifier(true));

      await tester.enterText(campoDe('Nombre'), 'Centro Histórico');
      await tester.pumpAndSettle();
      expect(guardia.hayCambiosSinGuardar, isTrue);

      await tester.enterText(campoDe('Nombre'), 'Centro');
      await tester.pumpAndSettle();

      expect(guardia.hayCambiosSinGuardar, isFalse);
    });

    testWidgets('los espacios de sobra no son un cambio', (tester) async {
      // El formulario manda el nombre recortado, así que comparar sin recortar diría
      // «sucio» por una barra espaciadora.
      final guardia = GuardiaDeSalida();

      await montar(tester, guardia: guardia, montado: ValueNotifier(true));

      await tester.enterText(campoDe('Nombre'), '  Centro  ');
      await tester.pumpAndSettle();

      expect(guardia.hayCambiosSinGuardar, isFalse);
    });
  });

  group('cómo se llama lo que se perdería', () {
    testWidgets('dice la sucursal por su nombre', (tester) async {
      // Lo pidió el dueño el 26 de octubre de 2026: «Tienes cambios sin guardar en el
      // expediente de la sucursal Centro». Aquí el nombre hace falta de verdad, porque hay
      // una sucursal por fila y «el expediente» a secas no diría de qué.
      final guardia = GuardiaDeSalida();

      await montar(tester, guardia: guardia, montado: ValueNotifier(true));

      await tester.enterText(campoDe('Calle'), 'Juárez');
      await tester.pumpAndSettle();

      expect(guardia.queSePierde, 'el expediente de la sucursal Centro');
    });

    testWidgets('y usa el nombre GUARDADO, no el que se está escribiendo', (
      tester,
    ) async {
      // ⚠️ RENOMBRAR ES EL CASO QUE LO DESTAPA: con el nombre del formulario, a alguien
      // que está cambiando «Centro» por «Centro Histórico» la pregunta le hablaría de una
      // sucursal que todavía no existe con ese nombre.
      final guardia = GuardiaDeSalida();

      await montar(tester, guardia: guardia, montado: ValueNotifier(true));

      await tester.enterText(campoDe('Nombre'), 'Centro Histórico');
      await tester.pumpAndSettle();

      expect(guardia.queSePierde, 'el expediente de la sucursal Centro');
    });
  });

  testWidgets('al desmontarse SUELTA su registro', (tester) async {
    // ⚠️ ES EL DESCUIDO CARO Y NO EL BARATO. Un registro pegado tras el `dispose`
    // responde «sí hay cambios» para siempre, así que **cada navegación preguntaría** por
    // un formulario que ya no existe: parecería un cuelgue del producto y nadie sabría
    // dónde mirar.
    //
    // Y tiene una trampa fina detrás: `liberar` compara por identidad, y Dart sólo
    // garantiza la igualdad entre dos referencias **al mismo método del mismo objeto**.
    // Registrar con una lambda `() => …` y soltar con otra no soltaría nada — y compila
    // igual.
    final guardia = GuardiaDeSalida();
    final montado = ValueNotifier(true);

    await montar(tester, guardia: guardia, montado: montado);

    await tester.enterText(campoDe('Calle'), 'Juárez');
    await tester.pumpAndSettle();
    expect(guardia.hayCambiosSinGuardar, isTrue);

    montado.value = false;
    await tester.pumpAndSettle();

    expect(find.text('desmontado'), findsOneWidget);
    expect(
      guardia.hayCambiosSinGuardar,
      isFalse,
      reason: 'el registro del expediente desmontado tenía que soltarse',
    );
  });
}
