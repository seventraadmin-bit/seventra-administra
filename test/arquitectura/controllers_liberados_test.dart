// Que ningún `TextEditingController` de la web nazca en el punto donde se usa.
//
// ## Por qué este candado existe, y quién lo necesitó
//
// Lo necesité yo, escribiendo el expediente de un cliente: los tres campos de sólo
// lectura —folio, inicio de la relación y última actualización— los pinté con
// `controller: TextEditingController(text: …)` dentro del `build`. Compila, se ve bien y
// **pierde un controlador en cada repintado**, que en esa pantalla es uno por tecla.
//
// Es el mismo error que este proyecto ya tiene anotado como lección —liberar los
// controllers de un diálogo no es opcional, y `Future.delayed(300ms)` para «esperar la
// animación» está prohibido— y no lo caza nada: no falla, no avisa y no sale en
// `analyze`. Lo único que lo caza es mirar la forma.
//
// ## Qué vigila exactamente, y por qué esa forma y no otra
//
// **`controller: TextEditingController(`**, que es el constructor en el argumento. No se
// intenta averiguar si está dentro de un `build` —eso pide un analizador, no un `grep`— y
// no hace falta: un controlador creado en el argumento **no lo posee nadie**, así que no
// hay un `dispose` que pueda liberarlo. Si lo que se quiere es un campo de sólo lectura,
// el controlador va en el estado y su texto se pone al cargar.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String normalizar(String ruta) => ruta.replaceAll(r'\', '/');

  /// Los archivos de la web, que son los únicos a los que la regla aplica: el escritorio
  /// tiene su propia disciplina y sus propias pruebas desde antes de la mudanza.
  List<File> fuentesDeLaWeb() => Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) {
        final ruta = normalizar(f.path);

        return ruta.endsWith('.dart') &&
            !ruta.endsWith('.g.dart') &&
            (ruta.contains('/web/') || ruta.contains('/core/direcciones/'));
      })
      .toList();

  /// El código sin las líneas de comentario: esta prueba y su explicación **nombran** el
  /// patrón, y nombrarlo no es escribirlo. Es el séptimo tropiezo del proyecto con un
  /// guardia que se disparaba contra su propia explicación.
  Iterable<String> codigo(File f) => f.readAsLinesSync().where((l) {
    final t = l.trimLeft();

    return !t.startsWith('//') && !t.startsWith('///') && !t.startsWith('*');
  });

  test('ningún controlador de la web nace en el argumento donde se usa', () {
    final culpables = <String>[];

    for (final archivo in fuentesDeLaWeb()) {
      for (final linea in codigo(archivo)) {
        if (!linea.contains('controller: TextEditingController(')) continue;

        culpables.add('${normalizar(archivo.path)} → ${linea.trim()}');
      }
    }

    expect(
      culpables,
      isEmpty,
      reason:
          'Un `TextEditingController` creado en el argumento no lo posee nadie, así que '
          'no hay `dispose` que lo libere: se pierde uno en CADA repintado.\n\n'
          'Si el campo es de sólo lectura, el controlador va en el estado y su texto se '
          'pone al cargar —como hace el expediente de un cliente con el folio—.'
          '\n\n${culpables.join('\n')}',
    );
  });

  test('el candado mira archivos de verdad, y los que tienen formularios', () {
    // LA RED DE LA RED: sin esto, mover una carpeta dejaría un guardia que enumera cero
    // archivos y pasa siempre. Se acota con «al menos», nunca con un total.
    final rutas = [for (final f in fuentesDeLaWeb()) normalizar(f.path)];

    expect(rutas.length, greaterThan(20));
    expect(
      rutas,
      contains(
        'lib/features/comercial/web/presentation/expediente_cliente_web_screen.dart',
      ),
    );
    expect(
      rutas,
      contains(
        'lib/features/organizacion/web/presentation/expediente_sucursal_web_screen.dart',
      ),
    );
  });
}
