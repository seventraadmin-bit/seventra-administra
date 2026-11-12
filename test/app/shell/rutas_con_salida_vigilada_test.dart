// LA OTRA MITAD DE D-56, Y FALTABA: **toda ruta del router pregunta antes de salir.**
//
// ===========================================================================
// POR QUÉ EXISTE, Y ES EL ALTA QUE SE FUE SIN PREGUNTAR (11 DE NOVIEMBRE DE 2026)
// ===========================================================================
//
// El dueño probando C2: escribió un nombre en «Nuevo servicio», cambió a la pestaña
// Clientes y **el alta se fue sin preguntar**. La pantalla hacía todo bien —se registra en
// el `GuardiaDeSalida` con el mixin, y `guardia_cubre_los_formularios_test.dart` lo
// comprobaba y pasaba— pero `/comercial/servicios/nuevo` **no estaba en la lista de rutas
// con `onExit`**, y una ruta sin `onExit` no pregunta. El expediente de un servicio estaba
// igual.
//
// ⚠️ **ERAN DOS REGLAS Y SÓLO UNA TENÍA CANDADO:**
//
//  1. el formulario **se registra** en el guardia → lo vigila `guardia_cubre_los_…`;
//  2. **su dirección pregunta** → no lo vigilaba nadie.
//
// Y la primera verde con la segunda roja **se ve igual que todo bien**: el guardia
// responde «sí hay cambios» y nadie se lo pregunta.
//
// ===========================================================================
// POR QUÉ SE MIDE LEYENDO EL ARCHIVO
// ===========================================================================
//
// Porque lo que puede faltar es **una palabra en una ruta nueva**, y eso no se nota
// montando el router: una ruta sin `onExit` navega perfectamente. La prueba de
// comportamiento —`salida_con_trabajo_sin_guardar_test.dart`— mide las direcciones que
// alguien se acordó de poner; esto mide que **no haya ninguna sin vigilar**, que es
// justamente lo que se olvidó.
//
// Es el mismo tipo de candado que `guardia_cubre_los_formularios_test.dart`: una
// propiedad aplicada a cada caso que encuentre, con una cota inferior para que dejar de
// encontrar nada no se vea como «todo bien».

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final fuente = File('lib/app/shell/router_web.dart').readAsStringSync();

  /// Cada `GoRoute(` del router, con lo que lleva dentro hasta el siguiente.
  ///
  /// No es un analizador de Dart y no hace falta que lo sea: las rutas de este archivo se
  /// escriben una tras otra, así que partir por `GoRoute(` deja un trozo por ruta.
  List<String> rutas() {
    final trozos = fuente.split('GoRoute(');

    // EL PRIMER TROZO ES LO DE ANTES de la primera ruta, y no es una ruta.
    return trozos.skip(1).toList();
  }

  group('toda ruta del router vigila la salida', () {
    test('ninguna se queda sin `onExit`', () {
      final sinVigilar = <String>[];

      for (final ruta in rutas()) {
        if (ruta.contains('onExit:')) continue;

        // Se nombra por su `path`, que es lo que alguien necesita leer para arreglarlo.
        final path = RegExp(r"path: '([^']*)'").firstMatch(ruta)?.group(1);

        sinVigilar.add(path ?? ruta.split('\n').first.trim());
      }

      expect(
        sinVigilar,
        isEmpty,
        reason:
            'Estas rutas del router NO llevan `onExit`, así que salir de ellas no '
            'pregunta y lo escrito en un formulario que viva ahí se pierde callado — '
            'que es exactamente lo que le pasó al alta de un servicio el 11 de '
            'noviembre de 2026.\n\n'
            'Se arregla con `onExit: (context, _) => seguroDeSalir(context, guardia)`. '
            'No hace falta saber si en esa dirección hay un formulario: quien decide es '
            'el guardia, y sin nadie registrado con cambios no pinta nada.\n\n'
            '${sinVigilar.join('\n')}',
      );
    });

    test('y el detector SÍ encuentra las rutas', () {
      // LA RED DE LA RED: si `GoRoute(` dejara de aparecer —otro paquete, otra forma de
      // declarar— esta prueba pasaría vacía y dejaría de proteger sin avisar. Es el mismo
      // error que «esperaba cero y encontró cero porque no miró».
      expect(
        rutas().length,
        greaterThanOrEqualTo(2),
        reason:
            'El detector no encontró las rutas del router, y las hay: dejó de mirar. '
            'Revisa cómo se declaran en `lib/app/shell/router_web.dart`.',
      );
    });

    test('y el detector CAZA una ruta sin `onExit`', () {
      // Un candado que nunca se vio fallar no es un candado. Aquí se le da de comer una
      // ruta sin vigilancia y tiene que verla.
      const conUnaSuelta = '''
        GoRoute(path: '/', builder: (_, _) => nada, onExit: (c, _) => si(c)),
        GoRoute(path: '/me-olvide', builder: (_, _) => nada),
      ''';

      final sueltas = [
        for (final r in conUnaSuelta.split('GoRoute(').skip(1))
          if (!r.contains('onExit:'))
            RegExp(r"path: '([^']*)'").firstMatch(r)?.group(1),
      ];

      expect(sueltas, ['/me-olvide']);
    });
  });
}
