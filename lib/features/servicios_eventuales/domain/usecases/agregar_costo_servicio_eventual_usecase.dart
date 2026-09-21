import 'package:riseg_one/core/database/app_database.dart';

import '../../data/tables/servicio_eventual_table.dart';
import '../repositories/servicio_eventual_repository.dart';

sealed class AgregarCostoServicioEventualResultado {}

class AgregarCostoServicioEventualExitoso extends AgregarCostoServicioEventualResultado {
  AgregarCostoServicioEventualExitoso(this.costo);
  final ServicioEventualCostoData costo;
}

class AgregarCostoServicioEventualNoExiste extends AgregarCostoServicioEventualResultado {}

class AgregarCostoServicioEventualCancelado extends AgregarCostoServicioEventualResultado {}

class AgregarCostoServicioEventualConceptoRequerido extends AgregarCostoServicioEventualResultado {}

class AgregarCostoServicioEventualMontoInvalido extends AgregarCostoServicioEventualResultado {}

class AgregarCostoServicioEventualErrorInesperado extends AgregarCostoServicioEventualResultado {
  AgregarCostoServicioEventualErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Todo lo que cuesta el evento y no es pago a una persona: traslados,
/// alimentos, equipo rentado.
///
/// El concepto es **texto libre a propósito**: un eventual es por
/// definición irregular y un catálogo cerrado obligaría a forzar cada
/// gasto real dentro de una categoría que no le corresponde. Igual que
/// una cobertura, nace `programado` y sin origen financiero.
class AgregarCostoServicioEventualUseCase {
  AgregarCostoServicioEventualUseCase(this._repository);

  final ServicioEventualRepository _repository;

  Future<AgregarCostoServicioEventualResultado> ejecutar({
    required String servicioEventualId,
    required String concepto,
    required int monto,
    required DateTime fecha,
    String? observaciones,
    String? actorUsuarioId,
  }) async {
    final eventual = await _repository.obtenerPorId(servicioEventualId);
    if (eventual == null) return AgregarCostoServicioEventualNoExiste();
    if (eventual.estatus == EstatusServicioEventual.cancelado.name) {
      return AgregarCostoServicioEventualCancelado();
    }

    final conceptoLimpio = concepto.trim();
    if (conceptoLimpio.isEmpty) return AgregarCostoServicioEventualConceptoRequerido();
    if (monto <= 0) return AgregarCostoServicioEventualMontoInvalido();

    try {
      final costo = await _repository.agregarCosto(
        servicioEventualId: servicioEventualId,
        concepto: conceptoLimpio,
        monto: monto,
        fecha: fecha,
        observaciones: observaciones?.trim().isEmpty ?? true ? null : observaciones!.trim(),
        actorUsuarioId: actorUsuarioId,
      );
      return AgregarCostoServicioEventualExitoso(costo);
    } catch (e) {
      return AgregarCostoServicioEventualErrorInesperado(e.toString());
    }
  }
}
