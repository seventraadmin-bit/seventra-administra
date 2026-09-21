import 'package:riseg_one/features/organizacion/domain/repositories/servicio_repository.dart';

/// División comercial primaria del listado (pedido explícito: "que
/// aparezca dividido en vigente y finalizado") — separa Servicios cuyo
/// contrato sigue vigente de aquellos ya terminados, independiente del
/// filtro más granular de `filtroEstatus`.
enum GrupoVigenciaServicio { vigentes, finalizados }

bool servicioEstatusEsFinalizado(String estatus) => estatus == 'terminado';

/// Filtro de Cliente/Tipo/Estatus del listado de Servicios (Etapa 16,
/// pasada visual de Comercial) — `null` significa "todos", nunca un
/// valor mágico separado.
class ServiciosListState {
  const ServiciosListState({
    this.cargando = true,
    this.servicios = const [],
    this.errorCarga,
    this.busqueda = '',
    this.logoPathPorClienteId = const {},
    this.personalPorServicio = const {},
    this.turnoPorServicio = const {},
    this.filtroClienteId,
    this.filtroEstatus,
    this.filtroTipoServicioId,
    this.grupo = GrupoVigenciaServicio.vigentes,
  });

  final bool cargando;
  final List<ServicioListItem> servicios;
  final String? errorCarga;
  final String busqueda;

  /// Ruta real en disco del logo del Cliente dueño, por `clienteId` —
  /// resuelta en lote junto con la carga de la lista (Etapa 16,
  /// evolución visual), mismo criterio que `ClientesListState`.
  final Map<String, String> logoPathPorClienteId;

  /// Personal con asignación vigente por Servicio
  /// (`AsignacionServicio.servicioId`, relación real) — agregado en
  /// memoria sobre `listarTodasActivas()`, la misma consulta en lote ya
  /// usada por `ClientesListController`, nunca una consulta por fila.
  final Map<String, int> personalPorServicio;

  /// Nombre(s) de Modalidad de turno entre el Personal vigente de cada
  /// Servicio (`AsignacionServicio.turnoId`) — join " / " cuando hay más
  /// de un turno distinto en el mismo Servicio; cadena vacía si ninguna
  /// asignación vigente tiene turno capturado.
  final Map<String, String> turnoPorServicio;

  final String? filtroClienteId;
  final String? filtroEstatus;
  final String? filtroTipoServicioId;
  final GrupoVigenciaServicio grupo;

  bool get hayFiltrosActivos =>
      busqueda.trim().isNotEmpty || filtroClienteId != null || filtroEstatus != null || filtroTipoServicioId != null;

  /// Clientes distintos presentes en el listado ya cargado — nunca una
  /// consulta nueva, solo de-duplicación en memoria sobre `servicios`.
  List<(String id, String nombre)> get clientesDisponibles {
    final vistos = <String>{};
    final resultado = <(String, String)>[];
    for (final item in servicios) {
      if (vistos.add(item.servicio.clienteId)) resultado.add((item.servicio.clienteId, item.clienteNombre));
    }
    resultado.sort((a, b) => a.$2.compareTo(b.$2));
    return resultado;
  }

  /// Tipos de Servicio distintos presentes en el listado ya cargado —
  /// mismo criterio que [clientesDisponibles].
  List<(String id, String nombre)> get tiposDisponibles {
    final vistos = <String>{};
    final resultado = <(String, String)>[];
    for (final item in servicios) {
      if (vistos.add(item.servicio.tipoServicioId)) resultado.add((item.servicio.tipoServicioId, item.tipoServicioNombre));
    }
    resultado.sort((a, b) => a.$2.compareTo(b.$2));
    return resultado;
  }

  /// Filtra por código, nombre, Cliente, Tipo de Servicio u
  /// observaciones, más Cliente/Estatus/Tipo — todo en memoria, sin
  /// volver a consultar la base de datos por cada letra tecleada (mismo
  /// patrón que `ClientesListState.clientesFiltrados`).
  List<ServicioListItem> get serviciosFiltrados {
    final termino = busqueda.trim().toLowerCase();

    return servicios.where((item) {
      final esFinalizado = servicioEstatusEsFinalizado(item.servicio.estatus);
      if (grupo == GrupoVigenciaServicio.vigentes && esFinalizado) return false;
      if (grupo == GrupoVigenciaServicio.finalizados && !esFinalizado) return false;

      if (termino.isNotEmpty) {
        final observaciones = item.servicio.observaciones?.toLowerCase() ?? '';
        final coincide = item.servicio.codigo.toLowerCase().contains(termino) ||
            item.servicio.nombre.toLowerCase().contains(termino) ||
            item.clienteNombre.toLowerCase().contains(termino) ||
            item.tipoServicioNombre.toLowerCase().contains(termino) ||
            observaciones.contains(termino);
        if (!coincide) return false;
      }
      if (filtroClienteId != null && item.servicio.clienteId != filtroClienteId) return false;
      if (filtroEstatus != null && item.servicio.estatus != filtroEstatus) return false;
      if (filtroTipoServicioId != null && item.servicio.tipoServicioId != filtroTipoServicioId) return false;
      return true;
    }).toList();
  }

  ServiciosListState copyWith({
    bool? cargando,
    List<ServicioListItem>? servicios,
    String? errorCarga,
    String? busqueda,
    Map<String, String>? logoPathPorClienteId,
    Map<String, int>? personalPorServicio,
    Map<String, String>? turnoPorServicio,
    String? filtroClienteId,
    bool limpiarFiltroCliente = false,
    String? filtroEstatus,
    bool limpiarFiltroEstatus = false,
    String? filtroTipoServicioId,
    bool limpiarFiltroTipo = false,
    GrupoVigenciaServicio? grupo,
  }) {
    return ServiciosListState(
      cargando: cargando ?? this.cargando,
      servicios: servicios ?? this.servicios,
      errorCarga: errorCarga,
      busqueda: busqueda ?? this.busqueda,
      logoPathPorClienteId: logoPathPorClienteId ?? this.logoPathPorClienteId,
      personalPorServicio: personalPorServicio ?? this.personalPorServicio,
      turnoPorServicio: turnoPorServicio ?? this.turnoPorServicio,
      filtroClienteId: limpiarFiltroCliente ? null : (filtroClienteId ?? this.filtroClienteId),
      filtroEstatus: limpiarFiltroEstatus ? null : (filtroEstatus ?? this.filtroEstatus),
      filtroTipoServicioId: limpiarFiltroTipo ? null : (filtroTipoServicioId ?? this.filtroTipoServicioId),
      grupo: grupo ?? this.grupo,
    );
  }
}
