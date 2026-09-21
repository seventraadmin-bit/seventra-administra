import '../repositories/nomina_repository.dart';

/// Motivo estructurado de eliminación física de una Nómina (Etapa 15,
/// Maestro-only) — mismo criterio que `MotivoEliminacionFisicaCompra`:
/// se persiste el nombre estable del enum en
/// `EliminacionFisicaEvento.motivoCodigo`, nunca la etiqueta. `otro` es
/// el único valor que exige `detalle`.
enum MotivoEliminacionFisicaNomina {
  nominaDePrueba,
  nominaDuplicada,
  errorDePeriodo,
  errorDeCaptura,
  generadaPorEquivocacion,
  otro,
}

/// Etiqueta traducida de cada [MotivoEliminacionFisicaNomina] — se
/// persiste también en `EliminacionFisicaEvento.motivo` (texto libre,
/// siempre poblado por compatibilidad con el resto de dominios que
/// comparten esa tabla).
extension MotivoEliminacionFisicaNominaLabel on MotivoEliminacionFisicaNomina {
  String get etiqueta => switch (this) {
        MotivoEliminacionFisicaNomina.nominaDePrueba => 'Nómina de prueba',
        MotivoEliminacionFisicaNomina.nominaDuplicada => 'Nómina duplicada',
        MotivoEliminacionFisicaNomina.errorDePeriodo => 'Error de periodo',
        MotivoEliminacionFisicaNomina.errorDeCaptura => 'Error de captura',
        MotivoEliminacionFisicaNomina.generadaPorEquivocacion => 'Generada por equivocación',
        MotivoEliminacionFisicaNomina.otro => 'Otro',
      };
}

/// Resumen de solo lectura de si una Nómina es elegible para
/// eliminación física (Etapa 15) — insumo del mensaje de confirmación
/// antes de pedir el motivo. `detalleBloqueo` no nulo significa que la
/// Nómina ya cruzó un punto irreversible (no está en Borrador, o ya
/// tiene un `PagoNomina` real registrado).
class ResumenEliminacionNomina {
  const ResumenEliminacionNomina({required this.existe, this.detalleBloqueo});

  final bool existe;
  final String? detalleBloqueo;

  bool get bloqueado => detalleBloqueo != null;
}

sealed class EliminarNominaFisicamenteResultado {}

class EliminarNominaFisicamenteExitoso extends EliminarNominaFisicamenteResultado {}

class EliminarNominaFisicamenteNoExiste extends EliminarNominaFisicamenteResultado {}

/// `motivo == MotivoEliminacionFisicaNomina.otro` sin `detalle` capturado.
class EliminarNominaFisicamenteDetalleRequerido extends EliminarNominaFisicamenteResultado {}

/// La Nómina ya cruzó un punto irreversible — nunca está en Borrador,
/// o ya tiene un `PagoNomina` real registrado contra ella. `detalle`
/// siempre nombra la razón real, nunca un mensaje genérico.
class EliminarNominaFisicamenteTieneDependencias extends EliminarNominaFisicamenteResultado {
  EliminarNominaFisicamenteTieneDependencias(this.detalle);
  final String detalle;
}

class EliminarNominaFisicamenteErrorInesperado extends EliminarNominaFisicamenteResultado {
  EliminarNominaFisicamenteErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Eliminación física extraordinaria de una `Nomina` (Etapa 15) —
/// exclusiva del Usuario Maestro (`exigirMaestro`, nunca aquí — este
/// caso de uso es puro). Solo un Borrador sin `PagoNomina` es
/// elegible — una Nómina Cerrada/Pagada, o con cualquier pago real
/// registrado, se bloquea siempre. `motivo` siempre obligatorio (enum
/// estructurado); `otro` exige `detalle`. Toda la validación +
/// reversión de `DescuentoInventario` aplicados (vuelven a `pendiente`,
/// nunca desaparecen) + snapshot + auditoría + `DELETE` ocurre
/// transaccionalmente dentro de `NominaRepositoryImpl.eliminarFisicamente`.
class EliminarNominaFisicamenteUseCase {
  EliminarNominaFisicamenteUseCase(this._repository);

  final NominaRepository _repository;

  Future<ResumenEliminacionNomina> obtenerResumen(String nominaId) {
    return _repository.obtenerResumenEliminacionFisica(nominaId);
  }

  Future<EliminarNominaFisicamenteResultado> ejecutar({
    required String nominaId,
    required MotivoEliminacionFisicaNomina motivo,
    String? detalle,
    String? actorUsuarioId,
  }) async {
    final detalleLimpio = detalle?.trim();
    if (motivo == MotivoEliminacionFisicaNomina.otro && (detalleLimpio == null || detalleLimpio.isEmpty)) {
      return EliminarNominaFisicamenteDetalleRequerido();
    }

    try {
      return await _repository.eliminarFisicamente(
        nominaId: nominaId,
        motivo: motivo.name,
        detalle: detalleLimpio,
        actorUsuarioId: actorUsuarioId,
      );
    } catch (e) {
      return EliminarNominaFisicamenteErrorInesperado(e.toString());
    }
  }
}
