import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/error/result.dart';
import 'package:riseg_one/features/finanzas/domain/fuente_egreso.dart';
import 'package:riseg_one/features/finanzas/domain/politica_saldo_cuenta.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/cuenta_financiera_repository.dart';

import '../repositories/nomina_repository.dart';
import '../repositories/pago_nomina_repository.dart';

sealed class RegistrarPagoNominaResultado {}

class RegistrarPagoNominaExitoso extends RegistrarPagoNominaResultado {
  RegistrarPagoNominaExitoso(this.pagoNomina);
  final PagoNominaData pagoNomina;
}

class RegistrarPagoNominaNominaNoExiste extends RegistrarPagoNominaResultado {}

/// Solo se puede pagar una Nómina `cerrada` — nunca una `borrador`
/// (Resolución explícita de Marlon: el cálculo debe quedar congelado
/// antes de que se le asocie dinero real).
class RegistrarPagoNominaNominaNoCerrada extends RegistrarPagoNominaResultado {}

class RegistrarPagoNominaListaVacia extends RegistrarPagoNominaResultado {}

class RegistrarPagoNominaRenglonNoPerteneceANomina extends RegistrarPagoNominaResultado {
  RegistrarPagoNominaRenglonNoPerteneceANomina(this.nominaEmpleadoId);
  final String nominaEmpleadoId;
}

class RegistrarPagoNominaMontoInvalido extends RegistrarPagoNominaResultado {
  RegistrarPagoNominaMontoInvalido(this.nominaEmpleadoId);
  final String nominaEmpleadoId;
}

/// `monto` excede el saldo pendiente de pago de ese renglón — nunca se
/// paga más de lo que ese Empleado todavía debe cobrar de esta Nómina.
class RegistrarPagoNominaSobrepago extends RegistrarPagoNominaResultado {
  RegistrarPagoNominaSobrepago(this.nominaEmpleadoId, this.saldoDisponible);
  final String nominaEmpleadoId;
  final int saldoDisponible;
}

/// No se indicó de qué CuentaFinanciera sale el dinero.
///
/// Un pago de Nómina mueve dinero real: sin cuenta, el `Egreso` nace
/// sin origen y **ningún saldo baja**, así que el sistema afirmaría que
/// a los empleados se les pagó con dinero que nunca salió de ningún
/// lado. `cuentaBancariaOrigen` no sustituye a esto: es texto
/// administrativo (el banco del empleado, una referencia), no una
/// entidad con saldo.
class RegistrarPagoNominaCuentaFinancieraRequerida extends RegistrarPagoNominaResultado {}

/// La cuenta indicada no existe, o está desactivada. Se rechaza en vez
/// de guardar una referencia rota o pagar desde una cuenta que la
/// empresa ya dio de baja.
class RegistrarPagoNominaCuentaFinancieraInvalida extends RegistrarPagoNominaResultado {
  RegistrarPagoNominaCuentaFinancieraInvalida(this.cuentaFinancieraId);
  final String cuentaFinancieraId;
}

/// La cuenta no alcanza. Lleva disponible/requerido/faltante listos
/// para la pantalla, que es lo que Marlon pidió ver: "Disponible,
/// Importe a cubrir, Faltan".
class RegistrarPagoNominaSaldoInsuficiente extends RegistrarPagoNominaResultado {
  RegistrarPagoNominaSaldoInsuficiente(this.detalle);
  final SaldoInsuficiente detalle;
}

/// La fecha del pago es anterior al saldo inicial de alguna cuenta:
/// ese movimiento no se sumaría al saldo y el dinero saldría sin
/// verse.
class RegistrarPagoNominaFechaAnteriorAlSaldoInicial extends RegistrarPagoNominaResultado {
  RegistrarPagoNominaFechaAnteriorAlSaldoInicial(this.detalle);
  final FechaAnteriorAlSaldoInicial detalle;
}

/// El reparto entre cuentas no cuadra con el total del pago.
class RegistrarPagoNominaDistribucionInvalida extends RegistrarPagoNominaResultado {
  RegistrarPagoNominaDistribucionInvalida(this.mensaje);
  final String mensaje;
}

class RegistrarPagoNominaErrorInesperado extends RegistrarPagoNominaResultado {
  RegistrarPagoNominaErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Registra un lote real de pago de Nómina (Etapa 6D) — "hoy salieron
/// $X hacia estos empleados". Cubre uno o varios renglones a la vez;
/// una Nómina puede recibir varios de estos lotes a lo largo del
/// tiempo (pagos parciales, fechas distintas por grupo de empleados).
/// Genera el `Egreso` automáticamente (`PagoNominaRepository.crear`) —
/// nunca dos Egresos para el mismo lote, sin importar si algún renglón
/// tiene distribución Fiscal/No fiscal.
class RegistrarPagoNominaUseCase {
  RegistrarPagoNominaUseCase(
    this._pagoNominaRepository,
    this._nominaRepository,
    this._generarCodigo,
    this._cuentaFinancieraRepository,
  );

  final PagoNominaRepository _pagoNominaRepository;
  final NominaRepository _nominaRepository;
  final GenerarCodigoUseCase _generarCodigo;

  /// Sólo para comprobar que la cuenta de origen existe y sigue activa.
  final CuentaFinancieraRepository _cuentaFinancieraRepository;

  Future<RegistrarPagoNominaResultado> ejecutar({
    required String nominaId,
    required DateTime fechaPago,
    required String formaPago,
    String? referencia,
    String? cuentaBancariaOrigen,
    String? cuentaFinancieraId,

    /// Reparto explícito entre varias cuentas (la suma debe ser
    /// exactamente el total del pago). Sin él, se paga todo desde
    /// [cuentaFinancieraId].
    List<FuenteEgreso>? fuentes,
    String? observaciones,
    required List<({String nominaEmpleadoId, int monto})> aplicaciones,
    String? actorUsuarioId,
  }) async {
    final nomina = await _nominaRepository.obtenerPorId(nominaId);
    if (nomina == null) return RegistrarPagoNominaNominaNoExiste();
    if (nomina.estatus != 'cerrada') return RegistrarPagoNominaNominaNoCerrada();
    if (aplicaciones.isEmpty) return RegistrarPagoNominaListaVacia();

    // De dónde sale el dinero, ANTES de tocar nada. Se valida aquí y no
    // en el diálogo para que ninguna pantalla futura —ni una llamada
    // directa al caso de uso— pueda crear un pago vigente cuyo Egreso
    // no descuente de ninguna cuenta.
    final idCuenta = (cuentaFinancieraId ?? '').trim();
    if (idCuenta.isEmpty) return RegistrarPagoNominaCuentaFinancieraRequerida();
    final cuenta = await _cuentaFinancieraRepository.obtenerPorId(idCuenta);
    if (cuenta == null || cuenta.cicloVidaRegistro != 'activo') {
      return RegistrarPagoNominaCuentaFinancieraInvalida(idCuenta);
    }

    final renglones = await _nominaRepository.listarEmpleados(nominaId);
    final renglonesPorId = {for (final r in renglones) r.id: r};

    for (final ap in aplicaciones) {
      if (!renglonesPorId.containsKey(ap.nominaEmpleadoId)) {
        return RegistrarPagoNominaRenglonNoPerteneceANomina(ap.nominaEmpleadoId);
      }
      if (ap.monto <= 0) return RegistrarPagoNominaMontoInvalido(ap.nominaEmpleadoId);

      final saldoDisponible = await _pagoNominaRepository.saldoPendientePago(ap.nominaEmpleadoId);
      if (ap.monto > saldoDisponible) {
        return RegistrarPagoNominaSobrepago(ap.nominaEmpleadoId, saldoDisponible);
      }
    }

    try {
      final folioResultado = await _generarCodigo.ejecutar('pago_nomina');
      final String folio;
      switch (folioResultado) {
        case Ok<String>(value: final v):
          folio = v;
        case Err<String>(failure: final f):
          return RegistrarPagoNominaErrorInesperado(f.message);
      }

      final pagoNomina = await _pagoNominaRepository.crear(
        folioPagoNomina: folio,
        nominaId: nominaId,
        fechaPago: fechaPago,
        formaPago: formaPago,
        referencia: referencia,
        cuentaBancariaOrigen: cuentaBancariaOrigen,
        cuentaFinancieraId: idCuenta,
        fuentes: fuentes,
        observaciones: observaciones,
        aplicaciones: aplicaciones,
        actorUsuarioId: actorUsuarioId,
      );
      return RegistrarPagoNominaExitoso(pagoNomina);
    } on SaldoInsuficienteException catch (e) {
      // La política abortó la transacción entera: no quedó ni el
      // PagoNomina, ni el Egreso, ni una sola aplicación.
      return switch (e.veredicto) {
        SaldoInsuficiente() => RegistrarPagoNominaSaldoInsuficiente(e.veredicto as SaldoInsuficiente),
        FechaAnteriorAlSaldoInicial() =>
          RegistrarPagoNominaFechaAnteriorAlSaldoInicial(e.veredicto as FechaAnteriorAlSaldoInicial),
        CuentaNoDisponible() => RegistrarPagoNominaCuentaFinancieraInvalida(cuentaFinancieraId ?? ''),
        SaldoSuficiente() => RegistrarPagoNominaErrorInesperado(e.toString()),
      };
    } on DistribucionInvalidaException catch (e) {
      return RegistrarPagoNominaDistribucionInvalida(e.mensaje);
    } catch (e) {
      return RegistrarPagoNominaErrorInesperado(e.toString());
    }
  }
}
