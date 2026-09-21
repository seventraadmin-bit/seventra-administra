import 'package:riseg_one/core/database/app_database.dart';

/// Filtro de "con/sin servicios" del listado de Clientes (Etapa 16,
/// pasada visual de Comercial) — derivado de `serviciosActivosPorCliente`
/// (relación real `Servicio.clienteId`), nunca inventado.
enum FiltroServiciosCliente { todos, conServicios, sinServicios }

/// División comercial primaria del listado (pedido explícito: "que
/// aparezca dividido en vigente y finalizado") — separa Clientes cuya
/// relación comercial sigue viva de aquellos cuya relación ya terminó,
/// independiente del filtro más granular de `filtroEstado`. `terminado`
/// (Cliente que fue comercialmente activo y dejó de serlo) y
/// `descartado` (prospecto que nunca llegó a convertirse) son ambos
/// relaciones ya cerradas — ninguno de los dos pertenece a "vigentes".
enum GrupoComercialCliente { vigentes, finalizados }

bool clienteEstatusEsFinalizado(String estatus) => estatus == 'terminado' || estatus == 'descartado';

/// Estado de la pantalla de listado de Clientes comerciales.
class ClientesListState {
  const ClientesListState({
    this.cargando = true,
    this.clientes = const [],
    this.errorCarga,
    this.busqueda = '',
    this.logoPathPorClienteId = const {},
    this.direccionReferenciaPorClienteId = const {},
    this.serviciosActivosPorCliente = const {},
    this.personalPorCliente = const {},
    this.filtroEstado,
    this.filtroServicios = FiltroServiciosCliente.todos,
    this.grupo = GrupoComercialCliente.vigentes,
  });

  final bool cargando;
  final List<ClienteData> clientes;
  final String? errorCarga;
  final String busqueda;

  /// Ruta real en disco del logo vigente, por Cliente — resuelta en
  /// lote junto con la carga de la lista (Etapa 16, evolución visual),
  /// nunca una consulta por fila. Solo contiene entradas para Clientes
  /// que sí tienen `logoAttachmentId`.
  final Map<String, String> logoPathPorClienteId;

  /// Dirección de referencia por Cliente (`Direccion.clienteId`,
  /// `tipoDireccion = referencia`) — resuelta en lote, nunca una
  /// consulta por tarjeta. Ausente para Clientes sin ninguna
  /// capturada.
  final Map<String, DireccionData> direccionReferenciaPorClienteId;

  /// Servicios con `estatus = activo` por Cliente (`Servicio.clienteId`,
  /// relación real) y Personal con asignación vigente por Cliente
  /// (cadena real `AsignacionServicio.servicioId → Servicio.clienteId`)
  /// — ambos agregados en memoria sobre listados completos ya
  /// cargados una sola vez (Etapa 16), nunca una consulta nueva por
  /// fila.
  final Map<String, int> serviciosActivosPorCliente;
  final Map<String, int> personalPorCliente;

  final String? filtroEstado;
  final FiltroServiciosCliente filtroServicios;
  final GrupoComercialCliente grupo;

  bool get hayFiltrosActivos =>
      (busqueda.trim().isNotEmpty) || filtroEstado != null || filtroServicios != FiltroServiciosCliente.todos;

  /// Filtra por grupo comercial (Vigentes/Finalizados) primero, luego
  /// código/nombre comercial/observaciones, Estado y con/sin servicios —
  /// todo en memoria, sin volver a consultar la base de datos.
  List<ClienteData> get clientesFiltrados {
    final termino = busqueda.trim().toLowerCase();

    return clientes.where((c) {
      final esFinalizado = clienteEstatusEsFinalizado(c.estatus);
      if (grupo == GrupoComercialCliente.vigentes && esFinalizado) return false;
      if (grupo == GrupoComercialCliente.finalizados && !esFinalizado) return false;

      if (termino.isNotEmpty) {
        final observaciones = c.observaciones?.toLowerCase() ?? '';
        final coincide = c.codigo.toLowerCase().contains(termino) ||
            c.nombreComercial.toLowerCase().contains(termino) ||
            observaciones.contains(termino);
        if (!coincide) return false;
      }
      if (filtroEstado != null && c.estatus != filtroEstado) return false;

      final tieneServicios = (serviciosActivosPorCliente[c.id] ?? 0) > 0;
      if (filtroServicios == FiltroServiciosCliente.conServicios && !tieneServicios) return false;
      if (filtroServicios == FiltroServiciosCliente.sinServicios && tieneServicios) return false;

      return true;
    }).toList();
  }

  ClientesListState copyWith({
    bool? cargando,
    List<ClienteData>? clientes,
    String? errorCarga,
    String? busqueda,
    Map<String, String>? logoPathPorClienteId,
    Map<String, DireccionData>? direccionReferenciaPorClienteId,
    Map<String, int>? serviciosActivosPorCliente,
    Map<String, int>? personalPorCliente,
    String? filtroEstado,
    bool limpiarFiltroEstado = false,
    FiltroServiciosCliente? filtroServicios,
    GrupoComercialCliente? grupo,
  }) {
    return ClientesListState(
      cargando: cargando ?? this.cargando,
      clientes: clientes ?? this.clientes,
      errorCarga: errorCarga,
      busqueda: busqueda ?? this.busqueda,
      logoPathPorClienteId: logoPathPorClienteId ?? this.logoPathPorClienteId,
      direccionReferenciaPorClienteId: direccionReferenciaPorClienteId ?? this.direccionReferenciaPorClienteId,
      serviciosActivosPorCliente: serviciosActivosPorCliente ?? this.serviciosActivosPorCliente,
      personalPorCliente: personalPorCliente ?? this.personalPorCliente,
      filtroEstado: limpiarFiltroEstado ? null : (filtroEstado ?? this.filtroEstado),
      filtroServicios: filtroServicios ?? this.filtroServicios,
      grupo: grupo ?? this.grupo,
    );
  }
}
