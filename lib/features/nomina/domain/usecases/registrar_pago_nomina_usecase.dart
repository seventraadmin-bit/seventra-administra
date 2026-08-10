import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/error/result.dart';

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
  RegistrarPagoNominaUseCase(this._pagoNominaRepository, this._nominaRepository, this._generarCodigo);

  final PagoNominaRepository _pagoNominaRepository;
  final NominaRepository _nominaRepository;
  final GenerarCodigoUseCase _generarCodigo;

  Future<RegistrarPagoNominaResultado> ejecutar({
    required String nominaId,
    required DateTime fechaPago,
    required String formaPago,
    String? referencia,
    String? cuentaBancariaOrigen,
    String? observaciones,
    required List<({String nominaEmpleadoId, int monto})> aplicaciones,
    String? actor,
  }) async {
    final nomina = await _nominaRepository.obtenerPorId(nominaId);
    if (nomina == null) return RegistrarPagoNominaNominaNoExiste();
    if (nomina.estatus != 'cerrada') return RegistrarPagoNominaNominaNoCerrada();
    if (aplicaciones.isEmpty) return RegistrarPagoNominaListaVacia();

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
        observaciones: observaciones,
        aplicaciones: aplicaciones,
        actor: actor,
      );
      return RegistrarPagoNominaExitoso(pagoNomina);
    } catch (e) {
      return RegistrarPagoNominaErrorInesperado(e.toString());
    }
  }
}
