// LO QUE SE LEE EN PANTALLA ES LENGUAJE DE OPERACIÓN, NO NUESTRO VOCABULARIO.
//
// ===========================================================================
// POR QUÉ EXISTE
// ===========================================================================
//
// El dueño probando C2 contra el ensayo, el 11 de noviembre de 2026, leyó esto bajo el
// domicilio de un servicio:
//
// > «Se corrige, pero no se puede quitar: **desde la 0059** no existe un servicio sin
// > domicilio operativo.»
//
// `0059` es el número de una migración nuestra. En la pantalla de quien captura un
// servicio **no significa nada**, y lo que es peor: parece que significa algo, así que se
// lee dos veces antes de decidir que no. Había más de la misma familia —«y el servidor no
// lo admite», «lo asigna el servidor»—.
//
// ⚠️ **NO SE ESCAPÓ POR DESCUIDO, SE ESCAPÓ POR CÓMO SE ESCRIBE.** Estos textos se
// redactan mientras se programa la regla, con la razón de la regla fresca; y la razón de
// la regla es nuestra, no de quien la usa. Por eso esto es un candado y no un repaso: el
// repaso se pasa una vez y la próxima pantalla vuelve a nacer con jerga.
//
// ===========================================================================
// QUÉ PROHÍBE, Y QUÉ NO
// ===========================================================================
//
// Prohíbe **en los textos de las pantallas**: números de migración, de deuda y de etapa;
// las palabras de nuestra plomería —servidor, migración, disparador, transacción, RLS,
// JSON, HTTP, `company_id`…—; y los códigos de estado.
//
// **No juzga el estilo ni la longitud.** «Textos de ayuda cortos» es una decisión de
// diseño y no se puede medir con una expresión regular sin empezar a mentir. Lo que esto
// fija es la frontera que **sí** es objetiva: nuestro vocabulario no sale a la pantalla.
//
// Y se mira sólo `presentation/` —las pantallas— y `core/direcciones/`, que son widgets
// compartidos. Los mensajes de `datos/` son fallos de lectura de una respuesta, otra
// capa y otra conversación.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String normalizar(String ruta) => ruta.replaceAll(r'\', '/');

  /// Las pantallas y los widgets compartidos de la web.
  List<File> fuentes() => [
    for (final raiz in ['lib/features', 'lib/core/direcciones'])
      ...Directory(raiz)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) {
            final ruta = normalizar(f.path);

            return ruta.endsWith('.dart') &&
                !ruta.endsWith('.g.dart') &&
                (ruta.contains('/web/presentation/') ||
                    ruta.contains('/core/direcciones/'));
          }),
  ];

  /// Lo que no se admite en un texto de pantalla, con cómo se llama en el aviso.
  final prohibido = <String, RegExp>{
    'un número de migración': RegExp(r'\b00[0-9]{2}\b'),
    'un número de deuda': RegExp(r'\bD-[0-9]{1,3}\b'),
    'un número de etapa': RegExp(r'\b5D\.[0-9]'),
    'un código de estado': RegExp(r'\b(400|401|402|403|404|409|422|500)\b'),
    'una ruta del servidor': RegExp(r'\b(GET|POST|PUT|PATCH|DELETE) /'),
    'jerga nuestra': RegExp(
      r'\b(servidor|migraci[óo]n|disparador|transacci[óo]n|RLS|company_id|'
      r'endpoint|JSON|UUID|HTTP|cursor)\b',
      caseSensitive: false,
    ),
  };

  /// Los textos de una línea de código, **sin lo que sea comentario**.
  ///
  /// ⚠️ **EL COMENTARIO SE CORTA MIRANDO LAS COMILLAS**, no a la primera `//`: una `//`
  /// dentro de un texto —`'http://…'`— cortaría la línea a la mitad y dejaría de leer lo
  /// que de verdad importa. Se corta en la primera `//` que tenga **un número par** de
  /// comillas detrás, que es la que está fuera de un texto.
  List<String> textosDe(String linea) {
    final limpia = linea.trimLeft();

    // UN COMENTARIO ENTERO NO TIENE TEXTOS, y un `import` tampoco: su ruta lleva comillas
    // y no es nada que nadie lea en pantalla.
    if (limpia.startsWith('//') ||
        limpia.startsWith('import ') ||
        limpia.startsWith('export ') ||
        limpia.startsWith('part ')) {
      return const [];
    }

    var codigo = linea;

    for (var i = 0; i + 1 < codigo.length; i++) {
      if (codigo[i] != '/' || codigo[i + 1] != '/') continue;

      final antes = codigo.substring(0, i);
      final comillas = antes.split("'").length - 1;

      if (comillas.isEven) {
        codigo = antes;
        break;
      }
    }

    return [
      for (final m in RegExp(r"'((?:[^'\\\n]|\\.)*)'").allMatches(codigo))
        m.group(1) ?? '',
    ];
  }

  /// Lo que un archivo enseña y no debería.
  List<String> jergaDe(File archivo) {
    final hallados = <String>[];
    final lineas = archivo.readAsLinesSync();

    for (var i = 0; i < lineas.length; i++) {
      for (final texto in textosDe(lineas[i])) {
        for (final entrada in prohibido.entries) {
          if (!entrada.value.hasMatch(texto)) continue;

          hallados.add(
            '${normalizar(archivo.path)}:${i + 1} — ${entrada.key}: «$texto»',
          );
        }
      }
    }

    return hallados;
  }

  group('ninguna pantalla enseña nuestro vocabulario', () {
    test('ni números nuestros ni jerga', () {
      final hallados = [for (final f in fuentes()) ...jergaDe(f)];

      expect(
        hallados,
        isEmpty,
        reason:
            'Estos textos se leen en pantalla y llevan vocabulario nuestro: un número '
            'de migración, de deuda o de etapa, un código de estado, o una palabra de '
            'nuestra plomería.\n\n'
            'Se arregla diciendo **qué pasa y qué hacer**, en lenguaje de operación. '
            'La razón de la regla va en el código, que es donde sirve.\n\n'
            '${hallados.join('\n')}',
      );
    });

    test('y el detector encuentra los textos', () {
      // LA RED DE LA RED: si la extracción dejara de ver textos, esto pasaría vacío y
      // dejaría de proteger sin avisar.
      final cuantos = [
        for (final f in fuentes())
          for (final l in f.readAsLinesSync()) ...textosDe(l),
      ].length;

      expect(
        cuantos,
        greaterThan(500),
        reason:
            'El detector encontró $cuantos textos en las pantallas de la web, y hay '
            'muchos más: dejó de mirar. Revisa `textosDe`.',
      );
    });

    test('y CAZA el texto que el dueño leyó en el ensayo', () {
      // Un candado que nunca se vio fallar no es un candado. Ésta es la línea exacta que
      // estaba en el expediente de un servicio.
      const comoEstaba =
          '            descripcion:\n'
          "                'Dónde se presta el servicio. Se corrige, pero no se puede "
          "quitar: '\n"
          "                'desde la 0059 no existe un servicio sin domicilio "
          "operativo.',";

      final cazados = [
        for (final linea in comoEstaba.split('\n'))
          for (final texto in textosDe(linea))
            for (final entrada in prohibido.entries)
              if (entrada.value.hasMatch(texto)) entrada.key,
      ];

      expect(cazados, contains('un número de migración'));
    });

    test('y NO se queja de una `//` que vive dentro de un texto', () {
      // El falso positivo que tendría un corte ingenuo: cortar a la primera `//` dejaría
      // `'https:` abierto y el resto de la línea sin leer.
      expect(
        textosDe("      const sitio = 'https://seventra.mx/ayuda';"),
        ['https://seventra.mx/ayuda'],
      );
    });

    test('y SÍ lee un texto con un comentario detrás', () {
      expect(
        textosDe("      label: 'Guardar', // el botón de siempre"),
        ['Guardar'],
      );
    });
  });
}
