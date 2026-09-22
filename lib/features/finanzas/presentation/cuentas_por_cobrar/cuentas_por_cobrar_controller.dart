import 'package:riseg_one/features/notificaciones/presentation/notificaciones_controller.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cancelar_cuenta_por_cobrar_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/corregir_cuenta_por_cobrar_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cuenta_por_cobrar_antiguedad.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/quitar_reprogramacion_cobro_cuenta_por_cobrar_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/reprogramar_cobro_cuenta_por_cobrar_usecase.dart';

import '../../../dashboard/presentation/dashboard_controller.dart';
import '../../finanzas_providers.dart';
import '../planeacion/planeacion_financiera_controller.dart';
import '../resumen/resumen_financiero_controller.dart';
import 'cuentas_por_cobrar_state.dart';

part 'cuentas_por_cobrar_controller.g.dart';

/// Controlador del listado de Cuentas por cobrar (Etapa 4J.1) — mismo
/// diseño que `AgendaController`. "Solo vencidas" se filtra en memoria
/// sobre la página cargada: `estaVencida` es derivada (Resolución D de
/// Marlon), no una columna que el repositorio pueda filtrar por SQL.
@riverpod
class CuentasPorCobrarController extends _$CuentasPorCobrarController {
  @override
  CuentasPorCobrarState build() {
    Future.microtask(_cargar);
    return const CuentasPorCobrarState();
  }

  Future<void> _cargar() async {
    state = state.copyWith(cargando: true, errorCarga: null);
    try {
      final cuentas = await ref.read(cuentaPorCobrarRepositoryProvider).listar(
            clienteId: state.clienteId,
            estatus: state.estatus,
          );
      // Los nombres se resuelven en LOTE junto con las filas: dos
      // consultas fijas, nunca una por cuenta.
      final nombres = await ref.read(resolverNombresContraparteUseCaseProvider).paraCuentas(cuentas);
      state = state.copyWith(cargando: false, cuentas: cuentas, nombres: nombres, errorCarga: null);
    } catch (e) {
      state = state.copyWith(cargando: false, errorCarga: e.toString());
    }
  }

  Future<void> reintentarCarga() => _cargar();

  Future<void> aplicarFiltros({
    String? clienteId,
    String? estatus,
    bool? soloVencidas,
    bool limpiarClienteId = false,
    bool limpiarEstatus = false,
  }) async {
    state = state.copyWith(
      clienteId: clienteId,
      estatus: estatus,
      soloVencidas: soloVencidas,
      limpiarClienteId: limpiarClienteId,
      limpiarEstatus: limpiarEstatus,
    );
    await _cargar();
  }

  /// Filas visibles considerando "solo vencidas" sobre la carga actual.
  List<CuentaPorCobrarData> cuentasVisibles(DateTime hoy) {
    if (!state.soloVencidas) return state.cuentas;
    return state.cuentas.where((c) => estaVencida(c, hoy)).toList();
  }

  Future<CuentaPorCobrarData?> obtenerPorId(String cuentaPorCobrarId) {
    return ref.read(cuentaPorCobrarRepositoryProvider).obtenerPorId(cuentaPorCobrarId);
  }

  Future<List<CuentaPorCobrarEventoData>> listarEventos(String cuentaPorCobrarId) {
    return ref.read(cuentaPorCobrarRepositoryProvider).listarEventos(cuentaPorCobrarId);
  }

  /// Corrige `fechaVencimiento`/`observaciones` (Etapa 7, Categoría C —
  /// ver el doc comment de `CorregirCuentaPorCobrarUseCase`).
  Future<CorregirCuentaPorCobrarResultado> corregir({
    required String cuentaPorCobrarId,
    DateTime? fechaVencimiento,
    bool limpiarFechaVencimiento = false,
    String? observaciones,
    bool limpiarObservaciones = false,
    required String motivo,
  }) async {
    final resultado = await ref.read(corregirCuentaPorCobrarAutorizadoProvider)(
      cuentaPorCobrarId: cuentaPorCobrarId,
      fechaVencimiento: fechaVencimiento,
      limpiarFechaVencimiento: limpiarFechaVencimiento,
      observaciones: observaciones,
      limpiarObservaciones: limpiarObservaciones,
      motivo: motivo,
    );
    if (resultado is CorregirCuentaPorCobrarExitoso) {
      await _cargar();
      // Cambia qué compromisos/serie muestran el Resumen y la
      // Planeación financiera, y la clasificación de cobranza del
      // Dashboard — ninguno de los tres se entera sin invalidar aquí
      // (Etapa 19C/19D corrigió los dos primeros; el Dashboard era un
      // hueco real: consume `fechaVencimiento`/`estatus` directo vía
      // `ObtenerResumenCobranzaUseCase`/`ObtenerAlertasDashboardUseCase`).
      ref.invalidate(resumenFinancieroControllerProvider);
      ref.invalidate(planeacionFinancieraControllerProvider);
      ref.invalidate(dashboardControllerProvider);
      // La campana cuenta CxC próximas a vencer y vencidas: cambiar su
      // vencimiento, reprogramarla o cancelarla altera ese número.
      ref.invalidate(notificacionesControllerProvider);
    }
    return resultado;
  }

  /// Reprograma la expectativa de cobro de una CxC vencida (Etapa 19D)
  /// — nunca toca `fechaVencimiento` (ver el doc comment del use case).
  /// `fechaCobroReprogramada: null` limpia la reprogramación (mismo
  /// mecanismo que expone [quitarReprogramacion] con semántica propia).
  Future<ReprogramarCobroCuentaPorCobrarResultado> reprogramarCobro({
    required String cuentaPorCobrarId,
    required DateTime? fechaCobroReprogramada,
    required String motivo,
  }) async {
    final resultado = await ref.read(reprogramarCobroCuentaPorCobrarAutorizadoProvider)(
      cuentaPorCobrarId: cuentaPorCobrarId,
      fechaCobroReprogramada: fechaCobroReprogramada,
      motivo: motivo,
    );
    if (resultado is ReprogramarCobroCuentaPorCobrarExitoso) {
      await _cargar();
      ref.invalidate(resumenFinancieroControllerProvider);
      ref.invalidate(planeacionFinancieraControllerProvider);
      ref.invalidate(dashboardControllerProvider);
      // La campana cuenta CxC próximas a vencer y vencidas: cambiar su
      // vencimiento, reprogramarla o cancelarla altera ese número.
      ref.invalidate(notificacionesControllerProvider);
    }
    return resultado;
  }

  /// Quita una reprogramación capturada por error (Etapa 7, Sección 5)
  /// — la Planeación vuelve a proyectar sobre `fechaVencimiento`.
  Future<QuitarReprogramacionCobroCuentaPorCobrarResultado> quitarReprogramacion({
    required String cuentaPorCobrarId,
    required String motivo,
  }) async {
    final resultado = await ref.read(quitarReprogramacionCobroCuentaPorCobrarAutorizadoProvider)(
      cuentaPorCobrarId: cuentaPorCobrarId,
      motivo: motivo,
    );
    if (resultado is QuitarReprogramacionCobroCuentaPorCobrarExitoso) {
      await _cargar();
      ref.invalidate(resumenFinancieroControllerProvider);
      ref.invalidate(planeacionFinancieraControllerProvider);
      ref.invalidate(dashboardControllerProvider);
      // La campana cuenta CxC próximas a vencer y vencidas: cambiar su
      // vencimiento, reprogramarla o cancelarla altera ese número.
      ref.invalidate(notificacionesControllerProvider);
    }
    return resultado;
  }

  /// Cancela la obligación completa (Etapa 7, Sección 6) — bloqueado si
  /// tiene alguna `AplicacionPago` activa (ver el doc comment de
  /// `CancelarCuentaPorCobrarUseCase`). Nunca toca `DocumentoPorEmitir`.
  Future<CancelarCuentaPorCobrarResultado> cancelar({
    required String cuentaPorCobrarId,
    required String motivo,
  }) async {
    final resultado = await ref.read(cancelarCuentaPorCobrarAutorizadoProvider)(
      cuentaPorCobrarId: cuentaPorCobrarId,
      motivo: motivo,
    );
    if (resultado is CancelarCuentaPorCobrarExitoso) {
      await _cargar();
      ref.invalidate(resumenFinancieroControllerProvider);
      ref.invalidate(planeacionFinancieraControllerProvider);
      ref.invalidate(dashboardControllerProvider);
      // La campana cuenta CxC próximas a vencer y vencidas: cambiar su
      // vencimiento, reprogramarla o cancelarla altera ese número.
      ref.invalidate(notificacionesControllerProvider);
    }
    return resultado;
  }
}
