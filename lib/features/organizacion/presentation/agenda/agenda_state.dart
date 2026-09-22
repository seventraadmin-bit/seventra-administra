import 'package:riseg_one/core/database/app_database.dart';

/// Estado del listado de la Agenda de documentos por emitir (Etapa
/// 4I.1) — mismo shape que `ServiciosListState`, con filtros propios en
/// vez de una sola búsqueda de texto libre.
class AgendaState {
  const AgendaState({
    this.cargando = true,
    this.generando = false,
    this.documentos = const [],
    this.totalEsperadoPorDocumento = const {},
    this.errorCarga,
    DateTime? rangoInicio,
    DateTime? rangoFin,
    this.clienteId,
    this.servicioId,
    this.tipoDocumento,
    this.estatus,
    this.modoPendientes = false,
  })  : _rangoInicio = rangoInicio,
        _rangoFin = rangoFin;

  final bool cargando;

  /// Bloquea "Generar agenda"/"Crear manual" contra doble-clic.
  final bool generando;
  final List<DocumentoPorEmitirData> documentos;

  /// Total esperado de cada documento (contractual + ajuste + IVA que
  /// corresponda), derivado en cada carga desde los snapshots ya
  /// persistidos — nunca se guarda en la base ni reescribe historia.
  ///
  /// La clave ausente significa **no calculable** (hoy: mixto con ajuste),
  /// que es distinto de cero y por eso se representa con la ausencia y no
  /// con un 0 que se sumaría sin ruido.
  final Map<String, int> totalEsperadoPorDocumento;
  final String? errorCarga;
  final DateTime? _rangoInicio;
  final DateTime? _rangoFin;
  final String? clienteId;
  final String? servicioId;
  final String? tipoDocumento;
  final String? estatus;

  /// Vista de "Pendientes de emisión": el conjunto accionable de
  /// CUALQUIER periodo, el mismo que cuentan la alerta del Dashboard y el
  /// Centro de notificaciones.
  ///
  /// No es un filtro más: cambia la unidad de lo que se está mirando. La
  /// vista normal es un mes; ésta es un conjunto de trabajo sin mes, y por
  /// eso el rango de fechas deja de aplicarse mientras está activa.
  final bool modoPendientes;

  /// El filtro de rango por defecto es el mes calendario actual —
  /// nunca se interpreta como "periodo iniciado este mes" (esa
  /// distinción vive en `GenerarAgendaUseCase`), aquí es solo la
  /// ventana de fechas de emisión programada que se está consultando.
  DateTime get rangoInicio => _rangoInicio ?? DateTime(DateTime.now().year, DateTime.now().month, 1);

  DateTime get rangoFin =>
      _rangoFin ?? DateTime(DateTime.now().year, DateTime.now().month + 1, 0);

  AgendaState copyWith({
    bool? cargando,
    bool? generando,
    List<DocumentoPorEmitirData>? documentos,
    Map<String, int>? totalEsperadoPorDocumento,
    String? errorCarga,
    DateTime? rangoInicio,
    DateTime? rangoFin,
    String? clienteId,
    String? servicioId,
    String? tipoDocumento,
    String? estatus,
    bool limpiarClienteId = false,
    bool limpiarServicioId = false,
    bool limpiarTipoDocumento = false,
    bool limpiarEstatus = false,
    bool? modoPendientes,
  }) {
    return AgendaState(
      cargando: cargando ?? this.cargando,
      generando: generando ?? this.generando,
      documentos: documentos ?? this.documentos,
      totalEsperadoPorDocumento: totalEsperadoPorDocumento ?? this.totalEsperadoPorDocumento,
      modoPendientes: modoPendientes ?? this.modoPendientes,
      errorCarga: errorCarga,
      rangoInicio: rangoInicio ?? _rangoInicio,
      rangoFin: rangoFin ?? _rangoFin,
      clienteId: limpiarClienteId ? null : (clienteId ?? this.clienteId),
      servicioId: limpiarServicioId ? null : (servicioId ?? this.servicioId),
      tipoDocumento: limpiarTipoDocumento ? null : (tipoDocumento ?? this.tipoDocumento),
      estatus: limpiarEstatus ? null : (estatus ?? this.estatus),
    );
  }
}
