// La comparación de tres versiones cuando dos personas guardaron el mismo
// expediente.
//
// LO QUE ESTO PROTEGE, Y POR QUÉ SE PRUEBA APARTE DE LA PANTALLA. El requisito del
// dueño fue: al recibir el 409, «no quiero perder lo que escribí». Eso se consigue con
// una tabla de cinco casos, y una tabla mal resuelta pierde trabajo en silencio — nadie
// se entera de que su cambio desapareció hasta que lo busca.
//
// Se prueba sin widgets a propósito: es lógica, y una prueba de pantalla la mediría
// a través de dos capas que pueden tapar un caso.

import 'package:flutter_test/flutter_test.dart';
import 'package:riseg_one/features/organizacion/web/modelos/choque_de_expediente.dart';

void main() {
  CampoComparado campo({
    String? base,
    String? mio,
    String? suyo,
    String nombre = 'legalName',
  }) => CampoComparado(
    campo: nombre,
    etiqueta: 'Razón social',
    base: base,
    mio: mio,
    suyo: suyo,
  );

  group('La tabla de los cinco casos', () {
    test('nadie lo tocó', () {
      final c = campo(base: 'A', mio: 'A', suyo: 'A');

      expect(c.estado, EstadoDelCampo.igual);
      expect(c.esChoque, isFalse);
      expect(c.porOmision, 'A');
    });

    test('sólo yo: se queda lo mío SIN preguntar', () {
      final c = campo(base: 'A', mio: 'B', suyo: 'A');

      expect(c.estado, EstadoDelCampo.soloMio);
      expect(c.esChoque, isFalse);
      expect(c.porOmision, 'B');
    });

    test('sólo la otra persona: se toma lo suyo SIN preguntar', () {
      // No se pregunta porque yo no expresé ninguna intención sobre este campo.
      // Preguntarlo obligaría a decidir sobre algo que no decidí.
      final c = campo(base: 'A', mio: 'A', suyo: 'C');

      expect(c.estado, EstadoDelCampo.soloSuyo);
      expect(c.esChoque, isFalse);
      expect(c.porOmision, 'C');
    });

    test('los dos, a LO MISMO: no es choque', () {
      // Es el caso que una comparación de dos versiones convertiría en conflicto: el
      // valor del servidor difiere del que yo cargué, pero coincide con el que quiero.
      final c = campo(base: 'A', mio: 'B', suyo: 'B');

      expect(c.estado, EstadoDelCampo.losDosIgual);
      expect(c.esChoque, isFalse);
      expect(c.porOmision, 'B');
    });

    test('los dos, a cosas DISTINTAS: esto sí es choque', () {
      final c = campo(base: 'A', mio: 'B', suyo: 'C');

      expect(c.estado, EstadoDelCampo.choque);
      expect(c.esChoque, isTrue);
    });

    test('y en un choque, por omisión se queda LO MÍO', () {
      // SI LA PERSONA CIERRA EL AVISO SIN DECIDIR, lo que escribió sigue ahí. Perder su
      // trabajo por no contestar sería exactamente lo que este aviso viene a evitar.
      expect(campo(base: 'A', mio: 'B', suyo: 'C').porOmision, 'B');
    });
  });

  group('Vacío y nulo son la misma ausencia', () {
    test('un nulo y una cadena vacía no chocan', () {
      // EL CASO QUE INVENTARÍA UN CHOQUE EN CADA CAMPO OPCIONAL: el servidor manda
      // nulo lo que nunca se llenó, y el formulario lo tiene en blanco.
      expect(campo(base: null, mio: '', suyo: null).estado, EstadoDelCampo.igual);
      expect(campo(base: '', mio: null, suyo: '').estado, EstadoDelCampo.igual);
    });

    test('ni los espacios de más', () {
      expect(campo(base: 'A', mio: ' A ', suyo: 'A').estado, EstadoDelCampo.igual);
    });

    test('pero llenar algo que estaba vacío SÍ cuenta', () {
      final c = campo(base: null, mio: 'B', suyo: null);

      expect(c.estado, EstadoDelCampo.soloMio);
      expect(c.porOmision, 'B');
    });

    test('y borrar algo que estaba lleno también', () {
      final c = campo(base: 'A', mio: '', suyo: 'A');

      expect(c.estado, EstadoDelCampo.soloMio);
      expect(c.porOmision, '');
    });
  });

  group('El expediente completo', () {
    test('sin choques se resuelve SOLO, sin preguntar nada', () {
      // EL CASO FRECUENTE DE VERDAD: dos personas editando secciones distintas del
      // mismo expediente. Sin esto, el aviso saldría igual y las dos tendrían que
      // confirmar algo que no chocaba.
      final choque = ChoqueDeExpediente([
        campo(nombre: 'legalName', base: 'A', mio: 'B', suyo: 'A'),
        campo(nombre: 'slogan', base: 'X', mio: 'X', suyo: 'Y'),
        campo(nombre: 'taxId', base: 'R', mio: 'R', suyo: 'R'),
      ]);

      expect(choque.seResuelveSolo, isTrue);
      expect(choque.hayChoque, isFalse);
      expect(choque.choques, isEmpty);

      // Y cada campo se queda con lo que corresponde: lo mío donde cambié yo, lo suyo
      // donde cambió la otra persona.
      expect(choque.resolver(const {}), {
        'legalName': 'B',
        'slogan': 'Y',
        'taxId': 'R',
      });
    });

    test('señala SÓLO los campos que de verdad chocan', () {
      final choque = ChoqueDeExpediente([
        campo(nombre: 'legalName', base: 'A', mio: 'B', suyo: 'C'),
        campo(nombre: 'slogan', base: 'X', mio: 'X', suyo: 'Y'),
        campo(nombre: 'taxId', base: 'R', mio: 'S', suyo: 'R'),
      ]);

      expect(choque.choques.map((c) => c.campo), ['legalName']);

      // Y lo que entró de fuera se informa aunque no se pregunte: la persona merece
      // saber qué cambió la otra.
      expect(choque.suyosSinChoque.map((c) => c.campo), ['slogan']);
    });

    test('elegir lo suyo o lo mío, campo por campo', () {
      final choque = ChoqueDeExpediente([
        campo(nombre: 'legalName', base: 'A', mio: 'B', suyo: 'C'),
        campo(nombre: 'taxId', base: 'R', mio: 'S', suyo: 'T'),
      ]);

      expect(choque.choques.length, 2);

      // Uno de cada: el primero suyo, el segundo mío.
      expect(choque.resolver(const {'legalName': true, 'taxId': false}), {
        'legalName': 'C',
        'taxId': 'S',
      });
    });

    test('y «todo lo suyo» o «todo lo mío» son el mismo mecanismo', () {
      // NO HACE FALTA UN CAMINO APARTE para los dos botones de «todo»: son el mapa
      // lleno con el mismo valor. Un segundo camino sería un segundo sitio donde
      // equivocarse.
      final choque = ChoqueDeExpediente([
        campo(nombre: 'legalName', base: 'A', mio: 'B', suyo: 'C'),
        campo(nombre: 'taxId', base: 'R', mio: 'S', suyo: 'T'),
      ]);

      final todoSuyo = {for (final c in choque.choques) c.campo: true};
      final todoMio = {for (final c in choque.choques) c.campo: false};

      expect(choque.resolver(todoSuyo), {'legalName': 'C', 'taxId': 'T'});
      expect(choque.resolver(todoMio), {'legalName': 'B', 'taxId': 'S'});
    });

    test('un campo sin elegir usa su omisión, no se pierde del resultado', () {
      // LA TRAMPA: resolver sólo los elegidos dejaría el expediente incompleto y el
      // `PUT` borraría lo que no se mencionó.
      final choque = ChoqueDeExpediente([
        campo(nombre: 'legalName', base: 'A', mio: 'B', suyo: 'C'),
        campo(nombre: 'slogan', base: 'X', mio: 'X', suyo: 'Y'),
      ]);

      final resuelto = choque.resolver(const {'legalName': true});

      expect(resuelto.keys.length, 2);
      expect(resuelto['legalName'], 'C');
      expect(resuelto['slogan'], 'Y');
    });

    test('seQuedaLoSuyo dice lo MISMO que porOmision, campo por campo', () {
      // LAS DOS SON LA MISMA TABLA y tienen que seguir diciendo lo mismo: `resolver`
      // devuelve VALORES, y para el horario —que es una lista— la pantalla necesita la
      // DECISIÓN. Si se separaran, el horario se resolvería al revés que el resto del
      // expediente y nadie lo notaría: el aviso enseñaría lo elegido y se guardaría lo
      // otro.
      final choque = ChoqueDeExpediente([
        campo(nombre: 'igual', base: 'A', mio: 'A', suyo: 'A'),
        campo(nombre: 'soloMio', base: 'A', mio: 'B', suyo: 'A'),
        campo(nombre: 'soloSuyo', base: 'A', mio: 'A', suyo: 'C'),
        campo(nombre: 'losDosIgual', base: 'A', mio: 'B', suyo: 'B'),
        campo(nombre: 'choque', base: 'A', mio: 'B', suyo: 'C'),
      ]);

      for (final c in choque.campos) {
        // SIN ELEGIR NADA: la decisión tiene que coincidir con el valor por omisión.
        final suyo = choque.seQuedaLoSuyo(c.campo, const {});

        expect(
          suyo ? c.suyo : c.mio,
          c.porOmision,
          reason:
              'El campo «${c.campo}» (${c.estado.name}) resuelve a '
              '«${c.porOmision}» pero la decisión dice '
              '${suyo ? 'lo suyo' : 'lo mío'}.',
        );
      }

      // Y CON ELECCIÓN, manda la elección en las dos direcciones.
      expect(choque.seQuedaLoSuyo('choque', const {'choque': true}), isTrue);
      expect(choque.seQuedaLoSuyo('choque', const {'choque': false}), isFalse);

      // UN CAMPO QUE NO ESTÁ EN LA COMPARACIÓN SE QUEDA CON LO MÍO: es lo que no
      // pierde el trabajo de nadie.
      expect(choque.seQuedaLoSuyo('inexistente', const {}), isFalse);
    });

    test('comoSeLee cambia lo que se MUESTRA, nunca lo que se compara', () {
      // EL TIPO DE SUCURSAL SE COMPARA POR ID Y SE LEE POR SU NOMBRE. Si `comoSeLee`
      // tocara la comparación, dos tipos con el mismo nombre parecerían el mismo tipo
      // —y el choque desaparecería sin que nadie eligiera nada—.
      final c = CampoComparado(
        campo: 'branchTypeId',
        etiqueta: 'Tipo de sucursal',
        base: 'id-1',
        mio: 'id-2',
        suyo: 'id-3',
        comoSeLee: (id) => switch (id) {
          'id-1' => 'Oficina',
          'id-2' => 'Bodega',
          'id-3' => 'Bodega',
          _ => 'Sin tipo',
        },
      );

      // DOS NOMBRES IGUALES Y SIGUE SIENDO CHOQUE: 'id-2' != 'id-3'.
      expect(c.estado, EstadoDelCampo.choque);

      expect(c.leer(c.mio), 'Bodega');
      expect(c.leer(c.suyo), 'Bodega');

      // EL NULO LLEGA SIN CONVERTIR a la función: «sin tipo» no es «(vacío)», y quien
      // sabe traducirlo es quien puso la función.
      expect(c.leer(null), 'Sin tipo');

      // Y SIN FUNCIÓN, el valor es lo que se muestra.
      final pelado = campo(nombre: 'name', base: 'A', mio: 'B', suyo: 'C');

      expect(pelado.leer(pelado.mio), 'B');
      expect(pelado.leer(null), isNull);
    });
  });
}
