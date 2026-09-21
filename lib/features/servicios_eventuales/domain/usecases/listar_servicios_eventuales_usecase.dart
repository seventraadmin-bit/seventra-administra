import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/cuenta_por_cobrar_repository.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/cliente_repository.dart';

import '../../data/tables/servicio_eventual_table.dart';
import '../repositories/servicio_eventual_repository.dart';
import '../totales_venta_eventual.dart';

/// Una fila del listado, ya resuelta: el eventual, cómo se llama su
/// solicitante y cuánto lleva costado.
class RenglonServicioEventual {
  const RenglonServicioEventual({
    required this.servicioEventual,
    required this.nombreSolicitante,
    required this.totales,
    required this.cuenta,
    this.cobrado = 0,
  });

  final ServicioEventualData servicioEventual;

  /// El nombre del Cliente, o el del solicitante externo capturado a
  /// mano. Nunca un id.
  final String nombreSolicitante;

  final TotalesServicioEventual totales;

  /// La Cuenta por cobrar del eventual (schemaVersion 88) — `null`
  /// sólo para el histórico anterior a la Rebanada 2.
  final CuentaPorCobrarData? cuenta;

  /// Lo que YA entró por este evento y **sigue vigente**: suma de las
  /// aplicaciones vigentes de Pagos no cancelados.
  ///
  /// Antes se derivaba de `saldoOriginal - saldoPendiente`, y eso
  /// mentía en cuanto la venta se anulaba: cancelar la Cuenta pone el
  /// saldo en 0, así que la resta daba el total de la venta y la
  /// pantalla afirmaba que una venta anulada seguía cobrada. Que
  /// alguna vez entraran esos pesos es historia —vive en el Pago, en
  /// el Ingreso y en la bitácora—, no cobranza vigente.
  final int cobrado;

  /// Lo que todavía se puede exigir. Una venta anulada no exige nada.
  int get pendiente => cuenta?.saldoPendiente ?? 0;

  /// El total a cobrar al cliente (schemaVersion 89) — con IVA cuando
  /// aplica. Es el mismo número que `CuentaPorCobrar.importeEmitido`.
  int get totalVenta => totalVentaEventual(
        importeAcordado: servicioEventual.importeAcordado,
        tratamientoIva: TratamientoIva.values.byName(servicioEventual.tratamientoIva),
      );

  /// Venta menos costo comprometido. **No** es utilidad cobrada: mide
  /// el acuerdo contra el gasto. Lo que de verdad entró es [cobrado],
  /// que sale de la Cuenta por cobrar.
  ///
  /// Usa el total BRUTO, con IVA — la misma convención que todo el
  /// resultado operativo de RISEG ONE, donde `Ingreso.monto` y
  /// `Egreso.monto` son siempre importes brutos. Inventar aquí una
  /// utilidad sobre base sin IVA sería una tercera fórmula que no
  /// cuadraría con Finanzas ni con Reportes.
  int get resultado => totalVenta - totales.costoComprometido;
}

/// Listado de eventuales con su resultado económico.
///
/// **Coste constante en consultas**, sin importar cuántos eventuales
/// haya: una para el listado, dos agregadas para los totales, una para
/// las Cuentas por cobrar y una para los nombres de Cliente. Nunca una
/// por fila — el error que ya se corrigió en Inventario y Compras.
class ListarServiciosEventualesUseCase {
  ListarServiciosEventualesUseCase(this._repository, this._clienteRepository, this._cuentaPorCobrarRepository);

  final ServicioEventualRepository _repository;
  final ClienteRepository _clienteRepository;
  final CuentaPorCobrarRepository _cuentaPorCobrarRepository;

  Future<List<RenglonServicioEventual>> ejecutar({EstatusServicioEventual? estatus}) async {
    final eventuales = await _repository.listar(estatus: estatus?.name);
    if (eventuales.isEmpty) return const [];

    final totales = await _repository.totalesPorEventual(eventuales.map((e) => e.id));

    // Dos consultas más, constantes: nunca una por renglón.
    final cuentas = await _cuentaPorCobrarRepository.porServiciosEventuales(eventuales.map((e) => e.id));
    final cobrado = await _repository.cobradoVigentePorEventual(eventuales.map((e) => e.id));

    final idsCliente = eventuales.map((e) => e.clienteId).whereType<String>().toSet();
    final clientes = idsCliente.isEmpty
        ? const <String, ClienteData>{}
        : await _clienteRepository.listarPorIds(idsCliente);

    return [
      for (final eventual in eventuales)
        RenglonServicioEventual(
          servicioEventual: eventual,
          nombreSolicitante: eventual.clienteId != null
              ? clientes[eventual.clienteId]?.nombreComercial ?? '—'
              : eventual.solicitanteNombre ?? '—',
          totales: totales[eventual.id] ?? const TotalesServicioEventual(),
          cuenta: cuentas[eventual.id],
          cobrado: cobrado[eventual.id] ?? 0,
        ),
    ];
  }
}
