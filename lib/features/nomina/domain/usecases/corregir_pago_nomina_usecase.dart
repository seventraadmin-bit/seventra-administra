import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/pago_nomina_repository.dart';

sealed class CorregirPagoNominaResultado {}

class CorregirPagoNominaExitoso extends CorregirPagoNominaResultado {
  CorregirPagoNominaExitoso(this.pagoNomina);
  final PagoNominaData pagoNomina;
}

class CorregirPagoNominaNoExiste extends CorregirPagoNominaResultado {}

class CorregirPagoNominaCancelado extends CorregirPagoNominaResultado {}

class CorregirPagoNominaErrorInesperado extends CorregirPagoNominaResultado {
  CorregirPagoNominaErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Corrige metadatos administrativos de un `PagoNomina` — nunca montos
/// (mismo límite que `CorregirPagoUseCase`: un monto incorrecto se
/// cancela y se vuelve a registrar, nunca se edita).
class CorregirPagoNominaUseCase {
  CorregirPagoNominaUseCase(this._repository);

  final PagoNominaRepository _repository;

  Future<CorregirPagoNominaResultado> ejecutar({
    required String pagoNominaId,
    DateTime? fechaPago,
    String? formaPago,
    String? referencia,
    String? cuentaBancariaOrigen,
    String? observaciones,
    required String motivo,
    String? actor,
  }) async {
    final pagoNomina = await _repository.obtenerPorId(pagoNominaId);
    if (pagoNomina == null) return CorregirPagoNominaNoExiste();
    if (pagoNomina.estatus == 'cancelado') return CorregirPagoNominaCancelado();

    try {
      final actualizado = await _repository.corregir(
        pagoNominaId: pagoNominaId,
        fechaPago: fechaPago,
        formaPago: formaPago,
        referencia: referencia,
        cuentaBancariaOrigen: cuentaBancariaOrigen,
        observaciones: observaciones,
        motivo: motivo,
        actor: actor,
      );
      return CorregirPagoNominaExitoso(actualizado);
    } catch (e) {
      return CorregirPagoNominaErrorInesperado(e.toString());
    }
  }
}
