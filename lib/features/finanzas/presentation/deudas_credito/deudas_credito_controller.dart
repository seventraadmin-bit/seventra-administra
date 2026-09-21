import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../finanzas_providers.dart';
import 'deudas_credito_state.dart';

part 'deudas_credito_controller.g.dart';

/// Controlador del listado de Deudas y crédito (Etapa 19) — mismo
/// diseño que `CuentasPorCobrarController`. Los KPIs de la pantalla se
/// derivan en memoria sobre `state.deudas` (la página ya cargada,
/// filtrada), nunca una segunda consulta.
@riverpod
class DeudasCreditoController extends _$DeudasCreditoController {
  @override
  DeudasCreditoState build() {
    Future.microtask(_cargar);
    return const DeudasCreditoState();
  }

  Future<void> _cargar() async {
    state = state.copyWith(cargando: true, errorCarga: null);
    try {
      final repo = ref.read(deudaRepositoryProvider);
      final deudas = await repo.listar(
        tipo: state.tipo,
        estatus: state.estatus,
        busqueda: state.busqueda,
      );
      final pagadoPorDeudaId = deudas.isEmpty ? <String, int>{} : await repo.totalPagadoPorDeuda(deudaIds: [for (final d in deudas) d.id]);
      state = state.copyWith(cargando: false, deudas: deudas, pagadoPorDeudaId: pagadoPorDeudaId, errorCarga: null);
    } catch (e) {
      state = state.copyWith(cargando: false, errorCarga: e.toString());
    }
  }

  Future<void> reintentarCarga() => _cargar();

  Future<void> aplicarFiltros({
    String? tipo,
    String? estatus,
    String? busqueda,
    bool limpiarTipo = false,
    bool limpiarEstatus = false,
    bool limpiarBusqueda = false,
  }) async {
    state = state.copyWith(
      tipo: tipo,
      estatus: estatus,
      busqueda: busqueda,
      limpiarTipo: limpiarTipo,
      limpiarEstatus: limpiarEstatus,
      limpiarBusqueda: limpiarBusqueda,
    );
    await _cargar();
  }
}
