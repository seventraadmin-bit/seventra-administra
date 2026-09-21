import 'package:riseg_one/features/finanzas/domain/politica_saldo_cuenta.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/error/diagnostico_error_inesperado.dart';

import '../origen_financiero_gasto.dart';
import '../repositories/deuda_repository.dart';
import '../repositories/egreso_repository.dart';

sealed class RegistrarEgresoResultado {}

class RegistrarEgresoExitoso extends RegistrarEgresoResultado {
  RegistrarEgresoExitoso(this.egreso);
  final EgresoData egreso;
}

class RegistrarEgresoMontoInvalido extends RegistrarEgresoResultado {}

class RegistrarEgresoConceptoRequerido extends RegistrarEgresoResultado {}

/// La TDC elegida como origen no existe, no es tarjeta, no está activa,
/// no tiene límite capturado, o el gasto excede su crédito disponible —
/// mismos 4 casos que `validarOrigenTarjeta` ya distingue para
/// Compras/Tiempos Extra, nunca una quinta regla propia.
class RegistrarEgresoTarjetaInvalida extends RegistrarEgresoResultado {
  RegistrarEgresoTarjetaInvalida(this.error, {this.disponible});
  final ErrorOrigenTarjeta error;

  /// Solo poblado cuando [error] es `excedeLimite`.
  final int? disponible;
}

class RegistrarEgresoErrorInesperado extends RegistrarEgresoResultado {
  RegistrarEgresoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Registra un Egreso manual (Etapa 4K.1) — este flujo de captura
/// directa sigue siendo 100% manual; Nómina/Compras generan el suyo
/// propio por su propia vía (`PagoNominaRepositoryImpl`/
/// `CompraRepositoryImpl`), nunca pasando por este use case.
///
/// **Rectificación de producto (Etapa "Origen financiero de Egresos
/// manuales: Cuenta vs. TDC", pedido explícito de Marlon).** Hasta la
/// etapa "origen financiero unificado" este use case afirmaba —también
/// por decisión explícita de entonces— que "Registrar egreso" representa
/// SIEMPRE una salida desde una `CuentaFinanciera` y que un gasto con
/// TDC debía capturarse por Compras o Tiempos Extra. El caso real que
/// tumbó esa premisa: una carga de gasolina de $1,359.98 pagada con la
/// TDC Konfío Empresarial — no es una Compra de inventario ni una
/// cobertura de ausencia, así que no tenía ningún flujo donde caber, y
/// terminó capturada como Egreso manual con `formaPago: 'tarjeta'`
/// (etiqueta descriptiva, sin FK a ninguna tarjeta) descontando dinero
/// de una cuenta bancaria de la que nunca salió. Desde esta etapa el
/// origen financiero es explícito y estructurado
/// ([OrigenFinancieroGasto]), y este use case sí compone
/// `DeudaRepository`.
///
/// Con [OrigenFinancieroCuenta] (o sin origen) el comportamiento es el
/// de siempre: un `Egreso` que reduce el saldo derivado de esa cuenta.
/// Con [OrigenFinancieroTarjeta] el `Egreso` sigue siendo el documento
/// del gasto pero NO mueve caja: la salida real ocurre después, al
/// pagar la tarjeta (`RegistrarPagoDeudaUseCase`). Ambos efectos
/// —`Egreso` + `MovimientoDeuda`— se escriben en la misma transacción
/// (`EgresoRepository.crearConOrigen`, que compone `DeudaRepository`
/// dentro de una sola `_db.transaction` — mismo criterio que
/// `CompraRepositoryImpl`, nunca dos escrituras sueltas encadenadas
/// desde el caso de uso).
class RegistrarEgresoUseCase {
  RegistrarEgresoUseCase(this._repository, this._generarCodigo, this._deudaRepository);

  final EgresoRepository _repository;
  final GenerarCodigoUseCase _generarCodigo;
  final DeudaRepository _deudaRepository;

  Future<RegistrarEgresoResultado> ejecutar({
    required int monto,
    required DateTime fecha,
    String? categoriaFinancieraId,
    String? servicioId,
    String? sucursalId,
    String? areaId,
    String? cuentaCaja,
    OrigenFinancieroGasto? origen,
    required String formaPago,
    String? beneficiario,
    required String concepto,
    String? observaciones,
    String? actorUsuarioId,
  }) async {
    if (monto <= 0) {
      return RegistrarEgresoMontoInvalido();
    }
    if (concepto.trim().isEmpty) {
      return RegistrarEgresoConceptoRequerido();
    }

    if (origen case OrigenFinancieroTarjeta(:final deudaId)) {
      final tarjeta = await _deudaRepository.obtenerPorId(deudaId);
      final validacion = validarOrigenTarjeta(tarjeta: tarjeta, monto: monto);
      if (!validacion.esValida) {
        return RegistrarEgresoTarjetaInvalida(validacion.error!, disponible: validacion.disponible);
      }
    }

    try {
      final codigoResultado = await _generarCodigo.ejecutar('egreso');
      final folioEgreso = codigoResultado.when(ok: (c) => c, failure: (f) => throw StateError(f.message));

      final egreso = await _repository.crearConOrigen(
        folioEgreso: folioEgreso,
        monto: monto,
        fecha: fecha,
        categoriaFinancieraId: categoriaFinancieraId,
        servicioId: servicioId,
        sucursalId: sucursalId,
        areaId: areaId,
        cuentaCaja: cuentaCaja,
        origen: origen,
        formaPago: formaPago,
        beneficiario: beneficiario,
        concepto: concepto.trim(),
        observaciones: observaciones,
        actorUsuarioId: actorUsuarioId,
      );

      return RegistrarEgresoExitoso(egreso);
    } on SaldoInsuficienteException {
      // Un saldo insuficiente NO es un error inesperado: es un rechazo
      // previsto y accionable. Se deja propagar para que la pantalla
      // muestre disponible/requerido/faltante. La transacción ya quedó
      // revertida entera.
      rethrow;
    } catch (e, s) {
      return RegistrarEgresoErrorInesperado(diagnosticoErrorInesperado(e, s, contexto: 'RegistrarEgresoUseCase'));
    }
  }
}
