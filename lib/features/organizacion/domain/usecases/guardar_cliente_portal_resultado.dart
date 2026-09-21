import 'package:riseg_one/core/database/app_database.dart';

import 'cliente_portal_errors.dart';

/// Resultado compartido por `CrearClientePortalUseCase` y
/// `ActualizarClientePortalUseCase` — evita duplicar el tipo de error
/// entre alta y edición (mismo motivo que `GuardarEntidadFiscalResultado`).
sealed class GuardarClientePortalResultado {}

class GuardarClientePortalExitoso extends GuardarClientePortalResultado {
  GuardarClientePortalExitoso(this.portal);
  final ClientePortalData portal;
}

class GuardarClientePortalErroresValidacion extends GuardarClientePortalResultado {
  GuardarClientePortalErroresValidacion(this.errores);
  final List<ErrorCampoClientePortal> errores;
}

/// Solo posible en `ActualizarClientePortalUseCase`: un portal archivado
/// es de solo consulta — no puede editarse hasta reactivarse (mismo
/// criterio que `GuardarEntidadFiscalArchivada`).
class GuardarClientePortalArchivado extends GuardarClientePortalResultado {}

/// Corregir los datos de acceso de un portal exige explicar por qué —
/// sólo en `ActualizarClientePortalUseCase`: un alta no justifica nada.
class GuardarClientePortalMotivoRequerido extends GuardarClientePortalResultado {}

class GuardarClientePortalErrorInesperado extends GuardarClientePortalResultado {
  GuardarClientePortalErrorInesperado(this.mensaje);
  final String mensaje;
}
