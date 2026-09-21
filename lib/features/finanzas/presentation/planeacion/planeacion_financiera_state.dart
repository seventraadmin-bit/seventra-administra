import 'package:riseg_one/features/finanzas/domain/usecases/calcular_serie_disponibilidad_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/obtener_proyeccion_caja_usecase.dart';

/// Periodo de Planeación financiera (Etapa 19D) — 4 formas de elegir
/// el mes visible del calendario; `personalizado` guarda el mes
/// elegido en `_mesVisible` directamente (nunca un rango de días
/// libre: toda esta pantalla gira alrededor de un calendario mensual).
enum PeriodoPlaneacion { mesAnterior, esteMes, mesSiguiente, personalizado }

class PlaneacionFinancieraState {
  const PlaneacionFinancieraState({
    this.cargando = true,
    this.errorCarga,
    this.periodo = PeriodoPlaneacion.esteMes,
    DateTime? mesVisible,
    this.diaSeleccionado,
    this.proyeccionCaja = const ProyeccionCaja(cuentasConfiguradas: false, saldoActual: 0, compromisos: [], pendientesVencidos: []),
    this.serie = const [],
  }) : _mesVisible = mesVisible;

  final bool cargando;
  final String? errorCarga;
  final PeriodoPlaneacion periodo;
  final DateTime? _mesVisible;

  /// Primer día del mes que el calendario muestra — mismo criterio que
  /// `ResumenFinancieroState.rangoInicio`: se resuelve contra
  /// `DateTime.now()` solo cuando nadie lo fijó todavía.
  DateTime get mesVisible {
    final hoy = DateTime.now();
    return _mesVisible ?? DateTime(hoy.year, hoy.month, 1);
  }

  /// Día seleccionado en el calendario — el detalle del día lo lee de
  /// aquí. `null` únicamente antes de la primera carga.
  final DateTime? diaSeleccionado;

  /// Única fuente de compromisos/posición de caja — la misma que
  /// consume el Resumen financiero (`ObtenerProyeccionCajaUseCase`),
  /// nunca una segunda lógica de proyección.
  final ProyeccionCaja proyeccionCaja;

  /// Serie diaria ya calculada (`calcularSerieDisponibilidad`) para el
  /// rango `hoy..hasta` real de este periodo — ver el doc comment del
  /// controlador para cómo se resuelve `hasta` cuando el mes visible
  /// queda antes o después de hoy.
  final List<PuntoDisponibilidadDiaria> serie;

  List<ResumenSemanal> get resumenSemanal => agruparPorSemanaCalendario(serie);

  PuntoDisponibilidadDiaria? get puntoMinimo => encontrarMinimo(serie);

  PlaneacionFinancieraState copyWith({
    bool? cargando,
    String? errorCarga,
    PeriodoPlaneacion? periodo,
    DateTime? mesVisible,
    DateTime? diaSeleccionado,
    bool limpiarDiaSeleccionado = false,
    ProyeccionCaja? proyeccionCaja,
    List<PuntoDisponibilidadDiaria>? serie,
  }) {
    return PlaneacionFinancieraState(
      cargando: cargando ?? this.cargando,
      errorCarga: errorCarga,
      periodo: periodo ?? this.periodo,
      mesVisible: mesVisible ?? _mesVisible,
      diaSeleccionado: limpiarDiaSeleccionado ? null : (diaSeleccionado ?? this.diaSeleccionado),
      proyeccionCaja: proyeccionCaja ?? this.proyeccionCaja,
      serie: serie ?? this.serie,
    );
  }
}
