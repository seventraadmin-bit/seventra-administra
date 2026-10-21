// La pestaña Empresa: **lista → ficha → editar**.
//
// Lo que este archivo fija es el RECORRIDO, que es lo que E1 estrena. El formulario de
// editar tiene sus pruebas en `expediente_pantalla_test.dart`.
//
// LAS TRES REGLAS QUE PROTEGE:
//
//  · con UNA empresa no se pinta la lista: un rótulo que no lleva a ninguna parte
//    ocupa espacio y no dice nada. Es la misma regla que la barra de pestañas;
//  · la ficha se ve COMPLETA sin permiso de edición —es la identidad de la empresa, no
//    un dato reservado— y lo que no se ve es «Editar»;
//  · «sin logotipo» y «no se pudo cargar el logotipo» **no son lo mismo**, y
//    confundirlos haría pensar que se perdió.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChannels;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riseg_one/core/api/api_client.dart';
import 'package:riseg_one/core/api/api_client_autenticado.dart';
import 'package:riseg_one/core/auth/almacen_sesion_remota.dart';
import 'package:riseg_one/core/auth/auth_api.dart';
import 'package:riseg_one/core/auth/gestor_de_sesion.dart';
import 'package:riseg_one/core/auth/sesion_remota.dart';
import 'package:riseg_one/core/company/almacen_company_recordada.dart';
import 'package:riseg_one/core/company/company_api.dart';
import 'package:riseg_one/core/company/company_remota.dart';
import 'package:riseg_one/core/company/gestor_de_company.dart';
import 'package:riseg_one/core/config/api_config.dart';
import 'package:riseg_one/core/logging/app_logger.dart';
import 'package:riseg_one/features/organizacion/web/datos/expedientes_repositorio_http.dart';
import 'package:riseg_one/features/organizacion/web/datos/logotipo_repositorio_http.dart';
import 'package:riseg_one/features/organizacion/web/modelos/expediente.dart';
import 'package:riseg_one/features/organizacion/web/presentation/empresa_ficha.dart';
import 'package:riseg_one/features/organizacion/web/presentation/empresas_web_screen.dart';
import 'package:riseg_one/features/usuarios/web/marca_seventra.dart';

/// El cuerpo de una sesión iniciada, para el `MockClient`.
String _sesion(DateTime t0) => jsonEncode({
  'accessToken': 'at_1',
  'accessExpiresAt': t0.add(const Duration(minutes: 30)).toIso8601String(),
  'refreshToken': 'rt_1',
  'refreshExpiresAt': t0.add(const Duration(days: 14)).toIso8601String(),
  'sessionId': '0193f0a0-0000-7000-8000-00000000aaaa',
  'identityId': '0193f0a0-0000-7000-8000-00000000bbbb',
  'displayName': 'Ana Torres',
  'email': 'ana@seventra.mx',
});

/// La preferencia de empresa, **sin tocar las de verdad del navegador**.
class _AlmacenCompanyEnMemoria implements AlmacenCompanyRecordada {
  const _AlmacenCompanyEnMemoria();

  @override
  Future<String?> leer() async => null;

  @override
  Future<void> escribir(String companyId) async {}

  @override
  Future<void> borrar() async {}
}

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

  final t0 = DateTime.utc(2026, 10, 21, 12);

  const empresa = '0193f0a0-0000-7000-8000-000000000001';

  /// Un PNG mínimo, **con su firma de verdad**: es lo que el modelo y el servidor
  /// miran, y unos bytes arbitrarios no se podrían decodificar.
  final unPng = Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  ]);

  ExpedienteDeEmpresa expedienteCompleto({
    String nombre = 'RISEG',
    String? razonSocial = 'Seguridad Privada RISEG S.A. de C.V.',
    String? rfc = 'SPR950101AB1',
    String? regimen = '601',
    Direccion? direccion,
    bool tarjetaLista = true,
  }) => ExpedienteDeEmpresa(
    empresaId: empresa,
    nombre: nombre,
    version: 2,
    tarjetaFiscalLista: tarjetaLista,
    razonSocial: razonSocial,
    rfc: rfc,
    representanteLegal: 'Juan Pérez',
    regimenFiscal: regimen,
    direccion:
        direccion ??
        const Direccion(
          calle: 'Hidalgo',
          numeroExterior: '10',
          colonia: 'Centro',
          municipio: 'Toluca',
          estado: 'Estado de México',
          codigoPostal: '50000',
          pais: 'México',
        ),
    contacto: const Contacto(telefono: '7221234567', correo: 'pagos@riseg.mx'),
  );

  /// El catálogo del SAT, con los dos que la ficha necesita nombrar.
  const catalogo = [
    RegimenFiscal(
      codigo: '601',
      nombre: 'General de Ley Personas Morales',
      personaFisica: false,
      personaMoral: true,
      seleccionable: true,
    ),
    RegimenFiscal(
      codigo: '626',
      nombre: 'Régimen Simplificado de Confianza',
      personaFisica: true,
      personaMoral: true,
      // UNO RETIRADO, para la prueba de que se sigue nombrando.
      seleccionable: false,
    ),
  ];

  Future<void> montarFicha(
    WidgetTester tester, {
    ExpedienteDeEmpresa? expediente,
    List<RegimenFiscal> regimenes = catalogo,
    Uint8List? logotipo,
    bool logotipoFallo = false,
    bool puedeEditar = true,
    VoidCallback? onVolverALaLista,
  }) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: MarcaSeventra.tema(),
        home: EmpresaFicha(
          expediente: expediente ?? expedienteCompleto(),
          regimenes: regimenes,
          logotipo: logotipo,
          logotipoFallo: logotipoFallo,
          puedeEditar: puedeEditar,
          onEditar: () {},
          onReintentarLogotipo: () {},
          onVolverALaLista: onVolverALaLista,
        ),
      ),
    );

    await tester.pumpAndSettle();
  }

  group('La entrada a la pestaña', () {
    /// Monta **la pestaña entera**, que es donde vive la decisión de por dónde se
    /// entra.
    Future<void> montarPestana(
      WidgetTester tester, {
      required List<CompanyDisponible> empresas,
    }) async {
      tester.view.physicalSize = const Size(1400, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final desnudo = ApiClient(
        config: config,
        cliente: MockClient((p) async {
          if (p.url.path.endsWith('/auth/login')) {
            return http.Response(_sesion(t0), 200);
          }

          // EL LOGOTIPO NO EXISTE: es el caso frecuente y no es un error.
          if (p.url.path.endsWith('/logo')) {
            return http.Response(
              jsonEncode({'code': 'logo_missing', 'message': 'Sin logotipo.'}),
              404,
            );
          }

          if (p.url.path.endsWith('/fiscal-regimes')) {
            return http.Response('[]', 200);
          }

          return http.Response(
            jsonEncode({
              'companyId': empresa,
              'name': 'RISEG',
              'legalName': 'Seguridad Privada RISEG S.A. de C.V.',
              'taxId': 'SPR950101AB1',
              'legalRep': null,
              'slogan': null,
              'fiscalRegimeCode': null,
              'address': null,
              'contact': null,
              'profileVersion': 1,
              'fiscalCardReady': false,
            }),
            200,
          );
        }),
        logger: AppLogger.console(),
      );

      final gestorDeSesion = GestorDeSesion(
        api: AuthApi(desnudo),
        almacen: _Almacen(),
        logger: AppLogger.console(),
        ahora: () => t0,
      );

      addTearDown(gestorDeSesion.dispose);
      await gestorDeSesion.iniciarSesion(email: 'ana@seventra.mx', password: 'x');

      final autenticado = ApiClientAutenticado(
        cliente: desnudo,
        gestor: gestorDeSesion,
      );

      final gestorDeCompany = GestorDeCompany(
        api: CompanyApi(autenticado),
        almacen: const _AlmacenCompanyEnMemoria(),
        logger: AppLogger.console(),
      );

      addTearDown(gestorDeCompany.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: MarcaSeventra.tema(),
          home: EmpresasWebScreen(
            repositorio: ExpedientesRepositorioHttp(autenticado),
            logotipos: LogotipoRepositorioHttp(autenticado),
            gestorDeCompany: gestorDeCompany,
            empresas: empresas,
            empresaActivaId: empresa,
            puedeEditar: true,
          ),
        ),
      );

      await tester.pumpAndSettle();
    }

    CompanyDisponible unaEmpresa(String id, String nombre) => CompanyDisponible(
      companyId: id,
      organizationId: '0193f0a0-0000-7000-8000-0000000000aa',
      companyName: nombre,
      organizationName: 'Organización RISEG',
      role: 'maestro',
    );

    testWidgets('con UNA empresa no se pinta la lista: se abre su ficha', (
      tester,
    ) async {
      // UNA LISTA DE UNO NO DECIDE NADA, y el paso de más se paga en cada visita. Es
      // la misma regla que la barra de pestañas: «un rótulo que no lleva a ninguna
      // parte ocupa espacio y no dice nada».
      await montarPestana(tester, empresas: [unaEmpresa(empresa, 'RISEG')]);

      expect(tester.takeException(), isNull);

      // LA FICHA: su razón social se ve, y el encabezado de la lista no.
      expect(find.text('Seguridad Privada RISEG S.A. de C.V.'), findsWidgets);
      expect(
        find.text('Las empresas que puedes abrir. Toca una para ver su ficha.'),
        findsNothing,
      );
    });

    testWidgets('con VARIAS se entra por la LISTA', (tester) async {
      // ⚠️ **ESTO SE PROGRAMÓ AL REVÉS LA PRIMERA VEZ.** La pantalla entraba siempre a
      // la ficha de la empresa activa, y el documento aprobado dice «con una sola
      // empresa la lista no se pinta» — que implica que con varias la lista **es** la
      // entrada, igual que en Sucursales. Lo encontré comparando lo construido con lo
      // aprobado, no con una prueba: ésta es la prueba que faltaba.
      await montarPestana(
        tester,
        empresas: [
          unaEmpresa(empresa, 'RISEG'),
          unaEmpresa('0193f0a0-0000-7000-8000-0000000000b2', 'RISEG Servicios'),
        ],
      );

      expect(tester.takeException(), isNull);

      expect(
        find.text('Las empresas que puedes abrir. Toca una para ver su ficha.'),
        findsOneWidget,
      );

      // LAS DOS FILAS, y la activa marcada: tocar otra cambia la empresa activa, así
      // que saber en cuál se está es parte de la decisión.
      expect(find.text('RISEG'), findsOneWidget);
      expect(find.text('RISEG Servicios'), findsOneWidget);
      expect(find.text('Abierta'), findsOneWidget);
    });
  });

  group('La ficha', () {
    testWidgets('el domicilio se pinta con las CINCO líneas de la tarjeta fiscal', (
      tester,
    ) async {
      // EL FORMATO NO SE REINVENTA: sale de `lineasDeDomicilioFiscal`, que el
      // escritorio declara «única fuente de este formato para no tener 3 formatos
      // ligeramente distintos entre pantalla, PDF y portapapeles».
      await montarFicha(tester);

      expect(tester.takeException(), isNull);

      final domicilio = find.textContaining('Hidalgo 10');

      expect(domicilio, findsOneWidget);

      final texto = (tester.widget(domicilio) as Text).data!;

      // LAS CINCO, EN SU ORDEN. Se afirma el orden y no sólo que estén: una tarjeta
      // fiscal con el C.P. antes de la colonia no se puede pegar en ningún sitio.
      expect(texto.split('\n'), [
        'Hidalgo 10',
        'Centro',
        'Toluca, Estado de México',
        'C.P. 50000',
        'México',
      ]);
    });

    testWidgets('«Editar» sólo aparece con el permiso, y la ficha se ve igual', (
      tester,
    ) async {
      await montarFicha(tester, puedeEditar: false);

      expect(find.text('Editar'), findsNothing);

      // LA FICHA COMPLETA SE VE: es la identidad de su empresa, no un dato reservado.
      expect(find.text('SPR950101AB1'), findsWidgets);
      expect(find.textContaining('Hidalgo 10'), findsOneWidget);

      // Y SIN NOTA DE PERMISO, al contrario que en el formulario: nadie está
      // intentando editar, así que sería la respuesta a una pregunta que no se hizo.
      expect(find.textContaining('necesitas el permiso'), findsNothing);

      await montarFicha(tester, puedeEditar: true);
      expect(find.text('Editar'), findsOneWidget);
    });

    testWidgets('sin logotipo: iniciales y NINGÚN mensaje de error', (
      tester,
    ) async {
      // «SIN LOGOTIPO» ES UN ESTADO LEGÍTIMO. La presentación es tipográfica, igual
      // que el logotipo de SEVENTRA en el login es «texto compuesto y no una imagen».
      await montarFicha(tester, logotipo: null);

      expect(find.text('R'), findsOneWidget);
      expect(find.textContaining('No se pudo cargar'), findsNothing);
    });

    testWidgets('un FALLO al cargar el logotipo se dice, y no es lo mismo', (
      tester,
    ) async {
      // ⚠️ LA DIFERENCIA QUE IMPORTA: confundir «no hay» con «no se pudo» haría pensar
      // que el logotipo se perdió.
      await montarFicha(tester, logotipo: null, logotipoFallo: true);

      expect(find.textContaining('No se pudo cargar el logotipo'), findsOneWidget);
      expect(find.textContaining('Reintentar'), findsOneWidget);
    });

    testWidgets('con logotipo se pinta la imagen', (tester) async {
      await montarFicha(tester, logotipo: unPng);

      expect(tester.takeException(), isNull);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('si falta algo para la tarjeta fiscal, se dice QUÉ falta', (
      tester,
    ) async {
      // «FALTAN DATOS» OBLIGA A ADIVINAR CUÁL DE LOS TRES.
      await montarFicha(
        tester,
        expediente: expedienteCompleto(rfc: null, tarjetaLista: false),
      );

      final aviso = find.textContaining('Para entregar la tarjeta fiscal');

      expect(aviso, findsOneWidget);
      expect((tester.widget(aviso) as Text).data, contains('el RFC'));
    });

    testWidgets('el regreso a la lista sólo existe si hay lista', (tester) async {
      // CON UNA EMPRESA, un «‹ Empresas» que lleva a una lista de uno sería un paso
      // que no decide nada.
      await montarFicha(tester);
      expect(find.text('Empresas'), findsNothing);

      await montarFicha(tester, onVolverALaLista: () {});
      expect(find.text('Empresas'), findsOneWidget);
    });

    testWidgets('⚠️ el régimen fiscal dice el CÓDIGO Y LA DESCRIPCIÓN', (
      tester,
    ) async {
      // **ESTE ES EL DEFECTO QUE SE VIO EN PANTALLA** el 21 de octubre de 2026: la
      // ficha enseñaba «601» a secas.
      //
      // El expediente sólo trae el CÓDIGO —es lo que se guarda— y un «601» pelado no
      // le dice nada a quien recibe la tarjeta fiscal. La descripción vive en el
      // catálogo del SAT, así que la ficha lo necesita; mi primera versión no se lo
      // pedía y ninguna prueba lo notó, porque ninguna miraba ese campo.
      await montarFicha(tester);

      expect(find.text('601 · General de Ley Personas Morales'), findsOneWidget);
      expect(
        find.text('601'),
        findsNothing,
        reason: 'El código pelado no debe quedar en ninguna parte de la ficha.',
      );
    });

    testWidgets('sin catálogo se enseña el código solo, y no se esconde', (
      tester,
    ) async {
      // UN CATÁLOGO QUE NO LLEGÓ NO PUEDE BORRAR EL DATO: el código es lo único que
      // se sabe, y esconderlo por no tener su descripción sería perder información
      // que el expediente sí tiene.
      await montarFicha(tester, regimenes: const []);

      expect(find.text('601'), findsOneWidget);
    });

    testWidgets('un régimen RETIRADO se sigue nombrando entero', (tester) async {
      // La empresa que lo tenía lo conserva —es la regla del catálogo— así que lo que
      // no se puede hacer es dejar de decirlo porque ya no se pueda elegir.
      await montarFicha(
        tester,
        expediente: expedienteCompleto(regimen: '626'),
      );

      expect(
        find.text('626 · Régimen Simplificado de Confianza'),
        findsOneWidget,
      );
    });

    testWidgets('⧉ y «Copiar datos» copian el régimen ENTERO', (tester) async {
      // ⚠️ **LO QUE SE PEGA TIENE QUE DECIR LO MISMO QUE LO QUE SE ESTABA MIRANDO.**
      // Medir sólo el texto de la pantalla habría dejado pasar un bloque que copiara
      // «601» pelado: son dos caminos distintos en el código.
      //
      // El portapapeles se intercepta por su canal: en una prueba no hay uno de
      // verdad, y sin esto `Clipboard.setData` no se puede observar.
      final copiado = <String>[];

      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (llamada) async {
          if (llamada.method == 'Clipboard.setData') {
            copiado.add((llamada.arguments as Map)['text'] as String);
          }

          return null;
        },
      );

      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await montarFicha(tester);

      // 1 · EL ⧉ DEL RÉGIMEN copia ese dato, entero.
      await tester.tap(find.byTooltip('Copiar Régimen fiscal'));
      await tester.pumpAndSettle();

      expect(copiado.last, '601 · General de Ley Personas Morales');

      // 2 · Y EL BLOQUE lo lleva igual, con su etiqueta.
      await tester.tap(find.text('Copiar datos'));
      await tester.pumpAndSettle();

      expect(
        copiado.last,
        contains('Régimen fiscal: 601 · General de Ley Personas Morales'),
      );

      // Y EL BLOQUE ES EL BLOQUE: lleva también la razón social y el RFC, no sólo el
      // campo que acabamos de medir.
      expect(copiado.last, contains('Seguridad Privada RISEG S.A. de C.V.'));
      expect(copiado.last, contains('RFC: SPR950101AB1'));
    });

    testWidgets('un dato sin capturar se DICE, no se deja en blanco', (
      tester,
    ) async {
      // Un hueco se lee como un fallo de carga y no como un dato que nadie capturó.
      await montarFicha(
        tester,
        expediente: expedienteCompleto(razonSocial: null, tarjetaLista: false),
      );

      expect(find.text('Sin capturar'), findsWidgets);
    });
  });

  // =========================================================================
  // El modelo de la lista
  // =========================================================================

  group('La lista de empresas', () {

    Future<ApiClientAutenticado> cliente(
      Future<http.Response> Function(http.Request) responder,
    ) async {
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

          return responder(p);
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

    test('el ESTADO viaja, y su ausencia sólo puede ser «activa»', () async {
      // ⚠️ **LA DECISIÓN DE QUE LA LISTA NAZCA CON `status`.**
      //
      // Hoy la ruta filtra por `c.status = 'activa'`, así que el campo vale siempre lo
      // mismo. Existe para que la lista y el modelo no haya que rehacerlos en E2,
      // cuando haya que enseñar las inactivas a quien pueda reactivarlas — y hace
      // falta de verdad, porque una empresa desactivada desaparece de esta consulta y
      // del autorizador a la vez.
      //
      // **Y SU AUSENCIA NO ES «ausencia es cero»:** con el filtro puesto, una fila sin
      // `status` sólo puede ser una empresa activa servida por un servidor que todavía
      // no manda el campo. Exigirlo rompería el INICIO DE SESIÓN contra un servidor
      // viejo, y eso es desproporcionado para un dato de presentación.
      final conEstado = CompanyDisponible.desdeJson(const {
        'companyId': empresa,
        'organizationId': '0193f0a0-0000-7000-8000-0000000000aa',
        'companyName': 'RISEG',
        'organizationName': 'Organización RISEG',
        'role': 'maestro',
        'status': 'activa',
      });

      expect(
        conEstado.when(ok: (c) => c.estado, failure: (f) => f.message),
        'activa',
      );

      final sinEstado = CompanyDisponible.desdeJson(const {
        'companyId': empresa,
        'organizationId': '0193f0a0-0000-7000-8000-0000000000aa',
        'companyName': 'RISEG',
        'organizationName': 'Organización RISEG',
        'role': 'maestro',
      });

      expect(
        sinEstado.when(ok: (c) => c.estado, failure: (f) => f.message),
        'activa',
        reason: 'Un servidor sin el campo no puede tumbar el inicio de sesión.',
      );
    });

    test('el logotipo que no existe NO es un fallo', () async {
      // «SIN LOGOTIPO» ES UN ESTADO, y el servidor lo dice con un 404
      // `logo_missing`. Tratarlo como fallo haría que la ficha enseñara un aviso de
      // error en la empresa que simplemente no subió su logotipo — que son todas, el
      // primer día.
      final api = await cliente(
        (_) async => http.Response(
          jsonEncode({
            'code': 'logo_missing',
            'message': 'Esta Company no tiene logotipo.',
          }),
          404,
        ),
      );

      final resultado = await LogotipoRepositorioHttp(api).leer(empresa);

      expect(
        resultado.when(ok: (bytes) => bytes, failure: (f) => f),
        isNull,
      );
    });

    test('quitar un logotipo que ya no estaba también es éxito', () async {
      // EL SERVIDOR CONTESTA 404 LA SEGUNDA VEZ A PROPÓSITO. Para quien pulsó
      // «Quitar», que ya no hubiera nada que quitar no es un problema que pueda
      // resolver.
      final api = await cliente(
        (_) async => http.Response(
          jsonEncode({'code': 'logo_missing', 'message': 'No tiene logotipo.'}),
          404,
        ),
      );

      final resultado = await LogotipoRepositorioHttp(api).quitar(empresa);

      expect(resultado.when(ok: (_) => true, failure: (_) => false), isTrue);
    });

    test('el 409 de capacidad llega CON CIFRAS, y son de la organización', () async {
      // «NO CABE» NO DICE QUÉ HACER; «usas 100 de 100 GB» sí. Y las cifras son de la
      // ORGANIZATION: el mensaje no puede decir «tu empresa se quedó sin espacio».
      final api = await cliente(
        (_) async => http.Response(
          jsonEncode({
            'code': 'storage_capacity_exceeded',
            'message': 'Sin capacidad.',
            'usedBytes': 107374182400,
            'capacityBytes': 107374182400,
          }),
          409,
        ),
      );

      final resultado = await LogotipoRepositorioHttp(api).subir(
        empresaId: empresa,
        nombreDeArchivo: 'logo.png',
        bytes: unPng,
      );

      final cifras = resultado.when(
        ok: (_) => null,
        failure: LogotipoRepositorioHttp.capacidadDe,
      );

      expect(cifras, isNotNull);
      expect(cifras!.usados, 107374182400);
      expect(cifras.capacidad, 107374182400);
    });
  });
}
