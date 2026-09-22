import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';
import '../../../usuarios/data/tables/usuario_table.dart';
import 'cliente_portal_table.dart';
import 'cliente_table.dart';
import 'configuracion_cobro_vigencia_table.dart';
import 'entidad_fiscal_table.dart';
import 'servicio_linea_comercial_vigencia_table.dart';
import 'servicio_table.dart';

/// Estados de la Etapa 4I.1+4I.2.1 — `emitido`/`enviado`/
/// `procesadoAceptado` se agregan en la 4I.2.1 (Emitido no puede pasar
/// a `cancelado`/`noRequerido` en esta etapa: eso implicaría una
/// cancelación fiscal real, fuera de alcance). Deliberadamente sin
/// ningún estado de pago (pendiente de pago/vencido/pagado/parcial) —
/// esos pertenecen a la futura Cuenta por cobrar.
enum EstatusDocumentoPorEmitir {
  pendiente,
  enPreparacion,
  cancelado,
  noRequerido,
  emitido,
  enviado,
  procesadoAceptado,
}

/// Tipos de evento del historial administrativo (`DocumentoPorEmitirEvento`,
/// Etapa 4I.2.1) — catálogo mínimo requerido explícitamente por Marlon.
/// `edicionObservaciones` queda reservado para cuando exista un caso de
/// uso real que edite `observaciones` fuera del flujo de emisión/envío
/// (ninguno existe todavía en 4I.2.1) — no se inventa ese flujo solo
/// para "usar" el valor del enum.
enum TipoEventoDocumentoPorEmitir {
  creadoAutomatico,
  creadoManual,
  marcadoEnPreparacion,
  ajusteRegistrado,

  /// Corrección del ajuste comercial de un documento YA emitido
  /// (Maestro). Distinto de `ajusteRegistrado` a propósito: ese es el
  /// flujo normal previo a la emisión; este reescribe un dato histórico
  /// y por eso lleva su propio motivo administrativo, separado del
  /// motivo comercial del ajuste.
  correccionAjusteHistorico,
  emisionRegistrada,
  correccionDatosEmision,
  archivoAdjuntado,
  archivoReemplazado,
  envioRegistrado,
  correccionEnviadoAEmitido,
  procesadoAceptado,
  cancelado,
  marcadoNoRequerido,
  edicionObservaciones,
}

/// Una obligación administrativa de preparar un documento (CFDI o
/// recibo) para un periodo — nunca el documento fiscal/recibo real ni
/// una Cuenta por cobrar (Etapa 4I.1). Todos los Servicios incluidos se
/// relacionan siempre vía `DocumentoPorEmitirServicio` (Resolución A:
/// una sola fuente de verdad, incluso para el caso de un solo
/// Servicio) — esta tabla nunca tiene su propio `servicioId`.
///
/// `clienteId`/`entidadFiscalId`/`tipoDocumento`/`metodo`/
/// `requiereComplemento` son valores únicos a nivel de documento porque
/// la compatibilidad de agrupación (`esCompatiblePara`, dominio) ya
/// garantiza que todo Servicio incluido comparte estos mismos valores
/// — agrupar Servicios con condiciones distintas produce documentos
/// separados, nunca uno solo con valores mixtos.
///
/// `fechaEmisionProgramada`/`fechaProcesamientoProgramada`/
/// `fechaPagoEsperadoProgramada` son una copia representativa (la más
/// próxima, cuando el documento agrupa varios Servicios) de los valores
/// reales que sí se guardan por Servicio en
/// `DocumentoPorEmitirConfiguracion` — sirven solo para listar/filtrar
/// por calendario sin una consulta adicional.
class DocumentoPorEmitir extends Table with AuditColumns {
  TextColumn get codigo => text().unique()();

  TextColumn get clienteId => text().references(Cliente, #id, onDelete: KeyAction.restrict)();

  TextColumn get entidadFiscalId =>
      text().nullable().references(EntidadFiscal, #id, onDelete: KeyAction.restrict)();

  /// Qué portal del Cliente se usó para este documento (Etapa 15) —
  /// referencia, igual que `entidadFiscalId`, nunca un snapshot: si el
  /// portal se edita después de generar este documento, el documento
  /// histórico refleja el valor actual del portal (decisión explícita
  /// de Marlon — sin duplicar datos de portal en Agenda).
  TextColumn get clientePortalId =>
      text().nullable().references(ClientePortal, #id, onDelete: KeyAction.restrict)();

  // Literales en vez de referencias a los enums — mismo motivo que
  // `AuditColumns.cicloVidaRegistro`. `tipoDocumento` reutiliza
  // `TipoDocumentoCobro`; `agrupacion` reutiliza `AgrupacionCobro`
  // (Etapa 4H.1) — nunca se inventa un enum paralelo.
  TextColumn get tipoDocumento => text()();

  TextColumn get agrupacion => text()();

  TextColumn get metodo => text()();

  BoolColumn get requiereComplemento => boolean().withDefault(const Constant(false))();

  DateTimeColumn get periodoInicio => dateTime()();

  DateTimeColumn get periodoFin => dateTime()();

  DateTimeColumn get fechaEmisionProgramada => dateTime().nullable()();

  DateTimeColumn get fechaProcesamientoProgramada => dateTime().nullable()();

  DateTimeColumn get fechaPagoEsperadoProgramada => dateTime().nullable()();

  /// Clave determinista de generación — protege la idempotencia real
  /// (un documento agrupado puede usar varias vigencias de cobro a la
  /// vez, así que `UNIQUE(configuracionCobroVigenciaId, periodoInicio)`
  /// no alcanza). Calculada en el dominio a partir de: agrupación,
  /// Cliente, Entidad fiscal, el conjunto ordenado de Servicios, el
  /// conjunto ordenado de vigencias de cobro, periodoInicio, periodoFin
  /// y tipoDocumento — ver `calcularGenerationKey`.
  TextColumn get generationKey => text().unique()();

  IntColumn get importeBaseEsperado => integer()();

  IntColumn get ajusteManual => integer().nullable()();

  TextColumn get motivoAjuste => text().nullable()();

  IntColumn get importeFinalEsperado => integer()();

  TextColumn get estatus => text().withDefault(const Constant('pendiente'))();

  /// Motivo obligatorio al pasar a `cancelado`/`noRequerido` — el mismo
  /// campo cubre ambos casos (ver dominio para la distinción semántica
  /// entre uno y otro).
  TextColumn get motivoEstatus => text().nullable()();

  TextColumn get observaciones => text().nullable()();

  // Datos definitivos del documento (Etapa 4I.2.1) — aditivos,
  // directamente en `DocumentoPorEmitir` y no en una entidad 1:1
  // separada (Corrección explícita de Marlon): solo existe una emisión
  // administrativa vigente por documento, nunca una colección, y el
  // historial de correcciones ya vive en `DocumentoPorEmitirEvento`.
  // Todos nullable: no existen hasta que se registra la emisión.
  TextColumn get folioDocumento => text().nullable()();

  /// Identificador fiscal único del CFDI ("folio fiscal" / UUID del
  /// timbre — en un CFDI real son el mismo dato, nunca dos
  /// independientes; corrección estructural Etapa 15, antes existían
  /// `folioFiscal`/`uuid` por separado sin ninguna relación entre
  /// ambos). Solo aplica a `tipoDocumento = cfdi` — `null` siempre para
  /// recibo. Puede capturarse después de marcar `emitido` (ej. al
  /// adjuntar el XML) — nunca obligatorio en el momento de la emisión
  /// misma. Validado con formato UUID (`esUuidFormatoValido`, mismo
  /// validador que ya usaba `ComplementoPago.uuid`).
  TextColumn get uuid => text().nullable()();

  DateTimeColumn get fechaEmisionReal => dateTime().nullable()();

  /// Monto real y total del documento tal como fue emitido (Total del
  /// CFDI, o importe del recibo) — el monto efectivamente cobrable al
  /// Cliente, nunca un subtotal antes de impuestos. Para
  /// `tratamientoIva = masIva` este valor NO se deriva de
  /// `importeFinalEsperado` (que es antes de IVA): RISEG ONE no calcula
  /// tasas de IVA, se captura el Total real del comprobante emitido
  /// externamente (Etapa 15, corrección estructural CFDI real).
  IntColumn get importeEmitido => integer().nullable()();

  TextColumn get observacionesEmision => text().nullable()();

  DateTimeColumn get fechaEnvio => dateTime().nullable()();

  TextColumn get observacionesEnvio => text().nullable()();

  @override
  List<String> get customConstraints => [
        'CHECK (periodo_fin >= periodo_inicio)',
        'CHECK (importe_base_esperado >= 0)',
        'CHECK (importe_final_esperado >= 0)',
        'CHECK (importe_emitido IS NULL OR importe_emitido >= 0)',
      ];
}

/// Servicios incluidos en un documento — siempre a través de esta tabla
/// (Resolución A), incluso cuando el documento corresponde a un único
/// Servicio (agrupación `porServicio`). Sin lifecycle propio: se
/// reconstruye completa al generar, mismo criterio que
/// `ConfiguracionCobroCorreo`.
class DocumentoPorEmitirServicio extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get documentoPorEmitirId =>
      text().references(DocumentoPorEmitir, #id, onDelete: KeyAction.cascade)();

  TextColumn get servicioId => text().references(Servicio, #id, onDelete: KeyAction.restrict)();

  @override
  List<String> get customConstraints => ['UNIQUE (documento_por_emitir_id, servicio_id)'];
}

/// Qué vigencia de Configuración de cobro se usó para cada Servicio
/// incluido, y las fechas que esa vigencia calculó — corrección
/// estructural explícita: un documento agrupado por Entidad fiscal o
/// Cliente puede incluir Servicios con vigencias de cobro distintas (ya
/// validadas como compatibles), así que nunca hay una sola
/// `configuracionCobroVigenciaId` a nivel de documento. Un documento de
/// un solo Servicio tiene exactamente una fila aquí; uno agrupado tiene
/// varias.
class DocumentoPorEmitirConfiguracion extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get documentoPorEmitirId =>
      text().references(DocumentoPorEmitir, #id, onDelete: KeyAction.cascade)();

  TextColumn get servicioId => text().references(Servicio, #id, onDelete: KeyAction.restrict)();

  TextColumn get configuracionCobroVigenciaId =>
      text().references(ConfiguracionCobroVigencia, #id, onDelete: KeyAction.restrict)();

  DateTimeColumn get fechaEmisionProgramada => dateTime().nullable()();

  DateTimeColumn get fechaProcesamientoProgramada => dateTime().nullable()();

  DateTimeColumn get fechaPagoEsperadoProgramada => dateTime().nullable()();

  @override
  List<String> get customConstraints => ['UNIQUE (documento_por_emitir_id, servicio_id)'];
}

/// Snapshot por línea comercial incluida — aquí vive `tratamientoIva`
/// (Resolución C: nunca un campo único a nivel de documento) y el
/// cálculo proporcional ya redondeado de esa línea.
///
/// `diasAplicables` es exclusivamente el prorrateo comercial: cuántos días
/// del periodo quedaron dentro de la vigencia de la condición comercial y
/// de la vida del Servicio (`calcularDiasAplicables`). No representa días
/// efectivamente cubiertos ni sabe nada de operación: Facturación no
/// consulta ausencias, coberturas ni incidencias, y cualquier diferencia
/// comercial se registra como el ajuste del documento, con su motivo.
class DocumentoPorEmitirLinea extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get documentoPorEmitirId =>
      text().references(DocumentoPorEmitir, #id, onDelete: KeyAction.cascade)();

  TextColumn get servicioId => text().references(Servicio, #id, onDelete: KeyAction.restrict)();

  TextColumn get lineaComercialVigenciaId =>
      text().references(ServicioLineaComercialVigencia, #id, onDelete: KeyAction.restrict)();

  TextColumn get puestoNombre => text()();

  TextColumn get modalidadTurnoNombre => text()();

  IntColumn get cantidadElementos => integer()();

  IntColumn get precioUnitario => integer()();

  TextColumn get tratamientoIva => text()();

  IntColumn get diasAplicables => integer()();

  IntColumn get subtotalProporcional => integer()();

  @override
  List<String> get customConstraints => [
        'CHECK (cantidad_elementos > 0)',
        'CHECK (precio_unitario > 0)',
        'CHECK (dias_aplicables > 0)',
        'CHECK (subtotal_proporcional >= 0)',
      ];
}

/// Hitos planeados de una vigencia de cobro, uno por etapa activa
/// (Etapa 15, ampliación "flujo posterior a la emisión") — snapshot
/// completo (`tipoSistema`/`nombre`/`orden`/`fechaProgramada`) tomado
/// al generar el documento, nunca un join vivo a
/// `ConfiguracionCobroEtapa` (mismo criterio que
/// `DocumentoPorEmitirLinea`): si la Configuración de cobro cambia o
/// una etapa se elimina después, los documentos ya generados conservan
/// exactamente los hitos que tenían en ese momento. Por Servicio, igual
/// que `DocumentoPorEmitirConfiguracion` — un documento agrupado puede
/// incluir Servicios con vigencias de cobro distintas, cada una con su
/// propio conjunto de etapas. Solo incluye etapas que sí resolvieron
/// una fecha (`CalcularFechasCobroUseCase` nunca inventa una) — una
/// etapa desactivada, o cuya regla todavía no se captura, nunca
/// participa en Agenda. Sin lifecycle propio: se reconstruye completa
/// junto con el documento, no se edita in place.
class DocumentoPorEmitirHito extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get documentoPorEmitirId =>
      text().references(DocumentoPorEmitir, #id, onDelete: KeyAction.cascade)();

  TextColumn get servicioId => text().references(Servicio, #id, onDelete: KeyAction.restrict)();

  /// Exactamente uno de `tipoSistema`/`nombre` es no nulo — mismo
  /// criterio que `ConfiguracionCobroEtapa`.
  TextColumn get tipoSistema => text().nullable()();

  TextColumn get nombre => text().nullable()();

  IntColumn get orden => integer()();

  DateTimeColumn get fechaProgramada => dateTime()();

  @override
  List<String> get customConstraints => ['CHECK (tipo_sistema IS NOT NULL OR nombre IS NOT NULL)'];
}

/// Correos de envío snapshot — copiados de la Configuración de cobro al
/// generar, mismo criterio que `ConfiguracionCobroCorreo`.
class DocumentoPorEmitirCorreo extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get documentoPorEmitirId =>
      text().references(DocumentoPorEmitir, #id, onDelete: KeyAction.cascade)();

  TextColumn get correo => text()();
}

/// Correos realmente utilizados al registrar el envío (Etapa 4I.2.1) —
/// distinta de `DocumentoPorEmitirCorreo` (esa es la lista de la
/// Configuración de cobro al momento de generar; esta es la lista
/// definitiva, editable, con la que realmente se envió). Se
/// reconstruye completa (borrar e insertar) cada vez que se registra o
/// re-registra un envío — el valor anterior queda preservado como
/// snapshot dentro del `datosRelevantes` del evento correspondiente,
/// nunca aquí.
class DocumentoPorEmitirCorreoEnvio extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get documentoPorEmitirId =>
      text().references(DocumentoPorEmitir, #id, onDelete: KeyAction.cascade)();

  TextColumn get correo => text()();
}

/// Historial administrativo (Etapa 4I.2.1) — tabla de solo inserción:
/// nunca se actualiza ni se elimina una fila existente. Cada acción
/// administrativa relevante agrega exactamente una fila, en la misma
/// transacción que la mutación real que representa.
class DocumentoPorEmitirEvento extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get documentoPorEmitirId =>
      text().references(DocumentoPorEmitir, #id, onDelete: KeyAction.cascade)();

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

  /// JSON libre con el snapshot de lo que cambió (ej. ajuste anterior/
  /// nuevo, folio anterior/nuevo, correos utilizados) — se justifica
  /// aquí porque es un log heterogéneo; nunca sustituye un campo
  /// principal consultable en otra tabla.
  TextColumn get datosRelevantes => text().nullable()();
}
