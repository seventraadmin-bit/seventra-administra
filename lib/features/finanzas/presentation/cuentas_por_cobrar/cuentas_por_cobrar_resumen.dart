import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/tables/cuenta_por_cobrar_table.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cuenta_por_cobrar_antiguedad.dart';

/// Resumen del conjunto filtrado de Cuentas por cobrar (Etapa 17,
/// centro de cobranza) — agregado en memoria sobre la página ya
/// cargada (`CuentasPorCobrarController.cuentasVisibles`), nunca una
/// consulta nueva. "Vencido"/"Por vencer" son clasificaciones
/// DERIVADAS (`estaVencida`, Resolución D de Marlon: nunca un estatus
/// persistido), nunca inventadas como columna.
class CuentasPorCobrarResumen {
  const CuentasPorCobrarResumen({
    required this.saldoPendiente,
    required this.saldoVencido,
    required this.saldoPorVencer,
    required this.pagadas,
  });

  final int saldoPendiente;
  final int saldoVencido;
  final int saldoPorVencer;
  final int pagadas;
}

CuentasPorCobrarResumen calcularResumenCuentasPorCobrar(List<CuentaPorCobrarData> cuentas, DateTime hoy) {
  var saldoPendiente = 0;
  var saldoVencido = 0;
  var pagadas = 0;

  for (final c in cuentas) {
    saldoPendiente += c.saldoPendiente;
    if (estaVencida(c, hoy)) saldoVencido += c.saldoPendiente;
    if (EstatusCuentaPorCobrar.values.byName(c.estatus) == EstatusCuentaPorCobrar.pagada) pagadas++;
  }

  return CuentasPorCobrarResumen(
    saldoPendiente: saldoPendiente,
    saldoVencido: saldoVencido,
    saldoPorVencer: saldoPendiente - saldoVencido,
    pagadas: pagadas,
  );
}
