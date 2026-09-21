import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart';

import '../repositories/complemento_pago_repository.dart';
import '../repositories/cuenta_por_cobrar_repository.dart';
import '../repositories/pago_repository.dart';
import 'complemento_pago_derivado.dart';

/// Un Complemento **pendiente**: un Pago real que exige Complemento y
/// todavía no tiene uno vigente.
///
/// NO es una fila de `ComplementoPago` — no existe, y no debe existir
/// (decisión de Marlon: "Pendiente NO es una fila persistida"). Es una
/// proyección, viva, calculada de los hechos reales. Por eso lleva los
/// datos del Pago y de las Cuentas cubiertas, nunca un id propio.
class ComplementoPendiente {
  const ComplementoPendiente({
    required this.pago,
    required this.cuentas,
  });

  final PagoData pago;

  /// Las Cuentas por cobrar que este Pago liquidó vía sus aplicaciones
  /// activas — todas, no sólo las que exigen Complemento: el documento
  /// fiscal reporta el Pago completo (ver la nota de cardinalidad en
  /// `ComplementoPago`).
  final List<CuentaPorCobrarData> cuentas;

  /// Las que originan la obligación. Un solo Pago basta con que tenga
  /// una para quedar pendiente.
  List<CuentaPorCobrarData> get cuentasQueExigenComplemento =>
      cuentas.where(cuentaRequiereComplemento).toList();
}

/// El Pago y las Cuentas de un Complemento YA registrado — el mismo
/// contexto que el pendiente, para que la pantalla pueda responder "qué
/// Pago lo originó / qué facturas cubre" sin copiar nada dentro de
/// `ComplementoPago`.
class ComplementoConContexto {
  const ComplementoConContexto({
    required this.complemento,
    required this.pago,
    required this.cuentas,
  });

  final ComplementoPagoData complemento;
  final PagoData? pago;
  final List<CuentaPorCobrarData> cuentas;
}

/// Proyecta los Complementos pendientes y da contexto a los existentes
/// (Etapa "Complemento dependiente del Pago real").
///
/// Reutiliza `complemento_pago_derivado.dart` **tal cual** — la fórmula
/// de "pendiente" vive en un solo lugar y este caso de uso sólo la
/// aplica sobre el universo completo. Ni Notificaciones ni la pantalla
/// de Complementos la reimplementan.
///
/// Tres consultas en lote sobre universos completos (pagos, aplicaciones
/// activas, cuentas, complementos), nunca una consulta por fila — mismo
/// criterio que `PagosController`.
class ObtenerComplementosPendientesUseCase {
  ObtenerComplementosPendientesUseCase(
    this._pagoRepository,
    this._cuentaRepository,
    this._complementoRepository,
  );

  final PagoRepository _pagoRepository;
  final CuentaPorCobrarRepository _cuentaRepository;
  final ComplementoPagoRepository _complementoRepository;

  Future<({List<ComplementoPendiente> pendientes, List<ComplementoConContexto> registrados})> ejecutar({
    String? clienteId,
  }) async {
    // Sólo Pagos vigentes: uno cancelado no sostiene ninguna obligación
    // fiscal (y `RegistrarComplementoPagoUseCase` ya lo rechaza).
    final pagos = await _pagoRepository.listar(estatus: EstatusPago.registrado.name, clienteId: clienteId);
    final aplicaciones = await _pagoRepository.listarTodasLasAplicacionesActivas();
    final cuentas = await _cuentaRepository.listar();
    final complementos = await _complementoRepository.listar();

    final cuentaPorId = {for (final c in cuentas) c.id: c};
    final pagoPorId = {for (final p in pagos) p.id: p};

    // El HISTÓRICO completo por Pago (schemaVersion 79) — antes era un
    // mapa de una sola fila, que con sustitutos se quedaba con una
    // arbitraria y podía dar por documentado un Pago cuyo único
    // Complemento estaba cancelado.
    final complementosPorPagoId = <String, List<ComplementoPagoData>>{};
    for (final c in complementos) {
      complementosPorPagoId.putIfAbsent(c.pagoId, () => []).add(c);
    }

    final cuentasPorPagoId = <String, List<CuentaPorCobrarData>>{};
    for (final a in aplicaciones) {
      final cuenta = cuentaPorId[a.cuentaPorCobrarId];
      if (cuenta == null) continue;
      cuentasPorPagoId.putIfAbsent(a.pagoId, () => []).add(cuenta);
    }

    final pendientes = <ComplementoPendiente>[];
    for (final pago in pagos) {
      final cuentasDelPago = cuentasPorPagoId[pago.id] ?? const <CuentaPorCobrarData>[];
      if (!pagoRequiereComplemento(cuentasDelPago)) continue;
      final pendiente = complementoPendiente(
        requiereComplemento: true,
        complementosDelPago: complementosPorPagoId[pago.id] ?? const [],
      );
      if (pendiente) {
        pendientes.add(ComplementoPendiente(pago: pago, cuentas: cuentasDelPago));
      }
    }
    // El más reciente primero: es el que se acaba de recibir y el que
    // hay que timbrar.
    pendientes.sort((a, b) => b.pago.fechaPago.compareTo(a.pago.fechaPago));

    final registrados = [
      for (final complemento in complementos)
        if (clienteId == null || pagoPorId[complemento.pagoId]?.clienteId == clienteId)
          ComplementoConContexto(
            complemento: complemento,
            pago: pagoPorId[complemento.pagoId],
            cuentas: cuentasPorPagoId[complemento.pagoId] ?? const [],
          ),
    ];

    return (pendientes: pendientes, registrados: registrados);
  }
}
