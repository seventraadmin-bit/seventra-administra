// Guardián estático de la regla de reactividad en las eliminaciones
// físicas: "una mutación confirmada → persistencia → invalidación de
// sus consumidores → UI visible actualizada".
//
// Nace de un bug real: borrar un Tiempo Extra lo quitaba de la base y
// dejaba el renglón en la tabla hasta cambiar de pestaña. El diálogo
// llamaba al provider autorizado directo, sin pasar por el controlador
// ni invalidar nada. Siete pantallas tenían exactamente el mismo hueco
// y seis ya lo hacían bien, así que el defecto no se veía como familia.
//
// La regla admite las TRES formas legítimas que ya usa el proyecto:
//   a) el diálogo pasa por un controlador (`...ControllerProvider
//      .notifier`), que recarga su propio listado; o
//   b) la pantalla que lo invoca invalida explícitamente a sus
//      consumidores, o recarga el controlador del módulo, en el mismo
//      método.
//
// Cualquier eliminación física nueva que no haga ninguna de las tres falla
// aquí, en vez de descubrirse usando la aplicación.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Declaración de la función de diálogo, p. ej.
/// `Future<bool> mostrarDialogoEliminarClienteFisicamente(`.
final _declaracion = RegExp(r'^Future<[^>]*>\s+(mostrarDialogo\w*Fisicamente)\s*\(');

/// Uso de esa misma función desde otro archivo.
RegExp _llamada(String nombre) => RegExp('(await|=)\\s*$nombre\\s*\\(');

void main() {
  test('toda eliminación física llega a un controlador o invalida a sus consumidores', () {
    final archivos = Directory('lib/features')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'))
        .toList();

    final contenido = {for (final f in archivos) f.path: f.readAsLinesSync()};

    // 1. Dónde se declara cada diálogo de eliminación física.
    final declaradoEn = <String, String>{};
    contenido.forEach((ruta, lineas) {
      for (final linea in lineas) {
        final m = _declaracion.firstMatch(linea);
        if (m != null) declaradoEn[m.group(1)!] = ruta;
      }
    });

    expect(declaradoEn, isNotEmpty, reason: 'el barrido no encontró ningún diálogo: el patrón quedó obsoleto');

    final incumplimientos = <String>[];

    for (final entrada in declaradoEn.entries) {
      final nombre = entrada.key;
      final rutaDialogo = entrada.value;

      // Forma (a): el propio diálogo pasa por un controlador.
      final porControlador = contenido[rutaDialogo]!.any((l) => l.contains('ControllerProvider.notifier)'));
      if (porControlador) continue;

      // Forma (b): cada llamador invalida en el método que lo invoca.
      final patron = _llamada(nombre);
      contenido.forEach((ruta, lineas) {
        if (ruta == rutaDialogo) return;
        for (var i = 0; i < lineas.length; i++) {
          if (!patron.hasMatch(lineas[i])) continue;

          // Cuerpo del método que contiene la llamada: hasta el primer
          // cierre a dos espacios, que en este proyecto es el fin de un
          // método de clase.
          final cuerpo = <String>[];
          for (var j = i; j < lineas.length; j++) {
            cuerpo.add(lineas[j]);
            if (j > i && lineas[j] == '  }') break;
          }

          // Tres formas legitimas, no dos: invalidar, o recargar el
          // controlador del modulo desde el propio llamador.
          final refresca = cuerpo.any((l) => l.contains('ref.invalidate(') || l.contains('ControllerProvider.notifier)'));
          if (!refresca) {
            incumplimientos.add('$nombre en ${ruta.replaceAll(r'\', '/')}:${i + 1}');
          }
        }
      });
    }

    expect(
      incumplimientos,
      isEmpty,
      reason: 'Estas eliminaciones físicas persisten pero no refrescan nada:\n  ${incumplimientos.join('\n  ')}\n'
          'Pasa la mutación por el controlador del módulo o invalida a sus consumidores en el mismo método.',
    );
  });
}
