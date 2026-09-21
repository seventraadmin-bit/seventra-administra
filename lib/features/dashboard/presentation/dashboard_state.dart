import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/personal/domain/plantilla_personal.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/obtener_credito_disponible_tarjetas_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/obtener_posicion_de_caja_usecase.dart';
import 'package:riseg_one/features/reportes/domain/usecases/obtener_resumen_general_usecase.dart';
import 'package:riseg_one/features/reportes/domain/usecases/obtener_resumen_inventario_usecase.dart';
import 'package:riseg_one/features/reportes/domain/usecases/obtener_resumen_nomina_usecase.dart';
import 'package:riseg_one/features/reportes/domain/usecases/obtener_resumen_personal_usecase.dart';
import 'package:riseg_one/features/reportes/domain/usecases/obtener_resumen_telefonia_usecase.dart';
import 'package:riseg_one/features/reportes/domain/usecases/obtener_resumen_vehiculos_usecase.dart';
import 'package:riseg_one/features/tiempos_extra/domain/usecases/obtener_resumen_tiempos_extra_usecase.dart';

import '../domain/periodo_dashboard.dart';
import '../domain/usecases/obtener_actividad_reciente_usecase.dart';
import '../domain/usecases/obtener_alertas_dashboard_usecase.dart';
import '../domain/usecases/obtener_cobertura_operativa_usecase.dart';
import '../domain/usecases/obtener_resumen_cobranza_usecase.dart';
import '../domain/usecases/obtener_serie_financiera_usecase.dart';

/// Resumen de Personal del Dashboard (Parte M del rediseño) — distingue
/// EXPLÍCITAMENTE "sin asignar" de "vacante": un Empleado sin destino y
/// una vacante que pide un perfil distinto son hechos independientes,
/// nunca el mismo número (Parte M: "no mezclarlos").
///
/// **Bug real corregido (Etapa "Plantilla operativa vs. administrativa").**
/// Esta clase calculaba antes `asignados / totalActivos`, donde el
/// numerador eran solo los empleados con Servicio y el denominador
/// TODOS los activos. Un administrativo correctamente adscrito a su
/// Sucursal entraba al denominador sin poder entrar jamás al numerador,
/// así que el indicador no podía llegar a 100% ni con cero operativos
/// sin asignar (caso real: 15/16 = 93.75% ≈ 94%, más "1 sin asignar"
/// que en realidad estaba perfectamente asignado a Sucursal Toluca).
///
/// Ahora los conteos vienen ya resueltos de `PlantillaPersonalResumen`
/// (`ObtenerPlantillaPersonalUseCase`), la fuente de verdad única que
/// comparten Dashboard, Personal y Reportes — aquí no se clasifica
/// nada, solo se transporta.
///
/// **Semántica mezclada, explícita a propósito**: [operativa],
/// [administrativa], [sinAsignacion], [inconsistentes] y
/// [vacantesAbiertas] son SNAPSHOT (estado de hoy, ajenos al filtro de
/// periodo); [rotacionOperativa] y [promedioDiasCobertura] son de
/// PERIODO. La UI lo señala para que nadie lea una como la otra.
class PersonalOperativoDashboard {
  const PersonalOperativoDashboard({
    required this.totalActivos,
    required this.operativa,
    required this.administrativa,
    required this.sinAsignacion,
    required this.inconsistentes,
    required this.vacantesAbiertas,
    this.promedioDiasCobertura,
    this.rotacionOperativa,
  });

  /// Toda la empresa: operativos + administrativos + sin plantilla
  /// conocida + inconsistentes.
  final int totalActivos;

  final ConteoPlantilla operativa;
  final ConteoPlantilla administrativa;

  /// Activos sin Servicio ni Sucursal, de cualquier plantilla.
  final int sinAsignacion;

  /// Servicio Y Sucursal a la vez — se muestran, nunca se esconden
  /// para mejorar un porcentaje.
  final int inconsistentes;

  final int vacantesAbiertas;

  /// Promedio de días para cubrir una vacante. Métrica exclusivamente
  /// OPERATIVA por construcción: `VacanteOperativa` cuelga de un
  /// `servicioId`, así que un administrativo nunca la altera.
  final Duration? promedioDiasCobertura;

  /// Rotación del periodo seleccionado, solo de la plantilla operativa.
  /// `null` si no se pudo calcular (plantilla promedio 0).
  final double? rotacionOperativa;
}

/// Estado del Dashboard (Etapa 13, rediseño gerencial Etapa 15) — cada
/// `resumenXxx` es `null` cuando la sesión no tiene el permiso
/// `xxx.ver` correspondiente (nunca se calcula ni se consulta en ese
/// caso, guardia real en el controller). `alertas`/`actividad` sí se
/// calculan siempre — sus propios campos internos son `null` por
/// sección, mismo criterio.
///
/// [periodo] es la única fuente de verdad del rango seleccionado
/// (Parte B) — afecta `resumenGeneral`/`resumenNomina`/`resumenCobranza`
/// (cobranza usa `hoy`, no el periodo, para vencimientos — ver el
/// propio use case)/`actividad`, pero NUNCA `resumenCobertura` (estado
/// operativo actual, siempre a la fecha de hoy real, sin importar el
/// periodo elegido).
class DashboardState {
  const DashboardState({
    this.cargando = true,
    this.periodo,
    this.resumenGeneral,
    this.resumenPersonal,
    this.resumenNomina,
    this.resumenInventario,
    this.resumenVehiculos,
    this.resumenTelefonia,
    this.resumenTiemposExtra,
    this.resumenCobertura,
    this.resumenCobranza,
    this.posicionCaja,
    this.creditoDisponibleTarjetas,
    this.personalOperativo,
    this.proximaNomina,
    this.proximaNominaTotal,
    this.serieFinanciera,
    this.alertas,
    this.actividad,
    this.errorCarga,
  });

  final bool cargando;
  final PeriodoDashboard? periodo;

  final ResumenGeneralReportes? resumenGeneral;
  final ResumenPersonalReportes? resumenPersonal;
  final ResumenNominaReportes? resumenNomina;
  final ResumenInventarioReportes? resumenInventario;
  final ResumenVehiculosReportes? resumenVehiculos;
  final ResumenTelefoniaReportes? resumenTelefonia;
  final ResumenTiemposExtraDetalle? resumenTiemposExtra;

  final ResumenCoberturaOperativa? resumenCobertura;
  final ResumenCobranza? resumenCobranza;

  /// Saldo disponible de caja (Etapa 20, 5º KPI ejecutivo) — snapshot
  /// actual, nunca afectado por el periodo (mismo criterio que
  /// Cobertura). `null` sin permiso `finanzas.ver`; con permiso,
  /// `PosicionDeCaja.configurada == false` es un estado real (sin
  /// ninguna CuentaFinanciera activa), nunca `$0.00` disfrazado.
  final PosicionDeCaja? posicionCaja;

  /// Crédito disponible agregado de TDC (Etapa "Dashboard: posición
  /// financiera", 6º KPI ejecutivo) — snapshot actual, mismo criterio
  /// que `posicionCaja` (nunca afectado por el periodo). `null` sin
  /// permiso `finanzas.ver`; con permiso,
  /// `CreditoDisponibleTarjetas.hayTarjetas == false` es un estado real
  /// (sin ninguna TDC activa), nunca `$0.00` disfrazado. Deliberadamente
  /// NUNCA se suma con `posicionCaja` — caja y crédito son conceptos
  /// financieros distintos.
  final CreditoDisponibleTarjetas? creditoDisponibleTarjetas;

  final PersonalOperativoDashboard? personalOperativo;

  /// `null` cuando no hay ninguna Nómina `cerrada` pendiente de pago —
  /// nunca una Nómina `pagada` (Parte C.4).
  final NominaData? proximaNomina;
  final int? proximaNominaTotal;

  final List<PuntoSerieFinanciera>? serieFinanciera;

  final AlertasDashboard? alertas;
  final ActividadRecienteDashboard? actividad;

  final String? errorCarga;

  DashboardState copyWith({
    bool? cargando,
    PeriodoDashboard? periodo,
    ResumenGeneralReportes? resumenGeneral,
    ResumenPersonalReportes? resumenPersonal,
    ResumenNominaReportes? resumenNomina,
    ResumenInventarioReportes? resumenInventario,
    ResumenVehiculosReportes? resumenVehiculos,
    ResumenTelefoniaReportes? resumenTelefonia,
    ResumenTiemposExtraDetalle? resumenTiemposExtra,
    ResumenCoberturaOperativa? resumenCobertura,
    ResumenCobranza? resumenCobranza,
    PosicionDeCaja? posicionCaja,
    CreditoDisponibleTarjetas? creditoDisponibleTarjetas,
    PersonalOperativoDashboard? personalOperativo,
    NominaData? proximaNomina,
    bool proximaNominaEsNull = false,
    int? proximaNominaTotal,
    List<PuntoSerieFinanciera>? serieFinanciera,
    AlertasDashboard? alertas,
    ActividadRecienteDashboard? actividad,
    String? errorCarga,
  }) {
    return DashboardState(
      cargando: cargando ?? this.cargando,
      periodo: periodo ?? this.periodo,
      resumenGeneral: resumenGeneral ?? this.resumenGeneral,
      resumenPersonal: resumenPersonal ?? this.resumenPersonal,
      resumenNomina: resumenNomina ?? this.resumenNomina,
      resumenInventario: resumenInventario ?? this.resumenInventario,
      resumenVehiculos: resumenVehiculos ?? this.resumenVehiculos,
      resumenTelefonia: resumenTelefonia ?? this.resumenTelefonia,
      resumenTiemposExtra: resumenTiemposExtra ?? this.resumenTiemposExtra,
      resumenCobertura: resumenCobertura ?? this.resumenCobertura,
      resumenCobranza: resumenCobranza ?? this.resumenCobranza,
      posicionCaja: posicionCaja ?? this.posicionCaja,
      creditoDisponibleTarjetas: creditoDisponibleTarjetas ?? this.creditoDisponibleTarjetas,
      personalOperativo: personalOperativo ?? this.personalOperativo,
      proximaNomina: proximaNominaEsNull ? null : (proximaNomina ?? this.proximaNomina),
      proximaNominaTotal: proximaNominaTotal ?? this.proximaNominaTotal,
      serieFinanciera: serieFinanciera ?? this.serieFinanciera,
      alertas: alertas ?? this.alertas,
      actividad: actividad ?? this.actividad,
      errorCarga: errorCarga,
    );
  }
}
