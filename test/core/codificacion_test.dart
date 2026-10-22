// Que ningún archivo del repositorio tenga los acentos destrozados.
//
// ===========================================================================
// POR QUÉ ESTA PRUEBA EXISTE
// ===========================================================================
//
// El 22 de octubre de 2026 edité `empresas_web_screen.dart` con `Set-Content` de
// PowerShell para quitarle unas líneas. PowerShell 5.1 leyó el archivo —UTF-8 sin BOM—
// con la página de códigos ANSI de Windows y lo escribió otra vez como UTF-8, así que
// cada carácter acentuado quedó **doblemente codificado**: `Dónde` → `DÃ³nde`,
// `propósito` → `propÃ³sito`, `perderá` → `perderÃ¡`.
//
// Y PASÓ DESAPERCIBIDO HASTA QUE SE COMITEÓ Y SE EMPUJÓ, porque nada de lo que
// normalmente vigila el código mira los acentos:
//
//  · `dart analyze` no se queja: son cadenas y comentarios válidos;
//  · las pruebas tampoco: ninguna afirmaba sobre un texto con acentos de ese archivo;
//  · y en pantalla sólo se habría visto al abrir un camino concreto.
//
// O sea: un daño que el código acepta, las pruebas acepten y la pantalla casi esconde.
// Eso es exactamente lo que un guardia tiene que cazar.
//
// ===========================================================================
// CÓMO LO DETECTA
// ===========================================================================
//
// No busca «acentos raros»: busca las **secuencias imposibles** que produce esa doble
// codificación. `Ã`, `Â` y `â` seguidas de otro carácter no-ASCII no aparecen nunca en
// español, ni en inglés, ni en ningún texto que este proyecto escriba — pero son
// exactamente lo que sale de leer UTF-8 como cp1252.
//
// Mira TAMBIÉN los comentarios, al contrario que los guardias de arquitectura: aquí el
// comentario es parte de lo que se daña, y de hecho es donde se dañó.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Las secuencias que delatan una doble codificación.
///
/// Son pares: `Ã` o `Â` o `â` **seguidos de un carácter no ASCII**. Buscar `Ã` a secas
/// daría falsos positivos en cualquier texto que hable de la letra; buscar el par no,
/// porque es una combinación que ningún idioma produce.
const _delatores = ['Ã', 'Â', 'â€'];

/// Archivos que contienen esas secuencias **a propósito**, porque hablan de este mismo
/// problema. Son rutas exactas, no carpetas: cada excepción nueva tiene que aparecer en
/// un diff y explicarse.
const _permitidos = <String>[
  // Esta prueba, obviamente: lleva los delatores en sus propias constantes y en esta
  // explicación.
  'test/core/codificacion_test.dart',
];

void main() {
  List<File> fuentes() => [
    for (final raiz in ['lib', 'test'])
      ...Directory(raiz)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart')),
  ];

  String normalizar(String ruta) => ruta.replaceAll('\\', '/');

  test('ningún .dart tiene acentos doblemente codificados', () {
    final danados = <String>[];

    for (final archivo in fuentes()) {
      final ruta = normalizar(archivo.path);
      if (_permitidos.contains(ruta)) continue;

      // SE LEE COMO UTF-8 ESTRICTO: un archivo que no sea UTF-8 válido también es un
      // problema, y `readAsStringSync` con `allowMalformed: false` lo dice en vez de
      // sustituir silenciosamente los bytes raros por `�`.
      final contenido = archivo.readAsStringSync();
      final lineas = contenido.split('\n');

      for (var i = 0; i < lineas.length; i++) {
        for (final delator in _delatores) {
          if (!lineas[i].contains(delator)) continue;

          danados.add('$ruta:${i + 1} → «${lineas[i].trim()}»');
          break;
        }
      }
    }

    expect(
      danados,
      isEmpty,
      reason:
          'Hay acentos doblemente codificados. Pasa al editar con `Set-Content` de '
          'PowerShell o con `sed`: leen el archivo con la página de códigos ANSI y lo '
          'reescriben como UTF-8.\n\n'
          'SE ARREGLA SIN TOCAR NADA A MANO, porque el daño es reversible y exacto:\n'
          '  \$b = [IO.File]::ReadAllBytes(\$ruta)\n'
          '  \$t = [Text.Encoding]::UTF8.GetString(\$b)\n'
          '  [IO.File]::WriteAllBytes(\$ruta, '
          '[Text.Encoding]::GetEncoding(1252).GetBytes(\$t))\n\n'
          'Y para no repetirlo: el código se edita con la herramienta de edición, '
          'nunca con `sed` ni con `Set-Content`.\n\n'
          '${danados.join('\n')}',
    );
  });

  test('ningún .dart empieza con BOM', () {
    // EL BOM ES EL RASTRO DEL MISMO ACCIDENTE: `Set-Content -Encoding utf8` en
    // PowerShell 5.1 lo añade, y ningún `.dart` de este repositorio lo lleva. No rompe
    // nada por sí solo —Dart lo tolera— pero encontrarlo significa que ese archivo pasó
    // por una herramienta que no debía tocarlo, y entonces conviene mirarle los acentos.
    // ESTOS TRES YA LO TRAÍAN ANTES DE ESTA PRUEBA, y sus acentos están bien —lo afirma
    // la prueba de arriba, que los mira igual—. Se nombran en vez de reescribirlos:
    // tocar tres archivos ajenos para satisfacer un guardia nuevo es cambiar código que
    // nadie pidió, y el BOM por sí solo no rompe nada.
    //
    // Lo que esta prueba protege es que **no aparezca uno nuevo**.
    const deAntes = <String>[
      'lib/features/usuarios/web/presentation/auditoria_legible.dart',
      'test/features/dashboard/dashboard_usecases_test.dart',
      'test/features/nomina/nomina_integration_test.dart',
    ];

    final conBom = <String>[];

    for (final archivo in fuentes()) {
      if (deAntes.contains(normalizar(archivo.path))) continue;

      final bytes = archivo.openSync().readSync(3);

      if (bytes.length == 3 &&
          bytes[0] == 0xEF &&
          bytes[1] == 0xBB &&
          bytes[2] == 0xBF) {
        conBom.add(normalizar(archivo.path));
      }
    }

    expect(conBom, isEmpty, reason: 'Archivos con BOM:\n${conBom.join('\n')}');
  });
}
