import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/actualizar_fecha_vencimiento_cuenta_por_cobrar_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cuenta_por_cobrar_antiguedad.dart';

import '../../finanzas_providers.dart';
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
      state = state.copyWith(cargando: false, cuentas: cuentas, errorCarga: null);
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

  Future<ActualizarFechaVencimientoCuentaPorCobrarResultado> actualizarFechaVencimiento({
    required String cuentaPorCobrarId,
    required DateTime fechaVencimiento,
    String? motivo,
  }) async {
    final resultado = await ref.read(actualizarFechaVencimientoCuentaPorCobrarUseCaseProvider).ejecutar(
          cuentaPorCobrarId: cuentaPorCobrarId,
          fechaVencimiento: fechaVencimiento,
          motivo: motivo,
        );
    if (resultado is ActualizarFechaVencimientoCuentaPorCobrarExitoso) {
      await _cargar();
    }
    return resultado;
  }
}
