// Política del portapapeles para datos sensibles y apertura de enlaces.
//
// Lo que se protege aquí no es la contraseña: es el portapapeles de la
// persona. Borrar lo que copió después sería peor que dejar la contraseña
// un minuto de más.

import 'package:flutter_test/flutter_test.dart';
import 'package:riseg_one/core/security/abridor_enlaces.dart';
import 'package:riseg_one/core/security/portapapeles_sensible.dart';

/// Portapapeles de mentira, para poder adelantar el vencimiento y simular
/// que alguien copió otra cosa.
class _PortapapelesFalso implements AccesoPortapapeles {
  String? contenido;
  int escrituras = 0;

  @override
  Future<void> escribir(String texto) async {
    contenido = texto;
    escrituras++;
  }

  @override
  Future<String?> leer() async => contenido;
}

void main() {
  group('Limpieza del portapapeles', () {
    test('1. copiar coloca exactamente el valor', () async {
      final falso = _PortapapelesFalso();
      final portapapeles = PortapapelesSensible(acceso: falso);

      await portapapeles.copiarTemporal('Contrasena-A');

      expect(falso.contenido, 'Contrasena-A');
      portapapeles.cancelar();
    });

    test('2. al vencer, si sigue siendo la misma contraseña, se limpia', () async {
      final falso = _PortapapelesFalso();
      final portapapeles = PortapapelesSensible(acceso: falso);
      await portapapeles.copiarTemporal('Contrasena-A');

      await portapapeles.limpiarSiSigueSiendoNuestro();

      expect(falso.contenido, '', reason: 'la contraseña deja de estar disponible');
    });

    test('3. si la persona copió otra cosa, NO se toca', () async {
      final falso = _PortapapelesFalso();
      final portapapeles = PortapapelesSensible(acceso: falso);
      await portapapeles.copiarTemporal('Contrasena-A');

      // El usuario copia un número de cuenta.
      falso.contenido = '012180001234567890';

      await portapapeles.limpiarSiSigueSiendoNuestro();

      expect(
        falso.contenido,
        '012180001234567890',
        reason: 'borrar contenido ajeno sería peor que dejar la contraseña',
      );
    });

    test('4. dos contraseñas seguidas: el temporizador de A no borra B', () async {
      final falso = _PortapapelesFalso();
      final portapapeles = PortapapelesSensible(acceso: falso);

      await portapapeles.copiarTemporal('Contrasena-A');
      await portapapeles.copiarTemporal('Contrasena-B');

      // Vence la ventana vigente, que es la de B.
      await portapapeles.limpiarSiSigueSiendoNuestro();
      expect(falso.contenido, '');

      // Y si algo volviera a disparar la limpieza, ya no hay nada pendiente:
      // no puede borrar lo que la persona copie a continuación.
      falso.contenido = 'algo del usuario';
      await portapapeles.limpiarSiSigueSiendoNuestro();
      expect(falso.contenido, 'algo del usuario');
    });

    test('5. cancelar desactiva la limpieza sin tocar el portapapeles', () async {
      final falso = _PortapapelesFalso();
      final portapapeles = PortapapelesSensible(acceso: falso);
      await portapapeles.copiarTemporal('Contrasena-A');

      // `cancelar()` sólo se usa al morir el contenedor (cierre de la
      // aplicación), NUNCA al cerrar la ficha: ahí la limpieza debe seguir.
      portapapeles.cancelar();
      await portapapeles.limpiarSiSigueSiendoNuestro();

      expect(falso.contenido, 'Contrasena-A');
    });

    test('6. cerrar la ficha NO cancela la limpieza pendiente', () async {
      final falso = _PortapapelesFalso();
      // El servicio vive en el contenedor, no en el diálogo: cerrar la ficha
      // no lo toca. Se simula exactamente eso — nadie llama a cancelar.
      final portapapeles = PortapapelesSensible(acceso: falso);
      await portapapeles.copiarTemporal('Contrasena-A');

      // ...la ficha se cierra aquí, sin efecto alguno sobre el servicio...
      await portapapeles.limpiarSiSigueSiendoNuestro();

      expect(falso.contenido, '', reason: 'antes, cerrar dejaba la contraseña indefinidamente en el portapapeles');
    });

    test('7. cerrar la ficha y copiar otra cosa: lo del usuario se respeta', () async {
      final falso = _PortapapelesFalso();
      final portapapeles = PortapapelesSensible(acceso: falso);
      await portapapeles.copiarTemporal('Contrasena-A');

      // Cierra la ficha y copia una CLABE.
      falso.contenido = 'CLABE 012345678901234567';
      await portapapeles.limpiarSiSigueSiendoNuestro();

      expect(falso.contenido, 'CLABE 012345678901234567');
    });

    test('8. A, luego B, luego cerrar: sólo vence B, y sólo si sigue siendo B', () async {
      final falso = _PortapapelesFalso();
      final portapapeles = PortapapelesSensible(acceso: falso);

      await portapapeles.copiarTemporal('Contrasena-A');
      await portapapeles.copiarTemporal('Contrasena-B');

      // La ficha se cierra; la limpieza pendiente sigue siendo la de B.
      await portapapeles.limpiarSiSigueSiendoNuestro();
      expect(falso.contenido, '', reason: 'se limpió B, no A');

      // Y no queda ninguna otra pendiente que pueda borrar lo siguiente.
      falso.contenido = 'texto posterior del usuario';
      await portapapeles.limpiarSiSigueSiendoNuestro();
      expect(falso.contenido, 'texto posterior del usuario');
    });

    test('9. una sola limpieza pendiente: la referencia se suelta al usarla', () async {
      final falso = _PortapapelesFalso();
      final portapapeles = PortapapelesSensible(acceso: falso);
      await portapapeles.copiarTemporal('Contrasena-A');

      await portapapeles.limpiarSiSigueSiendoNuestro();
      // Segunda invocación: ya no hay nada pendiente que comparar, así que
      // no puede tocar lo que haya ahora.
      falso.contenido = 'Contrasena-A';
      await portapapeles.limpiarSiSigueSiendoNuestro();

      expect(falso.contenido, 'Contrasena-A');
    });
  });

  group('Apertura de enlaces', () {
    test('10. sólo http y https se consideran abribles', () {
      expect(AbridorEnlaces.esAbrible('https://portal.sat.gob.mx'), isTrue);
      expect(AbridorEnlaces.esAbrible('http://intranet.local'), isTrue);
      expect(AbridorEnlaces.esAbrible('file:///C:/Windows/System32'), isFalse);
      expect(AbridorEnlaces.esAbrible('javascript:alert(1)'), isFalse);
      expect(AbridorEnlaces.esAbrible('ftp://algo'), isFalse);
    });

    test('11. texto que no es una dirección no rompe ni se abre', () {
      expect(AbridorEnlaces.esAbrible(null), isFalse);
      expect(AbridorEnlaces.esAbrible(''), isFalse);
      expect(AbridorEnlaces.esAbrible('   '), isFalse);
      expect(AbridorEnlaces.esAbrible('portal sin esquema'), isFalse);
      expect(AbridorEnlaces.esAbrible('https://'), isFalse, reason: 'sin host no hay a dónde ir');
    });

    test('12. una dirección con metacaracteres de shell no se considera especial', () async {
      // No hay intérprete de por medio: el texto viaja como argumento.
      // Aquí sólo se comprueba la decisión, no se ejecuta nada.
      expect(AbridorEnlaces.esAbrible(r'https://ok.mx/a&calc.exe'), isTrue);
      expect(AbridorEnlaces.esAbrible(r'& calc.exe'), isFalse);
      expect(await const AbridorEnlaces().abrir('no es una url'), isFalse);
    });
  });
}
