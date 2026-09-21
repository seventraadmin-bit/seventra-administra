import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/complemento_pago_repository.dart';

import '../../data/tables/servicio_eventual_table.dart';
import '../repositories/servicio_eventual_documento_fiscal_repository.dart';
import '../repositories/servicio_eventual_repository.dart';

sealed class CancelarServicioEventualResultado {}

class CancelarServicioEventualExitoso extends CancelarServicioEventualResultado {
  CancelarServicioEventualExitoso(this.servicioEventual);
  final ServicioEventualData servicioEventual;
}

class CancelarServicioEventualNoExiste extends CancelarServicioEventualResultado {}

class CancelarServicioEventualMotivoRequerido extends CancelarServicioEventualResultado {}

class CancelarServicioEventualYaCancelado extends CancelarServicioEventualResultado {}

/// Hay un CFDI vigente por esta venta.
///
/// Anular la venta en automático obligaría a cancelar el CFDI en
/// automático, y RISEG ONE nunca hace eso: no timbra, así que tampoco
/// puede cancelar ante el SAT. Mismo criterio exacto que
/// `CancelarPagoUseCase` con el Complemento y que
/// `EliminarPagoFisicamenteUseCase`: se bloquea y se dice qué hay que
/// resolver primero, nunca una cascada fiscal silenciosa.
class CancelarServicioEventualDocumentoFiscalVigente extends CancelarServicioEventualResultado {
  CancelarServicioEventualDocumentoFiscalVigente(this.folio);
  final String folio;
}

/// Alguno de los pagos de esta venta tiene un Complemento de pago
/// vigente. Mismo bloqueo, misma razón.
class CancelarServicioEventualComplementoVigente extends CancelarServicioEventualResultado {
  CancelarServicioEventualComplementoVigente(this.uuid);
  final String uuid;
}

class CancelarServicioEventualErrorInesperado extends CancelarServicioEventualResultado {
  CancelarServicioEventualErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Lo que va a pasar si se confirma, calculado ANTES de confirmar.
///
/// Existe porque la prueba manual encontró el caso opuesto: el evento
/// se cancelaba y el dinero cobrado seguía vivo sin que la pantalla lo
/// dijera. Ahora la pantalla puede enumerar exactamente qué se revierte
/// y qué permanece. Sólo lectura: construirlo no cambia nada.
class ResumenAnulacionServicioEventual {
  const ResumenAnulacionServicioEventual({
    required this.cuenta,
    required this.cobros,
    required this.totales,
    required this.coberturasPorCancelar,
    required this.costosPorCancelar,
    this.documentoFiscalVigente,
    this.complementoVigenteUuid,
  });

  final CuentaPorCobrarData? cuenta;

  /// Cobros vigentes de la venta. Los exclusivos se revierten enteros;
  /// de los compartidos sólo se suelta la aplicación.
  final List<CobroDeVentaEventual> cobros;

  final TotalesServicioEventual totales;

  final int coberturasPorCancelar;
  final int costosPorCancelar;

  final ServicioEventualDocumentoFiscalData? documentoFiscalVigente;
  final String? complementoVigenteUuid;

  /// Lo que vuelve a la cuenta bancaria: sólo los pagos que se cancelan
  /// enteros. La aplicación suelta de un pago compartido no saca dinero
  /// del banco, porque ese depósito de verdad ocurrió.
  int get montoQueVuelve =>
      cobros.where((c) => c.exclusivoDeEstaVenta).fold(0, (suma, c) => suma + c.pago.montoTotal);

  /// Lo aplicado a esta venta que deja de estar aplicado, sin salir del
  /// banco — queda disponible para aplicarse a otra cuenta.
  int get montoQueSeDesaplica =>
      cobros.where((c) => !c.exclusivoDeEstaVenta).fold(0, (suma, c) => suma + c.monto);

  /// Gasto real ya ejecutado. **Permanece**: ese dinero salió de verdad.
  int get gastoQuePermanece => totales.costoPagado;

  /// Nada que revertir del lado del dinero cobrado.
  bool get sinCobros => cobros.isEmpty;

  /// Si es `true`, la anulación no puede ejecutarse hasta resolver lo
  /// fiscal por su propio flujo.
  bool get bloqueada => documentoFiscalVigente != null || complementoVigenteUuid != null;
}

/// Anula la venta de un Servicio Eventual.
///
/// **Cancelar el evento es anular la operación completa** (decisión de
/// Marlon en la validación operativa): el hecho comercial deja de
/// existir, así que no puede quedar ni saldo por cobrar ni dinero
/// cobrado por él. En una sola transacción se revierte la cadena
/// `Pago → AplicacionPago → Ingreso → saldo de la cuenta`, se cancela
/// la Cuenta por cobrar y se cancela el evento con todo lo que todavía
/// no ocurría.
///
/// **Lo que NO revierte, a propósito:**
///
///  * Las coberturas y los costos **ya pagados**. Si dos personas
///    trabajaron el evento y ya se les pagó, ese Egreso es un gasto
///    real; que el cliente ya no pague no se lo quita a nadie.
///    Revertirlo es una decisión aparte (`RevertirPagoCobertura...`).
///  * El CFDI y el Complemento. RISEG ONE no timbra y por lo tanto no
///    cancela ante el SAT: si hay uno vigente, **bloquea** y dice cuál
///    hay que resolver primero.
///  * Los pagos compartidos con otras Cuentas por cobrar: de ésos sólo
///    se suelta la aplicación a esta venta.
class CancelarServicioEventualUseCase {
  CancelarServicioEventualUseCase(
    this._repository,
    this._documentoFiscalRepository,
    this._complementoPagoRepository,
  );

  final ServicioEventualRepository _repository;
  final ServicioEventualDocumentoFiscalRepository _documentoFiscalRepository;
  final ComplementoPagoRepository _complementoPagoRepository;

  /// La previsualización que la pantalla enseña antes de pedir
  /// confirmación. No escribe nada.
  Future<ResumenAnulacionServicioEventual> previsualizar(String servicioEventualId) async {
    final cuenta = await _repository.obtenerCuentaPorCobrar(servicioEventualId);
    final cobros = await _repository.cobrosDeLaVenta(servicioEventualId);
    final totales = (await _repository.totalesPorEventual([servicioEventualId]))[servicioEventualId] ??
        const TotalesServicioEventual();

    final documento = await _documentoFiscalRepository.obtenerVigente(servicioEventualId);
    final complemento = await _complementoVigenteDe(cobros);

    final coberturas = await _repository.listarCoberturas(servicioEventualId);
    final costos = await _repository.listarCostos(servicioEventualId);
    final programada = EstatusEjecucionServicioEventual.programada.name;

    return ResumenAnulacionServicioEventual(
      cuenta: cuenta,
      cobros: cobros,
      totales: totales,
      coberturasPorCancelar: coberturas.where((c) => c.estatus == programada).length,
      costosPorCancelar: costos.where((c) => c.estatus == programada).length,
      documentoFiscalVigente: documento,
      complementoVigenteUuid: complemento,
    );
  }

  Future<CancelarServicioEventualResultado> ejecutar({
    required String servicioEventualId,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    final motivoLimpio = motivo.trim();
    if (motivoLimpio.isEmpty) return CancelarServicioEventualMotivoRequerido();

    final actual = await _repository.obtenerPorId(servicioEventualId);
    if (actual == null) return CancelarServicioEventualNoExiste();
    if (actual.estatus == EstatusServicioEventual.cancelado.name) {
      return CancelarServicioEventualYaCancelado();
    }

    // Los bloqueos fiscales van ANTES de tocar nada: si esto no se
    // puede anular con seguridad, no se anula a medias.
    final documento = await _documentoFiscalRepository.obtenerVigente(servicioEventualId);
    if (documento != null) {
      return CancelarServicioEventualDocumentoFiscalVigente(documento.folio);
    }
    final cobros = await _repository.cobrosDeLaVenta(servicioEventualId);
    final complemento = await _complementoVigenteDe(cobros);
    if (complemento != null) return CancelarServicioEventualComplementoVigente(complemento);

    try {
      final eventual = await _repository.anularVenta(
        servicioEventualId: servicioEventualId,
        motivo: motivoLimpio,
        actorUsuarioId: actorUsuarioId,
      );
      return CancelarServicioEventualExitoso(eventual);
    } catch (e) {
      return CancelarServicioEventualErrorInesperado(e.toString());
    }
  }

  /// El UUID del primer Complemento vigente entre los pagos de la
  /// venta, o `null`. Sólo el vigente cuenta: uno cancelado ya no
  /// documenta nada (mismo criterio que `CancelarPagoUseCase`).
  Future<String?> _complementoVigenteDe(List<CobroDeVentaEventual> cobros) async {
    for (final cobro in cobros) {
      final complemento = await _complementoPagoRepository.obtenerVigentePorPagoId(cobro.pago.id);
      if (complemento != null) return complemento.uuid;
    }
    return null;
  }
}
