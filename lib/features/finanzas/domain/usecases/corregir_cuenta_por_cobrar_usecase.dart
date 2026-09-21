import 'package:riseg_one/core/auditoria/diff_evento.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/tables/cuenta_por_cobrar_table.dart';

import '../repositories/cuenta_por_cobrar_repository.dart';

sealed class CorregirCuentaPorCobrarResultado {}

class CorregirCuentaPorCobrarExitoso extends CorregirCuentaPorCobrarResultado {
  CorregirCuentaPorCobrarExitoso(this.cuenta);
  final CuentaPorCobrarData cuenta;
}

class CorregirCuentaPorCobrarNoExiste extends CorregirCuentaPorCobrarResultado {}

/// Una CxC cancelada es terminal — no admite más correcciones
/// administrativas (mismo criterio que "un Pago cancelado no admite
/// correcciones").
class CorregirCuentaPorCobrarCancelada extends CorregirCuentaPorCobrarResultado {}

class CorregirCuentaPorCobrarMotivoRequerido extends CorregirCuentaPorCobrarResultado {}

class CorregirCuentaPorCobrarErrorInesperado extends CorregirCuentaPorCobrarResultado {
  CorregirCuentaPorCobrarErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Corrige los ÚNICOS dos campos de Categoría C que son legítima
/// propiedad de una Cuenta por cobrar (Etapa 7, auditoría de fuente de
/// verdad): `fechaVencimiento` (Resolución E de Marlon: completa el
/// caso Mirabilia o corrige una fecha ya definida) y `observaciones`.
///
/// Nunca `importeEmitido`/`saldoOriginal`/`documentoPorEmitirId`/
/// `clienteId`/`folioDocumento`/`uuid` (Categoría A, snapshot congelado
/// del Documento de origen — ninguna vía real existe para que quedaran
/// desactualizados, así que no hay nada que corregir ahí; un error de
/// captura en esos campos se corrige en el dominio de
/// `DocumentoPorEmitir`, nunca aquí). Nunca `saldoPendiente`/`estatus`
/// (Categoría B, derivados — solo `PagoRepository.aplicar`/
/// `cancelarAplicacion`/`corregir` los mueven).
///
/// Reemplaza a `ActualizarFechaVencimientoCuentaPorCobrarUseCase`
/// (Etapa 4J.1) — evoluciona el permiso `cuentaPorCobrar.corregirFecha`
/// a `cuentaPorCobrar.corregir` (más amplio: ahora también cubre
/// `observaciones`), migrado de forma aditiva/idempotente (v74).
class CorregirCuentaPorCobrarUseCase {
  CorregirCuentaPorCobrarUseCase(this._repository);

  final CuentaPorCobrarRepository _repository;

  Future<CorregirCuentaPorCobrarResultado> ejecutar({
    required String cuentaPorCobrarId,
    DateTime? fechaVencimiento,
    bool limpiarFechaVencimiento = false,
    String? observaciones,
    bool limpiarObservaciones = false,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    if (!motivoEsValido(motivo)) return CorregirCuentaPorCobrarMotivoRequerido();

    final cuenta = await _repository.obtenerPorId(cuentaPorCobrarId);
    if (cuenta == null) return CorregirCuentaPorCobrarNoExiste();
    if (EstatusCuentaPorCobrar.values.byName(cuenta.estatus) == EstatusCuentaPorCobrar.cancelada) {
      return CorregirCuentaPorCobrarCancelada();
    }

    try {
      final actualizada = await _repository.corregir(
        cuentaPorCobrarId: cuentaPorCobrarId,
        fechaVencimiento: fechaVencimiento,
        limpiarFechaVencimiento: limpiarFechaVencimiento,
        observaciones: observaciones,
        limpiarObservaciones: limpiarObservaciones,
        motivo: motivo,
        actorUsuarioId: actorUsuarioId,
      );
      return CorregirCuentaPorCobrarExitoso(actualizada);
    } catch (e) {
      return CorregirCuentaPorCobrarErrorInesperado(e.toString());
    }
  }
}
