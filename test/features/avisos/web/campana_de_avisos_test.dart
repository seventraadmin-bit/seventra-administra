// LA CAMPANA DE AVISOS de la barra superior (CP-18 · M4-B, punto 8 del bloque del
// 12 de noviembre de 2026).
//
// ## Qué se fija aquí, y por qué estas cosas
//
//  1. **sin avisos no hay número y lo dice**: «Nada pendiente». Un «0» pegado a la
//     campana se aprende a ignorar, y el día que diga «3» ya nadie lo mira;
//  2. **el número es el total de los grupos**, no el de uno;
//  3. **máximo cinco filas por grupo**, y lo que no cabe se cuenta con un «+» en vez de
//     mentir con un número redondo: los listados paginan por cursor y **no devuelven
//     totales** (D-67), así que la sexta fila es cómo se sabe que hay más sin contar;
//  4. **un destino por fila**, y **la campana se cierra antes de navegar**: dejar el menú
//     abierto encima de la pantalla nueva es el mismo fallo que ya tuvieron las hojas
//     modales;
//  5. **se vuelve a leer al abrir**, porque los avisos se derivan al leer: no hay
//     leído/no leído y no hay nada guardado. Abrir es volver a preguntar;
//  6. **un grupo vacío no deja su encabezado suelto**, que es lo que haría que la campana
//     anunciara un grupo sin filas debajo.
//
// ## Lo que NO está aquí
//
// **El permiso**, a propósito: quien sabe qué permisos tiene la sesión es el portón —el
// único sitio que lee `effectivePermissions`—, y la campana pinta los grupos que le dan.
// Dos sitios decidiendo quién ve qué es cómo uno de los dos se queda viejo.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riseg_one/core/design_system/design_system_web.dart';
import 'package:riseg_one/features/avisos/web/presentation/campana_de_avisos.dart';
import 'package:riseg_one/features/usuarios/web/marca_seventra.dart';

FilaDeAviso _fila(String titulo, {VoidCallback? alAbrir}) => FilaDeAviso(
  titulo: titulo,
  detalle: 'Termina el 30/nov/2026',
  urgencia: RisegStatusTone.warning,
  alAbrir: alAbrir ?? () {},
);

void main() {
  Future<void> montar(WidgetTester tester, List<GrupoDeAvisos> grupos) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: MarcaSeventra.tema(),
        home: Scaffold(
          appBar: AppBar(actions: [CampanaDeAvisos(grupos: grupos)]),
          body: const SizedBox.shrink(),
        ),
      ),
    );

    await tester.pumpAndSettle();
  }

  Future<void> abrir(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('campana_de_avisos')));
    await tester.pumpAndSettle();
  }

  group('la campana de avisos', () {
    testWidgets('🚫 SIN AVISOS no hay número, y abierta lo DICE', (
      tester,
    ) async {
      await montar(tester, [
        GrupoDeAvisos(
          nombre: 'Servicios por terminar',
          leer: () async => const [],
          verTodos: () {},
        ),
      ]);

      // Ningún número pegado a la campana: ni «0» ni nada.
      expect(find.text('0'), findsNothing);

      await abrir(tester);

      expect(find.text('Nada pendiente'), findsOneWidget);
      // Y NO SE ANUNCIA EL GRUPO VACÍO: un encabezado sin filas debajo promete trabajo
      // que no existe.
      expect(find.text('SERVICIOS POR TERMINAR'), findsNothing);
    });

    testWidgets('el número es el total de TODOS los grupos', (tester) async {
      await montar(tester, [
        GrupoDeAvisos(
          nombre: 'Servicios por terminar',
          leer: () async => [_fila('Sportium Satélite'), _fila('Plaza Norte')],
          verTodos: () {},
        ),
        GrupoDeAvisos(
          nombre: 'Contratos por vencer',
          leer: () async => [_fila('Contrato CTR-0001')],
          verTodos: () {},
        ),
      ]);

      expect(find.text('3'), findsOneWidget);

      await abrir(tester);

      expect(find.text('SERVICIOS POR TERMINAR'), findsOneWidget);
      expect(find.text('CONTRATOS POR VENCER'), findsOneWidget);
      expect(find.text('Sportium Satélite'), findsOneWidget);
      expect(find.text('Contrato CTR-0001'), findsOneWidget);
    });

    testWidgets('🚫 CINCO FILAS POR GRUPO, y lo de más se dice con un «+»', (
      tester,
    ) async {
      await montar(tester, [
        GrupoDeAvisos(
          nombre: 'Servicios por terminar',
          // SEIS: uno más de los que caben, que es cómo se sabe que hay más sin contar.
          leer: () async => [
            for (var i = 1; i <= maximoPorGrupo + 1; i++) _fila('Servicio $i'),
          ],
          verTodos: () {},
        ),
      ]);

      // CINCO MÁS UN «+», NO SEIS: el seis sería un total, y un total no se sabe.
      expect(find.text('5+'), findsOneWidget);

      await abrir(tester);

      expect(find.text('Servicio 5'), findsOneWidget);
      expect(find.text('Servicio 6'), findsNothing);
      expect(find.text('Ver todos'), findsOneWidget);
    });

    testWidgets('cuando todo cabe, lleva al listado sin prometer más', (
      tester,
    ) async {
      await montar(tester, [
        GrupoDeAvisos(
          nombre: 'Servicios por terminar',
          leer: () async => [_fila('Sportium Satélite')],
          verTodos: () {},
        ),
      ]);

      await abrir(tester);

      expect(find.text('Ver todos'), findsNothing);
      expect(find.text('Ver en su listado'), findsOneWidget);
    });

    testWidgets('🚫 una fila ABRE SU DESTINO y CIERRA la campana', (
      tester,
    ) async {
      var abiertos = 0;

      await montar(tester, [
        GrupoDeAvisos(
          nombre: 'Servicios por terminar',
          leer: () async => [_fila('Sportium Satélite', alAbrir: () => abiertos++)],
          verTodos: () {},
        ),
      ]);

      await abrir(tester);
      await tester.tap(find.text('Sportium Satélite'));
      await tester.pumpAndSettle();

      expect(abiertos, 1);
      // EL MENÚ YA NO ESTÁ: si se quedara abierto, taparía la pantalla a la que acaba de
      // llevar.
      expect(find.text('Sportium Satélite'), findsNothing);
    });

    testWidgets('«Ver todos» lleva al listado y también cierra', (tester) async {
      var vistos = 0;

      await montar(tester, [
        GrupoDeAvisos(
          nombre: 'Servicios por terminar',
          leer: () async => [
            for (var i = 1; i <= maximoPorGrupo + 1; i++) _fila('Servicio $i'),
          ],
          verTodos: () => vistos++,
        ),
      ]);

      await abrir(tester);
      await tester.tap(find.text('Ver todos'));
      await tester.pumpAndSettle();

      expect(vistos, 1);
      expect(find.text('Servicio 1'), findsNothing);
    });

    testWidgets('🚫 ABRIR VUELVE A LEER: el aviso es la condición, no un mensaje', (
      tester,
    ) async {
      var lecturas = 0;
      var filas = <FilaDeAviso>[_fila('Sportium Satélite')];

      await montar(tester, [
        GrupoDeAvisos(
          nombre: 'Servicios por terminar',
          leer: () async {
            lecturas++;
            return filas;
          },
          verTodos: () {},
        ),
      ]);

      // Una al montar, que es de dónde sale el número de la campana.
      expect(lecturas, 1);
      expect(find.text('1'), findsOneWidget);

      // Entretanto el servicio se renovó: la condición dejó de existir.
      filas = <FilaDeAviso>[];

      await abrir(tester);

      expect(lecturas, 2);
      expect(find.text('Nada pendiente'), findsOneWidget);
    });

    testWidgets('sin grupos no hay nada que preguntar', (tester) async {
      await montar(tester, const []);

      await abrir(tester);

      expect(find.text('Nada pendiente'), findsOneWidget);
    });
  });
}
