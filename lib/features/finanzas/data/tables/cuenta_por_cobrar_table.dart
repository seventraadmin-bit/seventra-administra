import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';
import '../../../organizacion/data/tables/documento_por_emitir_table.dart';
import '../../../usuarios/data/tables/usuario_table.dart';

/// Estatus de progreso de cobro de una Cuenta por cobrar (Etapa 4J.1)
/// — deliberadamente sin `vencida`: esa condición nunca se almacena,
/// se deriva en el dominio a partir de `fechaVencimiento`/`estatus`
/// (Resolución D de Marlon: nunca un proceso en segundo plano solo
/// para mantener un estado al día). En 4J.1 ningún caso de uso mueve
/// una cuenta de `pendiente` a `parcial`/`pagada` todavía — el modelo
/// existe desde ahora, la interfaz de pagos llega en una etapa futura
/// (Resolución G).
enum EstatusCuentaPorCobrar { pendiente, parcial, pagada }

/// Tipos de evento del historial de una Cuenta por cobrar
/// (`CuentaPorCobrarEvento`) — mismo criterio append-only que
/// `DocumentoPorEmitirEvento`. `pagoAplicado`/`pagoAplicacionCancelada`
/// se agregaron en la Etapa 4J.2: registran el efecto de cada
/// `AplicacionPago` sobre esta Cuenta específica — el ciclo de vida
/// del Pago en sí (registrado/corregido/cancelado) vive en
/// `PagoEvento`, no aquí, porque bajo el modelo N:M un Pago puede
/// tocar varias Cuentas a la vez.
enum TipoEventoCuentaPorCobrar { creada, fechaVencimientoDefinida, pagoAplicado, pagoAplicacionCancelada }

/// Obligación de cobro real, generada automáticamente cuando un
/// `DocumentoPorEmitir` llega a `Procesado/Aceptado` (Etapa 4J.1,
/// Resolución A de Marlon) — 1:1 con su documento de origen, nunca
/// antes de ese estatus, nunca más de una por documento
/// (`UNIQUE(documento_por_emitir_id)`, exigido también en el dominio).
///
/// Snapshot administrativo completo (Resolución explícita de Marlon:
/// "no quiero depender de joins para reconstruir el documento años
/// después") — copia folio/serie/folio fiscal/UUID/importe emitido/
/// fecha de emisión real del documento al momento de crear la cuenta,
/// además de los campos que la Cuenta por cobrar necesita para
/// filtrar/reportar sin join (`clienteId`, `tipoDocumento`, `metodo`,
/// `requiereComplemento`).
///
/// `saldoOriginal` es seguro de congelar: `CorregirDatosEmisionDocumentoPorEmitirUseCase`
/// (Etapa 4I.2.1) ya rechaza cualquier corrección de `importeEmitido`
/// una vez que el documento está `Procesado/Aceptado` — no existe una
/// vía real por la que el snapshot pueda quedar desactualizado.
///
/// `moneda` existe desde ahora aunque hoy solo se use `'MXN'`
/// (Resolución explícita de Marlon: evitar una migración de tabla
/// completa el día que aparezca el primer cliente extranjero).
class CuentaPorCobrar extends Table with AuditColumns {
  TextColumn get documentoPorEmitirId =>
      text().unique().references(DocumentoPorEmitir, #id, onDelete: KeyAction.restrict)();

  TextColumn get clienteId => text()();

  // Literal en vez de referencia al enum — mismo motivo que en
  // `DocumentoPorEmitir`: `tipoDocumento` reutiliza `TipoDocumentoCobro`,
  // `metodo` reutiliza `MetodoPagoCobro` (Etapa 4H.1) — nunca se
  // inventa un enum paralelo para el mismo concepto.
  TextColumn get tipoDocumento => text()();

  TextColumn get metodo => text()();

  BoolColumn get requiereComplemento => boolean().withDefault(const Constant(false))();

  TextColumn get folioDocumento => text().nullable()();

  TextColumn get serieFiscal => text().nullable()();

  TextColumn get folioFiscal => text().nullable()();

  TextColumn get uuid => text().nullable()();

  DateTimeColumn get fechaEmisionReal => dateTime()();

  IntColumn get importeEmitido => integer()();

  IntColumn get saldoOriginal => integer()();

  IntColumn get saldoPendiente => integer()();

  TextColumn get moneda => text().withDefault(const Constant('MXN'))();

  TextColumn get estatus => text().withDefault(const Constant('pendiente'))();

  /// `null` mientras el documento de origen no tenga una fecha de
  /// pago esperado calculable (caso Mirabilia) — se completa después
  /// vía la acción administrativa "Definir fecha de vencimiento"
  /// (Resolución E de Marlon), nunca inventada al crear la cuenta.
  DateTimeColumn get fechaVencimiento => dateTime().nullable()();

  TextColumn get observaciones => text().nullable()();

  @override
  List<String> get customConstraints => [
        'CHECK (saldo_original >= 0)',
        'CHECK (saldo_pendiente >= 0 AND saldo_pendiente <= saldo_original)',
        'CHECK (importe_emitido >= 0)',
      ];
}

/// Historial administrativo de una Cuenta por cobrar (Etapa 4J.1) —
/// tabla de solo inserción: nunca se actualiza ni se elimina una fila
/// existente, mismo criterio exacto que `DocumentoPorEmitirEvento`.
class CuentaPorCobrarEvento extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get cuentaPorCobrarId =>
      text().references(CuentaPorCobrar, #id, onDelete: KeyAction.cascade)();

  DateTimeColumn get fechaHora => dateTime()();

  TextColumn get tipoEvento => text()();

  TextColumn get estadoAnterior => text().nullable()();

  TextColumn get estadoNuevo => text().nullable()();

  TextColumn get observacion => text().nullable()();

  /// **Legacy (Etapa 11D)** — nunca se pobló con un valor real; se
  /// conserva la columna físicamente por seguridad de migración pero
  /// ningún código desde 11D en adelante la lee ni la escribe. La única
  /// fuente funcional de "quién" es `actorUsuarioId`.
  TextColumn get actor => text().nullable()();

  TextColumn get actorUsuarioId => text().nullable().references(Usuario, #id, onDelete: KeyAction.setNull)();

  /// JSON libre con el snapshot de lo que cambió — mismo criterio que
  /// `DocumentoPorEmitirEvento.datosRelevantes`.
  TextColumn get datosRelevantes => text().nullable()();
}
