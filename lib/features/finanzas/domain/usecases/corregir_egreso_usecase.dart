import 'package:riseg_one/features/finanzas/domain/politica_saldo_cuenta.dart';
import 'package:riseg_one/core/auditoria/diff_evento.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/error/diagnostico_error_inesperado.dart';
import 'package:riseg_one/features/finanzas/data/tables/egreso_table.dart';

import '../origen_financiero_gasto.dart';
import '../repositories/deuda_repository.dart';
import '../repositories/egreso_repository.dart';
import 'obtener_origen_automatico_egreso_usecase.dart';

sealed class CorregirEgresoResultado {}

class CorregirEgresoExitoso extends CorregirEgresoResultado {
  CorregirEgresoExitoso(this.egreso);
  final EgresoData egreso;
}

class CorregirEgresoNoExiste extends CorregirEgresoResultado {}

class CorregirEgresoCancelado extends CorregirEgresoResultado {}

/// Un Egreso automático (generado por Compra/Pago de Nómina/Tiempo
/// Extra/un pago de Deuda — ver `ObtenerOrigenAutomaticoEgresoUseCase`)
/// solo se corrige a través de su entidad de origen — corregirlo aquí
/// directamente lo desincronizaría en silencio de esa fuente de
/// verdad. [origen] identifica cuál, para que la UI ofrezca "Ver
/// origen" sin una segunda consulta.
class CorregirEgresoOrigenAutomatico extends CorregirEgresoResultado {
  CorregirEgresoOrigenAutomatico(this.origen);
  final OrigenAutomaticoEgreso origen;
}

class CorregirEgresoMotivoRequerido extends CorregirEgresoResultado {}

class CorregirEgresoMontoInvalido extends CorregirEgresoResultado {}

/// La TDC elegida como origen nuevo no existe, no es tarjeta, no está
/// activa, no tiene límite capturado, o el gasto corregido excede su
/// crédito disponible — mismos casos exactos que
/// `RegistrarEgresoTarjetaInvalida`, resueltos por la misma
/// `validarOrigenTarjeta`.
class CorregirEgresoTarjetaInvalida extends CorregirEgresoResultado {
  CorregirEgresoTarjetaInvalida(this.error, {this.disponible});
  final ErrorOrigenTarjeta error;

  /// Solo poblado cuando [error] es `excedeLimite`. Cuando el gasto ya
  /// estaba en ESA misma tarjeta, es el disponible REAL para él: el
  /// crédito libre más lo que el propio gasto ya ocupaba (nunca el
  /// crédito libre a secas, que lo haría parecer imposible subir el
  /// monto de un gasto que ya casi agota la tarjeta).
  final int? disponible;
}

class CorregirEgresoErrorInesperado extends CorregirEgresoResultado {
  CorregirEgresoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Corrige un Egreso MANUAL — incluye `monto` (etapa "Ingresos y
/// Egresos": antes solo metadatos, "nunca monto"). Bloquea de raíz
/// cualquier intento sobre un Egreso automático (hueco real de
/// auditoría: antes de esta etapa, NINGÚN código verificaba esto —
/// Compra/Nómina/Tiempo Extra/pago de Deuda podían corregirse
/// directamente desde aquí sin que nada lo impidiera). Requiere
/// `motivo` no vacío, validado en dominio.
///
/// Etapa "Origen financiero de Egresos manuales: Cuenta vs. TDC" — la
/// corrección incluye el ORIGEN financiero ([origen]/[limpiarOrigen]),
/// cubriendo las 6 transiciones reales (Cuenta→misma/otra Cuenta,
/// TDC→misma/otra TDC, Cuenta→TDC, TDC→Cuenta) en una sola transacción
/// vía `EgresoRepository.corregirConOrigen`. Cambiar SOLO el origen
/// nunca altera el gasto operativo reconocido: mueve de dónde sale el
/// dinero, no cuánto se gastó.
class CorregirEgresoUseCase {
  CorregirEgresoUseCase(this._repository, this._obtenerOrigenAutomatico, this._deudaRepository);

  final EgresoRepository _repository;
  final ObtenerOrigenAutomaticoEgresoUseCase _obtenerOrigenAutomatico;
  final DeudaRepository _deudaRepository;

  Future<CorregirEgresoResultado> ejecutar({
    required String egresoId,
    int? monto,
    DateTime? fecha,
    String? categoriaFinancieraId,
    String? servicioId,
    String? sucursalId,
    String? areaId,
    String? cuentaCaja,
    OrigenFinancieroGasto? origen,
    bool limpiarOrigen = false,
    String? formaPago,
    String? beneficiario,
    String? concepto,
    String? observaciones,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    final egreso = await _repository.obtenerPorId(egresoId);
    if (egreso == null) {
      return CorregirEgresoNoExiste();
    }
    if (EstatusEgreso.values.byName(egreso.estatus) == EstatusEgreso.cancelado) {
      return CorregirEgresoCancelado();
    }
    // Ojo con los dos "origen" que conviven aquí, deliberadamente
    // distintos: `origenAutomatico` es QUÉ MÓDULO generó este Egreso
    // (Compra/Nómina/…) y bloquea la corrección; el parámetro `origen`
    // es CÓMO se financió el gasto (Cuenta/TDC) y es justo lo que esta
    // corrección puede cambiar.
    final origenAutomatico = await _obtenerOrigenAutomatico.ejecutar(egresoId);
    if (origenAutomatico != null) {
      return CorregirEgresoOrigenAutomatico(origenAutomatico);
    }
    if (!motivoEsValido(motivo)) {
      return CorregirEgresoMotivoRequerido();
    }
    if (monto != null && monto <= 0) {
      return CorregirEgresoMontoInvalido();
    }

    // Validación de crédito de la TDC destino, ANTES de tocar nada.
    if (origen case OrigenFinancieroTarjeta(:final deudaId)) {
      final tarjeta = await _deudaRepository.obtenerPorId(deudaId);
      final montoFinal = monto ?? egreso.monto;

      // Si el gasto YA estaba en esta misma tarjeta, lo que ocupa hoy
      // debe descontarse antes de comparar contra el disponible —
      // comparar el monto nuevo completo contra el crédito libre sería
      // ingenuo (el propio gasto ya consumió parte de ese saldo).
      // Mismo criterio exacto que `CorregirCompraUseCase` con
      // `netoAportadoPorCompra`.
      final netoYaOcupado = egreso.deudaId == deudaId
          ? await _deudaRepository.netoAportadoPorEgreso(deudaId: deudaId, egresoId: egresoId)
          : 0;

      final validacion = validarOrigenTarjeta(tarjeta: tarjeta, monto: montoFinal - netoYaOcupado);
      if (!validacion.esValida) {
        return CorregirEgresoTarjetaInvalida(
          validacion.error!,
          disponible: validacion.disponible == null ? null : validacion.disponible! + netoYaOcupado,
        );
      }
    }

    try {
      final actualizado = await _repository.corregirConOrigen(
        egresoId: egresoId,
        monto: monto,
        fecha: fecha,
        categoriaFinancieraId: categoriaFinancieraId,
        servicioId: servicioId,
        sucursalId: sucursalId,
        areaId: areaId,
        cuentaCaja: cuentaCaja,
        origen: origen,
        limpiarOrigen: limpiarOrigen,
        formaPago: formaPago,
        beneficiario: beneficiario,
        concepto: concepto,
        observaciones: observaciones,
        motivo: motivo,
        actorUsuarioId: actorUsuarioId,
      );
      return CorregirEgresoExitoso(actualizado);
    } on SaldoInsuficienteException {
      // Corregir también puede quedarse sin saldo (subir el importe, o
      // mover la salida a otra cuenta). No es un error inesperado: se
      // deja propagar para que la pantalla muestre los tres números.
      rethrow;
    } catch (e, s) {
      return CorregirEgresoErrorInesperado(diagnosticoErrorInesperado(e, s, contexto: 'CorregirEgresoUseCase'));
    }
  }
}
