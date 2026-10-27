// EL MENÚ ENSEÑA SÓLO LO QUE SE PUEDE ABRIR, y quien no puede abrir nada recibe una
// bienvenida que lo explica.
//
// ## El defecto que esto vino a cazar
//
// El menú enseñaba los nueve apartados, y los que no tienen pantalla salían con la
// insignia «Próximamente» y un aviso que decía: «Este apartado todavía se usa **desde
// la aplicación de escritorio**. Lo estamos trayendo a la web módulo por módulo».
//
// Ese texto es INTERNO. Tiene sentido para RISEG, que es cliente piloto y sí usa el
// escritorio, y ninguno para un cliente nuevo: a quien contrata Administra en la nube
// se le estaba nombrando un producto que no tiene y una mudanza que no le incumbe. Lo
// vio el dueño probando con una cuenta de usuario, y **llevaba meses ahí sin que
// ninguna prueba leyera ese texto**.
//
// ## Y la consecuencia que trae
//
// Al dejar de enseñar lo que no se abre, **una persona puede quedarse sin ningún
// apartado visible**. Antes era imposible —Dashboard aparecía para todo el mundo— y
// ahora pasa con quien no tiene ningún permiso, que es el primer caso que el dueño
// prueba. Sin la bienvenida sería un marco con el menú vacío y un hueco en medio.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riseg_one/app/shell/apartados_web.dart';
import 'package:riseg_one/core/company/permiso_company.dart';
import 'package:riseg_one/features/usuarios/web/marca_seventra.dart';
import 'package:riseg_one/features/usuarios/web/presentation/sin_accesos_web_screen.dart';

void main() {
  group('Lo que no está mudado no llega al menú', () {
    /// Lo que el portón pondría en el menú para esta persona.
    List<String> menuDe({required bool esMaestro, required Set<String> permisos}) => [
      for (final a in apartados)
        if (queHacerCon(a, esMaestro: esMaestro, permisos: permisos) ==
            QueHacerConElApartado.seAbre)
          a.nombre,
    ];

    test('un Maestro con TODO ve sólo los apartados que tienen pantalla', () {
      final menu = menuDe(esMaestro: true, permisos: PermisoCompany.todos);

      // ⚠️ **ESTA PRUEBA SE FIJABA A LA LISTA EXACTA** y C1 la puso roja al mudar
      // Comercial, que es un cambio correcto: otra vez la regla «una prueba nunca se
      // fija a una lista exacta». Lo que se afirma ahora es que **esté lo mudado**, y la
      // propiedad —ningún apartado sin pantalla llega al menú— se comprueba abajo, que
      // es lo que de verdad protege.
      expect(menu, containsAll(['Organización', 'Comercial', 'Configuración']));

      // Y NINGUNO DE LOS SIN MUDAR, nombrados para que la prueba diga qué se está
      // afirmando en vez de sólo contar.
      for (final sinMudar in [
        'Dashboard',
        'Finanzas',
        'Personal',
        'Compras e inventario',
        'Activos',
        'Reportes',
      ]) {
        expect(
          menu,
          isNot(contains(sinMudar)),
          reason: '$sinMudar no tiene pantalla: ofrecerlo no lleva a ninguna parte',
        );
      }
    });

    test('todo apartado del menú tiene al menos una pestaña que abrir', () {
      // ES LA PROPIEDAD, no la lista: lo que llega al menú se puede abrir. Así la
      // prueba sigue valiendo el día que se mude Personal, sin tocarla.
      for (final a in apartados) {
        final seAbre =
            queHacerCon(a, esMaestro: true, permisos: PermisoCompany.todos) ==
            QueHacerConElApartado.seAbre;

        final tiene = pestanasPara(
          a,
          esMaestro: true,
          permisos: PermisoCompany.todos,
        ).any((p) => p.mudada);

        expect(
          seAbre,
          tiene,
          reason:
              '${a.nombre}: «se abre» y «tiene algo mudado que esta persona ve» '
              'tienen que ser lo mismo',
        );
      }
    });

    test('con CERO permisos no queda NI UN apartado', () {
      // EL CASO QUE EL DUEÑO PRUEBA PRIMERO, y la precondición de la bienvenida.
      expect(menuDe(esMaestro: false, permisos: const {}), isEmpty);
    });

    test('con sólo «Consultar la organización» queda Organización', () {
      // EL CONTRAPUNTO: sin él, lo de arriba pasaría también si el menú estuviera
      // siempre vacío, que sería otro defecto.
      expect(
        menuDe(esMaestro: false, permisos: {PermisoCompany.organizacionVer}),
        ['Organización'],
      );
    });
  });

  group('La bienvenida de quien no tiene accesos', () {
    Future<void> montar(
      WidgetTester tester, {
      String nombre = 'Beto Ruiz',
      String empresa = 'RISEG',
      VoidCallback? alCerrarSesion,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: MarcaSeventra.tema(),
          home: SinAccesosWebScreen(
            nombre: nombre,
            empresa: empresa,
            alCerrarSesion: alCerrarSesion ?? () {},
          ),
        ),
      );

      await tester.pumpAndSettle();
    }

    testWidgets('dice qué pasa y QUÉ HACER', (tester) async {
      await montar(tester);

      expect(
        find.text(
          'Todavía no tienes accesos asignados en esta empresa. '
          'Pídele al administrador que te los otorgue.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('lleva su nombre y el de la empresa', (tester) async {
      // SON LAS DOS PREGUNTAS de quien ve esto: «¿entré con mi cuenta?» y «¿entré a
      // la empresa correcta?».
      await montar(tester);

      expect(find.text('Hola, Beto Ruiz'), findsOneWidget);
      expect(find.text('RISEG'), findsOneWidget);
    });

    testWidgets('sin nombre no saluda a medias', (tester) async {
      // `/auth/refresh` responde con `displayName` nulo, así que una sesión
      // restaurada no lo trae. «Hola, » con la coma colgando se ve roto.
      await montar(tester, nombre: '');

      expect(find.text('Hola'), findsOneWidget);
      expect(find.textContaining('Hola,'), findsNothing);
    });

    testWidgets('cerrar sesión funciona', (tester) async {
      // SIN ESTO NO HAY SALIDA. Si la respuesta a una de las dos preguntas de arriba
      // es no, tiene que poder salir sin buscar dónde.
      var cerro = false;

      await montar(tester, alCerrarSesion: () => cerro = true);

      await tester.tap(find.text('Cerrar sesión'));
      await tester.pumpAndSettle();

      expect(cerro, isTrue);
    });

    testWidgets('NO nombra el escritorio ni promete que llegará', (tester) async {
      // ⚠️ ES EL DEFECTO QUE ESTO REEMPLAZA, dicho como aserción. Lo que falta aquí
      // no es una función nuestra —son permisos que alguien de su empresa concede—,
      // así que «Próximamente» sería una promesa falsa.
      await montar(tester);

      for (final prohibido in ['escritorio', 'Próximamente', 'módulo por módulo']) {
        expect(
          find.textContaining(prohibido, findRichText: true),
          findsNothing,
          reason: 'la bienvenida no debe decir «$prohibido»',
        );
      }
    });
  });
}
