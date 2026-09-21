import 'package:riseg_one/core/auditoria/diff_evento.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart';

import '../repositories/complemento_pago_repository.dart';
import '../repositories/cuenta_por_cobrar_repository.dart';
import '../repositories/pago_repository.dart';
import 'package:riseg_one/features/finanzas/domain/contraparte_cobro.dart';

sealed class CorregirPagoResultado {}

class CorregirPagoExitoso extends CorregirPagoResultado {
  CorregirPagoExitoso(this.pago);
  final PagoData pago;
}

class CorregirPagoNoExiste extends CorregirPagoResultado {}

/// Un Pago cancelado no admite correcciones — cancélese/vuélvase a
/// capturar si el error está en el monto, o regístrese uno nuevo.
class CorregirPagoCancelado extends CorregirPagoResultado {}

class CorregirPagoMotivoRequerido extends CorregirPagoResultado {}

/// `montoTotal`/el monto de una fila de [PagoRepository.corregir]
/// `nuevaDistribucion` no es `> 0`.
class CorregirPagoValorInvalido extends CorregirPagoResultado {}

/// `montoTotal` bajó por debajo de lo que ya está aplicado
/// (`montoAplicado` actual) sin proveer una `nuevaDistribucion` que
/// reasigne ese dinero — Sección 3 del pedido: nunca se reduce en
/// silencio una aplicación arbitraria para cuadrar el nuevo total.
class CorregirPagoMontoMenorQueAplicado extends CorregirPagoResultado {
  CorregirPagoMontoMenorQueAplicado(this.montoAplicado);
  final int montoAplicado;
}

/// La suma de `nuevaDistribucion` excede el `montoTotal` final —
/// nunca se aplica más dinero del que efectivamente se recibió.
class CorregirPagoSobrepago extends CorregirPagoResultado {
  CorregirPagoSobrepago(this.montoDisponible);
  final int montoDisponible;
}

class CorregirPagoCuentaNoExiste extends CorregirPagoResultado {
  CorregirPagoCuentaNoExiste(this.cuentaPorCobrarId);
  final String cuentaPorCobrarId;
}

/// Una fila de `nuevaDistribucion` referencia una Cuenta por cobrar de
/// un Cliente distinto al del Pago.
class CorregirPagoClienteNoCoincide extends CorregirPagoResultado {
  CorregirPagoClienteNoCoincide(this.cuentaPorCobrarId);
  final String cuentaPorCobrarId;
}

/// Una fila de `nuevaDistribucion` excede el saldo que esa Cuenta
/// tendría disponible DESPUÉS de revertir la distribución anterior de
/// este mismo Pago (nunca el saldo actual en crudo, que todavía
/// refleja la distribución vieja).
class CorregirPagoSobrepagoDeCuenta extends CorregirPagoResultado {
  CorregirPagoSobrepagoDeCuenta(this.cuentaPorCobrarId, this.saldoDisponible);
  final String cuentaPorCobrarId;
  final int saldoDisponible;
}

/// Sección 6/17 del pedido (punto de decisión ya resuelto: bloqueo
/// estricto — monto/fecha/forma de pago/aplicaciones): existe un
/// `ComplementoPago` vigente (`estatus == registrado`) y la corrección
/// solicitada toca al menos uno de esos campos. Nunca se bloquean
/// `cuentaFinancieraId`/`referencia`/`bancoOrigen`/
/// `cuentaBancariaDestino`/`observaciones` (no aparecen en el CFDI de
/// Complemento de pago).
class CorregirPagoComplementoVigente extends CorregirPagoResultado {
  CorregirPagoComplementoVigente(this.uuid);
  final String uuid;
}

class CorregirPagoErrorInesperado extends CorregirPagoResultado {
  CorregirPagoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Corrige un Pago (Etapa 6, reversa explícita de la resolución de la
/// Etapa 4J.2 "nunca `montoTotal`") — ahora también `montoTotal`,
/// `cuentaFinancieraId` (vive únicamente en el `Ingreso` automático
/// ligado) y la distribución completa de `AplicacionPago` (modelo N:M
/// real, nunca solo 1 Pago → 1 Cuenta). Requiere `motivo`, actor real,
/// auditoría before/after (`PagoEvento`, `IngresoEvento`,
/// `CuentaPorCobrarEvento` vía `aplicar`/`cancelarAplicacion`).
///
/// Bloquea CUALQUIER corrección de monto/fecha/forma de pago/
/// aplicaciones si existe un `ComplementoPago` vigente asociado —
/// nunca campos puramente administrativos/no fiscales.
class CorregirPagoUseCase {
  CorregirPagoUseCase(this._repository, this._cuentaPorCobrarRepository, this._complementoPagoRepository);

  final PagoRepository _repository;
  final CuentaPorCobrarRepository _cuentaPorCobrarRepository;
  final ComplementoPagoRepository _complementoPagoRepository;

  Future<CorregirPagoResultado> ejecutar({
    required String pagoId,
    DateTime? fechaPago,
    String? formaPago,
    String? referencia,
    String? bancoOrigen,
    String? cuentaBancariaDestino,
    String? cuentaFinancieraId,
    bool limpiarCuentaFinancieraId = false,
    String? observaciones,
    int? montoTotal,
    List<({String cuentaPorCobrarId, int monto})>? nuevaDistribucion,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    if (!motivoEsValido(motivo)) return CorregirPagoMotivoRequerido();

    final pago = await _repository.obtenerPorId(pagoId);
    if (pago == null) {
      return CorregirPagoNoExiste();
    }
    if (EstatusPago.values.byName(pago.estatus) == EstatusPago.cancelado) {
      return CorregirPagoCancelado();
    }
    if (montoTotal != null && montoTotal <= 0) {
      return CorregirPagoValorInvalido();
    }

    // Sección 6/17: bloqueo estricto — nunca se decide caso por caso
    // qué tan "fiscalmente relevante" es cada corrección puntual, el
    // Complemento vigente congela monto/fecha/forma de pago/
    // aplicaciones en bloque.
    // Sólo el VIGENTE congela (schemaVersion 79) — un Complemento
    // cancelado no documenta nada, así que no puede bloquear una
    // corrección. Con el modelo de sustitutos el histórico puede tener
    // varios; la consulta pide exactamente el vigente.
    final complemento = await _complementoPagoRepository.obtenerVigentePorPagoId(pagoId);
    final tocaMonto = montoTotal != null && montoTotal != pago.montoTotal;
    final tocaFecha = fechaPago != null && fechaPago != pago.fechaPago;
    final tocaFormaPago = formaPago != null && formaPago != pago.formaPago;
    final tocaAplicaciones = nuevaDistribucion != null;
    if (complemento != null && (tocaMonto || tocaFecha || tocaFormaPago || tocaAplicaciones)) {
      return CorregirPagoComplementoVigente(complemento.uuid);
    }

    final montoTotalFinal = montoTotal ?? pago.montoTotal;

    if (nuevaDistribucion == null) {
      // Sin redistribución: el monto total puede cambiar, pero nunca
      // por debajo de lo que ya está aplicado — no hay a dónde
      // reasignar ese excedente sin una distribución explícita.
      if (montoTotalFinal < pago.montoAplicado) {
        return CorregirPagoMontoMenorQueAplicado(pago.montoAplicado);
      }
    } else {
      var suma = 0;
      final montoPorCuenta = <String, int>{};
      for (final item in nuevaDistribucion) {
        if (item.monto <= 0) return CorregirPagoValorInvalido();
        montoPorCuenta[item.cuentaPorCobrarId] = (montoPorCuenta[item.cuentaPorCobrarId] ?? 0) + item.monto;
        suma += item.monto;
      }
      if (suma > montoTotalFinal) {
        return CorregirPagoSobrepago(montoTotalFinal);
      }

      // Saldo simulado tras revertir la distribución ACTUAL de este
      // Pago (nunca el saldo en crudo de la Cuenta, que todavía
      // refleja la distribución vieja) — el primer paso real de
      // `PagoRepository.corregir` es exactamente esa reversión.
      final activas = (await _repository.listarAplicacionesPorPago(pagoId))
          .where((a) => a.estatus == 'aplicada');
      final revertidoPorCuenta = <String, int>{};
      for (final a in activas) {
        revertidoPorCuenta[a.cuentaPorCobrarId] = (revertidoPorCuenta[a.cuentaPorCobrarId] ?? 0) + a.monto;
      }

      final cuentasVistas = <String, CuentaPorCobrarData>{};
      for (final entry in montoPorCuenta.entries) {
        final cuentaPorCobrarId = entry.key;
        var cuenta = cuentasVistas[cuentaPorCobrarId];
        if (cuenta == null) {
          final encontrada = await _cuentaPorCobrarRepository.obtenerPorId(cuentaPorCobrarId);
          if (encontrada == null) return CorregirPagoCuentaNoExiste(cuentaPorCobrarId);
          cuenta = encontrada;
          cuentasVistas[cuentaPorCobrarId] = cuenta;
        }
        if (contraparteDeCuenta(cuenta) != contraparteDePago(pago)) {
          return CorregirPagoClienteNoCoincide(cuentaPorCobrarId);
        }
        final saldoSimulado = cuenta.saldoPendiente + (revertidoPorCuenta[cuentaPorCobrarId] ?? 0);
        if (entry.value > saldoSimulado) {
          return CorregirPagoSobrepagoDeCuenta(cuentaPorCobrarId, saldoSimulado);
        }
      }
    }

    try {
      final actualizado = await _repository.corregir(
        pagoId: pagoId,
        fechaPago: fechaPago,
        formaPago: formaPago,
        referencia: referencia,
        bancoOrigen: bancoOrigen,
        cuentaBancariaDestino: cuentaBancariaDestino,
        cuentaFinancieraId: cuentaFinancieraId,
        limpiarCuentaFinancieraId: limpiarCuentaFinancieraId,
        observaciones: observaciones,
        montoTotal: montoTotal,
        nuevaDistribucion: nuevaDistribucion,
        motivo: motivo,
        actorUsuarioId: actorUsuarioId,
      );
      return CorregirPagoExitoso(actualizado);
    } catch (e) {
      return CorregirPagoErrorInesperado(e.toString());
    }
  }
}
