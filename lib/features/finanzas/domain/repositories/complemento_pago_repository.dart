import 'package:riseg_one/core/database/app_database.dart';

/// Complementos de pago (CFDI de Recepción de Pagos) registrados
/// administrativamente (Etapa 4J.3) — un Pago tiene **N Complementos
/// históricos y a lo más UNO vigente** (schemaVersion 79). Nunca genera
/// ni timbra nada: solo deja constancia de un complemento ya emitido
/// externamente.
abstract interface class ComplementoPagoRepository {
  Future<ComplementoPagoData?> obtenerPorId(String id);

  /// El Complemento **vigente** (`estatus == 'registrado'`) de ese
  /// Pago, o `null` si la obligación sigue pendiente — sea porque nunca
  /// hubo uno, o porque el único que hubo se canceló.
  ///
  /// Es la consulta correcta para decidir "¿este Pago ya está
  /// documentado?". El índice único parcial
  /// `complemento_pago_vigente_por_pago` garantiza que devuelva a lo
  /// más una fila. **Nunca** uses [listarPorPagoId] para esto: mezcla
  /// cancelados.
  Future<ComplementoPagoData?> obtenerVigentePorPagoId(String pagoId);

  /// TODOS los Complementos de ese Pago, vigentes y cancelados, del más
  /// reciente al más antiguo — el histórico completo. La fila cancelada
  /// nunca se borra ni se reusa: es evidencia de un CFDI que existió.
  Future<List<ComplementoPagoData>> listarPorPagoId(String pagoId);

  /// `null` si ese UUID no está registrado en ningún otro Complemento
  /// — usado para la validación de unicidad amigable (además del
  /// `UNIQUE` en base de datos).
  Future<ComplementoPagoData?> obtenerPorUuid(String uuid);

  /// `clienteId` filtra vía join contra `Pago` — `ComplementoPago` no
  /// denormaliza ese campo, ya vive en el Pago al que pertenece.
  Future<List<ComplementoPagoData>> listar({
    String? clienteId,
    String? estatus,
    DateTime? rangoInicio,
    DateTime? rangoFin,
  });

  Future<List<ComplementoPagoEventoData>> listarEventos(String complementoPagoId);

  /// Inserta el Complemento y registra el evento `registrado`. El
  /// llamador (caso de uso) ya validó que no exista otro VIGENTE para
  /// ese Pago, la unicidad y el formato del UUID, y
  /// `fechaTimbrado >= Pago.fechaPago`. El índice único parcial es el
  /// candado final: aunque un llamador se saltara la validación, la
  /// base rechaza un segundo Complemento vigente.
  Future<ComplementoPagoData> crear({
    required String pagoId,
    required String uuid,
    String? serieFiscal,
    String? folioFiscal,
    required DateTime fechaTimbrado,
    required int montoTotal,
    String? observaciones,
    String? actorUsuarioId,
  });

  /// Corrige metadatos administrativos — nunca `uuid` ni `montoTotal`
  /// (Resolución de Marlon: un error ahí se cancela y se registra un
  /// Complemento nuevo, nunca se edita). Registra el evento
  /// `corregido` con los valores anterior/nuevo.
  Future<ComplementoPagoData> corregir({
    required String complementoPagoId,
    String? serieFiscal,
    String? folioFiscal,
    DateTime? fechaTimbrado,
    String? observaciones,
    required String motivo,
    String? actorUsuarioId,
  });

  /// Cancela el Complemento — sin cascada (a diferencia de cancelar un
  /// `Pago`): un `ComplementoPago` no tiene entidades hijas que
  /// revertir, cancelarlo solo cambia su propio estatus. Registra el
  /// evento `cancelado`.
  Future<ComplementoPagoData> cancelar({
    required String complementoPagoId,
    required String motivo,
    String? actorUsuarioId,
  });

  /// Adjunta un archivo (PDF/XML) — mismo mecanismo que cualquier otro
  /// `Attachment`. Registra el evento `archivoAdjuntado`.
  Future<AttachmentData> adjuntarArchivo({
    required String complementoPagoId,
    required String categoria,
    required String originalFileName,
    required String storedFileName,
    required String path,
    required String mimeType,
    required int sizeBytes,
    String? actorUsuarioId,
  });
}
