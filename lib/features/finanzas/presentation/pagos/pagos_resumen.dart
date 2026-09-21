import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart';

/// Resumen del conjunto filtrado de Pagos (Etapa 17) — agregado en
/// memoria sobre la página ya cargada, nunca una consulta nueva.
/// "Pendiente de aplicar" es real (`montoTotal - montoAplicado`, ambos
/// columnas ya almacenadas — un Pago puede quedar sin aplicar total o
/// parcialmente, confirmado por el modelo). Solo considera Pagos
/// `registrado` — un Pago `cancelado` no representa dinero recibido
/// vigente.
class PagosResumen {
  const PagosResumen({
    required this.pagosRecibidos,
    required this.montoRecibido,
    required this.montoAplicado,
    required this.pendienteAplicar,
  });

  final int pagosRecibidos;
  final int montoRecibido;
  final int montoAplicado;
  final int pendienteAplicar;
}

PagosResumen calcularResumenPagos(List<PagoData> pagos) {
  var pagosRecibidos = 0;
  var montoRecibido = 0;
  var montoAplicado = 0;

  for (final p in pagos) {
    if (EstatusPago.values.byName(p.estatus) != EstatusPago.registrado) continue;
    pagosRecibidos++;
    montoRecibido += p.montoTotal;
    montoAplicado += p.montoAplicado;
  }

  return PagosResumen(
    pagosRecibidos: pagosRecibidos,
    montoRecibido: montoRecibido,
    montoAplicado: montoAplicado,
    pendienteAplicar: montoRecibido - montoAplicado,
  );
}
