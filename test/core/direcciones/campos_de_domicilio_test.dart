// C1 · EL DOMICILIO COMPARTIDO: los diez campos, su tabla y su lectura.
//
// ## Por qué esto se prueba solo y no a través de una pantalla
//
// Porque lo usan **dos expedientes** —el de una sucursal y el de un cliente— y en cada
// uno toca **cinco sitios**: el formulario, el volcado al cargar, la lectura al guardar,
// la comparación de un choque y la mezcla de su resultado. Probarlo por la pantalla
// dejaría la mitad de las combinaciones sin mirar y obligaría a montar un router para
// afirmar aritmética sobre cadenas.
//
// Lo que se fija aquí son las tres cosas que, si se rompen, no fallan: que las claves de
// la tabla sean **las del contrato del servidor**, que un domicilio incompleto **se
// mande tal cual** en lugar de desaparecer, y que el vacío cuente como **ausencia** al
// comparar.

import 'package:flutter_test/flutter_test.dart';
import 'package:riseg_one/core/direcciones/campos_de_domicilio.dart';
import 'package:riseg_one/core/direcciones/direccion.dart';

void main() {
  const completa = Direccion(
    calle: 'Av. Reforma',
    numeroExterior: '222',
    colonia: 'Juárez',
    municipio: 'Cuauhtémoc',
    estado: 'Ciudad de México',
    codigoPostal: '06600',
    numeroInterior: '3B',
    ciudad: 'Ciudad de México',
    pais: 'México',
    referencias: 'Frente al parque',
  );

  group('la tabla dice lo mismo que el contrato del servidor', () {
    test('las diez claves son las diez del JSON de un domicilio', () {
      // ⚠️ ESTO ES LO QUE ATA LAS DOS LISTAS. Si alguien añade un campo a `Direccion` y
      // se olvida de la tabla, el formulario no lo pide y nadie se enteraría: el
      // servidor lo recibiría nulo y lo guardaría así.
      final delJson = completa.aJson().keys.toSet();
      final deLaTabla = camposDeDomicilio.map((c) => c.claveCorta).toSet();

      expect(deLaTabla, delJson);
    });

    test('todas las claves llevan el prefijo del servidor', () {
      // El prefijo es el que trae un error por campo —`address.street`— y el que nombra
      // el nodo de foco. Sin él, el error se pintaría en ningún sitio.
      for (final campo in camposDeDomicilio) {
        expect(campo.clave, startsWith('address.'));
      }
    });

    test('ninguna etiqueta se repite, y ninguna está vacía', () {
      final etiquetas = camposDeDomicilio.map((c) => c.etiqueta).toList();

      expect(etiquetas.toSet().length, etiquetas.length);
      expect(etiquetas.any((e) => e.trim().isEmpty), isFalse);
    });

    test('sólo el código postal abre el teclado de números', () {
      final conDigitos = [
        for (final c in camposDeDomicilio)
          if (c.soloDigitos) c.clave,
      ];

      expect(conDigitos, ['address.postalCode']);
    });
  });

  group('qué hay escrito', () {
    test('recién creado no hay nada, y la dirección es nula', () {
      final campos = CamposDeDomicilio();
      addTearDown(campos.dispose);

      expect(campos.hayAlgo, isFalse);
      expect(campos.direccion, isNull);
    });

    test('un solo campo escrito ya es «hay algo»', () {
      final campos = CamposDeDomicilio();
      addTearDown(campos.dispose);

      campos['address.landmarks'].text = 'Frente al parque';

      expect(campos.hayAlgo, isTrue);
    });

    test('los espacios no cuentan como algo escrito', () {
      final campos = CamposDeDomicilio();
      addTearDown(campos.dispose);

      campos['address.street'].text = '   ';

      expect(campos.hayAlgo, isFalse);
      expect(campos.direccion, isNull);
    });

    test('un domicilio INCOMPLETO se manda tal cual, no desaparece', () {
      // ⚠️ LA DECISIÓN QUE IMPORTA. Devolver nulo por estar incompleto dejaría a la
      // persona con un formulario que no manda nada y no dice por qué; mandándolo, el
      // servidor contesta «Falta la colonia.» y el error va a su campo.
      final campos = CamposDeDomicilio();
      addTearDown(campos.dispose);

      campos['address.street'].text = 'Av. Reforma';

      final d = campos.direccion;

      expect(d, isNotNull);
      expect(d!.calle, 'Av. Reforma');
      expect(d.colonia, isEmpty, reason: 'vacío, no nulo: es obligatorio');
      expect(d.ciudad, isNull, reason: 'opcional vacío sí va nulo');
    });

    test('volcar y leer devuelve el mismo domicilio', () {
      final campos = CamposDeDomicilio();
      addTearDown(campos.dispose);

      campos.volcar(completa);

      expect(campos.direccion!.aJson(), completa.aJson());
    });

    test('volcar nulo vacía los diez', () {
      final campos = CamposDeDomicilio();
      addTearDown(campos.dispose);

      campos.volcar(completa);
      campos.volcar(null);

      expect(campos.hayAlgo, isFalse);
    });

    test('volcar por clave vacía lo que no venga en el mapa', () {
      // Es el resultado de resolver un choque: viene COMPLETO, así que una clave
      // ausente significa «este campo queda vacío» y no «no lo toques».
      final campos = CamposDeDomicilio();
      addTearDown(campos.dispose);

      campos.volcar(completa);
      campos.volcarPorClave({'address.street': 'Otra calle'});

      expect(campos['address.street'].text, 'Otra calle');
      expect(campos['address.neighborhood'].text, isEmpty);
    });
  });

  group('D-56 · comparar contra lo cargado', () {
    test('lo volcado es igual a lo cargado', () {
      final campos = CamposDeDomicilio();
      addTearDown(campos.dispose);

      campos.volcar(completa);

      expect(campos.igualA(completa), isTrue);
    });

    test('vacío es igual a «sin domicilio», y no distinto', () {
      final campos = CamposDeDomicilio();
      addTearDown(campos.dispose);

      expect(campos.igualA(null), isTrue);
    });

    test('escribir una letra y borrarla NO es un cambio', () {
      // ⚠️ LA TRAMPA DE D-56: una pregunta que sale por nada enseña a contestar el
      // diálogo sin leerlo. Con los espacios tampoco.
      final campos = CamposDeDomicilio();
      addTearDown(campos.dispose);

      campos.volcar(completa);

      campos['address.landmarks'].text = '${completa.referencias}X';
      expect(campos.igualA(completa), isFalse);

      campos['address.landmarks'].text = completa.referencias!;
      expect(campos.igualA(completa), isTrue);

      campos['address.landmarks'].text = ' ${completa.referencias} ';
      expect(campos.igualA(completa), isTrue, reason: 'los espacios no cuentan');
    });

    test('cambiar un OPCIONAL también es un cambio', () {
      // El interior y las referencias son opcionales para el servidor, y eso no los
      // hace prescindibles para la persona que acaba de escribirlos.
      final campos = CamposDeDomicilio();
      addTearDown(campos.dispose);

      campos.volcar(completa);
      campos['address.interiorNumber'].text = '';

      expect(campos.igualA(completa), isFalse);
    });

    test('escribir sobre «sin domicilio» es un cambio', () {
      final campos = CamposDeDomicilio();
      addTearDown(campos.dispose);

      campos['address.street'].text = 'Av. Reforma';

      expect(campos.igualA(null), isFalse);
    });
  });
}
