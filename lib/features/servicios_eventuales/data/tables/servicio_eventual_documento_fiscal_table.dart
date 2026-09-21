import 'package:drift/drift.dart';

import '../../../../core/database/tables/attachment_table.dart';
import '../../../../core/database/tables/audit_columns.dart';
import '../../../organizacion/data/tables/entidad_fiscal_table.dart';
import '../../../usuarios/data/tables/usuario_table.dart';
import 'servicio_eventual_table.dart';

/// Ciclo de vida del documento fiscal de un eventual — deliberadamente
/// los mismos dos estados que `ComplementoPago`, y por la misma razón:
/// un CFDI o se sostiene o se canceló, no hay estados intermedios que
/// RISEG pueda conocer (no timbra, sólo registra lo que un sistema
/// externo emitió). Añadir más estados sería inventar información que
/// el sistema no tiene.
enum EstatusDocumentoFiscalEventual { registrado, cancelado }

/// El CFDI —o el documento equivalente— que se emitió por un Servicio
/// Eventual (schemaVersion 88).
///
/// **RISEG ONE no timbra.** Esta tabla registra lo que un sistema
/// externo ya generó, exactamente con el mismo criterio que
/// `DocumentoPorEmitir.registrarEmision` en la cobranza recurrente:
/// `folio` es obligatorio y `uuid` no lo es, porque el UUID suele
/// llegar después del folio (Resolución 11 de la Etapa 4I.2.1).
///
/// **A lo más uno VIGENTE por eventual**, conservando el histórico de
/// los cancelados: eso NO se puede expresar con `servicioEventualId`
/// `UNIQUE` —eso impediría guardar el documento cancelado y su
/// sustituto a la vez— sino con el índice único parcial de abajo,
/// mismo mecanismo exacto que resolvió el complemento sustituto en la
/// schemaVersion 79.
@TableIndex.sql(
  'CREATE UNIQUE INDEX IF NOT EXISTS servicio_eventual_documento_fiscal_vigente '
  "ON servicio_eventual_documento_fiscal (servicio_eventual_id) WHERE estatus = 'registrado'",
)
class ServicioEventualDocumentoFiscal extends Table with AuditColumns {
  TextColumn get servicioEventualId =>
      text().references(ServicioEventual, #id, onDelete: KeyAction.restrict)();

  /// Folio del documento tal como lo emitió el sistema externo —
  /// obligatorio, igual que en la cobranza recurrente.
  TextColumn get folio => text()();

  /// Folio fiscal (UUID). Nullable a propósito: en la operación real
  /// el folio se conoce al emitir y el UUID puede capturarse después.
  /// Su formato se valida en el caso de uso cuando viene poblado,
  /// nunca aquí.
  TextColumn get uuid => text().nullable()();

  DateTimeColumn get fechaEmision => dateTime()();

  /// Total del documento. Coincide con `ServicioEventual.importeAcordado`
  /// y con `CuentaPorCobrar.importeEmitido`: en v1 los tres representan
  /// la misma venta y el mismo número (decisión explícita de Marlon —
  /// `importeAcordado` ES el total que el cliente paga, no una base a
  /// la que después se le suma IVA).
  IntColumn get importe => integer()();

  /// `pue`/`ppd` — reutiliza `MetodoPagoCobro`, nunca un enum paralelo.
  /// `noAplica` no se guarda aquí: un eventual sin factura simplemente
  /// no tiene documento fiscal.
  TextColumn get metodo => text()();

  BoolColumn get requiereComplemento => boolean().withDefault(const Constant(false))();

  /// **Snapshot congelado** de a nombre de quién se emitió. Las
  /// pantallas históricas leen esto, jamás la `EntidadFiscal` viva: si
  /// el Cliente cambia de razón social mañana, el documento de ayer
  /// tiene que seguir diciendo lo que decía.
  ///
  /// Sólo razón social y RFC porque es lo único que el sistema tiene:
  /// `regimenFiscal`/`usoCfdi` no existen como dato estructurado en
  /// RISEG ONE (auditado y excluido en la Etapa 16), así que pedirlos
  /// aquí crearía un campo que el camino de Cliente nunca podría
  /// llenar.
  TextColumn get snapshotRazonSocial => text()();

  TextColumn get snapshotRfc => text()();

  /// CP fiscal del receptor, congelado igual que los otros dos
  /// (schemaVersion 90). Nullable **sólo** por el histórico: los
  /// documentos emitidos antes de la v90 no lo capturaron nunca y
  /// rellenarlos hoy con el CP actual del Cliente sería inventar que
  /// aquel CFDI decía algo que no decía.
  TextColumn get snapshotCodigoPostalFiscal => text().nullable()();

  /// Procedencia y navegación, nunca fuente de lectura: de qué
  /// `EntidadFiscal` se copió el snapshot. `null` cuando el solicitante
  /// es eventual — ahí los datos fiscales se capturan a mano y **no**
  /// se crea ni Cliente ni EntidadFiscal permanente.
  TextColumn get entidadFiscalId =>
      text().nullable().references(EntidadFiscal, #id, onDelete: KeyAction.restrict)();

  TextColumn get estatus => text().withDefault(const Constant('registrado'))();

  TextColumn get motivoCancelacion => text().nullable()();

  TextColumn get observaciones => text().nullable()();

  TextColumn get actorUsuarioId => text().nullable().references(Usuario, #id, onDelete: KeyAction.setNull)();

  @override
  List<String> get customConstraints => [
        'CHECK (importe > 0)',
      ];
}

/// Tabla puente ServicioEventualDocumentoFiscal↔Attachment — mismo
/// patrón por dominio que el resto desde la Etapa 5A (el PDF/XML del
/// CFDI vive aquí, no en un brazo más de `Attachment`).
class ServicioEventualDocumentoFiscalAttachment extends Table {
  TextColumn get attachmentId => text().references(Attachment, #id, onDelete: KeyAction.cascade)();

  TextColumn get servicioEventualDocumentoFiscalId =>
      text().references(ServicioEventualDocumentoFiscal, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {attachmentId};
}
