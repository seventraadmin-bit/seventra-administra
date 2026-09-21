import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/cuenta_financiera_repository.dart';

/// Saldo por cuenta activa, ya derivado (nunca perseado). `configurada
/// == false` cuando no existe ninguna `CuentaFinanciera` activa — en
/// ese caso la Parte J del pedido exige que la UI diga honestamente
/// "Configura tus cuentas financieras..." en vez de mostrar `$0.00`
/// como si fuera un saldo real.
class PosicionDeCaja {
  const PosicionDeCaja({
    required this.configurada,
    required this.saldoDisponible,
    required this.saldosPorCuenta,
    required this.cuentas,
  });

  final bool configurada;
  final int saldoDisponible;
  final Map<String, int> saldosPorCuenta;
  final List<CuentaFinancieraData> cuentas;
}

/// Posición de caja (Etapa 19C, Parte A) — `Saldo inicial + Entradas
/// reales − Salidas reales = Saldo disponible`, agregado sobre todas
/// las cuentas financieras ACTIVAS (una cuenta desactivada conserva su
/// historial pero deja de sumar a la disponibilidad operativa hoy).
class ObtenerPosicionDeCajaUseCase {
  ObtenerPosicionDeCajaUseCase(this._repository);

  final CuentaFinancieraRepository _repository;

  Future<PosicionDeCaja> ejecutar() async {
    final cuentas = await _repository.listar(soloActivas: true);
    if (cuentas.isEmpty) {
      return const PosicionDeCaja(configurada: false, saldoDisponible: 0, saldosPorCuenta: {}, cuentas: []);
    }

    final saldos = await _repository.calcularSaldos(cuentas.map((c) => c.id));
    final saldoDisponible = saldos.values.fold<int>(0, (s, v) => s + v);

    return PosicionDeCaja(configurada: true, saldoDisponible: saldoDisponible, saldosPorCuenta: saldos, cuentas: cuentas);
  }
}
