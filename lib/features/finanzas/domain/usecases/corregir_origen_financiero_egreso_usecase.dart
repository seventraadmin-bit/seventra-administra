import 'package:riseg_one/features/finanzas/domain/politica_saldo_cuenta.dart';
import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/cuenta_financiera_repository.dart';
import '../repositories/egreso_repository.dart';
import 'obtener_origen_automatico_egreso_usecase.dart';

sealed class CorregirOrigenFinancieroEgresoResultado {}

class CorregirOrigenFinancieroEgresoExitoso extends CorregirOrigenFinancieroEgresoResultado {
  CorregirOrigenFinancieroEgresoExitoso(this.egreso);
  final EgresoData egreso;
}

class CorregirOrigenFinancieroEgresoNoExiste extends CorregirOrigenFinancieroEgresoResultado {}

class CorregirOrigenFinancieroEgresoMotivoRequerido extends CorregirOrigenFinancieroEgresoResultado {}

/// La cuenta nueva no existe o está desactivada.
class CorregirOrigenFinancieroEgresoCuentaInvalida extends CorregirOrigenFinancieroEgresoResultado {}

/// Esta herramienta nunca deja un Egreso vigente sin origen: sirve para
/// `null → cuenta` y `cuenta A → cuenta B`, jamás para el camino
/// inverso. La arquitectura avanza hacia más integridad, no de vuelta.
class CorregirOrigenFinancieroEgresoNoPuedeQuedarSinCuenta
    extends CorregirOrigenFinancieroEgresoResultado {}

/// La cuenta elegida ya es la que tiene: no hay corrección que hacer, y
/// escribirla igual dejaría un asiento de auditoría que no explica
/// ningún cambio.
class CorregirOrigenFinancieroEgresoSinCambio extends CorregirOrigenFinancieroEgresoResultado {}

/// Un Egreso cancelado ya no afecta ningún saldo (el cálculo sólo suma
/// los `registrado`), así que asociarle una cuenta no corregiría nada:
/// sólo ataría un movimiento sin efecto a una cuenta real.
class CorregirOrigenFinancieroEgresoCancelado extends CorregirOrigenFinancieroEgresoResultado {}

/// Un Egreso pagado con tarjeta no sale de una cuenta bancaria: su
/// salida de efectivo ocurre al pagar la tarjeta. Reasignarle una
/// cuenta convertiría un cargo a crédito en una salida de banco y
/// contaría el gasto dos veces.
class CorregirOrigenFinancieroEgresoFinanciadoConTarjeta
    extends CorregirOrigenFinancieroEgresoResultado {}

/// El origen guarda **su propia copia** de la cuenta, así que corregir
/// sólo el Egreso los dejaría diciendo cosas distintas. Se corrige
/// desde el módulo de origen.
class CorregirOrigenFinancieroEgresoOrigenNoAdmitido
    extends CorregirOrigenFinancieroEgresoResultado {
  CorregirOrigenFinancieroEgresoOrigenNoAdmitido(this.detalle);
  final String detalle;
}

class CorregirOrigenFinancieroEgresoErrorInesperado extends CorregirOrigenFinancieroEgresoResultado {
  CorregirOrigenFinancieroEgresoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Herramienta de contingencia del Usuario Maestro: corrige **sólo** de
/// qué `CuentaFinanciera` salió un Egreso ya registrado, incluso si lo
/// generó otro módulo (Maestro-only vía `exigirMaestro` en la fachada,
/// nunca aquí: este caso de uso es puro).
///
/// **Por qué existe.** El hueco de integridad de Nómina dejó Egresos
/// reales con `cuentaFinancieraId = null`: el dinero salió, pero ningún
/// saldo bajó. Cancelar y recrear el Egreso falsearía la historia y
/// rompería la referencia del módulo origen; corregir la asociación no.
///
/// **Qué NO toca, a propósito:** monto, fecha, concepto, categoría,
/// forma de pago, beneficiario, el origen funcional ni la referencia al
/// registro de origen. Todo eso se corrige desde su módulo. Aquí sólo
/// cambia *dónde ocurrió la salida de efectivo*, y el saldo se mueve
/// solo porque se deriva de la asociación vigente del mismo Egreso —
/// no se inventa ningún movimiento compensatorio.
///
/// **Orígenes admitidos.** Todos aquellos en los que el `Egreso` es la
/// ÚNICA fuente de la cuenta: manual, Nómina, Compra, Tiempo extra,
/// Vehículos, Telefonía y pago de Deuda. Se auditó tabla por tabla:
/// `PagoNomina`, `Compra`, `TiempoExtra`, `VehiculoEvento` y la recarga
/// de Telefonía **no** guardan `cuentaFinancieraId`, así que no hay
/// copia que pueda divergir.
///
/// **Orígenes bloqueados** (guardan su propia copia de la cuenta, ver
/// [CorregirOrigenFinancieroEgresoOrigenNoAdmitido]): Servicio Eventual
/// —`ServicioEventualCobertura`/`Costo.cuentaFinancieraId`— y Descuento
/// programado —`DescuentoProgramadoEmpleado.cuentaFinancieraId`—.
class CorregirOrigenFinancieroEgresoUseCase {
  CorregirOrigenFinancieroEgresoUseCase(
    this._egresoRepository,
    this._cuentaFinancieraRepository,
    this._obtenerOrigen,
  );

  final EgresoRepository _egresoRepository;
  final CuentaFinancieraRepository _cuentaFinancieraRepository;
  final ObtenerOrigenAutomaticoEgresoUseCase _obtenerOrigen;

  Future<CorregirOrigenFinancieroEgresoResultado> ejecutar({
    required String egresoId,
    required String? cuentaFinancieraId,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    final motivoLimpio = motivo.trim();
    if (motivoLimpio.isEmpty) return CorregirOrigenFinancieroEgresoMotivoRequerido();

    final egreso = await _egresoRepository.obtenerPorId(egresoId);
    if (egreso == null) return CorregirOrigenFinancieroEgresoNoExiste();
    if (egreso.estatus != 'registrado') return CorregirOrigenFinancieroEgresoCancelado();
    if (egreso.deudaId != null) return CorregirOrigenFinancieroEgresoFinanciadoConTarjeta();

    final idNueva = (cuentaFinancieraId ?? '').trim();
    if (idNueva.isEmpty) return CorregirOrigenFinancieroEgresoNoPuedeQuedarSinCuenta();
    if (idNueva == egreso.cuentaFinancieraId) return CorregirOrigenFinancieroEgresoSinCambio();

    final cuenta = await _cuentaFinancieraRepository.obtenerPorId(idNueva);
    if (cuenta == null || cuenta.cicloVidaRegistro != 'activo') {
      return CorregirOrigenFinancieroEgresoCuentaInvalida();
    }

    // El origen decide si este Egreso es corregible desde aquí.
    final origen = await _obtenerOrigen.ejecutar(egresoId);
    final bloqueo = _motivoDeBloqueo(origen);
    if (bloqueo != null) return CorregirOrigenFinancieroEgresoOrigenNoAdmitido(bloqueo);

    try {
      // `EgresoRepository.corregir` ya escribe la fila y su asiento de
      // `EgresoEvento` con el diff en UNA transacción: no se duplica
      // ni la escritura ni la bitácora.
      final actualizado = await _egresoRepository.corregir(
        egresoId: egresoId,
        cuentaFinancieraId: idNueva,
        motivo: 'Corrección de origen financiero (Maestro): $motivoLimpio',
        actorUsuarioId: actorUsuarioId,
      );
      return CorregirOrigenFinancieroEgresoExitoso(actualizado);
    } on SaldoInsuficienteException {
      // Corregir también puede quedarse sin saldo (subir el importe, o
      // mover la salida a otra cuenta). No es un error inesperado: se
      // deja propagar para que la pantalla muestre los tres números.
      rethrow;
    } catch (e) {
      return CorregirOrigenFinancieroEgresoErrorInesperado(e.toString());
    }
  }

  /// `null` cuando el origen admite la corrección desde Finanzas.
  String? _motivoDeBloqueo(OrigenAutomaticoEgreso? origen) {
    return switch (origen) {
      // Guardan su propia copia de la cuenta: corregir sólo el Egreso
      // los dejaría divergentes.
      OrigenAutomaticoEgresoServicioEventual() =>
        'Este egreso pertenece a un Servicio Eventual, que guarda su propia cuenta de pago. '
            'Corrígelo desde el expediente del eventual.',
      OrigenAutomaticoEgresoDescuentoProgramado() =>
        'Este egreso pertenece a un descuento programado, que guarda su propia cuenta de origen. '
            'Corrígelo desde el expediente del descuento.',
      // El resto —manual (null), Nómina, Compra, Tiempo extra,
      // Vehículos, Telefonía y pago de Deuda— sólo guardan la cuenta en
      // el propio Egreso.
      _ => null,
    };
  }
}
