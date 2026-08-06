import 'package:riseg_one/core/database/app_database.dart';

/// Estado del listado de la Agenda de documentos por emitir (Etapa
/// 4I.1) — mismo shape que `ServiciosListState`, con filtros propios en
/// vez de una sola búsqueda de texto libre.
class AgendaState {
  const AgendaState({
    this.cargando = true,
    this.generando = false,
    this.documentos = const [],
    this.errorCarga,
    DateTime? rangoInicio,
    DateTime? rangoFin,
    this.clienteId,
    this.servicioId,
    this.tipoDocumento,
    this.estatus,
  })  : _rangoInicio = rangoInicio,
        _rangoFin = rangoFin;

  final bool cargando;

  /// Bloquea "Generar agenda"/"Crear manual" contra doble-clic.
  final bool generando;
  final List<DocumentoPorEmitirData> documentos;
  final String? errorCarga;
  final DateTime? _rangoInicio;
  final DateTime? _rangoFin;
  final String? clienteId;
  final String? servicioId;
  final String? tipoDocumento;
  final String? estatus;

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
  }) {
    return AgendaState(
      cargando: cargando ?? this.cargando,
      generando: generando ?? this.generando,
      documentos: documentos ?? this.documentos,
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
