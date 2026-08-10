import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/nomina_repository.dart';

sealed class ActualizarDistribucionNominaResultado {}

class ActualizarDistribucionNominaExitoso extends ActualizarDistribucionNominaResultado {
  ActualizarDistribucionNominaExitoso(this.renglon);
  final NominaEmpleadoData renglon;
}

class ActualizarDistribucionNominaNoExiste extends ActualizarDistribucionNominaResultado {}

class ActualizarDistribucionNominaNominaCerrada extends ActualizarDistribucionNominaResultado {}

class ActualizarDistribucionNominaValorInvalido extends ActualizarDistribucionNominaResultado {}

/// Fiscal + No fiscal no suman el total a pagar del renglón.
class ActualizarDistribucionNominaNoBalancea extends ActualizarDistribucionNominaResultado {}

/// Captura la distribución Fiscal/No fiscal de un renglón de Nómina
/// (Etapa 6C) — una sola Nómina, nunca dos separadas (Resolución
/// explícita de Marlon); ambos montos deben sumar exactamente el total
/// a pagar del renglón, siempre. Marca `distribucionModificadaManualmente`
/// y limpia `distribucionPendienteRevision` — el usuario ya resolvió lo
/// que estuviera pendiente.
class ActualizarDistribucionNominaUseCase {
  ActualizarDistribucionNominaUseCase(this._nominaRepository);

  final NominaRepository _nominaRepository;

  Future<ActualizarDistribucionNominaResultado> ejecutar({
    required String nominaEmpleadoId,
    required int montoFiscal,
    required int montoNoFiscal,
  }) async {
    final renglon = await _nominaRepository.obtenerEmpleado(nominaEmpleadoId);
    if (renglon == null) return ActualizarDistribucionNominaNoExiste();

    final nomina = await _nominaRepository.obtenerPorId(renglon.nominaId);
    if (nomina == null || nomina.estatus != 'borrador') return ActualizarDistribucionNominaNominaCerrada();

    if (montoFiscal < 0 || montoNoFiscal < 0) return ActualizarDistribucionNominaValorInvalido();
    if (montoFiscal + montoNoFiscal != renglon.totalAPagar) return ActualizarDistribucionNominaNoBalancea();

    final actualizado = await _nominaRepository.actualizarDistribucion(
      nominaEmpleadoId: nominaEmpleadoId,
      montoFiscal: montoFiscal,
      montoNoFiscal: montoNoFiscal,
    );
    await _nominaRepository.registrarEvento(
      nominaId: renglon.nominaId,
      nominaEmpleadoId: nominaEmpleadoId,
      tipoEvento: 'distribucionModificada',
    );
    return ActualizarDistribucionNominaExitoso(actualizado);
  }
}
