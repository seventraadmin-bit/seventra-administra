import 'package:riseg_one/core/auditoria/diff_evento.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';

import '../repositories/cliente_portal_repository.dart';

/// Resultado de [CambiarCicloVidaClientePortalUseCase] — su propio tipo
/// sellado, mismo patrón que `CambiarCicloVidaEntidadFiscalResultado`.
sealed class CambiarCicloVidaClientePortalResultado {}

class CambiarCicloVidaClientePortalExitoso extends CambiarCicloVidaClientePortalResultado {
  CambiarCicloVidaClientePortalExitoso(this.portal);
  final ClientePortalData portal;
}

/// Archivar o reactivar un portal exige explicar por qué.
class CambiarCicloVidaClientePortalMotivoRequerido extends CambiarCicloVidaClientePortalResultado {}

class CambiarCicloVidaClientePortalErrorInesperado extends CambiarCicloVidaClientePortalResultado {
  CambiarCicloVidaClientePortalErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Archivar y reactivar siempre están permitidos, sin excepción — a
/// diferencia de la eliminación física (bloqueada si hay referencias),
/// un portal archivado sigue siendo perfectamente resoluble por
/// `ConfiguracionCobroVigencia.clientePortalId`/
/// `DocumentoPorEmitir.clientePortalId` (decisión explícita de Marlon:
/// "Archivar sí puede permitirse si no rompe el histórico; las
/// referencias existentes deben seguir siendo resolubles"). Archivar
/// solo retira el portal de los selectores de alta nueva
/// (`ServicioConfiguracionCobroForm`), nunca invalida lo ya elegido.
class CambiarCicloVidaClientePortalUseCase {
  CambiarCicloVidaClientePortalUseCase(this._repository);

  final ClientePortalRepository _repository;

  Future<CambiarCicloVidaClientePortalResultado> ejecutar({
    required String clientePortalId,
    required CicloVidaRegistro nuevo,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    if (!motivoEsValido(motivo)) return CambiarCicloVidaClientePortalMotivoRequerido();
    try {
      final actualizado = await _repository.cambiarCicloVida(
        id: clientePortalId,
        nuevo: nuevo,
        motivo: motivo.trim(),
        actorUsuarioId: actorUsuarioId,
      );
      return CambiarCicloVidaClientePortalExitoso(actualizado);
    } catch (e) {
      return CambiarCicloVidaClientePortalErrorInesperado(e.toString());
    }
  }
}
