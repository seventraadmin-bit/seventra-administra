import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';
import '../../../organizacion/data/tables/documento_por_emitir_table.dart';
import '../../../servicios_eventuales/data/tables/servicio_eventual_table.dart';
import '../../../usuarios/data/tables/usuario_table.dart';

/// Estatus de progreso de cobro de una Cuenta por cobrar (Etapa 4J.1)
/// — deliberadamente sin `vencida`: esa condición nunca se almacena,
/// se deriva en el dominio a partir de `fechaVencimiento`/`estatus`
/// (Resolución D de Marlon: nunca un proceso en segundo plano solo
/// para mantener un estado al día).
///
/// `cancelada` (Etapa 7): la obligación en sí se anula — nunca se
/// alcanza automáticamente por saldo, solo vía
/// `CancelarCuentaPorCobrarUseCase`, y solo si no tiene ninguna
/// `AplicacionPago` activa (una Cuenta `pagada` siempre tiene al menos
/// una, así que nunca es candidata). Terminal: una vez `cancelada`,
/// ninguna otra operación (corregir/reprogramar/aplicar un Pago) la
/// toca de nuevo.
enum EstatusCuentaPorCobrar { pendiente, parcial, pagada, cancelada }

/// Tipos de evento del historial de una Cuenta por cobrar
/// (`CuentaPorCobrarEvento`) — mismo criterio append-only que
/// `DocumentoPorEmitirEvento`. `pagoAplicado`/`pagoAplicacionCancelada`
/// se agregaron en la Etapa 4J.2: registran el efecto de cada
/// `AplicacionPago` sobre esta Cuenta específica — el ciclo de vida
/// del Pago en sí (registrado/corregido/cancelado) vive en
/// `PagoEvento`, no aquí, porque bajo el modelo N:M un Pago puede
/// tocar varias Cuentas a la vez.
/// `fechaCobroReprogramada` (Etapa 19D) — registra el cambio de
/// expectativa de cobro (incluida su remoción, `fechaCobroReprogramada:
/// null`) de una CxC ya vencida, sin tocar `fechaVencimiento` (ver el
/// doc comment de esa columna abajo).
/// `fechaVencimientoDefinida` — **legacy** (Etapa 7): ningún código
/// nuevo lo escribe, se conserva para no perder el significado de
/// filas históricas ya existentes; `corregida` lo reemplaza (cubre
/// `fechaVencimiento`/`observaciones` juntos, vía `DiffEvento`).
/// `cancelada` (Etapa 7) — la CxC pasa a `EstatusCuentaPorCobrar.cancelada`.
enum TipoEventoCuentaPorCobrar {
  creada,
  fechaVencimientoDefinida,
  pagoAplicado,
  pagoAplicacionCancelada,
  fechaCobroReprogramada,
  corregida,
  cancelada,
}

/// Obligación de cobro real, generada automáticamente cuando un
/// `DocumentoPorEmitir` llega a `Procesado/Aceptado` (Etapa 4J.1,
/// Resolución A de Marlon) — 1:1 con su documento de origen, nunca
/// antes de ese estatus, nunca más de una por documento
/// (`UNIQUE(documento_por_emitir_id)`, exigido también en el dominio).
///
/// Snapshot administrativo completo (Resolución explícita de Marlon:
/// "no quiero depender de joins para reconstruir el documento años
/// después") — copia folio/UUID (folio fiscal)/importe emitido/fecha de
/// emisión real del documento al momento de crear la cuenta, además de
/// los campos que la Cuenta por cobrar necesita para filtrar/reportar
/// sin join (`clienteId`, `tipoDocumento`, `metodo`,
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
  /// **Nullable desde schemaVersion 87.** Una Cuenta por cobrar nace de
  /// un `DocumentoPorEmitir` (cobranza recurrente) **o** de un
  /// `ServicioEventual` (venta puntual) — exactamente uno de los dos,
  /// nunca ambos, nunca ninguno (`CHECK` abajo). No existe un enum
  /// `tipoOrigen` redundante: el origen se deriva inequívocamente de
  /// estas dos FK.
  ///
  /// Sigue siendo `UNIQUE`: en SQLite cada `NULL` cuenta como distinto,
  /// así que N cuentas de eventual conviven sin índice parcial mientras
  /// un documento sigue teniendo a lo más una cuenta.
  TextColumn get documentoPorEmitirId =>
      text().nullable().unique().references(DocumentoPorEmitir, #id, onDelete: KeyAction.restrict)();

  /// Origen eventual — schemaVersion 87.
  TextColumn get servicioEventualId =>
      text().nullable().references(ServicioEventual, #id, onDelete: KeyAction.restrict)();

  /// **Nullable desde schemaVersion 87**, y sigue siendo un snapshot sin
  /// FK (ver el doc comment de la tabla). Una cuenta de eventual cuyo
  /// solicitante NO es Cliente permanente no tiene ninguno que copiar;
  /// una cuyo solicitante sí lo es lo copia igual que hoy, para que
  /// filtros, notificaciones y análisis de cobranza sigan funcionando
  /// sin una sola línea nueva.
  ///
  /// Quién es la contraparte se resuelve SIEMPRE con `ContraparteCobro`,
  /// nunca comparando este campo a mano.
  TextColumn get clienteId => text().nullable()();

  // Literal en vez de referencia al enum — mismo motivo que en
  // `DocumentoPorEmitir`: `tipoDocumento` reutiliza `TipoDocumentoCobro`,
  // `metodo` reutiliza `MetodoPagoCobro` (Etapa 4H.1) — nunca se
  // inventa un enum paralelo para el mismo concepto.
  TextColumn get tipoDocumento => text()();

  TextColumn get metodo => text()();

  BoolColumn get requiereComplemento => boolean().withDefault(const Constant(false))();

  TextColumn get folioDocumento => text().nullable()();

  TextColumn get uuid => text().nullable()();

  DateTimeColumn get fechaEmisionReal => dateTime()();

  /// Monto real y total del documento (Total del CFDI, o importe del
  /// recibo) — el monto efectivamente cobrable al Cliente, copiado tal
  /// cual de `DocumentoPorEmitir.importeEmitido` (ver su doc comment).
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

  /// Expectativa de cobro reprogramada (Etapa 19D, "Calendario
  /// financiero y planeación de liquidez") — nunca sobrescribe
  /// [fechaVencimiento] (que sigue siendo la fecha contractual
  /// original, siempre visible). Solo tiene efecto en la proyección de
  /// caja cuando la cuenta YA está vencida: una CxC vencida sin esta
  /// fecha se excluye de "entradas previstas" (su cobro real ya no es
  /// predecible) y aparece en "Pendientes vencidos" en su lugar; con
  /// esta fecha capturada, vuelve a proyectarse en la nueva fecha. Se
  /// captura vía `ReprogramarCobroCuentaPorCobrarUseCase`, auditada en
  /// `CuentaPorCobrarEvento` (`fechaCobroReprogramada`).
  DateTimeColumn get fechaCobroReprogramada => dateTime().nullable()();

  TextColumn get observaciones => text().nullable()();

  @override
  List<String> get customConstraints => [
        'CHECK (saldo_original >= 0)',
        'CHECK (saldo_pendiente >= 0 AND saldo_pendiente <= saldo_original)',
        'CHECK (importe_emitido >= 0)',
        // schemaVersion 87 — origen exclusivo y obligatorio. Es un XOR
        // literal: en SQLite `<>` sobre dos booleanos es exactamente eso.
        'CHECK ((documento_por_emitir_id IS NOT NULL) <> (servicio_eventual_id IS NOT NULL))',
        // Toda cuenta tiene contraparte: un Cliente real, o el eventual
        // que la originó.
        'CHECK (cliente_id IS NOT NULL OR servicio_eventual_id IS NOT NULL)',
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
