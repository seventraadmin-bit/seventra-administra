import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:riseg_one/features/organizacion/web/modelos/puesto.dart';

/// El puesto y **el consecutivo que se sugiere al crearlo**.
///
/// El formato sale del escritorio, que lo genera solo: en `seed_data.dart` el renglón
/// del puesto es `('puesto', 'PUE', 4)` — prefijo **PUE** y **cuatro** dígitos.
void main() {
  group('Puesto.deJson', () {
    const json = '''
      {
        "id": "01a15071-dddd-7000-8000-000000000001",
        "areaId": "01a15071-cccc-7000-8000-000000000001",
        "code": "PUE-0003",
        "name": "Supervisor general",
        "kind": "operativo",
        "status": "activa",
        "updatedAt": "2026-10-18T19:45:00+00:00",
        "description": "Cubre el turno nocturno",
        "hierarchyLevel": 3
      }
    ''';

    test('lee la respuesta real de la API', () {
      final p = Puesto.deJson(jsonDecode(json) as Map<String, dynamic>);

      expect(p.id, '01a15071-dddd-7000-8000-000000000001');
      expect(p.areaId, '01a15071-cccc-7000-8000-000000000001');
      expect(p.codigo, 'PUE-0003');
      expect(p.nombre, 'Supervisor general');
      expect(p.tipo, 'operativo');
      expect(p.esOperativo, isTrue);
      expect(p.nivel, 3);
      expect(p.descripcion, 'Cubre el turno nocturno');
      expect(p.activo, isTrue);
    });

    test('«activo» se DERIVA del estado, no es un campo aparte', () {
      final inactivo = jsonDecode(json) as Map<String, dynamic>
        ..['status'] = 'inactiva';

      expect(Puesto.deJson(inactivo).activo, isFalse);
    });

    test('un NIVEL NULO se conserva nulo, y no se convierte en cero', () {
      // AUSENCIA NUNCA ES CERO. La columna es opcional en la base —hay puestos de
      // antes de que el campo existiera— y la ruta sólo lo exige al crear. Un cero
      // diría «el nivel más bajo de todos», que es una afirmación que nadie hizo.
      final sinNivel = jsonDecode(json) as Map<String, dynamic>
        ..['hierarchyLevel'] = null;

      expect(Puesto.deJson(sinNivel).nivel, isNull);
    });

    test('una descripción nula se conserva nula', () {
      final sinDescripcion = jsonDecode(json) as Map<String, dynamic>
        ..['description'] = null;

      expect(Puesto.deJson(sinDescripcion).descripcion, isNull);
    });

    test('«es operativo» se deriva del tipo, y administrativo NO lo es', () {
      final admin = jsonDecode(json) as Map<String, dynamic>
        ..['kind'] = 'administrativo';

      expect(Puesto.deJson(admin).esOperativo, isFalse);
    });

    test('un tipo DESCONOCIDO no se toma por operativo', () {
      // Se pregunta `== operativo`, no `!= administrativo`: si el servidor añadiera
      // un tipo nuevo, lo peligroso sería pintarlo como personal de campo.
      final raro = jsonDecode(json) as Map<String, dynamic>..['kind'] = 'mixto';

      expect(Puesto.deJson(raro).esOperativo, isFalse);
    });
  });

  group('siguienteCodigoDePuesto', () {
    test('sin puestos empieza en PUE-0001', () {
      expect(siguienteCodigoDePuesto(const []), 'PUE-0001');
    });

    test('es el MÁXIMO más uno, no el primer hueco', () {
      // Con PUE-0001 y PUE-0003 sugiere PUE-0004. Rellenar el hueco reutilizaría un
      // número que alguien pudo imprimir, decir por teléfono o meter en una hoja de
      // cálculo, y dos puestos distintos acabarían llamándose igual en dos sitios.
      expect(
        siguienteCodigoDePuesto(const ['PUE-0001', 'PUE-0003']),
        'PUE-0004',
      );
    });

    test('el orden en que vienen no importa', () {
      expect(
        siguienteCodigoDePuesto(const ['PUE-0007', 'PUE-0002', 'PUE-0005']),
        'PUE-0008',
      );
    });

    test('los códigos que NO siguen el patrón se ignoran', () {
      // El campo es editable: alguien pudo escribir SUP a mano, y eso no debe frenar
      // la sugerencia ni contarse como consecutivo.
      expect(
        siguienteCodigoDePuesto(const ['SUP', 'JTU', 'PUE-0002', 'AUX-9']),
        'PUE-0003',
      );
    });

    test('con SÓLO códigos a mano vuelve a PUE-0001', () {
      expect(siguienteCodigoDePuesto(const ['SUP', 'JTU']), 'PUE-0001');
    });

    test('compara NUMÉRICAMENTE, no como texto', () {
      // Por texto, 'PUE-10000' quedaría antes de 'PUE-9999' y la sugerencia
      // RETROCEDERÍA a PUE-10000 cuando ya existe PUE-9999.
      expect(
        siguienteCodigoDePuesto(const ['PUE-9999', 'PUE-10000']),
        'PUE-10001',
      );
    });

    test('pasado el 9999 crece a cinco dígitos, no vuelve a empezar', () {
      // Un código largo es incómodo; uno repetido es un error. El relleno a cuatro
      // es un mínimo, no un tope.
      expect(siguienteCodigoDePuesto(const ['PUE-9999']), 'PUE-10000');
    });

    test('tolera minúsculas y espacios en lo que ya existe', () {
      // Los códigos se normalizan a mayúsculas al guardar, pero la lista puede traer
      // lo que sea de una importación.
      expect(
        siguienteCodigoDePuesto(const [' pue-0004 ', 'PUE-0002']),
        'PUE-0005',
      );
    });

    test('un código con el prefijo y basura detrás no cuenta', () {
      // 'PUE-ABC' no es un consecutivo. Debe ignorarse en vez de reventar.
      expect(
        siguienteCodigoDePuesto(const ['PUE-ABC', 'PUE-0002']),
        'PUE-0003',
      );
    });

    test('el sugerido pasa la validación del servidor', () {
      // El servidor acepta de 1 a 32 caracteres de A–Z, dígitos, guion y guion bajo.
      // Si el formato dejara de cumplirlo, el alta fallaría con un 400 que parecería
      // culpa del usuario.
      final sugerido = siguienteCodigoDePuesto(const ['PUE-0001']);

      expect(sugerido.length, lessThanOrEqualTo(32));
      expect(RegExp(r'^[A-Z0-9_-]+$').hasMatch(sugerido), isTrue);
    });
  });
}
