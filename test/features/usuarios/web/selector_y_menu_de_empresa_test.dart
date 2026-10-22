// E1-B — elegir y cambiar de empresa, en pantalla.
//
// QUÉ DEFIENDEN ESTAS PRUEBAS, en orden de importancia:
//
//  1. **que cambiar de empresa sea deliberado.** Es la razón de toda la etapa: la lista
//     de Organización › Empresa cambiaba la empresa activa al consultar una ficha, y
//     ahora el único gesto que cambia de empresa es el menú de la barra;
//  2. **que la insignia «Última vez» se vea y la tarjeta salga primera**, porque es lo
//     que sustituye a la entrada automática que se quitó. Sin esto, el cambio habría
//     sido sólo perder una comodidad;
//  3. **que una empresa sin razón social enseñe una línea menos y no un hueco**, que es
//     «ausencia nunca es cero» en su forma visible;
//  4. **que el rol se diga en palabras**, no en el vocabulario del catálogo del backend.
//
// SE MONTAN BAJO `MarcaSeventra.tema()`, igual que las demás pruebas de pantalla de la
// web: el tema trae la extensión `AppColorScheme`, y sin ella `context.colors` revienta.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riseg_one/app/shell/shell_destinations.dart';
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
import 'package:riseg_one/core/company/logotipos_de_empresa.dart';
import 'package:riseg_one/core/config/api_config.dart';
import 'package:riseg_one/core/logging/app_logger.dart';
import 'package:riseg_one/features/usuarios/presentation/auth/widgets/auth_identity_panel.dart';
import 'package:riseg_one/features/usuarios/web/marca_seventra.dart';
import 'package:riseg_one/features/usuarios/web/marco_administra.dart';
import 'package:riseg_one/features/usuarios/web/selector_de_empresa_screen.dart';
import 'package:riseg_one/features/usuarios/web/tarjeta_de_empresa.dart';

void main() {
  const idA = '0193f0a0-0000-7000-8000-0000000000a1';
  const idB = '0193f0a0-0000-7000-8000-0000000000b2';

  CompanyDisponible empresa({
    required String id,
    required String nombre,
    String? razonSocial,
    String role = 'maestro',
    String organizacion = 'Cliente de prueba',
  }) => CompanyDisponible(
    companyId: id,
    organizationId: '0193f0a0-0000-7000-8000-0000000000aa',
    companyName: nombre,
    organizationName: organizacion,
    role: role,
    razonSocial: razonSocial,
  );

  /// Una caché de logotipos que **nunca tiene ninguno**: es el caso frecuente y el que
  /// hace visibles las iniciales. Devolver nulo es «no tiene», no un fallo.
  LogotiposDeEmpresa sinLogotipos() =>
      LogotiposDeEmpresa((_) async => null);

  Future<void> montar(WidgetTester tester, Widget pantalla) async {
    tester.view.physicalSize = const Size(1400, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: MarcaSeventra.tema(),
        // LOS DELEGADOS DE IDIOMA HACEN FALTA DE VERDAD: el marco monta `AppSidebar`,
        // y su encabezado lee `AppLocalizations.of(context)!`. Sin ellos la prueba
        // revienta con un «Null check operator used on a null value» que no tiene nada
        // que ver con lo que se está probando.
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: pantalla,
      ),
    );

    await tester.pumpAndSettle();
  }

  // =========================================================================
  group('La tarjeta de empresa', () {
    testWidgets('sin razón social enseña una línea MENOS, no un hueco', (
      tester,
    ) async {
      // AUSENCIA NUNCA ES CERO, y aquí se ve: `company.legal_name` es nullable porque
      // Tenancy crea la Company con un nombre y nada más. Lo que NO puede aparecer es
      // un «sin registrar» de relleno en una pantalla de bienvenida.
      await montar(
        tester,
        Scaffold(
          body: TarjetaDeEmpresa(
            empresa: empresa(id: idA, nombre: 'RISEG Servicios'),
            logotipos: sinLogotipos(),
            alPulsar: () {},
          ),
        ),
      );

      expect(find.text('RISEG Servicios'), findsOneWidget);
      expect(find.textContaining('sin registrar', findRichText: true), findsNothing);
      expect(find.textContaining('Sin razón social'), findsNothing);
    });

    testWidgets('con razón social la enseña bajo el nombre comercial', (
      tester,
    ) async {
      await montar(
        tester,
        Scaffold(
          body: TarjetaDeEmpresa(
            empresa: empresa(
              id: idA,
              nombre: 'SEGURIDAD PRIVADA RISEG',
              razonSocial: 'Seguridad Privada RISEG S.A. de C.V.',
            ),
            logotipos: sinLogotipos(),
            alPulsar: () {},
          ),
        ),
      );

      expect(find.text('SEGURIDAD PRIVADA RISEG'), findsOneWidget);
      expect(find.text('Seguridad Privada RISEG S.A. de C.V.'), findsOneWidget);
    });

    testWidgets('el rol se dice en PALABRAS, no «maestro» ni «user»', (
      tester,
    ) async {
      // Lo que se conserva de la decisión anterior —«el rol no se muestra porque es
      // vocabulario del modelo de permisos»— es justo esto: los valores del catálogo
      // cerrado del backend no se enseñan.
      await montar(
        tester,
        Scaffold(
          body: Column(
            children: [
              TarjetaDeEmpresa(
                empresa: empresa(id: idA, nombre: 'Alfa'),
                logotipos: sinLogotipos(),
                alPulsar: () {},
              ),
              TarjetaDeEmpresa(
                empresa: empresa(id: idB, nombre: 'Beta', role: 'user'),
                logotipos: sinLogotipos(),
                alPulsar: () {},
              ),
            ],
          ),
        ),
      );

      expect(find.text('Maestro'), findsOneWidget);
      expect(find.text('Usuario'), findsOneWidget);
      expect(find.text('maestro'), findsNothing);
      expect(find.text('user'), findsNothing);
    });

    testWidgets('un rol DESCONOCIDO se enseña tal cual, no como «Usuario»', (
      tester,
    ) async {
      // Si el catálogo del backend creciera, traducir lo desconocido al rol de menos
      // privilegio diría una cosa que nadie afirmó. Repetir lo que dijo el servidor es
      // peor estéticamente y mejor en todo lo demás.
      await montar(
        tester,
        Scaffold(
          body: TarjetaDeEmpresa(
            empresa: empresa(id: idA, nombre: 'Alfa', role: 'supervisor'),
            logotipos: sinLogotipos(),
            alPulsar: () {},
          ),
        ),
      );

      expect(find.text('supervisor'), findsOneWidget);
      expect(find.text('Usuario'), findsNothing);
    });

    testWidgets('sin logotipo salen DOS iniciales', (tester) async {
      await montar(
        tester,
        Scaffold(
          body: Column(
            children: [
              TarjetaDeEmpresa(
                empresa: empresa(id: idA, nombre: 'RISEG Servicios'),
                logotipos: sinLogotipos(),
                alPulsar: () {},
              ),
              TarjetaDeEmpresa(
                // UNA SOLA PALABRA: sus dos primeras letras.
                empresa: empresa(id: idB, nombre: 'Administración'),
                logotipos: sinLogotipos(),
                alPulsar: () {},
              ),
            ],
          ),
        ),
      );

      expect(find.text('RS'), findsOneWidget);
      expect(find.text('AD'), findsOneWidget);
    });

    testWidgets('con logotipo se pinta la imagen y NO las iniciales', (
      tester,
    ) async {
      // UN PNG DE 1×1 DE VERDAD, no bytes inventados: `Image.memory` con basura
      // dispararía su `errorBuilder` y la prueba pasaría por el camino equivocado
      // —enseñando iniciales— sin que nadie lo notara.
      final png = Uint8List.fromList(<int>[
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
        0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
        0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
        0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
        0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
        0x42, 0x60, 0x82,
      ]);

      await montar(
        tester,
        Scaffold(
          body: TarjetaDeEmpresa(
            empresa: empresa(id: idA, nombre: 'RISEG Servicios'),
            logotipos: LogotiposDeEmpresa((_) async => png),
            alPulsar: () {},
          ),
        ),
      );

      expect(find.byType(Image), findsOneWidget);
      expect(find.text('RS'), findsNothing);
    });
  });

  // =========================================================================
  group('El menú de la barra inferior', () {
    /// El marco con lo mínimo para que exista su barra inferior.
    Widget marco({
      required List<CompanyDisponible> empresas,
      required String activaId,
      Future<void> Function(CompanyDisponible)? alElegir,
    }) => MarcoAdministra(
      destinos: const [
        ShellDestination(
          path: '/organizacion',
          label: 'Organización',
          icon: Icons.apartment_outlined,
        ),
      ],
      indiceActivo: 0,
      alElegirDestino: (_) {},
      empresa: empresas
          .firstWhere((e) => e.companyId == activaId)
          .companyName,
      usuario: 'Marlon Rios',
      correo: 'marlon@seventra.mx',
      alCerrarSesion: () async {},
      cuerpo: const SizedBox.shrink(),
      logotipos: sinLogotipos(),
      empresas: empresas,
      empresaActivaId: activaId,
      alElegirEmpresa: alElegir,
    );

    testWidgets('con UNA empresa no hay menú: la barra es texto plano', (
      tester,
    ) async {
      // Un botón que no lleva a ninguna parte es peor que ningún botón.
      await montar(
        tester,
        marco(
          empresas: [empresa(id: idA, nombre: 'RISEG')],
          activaId: idA,
          alElegir: (_) async {},
        ),
      );

      expect(find.byKey(const Key('marco_pie_de_empresa')), findsOneWidget);
      expect(find.byKey(const Key('marco_cambiar_empresa')), findsNothing);
    });

    testWidgets('con VARIAS se abre, enseña nombre y rol, y marca la activa', (
      tester,
    ) async {
      await montar(
        tester,
        marco(
          empresas: [
            empresa(id: idA, nombre: 'SEGURIDAD PRIVADA RISEG'),
            empresa(id: idB, nombre: 'RISEG Servicios', role: 'user'),
          ],
          activaId: idA,
          alElegir: (_) async {},
        ),
      );

      await tester.tap(find.byKey(const Key('marco_cambiar_empresa')));
      await tester.pumpAndSettle();

      expect(find.text('TUS EMPRESAS'), findsOneWidget);
      expect(find.byKey(const Key('menu_empresa_$idA')), findsOneWidget);
      expect(find.byKey(const Key('menu_empresa_$idB')), findsOneWidget);

      // EL ROL EN CADA UNA: con dos empresas no es obvio, y es lo que dice qué se
      // podrá hacer al entrar.
      expect(find.text('Maestro'), findsOneWidget);
      expect(find.text('Usuario'), findsOneWidget);

      // LA ACTIVA MARCADA, y sólo ella.
      expect(find.byKey(const Key('tarjeta_es_la_activa')), findsOneWidget);
    });

    testWidgets('elegir otra empresa AVISA a quien sabe cambiarla', (
      tester,
    ) async {
      // LO QUE SE AFIRMA ES LA FRONTERA: el marco no cambia de empresa, dice cuál se
      // eligió. Preguntar por el trabajo sin guardar, llamar al gestor y anunciar el
      // resultado es del portón. Si esta prueba pudiera afirmar que la empresa cambió,
      // el cambio viviría en la pieza que pinta la cáscara.
      final elegidas = <String>[];

      await montar(
        tester,
        marco(
          empresas: [
            empresa(id: idA, nombre: 'SEGURIDAD PRIVADA RISEG'),
            empresa(id: idB, nombre: 'RISEG Servicios'),
          ],
          activaId: idA,
          alElegir: (e) async => elegidas.add(e.companyId),
        ),
      );

      await tester.tap(find.byKey(const Key('marco_cambiar_empresa')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('menu_empresa_$idB')));
      await tester.pumpAndSettle();

      expect(elegidas, [idB]);
    });

    testWidgets('la ACTIVA no se puede elegir: no avisa de nada', (
      tester,
    ) async {
      // Cambiar a la que ya está sería un viaje al servidor y un aviso para no mover
      // nada.
      final elegidas = <String>[];

      await montar(
        tester,
        marco(
          empresas: [
            empresa(id: idA, nombre: 'SEGURIDAD PRIVADA RISEG'),
            empresa(id: idB, nombre: 'RISEG Servicios'),
          ],
          activaId: idA,
          alElegir: (e) async => elegidas.add(e.companyId),
        ),
      );

      await tester.tap(find.byKey(const Key('marco_cambiar_empresa')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('menu_empresa_$idA')));
      await tester.pumpAndSettle();

      expect(elegidas, isEmpty);
    });

    testWidgets('sin nadie que recoja la elección, tampoco hay menú', (
      tester,
    ) async {
      await montar(
        tester,
        marco(
          empresas: [
            empresa(id: idA, nombre: 'Alfa'),
            empresa(id: idB, nombre: 'Beta'),
          ],
          activaId: idA,
        ),
      );

      expect(find.byKey(const Key('marco_cambiar_empresa')), findsNothing);
    });
  });

  // =========================================================================
  group('«Elige una empresa»', () {
    /// Un gestor de verdad, con un servidor que **no debería hacer falta**: estas
    /// pruebas no pulsan ninguna tarjeta, así que ninguna llamada sale. Se construye
    /// porque la pantalla lo exige por constructor, y si alguna prueba futura pulsa,
    /// el servidor contestará en vez de reventar.
    GestorDeCompany gestorDeMentira() {
      final desnudo = ApiClient(
        config: ApiConfig.resolve(raw: 'http://localhost:5199').when(
          ok: (c) => c,
          failure: (f) => throw StateError(f.message),
        ),
        cliente: MockClient((_) async => http.Response('[]', 200)),
        logger: AppLogger.console(),
      );

      final sesion = GestorDeSesion(
        api: AuthApi(desnudo),
        almacen: _SinSesion(),
        logger: AppLogger.console(),
      );

      addTearDown(sesion.dispose);

      final gestor = GestorDeCompany(
        api: CompanyApi(ApiClientAutenticado(cliente: desnudo, gestor: sesion)),
        almacen: const _SinPreferencia(),
        logger: AppLogger.console(),
      );

      addTearDown(gestor.dispose);

      return gestor;
    }

    Future<void> montarSelector(
      WidgetTester tester, {
      required List<CompanyDisponible> empresas,
      String? recordada,
      String usuario = 'Marlon Rios',
      Size tamano = const Size(1400, 1200),
    }) async {
      tester.view.physicalSize = tamano;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: MarcaSeventra.tema(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SelectorDeEmpresaScreen(
            gestor: gestorDeMentira(),
            disponibles: empresas,
            logotipos: sinLogotipos(),
            recordada: recordada,
            usuario: usuario,
            alCerrarSesion: () async {},
          ),
        ),
      );

      await tester.pumpAndSettle();
    }

    final dos = [
      empresa(
        id: idA,
        nombre: 'SEGURIDAD PRIVADA RISEG',
        razonSocial: 'Seguridad Privada RISEG S.A. de C.V.',
      ),
      empresa(id: idB, nombre: 'RISEG Servicios', role: 'user'),
    ];

    testWidgets('ancha: el panel oscuro del login, el saludo y las tarjetas', (
      tester,
    ) async {
      await montarSelector(tester, empresas: dos);

      // EL PANEL DEL LOGIN, no uno parecido: es la misma pieza.
      expect(find.byType(AuthIdentityPanel), findsOneWidget);

      expect(find.byKey(const Key('selector_saludo')), findsOneWidget);
      expect(find.text('Hola, Marlon Rios'), findsOneWidget);
      expect(find.text('Elige una empresa'), findsOneWidget);
      expect(find.text('Tienes acceso a 2. Podrás cambiar después.'), findsOneWidget);
      expect(find.byKey(const Key('selector_otra_cuenta')), findsOneWidget);

      // LAS DOS TARJETAS, con lo que cada una tiene que decir.
      expect(find.text('Seguridad Privada RISEG S.A. de C.V.'), findsOneWidget);
      expect(find.text('Maestro'), findsOneWidget);
      expect(find.text('Usuario'), findsOneWidget);
    });

    testWidgets('angosta: el panel se va ENTERO y queda el logotipo', (
      tester,
    ) async {
      // La misma regla que el login: por debajo de 900 px la zona decorativa no se
      // encoge, desaparece. Una franja estrecha de adorno no dice nada.
      await montarSelector(
        tester,
        empresas: dos,
        tamano: const Size(600, 1400),
      );

      expect(find.byType(AuthIdentityPanel), findsNothing);
      expect(find.byKey(const Key('selector_logo')), findsOneWidget);

      // Y SE SIGUE PUDIENDO ELEGIR, que es de lo que va la pantalla.
      expect(find.text('SEGURIDAD PRIVADA RISEG'), findsOneWidget);
      expect(find.text('RISEG Servicios'), findsOneWidget);
    });

    testWidgets('el saludo dice el nombre COMPLETO de la sesión, tal cual', (
      tester,
    ) async {
      // NADA ESTÁ FIJADO EN EL CÓDIGO: el saludo pinta el `displayName` que el
      // servidor devolvió al iniciar sesión, entero y sin recortar al primer nombre.
      // Se prueba con un nombre de TRES palabras porque es el caso de la cuenta de
      // prueba, y porque un saludo que se quedara con la primera palabra pasaría la
      // prueba de «Marlon Rios» a medias.
      await montarSelector(
        tester,
        empresas: dos,
        usuario: 'Usuario de prueba',
      );

      expect(find.text('Hola, Usuario de prueba'), findsOneWidget);
    });

    testWidgets('SIN NOMBRE no hay saludo: ni «Hola, » colgando', (
      tester,
    ) async {
      // `/auth/refresh` responde con `displayName` nulo, así que una sesión restaurada
      // no trae nombre. Es el caso frecuente de volver a entrar, no un borde raro.
      await montarSelector(tester, empresas: dos, usuario: '');

      expect(find.byKey(const Key('selector_saludo')), findsNothing);
      expect(find.textContaining('Hola'), findsNothing);
    });

    testWidgets('la recordada lleva «Última vez» y va PRIMERA', (tester) async {
      // ESTO ES LO QUE SUSTITUYE A LA ENTRADA AUTOMÁTICA. Antes, con una preferencia
      // válida se entraba sin preguntar y esta pantalla no se veía; ahora se pregunta
      // siempre, y lo que la preferencia hace es marcar y ordenar. Si la insignia o el
      // orden se perdieran, el cambio habría sido sólo quitar una comodidad.
      //
      // SE RECUERDA LA SEGUNDA a propósito: con la primera, «va primera» se cumpliría
      // sin hacer nada.
      await montarSelector(tester, empresas: dos, recordada: idB);

      expect(find.byKey(const Key('tarjeta_ultima_vez')), findsOneWidget);

      // EL ORDEN SE MIDE POR POSICIÓN EN PANTALLA, no por el orden de la lista que se
      // pasó: es lo que ve quien elige.
      final recordada = tester.getTopLeft(
        find.byKey(const Key('selector_empresa_$idB')),
      );
      final otra = tester.getTopLeft(
        find.byKey(const Key('selector_empresa_$idA')),
      );

      expect(
        recordada.dy,
        lessThan(otra.dy),
        reason: 'la recordada tiene que salir arriba',
      );

      // Y LA INSIGNIA ES DE ELLA, no de la primera de la lista original.
      expect(
        find.descendant(
          of: find.byKey(const Key('selector_empresa_$idB')),
          matching: find.byKey(const Key('tarjeta_ultima_vez')),
        ),
        findsOneWidget,
      );
    });

    testWidgets('sin recordada no hay insignia y manda el orden del servidor', (
      tester,
    ) async {
      // El orden del servidor es por Organization y luego por nombre, y no se reordena:
      // sería duplicar una decisión ya tomada.
      await montarSelector(tester, empresas: dos);

      expect(find.byKey(const Key('tarjeta_ultima_vez')), findsNothing);

      final primera = tester.getTopLeft(
        find.byKey(const Key('selector_empresa_$idA')),
      );
      final segunda = tester.getTopLeft(
        find.byKey(const Key('selector_empresa_$idB')),
      );

      expect(primera.dy, lessThan(segunda.dy));
    });

    testWidgets('una recordada que ya no está en la lista no marca nada', (
      tester,
    ) async {
      // No debería llegar —el gestor descarta la preferencia que el servidor no
      // confirma— pero si llegara, la pantalla no puede inventarse una insignia ni
      // dejar un hueco al ordenar.
      await montarSelector(
        tester,
        empresas: dos,
        recordada: '0193f0a0-0000-7000-8000-0000000000ff',
      );

      expect(find.byKey(const Key('tarjeta_ultima_vez')), findsNothing);
      expect(find.byKey(const Key('selector_empresa_$idA')), findsOneWidget);
      expect(find.byKey(const Key('selector_empresa_$idB')), findsOneWidget);
    });
  });
}

/// Una sesión que no existe: estas pruebas no autentican nada.
class _SinSesion implements AlmacenSesionRemota {
  @override
  Future<void> borrar() async {}

  @override
  Future<CredencialRemota?> leer() async => null;

  @override
  Future<void> escribir(CredencialRemota credencial) async {}
}

class _SinPreferencia implements AlmacenCompanyRecordada {
  const _SinPreferencia();

  @override
  Future<void> borrar() async {}

  @override
  Future<String?> leer() async => null;

  @override
  Future<void> escribir(String companyId) async {}
}
