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
import 'package:go_router/go_router.dart';
import 'package:riseg_one/app/shell/apartados_web.dart' show CapacidadesDeModulo;
import 'package:riseg_one/app/shell/router_web.dart' show seguroDeSalir;
import 'package:riseg_one/core/api/api_client.dart';
import 'package:riseg_one/core/api/api_client_autenticado.dart';
import 'package:riseg_one/core/auth/almacen_sesion_remota.dart';
import 'package:riseg_one/core/auth/auth_api.dart';
import 'package:riseg_one/core/auth/gestor_de_sesion.dart';
import 'package:riseg_one/core/auth/sesion_remota.dart';
import 'package:riseg_one/core/config/api_config.dart';
import 'package:riseg_one/core/design_system/design_system_web.dart'
    show RisegDateField, RisegLogotipoOIniciales;
import 'package:riseg_one/core/fechas/dia_de_negocio.dart';
import 'package:riseg_one/core/logging/app_logger.dart';
import 'package:riseg_one/core/trabajo_sin_guardar/guardia_de_salida.dart';
import 'package:riseg_one/features/comercial/web/datos/clientes_repositorio_http.dart';
import 'package:riseg_one/features/comercial/web/datos/condiciones_repositorio_http.dart';
import 'package:riseg_one/features/organizacion/web/datos/areas_repositorio_http.dart';
import 'package:riseg_one/features/organizacion/web/datos/puestos_repositorio_http.dart';
import 'package:riseg_one/features/comercial/web/datos/servicios_repositorio_http.dart';
import 'package:riseg_one/features/comercial/web/presentation/expediente_servicio_web_screen.dart';
import 'package:riseg_one/features/comercial/web/presentation/seccion_comercial.dart'
    show SeccionComercial;
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

  /// **El día que estas pruebas creen que es hoy**, fijo a propósito.
  const hoy = DiaDeNegocio(2026, 11, 11);

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

  /// **La ficha del cliente dueño del servicio**, que es de donde sale la identidad de la
  /// cabecera desde el 13 de noviembre de 2026: su logotipo, o **sus** iniciales.
  ///
  /// ⚠️ **«Sportium» da `SP`, y el servicio «Sportium Satélite» daría `SS`**: es justo lo
  /// que deja distinguir en una prueba si el avatar es del cliente o del servicio.
  const clienteDelServicio = {
    'id': sportium,
    'code': 'CLI-000001',
    'commercialName': 'Sportium',
    'status': 'active',
    'relationshipStartedOn': '2019-01-15',
    'notes': null,
    'createdAt': '2019-01-15T18:00:00Z',
    'updatedAt': '2026-11-01T18:00:00Z',
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

    // C3 · LAS LÍNEAS COMERCIALES, vacías. **Hacen falta aquí desde que renovar pregunta
    // el precio**: el diálogo las lee al abrirse, y sin esta rama caían en la respuesta
    // por omisión —la ficha del servicio—, que no es una lista y aborta la renovación
    // diciendo que no se pudieron leer los precios. Vacías es el caso de estas pruebas:
    // lo que miden es la FECHA.
    if (ruta.endsWith('/commercial-lines')) {
      return http.Response(jsonEncode(const []), 200);
    }

    // LA IDENTIDAD DEL CLIENTE, que es lo que la cabecera enseña desde el 13 de
    // noviembre de 2026: su nombre comercial, y **sin logotipo** —que es el caso en que
    // se pintan las iniciales—.
    if (ruta.endsWith('/logo/content')) return http.Response('', 404);

    if (ruta.contains('/clients/')) {
      return http.Response(jsonEncode(clienteDelServicio), 200);
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

  /// Cuántas veces la pantalla avisó de que **lo que la campana cuenta cambió**.
  var avisosReleidos = 0;

  Future<List<_Pedida>> montar(
    WidgetTester tester, {
    Map<String, Object?>? servicioActual,
    http.Response? Function(_Pedida pedida)? responder,
    CapacidadesDeModulo capacidades = todo,
    bool puedeElegirSupervisor = true,
    bool editando = false,
    // ⚠️ FALSO POR OMISIÓN para que ningún botón de precios aparezca en las pruebas que
    // miden otra cosa. La renovación con precios SÍ lo necesita, y lo pide.
    bool puedeTocarPrecios = false,
  }) async {
    // UNA VENTANA ALTA, y hace falta: el expediente tiene seis secciones y un `tap`
    // sobre algo que no se ve **no hace nada y no se queja**.
    tester.view.physicalSize = const Size(1600, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    dentro.clear();
    vueltas.clear();
    avisosReleidos = 0;

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
          // C3 · la pestaña Comercial. Estas pruebas no la abren, así que lo que importa
          // es que la pantalla se monte: los permisos van en false para que ningún botón
          // de precios aparezca en las capturas de las otras pestañas.
          condiciones: CondicionesRepositorioHttp(api),
          puestos: PuestosRepositorioHttp(api),
          areas: AreasRepositorioHttp(api),
          puedeTocarPrecios: puedeTocarPrecios,
          puedeVerSueldos: false,
          guardia: GuardiaDeSalida(),
          editando: editando,
          alIrADentro: dentro.add,
          alVolver: () => vueltas.add('listado'),
          alConocerElNombre: (_, _) {},
          // LO QUE AVISA A LA CAMPANA, aquí sólo se cuenta: lo que estas pruebas miden es
          // que la pantalla lo llame, y el grupo de abajo lo comprueba.
          alMoverElTermino: () => avisosReleidos++,
          // ⚠️ **EL DÍA SE FIJA, y no es una comodidad:** la insignia «Termina el…»
          // depende de cuántos días faltan, así que con el reloj de verdad la prueba del
          // término a cincuenta días **se rompería sola** cincuenta días después.
          hoy: () => hoy,
        ),
      ),
    );

    await tester.pumpAndSettle();

    return pedidas;
  }

  /// Abre una pestaña del expediente: **General · Domicilio · Vínculos**.
  ///
  /// ⚠️ **ES NUEVO CON EL ESTILO B, elegido por el dueño el 11 de noviembre de 2026**, y
  /// cambia cómo se escribe una prueba de esta pantalla: antes todo estaba apilado en una
  /// página larga, así que cualquier `find` lo encontraba. Ahora **lo que no está en la
  /// pestaña abierta no está en el árbol**, que es exactamente lo que el estilo compra —un
  /// asunto a la vez— y lo que obliga a decir aquí a cuál se va.
  Future<void> abrirPestana(WidgetTester tester, String cual) async {
    await tester.tap(find.text(cual));
    await tester.pumpAndSettle();
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

      // ⚠️ **UNA Y NO DOS, y es el estilo B.** Antes el nombre salía en el título **y**
      // dentro de un campo «Nombre del servicio» apagado, que es justo lo que el dueño
      // leyó como «la vista se ve casi igual que la edición». En consulta el nombre vive
      // en la cabecera y nada más; el campo aparece **al editar**.
      expect(find.text('Sportium Satélite'), findsOneWidget);
      expect(find.text('Activo'), findsOneWidget);

      // El folio sale dos veces a propósito: bajo el título, que es donde se busca, y
      // como dato de la pestaña General, que es donde se copia.
      expect(find.text('SRV-000001'), findsNWidgets(2));

      // LA CONDICIÓN TEMPORAL VIAJA COMO `inforce` —sin guion bajo, por decisión del
      // dueño— y la pantalla es el ÚNICO sitio donde se traduce.
      expect(find.text('Vigente'), findsOneWidget);
      expect(find.textContaining('inforce'), findsNothing);
    });

    testWidgets('🚫 EL AVATAR ES EL DEL CLIENTE, y mide lo que debe', (
      tester,
    ) async {
      // 🚫 **LO QUE EL DUEÑO VIO EN EL ENSAYO el 13 de noviembre de 2026:** «un cuadrito
      // verde con PA o A pegado al título». Eran dos defectos a la vez y ninguna prueba
      // miraba ninguno:
      //
      //  1. **la identidad era la del servicio** —sus iniciales—, cuando en el listado el
      //     avatar es **del cliente**: la misma empresa se reconocía distinta en dos
      //     pantallas;
      //  2. **el cuadro no medía.** `RisegIniciales` sólo elegía el tamaño de la letra y
      //     dejaba el cuadro a quien la montara; cuatro sitios lo envolvían en un
      //     `SizedBox` y éste no, así que salía del tamaño de sus dos letras.
      await montar(tester);

      // «Sportium» da SP. El servicio se llama «Sportium Satélite», que daría SS: es lo
      // que distingue de quién es el avatar.
      expect(find.text('SP'), findsOneWidget);
      expect(find.text('SS'), findsNothing);

      expect(
        tester.getSize(find.byType(RisegLogotipoOIniciales)),
        const Size(48, 48),
        reason:
            'el mismo lado que el avatar del expediente de un cliente: es el mismo '
            'componente, y por eso no pueden discrepar',
      );
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

      // Y SIN NADA POR CERRAR, la segunda cifra tampoco existe: ausencia no es cero,
      // tampoco aquí. ⚠️ La etiqueta se pinta en VERSALITA, así que se busca en mayúsculas.
      expect(find.text('POR CERRAR'), findsNothing);
    });

    /// **EL ENCABEZADO SEPARA LO QUE COBRA DE LO QUE SE VA** (dueño, 19-nov-2026).
    ///
    /// Era el punto 5 de su prueba de cierre de C3: «Importe mensual» mezclaba las líneas
    /// dadas de baja con las que cobran, así que **dar de baja una línea no movía la
    /// cifra** y el encabezado no decía nada de lo que estaba por terminarse. Ahora la
    /// primera cifra es lo que se cobra —sólo líneas activas— y la segunda es lo que deja
    /// de cobrarse, **con la fecha hasta la que se cobra**, que es la mitad útil del dato.
    testWidgets('«Por cerrar» sale aparte, con su fecha', (tester) async {
      await montar(
        tester,
        responder: (p) => p.url.path.endsWith('/indicators')
            ? http.Response(
                jsonEncode({
                  'monthlyAmount': const [
                    {'totalMinor': 4500000, 'currency': 'MXN'},
                  ],
                  'closingAmount': const [
                    {
                      'totalMinor': 900000,
                      'currency': 'MXN',
                      'hasta': '2026-12-14',
                    },
                  ],
                  'seniorityMonths': 80,
                }),
                200,
              )
            : null,
      );

      expect(find.text('POR CERRAR'), findsOneWidget);

      // LA FECHA VA PEGADA AL IMPORTE: «$9,000.00» a secas no dice si eso se deja de
      // cobrar el mes que viene o el año que viene, que es lo que alguien quiere saber.
      expect(
        find.textContaining(r'$9,000.00 MXN (hasta el 14/dic/2026)'),
        findsOneWidget,
      );

      // Y LA PRIMERA CIFRA SIGUE SIENDO LO QUE SE COBRA: las dos no se suman.
      expect(find.textContaining(r'$45,000.00 MXN'), findsOneWidget);
    });

    testWidgets('un servidor sin «closingAmount» no rompe el encabezado', (
      tester,
    ) async {
      // ⚠️ **EL CAMPO ES ADITIVO, y esto lo mide:** una build de la web más nueva que el
      // servidor enseña el encabezado completo **sin** la segunda cifra, en lugar de no
      // enseñar nada. Es el modo de fallo del contrato entre los dos repos: lo que revienta
      // al leer deja la pantalla cargando para siempre, sin error.
      await montar(tester);

      expect(find.textContaining(r'$45,000.00 MXN'), findsOneWidget);
      expect(find.text('POR CERRAR'), findsNothing);
    });

    /// 🚫 **EL ENCABEZADO SE REFRESCA AL GUARDAR UNA CONDICIÓN** (0066).
    ///
    /// Es el error 2 de la prueba en pantalla del dueño del 18-nov-2026: guardó una
    /// condición, la tarjeta de la línea dijo «Cobra hoy $30,000» y el encabezado siguió
    /// diciendo «Sin condiciones vigentes» hasta recargar. ⚠️ **Es la duda número uno del
    /// inventario de RISEG ONE** —«el personal asignado desaparece tras guardar»— repetida
    /// aquí con otro dato: el expediente reconstruía su estado sin volver a leer esa parte.
    testWidgets('al guardar una condición, el IMPORTE del encabezado se relee', (
      tester,
    ) async {
      var guardada = false;
      var lecturasDeIndicadores = 0;

      await montar(
        tester,
        responder: (p) {
          if (p.url.path.endsWith('/indicators')) {
            lecturasDeIndicadores++;

            return http.Response(
              jsonEncode({
                // ANTES de guardar no cobra nada; DESPUÉS, 45 000.
                'monthlyAmount': guardada
                    ? [
                        {'currency': 'MXN', 'totalMinor': 4500000},
                      ]
                    : const [],
                'seniorityMonths': 3,
              }),
              200,
            );
          }

          if (p.metodo == 'POST' && p.url.path.endsWith('/commercial-lines')) {
            guardada = true;

            return http.Response(
              jsonEncode({
                'line': {
                  'id': '0193f0bb-0000-7000-8000-0000000000e1',
                  'serviceId': servicio,
                  'name': 'Guardias',
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

      expect(find.text('Sin condiciones vigentes'), findsOneWidget);
      expect(lecturasDeIndicadores, 1);

      // Se abre la pestaña Comercial, que es quien avisa hacia arriba cuando guarda.
      await tester.tap(find.text('Comercial'));
      await tester.pumpAndSettle();

      // ⚠️ **SE DISPARA EL AVISO, no el diálogo entero:** que guardar una condición llame a
      // este aviso lo prueban las pruebas de la propia pestaña; lo que falta probar aquí es
      // la otra mitad —que el expediente **relee los indicadores** al recibirlo—, y es la
      // mitad que faltaba de verdad.
      final seccion = tester.widget<SeccionComercial>(find.byType(SeccionComercial));

      // La condición ya se guardó —eso es lo que el servidor contestaría—, así que la
      // siguiente lectura de indicadores trae los 45 000.
      guardada = true;

      seccion.alCambiarLoQueCobra!();
      await tester.pumpAndSettle();

      expect(lecturasDeIndicadores, 2);
      expect(find.text('Sin condiciones vigentes'), findsNothing);
      expect(find.text(r'$45,000.00 MXN'), findsOneWidget);
    });

    testWidgets('la pestaña MARCADA es la que se está viendo', (tester) async {
      // 🚫 **LO DESTAPÓ UNA CAPTURA DEL ESTILO B.** El contenido cambiaba a Vínculos y el
      // subrayado se quedaba en «General»: quien mira la pantalla no sabe dónde está, y
      // es peor que no tener pestañas — parecen rotas.
      await montar(tester);
      await abrirPestana(tester, 'Vínculos');

      final barra = tester.widget<TabBar>(find.byType(TabBar));

      expect(barra.controller!.index, 2);
    });

    testWidgets('un TERMINADO no dice «Vigente»: dice cuándo terminó', (
      tester,
    ) async {
      // 🚫 **LA CONTRADICCIÓN QUE EL DUEÑO VIO EN PANTALLA EL 11 DE NOVIEMBRE DE 2026.**
      //
      // El servidor manda `status: terminated` **y** `temporalCondition: inforce`, y las
      // dos son ciertas por separado: se terminó, y su fecha de término todavía no llega.
      // Juntas no se pueden leer — un servicio terminado no está vigente.
      //
      // ⚠️ **Y ES EL CASO QUE DE VERDAD PASA**: terminar un servicio hoy no mueve su
      // `endedOn` programado, así que `inforce` sobre un terminado no es un dato raro.
      await montar(
        tester,
        servicioActual: ficha(
          estatus: 'terminated',
          condicion: 'inforce',
          termino: '2026-12-31',
        ),
      );

      expect(find.text('Terminado'), findsOneWidget);
      expect(find.text('Vigente'), findsNothing);
      expect(find.text('Terminó el 31/dic/2026'), findsOneWidget);
    });

    testWidgets('un terminado SIN fecha de término no enseña insignia temporal', (
      tester,
    ) async {
      // El estatus ya lo dice todo, y un texto genérico —«Terminado hace tiempo»— no
      // añadiría nada cierto. `endedOn` nulo es un caso real: el servidor lo acepta.
      await montar(
        tester,
        servicioActual: ficha(estatus: 'terminated', condicion: 'inforce'),
      );

      expect(find.text('Terminado'), findsOneWidget);
      expect(find.text('Vigente'), findsNothing);
      expect(find.textContaining('Terminó el'), findsNothing);
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

      // EL SUPERVISOR VIVE EN «VÍNCULOS» desde el estilo B, así que hay que abrirla: lo
      // que no está en la pestaña puesta no está en el árbol.
      await abrirPestana(tester, 'Vínculos');

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

    testWidgets('🚫 lo que falta del domicilio se señala TODO, de un golpe', (
      tester,
    ) async {
      // 🚫 **LA FALLA DEL 11 DE NOVIEMBRE DE 2026 EN ESTA PANTALLA.** Aquí el único campo
      // que se podía poner en rojo era el nombre: el domicilio iba con
      // `erroresPorCampo: const {}` y lo que faltaba se descubría **de uno en uno** en el
      // aviso del servidor, que contesta el primero que falta y para.
      final pedidas = await montar(tester, editando: true);

      await abrirPestana(tester, 'Domicilio');
      await escribir(tester, 'Estado', '');
      await escribir(tester, 'Código postal', '');
      await tester.pumpAndSettle();

      // SE VUELVE A «GENERAL» A PROPÓSITO, para medir la pieza que el estilo B obligó a
      // añadir: guardar desde otra pestaña tiene que **abrir la del error**, o el aviso
      // se pintaría donde nadie está mirando y «Guardar» parecería no hacer nada.
      await abrirPestana(tester, 'General');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(find.text('Falta el estado.'), findsOneWidget);
      expect(find.text('Falta el código postal.'), findsOneWidget);

      // Y NO SE PIDE EL MOTIVO NI SE MANDA NADA: preguntar el motivo de una corrección
      // que no se va a poder guardar es hacer escribir para nada.
      expect(find.text('Motivo de la corrección'), findsNothing);
      expect(correcciones(pedidas), isEmpty);
      expect(pedidas.where((p) => p.metodo == 'PUT'), isEmpty);
    });

    testWidgets('el nombre vacío se señala EN SU CAMPO', (tester) async {
      final pedidas = await montar(tester, editando: true);

      await escribir(tester, 'Nombre del servicio', '');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(find.text('Falta el nombre del servicio.'), findsOneWidget);
      expect(correcciones(pedidas), isEmpty);
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
      await abrirPestana(tester, 'Domicilio');
      await escribir(tester, 'Colonia', 'Otra colonia');
      await tester.pumpAndSettle();

      // «GUARDAR» ESTÁ EN LA CABECERA, así que se pulsa igual desde cualquier pestaña:
      // con pestañas, un botón al pie del contenido sólo existiría en la que está puesta.
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
      await abrirPestana(tester, 'Vínculos');

      // EL NOMBRE Y EL NÚMERO EN UNA LÍNEA, con `·`: son un solo dato —quién es— y en
      // dos renglones el número parecía otro campo.
      expect(find.text('Juan Pérez García · empleado 1024'), findsOneWidget);
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
      await abrirPestana(tester, 'Vínculos');

      expect(
        find.text('Juan Pérez García · empleado 1024'),
        findsOneWidget,
      );
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

      await abrirPestana(tester, 'Vínculos');

      expect(find.text('Baja'), findsOneWidget);
      expect(find.textContaining('ya no está activa'), findsOneWidget);

      // Y SIGUE AHÍ: la referencia se conserva.
      expect(
        find.text('Juan Pérez García · empleado 1024'),
        findsOneWidget,
      );
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

      await abrirPestana(tester, 'Vínculos');

      // ⚠️ **AQUÍ `find.text('Asignar')` YA ES ÚNICO**, y antes no lo era: las tres filas
      // de asignaciones estrenan botón sólo cuando hay de dónde elegir, y en esta ficha
      // no hay entidades, contactos ni sucursales. Si algún día los hubiera, esta prueba
      // tendría que acotarlo a la fila del supervisor.
      await tester.tap(find.text('Asignar'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Juan Pérez García'));
      await tester.pumpAndSettle();

      // ⚠️ **MARCAR NO ES ASIGNAR**, y es lo que el dueño pidió el 12 de noviembre de
      // 2026: antes un clic en la fila asignaba y cerraba, así que no había forma de
      // mirar las opciones sin comprometerse. Aquí se mide que **todavía no viajó nada**.
      expect(
        pedidas.where(
          (p) => p.metodo == 'PUT' && p.url.path.endsWith('/supervisor'),
        ),
        isEmpty,
      );

      // Y AHORA SÍ: el botón del diálogo, que es el de abajo.
      await tester.tap(find.text('Asignar').last);
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

    testWidgets('«Renovar / extender» quita la fecha con un DELETE', (
      tester,
    ) async {
      // ⚠️ **UN SOLO BOTÓN, DOS SALIDAS**, pedido por el dueño el 11 de noviembre de
      // 2026: antes eran «Cambiar» y «Retirar» y obligaban a decidir cuál se parecía más
      // a lo que pasó. El caso real es uno —el contrato se renovó— y lo que se sabe es la
      // fecha nueva o que ya no hay fecha.
      final pedidas = await montar(
        tester,
        servicioActual: ficha(termino: '2027-03-31'),
        // ⚠️ **CON PERMISO DE PRECIOS, porque renovar lo exige** desde el 14-nov-2026: el
        // botón sólo dice «Renovar / extender» cuando se puede reprogramar el precio de cada
        // línea. Sin él dice «Programar», y eso tiene su propia prueba.
        puedeTocarPrecios: true,
        responder: (p) =>
            p.metodo == 'DELETE' && p.url.path.endsWith('/schedule-end')
            ? http.Response(jsonEncode(ficha()), 200)
            : null,
      );

      await tester.tap(find.text('Renovar / extender'));
      await tester.pumpAndSettle();

      // ⚠️ **DESDE C3 EL DIÁLOGO TIENE TRES PASOS Y SÍ PREGUNTA EL PRECIO.** Esta prueba
      // decía «No cambia los precios», que era verdad mientras las condiciones comerciales
      // no existían. Lo que se mide aquí sigue siendo la FECHA, con el servicio sin
      // líneas.
      expect(find.text('Renovar / extender · hasta cuándo'), findsOneWidget);

      await tester.tap(find.text('Se renovó sin fecha de fin'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();

      // ⚠️ **ESTE SERVICIO NO TIENE NINGUNA LÍNEA** —el arnés responde `[]` a
      // `/commercial-lines`—, así que no hay precio que renovar y esto es sólo la fecha.
      // 🚫 **El paso no se esconde**, y es a propósito: que no haya precios que mover es
      // un hecho que quien renueva necesita leer, no una pantalla que sobra.
      expect(
        find.textContaining('no tiene ninguna línea con precio que renovar'),
        findsOneWidget,
      );

      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();

      expect(find.textContaining('sin fecha de término'), findsOneWidget);

      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(
        pedidas.where(
          (p) => p.metodo == 'DELETE' && p.url.path.endsWith('/schedule-end'),
        ),
        hasLength(1),
      );

      expect(find.textContaining('Se quitó la fecha'), findsOneWidget);
    });

    testWidgets('«Renovar / extender» mueve la fecha a la ruta de programar', (
      tester,
    ) async {
      final pedidas = await montar(
        tester,
        servicioActual: ficha(termino: '2027-03-31'),
        puedeTocarPrecios: true,
        // POST Y NO PUT: programar un término es `POST …/schedule-end`, que es lo que ya
        // usaba «Programar». Renovar reusa esa ruta a propósito —es el mismo acto— en vez
        // de estrenar una.
        responder: (p) =>
            p.metodo == 'POST' && p.url.path.endsWith('/schedule-end')
            ? http.Response(jsonEncode(ficha(termino: '2027-03-15')), 200)
            : null,
      );

      await tester.tap(find.text('Renovar / extender'));
      await tester.pumpAndSettle();

      // ⚠️ **SE TOCA EL CAMPO, NO LA ETIQUETA:** `RisegDateField` pinta el `Text` de la
      // etiqueta y el campo como HERMANOS, así que tocar la etiqueta no abre nada y el
      // fallo se lee como «no encuentro el día 15». Desde C3 el campo lleva llave, que es
      // más corto de escribir y no se rompe al reordenar el diálogo.
      await tester.tap(
        find
            .descendant(
              of: find.byKey(const Key('renovacion-termino')),
              matching: find.byType(TextField),
            )
            .first,
      );
      await tester.pumpAndSettle();

      // El selector abre en el mes de la fecha cargada —marzo de 2027—, así que el 15
      // está a la vista sin navegar.
      await tester.tap(find.text('15'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // Los dos pasos que C3 añadió: los precios —que aquí no hay— y el resumen.
      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      final puesta = pedidas.singleWhere(
        (p) => p.metodo == 'POST' && p.url.path.endsWith('/schedule-end'),
      );

      expect(jsonDecode(puesta.cuerpo), {'endedOn': '2027-03-15'});
      expect(find.textContaining('Se movió la fecha'), findsOneWidget);
    });

    testWidgets('🚫 CON PRECIOS ES UNA SOLA PETICIÓN A /renew, no N', (
      tester,
    ) async {
      // La línea que cobra, con su condición vigente y su VERSIÓN. Es el escenario de una
      // renovación de verdad: hasta el 14-nov-2026 esto se hacía con 1 + N peticiones.
      const lineaId = '0193f0aa-0000-7000-8000-000000000001';
      final lineaQueCobra = {
        'id': lineaId,
        'serviceId': servicio,
        'name': 'Guardias intramuros',
        'status': 'active',
        'updatedAt': '2026-11-01T18:00:00Z',
      };

      final condicionVigente = {
        'id': '0193f0aa-0000-7000-8000-000000000002',
        'commercialLineId': lineaId,
        'temporality': 'current',
        'startsOn': '2026-01-01',
        'endsOn': '2027-03-31',
        'positionId': '0193f0aa-0000-7000-8000-000000000003',
        'shiftModalityId': null,
        'shiftPeriod': null,
        'headcount': 3,
        'unitPriceMinor': 1500000,
        'currency': 'MXN',
        'taxTreatment': 'mas_iva',
        'description': null,
        'version': 4,
        'schedules': const [],
        'updatedAt': '2026-11-01T18:00:00Z',
      };

      final pedidas = await montar(
        tester,
        servicioActual: ficha(termino: '2027-03-31'),
        puedeTocarPrecios: true,
        responder: (p) {
          if (p.url.path.endsWith('/commercial-lines')) {
            return http.Response(jsonEncode([lineaQueCobra]), 200);
          }

          if (p.url.path.endsWith('/terms')) {
            return http.Response(jsonEncode([condicionVigente]), 200);
          }

          if (p.metodo == 'POST' && p.url.path.endsWith('/renew')) {
            return http.Response(
              jsonEncode({
                'service': ficha(termino: '2028-03-31'),
                'terms': [condicionVigente],
              }),
              200,
            );
          }

          return null;
        },
      );

      await tester.tap(find.text('Renovar / extender'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();

      // LA SALIDA «PRECIO NUEVO» SE ELIGE: por omisión la línea sigue con el mismo precio,
      // así que sin esto el campo de importe no existe.
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('renovacion-decision-$lineaId')),
          matching: find.byWidgetPredicate((w) => w is DropdownButtonFormField),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Precio nuevo').last);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('renovacion-precio-$lineaId')),
          matching: find.byType(TextFormField),
        ),
        '16500',
      );

      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      // 🚫 **UNA SOLA ESCRITURA, Y NINGUNA A LAS RUTAS VIEJAS.** Si esto volviera a ser una
      // secuencia, el servicio podría quedar renovado con la mitad de los precios puestos.
      expect(
        pedidas.where((p) => p.metodo == 'POST' && p.url.path.endsWith('/renew')),
        hasLength(1),
      );

      expect(
        pedidas.where((p) => p.url.path.endsWith('/schedule-end')),
        isEmpty,
      );

      expect(
        pedidas.where((p) => p.url.path.endsWith('/schedule-next')),
        isEmpty,
      );

      // Y EL CUERPO QUE DE VERDAD VIAJA, campo por campo: es lo que dos suites verdes no
      // prueban. La fecha de los precios es **el día siguiente al término de hoy**.
      final renovacion = pedidas.singleWhere(
        (p) => p.metodo == 'POST' && p.url.path.endsWith('/renew'),
      );

      expect(jsonDecode(renovacion.cuerpo), {
        'removeEnd': false,
        'endedOn': '2027-03-31',
        'pricesStartOn': '2027-04-01',
        'prices': [
          {
            'lineId': lineaId,
            'unitPriceMinor': 1650000,
            // ⚠️ LA VERSIÓN DE LA CONDICIÓN, no un cero: sin ella el servidor responde 400,
            // y con un cero inventado pisaría el precio de alguien más.
            'expectedVersion': 4,
          },
        ],
      });

      expect(find.textContaining('Renovado.'), findsOneWidget);
    });

    testWidgets('🚫 DAR DE BAJA UNA LÍNEA viaja como `terminate`, SIN precio', (
      tester,
    ) async {
      const lineaId = '0193f0aa-0000-7000-8000-000000000001';
      final lineaQueCobra = {
        'id': lineaId,
        'serviceId': servicio,
        'name': 'Supervisor',
        'status': 'active',
        'updatedAt': '2026-11-01T18:00:00Z',
      };

      final condicionVigente = {
        'id': '0193f0aa-0000-7000-8000-000000000002',
        'commercialLineId': lineaId,
        'temporality': 'current',
        'startsOn': '2026-01-01',
        'endsOn': '2027-03-31',
        'positionId': '0193f0aa-0000-7000-8000-000000000003',
        'shiftModalityId': null,
        'shiftPeriod': null,
        'headcount': 1,
        'unitPriceMinor': 2000000,
        'currency': 'MXN',
        'taxTreatment': 'mas_iva',
        'description': null,
        'version': 2,
        'schedules': const [],
        'updatedAt': '2026-11-01T18:00:00Z',
      };

      final pedidas = await montar(
        tester,
        servicioActual: ficha(termino: '2027-03-31'),
        puedeTocarPrecios: true,
        responder: (p) {
          if (p.url.path.endsWith('/commercial-lines')) {
            return http.Response(jsonEncode([lineaQueCobra]), 200);
          }

          if (p.url.path.endsWith('/terms')) {
            return http.Response(jsonEncode([condicionVigente]), 200);
          }

          if (p.metodo == 'POST' && p.url.path.endsWith('/renew')) {
            return http.Response(
              jsonEncode({
                'service': ficha(termino: '2028-03-31'),
                'terms': const [],
                'terminated': [
                  {...lineaQueCobra, 'status': 'retired'},
                ],
              }),
              200,
            );
          }

          return null;
        },
      );

      await tester.tap(find.text('Renovar / extender'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('renovacion-decision-$lineaId')),
          matching: find.byWidgetPredicate((w) => w is DropdownButtonFormField),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dar de baja al término').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      final renovacion = pedidas.singleWhere(
        (p) => p.metodo == 'POST' && p.url.path.endsWith('/renew'),
      );

      // 🚫 **SIN `unitPriceMinor`**, y es lo que esta prueba defiende: mandar los dos es una
      // contradicción y el servidor contesta 400 en lugar de tirar uno en silencio.
      expect(jsonDecode(renovacion.cuerpo), {
        'removeEnd': false,
        'endedOn': '2027-03-31',
        'pricesStartOn': '2027-04-01',
        'prices': [
          {'lineId': lineaId, 'expectedVersion': 2, 'terminate': true},
        ],
      });

      // Y EL AVISO LO CONFIRMA: una baja que nadie confirma es una baja silenciosa.
      expect(
        find.textContaining('Una línea se dio de baja al término'),
        findsOneWidget,
      );
    });

    testWidgets('🚫 REACTIVAR UN TERMINADO QUE COBRABA PASA POR RENOVAR, en una petición', (
      tester,
    ) async {
      // El servicio paró el 30 de junio y su línea cobraba HASTA ese día: reactivarlo sin
      // reprogramar el precio lo dejaría operando sin cobrar.
      const lineaId = '0193f0aa-0000-7000-8000-000000000001';
      final lineaQueCobraba = {
        'id': lineaId,
        'serviceId': servicio,
        'name': 'Vigilancia',
        'status': 'active',
        'updatedAt': '2026-07-01T18:00:00Z',
      };

      final ultimaCondicion = {
        'id': '0193f0aa-0000-7000-8000-000000000002',
        'commercialLineId': lineaId,
        'temporality': 'past',
        'startsOn': '2026-01-01',
        'endsOn': '2026-06-30',
        'positionId': '0193f0aa-0000-7000-8000-000000000003',
        'shiftModalityId': null,
        'shiftPeriod': null,
        'headcount': 3,
        'unitPriceMinor': 1500000,
        'currency': 'MXN',
        'taxTreatment': 'mas_iva',
        'description': null,
        'version': 5,
        'schedules': const [],
        'updatedAt': '2026-07-01T18:00:00Z',
      };

      final pedidas = await montar(
        tester,
        servicioActual: ficha(
          estatus: 'terminated',
          condicion: 'expired',
          termino: '2026-06-30',
        ),
        puedeTocarPrecios: true,
        responder: (p) {
          if (p.url.path.endsWith('/commercial-lines')) {
            return http.Response(jsonEncode([lineaQueCobraba]), 200);
          }

          if (p.url.path.endsWith('/terms')) {
            return http.Response(jsonEncode([ultimaCondicion]), 200);
          }

          if (p.metodo == 'POST' && p.url.path.endsWith('/renew')) {
            return http.Response(
              jsonEncode({
                'service': ficha(termino: '2027-06-30'),
                'terms': [ultimaCondicion],
                'terminated': const [],
              }),
              200,
            );
          }

          return null;
        },
      );

      await tester.tap(find.text('Cambiar estatus'));
      await tester.pumpAndSettle();

      // EN UN TERMINADO LA OPCIÓN SE LLAMA «Reactivar», no «Activo».
      await tester.tap(find.text('Reactivar'));
      await tester.pumpAndSettle();

      // ⚠️ **ABRE EL DIÁLOGO DE RENOVAR, no el de motivo a secas**, y lo dice en su título:
      // reactivar un servicio que cobraba es renovarlo.
      expect(find.text('Reactivar · hasta cuándo'), findsOneWidget);
      expect(find.textContaining('paró el 30/jun/2026'), findsOneWidget);

      // ⚠️ **LA FECHA NACE VACÍA al reactivar** —la que tenía ya pasó y el campo no admite
      // el pasado—, así que aquí se reactiva **sin fecha de fin**, que es una salida
      // legítima: el cliente volvió y todavía no hay término pactado.
      await tester.tap(find.text('Se renovó sin fecha de fin'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();

      // Y DICE «COBRABA», no «Hoy»: en un servicio que paró, hoy no cobra nada.
      expect(find.textContaining('Cobraba \$15,000.00 MXN'), findsOneWidget);

      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();

      expect(find.textContaining('El servicio vuelve a operar'), findsOneWidget);

      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      // EL MOTIVO, que reactivar sigue exigiendo.
      await tester.enterText(find.byType(TextField).last, 'El cliente volvió');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reactivar').last);
      await tester.pumpAndSettle();

      // 🚫 **UNA SOLA PETICIÓN, Y A `/renew`: NINGUNA A `/status`.** Reactivar por estatus
      // dejaría el servicio operando sin cobrar, y el servidor lo rechaza con 409.
      final renovacion = pedidas.singleWhere(
        (p) => p.metodo == 'POST' && p.url.path.endsWith('/renew'),
      );

      expect(pedidas.where((p) => p.url.path.endsWith('/status')), isEmpty);

      final cuerpo = jsonDecode(renovacion.cuerpo) as Map<String, dynamic>;

      expect(cuerpo['reactivate'], isTrue);
      expect(cuerpo['reason'], 'El cliente volvió');
      expect(cuerpo['removeEnd'], isTrue);

      // 🚫 SIN `endedOn`: «retírala» y «ponla el 30 de junio» no se pueden cumplir las dos, y
      // mandar las dos es lo que el servidor rechaza con 400.
      expect(cuerpo.containsKey('endedOn'), isFalse);

      expect(cuerpo['prices'], [
        {'lineId': lineaId, 'unitPriceMinor': 1500000, 'expectedVersion': 5},
      ]);

      expect(find.textContaining('Reactivado.'), findsOneWidget);
    });

    testWidgets('🚫 SIN PERMISO DE PRECIOS NO SE OFRECE RENOVAR, sólo mover la fecha', (
      tester,
    ) async {
      // ⚠️ **UNA SOLA REGLA, LA MISMA QUE EL SERVIDOR.** `POST …/renew` exige `manage` Y
      // `pricing.manage` porque reprograma el precio de cada línea, así que ofrecer
      // «Renovar» sin el segundo sería ofrecer un 403. Lo que sí se puede es mover la
      // fecha, y eso es «Programar».
      await montar(
        tester,
        servicioActual: ficha(termino: '2027-03-31'),
      );

      expect(find.text('Renovar / extender'), findsNothing);
      expect(find.text('Programar'), findsOneWidget);

      // Y SE DICE POR QUÉ, en lugar de esconder el botón sin explicación.
      expect(
        find.textContaining('pide permiso de precios'),
        findsOneWidget,
      );
    });

    testWidgets('🚫 Y «Programar» SIN PERMISO DE PRECIOS NO PUEDE ALARGAR, sólo acortar', (
      tester,
    ) async {
      // ⚠️ La razón es la que el dueño señaló el 14-nov-2026: **alargar el término no alarga
      // las condiciones**, así que el servicio operaría el periodo nuevo con sus líneas
      // muertas en la fecha vieja. El servidor contesta 409 `renovacion_requerida`; el
      // selector no deja llegar ahí.
      await montar(
        tester,
        servicioActual: ficha(termino: '2027-03-31'),
      );

      await tester.tap(find.text('Programar'));
      await tester.pumpAndSettle();

      final campo = tester.widget<RisegDateField>(find.byType(RisegDateField));

      expect(campo.lastDate, DateTime(2027, 3, 31));

      expect(
        find.textContaining('no más allá del término que ya tiene'),
        findsOneWidget,
      );
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
  // 🚫 EL NÚMERO VIEJO DE LA CAMPANA — la falla del 13 de noviembre de 2026
  // =========================================================================
  //
  // El dueño quitó la fecha de término de un servicio y **la campana siguió diciendo
  // «1»** hasta que la volvió a abrir. Abrirla sí relee —los avisos se derivan al leer—,
  // pero el número se lee **sin abrir nada**, y un número viejo es peor que ninguno:
  // se cree.
  //
  // ⚠️ **ESTAS TRES ACCIONES NO CAMBIAN DE PANTALLA**, así que nadie de fuera se entera.
  // Por eso la pantalla avisa, y por eso el aviso es un parámetro **obligatorio**: lo que
  // se puede olvidar se olvida, y el síntoma se ve igual que todo bien.
  group('lo que mueve el término avisa a la campana', () {
    testWidgets('🚫 QUITAR LA FECHA DE TÉRMINO avisa', (tester) async {
      await montar(
        tester,
        servicioActual: ficha(termino: '2027-03-31'),
        // Con permiso de precios, que es lo que «Renovar / extender» exige desde el
        // 14-nov-2026: quitar la fecha se hace desde ese diálogo.
        puedeTocarPrecios: true,
        responder: (p) =>
            p.metodo == 'DELETE' && p.url.path.endsWith('/schedule-end')
            ? http.Response(jsonEncode(ficha()), 200)
            : null,
      );

      expect(avisosReleidos, 0, reason: 'cargar la ficha no mueve nada');

      await tester.tap(find.text('Renovar / extender'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Se renovó sin fecha de fin'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(avisosReleidos, 1);
    });

    testWidgets('🚫 CAMBIAR EL ESTATUS avisa', (tester) async {
      await montar(
        tester,
        responder: (p) => p.metodo == 'POST' && p.url.path.endsWith('/status')
            ? http.Response(
                jsonEncode(ficha(estatus: 'suspended', condicion: 'inforce')),
                200,
              )
            : null,
      );

      await tester.tap(find.text('Cambiar estatus'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Suspendido'));
      await tester.pumpAndSettle();

      await escribir(tester, 'Motivo del cambio', 'Lo pidió el cliente');
      await tester.tap(find.widgetWithText(InkWell, 'Cambiar el estatus').last);
      await tester.pumpAndSettle();

      expect(avisosReleidos, 1);
    });

    testWidgets('corregir el NOMBRE no avisa: no cambia a quién avisar', (
      tester,
    ) async {
      // 🚫 **LA FRONTERA.** Una relectura por cada guardado sería un sondeo con otro
      // nombre: renombrar un servicio no lo acerca ni lo aleja de su término.
      final pedidas = await montar(tester, editando: true);

      await escribir(tester, 'Nombre del servicio', 'Sportium Satélite Norte');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      await escribir(tester, 'Motivo de la corrección', 'Cambió el rótulo');
      await tester.tap(find.widgetWithText(InkWell, 'Guardar').last);
      await tester.pumpAndSettle();

      expect(
        correcciones(pedidas),
        hasLength(1),
        reason: 'la corrección tiene que haber salido, o esto no prueba nada',
      );
      expect(avisosReleidos, 0);
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
      await abrirPestana(tester, 'Vínculos');

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

      await abrirPestana(tester, 'Vínculos');

      // LA ETIQUETA YA NO VA EN VERSALES: el estilo B pinta el dato como lista de
      // definición —etiqueta a la izquierda, valor a la derecha— y la etiqueta se escribe
      // como se lee.
      // ⚠️ **«RAZÓN SOCIAL», UN SOLO TÉRMINO EN TODA LA INTERFAZ** desde el 12 de
      // noviembre de 2026: la pestaña, el título de la sección y esta fila decían tres
      // cosas distintas para lo mismo. «Entidad fiscal» se queda en el contrato y en el
      // código, que es donde significa algo.
      await tester.tap(botonDelVinculo('Razón social', 'Asignar'));
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Sportium SA de CV'));
      await tester.pumpAndSettle();

      // MARCAR NO ES ASIGNAR: la fila marca y el botón decide.
      expect(
        pedidas.where((p) => p.url.path.endsWith('/fiscal-entity')),
        isEmpty,
      );

      await tester.tap(find.text('Asignar').last);
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

  // =========================================================================
  // Guardar y volver, CON EL ROUTER DE VERDAD
  // =========================================================================
  //
  // 🚫 **LA FALLA DEL 12 DE NOVIEMBRE DE 2026, en la pantalla hermana.** El dueño la vio
  // en el expediente de un cliente: guardaba, leía «Se guardó», la pantalla **se quedaba
  // en `/editar`** y al salir le preguntaban si quería tirar lo que acababa de guardar.
  //
  // ⚠️ **NINGUNA PRUEBA DE ESTE ARCHIVO PODÍA VERLO**, y por una razón que conviene dejar
  // escrita: `montar` pone la pantalla **sin router**, así que `alIrADentro` sólo anota en
  // una lista y **nadie consulta a la guardia**. El cruce —guardar, navegar, y que el
  // `onExit` pregunte— no existía en ningún sitio.
  group('guardar vuelve a la consulta y no pregunta', () {
    testWidgets('🚫 con el `onExit` puesto, guardar NO deja la pantalla atrás', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final (api, _) = await cliente(servicioActual: ficha());
      final guardia = GuardiaDeSalida();

      ExpedienteServicioWebScreen pantalla(
        BuildContext contexto, {
        required bool editando,
      }) => ExpedienteServicioWebScreen(
        repositorio: ServiciosRepositorioHttp(api),
        clientes: ClientesRepositorioHttp(api),
        sucursales: SucursalesRepositorioHttp(api),
        empleados: EmpleadosRepositorioHttp(api),
        empresaId: empresa,
        servicioId: servicio,
        capacidades: todo,
        puedeElegirSupervisor: true,
        condiciones: CondicionesRepositorioHttp(api),
        puestos: PuestosRepositorioHttp(api),
        areas: AreasRepositorioHttp(api),
        puedeTocarPrecios: false,
        puedeVerSueldos: false,
        guardia: guardia,
        editando: editando,
        alIrADentro: (aDonde) => contexto.go(
          '/comercial/servicios/$servicio${aDonde == null ? '' : '/$aDonde'}',
        ),
        alVolver: () {},
        alConocerElNombre: (_, _) {},
        // Este grupo mide el `onExit` al guardar; mover el término no entra.
        alMoverElTermino: () {},
        hoy: () => hoy,
      );

      // LAS RUTAS CON `onExit`, como el router de verdad: ahí son planas —`/` y el
      // comodín—, así que pasar de `…/editar` a `…/<id>` dispara la pregunta.
      final router = GoRouter(
        initialLocation: '/comercial/servicios/$servicio/editar',
        routes: [
          GoRoute(
            path: '/comercial/servicios/:id',
            onExit: (contexto, _) => seguroDeSalir(contexto, guardia),
            builder: (contexto, _) => pantalla(contexto, editando: false),
            routes: [
              GoRoute(
                path: 'editar',
                onExit: (contexto, _) => seguroDeSalir(contexto, guardia),
                builder: (contexto, _) => pantalla(contexto, editando: true),
              ),
            ],
          ),
        ],
      );

      addTearDown(router.dispose);

      await tester.pumpWidget(
        MaterialApp.router(theme: MarcaSeventra.tema(), routerConfig: router),
      );
      await tester.pumpAndSettle();

      await escribir(tester, 'Nombre del servicio', 'Sportium Satélite Norte');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      await escribir(tester, 'Motivo de la corrección', 'Cambió el rótulo');
      await tester.tap(find.widgetWithText(InkWell, 'Guardar').last);
      await tester.pumpAndSettle();

      // NI UN DIÁLOGO, y la dirección es la de la consulta.
      expect(find.text('¿Salir sin guardar?'), findsNothing);
      expect(router.state.uri.path, '/comercial/servicios/$servicio');

      // Y LA GUARDIA QUEDÓ LIMPIA: es lo que de verdad se rompió.
      expect(guardia.hayCambiosSinGuardar, isFalse);
    });
  });
}
