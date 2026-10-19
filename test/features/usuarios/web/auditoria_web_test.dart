import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:riseg_one/features/usuarios/web/modelos/evento_de_auditoria.dart';

/// La auditoría de la empresa, contra la respuesta **real** de
/// `GET /companies/{id}/audit`.
///
/// El JSON está copiado del contrato `AuditPageResponse` / `AuditEventResponse` del
/// backend. Lo que estas pruebas protegen es el **nombre de los campos** y las tres
/// reglas que se rompen fácil: un nulo no es un error, un cursor nulo no es un fallo,
/// y la fecha no se convierte al leerla.
void main() {
  // Una página con dos hechos: conceder un acceso y crear un área.
  const pagina = '''
    {
      "items": [
        {
          "id": "01a15071-aaaa-7000-8000-000000000001",
          "organizationId": "01a15071-0000-7000-8000-000000000001",
          "companyId": "01a15071-2e91-798d-aa4e-44c09ff69d1e",
          "actorType": "identity",
          "actorIdentityId": "01a15071-0001-7000-8000-000000000001",
          "entityType": "company_access",
          "entityId": "01a15071-bbbb-7000-8000-000000000001",
          "action": "granted",
          "before": null,
          "after": "{\\"role\\":\\"user\\"}",
          "reason": null,
          "requestId": "abc123",
          "occurredAt": "2026-10-18T19:45:00+00:00"
        },
        {
          "id": "01a15071-aaaa-7000-8000-000000000002",
          "organizationId": "01a15071-0000-7000-8000-000000000001",
          "companyId": "01a15071-2e91-798d-aa4e-44c09ff69d1e",
          "actorType": "system",
          "actorIdentityId": null,
          "entityType": "area",
          "entityId": "01a15071-cccc-7000-8000-000000000001",
          "action": "created",
          "before": null,
          "after": "{\\"code\\":\\"MON\\"}",
          "reason": "alta inicial",
          "requestId": null,
          "occurredAt": "2026-10-18T20:00:00+00:00"
        }
      ],
      "nextCursor": "b3BhY28="
    }
  ''';

  group('PaginaDeAuditoria.deJson', () {
    test('lee los dos hechos y el cursor', () {
      final p = PaginaDeAuditoria.deJson(
        jsonDecode(pagina) as Map<String, dynamic>,
      );

      expect(p.eventos, hasLength(2));
      expect(p.siguienteCursor, 'b3BhY28=');
      expect(p.hayMas, isTrue);
    });

    test('un cursor NULO significa que no hay más, no que haya fallado', () {
      // Son dos cosas distintas y se distinguen aquí: un fallo llega como `Result`
      // fallido desde el repositorio y nunca como una página vacía.
      final ultima = jsonDecode(pagina) as Map<String, dynamic>
        ..['nextCursor'] = null;

      final p = PaginaDeAuditoria.deJson(ultima);

      expect(p.hayMas, isFalse);
      expect(p.eventos, hasLength(2));
    });

    test('una página VACÍA se lee sin romperse', () {
      // La primera empresa de un cliente no ha hecho nada todavía.
      final vacia = {'items': <Object?>[], 'nextCursor': null};

      final p = PaginaDeAuditoria.deJson(vacia);

      expect(p.eventos, isEmpty);
      expect(p.hayMas, isFalse);
    });
  });

  group('EventoDeAuditoria.deJson', () {
    PaginaDeAuditoria leer() =>
        PaginaDeAuditoria.deJson(jsonDecode(pagina) as Map<String, dynamic>);

    test('el hecho con actor humano trae su identidad', () {
      final e = leer().eventos[0];

      expect(e.tipoDeActor, 'identity');
      expect(e.identidadDelActor, '01a15071-0001-7000-8000-000000000001');
      expect(e.loHizoUnaPersona, isTrue);
      expect(e.accion, 'granted');
      expect(e.tipoDeEntidad, 'company_access');
    });

    test('un actor NULO no es un error: es un hecho sin persona detrás', () {
      // Si esto se leyera como «desconocido por error», la pantalla diría que falta un
      // dato que en realidad no existe para ese hecho.
      final e = leer().eventos[1];

      expect(e.tipoDeActor, 'system');
      expect(e.identidadDelActor, isNull);
      expect(e.loHizoUnaPersona, isFalse);
    });

    test('«antes» nulo en un alta, y el motivo sólo cuando lo hubo', () {
      final conceder = leer().eventos[0];
      final crear = leer().eventos[1];

      expect(conceder.antes, isNull);
      expect(conceder.motivo, isNull);

      expect(crear.motivo, 'alta inicial');
    });

    test('«después» llega como TEXTO JSON y no se interpreta', () {
      // Se conserva tal cual: su forma depende de la entidad, y entenderla aquí
      // exigiría conocer sesenta formas distintas.
      expect(leer().eventos[0].despues, '{"role":"user"}');
    });

    test('la fecha se guarda tal como vino, sin convertir a local', () {
      // `toLocal()` al leer perdería que el dato vino en UTC, y la conversión es de
      // quien pinta. Se comprueba por el instante, que no depende de la zona de la
      // máquina que corre la prueba.
      final e = leer().eventos[0];

      expect(
        e.cuando.toUtc(),
        DateTime.utc(2026, 10, 18, 19, 45),
      );
    });

    test('los dos hechos llegan en el ORDEN del servidor', () {
      // La auditoría la ordena el servidor —lo más reciente según su cursor— y
      // reordenar en el cliente duplicaría esa decisión.
      final eventos = leer().eventos;

      expect(eventos[0].accion, 'granted');
      expect(eventos[1].accion, 'created');
    });
  });
}
