import 'package:riseg_one/core/auditoria/diff_evento.dart';
import 'package:riseg_one/core/database/app_database.dart';

import '../../data/tables/linea_telefonica_table.dart';
import '../../data/tables/recarga_linea_telefonica_table.dart';
import '../repositories/linea_telefonica_repository.dart';
import '../repositories/recarga_linea_telefonica_repository.dart';

sealed class CancelarRecargaLineaTelefonicaResultado {}

class CancelarRecargaLineaTelefonicaExitoso extends CancelarRecargaLineaTelefonicaResultado {
  CancelarRecargaLineaTelefonicaExitoso(this.recarga);
  final RecargaLineaTelefonicaData recarga;
}

class CancelarRecargaLineaTelefonicaNoExiste extends CancelarRecargaLineaTelefonicaResultado {}

/// Ya estaba anulada — nunca se ejecuta una segunda anulación, ni se
/// escribe un segundo evento.
class CancelarRecargaLineaTelefonicaYaCancelada extends CancelarRecargaLineaTelefonicaResultado {}

class CancelarRecargaLineaTelefonicaMotivoRequerido extends CancelarRecargaLineaTelefonicaResultado {}

class CancelarRecargaLineaTelefonicaErrorInesperado extends CancelarRecargaLineaTelefonicaResultado {
  CancelarRecargaLineaTelefonicaErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Anula una recarga (schemaVersion 81) **sin borrarla**.
///
/// La fila se conserva en el historial de la línea con su motivo, y
/// deja de sumar en TODOS los totalizadores del módulo — el filtro vive
/// en un único predicado del repositorio (`_vigente`), no repetido en
/// cada suma, precisamente porque ese fue el bug que apareció en
/// Vehículos al introducir la anulación.
///
/// Es TERMINAL: no existe reactivación de una recarga. Si la recarga sí
/// ocurrió, se registra una nueva — el hecho de que alguien anulara la
/// anterior por error queda igualmente en el historial.
///
/// **No toca dinero**: Telefonía no generó Egreso al registrar, así que
/// tampoco hay nada que revertir en Finanzas al anular.
class CancelarRecargaLineaTelefonicaUseCase {
  CancelarRecargaLineaTelefonicaUseCase(this._recargaRepository, this._lineaRepository);

  final RecargaLineaTelefonicaRepository _recargaRepository;
  final LineaTelefonicaRepository _lineaRepository;

  Future<CancelarRecargaLineaTelefonicaResultado> ejecutar({
    required String recargaLineaTelefonicaId,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    if (!motivoEsValido(motivo)) return CancelarRecargaLineaTelefonicaMotivoRequerido();

    final actual = await _recargaRepository.obtenerPorId(recargaLineaTelefonicaId);
    if (actual == null) return CancelarRecargaLineaTelefonicaNoExiste();
    if (actual.estatus == EstatusRecargaLineaTelefonica.cancelada.name) {
      return CancelarRecargaLineaTelefonicaYaCancelada();
    }

    try {
      final cancelada = await _recargaRepository.cancelar(
        recargaLineaTelefonicaId: recargaLineaTelefonicaId,
        motivo: motivo,
      );

      await _lineaRepository.registrarEvento(
        lineaTelefonicaId: actual.lineaTelefonicaId,
        tipoEvento: TipoEventoLineaTelefonica.recargaCancelada,
        recargaId: recargaLineaTelefonicaId,
        observacion: motivo,
        estadoAnterior: EstatusRecargaLineaTelefonica.registrada.name,
        estadoNuevo: EstatusRecargaLineaTelefonica.cancelada.name,
        actorUsuarioId: actorUsuarioId,
      );

      return CancelarRecargaLineaTelefonicaExitoso(cancelada);
    } catch (e) {
      return CancelarRecargaLineaTelefonicaErrorInesperado(e.toString());
    }
  }
}
