/// Un hecho de la auditoría de la empresa, tal como lo devuelve
/// `GET /companies/{id}/audit`.
///
/// **ES APPEND-ONLY Y NO SE EDITA**: la auditoría registra lo que pasó, y nada en esta
/// pantalla la modifica. Por eso el modelo no tiene nada que no sea leer.
///
/// **`before` y `after` llegan como TEXTO, no como objetos**, y aquí se dejan así. El
/// servidor los guarda como JSON con la regla de que las claves no llevan fragmentos
/// sensibles, pero su forma depende de la entidad: un `area` y un `company_access`
/// guardan cosas distintas. Interpretarlos en el cliente exigiría conocer sesenta
/// formas, y la primera que cambiara rompería la pantalla en silencio.
class EventoDeAuditoria {
  const EventoDeAuditoria({
    required this.id,
    required this.tipoDeActor,
    required this.identidadDelActor,
    required this.tipoDeEntidad,
    required this.entidadId,
    required this.accion,
    required this.antes,
    required this.despues,
    required this.motivo,
    required this.cuando,
  });

  factory EventoDeAuditoria.deJson(Map<String, dynamic> json) =>
      EventoDeAuditoria(
        id: json['id'] as String,
        tipoDeActor: json['actorType'] as String,
        identidadDelActor: json['actorIdentityId'] as String?,
        tipoDeEntidad: json['entityType'] as String,
        entidadId: json['entityId'] as String?,
        accion: json['action'] as String,
        antes: json['before'] as String?,
        despues: json['after'] as String?,
        motivo: json['reason'] as String?,
        // `DateTime.parse` acepta el ISO-8601 con zona que manda el servidor. Se
        // guarda tal cual y se convierte a local SÓLO al pintar: un `toLocal()` aquí
        // perdería la información de que el dato vino en UTC.
        cuando: DateTime.parse(json['occurredAt'] as String),
      );

  final String id;

  /// Quién actuó, en categorías: una persona, el sistema, la plataforma.
  ///
  /// **No es el nombre de nadie.** El nombre, cuando se puede, lo resuelve la pantalla
  /// cruzando [identidadDelActor] con la lista de quienes tienen acceso.
  final String tipoDeActor;

  /// La identidad que actuó, **o nula**: hay hechos que no los hace una persona.
  ///
  /// Nulo NO significa «desconocido por error»: significa que ese hecho no tuvo actor
  /// humano, y la pantalla lo dice con esas palabras.
  final String? identidadDelActor;

  /// Sobre qué se actuó, con el código del servidor —`area`, `company_access`…—.
  final String tipoDeEntidad;

  final String? entidadId;

  /// Qué se hizo: `created`, `granted`, `revoked`, `disabled`…
  final String accion;

  /// El estado anterior y el posterior, **como texto JSON**. Nulos cuando no aplica:
  /// un alta no tiene «antes» y una baja puede no tener «después».
  final String? antes;
  final String? despues;

  /// El motivo que escribió quien actuó, si la operación pedía uno.
  final String? motivo;

  /// Cuándo pasó, **en la zona que mandó el servidor**.
  final DateTime cuando;

  /// ¿Lo hizo una persona identificable?
  bool get loHizoUnaPersona => identidadDelActor != null;
}

/// Una página de auditoría. **`siguienteCursor` nulo significa que no hay más**, no
/// que haya fallado.
class PaginaDeAuditoria {
  const PaginaDeAuditoria({required this.eventos, required this.siguienteCursor});

  factory PaginaDeAuditoria.deJson(Map<String, dynamic> json) =>
      PaginaDeAuditoria(
        eventos: [
          for (final fila in json['items'] as List)
            EventoDeAuditoria.deJson(fila as Map<String, dynamic>),
        ],
        siguienteCursor: json['nextCursor'] as String?,
      );

  final List<EventoDeAuditoria> eventos;

  /// El cursor para pedir la página siguiente. **Es opaco y no lleva alcance**: el
  /// servidor recalcula de qué empresa se trata en cada petición desde la autoridad de
  /// quien pregunta, así que presentarlo no permite asomarse a otra.
  final String? siguienteCursor;

  bool get hayMas => siguienteCursor != null;
}
