// El guardia de salida: quién tiene trabajo sin guardar, y cómo se llama lo que se
// perdería.
//
// NACIÓ EN E1-B para una sola pregunta —la barra inferior cambiando de empresa— y D-56 le
// sumó tres caminos más: el botón «atrás» del navegador, recargar y cerrar la pestaña. El
// guardia no pregunta, responde; quién pregunta está en `docs/diseno-d56-trabajo-sin-guardar.md`.
//
// LAS TRES COSAS QUE ESTAS PRUEBAS FIJAN, y las tres son asimetrías deliberadas:
//
//  1. **sin nadie registrado, NO hay cambios.** De los dos descuidos posibles, éste es el
//     barato: una pantalla que olvide registrarse pierde su protección y se nota la
//     primera vez —y desde D-56 la caza un candado—. El contrario —un registro pegado tras
//     un `dispose`— haría preguntar en CADA navegación por un formulario que ya no existe,
//     y parecería un cuelgue;
//  2. **liberar exige la MISMA función que se registró.** En Flutter el `initState` de la
//     pantalla siguiente corre ANTES del `dispose` de la anterior, así que un `liberar()`
//     sin comprobación borraría el registro que la nueva acaba de poner y la dejaría sin
//     protección, en silencio;
//  3. **un nombre roto no puede impedir la pregunta.** El nombre adorna; lo que protege el
//     trabajo es preguntar.

import 'package:flutter_test/flutter_test.dart';
import 'package:riseg_one/core/company/guardia_de_salida.dart';

void main() {
  /// Un registro cualquiera, cuando lo que se mide no es el nombre.
  String deAlgo() => 'el expediente de la empresa';

  test('sin nadie registrado no hay cambios', () {
    final guardia = GuardiaDeSalida();

    expect(guardia.hayCambiosSinGuardar, isFalse);
    expect(guardia.queSePierde, isNull);
  });

  test('responde lo que diga quien se registró, y EN EL MOMENTO', () {
    // Se consulta al preguntar y no al registrar: una pantalla registra una vez y su
    // formulario se ensucia después. Guardar el valor en vez de la función diría «no hay
    // cambios» para siempre.
    var sucio = false;
    final guardia = GuardiaDeSalida()
      ..registrar(() => sucio, queSePierde: deAlgo);

    expect(guardia.hayCambiosSinGuardar, isFalse);

    sucio = true;
    expect(guardia.hayCambiosSinGuardar, isTrue);
  });

  group('con varios registrados', () {
    test('basta que UNO tenga cambios', () {
      // ⚠️ ESTA PRUEBA AFIRMABA LO CONTRARIO —«el último en registrarse manda»— y cambió
      // con D-56, porque el guardia guardaba UNO solo.
      //
      // Lo rompió el primer caso real de la regla «toda pantalla con Guardar se registra»:
      // un panel de alta abierto ENCIMA de una pantalla. Los dos están montados y los dos
      // tienen algo que perder; con un solo hueco, el panel sobrescribía a la pantalla y
      // al cerrarse la dejaba SIN PROTECCIÓN. Así que ahora no manda el último: manda que
      // alguno tenga cambios.
      final guardia = GuardiaDeSalida()
        ..registrar(() => true, queSePierde: deAlgo)
        ..registrar(() => false, queSePierde: deAlgo);

      expect(guardia.hayCambiosSinGuardar, isTrue);
    });

    test('cerrar el de encima NO desprotege al de debajo', () {
      // EL CASO QUE OBLIGÓ AL CAMBIO, dicho en sus propios términos: la pantalla tiene
      // cambios, se abre un panel encima, el panel se cierra limpio — y la pantalla sigue
      // protegida.
      bool deLaPantalla() => true;
      bool delPanel() => false;

      final guardia = GuardiaDeSalida()
        ..registrar(deLaPantalla, queSePierde: () => 'el expediente de la empresa')
        ..registrar(delPanel, queSePierde: () => 'la nueva sucursal')
        ..liberar(delPanel);

      expect(guardia.hayCambiosSinGuardar, isTrue);
      expect(guardia.queSePierde, 'el expediente de la empresa');
    });

    test('nombra el de ENCIMA de los que tienen cambios', () {
      // El de encima es el que la persona está mirando. Nombrar el de debajo sería
      // correcto y desconcertante: preguntaría por algo que no tiene delante.
      final guardia = GuardiaDeSalida()
        ..registrar(() => true, queSePierde: () => 'el expediente de la empresa')
        ..registrar(() => true, queSePierde: () => 'la nueva sucursal');

      expect(guardia.queSePierde, 'la nueva sucursal');
    });

    test('y salta a los que NO tienen cambios para nombrar', () {
      // Un panel abierto y vacío no es lo que se perdería: lo que se perdería es la
      // pantalla de debajo, y es ésa la que hay que nombrar.
      final guardia = GuardiaDeSalida()
        ..registrar(() => true, queSePierde: () => 'el expediente de la empresa')
        ..registrar(() => false, queSePierde: () => 'la nueva sucursal');

      expect(guardia.queSePierde, 'el expediente de la empresa');
    });
  });

  test('liberar con OTRA función no borra el registro vigente', () {
    // EL ORDEN REAL DE FLUTTER, reproducido: la pantalla A registra, la B registra al
    // montarse, y A libera al desmontarse DESPUÉS. Sin la comprobación, B se queda sin
    // protección y nadie se enteraría.
    bool deA() => false;
    bool deB() => true;

    final guardia = GuardiaDeSalida()
      ..registrar(deA, queSePierde: deAlgo)
      ..registrar(deB, queSePierde: deAlgo)
      ..liberar(deA);

    expect(
      guardia.hayCambiosSinGuardar,
      isTrue,
      reason: 'el registro de B tiene que seguir en pie',
    );
  });

  test('liberar con la MISMA función sí lo suelta', () {
    bool hayCambios() => true;

    final guardia = GuardiaDeSalida()
      ..registrar(hayCambios, queSePierde: deAlgo);
    expect(guardia.hayCambiosSinGuardar, isTrue);

    guardia.liberar(hayCambios);
    expect(guardia.hayCambiosSinGuardar, isFalse);
  });

  test('liberar algo que no está registrado no hace nada', () {
    // Pasa de verdad: `dispose` corre aunque `initState` haya salido por una excepción.
    // Reventar aquí convertiría un formulario roto en una aplicación rota.
    bool registrada() => true;
    bool nunca() => true;

    final guardia = GuardiaDeSalida()
      ..registrar(registrada, queSePierde: deAlgo)
      ..liberar(nunca);

    expect(guardia.hayCambiosSinGuardar, isTrue);
  });

  group('lo que no puede tumbar la pregunta', () {
    test('una pantalla que lanza NO deja el producto preguntando siempre', () {
      // Una pantalla rota es un problema de esa pantalla; preguntar en cada navegación
      // por un formulario fantasma es un problema de todos.
      final guardia = GuardiaDeSalida()
        ..registrar(() => throw StateError('formulario roto'), queSePierde: deAlgo);

      expect(guardia.hayCambiosSinGuardar, isFalse);
    });

    test('un NOMBRE que lanza deja la pregunta en pie, sin nombre', () {
      // ⚠️ LA ASIMETRÍA VA AL CONTRARIO QUE ARRIBA, y es a propósito: el nombre adorna la
      // pregunta y la pregunta protege el trabajo. Tragarse la pregunta porque el nombre
      // falló tiraría lo escrito por un adorno.
      final guardia = GuardiaDeSalida()
        ..registrar(() => true, queSePierde: () => throw StateError('sin nombre'));

      expect(guardia.hayCambiosSinGuardar, isTrue);
      expect(guardia.queSePierde, isNull);
    });

    test('un nombre VACÍO se trata como ausente', () {
      // Ausencia nunca es un hueco en la frase: «Tienes cambios sin guardar en .» no se
      // le enseña a nadie. Quien pregunta usa su frase genérica.
      final guardia = GuardiaDeSalida()
        ..registrar(() => true, queSePierde: () => '   ');

      expect(guardia.queSePierde, isNull);
    });
  });
}
