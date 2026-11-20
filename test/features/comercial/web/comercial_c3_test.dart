// C3 · LA PESTAÑA COMERCIAL de un servicio: líneas, condiciones y sueldo de referencia.
//
// ## Qué se fija aquí, y por qué estas cosas
//
//  1. **el permiso de precios es SUYO y no `manage`.** Desde la migración 0062,
//     `clients_services.manage` da de alta líneas y **no** abre condiciones. Si la pantalla
//     plegara los dos en la misma bandera, ofrecería botones que el servidor contesta con
//     403 — y eso se ve igual que un error del servidor;
//  2. **«Retirar» NO deja de cobrar, y la pantalla lo dice.** Retirar una línea deja su
//     condición abierta, así que sigue facturando; lo que deja de cobrar es cerrarla. Suenan
//     igual y son opuestas en lo que importa;
//  3. **`cupo_rebasado` es un AVISO de una respuesta 200**, no un error. La condición se
//     guardó y el servidor no movió a nadie: pintarlo como fallo diría que no se guardó;
//  4. **el 409 del candado enseña el precio que el servidor tiene AHORA.** Sin eso, un
//     conflicto sólo puede decir «recarga» y la persona pierde lo que escribió;
//  5. **una línea sin condición no enseña `$0.00`.** Ausencia no es cero: un cero se leería
//     como «se cobra nada», que es una afirmación distinta de «no está puesto el precio»;
//  6. **el sueldo de referencia pide un permiso de PERSONAL.** Quien administra precios no
//     lo ve por eso.
//
// ## Lo que NO está aquí
//
// La aritmética de la semana —el cruce de medianoche, el solape de bloques— es del servidor
// y la garantiza una exclusión del motor. Repetirla aquí dejaría dos implementaciones que
// algún día discreparían.

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
import 'package:riseg_one/core/fechas/dia_de_negocio.dart';
import 'package:riseg_one/core/logging/app_logger.dart';
import 'package:riseg_one/core/trabajo_sin_guardar/guardia_de_salida.dart';
import 'package:riseg_one/features/comercial/web/datos/condiciones_repositorio_http.dart';
import 'package:riseg_one/features/comercial/web/modelos/condicion_comercial.dart';
import 'package:riseg_one/features/comercial/web/presentation/dialogo_de_condicion.dart'
    show clavesDeCierre, clavesDeCondicion, clavesDeRetiro;
import 'package:riseg_one/features/comercial/web/presentation/dialogo_de_renovacion.dart';
import 'package:riseg_one/features/comercial/web/presentation/seccion_comercial.dart';
import 'package:riseg_one/features/organizacion/web/datos/areas_repositorio_http.dart';
import 'package:riseg_one/features/organizacion/web/presentation/dialogo_de_puesto_rapido.dart'
    show clavesDePuestoRapido;
import 'package:riseg_one/features/organizacion/web/datos/puestos_repositorio_http.dart';
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

/// Una petición vista por el cliente falso.
class _Pedida {
  _Pedida(this.metodo, this.url, this.cuerpo);

  final String metodo;
  final Uri url;
  final String cuerpo;
}

void main() {
  const empresa = '0193f0aa-0000-7000-8000-000000000001';
  const servicio = '0193f0aa-0000-7000-8000-000000000002';
  const linea = '0193f0aa-0000-7000-8000-000000000003';
  const condicion = '0193f0aa-0000-7000-8000-000000000004';
  const puesto = '0193f0aa-0000-7000-8000-000000000005';
  const modalidad24 = '0193f0aa-0000-7000-8000-000000000006';
  const modalidad12 = '0193f0aa-0000-7000-8000-000000000007';
  const modalidad36 = '0193f0aa-0000-7000-8000-000000000008';
  const modalidadPropia = '0193f0aa-0000-7000-8000-000000000009';
  const modalidadRotativa = '0193f0aa-0000-7000-8000-00000000000c';
  const modalidadOficina = '0193f0aa-0000-7000-8000-00000000000d';
  const modalidad12Rotativa = '0193f0aa-0000-7000-8000-00000000000e';

  final t0 = DateTime.utc(2026, 1, 15, 18);

  final config = ApiConfig.resolve(
    raw: 'http://localhost:5199',
  ).when(ok: (c) => c, failure: (f) => throw StateError(f.message));

  final lineas = [
    {
      'id': linea,
      'serviceId': servicio,
      'name': 'Guardias intramuros',
      // EL TIPO DE LÍNEA, que el servidor manda desde la 0066.
      'kind': 'personal',
      'status': 'active',
      'updatedAt': '2026-01-10T18:00:00Z',
    },
  ];

  /// La condición vigente: 15 000.00 × 3 = 45 000.00 MXN.
  ///
  /// ⚠️ **`monthlyAmountMinor` LO MANDA EL SERVIDOR DERIVADO** (0066), y la pantalla lo
  /// enseña sin recalcularlo: con dos modos de cotización, dejar que cada cliente
  /// multiplique garantiza que algún día uno multiplique el total.
  final vigente = {
    'id': condicion,
    'commercialLineId': linea,
    'temporality': 'current',
    'startsOn': '2025-06-01',
    'endsOn': null,
    'kind': 'personal',
    'positionId': puesto,
    'shiftModalityId': modalidad24,
    'shiftPeriod': null,
    'shiftChangeMinute': null,
    'headcount': 3,
    'pricingMode': 'por_persona',
    'unitPriceMinor': 1500000,
    'monthlyTotalMinor': null,
    'monthlyAmountMinor': 4500000,
    'currency': 'MXN',
    'taxTreatment': 'mas_iva',
    'description': null,
    'observations': null,
    'version': 0,
    'schedules': [
      {
        'id': '0193f0aa-0000-7000-8000-00000000000a',
        'dayOfWeek': 1,
        'startMinute': 480,
        'endMinute': 1200,
        'durationMinutes': 720,
        'spansNextDay': false,
      },
    ],
    'updatedAt': '2026-01-10T18:00:00Z',
  };

  final modalidades = [
    // ⚠️ **NINGUNA TRAE UN NÚMERO DE PERSONAS COMO CAMPO**, y es lo que la pantalla recibe
    // de verdad desde el 14-nov-2026: las personas que el rol necesita van **dentro de la
    // explicación**, que la empresa puede corregir, y se leen junto al turno.
    {
      'id': modalidad24,
      'code': '24X24',
      'name': '24 × 24',
      'description': 'Un día de trabajo y uno de descanso. '
          'Para cubrir 24/7 se necesitan 2 personas.',
      'requiresPeriod': false,
      'status': 'activa',
      'updatedAt': '2026-01-01T18:00:00Z',
    },
    {
      'id': modalidad12,
      'code': '12X12_CORRIDO',
      'name': '12 × 12 corrido',
      'description': 'La plaza es diurna o nocturna. '
          'Para cubrir 24/7 se necesitan 2 personas, una por plaza.',
      'requiresPeriod': true,
      'status': 'activa',
      'updatedAt': '2026-01-01T18:00:00Z',
    },
    // LA DE DOCE POR TREINTA Y SEIS, con OTRO número en su frase: hace falta una distinta
    // para poder medir que cambiar el turno cambia **el texto** y no la cantidad.
    {
      'id': modalidad36,
      'code': '12X36',
      'name': '12 × 36',
      'description': 'Doce de trabajo y treinta y seis de descanso. '
          'Para cubrir 24/7 se necesitan 4 personas.',
      'requiresPeriod': true,
      'status': 'activa',
      'updatedAt': '2026-01-01T18:00:00Z',
    },
    // Y UNA PROPIA DE LA EMPRESA, cuya explicación no nombra ninguna cuenta: entonces no se
    // lee ningún número, que es lo honesto.
    {
      'id': modalidadPropia,
      'code': 'ROL_PROPIO',
      'name': 'Rol propio',
      'description': 'El que acordamos con este cliente.',
      'requiresPeriod': false,
      'status': 'activa',
      'updatedAt': '2026-01-01T18:00:00Z',
    },
    // ⚠️ **LAS DOS DE LA 0066, que son las que deciden QUÉ PREGUNTA se ve.** Una se captura
    // con la hora de cambio de turno —y entonces no hay rejilla semanal— y la otra con una
    // rejilla que nace puesta de lunes a viernes.
    {
      'id': modalidadRotativa,
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
    // Y LA QUE PIDE LAS DOS COSAS: hora de cambio **y** periodo. Hace falta una así para
    // medir que la hora es la del turno de DÍA y que la ayuda enseña las dos plazas — lo que
    // el dueño encontró contradiciéndose el 19-nov-2026.
    {
      'id': modalidad12Rotativa,
      'code': '12X12_TURNOS',
      'name': '12 × 12 por turnos',
      'description': 'Dos plazas: una de día y una de noche.',
      'requiresPeriod': true,
      'scheduleStyle': 'hora_de_cambio',
      'shiftMinutes': 720,
      'status': 'activa',
      'updatedAt': '2026-01-01T18:00:00Z',
    },
    {
      'id': modalidadOficina,
      'code': 'LUN_VIE_8',
      'name': 'Lunes a viernes, 8 horas',
      'description': 'Jornada administrativa de ocho horas. Se necesita 1 persona.',
      'requiresPeriod': false,
      'scheduleStyle': 'semanal_precargada',
      'shiftMinutes': null,
      'status': 'activa',
      'updatedAt': '2026-01-01T18:00:00Z',
    },
  ];

  final puestos = [
    {
      'id': puesto,
      'areaId': '0193f0aa-0000-7000-8000-00000000000b',
      'code': 'PUE-0001',
      'name': 'Guardia',
      'kind': 'operativo',
      'status': 'activa',
      'hierarchyLevel': 1,
      'description': null,
      'createdAt': '2026-01-01T18:00:00Z',
      'updatedAt': '2026-01-01T18:00:00Z',
    },
  ];

  /// La respuesta por omisión de cada ruta.
  http.Response porOmision(_Pedida p, List<Object?> condiciones) {
    final ruta = p.url.path;

    if (ruta.endsWith('/salary-references')) {
      return http.Response(jsonEncode(const []), 200);
    }

    if (ruta.endsWith('/terms')) {
      return http.Response(jsonEncode(condiciones), 200);
    }

    if (ruta.endsWith('/shift-modalities')) {
      return http.Response(jsonEncode(modalidades), 200);
    }

    if (ruta.endsWith('/positions')) {
      return http.Response(jsonEncode(puestos), 200);
    }

    if (ruta.endsWith('/commercial-lines')) {
      return http.Response(jsonEncode(lineas), 200);
    }

    return http.Response(jsonEncode(const {}), 200);
  }

  Future<(ApiClientAutenticado, List<_Pedida>)> cliente({
    List<Object?> condiciones = const [],
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
              'sessionId': '0193f0aa-0000-7000-8000-00000000aaaa',
              'identityId': '0193f0aa-0000-7000-8000-00000000bbbb',
              'displayName': 'Ana Torres',
              'email': 'ana@seventra.mx',
            }),
            200,
          );
        }

        final pedida = _Pedida(p.method, p.url, p.body);
        pedidas.add(pedida);

        return responder?.call(pedida) ?? porOmision(pedida, condiciones);
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
    bool puedeAdministrar = true,
    bool puedeTocarPrecios = true,
    bool puedeVerSueldos = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: MarcaSeventra.tema(),
        home: Scaffold(
          body: SeccionComercial(
            repositorio: CondicionesRepositorioHttp(api),
            empresaId: empresa,
            servicioId: servicio,
            puestos: PuestosRepositorioHttp(api),
            areas: AreasRepositorioHttp(api),
            puedeAdministrar: puedeAdministrar,
            puedeTocarPrecios: puedeTocarPrecios,
            puedeVerSueldos: puedeVerSueldos,
            hoy: () => const DiaDeNegocio(2026, 1, 15),
            guardia: GuardiaDeSalida(),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
  }

  /// El campo de texto que lleva esa llave.
  ///
  /// ⚠️ **No se busca por la etiqueta**: en este sistema de diseño la etiqueta es un `Text`
  /// ENCIMA del campo, no dentro, así que `widgetWithText` no lo encuentra. Y no se busca
  /// por posición, porque reordenar el formulario dejaría la prueba midiendo otro campo
  /// **sin fallar**.
  Finder campo(Key llave) => find.descendant(
    of: find.byKey(llave),
    matching: find.byType(TextFormField),
  );

  /// Abre el desplegable que lleva esa llave.
  ///
  /// ⚠️ **Se toca el `DropdownButtonFormField` y no el contenedor.** `RisegSelect` envuelve
  /// el campo en una `Column` con su etiqueta encima, así que tocar el centro del conjunto
  /// cae en la etiqueta y **no abre nada** — sin fallar, porque un toque en un `Text` es un
  /// toque válido. Se busca por predicado para no tener que nombrar el genérico del
  /// desplegable, que cambia en cada campo.
  Future<void> abrirDesplegable(WidgetTester tester, Key llave) async {
    final desplegable = find.descendant(
      of: find.byKey(llave),
      matching: find.byWidgetPredicate((w) => w is DropdownButtonFormField),
    );

    // ⚠️ `ensureVisible` ANTES DE TOCAR. El formulario de una condición es más alto que la
    // ventana de la prueba, así que la modalidad nace **fuera de pantalla** y un toque sobre
    // algo invisible no llega. El aviso de Flutter lo dice —«maybe the widget is off-screen»—
    // pero el fallo aparece dos líneas después, al no encontrar la opción del menú.
    await tester.ensureVisible(desplegable);
    await tester.pumpAndSettle();

    await tester.tap(desplegable);
    await tester.pumpAndSettle();
  }

  /// Abre «Corregir la vigente» desde el menú de la línea.
  ///
  /// El formulario llega **rellenado** con la condición que existe, que es lo que permite
  /// probar el comportamiento sin teclear siete campos.
  Future<void> abrirCorreccion(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Corregir la vigente'));
    await tester.pumpAndSettle();
  }

  group('lo que la tarjeta de una línea dice', () {
    testWidgets('el importe es precio × plazas, y se dice que es SIN IVA', (
      tester,
    ) async {
      final (api, _) = await cliente(condiciones: [vigente]);
      await montar(tester, api: api);

      expect(find.text('Guardias intramuros'), findsOneWidget);
      expect(find.text('Cobra hoy'), findsOneWidget);

      // 15 000.00 × 3 = 45 000.00. La cifra de la derecha es la que se mira al cotizar,
      // y la aritmética se enseña entera para que nadie tenga que confiar en ella.
      //
      // ⚠️ **YA NO DICE «PLAZAS»** (0066): la palabra sobra cuando la cuenta se lee, y en
      // una línea de concepto habría sido falsa — ahí se cobran unidades, no plazas.
      expect(
        find.text(r'$15,000.00 MXN × 3 = $45,000.00 MXN'),
        findsOneWidget,
      );

      // ⚠️ SE DICE QUE EL IMPORTE VA SIN IVA. El servidor suma así en los indicadores, y
      // una pantalla que lo sumara con impuesto daría dos cifras para la misma pregunta.
      expect(find.textContaining('Importe sin IVA'), findsOneWidget);
      expect(find.textContaining('Más IVA'), findsOneWidget);
    });

    testWidgets('el turno y el horario se leen con su duración', (tester) async {
      final (api, _) = await cliente(condiciones: [vigente]);
      await montar(tester, api: api);

      expect(find.textContaining('Guardia · 24 × 24'), findsOneWidget);
      expect(find.text('Lunes 08:00 → 20:00 (12 h)'), findsOneWidget);
    });

    testWidgets('una línea SIN condición dice que no cobra, y no enseña cero', (
      tester,
    ) async {
      final (api, _) = await cliente();
      await montar(tester, api: api);

      expect(
        find.text('Esta línea no cobra nada: no tiene condición.'),
        findsOneWidget,
      );

      // 🚫 AUSENCIA NUNCA ES CERO. Un `$0.00` se leería como «se cobra nada», que es una
      // afirmación distinta de «no está puesto el precio».
      expect(find.textContaining(r'$0.00'), findsNothing);
    });
  });

  group('el permiso de precios es SUYO y no «manage»', () {
    testWidgets('con manage y SIN precios no se ofrece poner la condición', (
      tester,
    ) async {
      final (api, _) = await cliente();
      await montar(tester, api: api, puedeTocarPrecios: false);

      // La línea existe y se puede administrar…
      expect(find.text('Guardias intramuros'), findsOneWidget);

      // …y el botón de poner precio NO está, ni en la tarjeta ni en el menú.
      expect(find.text('Poner su condición'), findsNothing);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      expect(find.text('Poner su condición'), findsNothing);
      expect(find.text('Renombrar'), findsOneWidget);
    });

    testWidgets('con el permiso de precios sí se ofrece', (tester) async {
      final (api, _) = await cliente();
      await montar(tester, api: api);

      expect(find.text('Poner su condición'), findsOneWidget);
    });

    testWidgets('sin el permiso de PERSONAL no se ofrece el sueldo de referencia', (
      tester,
    ) async {
      final (api, _) = await cliente(condiciones: [vigente]);
      await montar(tester, api: api, puedeVerSueldos: false);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      expect(find.text('Sueldo de referencia'), findsNothing);

      // Y las acciones de precios sí están: son dos permisos de dos módulos, y tener uno
      // no implica el otro en ninguna dirección.
      expect(find.text('Dejar de cobrar (cerrar)'), findsOneWidget);
    });
  });

  group('retirar una línea ES dejar de cobrar, con su fecha', () {
    /// 🚫 **ESTE GRUPO AFIRMABA LO CONTRARIO HASTA EL 19-nov-2026**, y con razón: retirar
    /// dejaba la condición abierta y el diálogo lo advertía. El dueño lo probó en pantalla,
    /// se confundió de todas formas y cambió el acto: ahora retirar **cierra la condición
    /// vigente y retira la línea en una transacción**, así que el diálogo **pide la fecha**.
    testWidgets('pide el último día que cobra —hoy por omisión— y el motivo', (
      tester,
    ) async {
      String? cuerpo;

      final (api, _) = await cliente(
        condiciones: [vigente],
        responder: (p) {
          if (p.url.path.endsWith('/retire')) {
            cuerpo = p.cuerpo;

            return http.Response(
              jsonEncode({
                'line': {...lineas.first, 'status': 'retired'},
                'closedTerm': {...vigente, 'endsOn': '2026-01-15'},
              }),
              200,
            );
          }

          return null;
        },
      );

      await montar(tester, api: api);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retirar la línea'));
      await tester.pumpAndSettle();

      // EL DIÁLOGO DICE QUE HACE LAS DOS COSAS, que es lo que la frase vieja no podía decir.
      expect(find.textContaining('hace dos cosas a la vez'), findsOneWidget);
      expect(find.byKey(clavesDeRetiro.ultimoDia), findsOneWidget);

      await tester.enterText(
        campo(clavesDeRetiro.motivo),
        'El cliente canceló ese puesto',
      );

      await tester.tap(find.text('Retirar').last);
      await tester.pumpAndSettle();

      // Y VIAJAN LOS DOS DATOS: la fecha de hoy —por omisión— y el motivo.
      final enviado = jsonDecode(cuerpo!) as Map<String, Object?>;

      expect(enviado['endsOn'], '2026-01-15');
      expect(enviado['reason'], 'El cliente canceló ese puesto');
    });

    testWidgets('sin motivo no se puede retirar', (tester) async {
      final (api, pedidas) = await cliente(condiciones: [vigente]);
      await montar(tester, api: api);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retirar la línea'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Retirar').last);
      await tester.pumpAndSettle();

      expect(find.text('Di por qué se retira.'), findsOneWidget);

      // Y NO SE MANDÓ NADA: el diálogo sigue abierto con lo capturado.
      expect(
        pedidas.where((p) => p.url.path.endsWith('/retire')),
        isEmpty,
      );
    });

    testWidgets('una línea que NO cobra nada se retira sin fecha', (
      tester,
    ) async {
      // ⚠️ SIN CONDICIÓN VIGENTE NO HAY NADA QUE CERRAR, y mandar la fecha responde 422. El
      // diálogo no la pide y lo dice, en vez de ofrecer un campo que el servidor rechaza.
      String? cuerpo;

      final (api, _) = await cliente(
        condiciones: const [],
        responder: (p) {
          if (p.url.path.endsWith('/retire')) {
            cuerpo = p.cuerpo;

            return http.Response(
              jsonEncode({
                'line': {...lineas.first, 'status': 'retired'},
                'closedTerm': null,
              }),
              200,
            );
          }

          return null;
        },
      );

      await montar(tester, api: api);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retirar la línea'));
      await tester.pumpAndSettle();

      // LA FRASE DEL DIÁLOGO, no la de la tarjeta: las dos dicen «no cobra nada» y la de
      // abajo —«no tiene condición»— ya estaba ahí antes de abrir nada.
      expect(
        find.textContaining('retirar sólo impide ponerle'),
        findsOneWidget,
      );
      expect(find.byKey(clavesDeRetiro.ultimoDia), findsNothing);

      await tester.enterText(campo(clavesDeRetiro.motivo), 'Ya no se presta');
      await tester.tap(find.text('Retirar').last);
      await tester.pumpAndSettle();

      final enviado = jsonDecode(cuerpo!) as Map<String, Object?>;

      expect(enviado.containsKey('endsOn'), isFalse);
      expect(enviado['reason'], 'Ya no se presta');
    });

    testWidgets(
      'la tarjeta de una retirada dice HASTA CUÁNDO cobra',
      (tester) async {
        final (api, _) = await cliente(
          condiciones: [
            {...vigente, 'endsOn': '2026-01-31'},
          ],
          responder: (p) => p.url.path.endsWith('/commercial-lines')
              ? http.Response(
                  jsonEncode([
                    {...lineas.first, 'status': 'retired'},
                  ]),
                  200,
                )
              : null,
        );

        await montar(tester, api: api);

        // ⚠️ **HAY QUE ABRIR LA SECCIÓN PLEGADA**: desde el 19-nov-2026 las retiradas viven
        // en «Retiradas (N)», cerrada por omisión. La tarjeta no existe hasta abrirla, y
        // eso es lo que se quiso.
        await tester.tap(find.text('Retiradas (1)'));
        await tester.pumpAndSettle();

        expect(find.text('Retirada'), findsOneWidget);
        expect(
          find.textContaining('Retirada · cobra hasta el'),
          findsOneWidget,
        );

        // LAS DOS FRASES VIEJAS SE FUERON: la de C3 —«no admite condiciones nuevas»— y la
        // que estuvo unas horas el 19-nov —«SIGUE COBRANDO»—, que era cierta con la regla
        // anterior y es justo la confusión que el dueño quitó cambiando el acto.
        expect(
          find.text('Retirada: no admite condiciones nuevas.'),
          findsNothing,
        );
        expect(find.textContaining('pero SIGUE COBRANDO'), findsNothing);
      },
    );

    testWidgets('una retirada SIN condición vigente dice que ya no cobra', (
      tester,
    ) async {
      final (api, _) = await cliente(
        condiciones: const [],
        responder: (p) => p.url.path.endsWith('/commercial-lines')
            ? http.Response(
                jsonEncode([
                  {...lineas.first, 'status': 'retired'},
                ]),
                200,
              )
            : null,
      );

      await montar(tester, api: api);

      await tester.tap(find.text('Retiradas (1)'));
      await tester.pumpAndSettle();

      expect(find.text('Retirada · ya no cobra'), findsOneWidget);
    });

    testWidgets(
      'una retirada ANTIGUA con condición abierta lo dice, no finge que ya no cobra',
      (tester) async {
        // ⚠️ **ESTE CASO EXISTE EN DATOS REALES Y HAY QUE DECIRLO.** Las líneas que el dueño
        // retiró ANTES del 19-nov-2026 quedaron con su condición **abierta**, así que siguen
        // cobrando sin fecha. Enseñar «ya no cobra» sobre ellas sería mentir en la dirección
        // peligrosa: pensar que algo dejó de facturar cuando factura cada mes.
        final (api, _) = await cliente(
          condiciones: [
            {...vigente, 'endsOn': null},
          ],
          responder: (p) => p.url.path.endsWith('/commercial-lines')
              ? http.Response(
                  jsonEncode([
                    {...lineas.first, 'status': 'retired'},
                  ]),
                  200,
                )
              : null,
        );

        await montar(tester, api: api);

        await tester.tap(find.text('Retiradas (1)'));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('SIGUE COBRANDO: su condición no tiene fecha'),
          findsOneWidget,
        );
        expect(find.text('Retirada · ya no cobra'), findsNothing);
      },
    );
  });

  group('una línea RETIRADA que todavía cobra se puede cerrar', () {
    /// Abre el menú de la única línea, que la prueba deja retirada.
    Future<void> abrirMenuDeLaRetirada(WidgetTester tester) async {
      await tester.tap(find.text('Retiradas (1)'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
    }

    Future<(ApiClientAutenticado, List<_Pedida>)> conRetirada({
      required List<Object?> condiciones,
    }) => cliente(
      condiciones: condiciones,
      responder: (p) => p.url.path.endsWith('/commercial-lines')
          ? http.Response(
              jsonEncode([
                {...lineas.first, 'status': 'retired'},
              ]),
              200,
            )
          : null,
    );

    testWidgets('su menú ofrece «Dejar de cobrar»', (tester) async {
      // 🚫 **EL HUECO QUE EL DUEÑO ENCONTRÓ EL 19-nov-2026.** Las líneas que retiró antes de
      // que retirar cerrara la condición quedaron **retiradas y cobrando**, y su menú sólo
      // ofrecía sueldo, renombrar y reactivar: la única forma de corregirlas era
      // **reactivarlas**, o sea inventarles un estado. El servidor nunca lo impidió — era la
      // pantalla, por tener esta opción dentro del candado de «línea activa».
      final (api, _) = await conRetirada(
        condiciones: [
          {...vigente, 'endsOn': null},
        ],
      );

      await montar(tester, api: api);
      await abrirMenuDeLaRetirada(tester);

      expect(find.text('Dejar de cobrar (cerrar)'), findsOneWidget);
      expect(find.text('Reactivar la línea'), findsOneWidget);

      // ⚠️ **Y LO QUE SIGUE SIN OFRECERSE**, porque una retirada no admite condiciones
      // nuevas y el servidor contesta `linea_retirada`: ofrecerlas sería enseñar un botón
      // que responde un error.
      expect(find.text('Programar la siguiente'), findsNothing);
      expect(find.text('Poner su condición'), findsNothing);
    });

    testWidgets('y cerrarla manda la fecha y el motivo sin reactivar nada', (
      tester,
    ) async {
      String? cuerpo;
      var reactivaciones = 0;

      final (api, _) = await cliente(
        condiciones: [
          {...vigente, 'endsOn': null},
        ],
        responder: (p) {
          if (p.url.path.endsWith('/commercial-lines')) {
            return http.Response(
              jsonEncode([
                {...lineas.first, 'status': 'retired'},
              ]),
              200,
            );
          }

          if (p.url.path.endsWith('/reactivate')) reactivaciones++;

          if (p.url.path.endsWith('/terms/current/close')) {
            cuerpo = p.cuerpo;

            return http.Response(
              jsonEncode({...vigente, 'endsOn': '2026-01-31'}),
              200,
            );
          }

          return null;
        },
      );

      await montar(tester, api: api);
      await abrirMenuDeLaRetirada(tester);

      await tester.tap(find.text('Dejar de cobrar (cerrar)'));
      await tester.pumpAndSettle();

      await tester.enterText(
        campo(clavesDeCierre.motivo),
        'Se retiró sin fecha por error',
      );

      await tester.tap(find.text('Cerrar la condición'));
      await tester.pumpAndSettle();

      final enviado = jsonDecode(cuerpo!) as Map<String, Object?>;

      expect(enviado['reason'], 'Se retiró sin fecha por error');
      expect(enviado['endsOn'], isNotNull);

      // LO QUE IMPORTA DE VERDAD: se corrigió **sin reactivar** la línea.
      expect(reactivaciones, 0);
    });

    testWidgets('una retirada que YA NO cobra no lo ofrece', (tester) async {
      // La otra mitad: sin condición vigente no hay nada que cerrar, y el servidor
      // responde 404. Un botón que contesta un error no se ofrece.
      final (api, _) = await conRetirada(condiciones: const []);

      await montar(tester, api: api);
      await abrirMenuDeLaRetirada(tester);

      expect(find.text('Dejar de cobrar (cerrar)'), findsNothing);
      expect(find.text('Reactivar la línea'), findsOneWidget);
    });

    testWidgets('y una línea ACTIVA lo sigue ofreciendo', (tester) async {
      // Sin esto, el arreglo podría haberse llevado por delante lo que ya funcionaba.
      final (api, _) = await cliente(condiciones: [vigente]);

      await montar(tester, api: api);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      expect(find.text('Dejar de cobrar (cerrar)'), findsOneWidget);
    });
  });

  group('la tarjeta de una línea de CONCEPTO no inventa puesto ni turno', () {
    testWidgets('dice «Concepto · Cantidad: N» y nada de horario', (
      tester,
    ) async {
      // 🚫 **DECÍA «Puesto no encontrado · Sin modalidad de turno · Sin horario semanal
      // fijo»**, tres frases que suenan a datos que faltan sobre una línea que está
      // completa. Lo marcó el dueño el 19-nov-2026. Material o equipo se cobra sin puesto,
      // sin turno y sin horario — así lo impone la 0066 con una FK compuesta.
      final (api, _) = await cliente(
        condiciones: [
          {
            ...vigente,
            'kind': 'concepto',
            'positionId': null,
            'shiftModalityId': null,
            'shiftPeriod': null,
            'headcount': 1,
            'schedules': const <Object?>[],
          },
        ],
        responder: (p) => p.url.path.endsWith('/commercial-lines')
            ? http.Response(
                jsonEncode([
                  {
                    ...lineas.first,
                    'name': 'Cámaras y monitoreo',
                    'kind': 'concepto',
                  },
                ]),
                200,
              )
            : null,
      );

      await montar(tester, api: api);

      expect(find.text('Concepto · Cantidad: 1'), findsOneWidget);

      // LAS TRES FRASES QUE NO DEBEN SALIR, una por una: cada una era una invención
      // distinta, y afirmar sólo la de arriba dejaría pasar las otras dos.
      expect(find.textContaining('Puesto no encontrado'), findsNothing);
      expect(find.textContaining('Sin modalidad de turno'), findsNothing);
      expect(find.text('Sin horario semanal fijo.'), findsNothing);
    });
  });

  group('las líneas retiradas van plegadas al final', () {
    testWidgets('la sección nace CERRADA, con su cuenta en el título', (
      tester,
    ) async {
      // ⚠️ VENTANA ALTA: dos líneas con su tarjeta no caben en la ventana por omisión, y un
      // desbordamiento de `RenderFlex` **falla la prueba** aunque lo medido esté bien.
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      // Decisión del dueño, 19-nov-2026: una línea retirada no desaparece —sigue cobrando
      // hasta que se cierre su condición— pero no compite por la vista con las vivas.
      final (api, _) = await cliente(
        condiciones: [vigente],
        responder: (p) => p.url.path.endsWith('/commercial-lines')
            ? http.Response(
                jsonEncode([
                  lineas.first,
                  {
                    ...lineas.first,
                    'id': '0193f0aa-0000-7000-8000-0000000000f1',
                    'name': 'Rondín nocturno',
                    'status': 'retired',
                  },
                ]),
                200,
              )
            : null,
      );

      await montar(tester, api: api);

      // LA ACTIVA SE VE; LA RETIRADA, NO — pero SÍ se sabe que está y cuántas son, que es
      // la diferencia entre plegar y esconder.
      expect(find.text('Guardias intramuros'), findsOneWidget);
      expect(find.text('Retiradas (1)'), findsOneWidget);
      expect(find.text('Rondín nocturno'), findsNothing);

      await tester.tap(find.text('Retiradas (1)'));
      await tester.pumpAndSettle();

      expect(find.text('Rondín nocturno'), findsOneWidget);
    });
  });

  group('0066 · el horario de un turno rotativo se LEE derivado', () {
    /// La misma condición vigente, con la modalidad que se captura por hora de cambio: a
    /// las 08:00, turnos de 24 h, y **sin un solo bloque semanal**, que es lo que de verdad
    /// guarda un turno rotativo.
    Map<String, Object?> deHoraDeCambio() => {
      ...vigente,
      'shiftModalityId': modalidadRotativa,
      'shiftChangeMinute': 480,
      'schedules': const <Object?>[],
    };

    testWidgets('la tarjeta dice la hora, la duración y la ventana', (
      tester,
    ) async {
      // 🚫 **DECÍA «Sin horario semanal fijo» Y ERA FALSO** (prueba en pantalla del dueño,
      // 19-nov-2026). Un 24×24 **sí** tiene horario —entra a una hora y dura lo que dura—;
      // lo que no tiene es rejilla, porque su ciclo no cabe en siete días. El dato estaba
      // guardado y la frase lo negaba.
      final (api, _) = await cliente(condiciones: [deHoraDeCambio()]);
      await montar(tester, api: api);

      expect(
        find.textContaining('Cambio de turno 08:00'),
        findsOneWidget,
      );
      expect(find.textContaining('turnos de 24 h'), findsOneWidget);
      expect(find.textContaining('08:00 a 08:00'), findsOneWidget);
      expect(find.text('Sin horario semanal fijo.'), findsNothing);
    });

    testWidgets('y la frase de la rejilla vacía sigue saliendo donde SÍ aplica', (
      tester,
    ) async {
      // ⚠️ LA OTRA MITAD, y hace falta: «sin rejilla» sigue siendo cierto y significativo
      // en una modalidad que se captura por rejilla —disponibilidad, bolsa de horas—. Sin
      // esta prueba, el arreglo podría haber borrado la frase en lugar de acotarla.
      final (api, _) = await cliente(
        condiciones: [
          {...vigente, 'schedules': const <Object?>[]},
        ],
      );

      await montar(tester, api: api);

      expect(find.text('Sin horario semanal fijo.'), findsOneWidget);
      expect(find.textContaining('Cambio de turno'), findsNothing);
    });
  });

  group('el aviso de cupo rebasado', () {
    testWidgets('sale DESPUÉS del éxito y no como un error', (tester) async {
      // ⚠️ SE PRUEBA SOBRE «CORREGIR LA VIGENTE» y no sobre un alta, a propósito: el
      // formulario llega RELLENADO con la condición que existe, así que la prueba mide lo
      // que importa —qué hace la pantalla con el aviso— y no la mecánica de rellenar siete
      // campos. Bajar las plazas de 3 a 1 es además el caso real del aviso.
      final (api, _) = await cliente(
        condiciones: [vigente],
        responder: (p) {
          if (p.metodo == 'PATCH') {
            return http.Response(
              jsonEncode({
                ...vigente,
                'headcount': 1,
                'version': 1,
                'warning': {
                  'code': 'cupo_rebasado',
                  'assigned': 3,
                  'headcount': 1,
                },
              }),
              200,
            );
          }

          return null;
        },
      );

      await montar(tester, api: api);
      await abrirCorreccion(tester);

      await tester.enterText(campo(clavesDeCondicion.plazas), '1');
      await tester.enterText(campo(clavesDeCondicion.motivo), 'Bajó la cobertura');

      await tester.tap(find.byKey(clavesDeCondicion.guardar));
      await tester.pumpAndSettle();

      // 🚫 ES UN AVISO Y LO DICE: «se guardó, con un aviso». La condición existe.
      expect(find.text('Se guardó, con un aviso'), findsOneWidget);
      expect(
        find.textContaining(
          'Hay 3 personas asignadas y la condición declara 1 plaza',
        ),
        findsOneWidget,
      );

      // Y dice quién mueve a la gente: una persona, no el sistema.
      expect(
        find.textContaining('el sistema no desasigna a nadie'),
        findsOneWidget,
      );
    });
  });

  group('el 409 del candado de versión', () {
    testWidgets('enseña el precio que el servidor tiene AHORA', (tester) async {
      final (api, _) = await cliente(
        condiciones: [vigente],
        responder: (p) {
          if (p.metodo == 'PATCH') {
            return http.Response(
              jsonEncode({
                'code': 'condicion_desactualizada',
                'message': 'Alguien más cambió esa condición desde que la cargaste.',
                // ⚠️ LA MITAD ÚTIL DEL 409: con esto la pantalla puede decir qué hay
                // ahora en lugar de «recarga y vuelve a escribir lo tuyo».
                'current': {
                  ...vigente,
                  'unitPriceMinor': 1700000,
                  // EL IMPORTE TAMBIÉN CAMBIA, porque lo deriva el servidor: 17 000 × 3.
                  'monthlyAmountMinor': 5100000,
                  'version': 1,
                },
              }),
              409,
            );
          }

          return null;
        },
      );

      await montar(tester, api: api);
      await abrirCorreccion(tester);

      await tester.enterText(campo(clavesDeCondicion.precio), '16000');
      await tester.enterText(campo(clavesDeCondicion.motivo), 'Se capturó mal');

      await tester.tap(find.byKey(clavesDeCondicion.guardar));
      await tester.pumpAndSettle();

      expect(find.text('Alguien más cambió esta condición'), findsOneWidget);

      // LO QUE COBRA AHORA, lo que dice el dato: 17 000 × 3 = 51 000.00, no lo que se
      // escribió. ⚠️ **Y se dice el IMPORTE, no la multiplicación** (0066): con dos modos
      // de cotización, el único número que significa lo mismo en los dos es el total.
      expect(
        find.textContaining(r'$51,000.00 MXN al mes'),
        findsOneWidget,
      );

      // Y se dice que lo escrito no se perdió, que es el punto entero.
      expect(
        find.textContaining('lo que escribiste sigue aquí'),
        findsOneWidget,
      );
    });

    testWidgets('la corrección manda expectedVersion, no una inventada', (
      tester,
    ) async {
      String? cuerpo;

      final (api, _) = await cliente(
        condiciones: [vigente],
        responder: (p) {
          if (p.metodo == 'PATCH') {
            cuerpo = p.cuerpo;

            return http.Response(jsonEncode(vigente), 200);
          }

          return null;
        },
      );

      await montar(tester, api: api);
      await abrirCorreccion(tester);

      await tester.enterText(campo(clavesDeCondicion.motivo), 'Se capturó mal');

      await tester.tap(find.byKey(clavesDeCondicion.guardar));
      await tester.pumpAndSettle();

      final enviado = jsonDecode(cuerpo!) as Map<String, Object?>;

      // ⚠️ LA VERSIÓN ES LA QUE SE LEYÓ, no un valor «para que pase»: eso borraría el
      // trabajo del otro, que es lo que el contador existe para impedir.
      expect(enviado['expectedVersion'], 0);
      expect(enviado['reason'], 'Se capturó mal');
    });
  });

  group('corregir la vigente sólo se ofrece si es la ÚNICA', () {
    testWidgets('con una histórica detrás, la opción no está', (tester) async {
      final historica = {
        ...vigente,
        'id': '0193f0aa-0000-7000-8000-00000000000c',
        'temporality': 'historical',
        'startsOn': '2024-01-01',
        'endsOn': '2025-05-31',
      };

      final (api, _) = await cliente(condiciones: [vigente, historica]);
      await montar(tester, api: api);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      // 🚫 EL SERVIDOR RESPONDE 409 `condicion_con_historia`, así que la opción no se
      // ofrece: un botón que siempre falla es peor que su ausencia. Lo que sí se ofrece
      // es programar la siguiente, que es la salida.
      expect(find.text('Corregir la vigente'), findsNothing);
      expect(find.text('Programar la siguiente'), findsOneWidget);
    });
  });

  group('el periodo del turno lo decide la modalidad', () {
    testWidgets('12 × 12 pide Diurno/Nocturno y 24 × 24 no', (tester) async {
      final (api, _) = await cliente(condiciones: [vigente]);
      await montar(tester, api: api);
      await abrirCorreccion(tester);

      // La condición llega con 24 × 24, que ROTA y cubre el día completo: el periodo no
      // significaría nada, así que su desplegable no existe.
      expect(find.byKey(clavesDeCondicion.periodo), findsNothing);

      // Y su explicación, con la cuenta de personas, se lee al elegir el turno. ⚠️ Es la
      // mitad del trabajo de C3 en esta pantalla: ese número es el que de verdad se usa al
      // cotizar, y hasta hoy vivía en la cabeza de quien cotiza.
      expect(
        find.textContaining('Para cubrir 24/7 se necesitan 2 personas'),
        findsOneWidget,
      );

      await abrirDesplegable(tester, clavesDeCondicion.modalidad);
      await tester.tap(find.text('12 × 12 corrido').last);
      await tester.pumpAndSettle();

      // 12 × 12 NO rota: la plaza es de día o de noche, y se cobra distinto.
      expect(find.byKey(clavesDeCondicion.periodo), findsOneWidget);
      expect(
        find.textContaining('la plaza es de día o de noche'),
        findsOneWidget,
      );
    });

    testWidgets(
      'con periodo, la hora es la del turno de DÍA y la ayuda enseña las dos plazas',
      (tester) async {
        // 🚫 **ESTO SE CONTRADECÍA, y el dueño lo vio el 19-nov-2026:** capturó un 12×12
        // Diurno con hora 20:00 y la ayuda dijo «esta plaza va de 20:00 a 08:00» —noche en
        // una plaza de día—. No era un error de cálculo: el campo se llamaba «Hora de
        // cambio de turno» y **no decía de qué plaza era la hora**, y en un 12×12 el cambio
        // ocurre dos veces al día, así que el nombre admitía las dos lecturas.
        final (api, _) = await cliente(
          condiciones: [
            {
              ...vigente,
              'shiftModalityId': modalidad12Rotativa,
              'shiftPeriod': 'diurno',
              'shiftChangeMinute': 480,
              'schedules': const <Object?>[],
            },
          ],
        );

        await montar(tester, api: api);
        await abrirCorreccion(tester);

        // EL NOMBRE DICE DE QUÉ PLAZA ES LA HORA, y el viejo no está.
        expect(find.text('Hora de entrada del turno de día'), findsOneWidget);
        expect(find.text('Hora de cambio de turno'), findsNothing);

        // Y LA AYUDA ENSEÑA LAS DOS PLAZAS, más cuál es la de esta condición: con 08:00 de
        // entrada, día 08:00–20:00 y noche 20:00–08:00.
        expect(find.textContaining('Día 08:00 a 20:00'), findsOneWidget);
        expect(find.textContaining('Noche 20:00 a 08:00'), findsOneWidget);
        expect(
          find.textContaining('Esta plaza es la de DÍA'),
          findsOneWidget,
        );
      },
    );

    testWidgets('sin periodo no se enseñan dos plazas, porque no hay dos', (
      tester,
    ) async {
      // LA OTRA MITAD: un 24×24 tiene una sola plaza, y hablarle de «la de noche» sería
      // inventarle una. El nombre del campo tampoco dice «de día».
      final (api, _) = await cliente(
        condiciones: [
          {
            ...vigente,
            'shiftModalityId': modalidadRotativa,
            'shiftChangeMinute': 480,
            'schedules': const <Object?>[],
          },
        ],
      );

      await montar(tester, api: api);
      await abrirCorreccion(tester);

      expect(find.text('Hora de entrada del turno'), findsOneWidget);
      expect(find.textContaining('Noche'), findsNothing);
      expect(
        find.textContaining('el turno va de 08:00 a 08:00'),
        findsOneWidget,
      );
    });

    testWidgets('sin modalidad no hay periodo que preguntar (segundo caso)', (
      tester,
    ) async {
      final (api, _) = await cliente(
        condiciones: [
          {...vigente, 'shiftModalityId': null},
        ],
      );

      await montar(tester, api: api);
      await abrirCorreccion(tester);

      expect(find.byKey(clavesDeCondicion.periodo), findsNothing);
    });
  });

  // =========================================================================
  // El número de personas: SUGERENCIA, nunca regla (14-nov-2026)
  // =========================================================================

  group('🚫 el turno NO toca la cantidad que se cobra', () {
    /// Lo que el campo de la cantidad tiene ahora mismo.
    String personas(WidgetTester tester) =>
        tester
            .widget<TextFormField>(
              find.descendant(
                of: find.byKey(clavesDeCondicion.plazas),
                matching: find.byType(TextFormField),
              ),
            )
            .controller
            ?.text ??
        '';

    Future<void> elegirTurno(WidgetTester tester, String nombre) async {
      await abrirDesplegable(tester, clavesDeCondicion.modalidad);
      await tester.tap(find.text(nombre).last);
      await tester.pumpAndSettle();
    }

    testWidgets('🚫 CAMBIAR DE TURNO NO MUEVE LA CANTIDAD, ni una vez ni tres', (
      tester,
    ) async {
      final (api, _) = await cliente(condiciones: [vigente]);
      await montar(tester, api: api);
      await abrirCorreccion(tester);

      // La condición llega con 3 de cantidad y el turno 24 × 24.
      expect(personas(tester), '3');

      // ⚠️ **ESTO CAMBIÓ EL 14-nov-2026.** Durante unas horas elegir el turno PRELLENABA
      // este campo con las personas que el rol necesita para cubrir 24/7, y el dueño lo
      // quitó el mismo día: la cantidad que se cobra es **dinero** —el importe mensual es
      // cantidad × precio— y las personas necesarias son una referencia de operación.
      await elegirTurno(tester, '12 × 36');

      expect(personas(tester), '3');

      await elegirTurno(tester, '12 × 12 corrido');

      expect(personas(tester), '3');

      await elegirTurno(tester, 'Rol propio');

      expect(personas(tester), '3');
    });

    testWidgets('el campo se llama por lo que es, y dice que multiplica', (
      tester,
    ) async {
      final (api, _) = await cliente(condiciones: [vigente]);
      await montar(tester, api: api);
      await abrirCorreccion(tester);

      // 🚫 **EL NOMBRE DEL DUEÑO, 19-nov-2026: «Número de elementos».** Decía «Cantidad
      // que se cobra» y en su prueba en pantalla **escribió 36000 ahí creyendo que pedía
      // dinero** — «cantidad» en español es cuánto dinero tanto como cuántas cosas, y
      // junto a un precio gana el dinero. «Elementos» es además el término con el que la
      // tarjeta ya lo leía.
      expect(find.text('Número de elementos'), findsOneWidget);
      expect(find.text('Cantidad que se cobra'), findsNothing);

      // ⚠️ **Y LA AYUDA LA DICE EL MODO DE COTIZACIÓN** (0066): esta condición se cobra
      // por persona, así que la cantidad multiplica y se dice. Con un total mensual la
      // misma frase sería falsa, y ahí la ayuda dice lo contrario.
      expect(
        find.textContaining('Cuántas personas cubre esta línea'),
        findsOneWidget,
      );
      expect(find.textContaining('multiplica el precio'), findsOneWidget);
    });

    testWidgets('las personas necesarias se LEEN junto al turno, y nada más', (
      tester,
    ) async {
      final (api, _) = await cliente(condiciones: [vigente]);
      await montar(tester, api: api);
      await abrirCorreccion(tester);

      // La explicación del turno elegido, con su cuenta de personas dentro. Es **texto
      // informativo**: no se guarda, no prellena y no entra en ningún cálculo.
      expect(
        find.textContaining('Para cubrir 24/7 se necesitan 2 personas'),
        findsOneWidget,
      );

      await elegirTurno(tester, '12 × 36');

      expect(
        find.textContaining('Para cubrir 24/7 se necesitan 4 personas'),
        findsOneWidget,
      );

      // Y la cantidad que se cobra sigue siendo la capturada: son dos números distintos y
      // la pantalla los enseña como tales.
      expect(personas(tester), '3');
    });
  });

  // =========================================================================
  // Renovar / extender, en tres pasos
  // =========================================================================

  group('renovar / extender pregunta el precio', () {
    /// La otra línea del servicio, para medir que la renovación las cubre TODAS.
    const otra = '0193f0aa-0000-7000-8000-00000000000d';

    /// Dos líneas que cobran: 15 000 y 20 000.
    ///
    /// ⚠️ **Las dos renovables por omisión**, y eso cambió el 14-nov-2026: la renovación
    /// manda el precio de todas las líneas que cobran, así que el caso normal es «todas
    /// entran». Con [conProgramada] la segunda tiene una condición programada, que **bloquea
    /// la renovación entera** y tiene su propia prueba.
    List<RenglonDeRenovacion> renglonesDePrueba({bool conProgramada = false}) => [
      RenglonDeRenovacion(
        linea: LineaComercial.deJson(lineas.first as Map<String, dynamic>),
        vigente: CondicionComercial.deJson(vigente),
        tieneProgramada: false,
      ),
      RenglonDeRenovacion(
        linea: LineaComercial.deJson({
          ...lineas.first as Map<String, dynamic>,
          'id': otra,
          'name': 'Supervisor',
        }),
        vigente: CondicionComercial.deJson({
          ...vigente,
          'id': '0193f0aa-0000-7000-8000-00000000000e',
          'commercialLineId': otra,
          'unitPriceMinor': 2000000,
          'headcount': 1,
        }),
        tieneProgramada: conProgramada,
      ),
    ];

    /// ⚠️ **UNA VENTANA ALTA, y hace falta desde que cada línea lleva su selector:** el menú
    /// de un desplegable se dibuja **sobre** su botón, así que en una ventana de 600 px el del
    /// segundo renglón cae fuera y el toque **no llega y no se queja**. Es la misma razón por
    /// la que `montar` la agranda en las pruebas del expediente.
    void ventanaAlta(WidgetTester tester) {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    Future<PlanDeRenovacion?> abrir(
      WidgetTester tester, {
      bool puedeTocarPrecios = true,
      bool conProgramada = false,
    }) async {
      PlanDeRenovacion? plan;

      ventanaAlta(tester);

      await tester.pumpWidget(
        MaterialApp(
          theme: MarcaSeventra.tema(),
          home: Scaffold(
            body: Builder(
              builder: (contexto) => TextButton(
                onPressed: () async {
                  plan = await mostrarRenovacion(
                    contexto,
                    nombreDelServicio: 'Sportium Satélite',
                    terminoActual: const DiaDeNegocio(2026, 3, 31),
                    hoy: const DiaDeNegocio(2026, 1, 15),
                    renglones: renglonesDePrueba(conProgramada: conProgramada),
                    puedeTocarPrecios: puedeTocarPrecios,
                    guardia: GuardiaDeSalida(),
                  );
                },
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      return plan;
    }

    testWidgets('el primer paso enseña hasta cuándo termina hoy', (
      tester,
    ) async {
      await abrir(tester);

      expect(find.text('Renovar / extender · hasta cuándo'), findsOneWidget);
      expect(
        find.textContaining('Sportium Satélite termina el'),
        findsOneWidget,
      );
    });

    /// Elige una de las tres salidas de una línea en el paso de los precios.
    Future<void> decidir(
      WidgetTester tester,
      String lineaId,
      DecisionDeRenovacion cual,
    ) async {
      await abrirDesplegable(tester, Key('renovacion-decision-$lineaId'));
      await tester.tap(find.text(cual.enPantalla).last);
      await tester.pumpAndSettle();
    }

    testWidgets('el segundo paso ofrece TRES salidas y por omisión no cambia nada', (
      tester,
    ) async {
      await abrir(tester);

      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();

      expect(find.text('Renovar / extender · los precios'), findsOneWidget);

      // LAS DOS LÍNEAS TIENEN SU SELECTOR: la renovación reprograma todas las que cobran.
      expect(find.byKey(const Key('renovacion-decision-$linea')), findsOneWidget);
      expect(find.byKey(const Key('renovacion-decision-$otra')), findsOneWidget);

      // 🚫 Y POR OMISIÓN NO HAY CAMPO DE PRECIO: la salida de por omisión es «mismo
      // precio», que es la que conserva lo pactado.
      expect(find.byKey(const Key('renovacion-precio-$linea')), findsNothing);

      // Al pedir precio nuevo, el campo aparece CON EL PRECIO QUE YA HAY. 🚫 Ningún aumento
      // precargado: cada cliente sube distinto, y que RISEG las suba en enero es una
      // costumbre de RISEG, no una regla del producto.
      await decidir(tester, linea, DecisionDeRenovacion.precioNuevo);

      final campoDelPrecio = tester.widget<TextFormField>(
        find.descendant(
          of: find.byKey(const Key('renovacion-precio-$linea')),
          matching: find.byType(TextFormField),
        ),
      );

      expect(campoDelPrecio.controller?.text, '15000');
    });

    testWidgets('🚫 DAR DE BAJA UNA LÍNEA se dice en el resumen y viaja en el plan', (
      tester,
    ) async {
      PlanDeRenovacion? plan;

      ventanaAlta(tester);

      await tester.pumpWidget(
        MaterialApp(
          theme: MarcaSeventra.tema(),
          home: Scaffold(
            body: Builder(
              builder: (contexto) => TextButton(
                onPressed: () async {
                  plan = await mostrarRenovacion(
                    contexto,
                    nombreDelServicio: 'Sportium Satélite',
                    terminoActual: const DiaDeNegocio(2026, 3, 31),
                    hoy: const DiaDeNegocio(2026, 1, 15),
                    renglones: renglonesDePrueba(),
                    puedeTocarPrecios: true,
                    guardia: GuardiaDeSalida(),
                  );
                },
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();

      // El supervisor se va; los guardias siguen igual.
      await decidir(tester, otra, DecisionDeRenovacion.darDeBaja);

      // SE COMPRUEBA QUE LA ELECCIÓN ENTRÓ, y no es ceremonia: un toque sobre un menú que
      // quedó fuera de la ventana **no hace nada y no falla**, así que sin esto el fallo
      // aparecería dos pasos después, en el resumen, leyéndose como un texto equivocado.
      expect(
        tester
            .widget<DropdownButtonFormField<DecisionDeRenovacion>>(
              find.descendant(
                of: find.byKey(const Key('renovacion-decision-$otra')),
                matching: find.byType(DropdownButtonFormField<DecisionDeRenovacion>),
              ),
            )
            .initialValue,
        DecisionDeRenovacion.darDeBaja,
      );

      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();

      // ⚠️ EL RESUMEN LO DICE CON SUS DOS MITADES: el día en que deja de cobrarse y el
      // último que sí se cobra. «Se da de baja el 1 de abril» a secas se lee de las dos
      // maneras, y una de las dos es un mes de más.
      expect(
        find.textContaining('Supervisor: se da de baja el 1/abr/2026'),
        findsOneWidget,
      );
      expect(find.textContaining('se cobra hasta el 31/mar/2026'), findsOneWidget);
      expect(find.textContaining('queda retirada'), findsOneWidget);

      await tester.tap(find.byKey(const Key('renovacion-confirmar')));
      await tester.pumpAndSettle();

      // Y EN EL PLAN: la baja sin precio, la otra con el suyo.
      final baja = plan!.bajas.single;

      expect(baja.linea.id, otra);
      expect(baja.precioNuevoMenores, isNull);
      expect(baja.seDaDeBaja, isTrue);

      final sigue = plan!.precios.singleWhere((p) => p.linea.id == linea);

      expect(sigue.seDaDeBaja, isFalse);
      expect(sigue.precioNuevoMenores, 1500000);
      expect(plan!.cambios, isEmpty);
    });

    testWidgets('el resumen dice qué cambia y qué queda SIN CAMBIO', (
      tester,
    ) async {
      await abrir(tester);

      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();

      await decidir(tester, linea, DecisionDeRenovacion.precioNuevo);

      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('renovacion-precio-$linea')),
          matching: find.byType(TextFormField),
        ),
        '16500',
      );

      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();

      expect(find.text('Renovar / extender · qué va a pasar'), findsOneWidget);

      // Lo que cambia, con el antes y el después.
      expect(
        find.text(r'Guardias intramuros: $15,000.00 MXN → $16,500.00 MXN'),
        findsOneWidget,
      );

      // ⚠️ Y LO QUE NO CAMBIA SE ENUMERA, no se calla: que una línea no aparezca es
      // indistinguible de que nadie la mirara.
      expect(
        find.textContaining('Supervisor: sin cambio'),
        findsOneWidget,
      );

      // 🚫 Y SE DICE QUE LAS DOS VUELVEN A EMPEZAR, no sólo la que sube de precio: «sin
      // cambio» es otra condición con el mismo importe, no «no la toques».
      expect(
        find.textContaining('2 líneas siguen en el periodo nuevo'),
        findsOneWidget,
      );

      // Y se dice lo que esto NO hace, en lugar de prometerlo.
      expect(
        find.textContaining('No registra que un contrato renueve a otro'),
        findsOneWidget,
      );
    });

    testWidgets('renovar sin cambiar ningún precio lo dice en voz alta', (
      tester,
    ) async {
      await abrir(tester);

      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();

      // ⚠️ ES LEGÍTIMO —extender— y tiene que distinguirse de haberse olvidado de los
      // precios, que es justo el silencio que CP-23 vino a romper. 🚫 Y NO dice «no se
      // toca nada»: las dos líneas estrenan condición, con el mismo importe.
      expect(
        find.textContaining('con el mismo precio que tienen hoy'),
        findsOneWidget,
      );
    });

    testWidgets('🚫 SIN EL PERMISO DE PRECIOS NO SE PUEDE RENOVAR, y se dice por qué', (
      tester,
    ) async {
      await abrir(tester, puedeTocarPrecios: false);

      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();

      // 🚫 **ESTO CAMBIÓ EL 14-nov-2026.** Antes decía «se facturará al precio anterior» y
      // dejaba guardar, y era falso: el periodo nuevo NO hereda los precios —la condición
      // de cada línea muere con el periodo que se cierra—, así que renovar sin
      // reprogramarlos dejaba el servicio operando sin cobrar nada.
      expect(
        find.textContaining('El periodo nuevo NO hereda los precios'),
        findsOneWidget,
      );

      expect(
        find.textContaining('usa «Programar el término»'),
        findsOneWidget,
      );

      expect(find.byKey(const Key('renovacion-precio-$linea')), findsNothing);

      // Y EL BOTÓN SE VE Y NO SE PUEDE PULSAR: escondido se leería como «está roto».
      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();

      final guardar = tester.widget<FilledButton>(
        find.byKey(const Key('renovacion-confirmar')),
      );

      expect(guardar.onPressed, isNull);
    });

    testWidgets('🚫 UNA CONDICIÓN PROGRAMADA BLOQUEA LA RENOVACIÓN ENTERA', (
      tester,
    ) async {
      await abrir(tester, conProgramada: true);

      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();

      // ⚠️ NO ES «esa línea se queda fuera»: la renovación cubre todas las que cobran y el
      // servidor admite una sola condición futura por línea, así que mientras una tenga la
      // suya no hay renovación posible. Antes esta pantalla decía «cancélala antes de
      // renovar SU precio», como si las demás pudieran ir sin ella.
      expect(
        find.textContaining('No se puede renovar mientras alguna línea tenga'),
        findsOneWidget,
      );

      // Y nombra la que estorba, porque «alguna» no se puede cancelar.
      expect(find.textContaining('Supervisor'), findsOneWidget);

      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();

      final guardar = tester.widget<FilledButton>(
        find.byKey(const Key('renovacion-confirmar')),
      );

      expect(guardar.onPressed, isNull);
    });

    testWidgets('el plan que devuelve lleva TODAS las líneas que cobran', (
      tester,
    ) async {
      PlanDeRenovacion? plan;

      ventanaAlta(tester);

      await tester.pumpWidget(
        MaterialApp(
          theme: MarcaSeventra.tema(),
          home: Scaffold(
            body: Builder(
              builder: (contexto) => TextButton(
                onPressed: () async {
                  plan = await mostrarRenovacion(
                    contexto,
                    nombreDelServicio: 'Sportium Satélite',
                    terminoActual: const DiaDeNegocio(2026, 3, 31),
                    hoy: const DiaDeNegocio(2026, 1, 15),
                    renglones: renglonesDePrueba(),
                    puedeTocarPrecios: true,
                    guardia: GuardiaDeSalida(),
                  );
                },
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();

      await decidir(tester, linea, DecisionDeRenovacion.precioNuevo);

      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('renovacion-precio-$linea')),
          matching: find.byType(TextFormField),
        ),
        '16500',
      );

      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('renovacion-confirmar')));
      await tester.pumpAndSettle();

      expect(plan, isNotNull);

      // 🚫 **LAS DOS LÍNEAS VIAJAN**, no sólo la que cambió: la condición vigente de cada
      // una termina con el periodo que se cierra, así que la que se quedara fuera dejaría
      // de cobrar. El servidor rechaza la renovación incompleta.
      expect(plan!.precios.length, 2);
      expect(
        plan!.precios.map((p) => p.linea.id).toSet(),
        {linea, otra},
      );

      // La que no se tocó viaja con el importe que ya tenía.
      final igual = plan!.precios.firstWhere((p) => p.linea.id == otra);

      expect(igual.precioNuevoMenores, 2000000);
      expect(igual.cambia, isFalse);

      // Y UN SOLO CAMBIO de importe, que es lo que el resumen enumera.
      final cambio = plan!.cambios.single;

      expect(cambio.linea.id, linea);
      expect(cambio.precioNuevoMenores, 1650000);

      // LA VERSIÓN VIAJA CON CADA PRECIO: sin ella el servidor responde 400, porque
      // renovar a ciegas pisaría un precio que alguien pudo mover mientras se decidía.
      expect(cambio.vigente.version, CondicionComercial.deJson(vigente).version);

      // Y LOS PRECIOS EMPIEZAN EL DÍA SIGUIENTE AL TÉRMINO DE HOY, que es la frontera
      // natural de una renovación: el 31 de marzo termina, el 1 de abril empieza lo nuevo.
      expect(plan!.desdeCuandoLosPrecios.enTexto, '2026-04-01');
      expect(plan!.quitarElTermino, isFalse);
    });
  });

  // =========================================================================
  // 0066 · el formulario único, el tipo de línea y cómo se cotiza
  // =========================================================================
  //
  // Todo este grupo sale de la PRUEBA EN PANTALLA DEL DUEÑO del 18-nov-2026 y de la tabla
  // de paridad con RISEG ONE que pidió a continuación. Lo que afirma, en una línea cada uno:
  //
  //  · el alta es **un solo formulario** y **una sola petición**, y la tarjeta nace completa;
  //  · la **modalidad es obligatoria**, y si el catálogo está vacío se arregla ahí mismo;
  //  · un **turno rotativo** pide una hora y **no** la rejilla semanal;
  //  · se puede cotizar **por persona o con un total mensual**, y el total se enseña grande;
  //  · una línea puede ser de **concepto**: sin puesto, sin turno y sin horario;
  //  · **50 personas** piden confirmación, con el total escrito.

  group('0066 · el alta es un solo formulario', () {
    /// ⚠️ **UNA VENTANA ALTA, y aquí hace más falta que en ningún sitio:** el formulario
    /// único lleva **quince campos**, así que en una ventana de 600 px el botón de guardar
    /// y la mitad de los campos caen fuera — y un toque sobre algo invisible **no llega y
    /// no se queja**.
    void ventanaAlta(WidgetTester tester) {
      tester.view.physicalSize = const Size(1600, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    /// Abre «Nueva línea», que desde la 0066 es el formulario completo.
    Future<void> abrirAlta(WidgetTester tester) async {
      ventanaAlta(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Nueva línea').first);
      await tester.pumpAndSettle();
    }


    /// Elige una fecha en el campo que lleva esa llave, por el selector real.
    ///
    /// ⚠️ **El alta nace con las fechas VACÍAS a propósito** —es lo que hace RISEG ONE, y
    /// por lo mismo: la fecha de una vigencia siempre se elige explícitamente—, así que
    /// toda alta pasa por aquí.
    Future<void> elegirDia(WidgetTester tester, Key llave, String dia) async {
      await tester.tap(
        find
            .descendant(of: find.byKey(llave), matching: find.byType(TextField))
            .first,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(dia).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    }

    /// Llena lo mínimo de una línea de personal con la modalidad semanal por omisión.
    Future<void> llenarLoMinimo(
      WidgetTester tester, {
      String nombre = 'Supervisor',
      String cantidad = '2',
      String precio = '18000',
    }) async {
      await elegirDia(tester, clavesDeCondicion.inicio, '15');
      await tester.enterText(campo(clavesDeCondicion.nombre), nombre);
      await tester.enterText(campo(clavesDeCondicion.plazas), cantidad);
      await tester.enterText(campo(clavesDeCondicion.precio), precio);

      await abrirDesplegable(tester, clavesDeCondicion.puesto);
      await tester.tap(find.text('Guardia').last);
      await tester.pumpAndSettle();

      await abrirDesplegable(tester, clavesDeCondicion.modalidad);
      await tester.tap(find.text('Rol propio').last);
      await tester.pumpAndSettle();
    }

    testWidgets('pide el nombre y el tipo, y NO existe «Sin modalidad»', (
      tester,
    ) async {
      final (api, _) = await cliente(condiciones: [vigente]);
      await montar(tester, api: api);
      await abrirAlta(tester);

      expect(find.text('Nueva línea comercial'), findsOneWidget);
      expect(find.text('Nombre de la línea'), findsOneWidget);
      expect(find.text('Tipo de línea'), findsOneWidget);

      // 🚫 LA MODALIDAD YA NO ES OPCIONAL, que es la deriva que la paridad encontró.
      expect(find.text('Modalidad de turno (opcional)'), findsNothing);
      expect(find.text('Modalidad de turno'), findsOneWidget);

      await abrirDesplegable(tester, clavesDeCondicion.modalidad);
      expect(find.text('Sin modalidad'), findsNothing);
    });

    testWidgets('la línea y su primera condición van en UNA petición', (
      tester,
    ) async {
      final (api, pedidas) = await cliente(
        condiciones: [vigente],
        responder: (p) {
          if (p.metodo == 'POST' && p.url.path.endsWith('/commercial-lines')) {
            return http.Response(
              jsonEncode({
                'line': {
                  'id': '0193f0aa-0000-7000-8000-0000000000f1',
                  'serviceId': servicio,
                  'name': 'Supervisor',
                  'kind': 'personal',
                  'status': 'active',
                  'updatedAt': '2026-01-10T18:00:00Z',
                },
                'term': {
                  ...vigente,
                  'id': '0193f0aa-0000-7000-8000-0000000000f2',
                  'commercialLineId': '0193f0aa-0000-7000-8000-0000000000f1',
                  'headcount': 2,
                  'unitPriceMinor': 1800000,
                  'monthlyAmountMinor': 3600000,
                },
              }),
              201,
            );
          }

          return null;
        },
      );

      await montar(tester, api: api);
      await abrirAlta(tester);
      await llenarLoMinimo(tester);

      await tester.tap(find.byKey(clavesDeCondicion.guardar));
      await tester.pumpAndSettle();

      final altas = pedidas
          .where((p) => p.metodo == 'POST' && p.url.path.endsWith('/commercial-lines'))
          .toList();

      // UNA SOLA, y con la condición dentro: antes eran dos peticiones y entre las dos
      // quedaba una línea que no cobraba nada.
      expect(altas, hasLength(1));

      final cuerpo = jsonDecode(altas.single.cuerpo) as Map<String, dynamic>;

      expect(cuerpo['name'], 'Supervisor');
      expect(cuerpo['kind'], 'personal');

      final condicion = cuerpo['firstTerm'] as Map<String, dynamic>;

      expect(condicion['headcount'], 2);
      expect(condicion['unitPriceMinor'], 1800000);
      expect(condicion['pricingMode'], 'por_persona');
      expect(condicion['monthlyTotalMinor'], isNull);

      // 🚫 **Y NO SE PIDE EL HISTORIAL DE LA LÍNEA NUEVA**: la respuesta ya trajo su
      // condición, así que la tarjeta nace completa. Era el defecto que el dueño vio —
      // «Leyendo sus condiciones…» para siempre— porque nadie la cargaba nunca.
      expect(find.text('Leyendo sus condiciones…'), findsNothing);
    });

    testWidgets('con el catálogo VACÍO se ofrece agregar las recomendadas', (
      tester,
    ) async {
      var agregadas = false;

      final (api, pedidas) = await cliente(
        condiciones: [vigente],
        responder: (p) {
          if (p.url.path.endsWith('/shift-modalities/recommended')) {
            agregadas = true;

            return http.Response(jsonEncode(modalidades), 200);
          }

          if (p.url.path.endsWith('/shift-modalities')) {
            // VACÍO: es la empresa del ensayo el 18-nov-2026.
            return http.Response(jsonEncode(agregadas ? modalidades : const []), 200);
          }

          return null;
        },
      );

      await montar(tester, api: api);
      await abrirAlta(tester);

      expect(
        find.text('Agregar las modalidades recomendadas'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(clavesDeCondicion.agregarModalidades));
      await tester.pumpAndSettle();

      expect(
        pedidas.any((p) => p.url.path.endsWith('/shift-modalities/recommended')),
        isTrue,
      );

      // Y EL DESPLEGABLE QUEDA LISTO SIN CERRAR EL FORMULARIO, que es el punto.
      expect(find.text('Agregar las modalidades recomendadas'), findsNothing);

      await abrirDesplegable(tester, clavesDeCondicion.modalidad);
      expect(find.text('Rol propio').last, findsOneWidget);
    });

    testWidgets('un turno ROTATIVO pide la hora de cambio y NO la rejilla', (
      tester,
    ) async {
      final (api, _) = await cliente(condiciones: [vigente]);
      await montar(tester, api: api);
      await abrirAlta(tester);

      // Con la modalidad semanal por omisión, la rejilla está.
      await abrirDesplegable(tester, clavesDeCondicion.modalidad);
      await tester.tap(find.text('Rol propio').last);
      await tester.pumpAndSettle();

      expect(find.text('Horario semanal'), findsOneWidget);
      expect(find.byKey(clavesDeCondicion.horaDeCambio), findsNothing);

      // Y con una que rota, se cambian las dos cosas: aparece la hora y desaparece la
      // rejilla. 🚫 **No es una preferencia de pantalla**: un ciclo de 24×24 vuelve a la
      // misma hora cada 48 horas, así que no cabe en una semana.
      await abrirDesplegable(tester, clavesDeCondicion.modalidad);
      await tester.tap(find.text('24 × 24').last);
      await tester.pumpAndSettle();

      expect(find.byKey(clavesDeCondicion.horaDeCambio), findsOneWidget);
      expect(find.text('Horario semanal'), findsNothing);
    });

    testWidgets('el TOTAL MENSUAL se enseña grande mientras se captura', (
      tester,
    ) async {
      final (api, _) = await cliente(condiciones: [vigente]);
      await montar(tester, api: api);
      await abrirAlta(tester);
      await llenarLoMinimo(tester, cantidad: '3', precio: '15000');
      await tester.pumpAndSettle();

      expect(find.text('TOTAL MENSUAL'), findsOneWidget);
      expect(find.text(r'$45,000.00 MXN'), findsOneWidget);
      expect(find.textContaining(r'3 × $15,000.00 MXN · sin IVA'), findsOneWidget);
    });

    testWidgets('cotizar con un TOTAL MENSUAL manda el total, no el unitario', (
      tester,
    ) async {
      String? cuerpo;

      final (api, _) = await cliente(
        condiciones: [vigente],
        responder: (p) {
          if (p.metodo == 'POST' && p.url.path.endsWith('/commercial-lines')) {
            cuerpo = p.cuerpo;

            return http.Response(
              jsonEncode({
                'line': {
                  'id': '0193f0aa-0000-7000-8000-0000000000f1',
                  'serviceId': servicio,
                  'name': 'Vigilancia por obra',
                  'kind': 'personal',
                  'status': 'active',
                  'updatedAt': '2026-01-10T18:00:00Z',
                },
                'term': null,
              }),
              201,
            );
          }

          return null;
        },
      );

      await montar(tester, api: api);
      await abrirAlta(tester);
      await llenarLoMinimo(tester, nombre: 'Vigilancia por obra', cantidad: '3');

      await abrirDesplegable(tester, clavesDeCondicion.modo);
      await tester.tap(find.text('Precio total mensual').last);
      await tester.pumpAndSettle();

      // LA ETIQUETA CAMBIA CON EL MODO: «Precio por persona» no significaba nada cuando lo
      // pactado es un total.
      expect(find.text('Precio total mensual'), findsWidgets);

      await tester.enterText(campo(clavesDeCondicion.precio), '100000');
      await tester.pumpAndSettle();

      // Y EL TOTAL ES EL CAPTURADO, sin multiplicar por las 3 personas.
      expect(find.text(r'$100,000.00 MXN'), findsOneWidget);

      await tester.tap(find.byKey(clavesDeCondicion.guardar));
      await tester.pumpAndSettle();

      final condicion =
          (jsonDecode(cuerpo!) as Map<String, dynamic>)['firstTerm']
              as Map<String, dynamic>;

      expect(condicion['pricingMode'], 'total_mensual');
      expect(condicion['monthlyTotalMinor'], 10000000);

      // 🚫 **NI RASTRO DEL UNITARIO**: mandar los dos responde 422, y dividir el total
      // entre 3 perdería centavos y cambiaría lo que se cobra.
      expect(condicion['unitPriceMinor'], isNull);
    });

    testWidgets('una línea de CONCEPTO no pide puesto, turno ni horario', (
      tester,
    ) async {
      String? cuerpo;

      final (api, _) = await cliente(
        condiciones: [vigente],
        responder: (p) {
          if (p.metodo == 'POST' && p.url.path.endsWith('/commercial-lines')) {
            cuerpo = p.cuerpo;

            return http.Response(
              jsonEncode({
                'line': {
                  'id': '0193f0aa-0000-7000-8000-0000000000f3',
                  'serviceId': servicio,
                  'name': 'Radios',
                  'kind': 'concepto',
                  'status': 'active',
                  'updatedAt': '2026-01-10T18:00:00Z',
                },
                'term': null,
              }),
              201,
            );
          }

          return null;
        },
      );

      await montar(tester, api: api);
      await abrirAlta(tester);

      await abrirDesplegable(tester, clavesDeCondicion.tipo);
      await tester.tap(find.text('Concepto').last);
      await tester.pumpAndSettle();

      await elegirDia(tester, clavesDeCondicion.inicio, '15');

      // LOS TRES CAMPOS QUE UN CONCEPTO NO TIENE.
      expect(find.byKey(clavesDeCondicion.puesto), findsNothing);
      expect(find.byKey(clavesDeCondicion.modalidad), findsNothing);
      expect(find.text('Horario semanal'), findsNothing);

      // Y la cantidad deja de hablar de personas.
      expect(find.text('Cantidad'), findsOneWidget);

      await tester.enterText(campo(clavesDeCondicion.nombre), 'Radios');
      await tester.enterText(campo(clavesDeCondicion.plazas), '12');
      await tester.enterText(campo(clavesDeCondicion.precio), '350');

      await tester.tap(find.byKey(clavesDeCondicion.guardar));
      await tester.pumpAndSettle();

      final enviado = jsonDecode(cuerpo!) as Map<String, dynamic>;

      expect(enviado['kind'], 'concepto');

      final condicion = enviado['firstTerm'] as Map<String, dynamic>;

      expect(condicion['positionId'], isNull);
      expect(condicion['shiftModalityId'], isNull);
      expect(condicion['schedules'], isEmpty);
    });

    testWidgets('desde 50 se pregunta, con el total escrito en la pregunta', (
      tester,
    ) async {
      var guardadas = 0;

      final (api, _) = await cliente(
        condiciones: [vigente],
        responder: (p) {
          if (p.metodo == 'POST' && p.url.path.endsWith('/commercial-lines')) {
            guardadas++;

            return http.Response(
              jsonEncode({
                'line': {
                  'id': '0193f0aa-0000-7000-8000-0000000000f4',
                  'serviceId': servicio,
                  'name': 'Evento',
                  'kind': 'personal',
                  'status': 'active',
                  'updatedAt': '2026-01-10T18:00:00Z',
                },
                'term': null,
              }),
              201,
            );
          }

          return null;
        },
      );

      await montar(tester, api: api);
      await abrirAlta(tester);
      await llenarLoMinimo(tester, nombre: 'Evento', cantidad: '60', precio: '1000');

      await tester.tap(find.byKey(clavesDeCondicion.guardar));
      await tester.pumpAndSettle();

      // LA PREGUNTA, con la cuenta hecha: 60 × 1 000 = 60 000.
      expect(find.text('¿60 en una sola línea?'), findsOneWidget);
      expect(find.textContaining(r'$60,000.00 MXN al mes'), findsOneWidget);

      // Y SI SE VUELVE A REVISAR, NO SE GUARDA NADA.
      await tester.tap(find.text('Volver a revisar'));
      await tester.pumpAndSettle();

      expect(guardadas, 0);

      // Aceptando, sí.
      await tester.tap(find.byKey(clavesDeCondicion.guardar));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sí, es correcto'));
      await tester.pumpAndSettle();

      expect(guardadas, 1);
    });

    testWidgets('sin puestos operativos se puede crear uno SIN salir', (
      tester,
    ) async {
      final (api, pedidas) = await cliente(
        condiciones: [vigente],
        responder: (p) {
          if (p.url.path.endsWith('/areas')) {
            if (p.metodo == 'POST') {
              return http.Response(
                jsonEncode({
                  'id': '0193f0aa-0000-7000-8000-0000000000a1',
                  'code': 'ARE-0001',
                  'name': 'Operaciones',
                  'status': 'activa',
                }),
                201,
              );
            }

            // NI UNA ÁREA, que es exactamente el caso del dueño: tuvo que crear área y
            // puesto, y salir le costó todo lo capturado.
            return http.Response(jsonEncode(const []), 200);
          }

          if (p.url.path.endsWith('/positions')) {
            if (p.metodo == 'POST') {
              return http.Response(
                jsonEncode({
                  'id': '0193f0aa-0000-7000-8000-0000000000a2',
                  'areaId': '0193f0aa-0000-7000-8000-0000000000a1',
                  'code': 'PUE-0001',
                  'name': 'Guardia de evento',
                  'kind': 'operativo',
                  'status': 'activa',
                  'hierarchyLevel': 1,
                  'description': null,
                  'createdAt': '2026-01-01T18:00:00Z',
                  'updatedAt': '2026-01-01T18:00:00Z',
                }),
                201,
              );
            }

            return http.Response(jsonEncode(const []), 200);
          }

          return null;
        },
      );

      await montar(tester, api: api);
      await abrirAlta(tester);

      // Se escribe algo ANTES de crear el puesto: lo que se comprueba es que no se pierda.
      await tester.enterText(campo(clavesDeCondicion.nombre), 'Guardias del evento');

      expect(find.text('Crear un puesto'), findsOneWidget);

      await tester.tap(find.byKey(clavesDeCondicion.crearPuesto));
      await tester.pumpAndSettle();

      expect(find.text('Nuevo puesto operativo'), findsOneWidget);

      await tester.enterText(
        find.descendant(
          of: find.byKey(clavesDePuestoRapido.areaNueva),
          matching: find.byType(TextFormField),
        ),
        'Operaciones',
      );

      await tester.enterText(
        find.descendant(
          of: find.byKey(clavesDePuestoRapido.nombre),
          matching: find.byType(TextFormField),
        ),
        'Guardia de evento',
      );

      await tester.tap(find.byKey(clavesDePuestoRapido.guardar));
      await tester.pumpAndSettle();

      // SE CREARON LAS DOS COSAS, el área y el puesto.
      expect(
        pedidas.where((p) => p.metodo == 'POST' && p.url.path.endsWith('/areas')),
        hasLength(1),
      );
      expect(
        pedidas.where((p) => p.metodo == 'POST' && p.url.path.endsWith('/positions')),
        hasLength(1),
      );

      // Y LO CAPTURADO SIGUE AHÍ, que es la mitad que importa.
      expect(find.text('Nueva línea comercial'), findsOneWidget);
      expect(
        tester.widget<TextFormField>(campo(clavesDeCondicion.nombre)).controller?.text,
        'Guardias del evento',
      );
    });

    testWidgets('la ayuda de «Hasta» cabe en tres líneas, y no se corta', (
      tester,
    ) async {
      final (api, _) = await cliente(condiciones: [vigente]);
      await montar(tester, api: api);
      await abrirAlta(tester);

      // 🚫 **ESTO ES EL ARREGLO DEL TEXTO CORTADO**, y se afirma sobre la decoración
      // porque un recorte con puntos suspensivos no se puede ver desde una prueba: el
      // campo de fecha no pasaba `helperMaxLines` y Flutter recorta a UNA línea.
      final hasta = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(clavesDeCondicion.termino),
          matching: find.byType(TextField),
        ),
      );

      expect(hasta.decoration?.helperMaxLines, 3);

      // Y LOS ASTERISCOS DEL PRECIO SE FUERON: el `helperText` es texto plano, así que
      // «**Cero es válido**» se leía con los asteriscos puestos.
      expect(find.textContaining('**'), findsNothing);
    });

    testWidgets('las OBSERVACIONES existen y viajan', (tester) async {
      String? cuerpo;

      final (api, _) = await cliente(
        condiciones: [vigente],
        responder: (p) {
          if (p.metodo == 'POST' && p.url.path.endsWith('/commercial-lines')) {
            cuerpo = p.cuerpo;

            return http.Response(
              jsonEncode({
                'line': {
                  'id': '0193f0aa-0000-7000-8000-0000000000f5',
                  'serviceId': servicio,
                  'name': 'Supervisor',
                  'kind': 'personal',
                  'status': 'active',
                  'updatedAt': '2026-01-10T18:00:00Z',
                },
                'term': null,
              }),
              201,
            );
          }

          return null;
        },
      );

      await montar(tester, api: api);
      await abrirAlta(tester);
      await llenarLoMinimo(tester);

      await tester.enterText(
        campo(clavesDeCondicion.observaciones),
        'Lo pidió el cliente por escrito.',
      );

      await tester.tap(find.byKey(clavesDeCondicion.guardar));
      await tester.pumpAndSettle();

      final condicion =
          (jsonDecode(cuerpo!) as Map<String, dynamic>)['firstTerm']
              as Map<String, dynamic>;

      expect(condicion['observations'], 'Lo pidió el cliente por escrito.');
    });
  });
}
