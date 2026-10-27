import 'package:flutter_test/flutter_test.dart';
import 'package:riseg_one/core/fechas/fecha_en_pantalla.dart';

/// Cómo se escribe una fecha del servidor en la pantalla.
///
/// **POR QUÉ ESTAS PRUEBAS NO FIJAN UNA ZONA.** Dart no deja cambiar la zona local en
/// ejecución, así que una prueba que afirmara «un instante UTC se ve así» sólo valdría en
/// la máquina de quien la escribió — y es justo la clase de dependencia que esta tanda
/// vino a quitar. Así que se prueba lo que es cierto en cualquier zona: con una fecha
/// **ya local** el texto es exacto, y con un instante en UTC el texto es el de su
/// conversión a local, nunca el del reloj UTC.
void main() {
  group('fechaCorta', () {
    test('una fecha local se escribe con el mes en letras', () {
      // El mes en letras a propósito: `3/10/2026` y `10/3/2026` se leen distinto según
      // de dónde sea quien mira, y una fecha no debería necesitar contexto.
      expect(fechaCorta(DateTime(2026, 10, 3)), '3/oct/2026');
      expect(fechaCorta(DateTime(2026, 1, 31)), '31/ene/2026');
      expect(fechaCorta(DateTime(2026, 12, 1)), '1/dic/2026');
    });

    test('un instante en UTC se convierte a la zona de quien mira', () {
      final instante = DateTime.utc(2026, 10, 1, 12);
      final local = instante.toLocal();

      expect(fechaCorta(instante), '${local.day}/oct/${local.year}');

      // Y LO QUE DE VERDAD IMPORTA: que el día salga del reloj LOCAL. En una máquina al
      // oeste de Greenwich un instante de las 02:00 UTC es el día anterior, y sin
      // `toLocal()` la pantalla diría el día de UTC. La comprobación es vacía en una
      // máquina donde los dos días coinciden, y en México —que es donde se usa— no.
      final deMadrugada = DateTime.utc(2026, 10, 1, 2);

      expect(
        fechaCorta(deMadrugada),
        '${deMadrugada.toLocal().day}/'
        '${deMadrugada.toLocal().month == 9 ? 'sep' : 'oct'}/2026',
      );
    });
  });

  group('fechaYHora', () {
    test('lleva la hora, que en una bitácora es parte del dato', () {
      expect(fechaYHora(DateTime(2026, 10, 18, 13, 45)), '18/oct/2026 13:45');
    });

    test('el día y la hora de un dígito van con cero delante', () {
      // Sin el cero, una columna de horas no se puede leer de un vistazo.
      expect(fechaYHora(DateTime(2026, 3, 5, 9, 7)), '05/mar/2026 09:07');
    });

    test('un instante en UTC también se convierte', () {
      final instante = DateTime.utc(2026, 10, 18, 19, 45);
      final local = instante.toLocal();

      expect(
        fechaYHora(instante),
        '${local.day.toString().padLeft(2, '0')}/oct/${local.year} '
        '${local.hour.toString().padLeft(2, '0')}:45',
      );
    });
  });

  group('los doce meses', () {
    test('ninguno falta ni se repite', () {
      // Un arreglo de meses con un hueco o un duplicado se descubre en noviembre, en
      // pantalla, y no antes.
      final nombres = [
        for (var mes = 1; mes <= 12; mes++) fechaCorta(DateTime(2026, mes, 1)).split('/')[1],
      ];

      expect(nombres.toSet().length, 12);
      expect(nombres.first, 'ene');
      expect(nombres.last, 'dic');
    });
  });
}
