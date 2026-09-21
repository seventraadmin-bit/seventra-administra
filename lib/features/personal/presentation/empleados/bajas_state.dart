import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/servicio_repository.dart' show ServicioListItem;
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart' show MotivoBajaEmpleado;
import 'package:riseg_one/features/personal/domain/usecases/analitica_bajas.dart';
import 'package:riseg_one/features/personal/domain/usecases/construir_eventos_baja.dart';

enum OrdenBajas { fechaBajaDesc, permanencia, empleado, servicio }

/// Estado de la vista "BAJAS DE PERSONAL" (Etapa 15) — `eventos`
/// siempre contiene TODOS los eventos de baja de la compañía
/// (`BajaEvento`, uno por periodo laboral terminado); el periodo
/// seleccionado y los filtros de tabla se aplican como *getters*
/// derivados, nunca recargando de la BD (misma consulta cara una sola
/// vez, filtrado barato en memoria).
class BajasState {
  const BajasState({
    this.cargando = true,
    this.eventos = const [],
    this.puestos = const [],
    this.servicios = const [],
    this.periodo = PeriodoAnaliticaBajas.esteMes,
    this.inicioPersonalizado,
    this.finPersonalizado,
    this.texto,
    this.servicioFiltro,
    this.puestoFiltro,
    this.motivoFiltro,
    this.segmentoFiltro,
    this.orden = OrdenBajas.fechaBajaDesc,
    this.fotografiaPathPorEmpleadoId = const {},
    this.errorCarga,
  });

  final bool cargando;
  final List<BajaEvento> eventos;
  final List<PuestoData> puestos;
  final List<ServicioListItem> servicios;

  /// Fotografía VIGENTE del Empleado por `empleadoId` (Etapa 16,
  /// evolución visual) — identidad visual de la persona hoy; nunca
  /// representa el puesto/servicio/turno de un periodo laboral pasado
  /// (esos siguen viniendo exclusivamente del snapshot de `BajaEvento`).
  final Map<String, String> fotografiaPathPorEmpleadoId;

  final PeriodoAnaliticaBajas periodo;
  final DateTime? inicioPersonalizado;
  final DateTime? finPersonalizado;

  final String? texto;
  final String? servicioFiltro;
  final String? puestoFiltro;
  final MotivoBajaEmpleado? motivoFiltro;
  final SegmentoPermanencia? segmentoFiltro;
  final OrdenBajas orden;
  final String? errorCarga;

  /// Etapa 15, rediseño visual — solo para que "Limpiar filtros" adquiera
  /// protagonismo cuando de verdad hay algo que limpiar (filtros de
  /// tabla; el periodo tiene su propio selector, siempre visible).
  bool get hayFiltrosActivos =>
      (texto != null && texto!.trim().isNotEmpty) ||
      servicioFiltro != null ||
      puestoFiltro != null ||
      motivoFiltro != null ||
      segmentoFiltro != null;

  ({DateTime inicio, DateTime fin}) get rango =>
      resolverRangoPeriodoBajas(periodo, inicioPersonalizado: inicioPersonalizado, finPersonalizado: finPersonalizado);

  /// Eventos dentro del periodo seleccionado — base de KPIs, gráficas y
  /// de la tabla (Resolución: la tabla respeta el mismo periodo que el
  /// resto de la pantalla, mismo criterio que `ReportesFiltroBar` en el
  /// resto de RISEG ONE — un solo rango vigente para toda la vista, en
  /// vez de que la tabla "vea" datos que las tarjetas no reflejan).
  List<BajaEvento> get eventosDelPeriodo {
    final r = rango;
    return filtrarEventosPorRango(eventos, r.inicio, r.fin);
  }

  /// Eventos del periodo + filtros de tabla — nunca afecta KPIs ni
  /// gráficas, solo la tabla de abajo.
  List<BajaEvento> get filasTabla {
    final textoNormalizado = texto?.trim().toLowerCase();
    var filas = eventosDelPeriodo.where((e) {
      if (textoNormalizado != null && textoNormalizado.isNotEmpty) {
        final coincide = e.nombreCompleto.toLowerCase().contains(textoNormalizado) || e.numeroEmpleado.toString().contains(textoNormalizado);
        if (!coincide) return false;
      }
      if (servicioFiltro != null && e.servicioNombre != servicioFiltro) return false;
      if (puestoFiltro != null && e.puestoNombre != puestoFiltro) return false;
      if (motivoFiltro != null && e.motivoBaja != motivoFiltro!.name) return false;
      if (segmentoFiltro != null && segmentoPermanenciaDeEvento(e) != segmentoFiltro) return false;
      return true;
    }).toList();

    filas = switch (orden) {
      OrdenBajas.fechaBajaDesc => filas..sort((a, b) => b.fechaBaja.compareTo(a.fechaBaja)),
      OrdenBajas.permanencia => filas..sort((a, b) => b.permanenciaDias.compareTo(a.permanenciaDias)),
      OrdenBajas.empleado => filas..sort((a, b) => a.nombreCompleto.toLowerCase().compareTo(b.nombreCompleto.toLowerCase())),
      OrdenBajas.servicio => filas..sort((a, b) => (a.servicioNombre ?? '').toLowerCase().compareTo((b.servicioNombre ?? '').toLowerCase())),
    };
    return filas;
  }

  BajasState copyWith({
    bool? cargando,
    List<BajaEvento>? eventos,
    List<PuestoData>? puestos,
    List<ServicioListItem>? servicios,
    PeriodoAnaliticaBajas? periodo,
    DateTime? inicioPersonalizado,
    DateTime? finPersonalizado,
    String? texto,
    String? servicioFiltro,
    String? puestoFiltro,
    MotivoBajaEmpleado? motivoFiltro,
    SegmentoPermanencia? segmentoFiltro,
    OrdenBajas? orden,
    Map<String, String>? fotografiaPathPorEmpleadoId,
    bool limpiarTexto = false,
    bool limpiarServicioFiltro = false,
    bool limpiarPuestoFiltro = false,
    bool limpiarMotivoFiltro = false,
    bool limpiarSegmentoFiltro = false,
    String? errorCarga,
  }) {
    return BajasState(
      cargando: cargando ?? this.cargando,
      eventos: eventos ?? this.eventos,
      puestos: puestos ?? this.puestos,
      servicios: servicios ?? this.servicios,
      periodo: periodo ?? this.periodo,
      inicioPersonalizado: inicioPersonalizado ?? this.inicioPersonalizado,
      finPersonalizado: finPersonalizado ?? this.finPersonalizado,
      texto: limpiarTexto ? null : (texto ?? this.texto),
      servicioFiltro: limpiarServicioFiltro ? null : (servicioFiltro ?? this.servicioFiltro),
      puestoFiltro: limpiarPuestoFiltro ? null : (puestoFiltro ?? this.puestoFiltro),
      motivoFiltro: limpiarMotivoFiltro ? null : (motivoFiltro ?? this.motivoFiltro),
      segmentoFiltro: limpiarSegmentoFiltro ? null : (segmentoFiltro ?? this.segmentoFiltro),
      orden: orden ?? this.orden,
      fotografiaPathPorEmpleadoId: fotografiaPathPorEmpleadoId ?? this.fotografiaPathPorEmpleadoId,
      errorCarga: errorCarga,
    );
  }
}
