// Las dos cosas que fallaron al abrir Áreas por primera vez contra la API real,
// el 17 de octubre de 2026.
//
// LA SEGUNDA ES LA QUE IMPORTA, y conviene decir por qué el diagnóstico apuntó
// primero a la equivocada. El síntoma fue «Unexpected null value» justo después de
// un `GET /areas` que respondió 200 en 11 ms, así que todo señalaba al JSON: un
// campo con otro nombre, o un `!` sobre algo que el servidor manda nulo.
//
// No era eso. El modelo y la respuesta de la API coinciden campo por campo. Lo que
// faltaba era la **extensión de tema**: el Design System lee sus colores con
// `Theme.of(context).extension<AppColorScheme>()!`, y `main_web` construía un
// `ThemeData` a mano, sin instalarla. La PRIMERA línea del `build` de Áreas es
// `final colors = context.colors;`, así que reventaba ahí — con un mensaje que no
// menciona ni el tema ni la extensión.
//
// Por eso esta prueba cubre las dos: la lectura del JSON tal como viaja, y el
// requisito del tema, que es el que de verdad se rompió.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riseg_one/core/design_system/theme_context.dart';
import 'package:riseg_one/core/design_system/tokens/app_color_scheme.dart';
import 'package:riseg_one/features/organizacion/web/modelos/area.dart';
import 'package:riseg_one/features/usuarios/web/marca_seventra.dart';

void main() {
  group('Area.deJson lee la respuesta REAL de la API', () {
    // EL JSON ESTÁ COPIADO DEL CONTRATO DEL SERVIDOR, no inventado para que pase:
    // `AreaResponse(Guid Id, string Code, string Name, string Status,
    // DateTimeOffset UpdatedAt)`, que en JSON sale con las claves de abajo.
    //
    // `updatedAt` SOBRA para la pantalla y viene de todas formas. Se incluye aquí a
    // propósito: una prueba con sólo los cuatro campos que el modelo usa no
    // detectaría que un campo extra rompe la lectura, y los campos extra son
    // exactamente lo que un servidor añade sin avisar.
    const fila = {
      'id': '0199a0f9-4c5a-7909-a34c-097fed6ebd41',
      'code': 'ADMIN',
      'name': 'Administracion',
      'status': 'activa',
      'updatedAt': '2026-10-17T20:11:57.1234567+00:00',
    };

    test('los cuatro campos que la pantalla usa', () {
      final area = Area.deJson(fila);

      expect(area.id, '0199a0f9-4c5a-7909-a34c-097fed6ebd41');
      expect(area.codigo, 'ADMIN');
      expect(area.nombre, 'Administracion');
      expect(area.activa, isTrue);
    });

    test('«activa» se DERIVA del estado, no es un campo aparte', () {
      // Dos campos para un solo hecho acabarían discrepando. Y la derivación es por
      // igualdad con 'activa', no por «distinto de inactiva»: un estado nuevo que
      // nadie previó NO debe colarse como activo.
      expect(Area.deJson({...fila, 'status': 'inactiva'}).activa, isFalse);
      expect(Area.deJson({...fila, 'status': 'lo_que_sea'}).activa, isFalse);
    });

    test('la lista completa que devolvió la siembra', () {
      // Las cuatro áreas que el guion de siembra crea, con sus códigos reales.
      final lista = [
        {...fila, 'code': 'ADMIN', 'name': 'Administracion'},
        {...fila, 'code': 'OPS', 'name': 'Operaciones'},
        {...fila, 'code': 'SUP', 'name': 'Supervision'},
        {...fila, 'code': 'RH', 'name': 'Recursos Humanos'},
      ];

      final areas = [for (final f in lista) Area.deJson(f)];

      expect(areas, hasLength(4));
      expect(areas.map((a) => a.codigo), ['ADMIN', 'OPS', 'SUP', 'RH']);
      expect(areas.every((a) => a.activa), isTrue);
    });
  });

  group('El tema de la web instala lo que el Design System EXIGE', () {
    test('MarcaSeventra.tema() trae la extensión AppColorScheme', () {
      // ESTE ES EL FALLO, EN UNA LÍNEA. Sin la extensión, `context.colors` es un
      // `!` sobre `null` y la pantalla revienta antes de pintar nada.
      expect(
        MarcaSeventra.tema().extension<AppColorScheme>(),
        isNotNull,
        reason:
            'Sin AppColorScheme, la primera línea del build de cualquier pantalla '
            'del producto lanza «Unexpected null value»',
      );
    });

    testWidgets('context.colors funciona bajo el tema de la web', (tester) async {
      // Se comprueba el ACCESO REAL, no sólo que la extensión esté presente: es la
      // misma llamada que hace `areas_web_screen.dart:100`.
      Color? leido;

      await tester.pumpWidget(
        MaterialApp(
          theme: MarcaSeventra.tema(),
          home: Builder(
            builder: (context) {
              leido = context.colors.surface;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(leido, isNotNull);
    });

    testWidgets('y con un ThemeData pelado NO funciona — la regresión que se vigila', (
      tester,
    ) async {
      // LA CONTRAPARTE, Y HACE FALTA. Sin ella, alguien podría volver a poner un
      // `ThemeData(...)` a mano en `main_web` y la prueba de arriba seguiría
      // pasando —porque prueba `MarcaSeventra.tema()`, no lo que la aplicación
      // usa—, hasta que la pantalla volviera a reventar contra la API real.
      //
      // Esta prueba fija que el fallo EXISTE y es exactamente el que se vio.
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: Builder(
            builder: (context) {
              context.colors.surface;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(
        tester.takeException(),
        isA<TypeError>(),
        reason:
            'Si esto deja de lanzar, el Design System ya no exige la extensión y '
            'la prueba de arriba dejó de proteger nada: revísalo',
      );
    });
  });

  group('main_web NO vuelve a construir un tema a mano', () {
    test('usa MarcaSeventra.tema() y ningún ThemeData propio', () {
      // Se mira el ARCHIVO porque es donde estaba el defecto, y porque el widget
      // que lo usa es privado: no hay forma de preguntárselo en tiempo de
      // ejecución sin abrirlo a propósito sólo para la prueba.
      //
      // Se ignoran los comentarios: el archivo explica justamente por qué NO hay un
      // `ThemeData` a mano, y un guardia que se dispara contra su propia
      // explicación obliga a borrar la explicación. Es el séptimo tropiezo del
      // proyecto con lo mismo.
      final codigo = _sinComentarios('lib/main_web.dart');

      expect(codigo, contains('MarcaSeventra.tema()'));
      expect(
        codigo,
        isNot(contains('ThemeData(')),
        reason:
            'Un ThemeData construido aquí no instala AppColorScheme y devuelve la '
            'pantalla roja a Áreas',
      );
    });

    test('instala la red de seguridad contra la pantalla roja', () {
      final codigo = _sinComentarios('lib/main_web.dart');

      // Los dos caminos, y los dos hacen falta: uno sustituye el recuadro rojo al
      // construir, el otro recoge lo que falla fuera de un build.
      expect(codigo, contains('ErrorWidget.builder'));
      expect(codigo, contains('FlutterError.onError'));
    });
  });
}

String _sinComentarios(String ruta) =>
    File(ruta)
        .readAsLinesSync()
        .where((l) {
          final t = l.trimLeft();
          return !t.startsWith('//') && !t.startsWith('///') && !t.startsWith('*');
        })
        .join('\n');
