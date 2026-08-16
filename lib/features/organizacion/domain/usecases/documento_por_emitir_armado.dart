/// Un hito planeado de una etapa activa que sí resolvió fecha (Etapa
/// 15) — snapshot listo para `DocumentoPorEmitirHito`, ya sin `null`
/// (las etapas sin fecha calculable nunca llegan a ser un hito: no
/// participan en Agenda).
class HitoArmado {
  const HitoArmado({required this.orden, required this.fecha, this.tipoSistema, this.nombre});

  final int orden;
  final DateTime fecha;
  final String? tipoSistema;
  final String? nombre;
}

/// Qué vigencia de Configuración de cobro se usó para un Servicio
/// incluido, y las fechas que calculó — un elemento de
/// `DocumentoPorEmitirArmado.configuraciones` (una fila por Servicio,
/// nunca una sola para todo el documento — corrección estructural de la
/// Etapa 4I.1). `fechaEmisionProgramada`/`fechaProcesamientoProgramada`/
/// `fechaPagoEsperadoProgramada` son el adaptador legacy (Etapa 15):
/// derivadas de [hitos] por `tipoSistema`, se conservan mientras Agenda/
/// CxC sigan leyéndolas directamente. [hitos] es la fuente completa —
/// cualquier etapa activa con fecha calculable, de sistema o
/// personalizada.
class ConfiguracionServicioArmada {
  const ConfiguracionServicioArmada({
    required this.servicioId,
    required this.configuracionCobroVigenciaId,
    this.fechaEmisionProgramada,
    this.fechaProcesamientoProgramada,
    this.fechaPagoEsperadoProgramada,
    this.hitos = const [],
  });

  final String servicioId;
  final String configuracionCobroVigenciaId;
  final DateTime? fechaEmisionProgramada;
  final DateTime? fechaProcesamientoProgramada;
  final DateTime? fechaPagoEsperadoProgramada;
  final List<HitoArmado> hitos;
}

/// Snapshot ya calculado de una línea comercial incluida — un elemento
/// de `DocumentoPorEmitirArmado.lineas`.
class LineaArmada {
  const LineaArmada({
    required this.servicioId,
    required this.lineaComercialVigenciaId,
    required this.puestoNombre,
    required this.modalidadTurnoNombre,
    required this.cantidadElementos,
    required this.precioUnitario,
    required this.tratamientoIva,
    required this.diasAplicables,
    required this.subtotalProporcional,
  });

  final String servicioId;
  final String lineaComercialVigenciaId;
  final String puestoNombre;
  final String modalidadTurnoNombre;
  final int cantidadElementos;
  final int precioUnitario;
  final String tratamientoIva;
  final int diasAplicables;
  final int subtotalProporcional;
}

/// Todo lo necesario para persistir un `DocumentoPorEmitir` — ya
/// resuelto, calculado y validado por el caso de uso que lo arma
/// (`GenerarAgendaUseCase`/`CrearDocumentoManualUseCase`); el
/// repositorio solo lo inserta, transaccionalmente, en la tabla
/// principal y sus 4 hijas.
class DocumentoPorEmitirArmado {
  const DocumentoPorEmitirArmado({
    required this.clienteId,
    required this.tipoDocumento,
    required this.agrupacion,
    required this.metodo,
    required this.requiereComplemento,
    required this.periodoInicio,
    required this.periodoFin,
    required this.generationKey,
    required this.importeBaseEsperado,
    required this.servicioIds,
    required this.configuraciones,
    required this.lineas,
    required this.correos,
    this.entidadFiscalId,
    this.clientePortalId,
    this.fechaEmisionProgramada,
    this.fechaProcesamientoProgramada,
    this.fechaPagoEsperadoProgramada,
  });

  final String clienteId;
  final String? entidadFiscalId;

  /// Qué `ClientePortal` se usó al generar este documento — referencia,
  /// nunca un snapshot de sus datos (decisión explícita de Marlon,
  /// Etapa 15: si el portal se edita después, el documento histórico
  /// refleja el valor actual del portal, mismo criterio que
  /// `entidadFiscalId`).
  final String? clientePortalId;
  final String tipoDocumento;
  final String agrupacion;
  final String metodo;
  final bool requiereComplemento;
  final DateTime periodoInicio;
  final DateTime periodoFin;

  /// Representativas para calendario/listado — la más próxima cuando el
  /// documento agrupa varios Servicios (ver doc de la tabla).
  final DateTime? fechaEmisionProgramada;
  final DateTime? fechaProcesamientoProgramada;
  final DateTime? fechaPagoEsperadoProgramada;

  final String generationKey;
  final int importeBaseEsperado;
  final List<String> servicioIds;
  final List<ConfiguracionServicioArmada> configuraciones;
  final List<LineaArmada> lineas;
  final List<String> correos;
}
