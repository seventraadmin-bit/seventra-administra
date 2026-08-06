/// Qué vigencia de Configuración de cobro se usó para un Servicio
/// incluido, y las fechas que calculó — un elemento de
/// `DocumentoPorEmitirArmado.configuraciones` (una fila por Servicio,
/// nunca una sola para todo el documento — corrección estructural de la
/// Etapa 4I.1).
class ConfiguracionServicioArmada {
  const ConfiguracionServicioArmada({
    required this.servicioId,
    required this.configuracionCobroVigenciaId,
    this.fechaEmisionProgramada,
    this.fechaProcesamientoProgramada,
    this.fechaPagoEsperadoProgramada,
  });

  final String servicioId;
  final String configuracionCobroVigenciaId;
  final DateTime? fechaEmisionProgramada;
  final DateTime? fechaProcesamientoProgramada;
  final DateTime? fechaPagoEsperadoProgramada;
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
    this.fechaEmisionProgramada,
    this.fechaProcesamientoProgramada,
    this.fechaPagoEsperadoProgramada,
  });

  final String clienteId;
  final String? entidadFiscalId;
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
