import 'package:riseg_one/features/finanzas/domain/usecases/obtener_complementos_pendientes_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/resolver_nombres_contraparte_usecase.dart';

/// Qué se está mirando en Finanzas → Complementos (etapa "Complemento
/// dependiente del Pago real").
///
/// `pendientes` NO es un estatus de `ComplementoPago`: no existe tal
/// fila. Es una **proyección** de Pagos reales que exigen Complemento y
/// todavía no tienen uno vigente (ver
/// `ObtenerComplementosPendientesUseCase`). Por eso vive aquí, en la
/// vista, y no en el filtro `estatus` que va al repositorio.
enum VistaComplementos { pendientes, registrados, cancelados, todos }

/// Estado del listado de Complementos de pago (Etapa 4J.3, ampliado en
/// la etapa "Complemento dependiente del Pago real").
class ComplementosState {
  const ComplementosState({
    this.cargando = true,
    this.vista = VistaComplementos.pendientes,
    this.complementos = const [],
    this.pendientes = const [],
    this.errorCarga,
    this.clienteId,
    this.contextoPorComplemento = const {},
    this.nombrePorCliente = const {},
    this.nombres = const NombresContraparte.vacio(),
  });

  final bool cargando;

  /// Arranca en `pendientes`: la pregunta que la pantalla no sabía
  /// responder era "¿qué complementos me faltan?".
  final VistaComplementos vista;

  /// Complementos reales visibles según [vista] (vacío en `pendientes`).
  final List<ComplementoConContexto> complementos;

  /// Proyección derivada — nunca filas persistidas.
  final List<ComplementoPendiente> pendientes;

  final String? errorCarga;
  final String? clienteId;

  /// Contexto (Pago + Cuentas cubiertas) por id de Complemento, para no
  /// copiar Cliente/Folio/CxC dentro de `ComplementoPago` sólo para
  /// pintar la UI — todo se deriva de las FK reales.
  final Map<String, ComplementoConContexto> contextoPorComplemento;

  final Map<String, String> nombrePorCliente;

  /// Contrapartes ya resueltas (Cliente o Servicio Eventual) de los
  /// Pagos en pantalla — schemaVersion 88.
  final NombresContraparte nombres;

  /// Cuántos complementos faltan — se calcula siempre, para que el
  /// contador de la pestaña sea correcto aunque se esté mirando otra
  /// vista.
  int get totalPendientes => pendientes.length;

  ComplementosState copyWith({
    bool? cargando,
    VistaComplementos? vista,
    List<ComplementoConContexto>? complementos,
    List<ComplementoPendiente>? pendientes,
    String? errorCarga,
    String? clienteId,
    Map<String, ComplementoConContexto>? contextoPorComplemento,
    Map<String, String>? nombrePorCliente,
    NombresContraparte? nombres,
    bool limpiarClienteId = false,
  }) {
    return ComplementosState(
      cargando: cargando ?? this.cargando,
      vista: vista ?? this.vista,
      complementos: complementos ?? this.complementos,
      pendientes: pendientes ?? this.pendientes,
      errorCarga: errorCarga,
      clienteId: limpiarClienteId ? null : (clienteId ?? this.clienteId),
      contextoPorComplemento: contextoPorComplemento ?? this.contextoPorComplemento,
      nombrePorCliente: nombrePorCliente ?? this.nombrePorCliente,
      nombres: nombres ?? this.nombres,
    );
  }
}
