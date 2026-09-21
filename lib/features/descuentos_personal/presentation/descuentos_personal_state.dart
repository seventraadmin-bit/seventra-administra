import 'package:riseg_one/core/database/app_database.dart';

/// Una fila del listado global — el descuento más los agregados
/// derivados de sus cuotas que la tabla en sí no almacena (recuperado,
/// próxima cuota).
class DescuentoProgramadoResumen {
  const DescuentoProgramadoResumen({
    required this.descuento,
    required this.empleadoNombre,
    required this.numeroEmpleado,
    required this.proximaCuota,
  });

  final DescuentoProgramadoEmpleadoData descuento;
  final String empleadoNombre;

  /// `null` solo si el Empleado ya no existe (registro huérfano) — la
  /// columna de identidad muestra únicamente el nombre en ese caso.
  final int? numeroEmpleado;
  final DescuentoProgramadoCuotaData? proximaCuota;

  int get recuperado => descuento.importeOriginal - descuento.saldoPendiente;

  /// Progreso 0–100 de recuperación (Etapa 16, evolución visual) —
  /// `pagado/importeOriginal`, protegido contra división por cero
  /// (un `importeOriginal` de 0 no puede ocurrir por su propio CHECK,
  /// pero un registro futuro con otro tipo no se descarta). `null`
  /// para `cancelado`: un saldo cancelado nunca "sigue cobrándose",
  /// no debe leerse como progreso hacia liquidar.
  double? get progresoPorcentaje {
    if (descuento.estatus == 'cancelado') return null;
    if (descuento.importeOriginal <= 0) return null;
    return (recuperado / descuento.importeOriginal * 100)
        .clamp(0, 100)
        .toDouble();
  }
}

/// KPIs de la pantalla global "Descuentos al Personal" — agregados
/// simples sobre las obligaciones activas, recalculados en cada carga
/// (nunca cacheados aparte).
class DescuentosPersonalKpis {
  const DescuentosPersonalKpis({
    this.saldoPendienteTotal = 0,
    this.prestamosActivos = 0,
    this.cobrosProximos = 0,
    this.empleadosConSaldo = 0,
  });

  final int saldoPendienteTotal;
  final int prestamosActivos;

  /// Cuotas `pendiente`/`reservada` cuya `fechaProgramada` cae dentro
  /// de los próximos 15 días (una quincena) — mismo horizonte que un
  /// ciclo de Nómina.
  final int cobrosProximos;
  final int empleadosConSaldo;
}

/// Sub-filtro de tipo/estatus DENTRO del grupo activo (pedido
/// explícito: separar activos/cancelados en dos pestañas) — `activos`/
/// `cancelados` ya no existen aquí, esa partición ahora la decide
/// [GrupoEstadoDescuento] primero; este enum solo refina lo que ya
/// quedó dentro del grupo elegido.
enum DescuentosPersonalFiltro { todos, prestamos, botas, liquidados }

/// Partición primaria del listado (pedido explícito: "cancelados y
/// activos en dos pestañas", mismo criterio que `GrupoVigenciaServicio`/
/// `GrupoComercialCliente`) — un descuento `cancelado` nunca aparece en
/// [activos], y viceversa.
enum GrupoEstadoDescuento { activos, cancelados }

bool descuentoEstatusEsCancelado(String estatus) => estatus == 'cancelado';

class DescuentosPersonalState {
  const DescuentosPersonalState({
    this.cargando = true,
    this.descuentos = const [],
    this.kpis = const DescuentosPersonalKpis(),
    this.grupo = GrupoEstadoDescuento.activos,
    this.filtro = DescuentosPersonalFiltro.todos,
    this.fotografiaPathPorEmpleadoId = const {},
    this.errorCarga,
  });

  final bool cargando;
  final List<DescuentoProgramadoResumen> descuentos;
  final DescuentosPersonalKpis kpis;
  final GrupoEstadoDescuento grupo;
  final DescuentosPersonalFiltro filtro;

  /// Fotografía vigente del Empleado por `empleadoId` (Etapa 16,
  /// evolución visual) — identidad visual del Empleado hoy, resuelta
  /// en una sola consulta en lote, nunca por renglón.
  final Map<String, String> fotografiaPathPorEmpleadoId;
  final String? errorCarga;

  List<DescuentoProgramadoResumen> get visibles {
    final delGrupo = descuentos.where((d) {
      final cancelado = descuentoEstatusEsCancelado(d.descuento.estatus);
      return grupo == GrupoEstadoDescuento.cancelados ? cancelado : !cancelado;
    });
    return switch (filtro) {
      DescuentosPersonalFiltro.todos => delGrupo.toList(),
      DescuentosPersonalFiltro.prestamos => delGrupo.where((d) => d.descuento.tipo == 'prestamo').toList(),
      DescuentosPersonalFiltro.botas => delGrupo.where((d) => d.descuento.tipo == 'botas').toList(),
      DescuentosPersonalFiltro.liquidados => delGrupo.where((d) => d.descuento.estatus == 'liquidado').toList(),
    };
  }

  DescuentosPersonalState copyWith({
    bool? cargando,
    List<DescuentoProgramadoResumen>? descuentos,
    DescuentosPersonalKpis? kpis,
    GrupoEstadoDescuento? grupo,
    DescuentosPersonalFiltro? filtro,
    Map<String, String>? fotografiaPathPorEmpleadoId,
    String? errorCarga,
  }) {
    return DescuentosPersonalState(
      cargando: cargando ?? this.cargando,
      descuentos: descuentos ?? this.descuentos,
      kpis: kpis ?? this.kpis,
      grupo: grupo ?? this.grupo,
      filtro: filtro ?? this.filtro,
      fotografiaPathPorEmpleadoId: fotografiaPathPorEmpleadoId ?? this.fotografiaPathPorEmpleadoId,
      errorCarga: errorCarga,
    );
  }
}
