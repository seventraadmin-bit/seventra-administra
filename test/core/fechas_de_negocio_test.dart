import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Que la web **no calcule un día de negocio con el reloj UTC**.
///
/// ## Por qué existe, si hoy no hay ningún caso
///
/// El 25 de octubre de 2026 el dueño encontró este error en el servidor: el día de hoy
/// se calculaba con `DateOnly.FromDateTime(…UtcNow…)`, y de las 18:00 a las 23:59 de la
/// Ciudad de México el día UTC **ya es el siguiente**. Estaba copiado en **ocho** sitios.
/// La web se revisó entera y está limpia: lo único que convierte a UTC son caducidades
/// de token y el sello de un respaldo portable —instantes, donde UTC es lo correcto—, y
/// los dos sitios que pintan un instante como fecha llaman a `toLocal()` primero.
///
/// **Este candado es preventivo, y el riesgo tiene fecha:** con las pantallas de Clientes
/// la web va a proponer «hoy» como fecha de inicio (deuda **D-55**). Si ese «hoy» sale de
/// `DateTime.now().toUtc()`, de las 18:00 a las 23:59 propondrá **mañana** — y nadie lo
/// notará, porque de día funciona.
///
/// ## Qué NO vigila, y por qué
///
/// No prohíbe `toUtc()`: un **instante** en UTC es correcto y es lo que hace la sesión.
/// Lo que prohíbe es **la combinación** `DateTime.now().toUtc()`, que es «ahora» llevado
/// a otro reloj — el único motivo para escribirla es derivar un día o compararlo, y en
/// los dos casos el reloj equivocado.
void main() {
  /// Lo que no puede aparecer: «ahora» convertido a UTC.
  const patron = 'DateTime.now().toUtc()';

  /// Dónde sí es correcto, por ruta exacta.
  ///
  /// El gestor de sesión compara **instantes** —cuándo caduca el token—, y para eso UTC
  /// es el reloj correcto: es el mismo que escribió el servidor. Cada excepción nueva
  /// tiene que aparecer en un diff y explicarse.
  const permitidos = ['lib/core/auth/gestor_de_sesion.dart'];

  /// Las fuentes de la aplicación, sin lo generado.
  List<File> fuentes() {
    final raiz = Directory('lib');

    expect(
      raiz.existsSync(),
      isTrue,
      reason: 'La prueba se corre desde la raíz del repositorio.',
    );

    return raiz
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
  }

  String relativa(File f) => f.path.replaceAll(r'\', '/');

  test('ningún día de negocio sale del reloj UTC', () {
    final copias = <String>[];

    for (final archivo in fuentes()) {
      final ruta = relativa(archivo);
      if (permitidos.contains(ruta)) continue;

      final lineas = archivo.readAsLinesSync();

      for (var i = 0; i < lineas.length; i++) {
        // SE MIRA EL CÓDIGO Y NO LOS COMENTARIOS: esta prueba y la documentación de la
        // deuda NOMBRAN el patrón para explicarlo, y nombrarlo no es copiarlo.
        final linea = lineas[i];
        final comentario = linea.indexOf('//');
        final codigo = comentario >= 0 ? linea.substring(0, comentario) : linea;

        if (!codigo.contains(patron)) continue;

        copias.add('$ruta:${i + 1} → «${linea.trim()}»');
      }
    }

    expect(
      copias,
      isEmpty,
      reason:
          'Hay un «ahora» convertido a UTC. De las 18:00 a las 23:59 de la Ciudad de '
          'México el día UTC YA ES EL SIGUIENTE, así que una fecha propuesta así dice '
          'mañana.\n\nUn instante sí va en UTC —la caducidad de un token—; un DÍA, '
          'nunca.\n\n${copias.join('\n')}',
    );
  });

  test('el candado mira las fuentes de verdad', () {
    // Sin esto, mover la carpeta dejaría un guardia que enumera cero archivos y pasa
    // siempre. Se acota con «al menos», nunca con un total: `lib` crece cada semana.
    final rutas = fuentes().map(relativa).toList();

    expect(rutas.length, greaterThan(200));
    expect(rutas, contains('lib/core/auth/gestor_de_sesion.dart'));
    expect(rutas, contains('lib/main_web.dart'));
  });

  test('el candado distingue el código de la prosa', () {
    // La regla, ejercitada: la misma línea cuenta como copia en código y no cuenta
    // dentro de un comentario. Es lo que deja pasar la explicación del arreglo.
    const codigo = '    final hoy = DateTime.now().toUtc();';
    const prosa = '    // Nunca `DateTime.now().toUtc()` para un día.';

    expect(codigo.contains('DateTime.now().toUtc()'), isTrue);

    expect(
      prosa.substring(0, prosa.indexOf('//')).contains('DateTime.now().toUtc()'),
      isFalse,
    );
  });
}
