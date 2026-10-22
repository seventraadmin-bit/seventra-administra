// E2 — los dos defectos que salieron al probar la administración en pantalla.
//
// NINGUNO LO HABRÍA CAZADO UNA PRUEBA DE LAS QUE YA HABÍA, y las dos razones valen la
// pena:
//
//  1. **«la aplicación vuelve a Elige una empresa»** no ocurría dentro de esta pantalla:
//     ocurría en el PORTÓN, que es quien recibe el aviso. La pantalla hacía su trabajo;
//     lo que estaba mal era con qué dato avisaba — sin el id de la empresa afectada, el
//     portón tenía que elegir lo más caro, y lo más caro vuelve a preguntar;
//  2. **las comillas al confirmar** sólo se ven copiando el texto con el ratón. Una
//     prueba que escriba el nombre a mano acierta siempre.
//
// EL REPOSITORIO ES FALSO Y LA PANTALLA ES LA DE VERDAD: lo que se mide es qué hace la
// pantalla con las respuestas y qué avisa, no cómo viajan.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riseg_one/core/company/autoridad_de_organizacion.dart';
import 'package:riseg_one/core/design_system/design_system_web.dart';
import 'package:riseg_one/core/company/logotipos_de_empresa.dart';
import 'package:riseg_one/core/error/result.dart';
import 'package:riseg_one/features/organizacion/web/datos/empresas_repositorio_http.dart';
import 'package:riseg_one/features/organizacion/web/modelos/empresa_administrada.dart';
import 'package:riseg_one/features/organizacion/web/presentation/empresas_administracion_screen.dart';
import 'package:riseg_one/features/usuarios/web/marca_seventra.dart';

/// El botón de confirmar del diálogo, que lo pinta el marco de `RisegDialog` y por eso
/// no tiene clave propia: se busca por su etiqueta **dentro de un `RisegButton`**, para
/// no confundirlo con el título del diálogo, que dice la misma palabra.
Finder _botonDe(String etiqueta) => find.ancestor(
  of: find.text(etiqueta),
  matching: find.byType(RisegButton),
);

const _org = '0193f0a0-0000-7000-8000-0000000000aa';
const _idA = '0193f0a0-0000-7000-8000-0000000000a1';
const _idB = '0193f0a0-0000-7000-8000-0000000000b2';

EmpresaAdministrada _empresa({
  required String id,
  required String nombre,
  String estado = 'activa',
  int accesos = 1,
}) => EmpresaAdministrada.desdeJson({
  'companyId': id,
  'name': nombre,
  'status': estado,
  'accessCount': accesos,
  'createdAt': '2026-10-01T12:00:00Z',
}).when(ok: (e) => e, failure: (f) => throw StateError(f.message));

class _RepositorioFalso implements EmpresasRepositorioHttp {
  _RepositorioFalso(this._empresas);

  List<EmpresaAdministrada> _empresas;

  final List<String> descartadas = [];
  final List<String> desactivadas = [];

  @override
  Future<Result<List<EmpresaAdministrada>>> listar(String organizationId) async =>
      Result.ok(_empresas);

  @override
  Future<Result<AutoridadDeOrganizacion?>> leerAutoridad(String organizationId) async =>
      throw UnimplementedError('la pantalla recibe la autoridad ya resuelta');

  @override
  Future<Result<void>> crear({
    required String organizationId,
    required String nombre,
    String? maestroIdentityId,
    String? razonSocial,
  }) async => const Result.ok(null);

  @override
  Future<Result<void>> desactivar({
    required String organizationId,
    required String companyId,
    required String motivo,
  }) async {
    desactivadas.add(companyId);
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> reactivar({
    required String organizationId,
    required String companyId,
  }) async => const Result.ok(null);

  @override
  Future<Result<void>> descartar({
    required String organizationId,
    required String companyId,
    required String motivo,
  }) async {
    descartadas.add(companyId);

    // La pantalla recarga después de cada acción, y una descartada ya no sale de la
    // lista de administración.
    _empresas = [
      for (final e in _empresas)
        if (e.companyId != companyId) e,
    ];

    return const Result.ok(null);
  }
}

void main() {
  /// Monta la pantalla con la autoridad de Owner, que es la única que ofrece descartar.
  Future<_RepositorioFalso> montar(
    WidgetTester tester, {
    required List<EmpresaAdministrada> empresas,
    required String activaId,
    List<String?>? avisos,
  }) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repositorio = _RepositorioFalso(empresas);

    await tester.pumpWidget(
      MaterialApp(
        theme: MarcaSeventra.tema(),
        home: Scaffold(
          body: EmpresasAdministracionScreen(
            repositorio: repositorio,
            logotipos: LogotiposDeEmpresa((_) async => null),
            organizationId: _org,
            autoridad: const AutoridadDeOrganizacion(
              organizationId: _org,
              role: 'owner',
              permisos: {},
            ),
            empresaActivaId: activaId,
            alCambiarLaLista: avisos?.add,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    return repositorio;
  }

  group('La confirmación por nombre', () {
    test('acepta el nombre con las comillas que la pantalla PONÍA', () {
      // EL DEFECTO, en una línea: la etiqueta decía «Escribe «X» para confirmar», y
      // copiar eso con el ratón se lleva las angulares dentro. Eran comillas MÍAS, no
      // del nombre de la empresa.
      expect(
        EmpresasAdministracionScreen.confirmacionCoincide(
          '«RISEG Servicios»',
          'RISEG Servicios',
        ),
        isTrue,
      );
    });

    test('acepta las rectas, las tipográficas y los espacios de los extremos', () {
      for (final escrito in [
        '"RISEG Servicios"',
        '“RISEG Servicios”',
        '  RISEG Servicios  ',
        '«  RISEG Servicios  »',
      ]) {
        expect(
          EmpresasAdministracionScreen.confirmacionCoincide(escrito, 'RISEG Servicios'),
          isTrue,
          reason: 'debería aceptar «$escrito»',
        );
      }
    });

    test('NO acepta otro nombre, ni uno parecido', () {
      // LO QUE NO SE AFLOJA: la defensa es que la persona LEA el nombre y lo copie.
      for (final escrito in [
        'RISEG',
        'RISEG Servicio',
        'riseg servicios',
        'RISEG  Servicios',
        '',
      ]) {
        expect(
          EmpresasAdministracionScreen.confirmacionCoincide(escrito, 'RISEG Servicios'),
          isFalse,
          reason: 'NO debería aceptar «$escrito»',
        );
      }
    });

    test('las comillas de DENTRO del nombre se respetan', () {
      // Sólo se perdona el adorno de los extremos. Quien omita las de dentro no está
      // copiando el nombre.
      expect(
        EmpresasAdministracionScreen.confirmacionCoincide('RISEG "Norte"', 'RISEG "Norte"'),
        isTrue,
      );

      expect(
        EmpresasAdministracionScreen.confirmacionCoincide('RISEG Norte', 'RISEG "Norte"'),
        isFalse,
      );
    });
  });

  group('La pantalla', () {
    testWidgets('el texto de confirmar NO lleva comillas alrededor del nombre', (
      tester,
    ) async {
      // LA OTRA MITAD DEL ARREGLO: que no se pinten. Lo de aceptarlas es el cinturón;
      // esto es no ponerle la trampa delante.
      await montar(
        tester,
        empresas: [
          _empresa(id: _idA, nombre: 'SEGURIDAD PRIVADA RISEG'),
          _empresa(id: _idB, nombre: 'RISEG Servicios'),
        ],
        activaId: _idA,
      );

      await tester.tap(find.byKey(const Key('admin_menu_$_idB')));
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Descartar'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('nombre_a_escribir')), findsOneWidget);

      // NI EN LA ETIQUETA NI EN LA INSTRUCCIÓN: se busca el nombre entrecomillado en
      // todo el diálogo, que es lo que alguien podría copiar.
      expect(find.textContaining('«RISEG Servicios»'), findsNothing);
    });

    testWidgets('al descartar, el aviso lleva EL ID de la empresa afectada', (
      tester,
    ) async {
      // ⚠️ ES EL DATO QUE ARREGLA EL PRIMER DEFECTO. Antes el aviso no llevaba nada, así
      // que el portón tenía que llamar a `resolver()` — y resolver con varias empresas
      // publica «hay que elegir», o sea que sacaba a la persona de donde estaba.
      final avisos = <String?>[];

      final repositorio = await montar(
        tester,
        empresas: [
          _empresa(id: _idA, nombre: 'SEGURIDAD PRIVADA RISEG'),
          _empresa(id: _idB, nombre: 'RISEG Servicios'),
        ],
        activaId: _idA,
        avisos: avisos,
      );

      await tester.tap(find.byKey(const Key('admin_menu_$_idB')));
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Descartar'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('motivo')), 'la creé por error');
      await tester.enterText(
        find.byKey(const Key('nombre_a_escribir')),
        // CON LAS COMILLAS, a propósito: así esta prueba cubre los dos arreglos de una
        // vez — si el nombre se rechazara, no habría aviso que comprobar.
        '«RISEG Servicios»',
      );
      await tester.pumpAndSettle();

      await tester.tap(_botonDe('Descartar'));
      await tester.pumpAndSettle();

      expect(repositorio.descartadas, [_idB]);
      expect(avisos, [_idB], reason: 'el aviso tiene que decir CUÁL empresa cambió');
    });

    testWidgets('con el nombre MAL no descarta nada y NO avisa', (tester) async {
      // Y no se cierra en silencio: si no avisara pero hubiera descartado, o al revés,
      // esta prueba lo diría.
      final avisos = <String?>[];

      final repositorio = await montar(
        tester,
        empresas: [
          _empresa(id: _idA, nombre: 'SEGURIDAD PRIVADA RISEG'),
          _empresa(id: _idB, nombre: 'RISEG Servicios'),
        ],
        activaId: _idA,
        avisos: avisos,
      );

      await tester.tap(find.byKey(const Key('admin_menu_$_idB')));
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Descartar'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('motivo')), 'motivo');
      await tester.enterText(find.byKey(const Key('nombre_a_escribir')), 'RISEG');
      await tester.pumpAndSettle();

      await tester.tap(_botonDe('Descartar'));
      await tester.pumpAndSettle();

      expect(repositorio.descartadas, isEmpty);
      expect(avisos, isEmpty);
    });

    testWidgets('la empresa ABIERTA no ofrece descartar ni desactivar', (tester) async {
      // Dejarse fuera a uno mismo de un clic no es una decisión, es un accidente. Y el
      // servidor no lo impide, así que la defensa es ésta.
      await montar(
        tester,
        empresas: [
          _empresa(id: _idA, nombre: 'SEGURIDAD PRIVADA RISEG'),
          _empresa(id: _idB, nombre: 'RISEG Servicios'),
        ],
        activaId: _idA,
      );

      await tester.tap(find.byKey(const Key('admin_menu_$_idA')));
      await tester.pumpAndSettle();

      // APARECEN, PERO DICEN POR QUÉ NO SE PUEDEN: un elemento ausente obliga a
      // buscarlo; uno deshabilitado sin explicación obliga a adivinar.
      expect(find.text('Desactivar — cambia de empresa primero'), findsOneWidget);
      expect(find.text('Descartar — cambia de empresa primero'), findsOneWidget);
    });
  });
}
