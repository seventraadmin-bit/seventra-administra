import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';

import 'package:riseg_one/core/auditoria/diff_evento.dart';
import '../repositories/entidad_fiscal_repository.dart';

/// Resultado de [CambiarCicloVidaEntidadFiscalUseCase] — su propio tipo
/// sellado, mismo patrón que `CambiarCicloVidaPuestoResultado`.
sealed class CambiarCicloVidaEntidadFiscalResultado {}

class CambiarCicloVidaEntidadFiscalExitoso extends CambiarCicloVidaEntidadFiscalResultado {
  CambiarCicloVidaEntidadFiscalExitoso(this.entidadFiscal);
  final EntidadFiscalData entidadFiscal;
}

/// Archivar o reactivar una Entidad fiscal exige explicar por qué.
class CambiarCicloVidaEntidadFiscalMotivoRequerido extends CambiarCicloVidaEntidadFiscalResultado {}

class CambiarCicloVidaEntidadFiscalErrorInesperado extends CambiarCicloVidaEntidadFiscalResultado {
  CambiarCicloVidaEntidadFiscalErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Archivar y reactivar están siempre permitidos en esta etapa —
/// Servicios todavía no existe, así que no hay nada que pueda estar
/// "en uso" de una Entidad fiscal para bloquear la transición. Cuando
/// Servicios exista, aquí es donde se agregaría ese bloqueo cruzado
/// (mismo lugar donde `CambiarCicloVidaPuestoUseCase` valida Área).
///
/// Archivar el registro nunca toca su domicilio fiscal por separado —
/// el domicilio conserva su propio ciclo de vida independiente, no se
/// archiva en cascada (rompería su propio historial si la Entidad
/// fiscal se reactiva después).
class CambiarCicloVidaEntidadFiscalUseCase {
  CambiarCicloVidaEntidadFiscalUseCase(this._repository);

  final EntidadFiscalRepository _repository;

  Future<CambiarCicloVidaEntidadFiscalResultado> ejecutar({
    required String entidadFiscalId,
    required CicloVidaRegistro nuevo,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    if (!motivoEsValido(motivo)) return CambiarCicloVidaEntidadFiscalMotivoRequerido();
    try {
      final actualizada = await _repository.cambiarCicloVida(
        id: entidadFiscalId,
        nuevo: nuevo,
        motivo: motivo.trim(),
        actorUsuarioId: actorUsuarioId,
      );
      return CambiarCicloVidaEntidadFiscalExitoso(actualizada);
    } catch (e) {
      return CambiarCicloVidaEntidadFiscalErrorInesperado(e.toString());
    }
  }
}
