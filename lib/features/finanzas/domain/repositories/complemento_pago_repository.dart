import 'package:riseg_one/core/database/app_database.dart';

/// Complementos de pago (CFDI de Recepción de Pagos) registrados
/// administrativamente (Etapa 4J.3) — relación **1:1 con `Pago`**
/// (decisión definitiva de Marlon: "no quiero una relación N:M en
/// esta etapa"). Nunca genera ni timbra nada — solo deja constancia de
/// un complemento ya emitido externamente.
abstract interface class ComplementoPagoRepository {
  Future<ComplementoPagoData?> obtenerPorId(String id);

  /// `null` si ese Pago todavía no tiene Complemento registrado —
  /// también la vía para hacer cumplir la relación 1:1 antes de
  /// insertar (además del `UNIQUE` en base de datos).
  Future<ComplementoPagoData?> obtenerPorPagoId(String pagoId);

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
  /// llamador (caso de uso) ya validó la relación 1:1, la unicidad del
  /// UUID, el formato del UUID y `fechaTimbrado >= Pago.fechaPago`.
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
