import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:riseg_one/features/organizacion/web/modelos/tipo_de_sucursal.dart';

/// Los tipos de sucursal, y **la resta que evita un mensaje falso**.
///
/// ## Por qué existe este archivo
///
/// `POST …/branch-types/recommended` **devuelve el conjunto resultante, no lo que
/// acaba de crear**. Yo supuse lo contrario al escribir la pantalla, y al segundo
/// clic del botón decía «Se agregaron 3 tipos recomendados» sin haber creado ninguno:
/// la base quedaba bien —el endpoint es idempotente— pero la pantalla mentía.
///
/// Lo midió `BranchTypeTests` del backend, no una revisión:
///
/// ```csharp
/// var segunda = await AddRecommendedBranchTypesAsync(contexto, Ct);
/// Assert.Equal(3, segunda.Value!.Count);   // tres, no cero
/// ```
///
/// Así que la cuenta sale de restar contra lo que ya se tenía, y eso es lo que estas
/// pruebas fijan.
void main() {
  TipoDeSucursal tipo(String codigo, String nombre, {bool activo = true}) =>
      TipoDeSucursal.deJson({
        'id': 'id-$codigo',
        'code': codigo,
        'name': nombre,
        'status': activo ? 'activa' : 'inactiva',
      });

  group('TipoDeSucursal.deJson', () {
    test('lee la respuesta real de la API', () {
      const json = '''
        {
          "id": "01a15071-cccc-7000-8000-000000000001",
          "code": "OFICINA_ADMIN",
          "name": "Oficina administrativa",
          "status": "activa",
          "updatedAt": "2026-10-18T19:45:00+00:00"
        }
      ''';

      final t = TipoDeSucursal.deJson(jsonDecode(json) as Map<String, dynamic>);

      expect(t.id, '01a15071-cccc-7000-8000-000000000001');
      expect(t.codigo, 'OFICINA_ADMIN');
      expect(t.nombre, 'Oficina administrativa');
      expect(t.activo, isTrue);
    });

    test('«activo» se DERIVA del estado, no es un campo aparte', () {
      expect(tipo('X', 'X', activo: false).activo, isFalse);
      expect(tipo('X', 'X').activo, isTrue);
    });
  });

  group('tiposNuevos: la resta que evita el mensaje falso', () {
    // Los tres que el servidor recomienda, medidos en BranchTypeTests. BODEGA no va.
    final recomendados = [
      tipo('BASE_OPERATIVA', 'Base operativa'),
      tipo('OFICINA_ADMIN', 'Oficina administrativa'),
      tipo('ZONA_SUPERVISION', 'Zona de supervisión'),
    ];

    test('la PRIMERA vez, sobre un catálogo vacío, son los tres', () {
      expect(
        tiposNuevos(antes: const [], despues: recomendados).map((t) => t.codigo),
        ['BASE_OPERATIVA', 'OFICINA_ADMIN', 'ZONA_SUPERVISION'],
      );
    });

    test('LA SEGUNDA VEZ son CERO, aunque la respuesta traiga los tres', () {
      // ÉSTA ES LA PRUEBA QUE IMPORTA. El servidor devuelve el conjunto resultante,
      // así que `despues.length` seguiría siendo 3 y la pantalla diría «Se agregaron
      // 3» sin haber creado nada.
      expect(
        tiposNuevos(antes: recomendados, despues: recomendados),
        isEmpty,
        reason:
            'Si esto deja de ser vacío, el botón volverá a decir «Se agregaron 3» al '
            'segundo clic.',
      );
    });

    test('con un tipo PROPIO del mismo código, sólo cuenta los otros dos', () {
      // El caso que distingue «idempotente» de «no falla»: el servidor no pisa el
      // nombre del tipo que la empresa ya había creado, y lo devuelve con el suyo.
      final propio = [tipo('BASE_OPERATIVA', 'La mía')];

      final respuestaDelServidor = [
        tipo('BASE_OPERATIVA', 'La mía'),
        tipo('OFICINA_ADMIN', 'Oficina administrativa'),
        tipo('ZONA_SUPERVISION', 'Zona de supervisión'),
      ];

      expect(
        tiposNuevos(antes: propio, despues: respuestaDelServidor).map((t) => t.codigo),
        ['OFICINA_ADMIN', 'ZONA_SUPERVISION'],
      );
    });

    test('compara por CÓDIGO, no por nombre', () {
      // Si alguien renombró «Oficina administrativa» a «Oficinas», sigue siendo el
      // mismo tipo y no se cuenta como nuevo.
      final antes = [tipo('OFICINA_ADMIN', 'Oficinas')];
      final despues = [tipo('OFICINA_ADMIN', 'Oficina administrativa')];

      expect(tiposNuevos(antes: antes, despues: despues), isEmpty);
    });

    test('compara por CÓDIGO, no por id', () {
      // El código es la identidad que el servidor usa para saltarse los que ya
      // existen. Comparar por id contaría como nuevo algo que ya estaba.
      final antes = [
        TipoDeSucursal.deJson({
          'id': 'uno',
          'code': 'OFICINA_ADMIN',
          'name': 'Oficina',
          'status': 'activa',
        }),
      ];
      final despues = [
        TipoDeSucursal.deJson({
          'id': 'OTRO-ID',
          'code': 'OFICINA_ADMIN',
          'name': 'Oficina',
          'status': 'activa',
        }),
      ];

      expect(tiposNuevos(antes: antes, despues: despues), isEmpty);
    });

    test('un tipo que YA ESTABA pero inactivo tampoco es nuevo', () {
      // El servidor se lo salta por código, esté activo o no, así que contarlo como
      // nuevo diría que se creó algo que ya existía.
      final antes = [tipo('OFICINA_ADMIN', 'Oficina', activo: false)];

      expect(tiposNuevos(antes: antes, despues: recomendados).map((t) => t.codigo), [
        'BASE_OPERATIVA',
        'ZONA_SUPERVISION',
      ]);
    });

    test('devuelve los OBJETOS del servidor, no los de antes', () {
      // Lo que se muestra tiene que ser lo que el servidor dice que hay ahora.
      final despues = [tipo('NUEVO', 'Nombre del servidor')];

      expect(
        tiposNuevos(antes: const [], despues: despues).single.nombre,
        'Nombre del servidor',
      );
    });

    test('y conserva el ORDEN en que el servidor los mandó', () {
      expect(
        tiposNuevos(antes: const [], despues: recomendados).map((t) => t.codigo).toList(),
        recomendados.map((t) => t.codigo).toList(),
      );
    });
  });
}
