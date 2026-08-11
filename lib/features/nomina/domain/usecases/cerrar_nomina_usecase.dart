import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/nomina_repository.dart';
import 'evaluar_renglones_requieren_revision_usecase.dart';

sealed class CerrarNominaResultado {}

class CerrarNominaExitoso extends CerrarNominaResultado {
  CerrarNominaExitoso(this.nomina);
  final NominaData nomina;
}

class CerrarNominaNoExiste extends CerrarNominaResultado {}

class CerrarNominaYaCerrada extends CerrarNominaResultado {}

class CerrarNominaSinEmpleados extends CerrarNominaResultado {}

/// Al menos un renglón tiene `distribucionPendienteRevision` — nunca se
/// cierra con una distribución Fiscal/No fiscal que dejó de sumar el
/// total (Resolución explícita de Marlon).
class CerrarNominaDistribucionPendiente extends CerrarNominaResultado {
  CerrarNominaDistribucionPendiente(this.renglonesPendientes);
  final List<NominaEmpleadoData> renglonesPendientes;
}

/// Al menos un renglón, re-evaluado contra el estado actual de
/// Personal (`EvaluarRenglonesRequierenRevisionUseCase`), se quedó sin
/// cobertura laboral/sueldo pero conserva movimientos manuales o una
/// distribución ya capturada a mano — nunca se cierra sin que el
/// usuario los revise explícitamente (Resolución explícita de Marlon
/// al cerrar la Etapa 6C).
class CerrarNominaRequiereRevision extends CerrarNominaResultado {
  CerrarNominaRequiereRevision(this.renglonesPendientes);
  final List<NominaEmpleadoData> renglonesPendientes;
}

/// Reservado para la frontera de autorización (Etapa 11C) — nunca lo
/// produce el propio caso de uso.
class CerrarNominaErrorInesperado extends CerrarNominaResultado {
  CerrarNominaErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Cierra una Nómina (Etapa 6C) — congela todos los renglones/tramos
/// (ninguna acción posterior los vuelve a tocar, ni
/// `ActualizarNominaDesdePersonalUseCase`, ver el doc comment de
/// `Nomina`). Nunca genera un Egreso ni marca nada como pagado —
/// "Cerrada" significa que el cálculo quedó aprobado, no que el dinero
/// salió; eso es la Etapa 6D (Resolución explícita de Marlon).
class CerrarNominaUseCase {
  CerrarNominaUseCase(this._nominaRepository, this._evaluarRenglonesRequierenRevision);

  final NominaRepository _nominaRepository;
  final EvaluarRenglonesRequierenRevisionUseCase _evaluarRenglonesRequierenRevision;

  Future<CerrarNominaResultado> ejecutar({required String nominaId, String? actorUsuarioId}) async {
    final nomina = await _nominaRepository.obtenerPorId(nominaId);
    if (nomina == null) return CerrarNominaNoExiste();
    if (nomina.estatus != 'borrador') return CerrarNominaYaCerrada();

    final renglones = await _nominaRepository.listarEmpleados(nominaId);
    if (renglones.isEmpty) return CerrarNominaSinEmpleados();

    final requierenRevision = await _evaluarRenglonesRequierenRevision.ejecutar(nominaId);
    if (requierenRevision.isNotEmpty) return CerrarNominaRequiereRevision(requierenRevision);

    final pendientes = renglones.where((r) => r.distribucionPendienteRevision).toList();
    if (pendientes.isNotEmpty) return CerrarNominaDistribucionPendiente(pendientes);

    final cerrada = await _nominaRepository.cerrar(nominaId: nominaId, actorUsuarioId: actorUsuarioId);
    return CerrarNominaExitoso(cerrada);
  }
}
