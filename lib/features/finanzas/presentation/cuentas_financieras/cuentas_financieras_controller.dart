import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../finanzas_providers.dart';
import '../invalidacion_financiera.dart';
import 'cuentas_financieras_state.dart';

part 'cuentas_financieras_controller.g.dart';

/// Controlador del listado de Cuentas financieras (Etapa 19C) — mismo
/// diseño que `DeudasCreditoController`. El saldo por cuenta se
/// resuelve en lote (`calcularSaldos`), nunca una consulta por fila.
@riverpod
class CuentasFinancierasController extends _$CuentasFinancierasController {
  @override
  CuentasFinancierasState build() {
    Future.microtask(_cargar);
    return const CuentasFinancierasState();
  }

  Future<void> _cargar() async {
    state = state.copyWith(cargando: true, errorCarga: null);
    try {
      final repo = ref.read(cuentaFinancieraRepositoryProvider);
      final cuentas = await repo.listar();
      final saldos = cuentas.isEmpty ? <String, int>{} : await repo.calcularSaldos(cuentas.map((c) => c.id));
      state = state.copyWith(cargando: false, cuentas: cuentas, saldosPorCuenta: saldos, errorCarga: null);
    } catch (e) {
      state = state.copyWith(cargando: false, errorCarga: e.toString());
    }
  }

  Future<void> reintentarCarga() => _cargar();

  /// Recarga esta pantalla y avisa al resto de consumidores
  /// financieros con la lista compartida.
  ///
  /// Existe aquí, y no en el diálogo, porque la extensión de
  /// invalidación vive sobre `Ref` y un widget sólo tiene `WidgetRef`.
  /// Que todo movimiento pase por un notifier evita que cada diálogo
  /// invente su propia lista — el fallo que dejó "Caja y bancos"
  /// mostrando el importe viejo.
  Future<void> refrescarTrasMovimientoFinanciero() async {
    await _cargar();
    ref.invalidarConsumidoresFinancieros(omitir: {cuentasFinancierasControllerProvider});
  }
}
