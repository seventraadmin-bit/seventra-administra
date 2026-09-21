import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/descuentos_personal/domain/repositories/descuento_programado_repository.dart';
import 'package:riseg_one/features/inventario/domain/repositories/articulo_repository.dart';
import 'package:riseg_one/features/inventario/domain/repositories/asignacion_repository.dart';
import 'package:riseg_one/features/inventario/domain/repositories/inventario_repository.dart';
import 'package:riseg_one/features/personal/data/tables/conciliacion_baja_table.dart';
import 'package:riseg_one/features/personal/domain/repositories/conciliacion_baja_repository.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/puesto_repository.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/servicio_repository.dart';
import 'package:riseg_one/features/personal/domain/repositories/asignacion_servicio_repository.dart';
import 'package:riseg_one/features/personal/domain/repositories/empleado_repository.dart';
import 'package:riseg_one/features/vehiculos/domain/repositories/asignacion_vehiculo_repository.dart';
import 'package:riseg_one/features/vehiculos/domain/repositories/vehiculo_repository.dart';

import 'comparacion_periodo.dart';

/// Qué clase de bien es un renglón. La conciliación apunta por FK a
/// exactamente una de las dos asignaciones.
enum TipoBienConciliado { inventario, vehiculo }

/// Cómo terminó la búsqueda del Servicio al que estaba adscrito el ex
/// empleado EN LA FECHA DE BAJA.
///
/// Son tres resultados distintos y ninguno puede confundirse con otro:
/// no saberlo no es lo mismo que saber que hay basura en los datos.
enum EstadoServicioHistorico {
  /// Exactamente una `AsignacionServicio` cubría la fecha de baja.
  resuelto,

  /// Ninguna la cubría. No hay respuesta y no se inventa una.
  sinAsignacion,

  /// Dos o más la cubrían. Elegir una sería arbitrario.
  inconsistente,
}

/// Servicio histórico de una baja, resuelto **sólo** por vigencia real
/// (`empleadoId` + `fechaInicio`/`fechaTermino` + FK a `Servicio`).
///
/// Nunca sale de la asignación vigente de hoy, ni del último servicio
/// "conocido", ni de `Empleado.sucursalId`, ni de los resguardos.
class ServicioHistorico {
  const ServicioHistorico.resuelto({required String this.servicioId, required String this.nombre})
      : estado = EstadoServicioHistorico.resuelto,
        candidatos = 1;

  const ServicioHistorico.sinAsignacion()
      : estado = EstadoServicioHistorico.sinAsignacion,
        servicioId = null,
        nombre = null,
        candidatos = 0;

  const ServicioHistorico.inconsistente(this.candidatos)
      : estado = EstadoServicioHistorico.inconsistente,
        servicioId = null,
        nombre = null;

  final EstadoServicioHistorico estado;

  /// Sólo cuando [estado] es `resuelto`. En los otros dos casos es
  /// `null` a propósito: no hay un servicio que nombrar.
  final String? servicioId;
  final String? nombre;

  /// Cuántas asignaciones cubrían la fecha de baja. Útil sólo cuando
  /// hay inconsistencia, para saber qué tan roto está el dato.
  final int candidatos;

  bool get esResuelto => estado == EstadoServicioHistorico.resuelto;
}

/// Una opción de un filtro de personas — el catálogo, no el resultado.
class OpcionPersonaFiltro {
  const OpcionPersonaFiltro({required this.empleadoId, required this.nombre, this.puesto});

  final String empleadoId;
  final String nombre;

  /// Puesto vigente de la persona, cuando se puede resolver. Se muestra
  /// para distinguir homónimos; nunca se usa para filtrar.
  final String? puesto;

  String get etiqueta => puesto == null ? nombre : '$nombre — $puesto';
}

/// Una opción del filtro de Servicio.
class OpcionServicioFiltro {
  const OpcionServicioFiltro({required this.servicioId, required this.nombre, this.cliente});

  final String servicioId;
  final String nombre;
  final String? cliente;

  String get etiqueta => cliente == null ? nombre : '$nombre — $cliente';
}

/// Catálogos de los filtros buscables.
///
/// Se arma SIEMPRE sobre el universo del periodo **sin filtrar**: si
/// dependiera del resultado ya filtrado, elegir a una persona dejaría
/// la lista con esa sola persona y el filtro se volvería un callejón
/// sin salida ("filtros que desaparecen").
class CatalogoFiltrosPatrimonio {
  const CatalogoFiltrosPatrimonio({
    required this.empleados,
    required this.autorizadores,
    required this.servicios,
  });

  static const vacio = CatalogoFiltrosPatrimonio(empleados: [], autorizadores: [], servicios: []);

  final List<OpcionPersonaFiltro> empleados;
  final List<OpcionPersonaFiltro> autorizadores;
  final List<OpcionServicioFiltro> servicios;
}

/// Concentración de problemas patrimoniales por Servicio.
///
/// Las bajas cuyo servicio no se pudo resolver NO se reparten entre los
/// demás: tienen su propio renglón, para que la suma del ranking siga
/// cuadrando con los KPI.
class ProblemaPorServicio {
  const ProblemaPorServicio({
    required this.estado,
    required this.servicioId,
    required this.nombre,
    required this.bajas,
    required this.pendientes,
    required this.perdidos,
    required this.importeDescuentos,
    required this.decisionesAutorizadas,
    required this.decisionesSinCobro,
  });

  final EstadoServicioHistorico estado;

  /// `null` en los renglones de "sin servicio" e "inconsistencia".
  final String? servicioId;

  /// `null` en esos mismos dos renglones: la pantalla y la exportación
  /// ponen su propio texto, nunca una celda vacía.
  final String? nombre;

  final int bajas;
  final int pendientes;
  final int perdidos;
  final int importeDescuentos;
  final int decisionesAutorizadas;
  final int decisionesSinCobro;

  int get bienesEnRiesgo => pendientes + perdidos;
}

/// Filtros de la sección Patrimonio y bajas.
///
/// El rango acota la **fecha de baja** de la conciliación. Lo demás son
/// cortes sobre el universo resultante.
class FiltroPatrimonio {
  const FiltroPatrimonio({
    this.empleadoId,
    this.autorizadorId,
    this.servicioId,
    this.tipoBien,
    this.resolucion,
    this.motivoNoEntrega,
    this.soloPendientes = false,
    this.conDescuento,
  });

  final String? empleadoId;
  final String? autorizadorId;

  /// Servicio HISTORICO de la baja (el vigente a la fecha de baja), no
  /// el servicio actual de nadie.
  final String? servicioId;

  final TipoBienConciliado? tipoBien;
  final ResolucionResguardoBaja? resolucion;
  final MotivoNoEntregaResguardo? motivoNoEntrega;

  /// Sólo lo que RISEG todavía espera recuperar.
  final bool soloPendientes;

  /// `true` = sólo con obligación económica; `false` = sólo sin ella;
  /// `null` = ambos.
  final bool? conDescuento;

  FiltroPatrimonio copyWith({
    String? empleadoId,
    String? autorizadorId,
    String? servicioId,
    TipoBienConciliado? tipoBien,
    ResolucionResguardoBaja? resolucion,
    MotivoNoEntregaResguardo? motivoNoEntrega,
    bool? soloPendientes,
    bool? conDescuento,
    bool limpiarEmpleado = false,
    bool limpiarAutorizador = false,
    bool limpiarServicio = false,
    bool limpiarTipoBien = false,
    bool limpiarResolucion = false,
    bool limpiarMotivo = false,
    bool limpiarConDescuento = false,
  }) {
    return FiltroPatrimonio(
      empleadoId: limpiarEmpleado ? null : (empleadoId ?? this.empleadoId),
      autorizadorId: limpiarAutorizador ? null : (autorizadorId ?? this.autorizadorId),
      servicioId: limpiarServicio ? null : (servicioId ?? this.servicioId),
      tipoBien: limpiarTipoBien ? null : (tipoBien ?? this.tipoBien),
      resolucion: limpiarResolucion ? null : (resolucion ?? this.resolucion),
      motivoNoEntrega: limpiarMotivo ? null : (motivoNoEntrega ?? this.motivoNoEntrega),
      soloPendientes: soloPendientes ?? this.soloPendientes,
      conDescuento: limpiarConDescuento ? null : (conDescuento ?? this.conDescuento),
    );
  }
}

/// Un renglón de conciliación con todo resuelto por FK: qué bien, de
/// quién, qué se decidió, quién autorizó, quién recibió y qué obligación
/// económica nació.
class RenglonPatrimonio {
  const RenglonPatrimonio({
    required this.renglon,
    required this.conciliacion,
    required this.empleadoNombre,
    required this.fechaBaja,
    required this.tipo,
    required this.bienDescripcion,
    required this.resolucion,
    required this.motivoNoEntrega,
    required this.destino,
    required this.condicion,
    required this.estatusUnidad,
    required this.pendienteDesde,
    required this.fechaCompromiso,
    required this.autorizadorNombre,
    required this.receptorNombre,
    required this.descuento,
    required this.cuotasDescuento,
    required this.valorAproximado,
    required this.servicioHistorico,
  });

  final ConciliacionBajaRenglonData renglon;
  final ConciliacionBajaData conciliacion;
  final String empleadoNombre;
  final DateTime fechaBaja;
  final TipoBienConciliado tipo;

  /// Artículo + unidad, o vehículo — siempre armado desde las entidades
  /// reales, nunca desde un texto guardado en el renglón.
  final String bienDescripcion;

  final ResolucionResguardoBaja resolucion;
  final MotivoNoEntregaResguardo? motivoNoEntrega;
  final DestinoDevolucionResguardo? destino;
  final CondicionDevolucionResguardo? condicion;

  /// Estatus físico actual de la unidad serializada. `null` para bienes
  /// por cantidad y para vehículos: no tienen `ArticuloUnidad`.
  final String? estatusUnidad;

  /// `Asignacion.pendienteRecuperacionDesde` — la marca real, no una
  /// inferencia. `null` significa que NO está pendiente.
  final DateTime? pendienteDesde;

  final DateTime? fechaCompromiso;
  final String? autorizadorNombre;
  final String? receptorNombre;

  /// La obligación económica creada por ESTE renglón, vía la FK
  /// `descuentoProgramadoId`. Nunca se busca por prefijo de folio.
  final DescuentoProgramadoEmpleadoData? descuento;

  /// En cuántas exhibiciones se programó recuperar la obligación. `0`
  /// cuando no hay descuento — nunca `1` por omisión: decir "una cuota"
  /// donde no hay cobro sería afirmar algo que nadie capturó.
  final int cuotasDescuento;

  /// Costo promedio del artículo, cuando se conoce. `null` = no hay
  /// entrada con costo capturado; nunca se asume 0.
  final int? valorAproximado;

  /// Servicio al que estaba adscrito el ex empleado EN LA FECHA DE
  /// BAJA, reconstruido por vigencia real de `AsignacionServicio`.
  ///
  /// No sale del resguardo: `Asignacion.empleadoId`/`servicioId` son
  /// mutuamente excluyentes por CHECK, así que un bien entregado a una
  /// persona NUNCA trae servicio. Tampoco sale de `ConciliacionBaja`,
  /// que no guarda snapshot de adscripción, ni del servicio actual de
  /// nadie: eso sería inventarlo.
  ///
  /// Sucursal, área y puesto siguen SIN dimensión histórica — no existe
  /// tabla con vigencias para reconstruirlos.
  final ServicioHistorico servicioHistorico;

  /// Sigue pendiente de recuperar: la marca existe y la resolución dejó
  /// el bien con la persona.
  bool get estaPendiente => pendienteDesde != null;

  /// El bien volvió a RISEG.
  bool get fueRecuperado =>
      resolucion == ResolucionResguardoBaja.devuelto || resolucion == ResolucionResguardoBaja.desecho;

  bool get sePerdio => resolucion == ResolucionResguardoBaja.perdido;

  bool get fueTransferido => resolucion == ResolucionResguardoBaja.transferido;

  /// Se decidió no recuperar y alguien lo autorizó con su nombre.
  bool get autorizadoSinRecuperar =>
      resolucion == ResolucionResguardoBaja.noEntregado &&
      (motivoNoEntrega?.exigeAutorizacion ?? false);

  /// Se renunció a cobrar algo que sí tenía costo, con motivo y
  /// autorizador.
  bool get noCobroAutorizado => renglon.motivoNoCobro != null && renglon.autorizadorEmpleadoId != null;

  int get importeDescuento => descuento?.importeOriginal ?? 0;

  int get saldoDescuento => descuento?.saldoPendiente ?? 0;

  int get aplicadoDescuento => (descuento?.importeOriginal ?? 0) - (descuento?.saldoPendiente ?? 0);
}

/// Cuántos bienes y cuánto importe concentra un ex empleado.
class ImpactoBaja {
  const ImpactoBaja({
    required this.empleadoId,
    required this.nombre,
    required this.fechaBaja,
    required this.bienesPendientes,
    required this.bienesPerdidos,
    required this.importeDescuentos,
    required this.valorComprometido,
    required this.decisionesAutorizadas,
  });

  final String empleadoId;
  final String nombre;
  final DateTime fechaBaja;
  final int bienesPendientes;
  final int bienesPerdidos;
  final int importeDescuentos;
  final int valorComprometido;
  final int decisionesAutorizadas;

  int get bienesEnRiesgo => bienesPendientes + bienesPerdidos;
}

/// Qué decidió un autorizador administrativo.
class ActividadAutorizador {
  const ActividadAutorizador({
    required this.empleadoId,
    required this.nombre,
    required this.decisiones,
    required this.decisionesSinCobro,
    required this.importeInvolucrado,
  });

  final String empleadoId;
  final String nombre;
  final int decisiones;

  /// Cuántas de esas decisiones renunciaron a cobrar.
  final int decisionesSinCobro;

  /// Valor aproximado de los bienes involucrados en sus decisiones.
  /// Sólo suma lo que tiene costo conocido.
  final int importeInvolucrado;
}

/// Un punto de la serie mensual de bajas.
class PuntoBajasMes {
  const PuntoBajasMes({
    required this.mes,
    required this.bajas,
    required this.pendientesGenerados,
    required this.importeDescuentos,
  });

  final DateTime mes;
  final int bajas;
  final int pendientesGenerados;
  final int importeDescuentos;
}

/// Tasa de recuperación, con su denominador explícito.
///
/// El denominador NO es "todos los bienes conciliados": excluye lo que
/// semánticamente nunca debió volver al almacén.
class TasaRecuperacion {
  const TasaRecuperacion({
    required this.recuperados,
    required this.debianRecuperarse,
    required this.excluidosTransferidos,
    required this.excluidosAutorizados,
  });

  /// Devueltos (incluye los que entraron como desecho: volvieron).
  final int recuperados;

  /// Recuperados + pendientes + perdidos.
  final int debianRecuperarse;

  /// Pasaron a otra persona: nunca debieron volver al almacén.
  final int excluidosTransferidos;

  /// Alguien autorizó que la persona se los quedara o no se solicitó
  /// devolución.
  final int excluidosAutorizados;

  /// `null` cuando el denominador es cero: sin bienes que recuperar no
  /// hay tasa, y 0 % diría que no se recuperó nada.
  double? get tasa => debianRecuperarse == 0 ? null : recuperados / debianRecuperarse;
}

/// Todo el análisis patrimonial de bajas, en una sola pasada.
class AnalisisPatrimonio {
  const AnalisisPatrimonio({
    required this.rango,
    required this.renglones,
    required this.bajasConciliadas,
    required this.recuperados,
    required this.pendientes,
    required this.perdidos,
    required this.transferidos,
    required this.unidadesPorEstatus,
    required this.importeDescuentos,
    required this.saldoDescuentos,
    required this.importeNoCobrado,
    required this.decisionesSinCobro,
    required this.valorPendiente,
    required this.valorPerdido,
    required this.bienesSinValorConocido,
    required this.impactoPorBaja,
    required this.autorizadores,
    required this.serieMensual,
    required this.tasaRecuperacion,
    required this.problemasPorServicio,
    required this.catalogo,
  });

  final RangoPeriodo rango;

  /// Renglones ya filtrados y ordenados — el universo del que salen
  /// TODOS los agregados de abajo.
  final List<RenglonPatrimonio> renglones;

  final int bajasConciliadas;
  final int recuperados;
  final int pendientes;
  final int perdidos;
  final int transferidos;

  /// Estatus físico actual de las unidades serializadas de estos
  /// renglones. Deliberadamente separado de [pendientes]: un bien
  /// pendiente de recuperación NO está en lavandería — sigue con la
  /// persona.
  final Map<String, int> unidadesPorEstatus;

  final int importeDescuentos;
  final int saldoDescuentos;

  /// Valor de los bienes en los que se decidió explícitamente no
  /// cobrar. Es el valor del bien, no un "importe condonado" — no
  /// existía una obligación que perdonar.
  final int importeNoCobrado;

  final int decisionesSinCobro;

  final int valorPendiente;
  final int valorPerdido;

  /// Cuántos bienes de los incluidos no tienen costo conocido. Si es
  /// mayor que cero, los valores de arriba son PARCIALES y la pantalla
  /// lo dice.
  final int bienesSinValorConocido;

  final List<ImpactoBaja> impactoPorBaja;
  final List<ActividadAutorizador> autorizadores;
  final List<PuntoBajasMes> serieMensual;
  final TasaRecuperacion tasaRecuperacion;

  /// En qué servicios se concentran los problemas. Incluye los
  /// renglones de "sin servicio resoluble" e "inconsistencia": la suma
  /// del ranking cuadra con los KPI porque nada se descarta.
  final List<ProblemaPorServicio> problemasPorServicio;

  /// Opciones de los filtros buscables, armadas sobre el periodo SIN
  /// filtrar — nunca se recortan por el resultado ya filtrado.
  final CatalogoFiltrosPatrimonio catalogo;

  int get aplicadoDescuentos => importeDescuentos - saldoDescuentos;

  bool get valorEsParcial => bienesSinValorConocido > 0;
}

/// Análisis patrimonial de bajas laborales.
///
/// **Proyecta, no reconstruye.** Cada dato sale de una FK real:
/// `ConciliacionBajaRenglon` apunta a la asignación (de Inventario o de
/// Vehículos), al autorizador, al receptor y a la obligación económica.
/// Nada se deduce de descripciones ni de prefijos de folio.
///
/// Las cuatro situaciones se mantienen separadas a propósito:
/// **pendiente** (sigue con la persona), **perdido** (resolución
/// declarada), **pendienteDesecho** (recuperado, esperando la baja
/// física) y **lavandería/reparación** (recuperado, fuera de
/// disponibilidad). Confundirlas era el riesgo principal de este
/// reporte.
///
/// Sin N+1: once consultas de universo/lote y todo lo demás resuelto en
/// memoria contra mapas.
class ObtenerAnalisisPatrimonioUseCase {
  ObtenerAnalisisPatrimonioUseCase(
    this._conciliacionRepository,
    this._asignacionRepository,
    this._asignacionVehiculoRepository,
    this._inventarioRepository,
    this._articuloRepository,
    this._vehiculoRepository,
    this._empleadoRepository,
    this._descuentoRepository,
    this._asignacionServicioRepository,
    this._servicioRepository,
    this._puestoRepository,
  );

  final ConciliacionBajaRepository _conciliacionRepository;
  final AsignacionRepository _asignacionRepository;
  final AsignacionVehiculoRepository _asignacionVehiculoRepository;
  final InventarioRepository _inventarioRepository;
  final ArticuloRepository _articuloRepository;
  final VehiculoRepository _vehiculoRepository;
  final EmpleadoRepository _empleadoRepository;
  final DescuentoProgramadoRepository _descuentoRepository;
  final AsignacionServicioRepository _asignacionServicioRepository;
  final ServicioRepository _servicioRepository;
  final PuestoRepository _puestoRepository;

  /// Cuántas bajas se listan por nombre en el ranking antes de agrupar.
  static const topImpacto = 6;

  Future<AnalisisPatrimonio> ejecutar({
    required RangoPeriodo rango,
    FiltroPatrimonio filtro = const FiltroPatrimonio(),
  }) async {
    final desde = DateTime(rango.inicio.year, rango.inicio.month, rango.inicio.day);
    final hasta = DateTime(rango.fin.year, rango.fin.month, rango.fin.day, 23, 59, 59, 999);

    final conciliaciones = await _conciliacionRepository.listar(desde: desde, hasta: hasta);
    final renglonesPorConciliacion =
        await _conciliacionRepository.listarRenglonesPorConciliaciones(conciliaciones.map((c) => c.id));

    final todosLosRenglones = [for (final lista in renglonesPorConciliacion.values) ...lista];

    // --- Lotes ---
    final asignaciones = {
      for (final a in await _asignacionRepository
          .listarPorIds([for (final r in todosLosRenglones) if (r.asignacionId != null) r.asignacionId!]))
        a.id: a,
    };
    final asignacionesVehiculo = await _asignacionVehiculoRepository
        .listarPorIds([for (final r in todosLosRenglones) if (r.asignacionVehiculoId != null) r.asignacionVehiculoId!]);

    final articulos = {for (final a in await _articuloRepository.listar(soloActivos: false)) a.id: a};
    final unidades = {for (final u in await _inventarioRepository.listarTodasUnidades()) u.id: u};
    final vehiculos = {for (final v in await _vehiculoRepository.listar(soloActivos: false)) v.id: v};
    final empleados = {for (final e in await _empleadoRepository.listarParaReporte()) e.id: e};
    final descuentos = {for (final d in await _descuentoRepository.listarTodos()) d.id: d};
    // Valuación en dos consultas fijas: por artículo y por variante.
    //
    // Un artículo con tallas no tiene costo a nivel de artículo —una
    // talla puede costar seis veces otra—, así que para esos bienes se
    // pregunta por la VARIANTE REAL que el resguardo conservó. No hay
    // promedio global de rescate: si la variante no se puede resolver,
    // el valor queda desconocido.
    final costoPorArticulo =
        await _inventarioRepository.calcularCostoPromedioPorArticulo(asignaciones.values.map((a) => a.articuloId));
    final costoPorVariante = await _inventarioRepository
        .calcularCostoPromedioPorVariante(asignaciones.values.map((a) => a.varianteId).whereType<String>());
    // En cuántas exhibiciones se está recuperando cada obligación —
    // una sola consulta agregada, nunca una por descuento.
    final cuotasPorDescuento = await _descuentoRepository.contarCuotasPorDescuento(
      todosLosRenglones.map((r) => r.descuentoProgramadoId).whereType<String>(),
    );
    // Adscripción histórica: TODO el historial de servicio de los ex
    // empleados de estas bajas, en una consulta, para resolver por
    // vigencia en memoria.
    final asignacionesServicio =
        await _asignacionServicioRepository.listarPorEmpleados(conciliaciones.map((c) => c.empleadoId));
    final servicios = {for (final s in await _servicioRepository.listar()) s.servicio.id: s};
    // Incluye archivados: un puesto puede haberse archivado después de
    // que la persona se fue, y aun así hay que poder nombrarlo.
    final puestos = {for (final p in await _puestoRepository.listarTodos()) p.id: p.nombre};

    final conciliacionPorId = {for (final c in conciliaciones) c.id: c};

    // Una resolución por BAJA, no por renglón: todos los bienes de una
    // misma conciliación comparten fecha y persona.
    final servicioPorConciliacion = {
      for (final c in conciliaciones)
        c.id: _resolverServicioHistorico(
          asignaciones: asignacionesServicio[c.empleadoId] ?? const [],
          fechaBaja: c.fechaBaja,
          servicios: servicios,
        ),
    };

    // --- Proyección ---
    final proyectados = <RenglonPatrimonio>[];
    for (final renglon in todosLosRenglones) {
      final conciliacion = conciliacionPorId[renglon.conciliacionBajaId];
      if (conciliacion == null) continue;

      final esVehiculo = renglon.asignacionVehiculoId != null;
      final asignacion = renglon.asignacionId == null ? null : asignaciones[renglon.asignacionId];
      final asignacionVehiculo =
          renglon.asignacionVehiculoId == null ? null : asignacionesVehiculo[renglon.asignacionVehiculoId];
      final unidad = asignacion?.unidadId == null ? null : unidades[asignacion!.unidadId];

      proyectados.add(RenglonPatrimonio(
        renglon: renglon,
        conciliacion: conciliacion,
        empleadoNombre: empleados[conciliacion.empleadoId]?.nombreCompleto ?? conciliacion.empleadoId,
        fechaBaja: conciliacion.fechaBaja,
        tipo: esVehiculo ? TipoBienConciliado.vehiculo : TipoBienConciliado.inventario,
        bienDescripcion: _describirBien(
          esVehiculo: esVehiculo,
          asignacion: asignacion,
          asignacionVehiculo: asignacionVehiculo,
          articulos: articulos,
          unidades: unidades,
          vehiculos: vehiculos,
        ),
        resolucion: ResolucionResguardoBaja.values.byName(renglon.resolucion),
        motivoNoEntrega: renglon.motivoNoEntrega == null
            ? null
            : MotivoNoEntregaResguardo.values.byName(renglon.motivoNoEntrega!),
        destino: renglon.destino == null ? null : DestinoDevolucionResguardo.values.byName(renglon.destino!),
        condicion:
            renglon.condicion == null ? null : CondicionDevolucionResguardo.values.byName(renglon.condicion!),
        estatusUnidad: unidad?.estatus,
        // La marca REAL, en la asignación que corresponda — jamás
        // deducida de la resolución.
        pendienteDesde: esVehiculo
            ? asignacionVehiculo?.pendienteRecuperacionDesde
            : asignacion?.pendienteRecuperacionDesde,
        fechaCompromiso: renglon.fechaCompromiso,
        autorizadorNombre: renglon.autorizadorEmpleadoId == null
            ? null
            : empleados[renglon.autorizadorEmpleadoId]?.nombreCompleto,
        receptorNombre:
            renglon.receptorEmpleadoId == null ? null : empleados[renglon.receptorEmpleadoId]?.nombreCompleto,
        descuento: renglon.descuentoProgramadoId == null ? null : descuentos[renglon.descuentoProgramadoId],
        cuotasDescuento:
            renglon.descuentoProgramadoId == null ? 0 : (cuotasPorDescuento[renglon.descuentoProgramadoId] ?? 0),
        // La talla que el resguardo REALMENTE entregó manda sobre el
        // artículo. `varianteId`/`unidadId` son excluyentes por CHECK,
        // así que un bien serializado nunca trae variante: si además su
        // artículo maneja tallas, el costo queda desconocido en vez de
        // inventar una.
        valorAproximado: asignacion == null
            ? null
            : (asignacion.varianteId != null
                ? costoPorVariante[asignacion.varianteId]
                : costoPorArticulo[asignacion.articuloId]),
        servicioHistorico: servicioPorConciliacion[conciliacion.id] ?? const ServicioHistorico.sinAsignacion(),
      ));
    }

    // El catálogo se arma ANTES de filtrar, a propósito: si saliera del
    // resultado filtrado, elegir a una persona vaciaría la lista y el
    // filtro no se podría volver a cambiar sin limpiarlo.
    final catalogo = _catalogo(proyectados: proyectados, empleados: empleados, puestos: puestos, servicios: servicios);

    final filtrados = [for (final p in proyectados) if (_pasaFiltro(p, filtro)) p]
      ..sort(_masUrgentePrimero);

    return _agregar(rango: rango, renglones: filtrados, catalogo: catalogo);
  }

  static bool _pasaFiltro(RenglonPatrimonio p, FiltroPatrimonio filtro) {
    if (filtro.empleadoId != null && p.conciliacion.empleadoId != filtro.empleadoId) return false;
    if (filtro.autorizadorId != null && p.renglon.autorizadorEmpleadoId != filtro.autorizadorId) return false;
    // Sólo casa lo RESUELTO: una baja sin servicio resoluble jamás cae
    // dentro de un servicio concreto por descarte.
    if (filtro.servicioId != null && p.servicioHistorico.servicioId != filtro.servicioId) return false;
    if (filtro.tipoBien != null && p.tipo != filtro.tipoBien) return false;
    if (filtro.resolucion != null && p.resolucion != filtro.resolucion) return false;
    if (filtro.motivoNoEntrega != null && p.motivoNoEntrega != filtro.motivoNoEntrega) return false;
    if (filtro.soloPendientes && !p.estaPendiente) return false;
    if (filtro.conDescuento != null && (p.descuento != null) != filtro.conDescuento) return false;
    return true;
  }

  /// Resuelve el Servicio de una baja **sólo** por vigencia real.
  ///
  /// Reglas, sin excepciones: se compara por día (una baja fechada a las
  /// 10:00 del mismo día en que se cerró la asignación sigue estando
  /// dentro), `fechaTermino == null` significa vigente, y el resultado
  /// es uno de tres — nunca un servicio elegido a dedo.
  ///
  /// La conciliación cierra la `AsignacionServicio` con
  /// `fechaTermino = fechaBaja`, así que el límite superior tiene que
  /// ser inclusivo o toda baja quedaría "sin servicio".
  static ServicioHistorico _resolverServicioHistorico({
    required List<AsignacionServicioData> asignaciones,
    required DateTime fechaBaja,
    required Map<String, ServicioListItem> servicios,
  }) {
    final dia = DateTime(fechaBaja.year, fechaBaja.month, fechaBaja.day);

    final vigentes = asignaciones.where((a) {
      final inicio = DateTime(a.fechaInicio.year, a.fechaInicio.month, a.fechaInicio.day);
      if (dia.isBefore(inicio)) return false;
      final termino = a.fechaTermino;
      if (termino == null) return true;
      final fin = DateTime(termino.year, termino.month, termino.day);
      return !dia.isAfter(fin);
    }).toList();

    if (vigentes.isEmpty) return const ServicioHistorico.sinAsignacion();
    // Más de una vigencia cubriendo el mismo día es un dato roto: se
    // reporta como tal en vez de quedarse con la primera.
    if (vigentes.length > 1) return ServicioHistorico.inconsistente(vigentes.length);

    final servicio = servicios[vigentes.single.servicioId];
    // La FK existe pero el Servicio no se pudo leer: tampoco se inventa
    // un nombre — se trata como no resoluble.
    if (servicio == null) return const ServicioHistorico.sinAsignacion();
    return ServicioHistorico.resuelto(servicioId: servicio.servicio.id, nombre: servicio.servicio.nombre);
  }

  /// Catálogos de los filtros buscables, sobre el universo SIN filtrar.
  static CatalogoFiltrosPatrimonio _catalogo({
    required List<RenglonPatrimonio> proyectados,
    required Map<String, EmpleadoReporteRow> empleados,
    required Map<String, String> puestos,
    required Map<String, ServicioListItem> servicios,
  }) {
    final personas = <String, OpcionPersonaFiltro>{};
    final autorizadores = <String, OpcionPersonaFiltro>{};
    final serviciosVistos = <String, OpcionServicioFiltro>{};

    OpcionPersonaFiltro? opcionDe(String? empleadoId) {
      if (empleadoId == null) return null;
      final empleado = empleados[empleadoId];
      if (empleado == null) return null;
      return OpcionPersonaFiltro(
        empleadoId: empleadoId,
        nombre: empleado.nombreCompleto,
        puesto: empleado.puestoId == null ? null : puestos[empleado.puestoId],
      );
    }

    for (final p in proyectados) {
      final persona = opcionDe(p.conciliacion.empleadoId);
      if (persona != null) personas[persona.empleadoId] = persona;

      final autorizador = opcionDe(p.renglon.autorizadorEmpleadoId);
      if (autorizador != null) autorizadores[autorizador.empleadoId] = autorizador;

      final servicioId = p.servicioHistorico.servicioId;
      if (servicioId != null) {
        final servicio = servicios[servicioId];
        serviciosVistos[servicioId] = OpcionServicioFiltro(
          servicioId: servicioId,
          nombre: p.servicioHistorico.nombre ?? servicioId,
          cliente: servicio?.clienteNombre,
        );
      }
    }

    int porNombre(dynamic a, dynamic b) => (a.nombre as String).toLowerCase().compareTo((b.nombre as String).toLowerCase());

    return CatalogoFiltrosPatrimonio(
      empleados: personas.values.toList()..sort(porNombre),
      autorizadores: autorizadores.values.toList()..sort(porNombre),
      servicios: serviciosVistos.values.toList()..sort(porNombre),
    );
  }

  /// Lo pendiente primero y, dentro, lo más antiguo: es el orden con el
  /// que se persigue una recuperación.
  static int _masUrgentePrimero(RenglonPatrimonio a, RenglonPatrimonio b) {
    if (a.estaPendiente != b.estaPendiente) return a.estaPendiente ? -1 : 1;
    final porPendiente = (a.pendienteDesde ?? a.fechaBaja).compareTo(b.pendienteDesde ?? b.fechaBaja);
    if (porPendiente != 0) return porPendiente;
    return b.fechaBaja.compareTo(a.fechaBaja);
  }

  String _describirBien({
    required bool esVehiculo,
    required AsignacionData? asignacion,
    required AsignacionVehiculoData? asignacionVehiculo,
    required Map<String, ArticuloData> articulos,
    required Map<String, ArticuloUnidadData> unidades,
    required Map<String, VehiculoData> vehiculos,
  }) {
    if (esVehiculo) {
      final vehiculo = asignacionVehiculo == null ? null : vehiculos[asignacionVehiculo.vehiculoId];
      if (vehiculo == null) return '—';
      final placas = vehiculo.placas;
      return placas == null
          ? '${vehiculo.marca} ${vehiculo.modelo}'
          : '${vehiculo.marca} ${vehiculo.modelo} · $placas';
    }
    if (asignacion == null) return '—';
    final articulo = articulos[asignacion.articuloId];
    final unidad = asignacion.unidadId == null ? null : unidades[asignacion.unidadId];
    final nombre = articulo?.nombre ?? asignacion.articuloId;
    return unidad == null ? nombre : '$nombre · ${unidad.codigo}';
  }

  AnalisisPatrimonio _agregar({
    required RangoPeriodo rango,
    required List<RenglonPatrimonio> renglones,
    required CatalogoFiltrosPatrimonio catalogo,
  }) {
    var recuperados = 0;
    var pendientes = 0;
    var perdidos = 0;
    var transferidos = 0;
    var importeDescuentos = 0;
    var saldoDescuentos = 0;
    var importeNoCobrado = 0;
    var decisionesSinCobro = 0;
    var valorPendiente = 0;
    var valorPerdido = 0;
    var sinValor = 0;
    var excluidosTransferidos = 0;
    var excluidosAutorizados = 0;

    final bajas = <String>{};
    final unidadesPorEstatus = <String, int>{};
    final impacto = <String, ImpactoBaja>{};
    final decisionesPorAutorizador = <String, int>{};
    final sinCobroPorAutorizador = <String, int>{};
    final importePorAutorizador = <String, int>{};
    final nombrePorAutorizador = <String, String>{};
    final serie = <DateTime, PuntoBajasMes>{};
    final bajasContadasPorMes = <DateTime, Set<String>>{};
    final porServicio = <String, ProblemaPorServicio>{};
    final bajasPorServicio = <String, Set<String>>{};

    for (final r in renglones) {
      bajas.add(r.conciliacion.id);

      if (r.estaPendiente) pendientes++;
      if (r.sePerdio) perdidos++;
      if (r.fueRecuperado) recuperados++;
      if (r.fueTransferido) {
        transferidos++;
        excluidosTransferidos++;
      }
      if (r.autorizadoSinRecuperar) excluidosAutorizados++;

      // Estado físico SÓLO de lo que volvió (§17). Un bien pendiente
      // sigue con la persona y su unidad conserva el estatus `asignado`:
      // contarlo aquí lo disfrazaría de bien en resguardo, y un perdido
      // aparecería como una ubicación más. Los dos tienen su propio KPI.
      final estatus = r.fueRecuperado ? r.estatusUnidad : null;
      if (estatus != null) unidadesPorEstatus[estatus] = (unidadesPorEstatus[estatus] ?? 0) + 1;

      importeDescuentos += r.importeDescuento;
      saldoDescuentos += r.saldoDescuento;

      if (r.noCobroAutorizado) {
        decisionesSinCobro++;
        // Es el VALOR DEL BIEN, no un importe condonado: nunca existió
        // una obligación que perdonar.
        importeNoCobrado += r.valorAproximado ?? 0;
      }

      final valor = r.valorAproximado;
      if (valor == null && r.tipo == TipoBienConciliado.inventario) {
        sinValor++;
      } else if (valor != null) {
        if (r.estaPendiente) valorPendiente += valor;
        if (r.sePerdio) valorPerdido += valor;
      }

      // Ranking por baja.
      final anterior = impacto[r.conciliacion.empleadoId];
      impacto[r.conciliacion.empleadoId] = ImpactoBaja(
        empleadoId: r.conciliacion.empleadoId,
        nombre: r.empleadoNombre,
        fechaBaja: r.fechaBaja,
        bienesPendientes: (anterior?.bienesPendientes ?? 0) + (r.estaPendiente ? 1 : 0),
        bienesPerdidos: (anterior?.bienesPerdidos ?? 0) + (r.sePerdio ? 1 : 0),
        importeDescuentos: (anterior?.importeDescuentos ?? 0) + r.importeDescuento,
        valorComprometido:
            (anterior?.valorComprometido ?? 0) + ((r.estaPendiente || r.sePerdio) ? (r.valorAproximado ?? 0) : 0),
        decisionesAutorizadas:
            (anterior?.decisionesAutorizadas ?? 0) + (r.renglon.autorizadorEmpleadoId != null ? 1 : 0),
      );

      // Autorizadores — agrupados por empleadoId, nunca por nombre.
      final autorizadorId = r.renglon.autorizadorEmpleadoId;
      if (autorizadorId != null) {
        decisionesPorAutorizador[autorizadorId] = (decisionesPorAutorizador[autorizadorId] ?? 0) + 1;
        if (r.noCobroAutorizado || r.autorizadoSinRecuperar) {
          sinCobroPorAutorizador[autorizadorId] = (sinCobroPorAutorizador[autorizadorId] ?? 0) + 1;
        }
        importePorAutorizador[autorizadorId] = (importePorAutorizador[autorizadorId] ?? 0) + (r.valorAproximado ?? 0);
        nombrePorAutorizador[autorizadorId] = r.autorizadorNombre ?? autorizadorId;
      }

      // Concentración por Servicio histórico. Lo no resoluble no se
      // reparte entre los servicios reales: va a su propio renglón.
      final servicioHistorico = r.servicioHistorico;
      final claveServicio = servicioHistorico.servicioId ?? servicioHistorico.estado.name;
      final bajasDelServicio = bajasPorServicio.putIfAbsent(claveServicio, () => <String>{})
        ..add(r.conciliacion.id);
      final servicioPrevio = porServicio[claveServicio];
      porServicio[claveServicio] = ProblemaPorServicio(
        estado: servicioHistorico.estado,
        servicioId: servicioHistorico.servicioId,
        nombre: servicioHistorico.nombre,
        bajas: bajasDelServicio.length,
        pendientes: (servicioPrevio?.pendientes ?? 0) + (r.estaPendiente ? 1 : 0),
        perdidos: (servicioPrevio?.perdidos ?? 0) + (r.sePerdio ? 1 : 0),
        importeDescuentos: (servicioPrevio?.importeDescuentos ?? 0) + r.importeDescuento,
        decisionesAutorizadas:
            (servicioPrevio?.decisionesAutorizadas ?? 0) + (r.renglon.autorizadorEmpleadoId != null ? 1 : 0),
        decisionesSinCobro: (servicioPrevio?.decisionesSinCobro ?? 0) + (r.noCobroAutorizado ? 1 : 0),
      );

      // Serie mensual, sobre fechas REALES de baja.
      final mes = DateTime(r.fechaBaja.year, r.fechaBaja.month);
      final bajasDelMes = bajasContadasPorMes.putIfAbsent(mes, () => <String>{})..add(r.conciliacion.id);
      final punto = serie[mes];
      serie[mes] = PuntoBajasMes(
        mes: mes,
        bajas: bajasDelMes.length,
        pendientesGenerados: (punto?.pendientesGenerados ?? 0) + (r.estaPendiente ? 1 : 0),
        importeDescuentos: (punto?.importeDescuentos ?? 0) + r.importeDescuento,
      );
    }

    final ranking = impacto.values.toList()
      ..sort((a, b) {
        final porRiesgo = b.bienesEnRiesgo.compareTo(a.bienesEnRiesgo);
        if (porRiesgo != 0) return porRiesgo;
        return b.importeDescuentos.compareTo(a.importeDescuentos);
      });

    final autorizadores = [
      for (final id in decisionesPorAutorizador.keys)
        ActividadAutorizador(
          empleadoId: id,
          nombre: nombrePorAutorizador[id] ?? id,
          decisiones: decisionesPorAutorizador[id]!,
          decisionesSinCobro: sinCobroPorAutorizador[id] ?? 0,
          importeInvolucrado: importePorAutorizador[id] ?? 0,
        ),
    ]..sort((a, b) => b.decisiones.compareTo(a.decisiones));

    final serieOrdenada = serie.values.toList()..sort((a, b) => a.mes.compareTo(b.mes));

    // Los servicios reales primero, por concentración de problemas; los
    // dos renglones de dato no resoluble siempre al final, para que no
    // encabecen un ranking que no describen.
    final rankingServicios = porServicio.values.toList()
      ..sort((a, b) {
        final aResuelto = a.estado == EstadoServicioHistorico.resuelto;
        final bResuelto = b.estado == EstadoServicioHistorico.resuelto;
        if (aResuelto != bResuelto) return aResuelto ? -1 : 1;
        final porRiesgo = b.bienesEnRiesgo.compareTo(a.bienesEnRiesgo);
        if (porRiesgo != 0) return porRiesgo;
        final porImporte = b.importeDescuentos.compareTo(a.importeDescuentos);
        if (porImporte != 0) return porImporte;
        return b.bajas.compareTo(a.bajas);
      });

    return AnalisisPatrimonio(
      rango: rango,
      renglones: renglones,
      bajasConciliadas: bajas.length,
      recuperados: recuperados,
      pendientes: pendientes,
      perdidos: perdidos,
      transferidos: transferidos,
      unidadesPorEstatus: unidadesPorEstatus,
      importeDescuentos: importeDescuentos,
      saldoDescuentos: saldoDescuentos,
      importeNoCobrado: importeNoCobrado,
      decisionesSinCobro: decisionesSinCobro,
      valorPendiente: valorPendiente,
      valorPerdido: valorPerdido,
      bienesSinValorConocido: sinValor,
      impactoPorBaja: ranking,
      autorizadores: autorizadores,
      serieMensual: serieOrdenada,
      problemasPorServicio: rankingServicios,
      catalogo: catalogo,
      tasaRecuperacion: TasaRecuperacion(
        recuperados: recuperados,
        // El denominador es lo que RISEG esperaba de vuelta: lo que
        // volvió, lo que sigue pendiente y lo que se perdió. Quedan
        // fuera los transferidos (pasaron a otra persona, nunca debieron
        // volver al almacén) y los autorizados a conservar / sin
        // solicitud de devolución.
        debianRecuperarse: recuperados + pendientes + perdidos,
        excluidosTransferidos: excluidosTransferidos,
        excluidosAutorizados: excluidosAutorizados,
      ),
    );
  }
}
