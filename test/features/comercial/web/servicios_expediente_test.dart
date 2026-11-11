// C2 · EL EXPEDIENTE DE UN SERVICIO (bloque 6d).
//
// ## Qué se fija aquí, y por qué estas cosas
//
//  1. **sólo viaja lo que cambió**, y en las DOS peticiones. El servidor rechaza un
//     `PATCH` que no cambia nada, y mandar los tres campos «porque están ahí» haría que
//     un cambio de nombre arrastrara unas observaciones que nadie tocó — y el evento de
//     la auditoría diría que también cambiaron;
//  2. **si el domicilio falla, se dice qué SÍ quedó guardado.** Sin eso, quien lea
//     «Falta la colonia.» pensaría que no se guardó nada y volvería a escribirlo todo;
//  3. **el supervisor tiene DOS puertas y son de MÓDULOS distintos**: verlo es
//     `clients_services.read` y elegirlo obliga a listar empleados, que es
//     `personal.read`. Sin la segunda se ve el nombre y no se ofrece el selector;
//  4. **un supervisor dado de baja NO se desvincula solo**: la ficha lo dice con una
//     insignia y ofrece cambiarlo, en vez de enseñar un nombre que parece vigente;
//  5. **terminado → suspendido no se ofrece**: el servidor responde 409, y un botón que
//     siempre falla es peor que su ausencia;
//  6. **el tipo retirado que el servicio YA USA se sigue ofreciendo**: si no, abrir el
//     expediente con el selector en blanco haría que cualquier otra corrección le
//     cambiara el tipo sin que nadie lo pidiera.
//
// ## Lo que NO está aquí
//
// A dónde llevan `alVolver` y `alIrADentro`: lo decide el portón. Aquí se comprueba que
// la pantalla los llame.

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
import 'package:riseg_one/features/comercial/web/datos/clientes_repositorio_http.dart';
import 'package:riseg_one/features/comercial/web/datos/servicios_repositorio_http.dart';
import 'package:riseg_one/features/comercial/web/presentation/expediente_servicio_web_screen.dart';
import 'package:riseg_one/features/organizacion/web/datos/sucursales_repositorio_http.dart';
import 'package:riseg_one/features/personal/web/datos/empleados_repositorio_http.dart';
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
}

void main() {
  final config = ApiConfig.resolve(
    raw: 'http://localhost:5199',
  ).when(ok: (c) => c, failure: (f) => throw StateError(f.message));

  final t0 = DateTime.utc(2026, 11, 11, 12);

  const empresa = '0193f0a0-0000-7000-8000-000000000001';
  const sportium = '0193f0a0-0000-7000-8000-0000000000c1';
  const servicio = '0193f0a0-0000-7000-8000-0000000000a1';
  const intramuros = '0193f0a0-0000-7000-8000-0000000000b1';
  const rondin = '0193f0a0-0000-7000-8000-0000000000b2';
  const empleado = '0193f0a0-0000-7000-8000-0000000000e1';

  Map<String, Object?> ficha({
    String estatus = 'active',
    String condicion = 'inforce',
    String? termino,
    String tipoId = intramuros,
    String? supervisorId,
    String? entidadFiscalId,
    String? contactoId,
    String? sucursalId,
    String? observaciones,
  }) => {
    'id': servicio,
    'clientId': sportium,
    'code': 'SRV-000001',
    'name': 'Sportium Satélite',
    'serviceTypeId': tipoId,
    'status': estatus,
    'temporalCondition': condicion,
    'startedOn': '2019-03-01',
    'endedOn': termino,
    'notes': observaciones,
    'supervisorEmployeeId': supervisorId,
    'administrativeBranchId': sucursalId,
    'responsibleContactId': contactoId,
    'fiscalEntityId': entidadFiscalId,
    'createdAt': '2026-10-20T18:00:00Z',
    'updatedAt': '2026-11-01T18:00:00Z',
  };

  const domicilio = {
    'street': 'Circuito Centro Comercial',
    'exteriorNumber': '40',
    'interiorNumber': null,
    'neighborhood': 'Ciudad Satélite',
    'municipality': 'Naucalpan',
    'city': 'Naucalpan',
    'state': 'Estado de México',
    'postalCode': '53100',
    'country': null,
    'reference': null,
  };

  const indicadores = {
    'monthlyAmount': [
      // `totalMinor`, en unidades MENORES: 45 000.00 MXN. Nunca un decimal.
      {'totalMinor': 4500000, 'currency': 'MXN'},
    ],
    'seniorityMonths': 80,
  };

  final tipos = [
    {
      'id': intramuros,
      'code': 'INTRAMUROS',
      'name': 'Vigilancia intramuros',
      'status': 'activa',
    },
    {'id': rondin, 'code': 'RONDIN', 'name': 'Rondín', 'status': 'activa'},
  ];

  /// La respuesta por omisión de cada ruta, con la ficha que la prueba pida.
  http.Response porOmision(_Pedida p, Map<String, Object?> servicioActual) {
    final ruta = p.url.path;

    if (ruta.endsWith('/indicators')) {
      return http.Response(jsonEncode(indicadores), 200);
    }

    if (ruta.endsWith('/address')) {
      return http.Response(jsonEncode(domicilio), 200);
    }

    if (ruta.endsWith('/service-types')) {
      return http.Response(jsonEncode(tipos), 200);
    }

    if (ruta.endsWith('/contacts')) {
      return http.Response(jsonEncode(const []), 200);
    }

    if (ruta.endsWith('/fiscal-entities')) {
      return http.Response(jsonEncode(const []), 200);
    }

    if (ruta.endsWith('/branches')) {
      return http.Response(jsonEncode(const []), 200);
    }

    if (ruta.endsWith('/supervisor')) {
      return http.Response(
        jsonEncode({
          'employeeId': empleado,
          'employeeNumber': 1024,
          'fullName': 'Juan Pérez García',
          'isActive': true,
        }),
        200,
      );
    }

    return http.Response(jsonEncode(servicioActual), 200);
  }

  Future<(ApiClientAutenticado, List<_Pedida>)> cliente({
    required Map<String, Object?> servicioActual,
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

        return responder?.call(pedida) ?? porOmision(pedida, servicioActual);
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

  const todo = CapacidadesDeModulo(
    puedeVer: true,
    puedeCrear: true,
    puedeModificar: true,
    puedeArchivar: true,
  );

  const soloLeer = CapacidadesDeModulo(
    puedeVer: true,
    puedeCrear: false,
    puedeModificar: false,
    puedeArchivar: false,
  );

  final dentro = <String?>[];
  final vueltas = <String>[];

  Future<List<_Pedida>> montar(
    WidgetTester tester, {
    Map<String, Object?>? servicioActual,
    http.Response? Function(_Pedida pedida)? responder,
    CapacidadesDeModulo capacidades = todo,
    bool puedeElegirSupervisor = true,
    bool editando = false,
  }) async {
    // UNA VENTANA ALTA, y hace falta: el expediente tiene seis secciones y un `tap`
    // sobre algo que no se ve **no hace nada y no se queja**.
    tester.view.physicalSize = const Size(1600, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    dentro.clear();
    vueltas.clear();

    final (api, pedidas) = await cliente(
      servicioActual: servicioActual ?? ficha(),
      responder: responder,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: MarcaSeventra.tema(),
        home: ExpedienteServicioWebScreen(
          repositorio: ServiciosRepositorioHttp(api),
          clientes: ClientesRepositorioHttp(api),
          sucursales: SucursalesRepositorioHttp(api),
          empleados: EmpleadosRepositorioHttp(api),
          empresaId: empresa,
          servicioId: servicio,
          capacidades: capacidades,
          puedeElegirSupervisor: puedeElegirSupervisor,
          guardia: GuardiaDeSalida(),
          editando: editando,
          alIrADentro: dentro.add,
          alVolver: () => vueltas.add('listado'),
          alConocerElNombre: (_, _) {},
        ),
      ),
    );

    await tester.pumpAndSettle();

    return pedidas;
  }

  /// Escribe en un campo por su etiqueta.
  ///
  /// ⚠️ **La etiqueta es HERMANA del campo, no su madre.** Se sube a la `Column` y se
  /// baja desde ahí; `find.ancestor(of: etiqueta, matching: TextField)` no encuentra
  /// nada y falla con «Bad state: No element», que no se parece a su causa.
  Future<void> escribir(
    WidgetTester tester,
    String etiqueta,
    String texto,
  ) async {
    await tester.enterText(
      find
          .descendant(
            of: find
                .ancestor(of: find.text(etiqueta), matching: find.byType(Column))
                .first,
            matching: find.byType(TextField),
          )
          .first,
      texto,
    );
  }

  List<_Pedida> correcciones(List<_Pedida> pedidas) => pedidas
      .where((p) => p.metodo == 'PATCH' && p.url.path.endsWith(servicio))
      .toList();

  /// El botón de UN vínculo concreto, por la etiqueta de su fila.
  ///
  /// ⚠️ **`find.text('Asignar').first` NO SIRVE AQUÍ**, y es un error que pasa
  /// desapercibido: la sección del supervisor también tiene un «Asignar» y va ANTES, así
  /// que `.first` abriría el selector de empleados y la prueba mediría otra cosa. Se
  /// acota a la fila por su etiqueta, que es única.
  Finder botonDelVinculo(String etiqueta, String label) => find.descendant(
    of: find
        .ancestor(of: find.text(etiqueta), matching: find.byType(Row))
        .first,
    matching: find.text(label),
  );

  // =========================================================================
  group('la ficha', () {
    testWidgets('trae folio, nombre, estatus y condición temporal EN ESPAÑOL', (
      tester,
    ) async {
      await montar(tester);

      // ⚠️ **DOS Y NO UNA**: el nombre sale en el título y otra vez dentro del campo
      // «Nombre del servicio», que existe también en consulta —apagado—. Exigir una
      // sola mediría que el formulario NO está, que es otra cosa.
      // El folio igual: bajo el título y en su campo de sólo lectura.
      expect(find.text('Sportium Satélite'), findsNWidgets(2));
      expect(find.text('SRV-000001'), findsNWidgets(2));
      expect(find.text('Activo'), findsOneWidget);

      // LA CONDICIÓN TEMPORAL VIAJA COMO `inforce` —sin guion bajo, por decisión del
      // dueño— y la pantalla es el ÚNICO sitio donde se traduce.
      expect(find.text('Vigente'), findsOneWidget);
      expect(find.textContaining('inforce'), findsNothing);
    });

    testWidgets('los indicadores dicen el importe y la antigüedad', (
      tester,
    ) async {
      await montar(tester);

      // LA ETIQUETA VA EN VERSALES, que es como las pinta la ficha.
      expect(find.text('ANTIGÜEDAD'), findsOneWidget);

      // 80 meses son 6 años y 8 meses: la redacción es de la pantalla, el número del
      // servidor.
      expect(find.text('6 años, 8 meses'), findsOneWidget);
    });

    testWidgets('sin condiciones vigentes, el importe NO dice cero', (
      tester,
    ) async {
      // ⚠️ **AUSENCIA NUNCA ES CERO.** Una lista vacía significa que no hay condiciones
      // comerciales vigentes; «$0.00» diría que el servicio no vale nada, que es otra
      // cosa y además falsa.
      await montar(
        tester,
        responder: (p) => p.url.path.endsWith('/indicators')
            ? http.Response(
                jsonEncode({
                  'monthlyAmount': const [],
                  'seniorityMonths': 3,
                }),
                200,
              )
            : null,
      );

      expect(find.text('Sin condiciones vigentes'), findsOneWidget);
      expect(find.textContaining('0.00'), findsNothing);
    });

    testWidgets('en un terminado, la antigüedad se llama «Duró»', (
      tester,
    ) async {
      await montar(
        tester,
        servicioActual: ficha(
          estatus: 'terminated',
          condicion: 'expired',
          termino: '2026-09-30',
        ),
      );

      expect(find.text('DURÓ'), findsOneWidget);
      expect(find.text('ANTIGÜEDAD'), findsNothing);
    });

    testWidgets('quien sólo lee no ve «Editar» ni «Cambiar estatus»', (
      tester,
    ) async {
      await montar(tester, capacidades: soloLeer);

      expect(find.text('Editar'), findsNothing);
      expect(find.text('Cambiar estatus'), findsNothing);

      // Pero la ficha SÍ se ve: eso es lo que `read` compra.
      expect(find.text('Sportium Satélite'), findsWidgets);
    });

    testWidgets('el supervisor NO se pide si la ficha dice que no hay', (
      tester,
    ) async {
      // Su ruta responde 404 cuando no hay, así que pedirlo igual sería pagar una
      // consulta para que conteste algo que la ficha ya dijo.
      final pedidas = await montar(tester);

      expect(
        pedidas.where((p) => p.url.path.endsWith('/supervisor')),
        isEmpty,
      );
      expect(find.text('Sin supervisor asignado'), findsOneWidget);
    });
  });

  // =========================================================================
  group('guardar manda SÓLO lo que cambió', () {
    testWidgets('cambiar el nombre NO arrastra las observaciones', (
      tester,
    ) async {
      final pedidas = await montar(
        tester,
        servicioActual: ficha(observaciones: 'Dos accesos'),
        editando: true,
      );

      await escribir(tester, 'Nombre del servicio', 'Sportium Satélite Norte');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      // El motivo se pide ANTES de mandar nada, por lo mismo que el servidor lo valida
      // primero: no es un campo del formulario, es la condición para corregir.
      await escribir(tester, 'Motivo de la corrección', 'Cambió el rótulo');
      await tester.tap(find.widgetWithText(InkWell, 'Guardar').last);
      await tester.pumpAndSettle();

      expect(jsonDecode(correcciones(pedidas).single.cuerpo), {
        'reason': 'Cambió el rótulo',
        'name': 'Sportium Satélite Norte',
      });
    });

    testWidgets('sin tocar nada, NO se manda ningún PATCH', (tester) async {
      // El servidor respondería «No hay nada que modificar», que es un 400 por algo que
      // no es un error del usuario: quería salir.
      final pedidas = await montar(tester, editando: true);

      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(correcciones(pedidas), isEmpty);

      // Y SE VUELVE A LA CONSULTA, que es lo que esa persona quería.
      expect(dentro, [null]);
    });

    testWidgets('si el domicilio falla, se dice que el servicio SÍ se guardó', (
      tester,
    ) async {
      // ⚠️ **SIN ESTO, quien lea «Falta la colonia.» pensaría que no se guardó nada** y
      // volvería a escribir el nombre. No se intenta deshacer: deshacer una corrección
      // es otra corrección, con su motivo.
      await montar(
        tester,
        editando: true,
        responder: (p) => p.metodo == 'PUT' && p.url.path.endsWith('/address')
            ? http.Response(
                jsonEncode({
                  'code': 'entrada_invalida',
                  'message': 'Falta la colonia.',
                }),
                400,
              )
            : null,
      );

      await escribir(tester, 'Nombre del servicio', 'Otro nombre');
      await escribir(tester, 'Colonia', 'Otra colonia');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      await escribir(tester, 'Motivo de la corrección', 'Corrección');
      await tester.tap(find.widgetWithText(InkWell, 'Guardar').last);
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Se guardaron los datos del servicio, pero el '
            'domicilio no'),
        findsOneWidget,
      );
    });
  });

  // =========================================================================
  group('el tipo de servicio', () {
    testWidgets('un tipo RETIRADO que el servicio ya usa se sigue ofreciendo', (
      tester,
    ) async {
      // ⚠️ SI NO, el expediente abriría con el selector en blanco y guardar cualquier
      // otra corrección le cambiaría el tipo sin que nadie lo pidiera.
      await montar(
        tester,
        editando: true,
        responder: (p) => p.url.path.endsWith('/service-types')
            ? http.Response(
                jsonEncode([
                  {
                    'id': intramuros,
                    'code': 'INTRAMUROS',
                    'name': 'Vigilancia intramuros',
                    'status': 'inactiva',
                  },
                  ...tipos.where((t) => t['id'] != intramuros),
                ]),
                200,
              )
            : null,
      );

      // Y SE DICE QUE ESTÁ RETIRADO, para que nadie crea que sigue disponible.
      expect(find.text('Vigilancia intramuros (retirado)'), findsOneWidget);
    });
  });

  // =========================================================================
  group('el supervisor responsable', () {
    final conSupervisor = ficha(supervisorId: empleado);

    testWidgets('se ve con su nombre y su número', (tester) async {
      await montar(tester, servicioActual: conSupervisor);

      expect(find.text('Juan Pérez García'), findsOneWidget);
      expect(find.text('Empleado 1024'), findsOneWidget);
    });

    testWidgets('sin personal.read se VE y NO se ofrece el selector', (
      tester,
    ) async {
      // ⚠️ **LA PROPIEDAD 3, Y SON DOS MÓDULOS.** Ver el supervisor es
      // `clients_services.read`; elegirlo obliga a listar empleados, que es
      // `personal.read`. Enseñar el selector sería enseñar una puerta que da 403.
      await montar(
        tester,
        servicioActual: conSupervisor,
        puedeElegirSupervisor: false,
      );

      expect(find.text('Juan Pérez García'), findsOneWidget);
      expect(find.text('Cambiar'), findsNothing);

      // Y SE DICE POR QUÉ, en vez de dejar un hueco sin explicación.
      expect(
        find.textContaining('permiso de lectura en Personal'),
        findsOneWidget,
      );
    });

    testWidgets('un supervisor DADO DE BAJA lleva insignia y aviso', (
      tester,
    ) async {
      // ⚠️ **NO SE DESVINCULA SOLO** —decisión del dueño—, así que la ficha tiene que
      // poder decir que esa persona ya no está en vez de enseñar un nombre que parece
      // vigente. Es la razón de que la ruta devuelva `isActive`.
      await montar(
        tester,
        servicioActual: conSupervisor,
        responder: (p) => p.url.path.endsWith('/supervisor') && p.metodo == 'GET'
            ? http.Response(
                jsonEncode({
                  'employeeId': empleado,
                  'employeeNumber': 1024,
                  'fullName': 'Juan Pérez García',
                  'isActive': false,
                }),
                200,
              )
            : null,
      );

      expect(find.text('Baja'), findsOneWidget);
      expect(find.textContaining('ya no está activa'), findsOneWidget);

      // Y SIGUE AHÍ: la referencia se conserva.
      expect(find.text('Juan Pérez García'), findsOneWidget);
    });

    testWidgets('asignar uno manda su id y lo pinta sin volver a preguntar', (
      tester,
    ) async {
      final pedidas = await montar(
        tester,
        responder: (p) {
          if (p.url.path.endsWith('/employees')) {
            return http.Response(
              jsonEncode({
                'items': [
                  {
                    'id': empleado,
                    'employeeNumber': 1024,
                    'fullName': 'Juan Pérez García',
                    'isActive': true,
                  },
                ],
                'nextCursor': null,
              }),
              200,
            );
          }

          if (p.metodo == 'PUT' && p.url.path.endsWith('/supervisor')) {
            return http.Response(
              jsonEncode(ficha(supervisorId: empleado)),
              200,
            );
          }

          return null;
        },
      );

      await tester.tap(find.text('Asignar'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Juan Pérez García'));
      await tester.pumpAndSettle();

      final puesto = pedidas.singleWhere(
        (p) => p.metodo == 'PUT' && p.url.path.endsWith('/supervisor'),
      );

      expect(jsonDecode(puesto.cuerpo), {'id': empleado});

      // LOS EMPLEADOS SE PIDEN **ACTIVOS**, y el filtro lo aplica el servidor: filtrar
      // una página no es filtrar la plantilla.
      final listados = pedidas.where((p) => p.url.path.endsWith('/employees'));

      expect(listados.single.url.queryParameters['status'], 'active');
    });
  });

  // =========================================================================
  group('el estatus y el término', () {
    testWidgets('en un TERMINADO no se ofrece «Suspendido»', (tester) async {
      // 🚫 **TERMINADO → SUSPENDIDO ESTÁ PROHIBIDO** y el servidor responde 409. Un
      // botón que siempre falla es peor que su ausencia, y aquí además confundiría
      // «suspender» con «reactivar».
      await montar(
        tester,
        servicioActual: ficha(
          estatus: 'terminated',
          condicion: 'expired',
          termino: '2026-09-30',
        ),
      );

      await tester.tap(find.text('Cambiar estatus'));
      await tester.pumpAndSettle();

      expect(find.text('Suspendido'), findsNothing);

      // Y REACTIVAR SE LLAMA «Reactivar», no «Activo»: desde un terminado, volver a
      // operar es otra cosa que activar algo que estaba en pausa.
      expect(find.text('Reactivar'), findsOneWidget);
    });

    testWidgets('en un ACTIVO se ofrecen suspender y terminar', (tester) async {
      await montar(tester);

      await tester.tap(find.text('Cambiar estatus'));
      await tester.pumpAndSettle();

      expect(find.text('Suspendido'), findsOneWidget);
      expect(find.text('Terminado'), findsOneWidget);

      // EL ACTUAL NO SE OFRECE: cambiarlo a lo que ya es no es un cambio.
      //
      // ⚠️ **SE ACOTA AL DIÁLOGO**, y hace falta: la insignia de la cabecera también
      // dice «Activo» y sigue pintada detrás. Sin acotar, esta aserción fallaría por la
      // insignia y parecería que el diálogo ofrece el estatus actual.
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Activo'),
        ),
        findsNothing,
      );
    });

    testWidgets('sin término, la sección lo dice y ofrece programarlo', (
      tester,
    ) async {
      await montar(tester);

      expect(find.text('Sin fecha de término'), findsOneWidget);
      expect(find.text('Programar'), findsOneWidget);
      expect(find.text('Retirar'), findsNothing);
    });

    testWidgets('con término, se puede retirar y la llamada es un DELETE', (
      tester,
    ) async {
      final pedidas = await montar(
        tester,
        servicioActual: ficha(termino: '2027-03-31'),
        responder: (p) =>
            p.metodo == 'DELETE' && p.url.path.endsWith('/schedule-end')
            ? http.Response(jsonEncode(ficha()), 200)
            : null,
      );

      await tester.tap(find.text('Retirar'));
      await tester.pumpAndSettle();

      expect(
        pedidas.where(
          (p) => p.metodo == 'DELETE' && p.url.path.endsWith('/schedule-end'),
        ),
        hasLength(1),
      );

      expect(find.textContaining('Se retiró el término'), findsOneWidget);
    });

    testWidgets('en un TERMINADO no se ofrece programar ni retirar', (
      tester,
    ) async {
      // No se «programa» algo que ya pasó: la fecha de un terminado es un hecho.
      await montar(
        tester,
        servicioActual: ficha(
          estatus: 'terminated',
          condicion: 'expired',
          termino: '2026-09-30',
        ),
      );

      expect(find.text('Programar'), findsNothing);
      expect(find.text('Retirar'), findsNothing);
      expect(find.textContaining('reactívalo'), findsOneWidget);
    });
  });

  // =========================================================================
  group('los vínculos', () {
    testWidgets('sin de dónde elegir, NO se ofrece el botón y se explica', (
      tester,
    ) async {
      // Un selector vacío parece un error del producto y no la consecuencia de que el
      // cliente todavía no tenga contactos.
      await montar(tester);

      expect(
        find.text('Este cliente todavía no tiene contactos.'),
        findsOneWidget,
      );
      expect(find.text('La empresa todavía no tiene sucursales.'), findsOneWidget);
    });

    testWidgets('la PRIMERA entidad fiscal NO pide motivo', (tester) async {
      // ⚠️ **R9 · EL MOTIVO ES CONDICIONAL**, y la pantalla aplica la misma regla que el
      // servidor: la primera asignación no lo pide y cambiarla sí. Preguntarlo siempre
      // pediría algo que el servidor no exige.
      const entidad = '0193f0a0-0000-7000-8000-0000000000f1';

      final pedidas = await montar(
        tester,
        responder: (p) {
          if (p.url.path.endsWith('/fiscal-entities')) {
            return http.Response(
              jsonEncode([
                {
                  'id': entidad,
                  'legalName': 'Sportium SA de CV',
                  'taxId': 'SPO010101AAA',
                  'taxRegime': null,
                  'notes': null,
                  'status': 'activa',
                },
              ]),
              200,
            );
          }

          if (p.metodo == 'PUT' && p.url.path.endsWith('/fiscal-entity')) {
            return http.Response(
              jsonEncode(ficha(entidadFiscalId: entidad)),
              200,
            );
          }

          return null;
        },
      );

      await tester.tap(botonDelVinculo('ENTIDAD FISCAL', 'Asignar'));
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Sportium SA de CV'));
      await tester.pumpAndSettle();

      final asignada = pedidas.singleWhere(
        (p) => p.metodo == 'PUT' && p.url.path.endsWith('/fiscal-entity'),
      );

      // SIN `reason`: la primera asignación no lo lleva.
      expect(jsonDecode(asignada.cuerpo), {'id': entidad});
    });
  });

  // =========================================================================
  group('la salida', () {
    testWidgets('el regreso dice «Servicios» y llama a quien lo trajo', (
      tester,
    ) async {
      await montar(tester);

      await tester.tap(find.text('Servicios'));
      await tester.pumpAndSettle();

      expect(vueltas, ['listado']);
    });

    testWidgets('«Editar» pide la OTRA dirección, no un modo interno', (
      tester,
    ) async {
      // D-39 · consultar y editar son dos direcciones, no un `bool` dentro de una: así
      // «atrás» devuelve de la edición a la consulta.
      await montar(tester);

      await tester.tap(find.text('Editar'));
      await tester.pumpAndSettle();

      expect(dentro, ['editar']);
    });
  });
}
