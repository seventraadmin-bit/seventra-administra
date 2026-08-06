import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';
import 'cliente_table.dart';
import 'configuracion_cobro_vigencia_table.dart';
import 'entidad_fiscal_table.dart';
import 'servicio_linea_comercial_vigencia_table.dart';
import 'servicio_table.dart';

/// Estados de la Etapa 4I.1 únicamente — Emitido/Enviado/
/// Procesado-Aceptado llegan en la 4I.2, sin necesitar una migración
/// nueva (el valor se guarda como texto libre, igual que todo enum del
/// proyecto). Deliberadamente sin ningún estado de pago (pendiente de
/// pago/vencido/pagado/parcial) — esos pertenecen a la futura Cuenta
/// por cobrar.
enum EstatusDocumentoPorEmitir { pendiente, enPreparacion, cancelado, noRequerido }

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

  @override
  List<String> get customConstraints => [
        'CHECK (periodo_fin >= periodo_inicio)',
        'CHECK (importe_base_esperado >= 0)',
        'CHECK (importe_final_esperado >= 0)',
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
/// cálculo proporcional ya redondeado de esa línea. El hueco para un
/// futuro descuento por cobertura no prestada vive en `diasAplicables`
/// sin rediseñar nada hoy.
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

/// Correos de envío snapshot — copiados de la Configuración de cobro al
/// generar, mismo criterio que `ConfiguracionCobroCorreo`.
class DocumentoPorEmitirCorreo extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get documentoPorEmitirId =>
      text().references(DocumentoPorEmitir, #id, onDelete: KeyAction.cascade)();

  TextColumn get correo => text()();
}
