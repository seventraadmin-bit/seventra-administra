import 'package:riseg_one/core/database/app_database.dart';

import '../../data/tables/servicio_eventual_table.dart';
import '../repositories/servicio_eventual_repository.dart';

sealed class CorregirCoberturaServicioEventualResultado {}

class CorregirCoberturaServicioEventualExitoso extends CorregirCoberturaServicioEventualResultado {
  CorregirCoberturaServicioEventualExitoso(this.cobertura);
  final ServicioEventualCoberturaData cobertura;
}

class CorregirCoberturaServicioEventualNoExiste extends CorregirCoberturaServicioEventualResultado {}

class CorregirCoberturaServicioEventualMotivoRequerido extends CorregirCoberturaServicioEventualResultado {}

class CorregirCoberturaServicioEventualHorarioInvalido extends CorregirCoberturaServicioEventualResultado {}

class CorregirCoberturaServicioEventualImporteInvalido extends CorregirCoberturaServicioEventualResultado {}

/// Una cobertura cancelada es historia: se consulta, no se corrige.
class CorregirCoberturaServicioEventualCancelada extends CorregirCoberturaServicioEventualResultado {}

/// Ya se pagó: el importe corregido dejaría de coincidir con el Egreso
/// o el cargo emitido. Primero se revierte el pago, luego se corrige,
/// luego se vuelve a pagar — cada paso con su propia huella.
class CorregirCoberturaServicioEventualPagada extends CorregirCoberturaServicioEventualResultado {}

class CorregirCoberturaServicioEventualErrorInesperado extends CorregirCoberturaServicioEventualResultado {
  CorregirCoberturaServicioEventualErrorInesperado(this.mensaje);
  final String mensaje;
}

class CorregirCoberturaServicioEventualUseCase {
  CorregirCoberturaServicioEventualUseCase(this._repository);

  final ServicioEventualRepository _repository;

  Future<CorregirCoberturaServicioEventualResultado> ejecutar({
    required String coberturaId,
    DateTime? fecha,
    int? horaInicioMinutos,
    int? horaFinMinutos,
    String? descripcionHorario,
    int? importeAcordado,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    final motivoLimpio = motivo.trim();
    if (motivoLimpio.isEmpty) return CorregirCoberturaServicioEventualMotivoRequerido();

    final actual = await _repository.obtenerCobertura(coberturaId);
    if (actual == null) return CorregirCoberturaServicioEventualNoExiste();
    if (actual.estatus == EstatusEjecucionServicioEventual.cancelada.name) {
      return CorregirCoberturaServicioEventualCancelada();
    }
    if (actual.estatus == EstatusEjecucionServicioEventual.pagada.name) {
      return CorregirCoberturaServicioEventualPagada();
    }

    // Igual que en el eventual: el horario resultante es lo que
    // importa, no solo lo que viene en la llamada.
    final inicio = horaInicioMinutos ?? actual.horaInicioMinutos;
    final fin = horaFinMinutos ?? actual.horaFinMinutos;
    if (!_horaValida(inicio) || !_horaValida(fin) || inicio == fin) {
      return CorregirCoberturaServicioEventualHorarioInvalido();
    }
    if (importeAcordado != null && importeAcordado <= 0) {
      return CorregirCoberturaServicioEventualImporteInvalido();
    }

    try {
      final cobertura = await _repository.corregirCobertura(
        coberturaId: coberturaId,
        fecha: fecha,
        horaInicioMinutos: horaInicioMinutos,
        horaFinMinutos: horaFinMinutos,
        descripcionHorario: descripcionHorario?.trim().isEmpty ?? true ? null : descripcionHorario!.trim(),
        importeAcordado: importeAcordado,
        motivo: motivoLimpio,
        actorUsuarioId: actorUsuarioId,
      );
      return CorregirCoberturaServicioEventualExitoso(cobertura);
    } catch (e) {
      return CorregirCoberturaServicioEventualErrorInesperado(e.toString());
    }
  }
}

bool _horaValida(int minutos) => minutos >= 0 && minutos <= 1439;
