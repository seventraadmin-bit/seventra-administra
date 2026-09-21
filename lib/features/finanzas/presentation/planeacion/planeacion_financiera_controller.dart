import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:riseg_one/features/finanzas/domain/usecases/calcular_serie_disponibilidad_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/reprogramar_cobro_cuenta_por_cobrar_usecase.dart';

import '../../../dashboard/presentation/dashboard_controller.dart';
import '../../finanzas_providers.dart';
import '../cuentas_por_cobrar/cuentas_por_cobrar_controller.dart';
import '../resumen/resumen_financiero_controller.dart';
import 'planeacion_financiera_state.dart';

part 'planeacion_financiera_controller.g.dart';

/// Controlador de Planeación financiera (Etapa 19D) — consume
/// exactamente el mismo `ObtenerProyeccionCajaUseCase` que
/// `ResumenFinancieroController`, nunca una segunda lógica de
/// proyección. Lo único propio de esta pantalla es la serie diaria
/// (`calcularSerieDisponibilidad`, función pura) y el estado de
/// navegación del calendario (mes visible, día seleccionado).
@riverpod
class PlaneacionFinancieraController extends _$PlaneacionFinancieraController {
  @override
  PlaneacionFinancieraState build() {
    Future.microtask(_cargar);
    return const PlaneacionFinancieraState();
  }

  /// La serie/proyección siempre arranca en HOY (nunca hay "proyección
  /// pasada", ver el doc comment de `ObtenerProyeccionCajaUseCase`).
  /// Cuando el mes visible termina antes de hoy (Mes anterior), no hay
  /// nada que proyectar hacia adelante en ese rango — `hasta` se topa
  /// en `hoy` y la serie queda vacía; el calendario en sí sigue
  /// mostrando lo que corresponda (normalmente nada, todo ya resuelto o
  /// movido a "Pendientes vencidos").
  DateTime _hastaDelMesVisible(DateTime mesVisible, DateTime hoySinHora) {
    final finDeMes = DateTime(mesVisible.year, mesVisible.month + 1, 0, 23, 59, 59, 999);
    return finDeMes.isBefore(hoySinHora) ? hoySinHora : finDeMes;
  }

  Future<void> _cargar() async {
    state = state.copyWith(cargando: true, errorCarga: null);
    try {
      final hoy = DateTime.now();
      final hoySinHora = DateTime(hoy.year, hoy.month, hoy.day);
      final mesVisible = state.mesVisible;
      final hasta = _hastaDelMesVisible(mesVisible, hoySinHora);

      final proyeccionCaja = await ref.read(obtenerProyeccionCajaUseCaseProvider).ejecutar(hoy: hoy, hasta: hasta);
      final serie = calcularSerieDisponibilidad(
        hoy: hoy,
        hasta: hasta,
        saldoActual: proyeccionCaja.saldoActual,
        compromisos: proyeccionCaja.compromisos,
      );

      final dentroDelMesVisible = hoySinHora.year == mesVisible.year && hoySinHora.month == mesVisible.month;
      final diaSeleccionado = state.diaSeleccionado ?? (dentroDelMesVisible ? hoySinHora : DateTime(mesVisible.year, mesVisible.month, 1));

      state = state.copyWith(
        cargando: false,
        proyeccionCaja: proyeccionCaja,
        serie: serie,
        diaSeleccionado: diaSeleccionado,
        errorCarga: null,
      );
    } catch (e) {
      state = state.copyWith(cargando: false, errorCarga: e.toString());
    }
  }

  Future<void> reintentarCarga() => _cargar();

  Future<void> cambiarPeriodo(PeriodoPlaneacion periodo) async {
    final hoy = DateTime.now();
    final mesVisible = switch (periodo) {
      PeriodoPlaneacion.mesAnterior => DateTime(hoy.year, hoy.month - 1, 1),
      PeriodoPlaneacion.esteMes => DateTime(hoy.year, hoy.month, 1),
      PeriodoPlaneacion.mesSiguiente => DateTime(hoy.year, hoy.month + 1, 1),
      PeriodoPlaneacion.personalizado => state.mesVisible,
    };
    state = state.copyWith(periodo: periodo, mesVisible: mesVisible, limpiarDiaSeleccionado: true);
    await _cargar();
  }

  Future<void> elegirMesPersonalizado(DateTime unDiaDelMes) async {
    state = state.copyWith(
      periodo: PeriodoPlaneacion.personalizado,
      mesVisible: DateTime(unDiaDelMes.year, unDiaDelMes.month, 1),
      limpiarDiaSeleccionado: true,
    );
    await _cargar();
  }

  void seleccionarDia(DateTime dia) {
    state = state.copyWith(diaSeleccionado: DateTime(dia.year, dia.month, dia.day));
  }

  /// Reprograma (o limpia, con `fechaCobroReprogramada: null`) la
  /// expectativa de cobro de una CxC vencida — ver el doc comment de
  /// `ReprogramarCobroCuentaPorCobrarUseCase`.
  Future<ReprogramarCobroCuentaPorCobrarResultado> reprogramarCobro({
    required String cuentaPorCobrarId,
    required DateTime? fechaCobroReprogramada,
    required String motivo,
  }) async {
    // Etapa 0 (auditoría de consistencia transversal — corrección de
    // un hueco real de autorización): antes llamaba al use case crudo,
    // sin ningún `autorizarUseCase` — la misma operación invocada
    // desde Cuentas por Cobrar sí estaba gateada (`finanzas.modificar`).
    final resultado = await ref.read(reprogramarCobroCuentaPorCobrarAutorizadoProvider)(
      cuentaPorCobrarId: cuentaPorCobrarId,
      fechaCobroReprogramada: fechaCobroReprogramada,
      motivo: motivo,
    );
    if (resultado is ReprogramarCobroCuentaPorCobrarExitoso) {
      await _cargar();
      // Cambia qué compromisos muestra el Resumen financiero, el
      // listado de Cuentas por cobrar y la clasificación de cobranza
      // del Dashboard — ninguno de los tres se entera sin invalidar
      // aquí (Etapa 7: el Dashboard era un hueco real).
      ref.invalidate(resumenFinancieroControllerProvider);
      ref.invalidate(cuentasPorCobrarControllerProvider);
      ref.invalidate(dashboardControllerProvider);
    }
    return resultado;
  }
}
