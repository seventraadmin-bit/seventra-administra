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
import 'package:riseg_one/core/trabajo_sin_guardar/guardia_de_salida.dart';
import 'package:riseg_one/core/config/api_config.dart';
import 'package:riseg_one/core/design_system/design_system_web.dart';
import 'package:riseg_one/core/logging/app_logger.dart';
import 'package:riseg_one/app/shell/apartados_web.dart' show CapacidadesDeModulo;
import 'package:riseg_one/features/organizacion/web/datos/expedientes_repositorio_http.dart';
import 'package:riseg_one/features/organizacion/web/datos/logotipo_repositorio_http.dart';
import 'package:riseg_one/features/organizacion/web/datos/sucursales_repositorio_http.dart';
import 'package:riseg_one/features/organizacion/web/modelos/expediente.dart';
import 'package:riseg_one/features/organizacion/web/modelos/sucursal.dart';
import 'package:riseg_one/features/organizacion/web/modelos/tipo_de_sucursal.dart';
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
  const tipoId = '0193f0a0-0000-7000-8000-0000000000d1';

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

  /// El cliente autenticado del último [construir].
  ///
  /// **POR QUÉ UNA VARIABLE Y NO UN CAMPO MÁS DEL REGISTRO.** El expediente de una
  /// sucursal necesita **dos** repositorios desde que concentra todo: el del
  /// expediente para guardar, y el de la estructura para cerrar, reabrir, desactivar y
  /// eliminar. Añadir `sucursales:` al registro que devuelve [construir] rompería las
  /// treinta desestructuraciones `final (repo: repo, vistas: _) = …` de este archivo,
  /// porque un registro de tres campos no es subtipo de uno de dos.
  ///
  /// Las pruebas corren una después de otra y cada una llama a [construir] antes de
  /// montar, así que esto siempre vale lo de la prueba en curso.
  ApiClientAutenticado? clienteDelUltimoConstruir;

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

    final autenticado = ApiClientAutenticado(cliente: desnudo, gestor: sesion);

    // SE GUARDA PARA EL REPOSITORIO DE LA ESTRUCTURA, que `montarSucursal` construye
    // sobre EL MISMO cliente: así las peticiones de los dos repositorios caen en la
    // misma lista de `vistas` y una prueba puede afirmar sobre las dos.
    clienteDelUltimoConstruir = autenticado;

    return (
      repo: ExpedientesRepositorioHttp(autenticado),
      vistas: vistas,
    );
  }

  String empresaJson({
    int version = 2,
    String? razonSocial = 'Seguridad Privada RISEG S.A. de C.V.',
    String? rfc = 'SPR950101AB1',
    // SE PUEDE PEDIR SIN RÉGIMEN, y hace falta: con uno puesto, cambiar el RFC a otro
    // tipo de persona dispara el aviso de que no corresponde — y un aviso tapa la
    // ayuda del campo, porque `InputDecoration` esconde `helperText` cuando hay
    // `errorText`. La prueba de la ayuda necesita un expediente sin contradicción.
    String? regimen = '601',
    Map<String, dynamic>? direccion,
    bool tarjetaLista = false,
  }) => jsonEncode({
    'companyId': empresa,
    'name': 'RISEG',
    'legalName': razonSocial,
    'taxId': rfc,
    'legalRep': 'Juan Pérez',
    'slogan': null,
    'fiscalRegimeCode': regimen,
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
    String? nombre = 'Matriz',
    // `tipo` Y NO `tipoId`, porque el `const tipoId` de arriba es su valor por
    // omisión y un parámetro con el mismo nombre lo taparía.
    String? tipo = tipoId,
    Map<String, dynamic>? direccion,
  }) => jsonEncode({
    'branchId': sucursalId,
    'code': 'MATRIZ',
    'name': nombre,
    // EL TIPO VIAJA DESDE EL 21 DE OCTUBRE DE 2026: el expediente ahora lo guarda,
    // así que la respuesta lo trae.
    //
    // **PUEDE SER NULO**, y no es un hueco de la prueba: la columna es anulable desde
    // la 0048 porque las sucursales dadas de alta antes de que existieran los tipos no
    // tienen ninguno.
    'branchTypeId': tipo,
    'address': direccion,
    'schedule': horario,
    'profileVersion': version,
  });

  /// El campo que lleva esta etiqueta.
  ///
  /// ⚠️ **NO SIRVE `find.ancestor(of: find.text(etiqueta), matching:
  /// find.byType(TextField))`**, y cuesta un rato verlo: `RisegTextField` pinta un
  /// `Text(label)` y **debajo** su campo, los dos hermanos en la misma `Column`. El
  /// campo no es ancestro de su etiqueta, así que ese buscador no encuentra nada y la
  /// prueba muere con un `StateError` que no nombra ni el campo ni la etiqueta.
  ///
  /// Del texto se sube a la `Column` más cercana y de ahí se baja al campo, que es lo
  /// que permite preguntar por UNO concreto en vez de por todos los de la pantalla.
  TextField campoDe(WidgetTester tester, String etiqueta) =>
      tester.widget<TextField>(
        find
            .descendant(
              of: find
                  .ancestor(
                    of: find.text(etiqueta),
                    matching: find.byType(Column),
                  )
                  .first,
              matching: find.byType(TextField),
            )
            .first,
      );

  /// El buscador del campo que lleva esta etiqueta, para escribir en él.
  ///
  /// **`find.byType(TextField).first` NO SIRVE en el expediente de la empresa**: su
  /// primer campo no es siempre el que la prueba quiere, y escribir en el equivocado
  /// pasa sin quejarse.
  Finder campoDeTexto(WidgetTester tester, String etiqueta) => find
      .descendant(
        of: find
            .ancestor(of: find.text(etiqueta), matching: find.byType(Column))
            .first,
        matching: find.byType(TextField),
      )
      .first;

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

  /// Lo último que `alGuardar` recibió, para las pruebas que miden el cierre.
  ExpedienteDeEmpresa? guardado;

  /// Cuántas veces se pidió cancelar.
  var canceles = 0;

  /// Monta **el formulario de editar** del expediente de la empresa.
  ///
  /// ⚠️ **ES UN MODO, NO LA PESTAÑA.** Desde el 21 de octubre de 2026 la pestaña
  /// Empresa es lista → ficha → editar (`EmpresasWebScreen`), y esto es el tercer
  /// paso. Guardar **no se queda aquí**: avisa al llamador, que cierra y vuelve a la
  /// ficha — por eso estas pruebas miden [guardado] y no lo que el formulario pinte
  /// después.
  Future<void> montarEmpresa(
    WidgetTester tester,
    ExpedientesRepositorioHttp repo, {
    bool puedeEditar = true,
  }) async {
    ventanaAlta(tester);

    guardado = null;
    canceles = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: MarcaSeventra.tema(),
        home: Scaffold(
          body: EmpresaWebScreen(
            repositorio: repo,
            logotipos: LogotipoRepositorioHttp(clienteDelUltimoConstruir!),
            empresaId: empresa,
            puedeEditar: puedeEditar,
            alGuardar: (e) => guardado = e,
            alCancelar: () => canceles++,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
  }

  /// La sucursal de la lista que abre el expediente.
  ///
  /// **De aquí salen los dos estados que el expediente no trae** —si está activa y si
  /// está operando—, que son los que gobiernan las acciones del encabezado.
  Sucursal sucursalDeLaLista({
    bool activa = true,
    String estadoOperativo = 'operando',
  }) => Sucursal(
    id: sucursalId,
    codigo: 'SUC-0001',
    nombre: 'Centro',
    activa: activa,
    tipoId: tipoId,
    estadoOperativo: estadoOperativo,
  );

  /// Monta el expediente de una sucursal.
  ///
  /// ⚠️ **DOS PERMISOS Y NO UNO, y es el cambio del 21 de octubre de 2026.** Antes
  /// esta pantalla recibía un solo `puedeEditar` —`company.settings.manage`— porque
  /// sólo tenía domicilio y horario. Ahora tiene también el nombre y el tipo, que son
  /// **estructura** (`organizacion.modificar`), y las tres operaciones de estado. Un
  /// solo interruptor para las dos familias habría movido el renombrado de una
  /// sucursal al permiso del expediente fiscal.
  Future<void> montarSucursal(
    WidgetTester tester,
    ExpedientesRepositorioHttp repo, {
    CapacidadesDeModulo capacidades = const CapacidadesDeModulo(
      puedeVer: true,
      puedeCrear: true,
      puedeModificar: true,
      puedeArchivar: true,
    ),
    bool puedeEditarExpedientes = true,
    bool esMaestro = false,
    Sucursal? sucursal,
    SucursalesRepositorioHttp? repositorioDeSucursales,
    void Function(Sucursal)? alCambiar,
    VoidCallback? onVolver,
  }) async {
    ventanaAlta(tester);

    await tester.pumpWidget(
      MaterialApp(
        theme: MarcaSeventra.tema(),
        home: Scaffold(
          body: ExpedienteSucursalWebScreen(
            repositorio: repo,
            // EL MISMO CLIENTE PARA LOS DOS REPOSITORIOS: lo simulado es el
            // transporte, así que las peticiones de los dos caen en el mismo
            // interceptor y se ven en la misma lista de vistas.
            repositorioDeSucursales:
                repositorioDeSucursales ??
                SucursalesRepositorioHttp(clienteDelUltimoConstruir!),
            empresaId: empresa,
            sucursal: sucursal ?? sucursalDeLaLista(),
            tipos: const [
              TipoDeSucursal(
                id: tipoId,
                codigo: 'OFI',
                nombre: 'Oficina',
                activo: true,
              ),
            ],
            capacidades: capacidades,
            esMaestro: esMaestro,
            puedeEditarExpedientes: puedeEditarExpedientes,
            onVolver: onVolver ?? () {},
            // D-56 · UNO PROPIO: aquí se mide el formulario, y nadie le pregunta al
            // guardia. Que la pantalla registre lo que tiene que perder lo fija
            // `expediente_declara_sus_cambios_test.dart`.
            guardia: GuardiaDeSalida(),
            alCambiar: alCambiar,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
  }

  // =========================================================================
  // 1 · EL EXPEDIENTE DE LA EMPRESA
  // =========================================================================

  group('Editar el expediente de la empresa', () {
    testWidgets('guardar CIERRA, y lleva el expediente que el PUT devolvió', (
      tester,
    ) async {
      // ⚠️ **CERRAR AL GUARDAR ES LA REGLA DEL RECORRIDO**, y la ficha se pinta con lo
      // que la respuesta trajo: pedirlo otra vez sería una petición que no puede traer
      // nada nuevo.
      final (repo: repo, vistas: _) = await construir((p) async {
        if (p.url.path.endsWith('/fiscal-regimes')) {
          return http.Response(catalogoJson(), 200);
        }

        return p.method == 'GET'
            ? http.Response(empresaJson(), 200)
            : http.Response(empresaJson(version: 3, razonSocial: 'Ya guardada'), 200);
      });

      await montarEmpresa(tester, repo);

      await tester.tap(find.text('Guardar expediente'));
      await tester.pumpAndSettle();

      expect(guardado, isNotNull);
      expect(guardado!.razonSocial, 'Ya guardada');
      expect(guardado!.version, 3);
    });

    testWidgets('un guardado que FALLA no cierra', (tester) async {
      // Cerrar con un error pendiente dejaría a la persona en la ficha sin saber que
      // su cambio no entró.
      final (repo: repo, vistas: _) = await construir((p) async {
        if (p.url.path.endsWith('/fiscal-regimes')) {
          return http.Response(catalogoJson(), 200);
        }

        return p.method == 'GET'
            ? http.Response(empresaJson(), 200)
            : http.Response(
                jsonEncode({
                  'code': 'entrada_invalida',
                  'message': 'Revisa los campos señalados.',
                  'fields': [
                    {'field': 'taxId', 'message': 'El RFC no tiene la forma.'},
                  ],
                }),
                400,
              );
      });

      await montarEmpresa(tester, repo);

      await tester.tap(find.text('Guardar expediente'));
      await tester.pumpAndSettle();

      expect(guardado, isNull, reason: 'Se cerró con un error pendiente.');
      expect(find.text('El RFC no tiene la forma.'), findsOneWidget);
    });

    testWidgets('el NOMBRE COMERCIAL se manda, y sin permiso NO', (tester) async {
      // ⚠️ NULO ES «NO LO TOQUES», no «bórralo»: la columna es NOT NULL. Así que quien
      // no puede editar no lo manda, y el servidor no tiene que exigirle un permiso
      // por un campo que no quiso cambiar.
      final (repo: repo, vistas: vistas) = await construir((p) async {
        if (p.url.path.endsWith('/fiscal-regimes')) {
          return http.Response(catalogoJson(), 200);
        }

        return p.method == 'GET'
            ? http.Response(empresaJson(), 200)
            : http.Response(empresaJson(version: 3), 200);
      });

      // 1 · CON PERMISO: el campo existe, se edita y viaja.
      await montarEmpresa(tester, repo);

      expect(campoDe(tester, 'Nombre comercial').enabled, isTrue);

      await tester.enterText(
        campoDeTexto(tester, 'Nombre comercial'),
        'RISEG Servicios',
      );
      await tester.tap(find.text('Guardar expediente'));
      await tester.pumpAndSettle();

      final conPermiso =
          jsonDecode(vistas.lastWhere((v) => v.method == 'PUT').body)
              as Map<String, dynamic>;

      expect(conPermiso['name'], 'RISEG Servicios');

      // 2 · SIN PERMISO: no se manda la clave.
      vistas.clear();
      await montarEmpresa(tester, repo, puedeEditar: false);

      expect(campoDe(tester, 'Nombre comercial').enabled, isFalse);

      // Sin permiso no hay botón de guardar, así que la petición no se puede provocar
      // desde la pantalla. Lo que se mide aquí es que el campo salga de sólo lectura,
      // que es la mitad que la pantalla decide; que el servidor lo exija lo fija
      // `CompanyProfileTests` del backend.
      expect(find.text('Guardar expediente'), findsNothing);
      expect(find.text('Volver'), findsOneWidget);
    });

    testWidgets('cancelar avisa al llamador, que es quien pregunta', (
      tester,
    ) async {
      // LA PREGUNTA DE «HAY CAMBIOS SIN GUARDAR» NO VIVE AQUÍ: hace falta también al
      // tocar otra empresa en la lista, y tenerla en dos sitios serían dos textos que
      // divergen. El formulario sólo avisa.
      final (repo: repo, vistas: _) = await construir((p) async {
        if (p.url.path.endsWith('/fiscal-regimes')) {
          return http.Response(catalogoJson(), 200);
        }

        return http.Response(empresaJson(), 200);
      });

      await montarEmpresa(tester, repo);

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(canceles, 1);
    });
  });

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

      // ⚠️ Y AL EDITAR, EL ERROR DE ESE CAMPO SE VA — Y SÓLO EL DE ESE CAMPO.
      //
      // Se encontró probando el ensayo: el error sólo se limpiaba al volver a guardar,
      // así que mientras la persona corregía el RFC seguía leyendo que estaba mal.
      // Con un RFC ya válido delante, el mensaje viejo convierte la pantalla en una
      // mentirosa, y a partir de ahí los mensajes dejan de creerse.
      await tester.enterText(campoDeTexto(tester, 'RFC'), 'XAXX010101000');
      await tester.pumpAndSettle();

      expect(find.text('El RFC no tiene la forma correcta.'), findsNothing);

      // EL DEL CÓDIGO POSTAL SIGUE, porque nadie lo ha tocado. Limpiarlos todos de
      // golpe escondería problemas que no se han corregido.
      expect(find.text('El código postal son cinco dígitos.'), findsOneWidget);
    });

    testWidgets('un RFC pegado CON ESPACIOS llega al servidor sin ellos', (
      tester,
    ) async {
      // AL PEGAR ES FÁCIL LLEVARSE UN ESPACIO, y un RFC de 13 caracteres con uno
      // delante son 14: el servidor lo rechazaría por longitud y el mensaje hablaría de
      // contar caracteres cuando lo que sobra es un espacio invisible.
      //
      // Se recortan los extremos en los DOS lados —aquí al mandar, y en el servidor al
      // leer—, y esto fija el de aquí: lo que viaja es lo que se ve.
      //
      // 🚫 LOS DE EN MEDIO NO SE TOCAN: un RFC no los lleva nunca, así que quitarlos en
      // silencio sería cambiar lo que alguien escribió en vez de decírselo.
      final (repo: repo, vistas: vistas) = await construir((p) async {
        if (p.url.path.endsWith('/fiscal-regimes')) {
          return http.Response(catalogoJson(), 200);
        }

        return p.method == 'GET'
            ? http.Response(empresaJson(), 200)
            : http.Response(empresaJson(version: 3), 200);
      });

      await montarEmpresa(tester, repo);

      await tester.enterText(
        campoDeTexto(tester, 'RFC'),
        '  XAXX010101000  ',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar expediente'));
      await tester.pumpAndSettle();

      final put = vistas.lastWhere((v) => v.method == 'PUT');
      final cuerpo = jsonDecode(put.body) as Map<String, dynamic>;

      expect(cuerpo['taxId'], 'XAXX010101000');
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

        // ⚠️ SIN RÉGIMEN, y es necesario: con `601` puesto, escribir un RFC de 13
        // caracteres contradice al régimen y el aviso TAPA la ayuda —
        // `InputDecoration` esconde `helperText` cuando hay `errorText`—. Esta prueba
        // es sobre la ayuda, así que el expediente no debe traer contradicción.
        // El aviso tiene sus propias pruebas más abajo.
        return http.Response(empresaJson(rfc: null, regimen: null), 200);
      });

      await montarEmpresa(tester, repo);

      // Sin RFC: no promete nada.
      expect(find.textContaining('Escribe el RFC'), findsOneWidget);

      // ⚠️ POR SU ETIQUETA Y NO POR SU POSICIÓN. Esto decía `.at(1)`, y el campo del
      // nombre comercial —que entró el 21 de octubre de 2026— lo desplazó: la prueba
      // empezó a escribir el RFC dentro de la razón social, y lo que falló fue la
      // aserción de la ayuda, tres líneas más abajo y sin relación aparente con la
      // causa. Un índice posicional en un formulario que crece es una prueba que
      // miente en cuanto alguien añade un campo arriba.
      await tester.enterText(campoDeTexto(tester, 'RFC'), 'SPR950101AB1');
      await tester.pumpAndSettle();

      // SE BUSCA LA FRASE COMPLETA DE LA AYUDA, no «persona moral» a secas: el nombre
      // de un régimen del catálogo —«General de Ley Personas Morales»— también la
      // contendría, y la prueba pasaría o fallaría según qué regímenes estén sembrados.
      expect(
        find.textContaining('la lista muestra los de persona moral'),
        findsOneWidget,
      );

      await tester.enterText(campoDeTexto(tester, 'RFC'), 'RIMA900101AB1');
      await tester.pumpAndSettle();

      expect(
        find.textContaining('la lista muestra los de persona física'),
        findsOneWidget,
      );
    });

    testWidgets('cambiar el RFC a uno de OTRO TIPO no tira la pantalla, y avisa', (
      tester,
    ) async {
      // ⚠️ ESTO REVENTABA, y se encontró probando el ensayo el 22 de octubre de 2026.
      // Con `601` elegido —persona moral— y el RFC cambiado a uno de 13 caracteres, el
      // catálogo vuelve filtrado a persona física y `601` ya no está en él. El menú
      // desplegable EXIGE que su valor esté entre sus opciones, así que lanzaba y la
      // pantalla entera se caía con «Algo salió mal. Vuelve a intentarlo.».
      //
      // ⚠️ Y LA PRUEBA DE AL LADO NO LO VEÍA porque servía el catálogo COMPLETO
      // pasara lo que pasara. Ésta filtra como filtra el servidor, que es la única
      // forma de reproducirlo.
      final (repo: repo, vistas: _) = await construir((p) async {
        if (p.url.path.endsWith('/fiscal-regimes')) {
          final rfc = p.url.queryParameters['rfc'] ?? '';

          // El servidor filtra por LONGITUD: 12 es empresa, 13 es persona física.
          final todos = jsonDecode(catalogoJson()) as List<dynamic>;

          final filtrados = switch (rfc.length) {
            12 => [
              for (final r in todos)
                if ((r as Map<String, dynamic>)['personaMoral'] == true) r,
            ],
            13 => [
              for (final r in todos)
                if ((r as Map<String, dynamic>)['personaFisica'] == true) r,
            ],
            _ => todos,
          };

          return http.Response(jsonEncode(filtrados), 200);
        }

        return http.Response(empresaJson(), 200);
      });

      await montarEmpresa(tester, repo);

      // De partida: RFC de empresa y régimen de empresa. Todo cuadra.
      // `textContaining` porque la etiqueta lleva el código delante: «601 · General…».
      expect(
        find.textContaining('General de Ley Personas Morales'),
        findsWidgets,
      );

      await tester.enterText(campoDeTexto(tester, 'RFC'), 'XEXX010101000');
      await tester.pumpAndSettle();

      // 1 · LA PANTALLA SIGUE VIVA. Es lo primero, porque lo que pasaba era que no.
      //
      // ⚠️ LO QUE DE VERDAD LO FIJA ES QUE ESTA PRUEBA LLEGUE HASTA AQUÍ: el
      // desplegable lanza DURANTE EL BUILD, y `flutter_test` falla la prueba con la
      // excepción. Comprobado quitando el arreglo: «There should be exactly one item
      // with [DropdownButton]'s value: 601».
      //
      // NO se busca «Algo salió mal», que es lo que ve una persona: ese texto lo pinta
      // el `ErrorWidget.builder` de `main_web.dart`, que una prueba de widget no
      // instala. Buscarlo aquí pasaría siempre y no probaría nada.
      expect(find.text('Guardar expediente'), findsOneWidget);

      // 2 · NO SE LE BORRÓ LA ELECCIÓN A NADIE. El régimen sigue ahí, nombrado por lo
      // que es y marcado por lo que le pasa.
      expect(
        find.textContaining('General de Ley Personas Morales'),
        findsWidgets,
      );

      // 3 · Y EL AVISO DICE LAS DOS MITADES, porque cualquiera de las dos puede ser la
      // que está mal: tan válido es corregir el RFC como cambiar el régimen.
      expect(
        find.textContaining('es de persona moral y el RFC que escribiste'),
        findsOneWidget,
      );
      expect(find.textContaining('Cambia uno de los dos'), findsOneWidget);
    });

    testWidgets('con los tres datos puestos pero el régimen que no cuadra, dice que REVISES', (
      tester,
    ) async {
      // ⚠️ «COMPLETOS» NO ES «CORRECTOS». Salió probando el ensayo: con razón social,
      // RFC y domicilio puestos, la pantalla daba el expediente por bueno aunque el
      // régimen contradijera al RFC — y de ahí saldría una tarjeta fiscal que se
      // contradice a sí misma.
      //
      // El servidor dice `fiscalCardReady` sobre LOS TRES INDISPENSABLES y eso sigue
      // siendo verdad. Lo que se añade es lo que la pantalla sí sabe y él no mira.
      final (repo: repo, vistas: _) = await construir((p) async {
        if (p.url.path.endsWith('/fiscal-regimes')) {
          final rfc = p.url.queryParameters['rfc'] ?? '';
          final todos = jsonDecode(catalogoJson()) as List<dynamic>;

          final filtrados = switch (rfc.length) {
            13 => [
              for (final r in todos)
                if ((r as Map<String, dynamic>)['personaFisica'] == true) r,
            ],
            _ => todos,
          };

          return http.Response(jsonEncode(filtrados), 200);
        }

        // CON LA TARJETA LISTA: el servidor dice que los tres están.
        return http.Response(empresaJson(tarjetaLista: true), 200);
      });

      await montarEmpresa(tester, repo);

      // De partida no hay nada que revisar: RFC de empresa y régimen de empresa.
      expect(find.textContaining('Los datos fiscales están completos'), findsOneWidget);

      await tester.enterText(campoDeTexto(tester, 'RFC'), 'XEXX010101000');
      await tester.pumpAndSettle();

      // Y AHORA NO: están los tres, y hay algo que revisar.
      expect(find.textContaining('Los datos fiscales están completos'), findsNothing);
      expect(find.textContaining('hay algo que revisar'), findsOneWidget);
      expect(
        find.textContaining('el régimen fiscal no corresponde al tipo de persona'),
        findsOneWidget,
      );
    });

    testWidgets('y al volver a un RFC de empresa, el aviso desaparece', (
      tester,
    ) async {
      // La otra mitad: un aviso que se queda puesto después de arreglarlo enseña a
      // ignorarlo.
      final (repo: repo, vistas: _) = await construir((p) async {
        if (p.url.path.endsWith('/fiscal-regimes')) {
          final rfc = p.url.queryParameters['rfc'] ?? '';
          final todos = jsonDecode(catalogoJson()) as List<dynamic>;

          final filtrados = switch (rfc.length) {
            13 => [
              for (final r in todos)
                if ((r as Map<String, dynamic>)['personaFisica'] == true) r,
            ],
            _ => todos,
          };

          return http.Response(jsonEncode(filtrados), 200);
        }

        return http.Response(empresaJson(), 200);
      });

      await montarEmpresa(tester, repo);

      await tester.enterText(campoDeTexto(tester, 'RFC'), 'XEXX010101000');
      await tester.pumpAndSettle();
      expect(find.textContaining('Cambia uno de los dos'), findsOneWidget);

      await tester.enterText(campoDeTexto(tester, 'RFC'), 'SPR950101AB1');
      await tester.pumpAndSettle();

      expect(find.textContaining('Cambia uno de los dos'), findsNothing);

      // Y el régimen volvió a ser una opción normal, sin la coletilla.
      expect(find.textContaining('(no corresponde a este RFC)'), findsNothing);
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

    // =======================================================================
    // El choque, en el expediente de DIECISÉIS campos
    // =======================================================================

    testWidgets('un choque DE VERDAD pregunta sólo por el campo que choca', (
      tester,
    ) async {
      // **AQUÍ PESA MÁS QUE EN LA SUCURSAL**: este formulario tiene dieciséis campos,
      // así que el aviso de antes —recargar y volver a escribir— podía tirar dieciséis
      // datos por un choque en uno.
      var puts = 0;

      final (repo: repo, vistas: vistas) = await construir((p) async {
        if (p.url.path.endsWith('/fiscal-regimes')) {
          return http.Response(catalogoJson(), 200);
        }

        if (p.method == 'GET') return http.Response(empresaJson(), 200);

        puts++;

        // ELLA CAMBIÓ LA RAZÓN SOCIAL **y** el representante legal; yo sólo la razón
        // social. Así que la razón social choca y el representante no.
        return puts == 1
            ? http.Response(
                jsonEncode({
                  'code': 'expediente_desactualizado',
                  'message': 'Alguien más guardó este expediente.',
                  'current': jsonDecode(
                    jsonEncode({
                      ...jsonDecode(empresaJson(version: 9)) as Map<String, dynamic>,
                      'legalName': 'La suya S.A.',
                      'legalRep': 'Ana Suya',
                    }),
                  ),
                }),
                409,
              )
            : http.Response(empresaJson(version: 10), 200);
      });

      await montarEmpresa(tester, repo);

      await tester.enterText(campoDeTexto(tester, 'Razón social'), 'La mía S.A.');
      await tester.tap(find.text('Guardar expediente'));
      await tester.pumpAndSettle();

      // SE PREGUNTA POR LA RAZÓN SOCIAL…
      expect(find.text('Razón social'), findsWidgets);
      expect(find.text('La suya S.A.'), findsOneWidget);

      // …Y EL REPRESENTANTE SE INFORMA, NO SE PREGUNTA: ella lo cambió y yo no lo
      // toqué, así que no hay nada que decidir — pero esconderlo haría guardar sin
      // saber qué entró de fuera.
      expect(
        find.textContaining('cambió 1 dato que tú no habías tocado'),
        findsOneWidget,
      );
      expect(find.textContaining('Ana Suya'), findsOneWidget);

      // SIN ELEGIR NADA se queda lo mío, y se dice antes de guardar.
      expect(find.text('Si no eliges, se queda lo tuyo.'), findsOneWidget);

      await tester.tap(find.text('Guardar con estas decisiones'));
      await tester.pumpAndSettle();

      expect(puts, 2);

      final segundo =
          jsonDecode(vistas.where((v) => v.method == 'PUT').last.body)
              as Map<String, dynamic>;

      // MI RAZÓN SOCIAL —no elegí, así que se queda la mía— Y SU REPRESENTANTE.
      expect(segundo['legalName'], 'La mía S.A.');
      expect(segundo['legalRep'], 'Ana Suya');
      expect(segundo['profileVersion'], 9);
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

      // NINGUNA DE LAS DOS FAMILIAS: ni estructura ni expediente.
      await montarSucursal(
        tester,
        repo,
        capacidades: const CapacidadesDeModulo.ninguna(),
        puedeEditarExpedientes: false,
      );

      expect(find.text('Guardar expediente'), findsNothing);
      expect(find.text('Agregar tramo'), findsNothing);

      // PERO EL HORARIO SE VE: consultar no es editar, y esconderlo dejaría a quien
      // sólo lee sin saber a qué hora abre su sucursal.
      expect(find.text('Desde'), findsOneWidget);
    });

    // =======================================================================
    // Los dos permisos, campo por campo
    // =======================================================================

    testWidgets(
      'con SÓLO modificar: nombre y tipo se editan, domicilio y horario NO',
      (tester) async {
        // LA REGLA DE PANTALLA DEL 21 DE OCTUBRE DE 2026: los campos sin permiso
        // salen de sólo lectura, **con una nota que dice qué permiso falta**. No se
        // esconden: el expediente se consulta mucho más de lo que se edita, y quitarle
        // la dirección a quien puede renombrar la sucursal le quitaría el dato sin
        // motivo.
        final (repo: repo, vistas: _) = await construir(
          (_) async => http.Response(sucursalJson(), 200),
        );

        await montarSucursal(
          tester,
          repo,
          capacidades: const CapacidadesDeModulo(
            puedeVer: true,
            puedeCrear: false,
            puedeModificar: true,
            puedeArchivar: false,
          ),
          puedeEditarExpedientes: false,
        );

        // SE PUEDE GUARDAR: hay una familia con permiso.
        expect(find.text('Guardar expediente'), findsOneWidget);

        // EL NOMBRE, EDITABLE.
        expect(campoDe(tester, 'Nombre').enabled, isTrue);

        // LA CALLE, DE SÓLO LECTURA Y CON SU NOTA.
        expect(campoDe(tester, 'Calle').enabled, isFalse);

        expect(
          find.textContaining('domicilio necesitas el permiso de configurar'),
          findsOneWidget,
        );
        expect(
          find.textContaining('horario necesitas el permiso de configurar'),
          findsOneWidget,
        );

        // Y NO LA DEL OTRO LADO: quien sí puede modificar no tiene que leer que le
        // falta un permiso que tiene.
        expect(
          find.textContaining('nombre o el tipo necesitas'),
          findsNothing,
        );
      },
    );

    testWidgets(
      'con SÓLO el expediente: domicilio y horario se editan, nombre y tipo NO',
      (tester) async {
        final (repo: repo, vistas: _) = await construir(
          (_) async => http.Response(sucursalJson(), 200),
        );

        await montarSucursal(
          tester,
          repo,
          capacidades: const CapacidadesDeModulo(
            puedeVer: true,
            puedeCrear: false,
            puedeModificar: false,
            puedeArchivar: false,
          ),
        );

        expect(campoDe(tester, 'Nombre').enabled, isFalse);
        expect(campoDe(tester, 'Calle').enabled, isTrue);

        expect(
          find.textContaining('nombre o el tipo necesitas el permiso de modificar'),
          findsOneWidget,
        );
      },
    );

    testWidgets('sin permiso NO manda el nombre ni el tipo en el cuerpo', (
      tester,
    ) async {
      // ⚠️ LO QUE ESTO IMPIDE ES UN 403 POR UN CAMPO QUE NADIE TOCÓ. En el `PUT` un
      // nombre nulo significa «no lo toques»; mandarlo con su valor actual «porque no
      // cambia» haría que el servidor comparase y, si otra persona lo hubiera
      // cambiado entre medias, exigiera un permiso que esta persona no tiene para un
      // campo que no quiso tocar.
      final (repo: repo, vistas: vistas) = await construir(
        (_) async => http.Response(sucursalJson(), 200),
      );

      await montarSucursal(
        tester,
        repo,
        capacidades: const CapacidadesDeModulo.ninguna(),
      );

      await tester.tap(find.text('Guardar expediente'));
      await tester.pumpAndSettle();

      final put = vistas.lastWhere((v) => v.method == 'PUT');
      final cuerpo = jsonDecode(put.body) as Map<String, dynamic>;

      expect(cuerpo.containsKey('name'), isFalse);
      expect(cuerpo.containsKey('branchTypeId'), isFalse);

      // PERO EL DOMICILIO Y EL HORARIO SÍ VAN, con lo que se cargó: en este `PUT` un
      // domicilio ausente significa «bórralo», así que omitirlos borraría los datos de
      // quien sólo iba a mirar.
      expect(cuerpo.containsKey('address'), isTrue);
      expect(cuerpo.containsKey('schedule'), isTrue);
    });

    testWidgets('las tres acciones del encabezado, cada una con su permiso', (
      tester,
    ) async {
      // LAS TRES VIENEN DEL PANEL QUE ESTA PANTALLA SUSTITUYÓ, con sus permisos
      // intactos: cerrar y reabrir es `modificar` —no da de baja y es reversible—, el
      // interruptor es `archivar`, y eliminar exige Maestro **y además** `archivar`.
      final (repo: repo, vistas: _) = await construir(
        (_) async => http.Response(sucursalJson(), 200),
      );

      // 1. SÓLO MODIFICAR: cerrar sí, desactivar no, eliminar no.
      await montarSucursal(
        tester,
        repo,
        capacidades: const CapacidadesDeModulo(
          puedeVer: true,
          puedeCrear: false,
          puedeModificar: true,
          puedeArchivar: false,
        ),
      );

      expect(find.text('Cerrar temporalmente'), findsOneWidget);
      expect(find.text('Desactivar'), findsNothing);
      expect(find.text('Eliminar'), findsNothing);

      // 2. SÓLO ARCHIVAR: desactivar sí, cerrar no. Y eliminar TAMPOCO, porque falta
      // el rol: son dos autoridades y hacen falta las dos.
      await montarSucursal(
        tester,
        repo,
        capacidades: const CapacidadesDeModulo(
          puedeVer: true,
          puedeCrear: false,
          puedeModificar: false,
          puedeArchivar: true,
        ),
      );

      expect(find.text('Cerrar temporalmente'), findsNothing);
      expect(find.text('Desactivar'), findsOneWidget);
      expect(find.text('Eliminar'), findsNothing);

      // 3. MAESTRO SIN `archivar`: eliminar tampoco. El rol solo no basta.
      await montarSucursal(
        tester,
        repo,
        esMaestro: true,
        capacidades: const CapacidadesDeModulo(
          puedeVer: true,
          puedeCrear: false,
          puedeModificar: true,
          puedeArchivar: false,
        ),
      );

      expect(find.text('Eliminar'), findsNothing);

      // 4. MAESTRO CON `archivar`: ahora sí.
      await montarSucursal(
        tester,
        repo,
        esMaestro: true,
        capacidades: const CapacidadesDeModulo(
          puedeVer: true,
          puedeCrear: false,
          puedeModificar: true,
          puedeArchivar: true,
        ),
      );

      expect(find.text('Eliminar'), findsOneWidget);
    });

    // =======================================================================
    // El choque: cuando otra persona guardó mientras yo editaba
    // =======================================================================

    /// El cuerpo del 409, **con el expediente que el servidor tiene ahora**.
    ///
    /// Es lo que permite no tirar lo que la persona escribió: con esto, lo que se
    /// cargó al abrir y lo que hay en el formulario, la pantalla compara las tres
    /// versiones y pregunta **sólo por lo que de verdad choca**.
    String conflictoJson({String? nombre = 'Matriz', Map<String, dynamic>? direccion}) =>
        jsonEncode({
          'code': 'expediente_desactualizado',
          'message': 'Alguien más guardó este expediente mientras lo editabas.',
          'current': jsonDecode(
            sucursalJson(version: 9, nombre: nombre, direccion: direccion),
          ),
        });

    /// La calle completa, para que el servidor no rechace una dirección a medias.
    Map<String, dynamic> direccionCon(String calle) => {
      'street': calle,
      'exteriorNumber': '5',
      'interiorNumber': null,
      'neighborhood': 'Centro',
      'municipality': 'Toluca',
      'city': null,
      'state': 'Estado de México',
      'postalCode': '50000',
      'country': null,
      'landmarks': null,
    };

    testWidgets('un choque que NO choca se reintenta SOLO, sin preguntar nada', (
      tester,
    ) async {
      // **ES EL CASO FRECUENTE DE VERDAD**: dos personas editando secciones distintas
      // del mismo expediente. Antes salía el aviso igual y la persona tenía que volver
      // a escribir lo suyo; ahora no se le pregunta nada porque no hay nada que
      // decidir.
      var puts = 0;

      final (repo: repo, vistas: vistas) = await construir((p) async {
        if (p.method == 'GET') return http.Response(sucursalJson(), 200);

        puts++;

        // EL PRIMER `PUT` CHOCA: la otra persona cambió la CALLE, que yo no toqué.
        return puts == 1
            ? http.Response(
                conflictoJson(direccion: direccionCon('Avenida Suya')),
                409,
              )
            : http.Response(sucursalJson(version: 10, nombre: 'Lo mío'), 200);
      });

      await montarSucursal(tester, repo);

      await tester.enterText(find.byType(TextField).first, 'Lo mío');
      await tester.tap(find.text('Guardar expediente'));
      await tester.pumpAndSettle();

      // NO SE PREGUNTÓ NADA.
      expect(find.text('Alguien más guardó mientras editabas'), findsNothing);
      expect(find.text('Alguien más guardó este expediente'), findsNothing);

      // Y SE GUARDÓ DOS VECES: el segundo intento va con LA VERSIÓN DE ELLA —9— que es
      // lo que lo hace aceptable, y lleva mi nombre y su calle.
      expect(puts, 2);

      final segundo =
          jsonDecode(vistas.where((v) => v.method == 'PUT').last.body)
              as Map<String, dynamic>;

      expect(segundo['profileVersion'], 9);
      expect(segundo['name'], 'Lo mío');
      expect(
        (segundo['address'] as Map<String, dynamic>)['street'],
        'Avenida Suya',
      );
    });

    testWidgets('un choque DE VERDAD se pregunta, y gana lo que se elige', (
      tester,
    ) async {
      var puts = 0;

      final (repo: repo, vistas: vistas) = await construir((p) async {
        if (p.method == 'GET') return http.Response(sucursalJson(), 200);

        puts++;

        // LOS DOS CAMBIAMOS EL NOMBRE, a cosas distintas: eso es el choque.
        return puts == 1
            ? http.Response(conflictoJson(nombre: 'Lo suyo'), 409)
            : http.Response(sucursalJson(version: 10, nombre: 'Lo suyo'), 200);
      });

      await montarSucursal(tester, repo);

      await tester.enterText(find.byType(TextField).first, 'Lo mío');
      await tester.tap(find.text('Guardar expediente'));
      await tester.pumpAndSettle();

      // SE PREGUNTA, y se enseñan las dos versiones.
      expect(find.text('Alguien más guardó mientras editabas'), findsOneWidget);
      expect(find.text('Lo mío'), findsWidgets);
      expect(find.text('Lo suyo'), findsOneWidget);

      // SE ELIGE LO SUYO y se guarda.
      await tester.tap(find.text('Lo de la otra persona'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar con estas decisiones'));
      await tester.pumpAndSettle();

      expect(puts, 2);

      final segundo =
          jsonDecode(vistas.where((v) => v.method == 'PUT').last.body)
              as Map<String, dynamic>;

      expect(segundo['name'], 'Lo suyo');
      expect(segundo['profileVersion'], 9);
    });

    testWidgets('cerrar el aviso NO pierde lo escrito ni guarda nada', (
      tester,
    ) async {
      // ⚠️ **ES LO QUE ESTE AVISO VIENE A PROTEGER.** El aviso de antes tenía un solo
      // botón —«Cargar lo más reciente»— que recargaba el formulario y tiraba todo lo
      // que la persona había escrito. Aquí, si cierra, se queda como estaba.
      var puts = 0;

      final (repo: repo, vistas: _) = await construir((p) async {
        if (p.method == 'GET') return http.Response(sucursalJson(), 200);

        puts++;

        return http.Response(conflictoJson(nombre: 'Lo suyo'), 409);
      });

      await montarSucursal(tester, repo);

      await tester.enterText(find.byType(TextField).first, 'Lo mío');
      await tester.tap(find.text('Guardar expediente'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Seguir editando'));
      await tester.pumpAndSettle();

      // NO SE GUARDÓ OTRA VEZ.
      expect(puts, 1);

      // Y LO ESCRITO SIGUE AHÍ.
      expect(campoDe(tester, 'Nombre').controller!.text, 'Lo mío');
    });

    testWidgets('un 409 SIN el expediente del servidor cae en el aviso de antes', (
      tester,
    ) async {
      // UN SERVIDOR QUE NO MANDE `current` NO ROMPE LA PANTALLA: no se puede comparar,
      // así que se avisa y se recarga, que es lo que se hacía antes. Es el único
      // camino en que la persona todavía tiene que volver a escribir lo suyo.
      final (repo: repo, vistas: _) = await construir((p) async {
        if (p.method == 'GET') return http.Response(sucursalJson(), 200);

        return http.Response(
          jsonEncode({
            'code': 'expediente_desactualizado',
            'message': 'Alguien más guardó este expediente.',
          }),
          409,
        );
      });

      await montarSucursal(tester, repo);

      await tester.tap(find.text('Guardar expediente'));
      await tester.pumpAndSettle();

      expect(find.text('Alguien más guardó este expediente'), findsOneWidget);
      expect(find.text('Cargar lo más reciente'), findsOneWidget);
    });

    testWidgets('un tipo retirado se señala EN EL SELECTOR, no en un diálogo', (
      tester,
    ) async {
      // EL SERVIDOR LO MANDA COMO 422 CON SU PROPIO CÓDIGO —es una regla de catálogo,
      // no de formato— pero para quien mira la pantalla es un campo que puede
      // corregir ahí mismo. Un diálogo lo obligaría a cerrarlo para encontrar cuál.
      final (repo: repo, vistas: _) = await construir((p) async {
        if (p.method == 'GET') return http.Response(sucursalJson(), 200);

        return http.Response(
          jsonEncode({
            'code': 'tipo_de_sucursal_no_disponible',
            'message': 'Ese tipo de sucursal no existe en esta empresa o está inactivo.',
          }),
          422,
        );
      });

      await montarSucursal(tester, repo);

      await tester.tap(find.text('Guardar expediente'));
      await tester.pumpAndSettle();

      expect(
        find.text('Ese tipo de sucursal no existe en esta empresa o está inactivo.'),
        findsOneWidget,
      );
    });

    testWidgets('una sucursal SIN TIPO abre su expediente y lo dice', (
      tester,
    ) async {
      // ⚠️ ESTO REVENTABA LA PANTALLA. `branchTypeId` es anulable en la base desde la
      // 0048 —las sucursales dadas de alta antes de que existieran los tipos no
      // tienen ninguno— y el modelo lo leía como obligatorio: `json['branchTypeId']
      // as String` sobre un nulo lanza. Y el servidor contestaba 500 antes de que la
      // web llegara a intentarlo.
      final (repo: repo, vistas: _) = await construir(
        (_) async => http.Response(sucursalJson(tipo: null), 200),
      );

      await montarSucursal(
        tester,
        repo,
        sucursal: const Sucursal(
          id: sucursalId,
          codigo: 'SUC-0001',
          nombre: 'Centro',
          activa: true,
          tipoId: null,
          estadoOperativo: 'operando',
        ),
      );

      expect(tester.takeException(), isNull);

      // EL SELECTOR SE VE VACÍO, con su invitación: no se inventa un tipo ni se
      // preselecciona el primero del catálogo.
      expect(find.text('Elige un tipo'), findsOneWidget);
    });
  });
}
