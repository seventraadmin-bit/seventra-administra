// El guardia de salida (E1-B): quién tiene trabajo sin guardar cuando la barra
// inferior quiere cambiar de empresa.
//
// LAS DOS COSAS QUE ESTAS PRUEBAS FIJAN, y las dos son asimetrías deliberadas:
//
//  1. **sin nadie registrado, NO hay cambios.** De los dos descuidos posibles, éste es
//     el barato: una pantalla que olvide registrarse pierde su protección y se nota la
//     primera vez. El contrario —un guardia pegado tras un `dispose`— bloquearía el
//     cambio de empresa para siempre y parecería un cuelgue;
//  2. **liberar exige la MISMA función que se registró.** En Flutter el `initState` de
//     la pantalla siguiente corre ANTES del `dispose` de la anterior, así que un
//     `liberar()` sin comprobación borraría el guardia que la nueva acaba de poner y la
//     dejaría sin protección, en silencio.

import 'package:flutter_test/flutter_test.dart';
import 'package:riseg_one/core/company/guardia_de_salida.dart';

void main() {
  test('sin nadie registrado no hay cambios', () {
    expect(GuardiaDeSalida().hayCambiosSinGuardar, isFalse);
  });

  test('responde lo que diga quien se registró, y EN EL MOMENTO', () {
    // Se consulta al preguntar y no al registrar: una pantalla registra una vez y su
    // formulario se ensucia después. Guardar el valor en vez de la función diría «no
    // hay cambios» para siempre.
    var sucio = false;
    final guardia = GuardiaDeSalida()..registrar(() => sucio);

    expect(guardia.hayCambiosSinGuardar, isFalse);

    sucio = true;
    expect(guardia.hayCambiosSinGuardar, isTrue);
  });

  test('el último en registrarse manda', () {
    final guardia = GuardiaDeSalida()
      ..registrar(() => true)
      ..registrar(() => false);

    expect(guardia.hayCambiosSinGuardar, isFalse);
  });

  test('liberar con OTRA función no borra el guardia vigente', () {
    // EL ORDEN REAL DE FLUTTER, reproducido: la pantalla A registra, la B registra al
    // montarse, y A libera al desmontarse DESPUÉS. Sin la comprobación, B se queda sin
    // guardia y nadie se enteraría.
    bool deA() => false;
    bool deB() => true;

    final guardia = GuardiaDeSalida()
      ..registrar(deA)
      ..registrar(deB)
      ..liberar(deA);

    expect(
      guardia.hayCambiosSinGuardar,
      isTrue,
      reason: 'el guardia de B tiene que seguir en pie',
    );
  });

  test('liberar con la MISMA función sí lo suelta', () {
    bool hayCambios() => true;

    final guardia = GuardiaDeSalida()..registrar(hayCambios);
    expect(guardia.hayCambiosSinGuardar, isTrue);

    guardia.liberar(hayCambios);
    expect(guardia.hayCambiosSinGuardar, isFalse);
  });

  test('una pantalla que lanza NO deja el producto sin cambiar de empresa', () {
    // Una pantalla rota es un problema de esa pantalla; que nadie pueda volver a
    // cambiar de empresa es un problema de todos.
    final guardia = GuardiaDeSalida()
      ..registrar(() => throw StateError('formulario roto'));

    expect(guardia.hayCambiosSinGuardar, isFalse);
  });
}
