// Que ningún pendiente quede suelto: un marcador sin número de deuda o de compromiso.
//
// ===========================================================================
// POR QUÉ ESTA PRUEBA EXISTE
// ===========================================================================
//
// El 25 de octubre de 2026 se barrieron los dos repositorios buscando pendientes sueltos
// y salieron **48 deudas** repartidas entre documentos y comentarios, ninguna con etapa
// asignada. Se metieron todas en `docs/deudas-conocidas.md` —y las de la nube en
// `seventra-backend/docs/deudas-conocidas.md`— con su número y su etapa, y se marcó cada
// línea con el suyo. Este guardia es lo que impide que vuelva a pasar.
//
// ===========================================================================
// LA REGLA
// ===========================================================================
//
// Un marcador de pendiente —el reloj, `FIXME`, un `TODO` de verdad— tiene que llevar en
// **la misma línea** un `D-xx` o un `CP-xx`. Con eso, cualquiera que lo lee sabe en qué
// etapa se resuelve sin preguntar, y el archivo de deudas no puede quedarse corto sin que
// una prueba lo diga.
//
// LA NUMERACIÓN ES ÚNICA ENTRE LOS DOS REPOSITORIOS: el backend lleva D-01 a D-27 y la web
// desde D-28, así que un número nunca significa dos cosas.
//
// ===========================================================================
// LA PALABRA NO ES EL MARCADOR
// ===========================================================================
//
// Y esta distinción es la mitad del guardia. En español «TODO» es una palabra —«revierte
// TODO (Pago/Ingreso)» es el nombre de una prueba de verdad— y «pendiente» es vocabulario
// del negocio: una cuota pendiente, un bien pendiente de recuperación, un complemento
// pendiente. Contarlas como marcadores daría 104 archivos en este repositorio, casi todos
// prosa, y un guardia que grita por todo es un guardia que se apaga.
//
// Así que sólo cuentan las formas inequívocas, y hay dos casos de control que fallan si
// alguien ensancha la regla.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Las formas que sí son un marcador.
///
/// Las tres condiciones son CICATRICES de las dos primeras corridas de este guardia:
///
///  · `TODO[:(]` sin espacio en medio, porque «conserva TODO (datos…)» es prosa;
///  · ancladas al PRINCIPIO de la línea o del comentario, porque «bloquea TODO: cero
///    Asignaciones» y «revertiría TODO: la anterior» son frases en español que acaban en
///    dos puntos — un marcador ABRE el comentario, no cae a mitad de una oración;
///  · y `TODO` exige los dos puntos mientras `PENDIENTE` y `DEUDA` no, porque
///    «TODO pasa por CompanyScope» abre un comentario y es español, y «PENDIENTE antes de
///    producción» es un título que sí es un pendiente.
final _marcador = RegExp(
  r'⏳|FIXME|\bHACK\b|\bXXX\b'
  r'|^[\s>\-*#/]*\**\s*TODO[:(]'
  r'|^[\s>\-*#/]*\**\s*(?:PENDIENTE|DEUDA)\b',
  unicode: true,
);

/// El número que lo salva: una deuda o un compromiso.
final _numero = RegExp(r'\b(D|CP)-\d{2,}\b');

/// Lo que no se mira, con su razón.
const _exentos = <String>[
  // Esta prueba: lleva los marcadores en sus propias constantes.
  'test/core/pendientes_con_numero_test.dart',

  // EL REGISTRO. Es la lista en sí: exigirle un número a sus propias filas sería pedirle
  // a la tabla que se cite a sí misma renglón por renglón.
  'docs/deudas-conocidas.md',
];

void main() {
  String normalizar(String ruta) => ruta.replaceAll('\\', '/');

  List<File> vigilados() => [
    for (final raiz in ['lib', 'test', 'docs'])
      ...Directory(raiz)
          .listSync(recursive: true)
          .whereType<File>()
          .where(
            (f) =>
                (f.path.endsWith('.dart') || f.path.endsWith('.md')) &&
                !f.path.endsWith('.g.dart'),
          ),
  ];

  test('ningún marcador de pendiente queda sin número', () {
    final sueltos = <String>[];

    for (final archivo in vigilados()) {
      final ruta = normalizar(archivo.path);
      if (_exentos.contains(ruta)) continue;

      final lineas = archivo.readAsStringSync().split('\n');

      for (var i = 0; i < lineas.length; i++) {
        if (!_marcador.hasMatch(lineas[i])) continue;
        if (_numero.hasMatch(lineas[i])) continue;

        sueltos.add('$ruta:${i + 1}: ${lineas[i].trim()}');
      }
    }

    expect(
      sueltos,
      isEmpty,
      reason:
          'Hay pendientes sin número de deuda ni de compromiso. Cada uno entra en '
          'docs/deudas-conocidas.md con su etapa —o en '
          'seventra-backend/docs/compromisos.md si lo entrega otra etapa— y la línea '
          'se marca con su número:\n  ${sueltos.join('\n  ')}',
    );
  });

  test('la palabra española TODO no es un marcador', () {
    // Si alguien ensancha `_marcador` a un `TODO` suelto, esto falla con las frases
    // reales que hay en el repositorio.
    expect(
      _marcador.hasMatch(
        "    test('atomicidad: un fallo real a mitad de la redistribución revierte TODO (Pago/Ingreso)',",
      ),
      isFalse,
    );
    // LAS DOS FRASES QUE TUMBARON LA SEGUNDA CORRIDA. Las dos acaban en «TODO:» y las
    // dos son español: el marcador abre el comentario, no cae a mitad de una oración.
    expect(
      _marcador.hasMatch('    // y la transacción revertiría TODO: la anterior seguiría'),
      isFalse,
    );
    expect(
      _marcador.hasMatch(
        "    test('stock insuficiente en la línea 2 de 3 bloquea TODO: cero Asignaciones', () async {",
      ),
      isFalse,
    );

    // Y la que abre el comentario con la palabra, sin dos puntos.
    expect(
      _marcador.hasMatch('/// TODO pasa por `CompanyScope`, y eso no es comodidad'),
      isFalse,
    );
  });

  test('pendiente como palabra del negocio no es un marcador', () {
    expect(
      _marcador.hasMatch(
        '  /// Fecha de la baja laboral que dejó este bien PENDIENTE DE RECUPERACIÓN.',
      ),
      isFalse,
    );
    expect(
      _marcador.hasMatch(
        "    test('4. un documento PENDIENTE equivalente tampoco se duplica', () async {",
      ),
      isFalse,
    );
  });

  test('el guardia reconoce los marcadores de verdad', () {
    // Sin esto, un patrón roto —una expresión que no casa con nada— dejaría pasar todo y
    // las pruebas de arriba seguirían verdes.
    expect(_marcador.hasMatch('/// ⏳ **No se escucha `restricted` todavía.**'), isTrue);
    expect(_marcador.hasMatch('// TODO: engancharlo cuando exista la pantalla'), isTrue);
    expect(_marcador.hasMatch('  // DEUDA: la corrección de fondo es otra'), isTrue);
    expect(_marcador.hasMatch('### PENDIENTE antes del piloto'), isTrue);

    // Y que el número los salva, que es la otra mitad de la regla.
    expect(_numero.hasMatch('/// ⏳(D-46) **No se escucha `restricted` todavía.**'), isTrue);
    expect(_numero.hasMatch('/// 🚫 **PENDIENTE(D-30) ANTES DEL PILOTO**'), isTrue);
    expect(_numero.hasMatch('/// ⏳ **No se escucha `restricted` todavía.**'), isFalse);
  });
}
