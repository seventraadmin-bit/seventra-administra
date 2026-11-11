// LA NUMERACIÓN DE DEUDAS ES ÚNICA ENTRE LOS DOS REPOSITORIOS.
//
// ===========================================================================
// POR QUÉ EXISTE, Y ES UN FALLO DEL 11 DE NOVIEMBRE DE 2026
// ===========================================================================
//
// Se abrió una deuda nueva en el registro del BACKEND como **D-72**, buscando el número
// libre **en un solo registro** — y D-72 ya existía **aquí**, en la web, desde el 6-nov:
// «el escritorio se niega a arrancar sin `SEVENTRA_API_BASE_URL`». Lo cazó el dueño
// leyendo, que es exactamente lo que un candado evita.
//
// ⚠️ **Dos filas con el mismo número no dan error: dan una conversación imposible.**
// «Arregla la D-72» deja de tener una respuesta, y el registro —que existe para que
// cualquiera sepa en qué etapa se resuelve algo sin preguntar— empieza a necesitar que se
// pregunte.
//
// ===========================================================================
// POR QUÉ ESTÁ EN LOS DOS LADOS
// ===========================================================================
//
// Su gemela vive en `seventra-backend/tests/Seventra.Tests/NumeracionDeDeudasTests.cs`, y
// no es duplicación por descuido: **con el guardia en un solo lado, una deuda abierta
// desde el repositorio contrario se cuela igual**. Es literalmente lo que pasó — quien
// abrió la D-72 del backend no corrió la suite de la web.
//
// ===========================================================================
// SE CUENTAN FILAS, NO MENCIONES
// ===========================================================================
//
// Un registro cita números del otro a propósito —«va con D-70 y D-15»— y eso es correcto:
// lo que no puede haber es la misma deuda **definida** dos veces. Por eso el patrón se
// ancla al principio de línea.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Una fila que DEFINE una deuda: `| D-58 | …`.
final _fila = RegExp(r'^\|\s*D-(\d+)\s*\|');

/// La raíz de este repositorio, subiendo hasta encontrar `pubspec.yaml`.
Directory _raiz() {
  var directorio = Directory.current;

  while (!File('${directorio.path}/pubspec.yaml').existsSync()) {
    final padre = directorio.parent;

    if (padre.path == directorio.path) {
      fail('No se encontró la raíz del repositorio (pubspec.yaml).');
    }

    directorio = padre;
  }

  return directorio;
}

Set<int> _numerosDe(File archivo) {
  final numeros = <int>{};

  for (final linea in archivo.readAsLinesSync()) {
    final m = _fila.firstMatch(linea);
    if (m != null) numeros.add(int.parse(m.group(1)!));
  }

  return numeros;
}

void main() {
  test('ningún número de deuda está definido en los DOS registros', () {
    final raiz = _raiz();
    final propio = File('${raiz.path}/docs/deudas-conocidas.md');

    expect(
      propio.existsSync(),
      isTrue,
      reason: 'No se encontró el registro propio en ${propio.path}.',
    );

    final ajeno = File(
      '${raiz.parent.path}/seventra-backend/docs/deudas-conocidas.md',
    );

    if (!ajeno.existsSync()) {
      // ⚠️ **SE SALTA Y LO DICE, en vez de pasar en silencio.** Un guardia que no puede
      // ver la mitad de lo que vigila y contesta «verde» es peor que su ausencia: enseña
      // a confiar en una comprobación que no ocurrió.
      markTestSkipped(
        'No se encontró el registro del BACKEND junto a este repositorio, así que la '
        'unicidad entre los dos NO se pudo comprobar. Se esperaba en '
        '«${ajeno.path}». Su gemela en el backend lo comprueba desde el otro lado.',
      );

      return;
    }

    final deAqui = _numerosDe(propio);
    final deAlla = _numerosDe(ajeno);

    // Y QUE HAYA ALGO QUE COMPARAR: con cero números leídos de cualquiera de los dos, la
    // intersección sería vacía y esto pasaría sin mirar nada. Es la forma en que un
    // guardia de texto se muere al cambiar el formato de una tabla.
    expect(
      deAqui.length,
      greaterThanOrEqualTo(10),
      reason:
          'Sólo se leyeron ${deAqui.length} deudas del registro de la web. ¿Cambió el '
          'formato de la tabla? El guardia estaría pasando sin comparar nada.',
    );

    expect(
      deAlla.length,
      greaterThanOrEqualTo(20),
      reason:
          'Sólo se leyeron ${deAlla.length} deudas del registro del backend '
          '(${ajeno.path}). ¿Cambió el formato de la tabla?',
    );

    final repetidos = (deAqui.intersection(deAlla).toList()..sort())
        .map((n) => 'D-$n')
        .toList();

    expect(
      repetidos,
      isEmpty,
      reason:
          'Estos números están DEFINIDOS como fila en los DOS registros, y la '
          'numeración es única entre los dos repositorios: ${repetidos.join(', ')}.\n'
          'Renumera la más nueva al primer libre MIRANDO LOS DOS ARCHIVOS:\n'
          '  ${propio.path}\n  ${ajeno.path}\n'
          '(Citar un número del otro registro SÍ se puede —«va con D-70»—: aquí sólo '
          'se cuentan las filas que lo DEFINEN.)',
    );
  });
}
