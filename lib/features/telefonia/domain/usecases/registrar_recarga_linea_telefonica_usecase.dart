import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/linea_telefonica_repository.dart';
import '../repositories/recarga_linea_telefonica_repository.dart';

sealed class RegistrarRecargaLineaTelefonicaResultado {}

class RegistrarRecargaLineaTelefonicaExitoso extends RegistrarRecargaLineaTelefonicaResultado {
  RegistrarRecargaLineaTelefonicaExitoso(this.recarga);
  final RecargaLineaTelefonicaData recarga;
}

class RegistrarRecargaLineaTelefonicaLineaNoExiste extends RegistrarRecargaLineaTelefonicaResultado {}

/// Una línea dada de baja no admite nuevas recargas — sí una
/// suspendida (ver el doc comment de la clase, punto 5 de la
/// resolución de 9C: recargar es, en la operación real, la acción que
/// suele reactivar una línea suspendida).
class RegistrarRecargaLineaTelefonicaLineaDeBaja extends RegistrarRecargaLineaTelefonicaResultado {}

class RegistrarRecargaLineaTelefonicaImporteInvalido extends RegistrarRecargaLineaTelefonicaResultado {}

class RegistrarRecargaLineaTelefonicaErrorInesperado extends RegistrarRecargaLineaTelefonicaResultado {
  RegistrarRecargaLineaTelefonicaErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Registra una recarga prepago (Etapa 9C) — fecha, importe,
/// observaciones opcionales. Sin gigabytes/minutos/SMS/paquete/vigencia/
/// saldo (fuera de alcance confirmado por Marlon) y sin crear un Egreso
/// automático: Telefonía registra el contexto operativo, Finanzas sigue
/// siendo la única fuente de movimientos de dinero reales.
///
/// **Única regla de estatus**: `baja` bloquea, `suspendida` **no** —
/// una línea suspendida conserva asignación/equipo/historial y puede
/// seguir recargándose; en prepago real, recargar es frecuentemente la
/// acción que reactiva una línea suspendida.
class RegistrarRecargaLineaTelefonicaUseCase {
  RegistrarRecargaLineaTelefonicaUseCase(this._recargaRepository, this._lineaRepository);

  final RecargaLineaTelefonicaRepository _recargaRepository;
  final LineaTelefonicaRepository _lineaRepository;

  Future<RegistrarRecargaLineaTelefonicaResultado> ejecutar({
    required String lineaTelefonicaId,
    required DateTime fecha,
    required int importe,
    String? observaciones,
  }) async {
    final linea = await _lineaRepository.obtenerPorId(lineaTelefonicaId);
    if (linea == null) return RegistrarRecargaLineaTelefonicaLineaNoExiste();
    if (linea.estatus == 'baja') return RegistrarRecargaLineaTelefonicaLineaDeBaja();
    if (importe <= 0) return RegistrarRecargaLineaTelefonicaImporteInvalido();

    try {
      final recarga = await _recargaRepository.registrar(
        lineaTelefonicaId: lineaTelefonicaId,
        fecha: fecha,
        importe: importe,
        observaciones: observaciones?.trim().isEmpty ?? true ? null : observaciones!.trim(),
      );
      return RegistrarRecargaLineaTelefonicaExitoso(recarga);
    } catch (e) {
      return RegistrarRecargaLineaTelefonicaErrorInesperado(e.toString());
    }
  }
}
