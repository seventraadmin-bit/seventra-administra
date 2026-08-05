import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/validation/direccion_validator.dart';

import 'entidad_fiscal_errors.dart';

/// Errores estructurados de guardar una Entidad fiscal — sellada porque
/// los campos propios (razón social/RFC/Cliente) y el domicilio fiscal
/// tienen formas de error genuinamente distintas.
/// `ErrorDomicilioFiscal` reutiliza directamente el [ErrorCampoDireccion]
/// de `core/validation` — no inventa un envoltorio redundante (mismo
/// patrón que `ErrorDireccionCliente`).
sealed class ErrorGuardarEntidadFiscal {}

class ErrorCampoEntidadFiscalGeneral extends ErrorGuardarEntidadFiscal {
  ErrorCampoEntidadFiscalGeneral(this.error);
  final ErrorCampoEntidadFiscal error;
}

class ErrorDomicilioFiscal extends ErrorGuardarEntidadFiscal {
  ErrorDomicilioFiscal(this.error);
  final ErrorCampoDireccion error;
}

/// Resultado compartido por `CrearEntidadFiscalUseCase` y
/// `ActualizarEntidadFiscalUseCase` — evita duplicar el tipo de error
/// entre alta y edición (mismo motivo que `GuardarPuestoResultado`).
sealed class GuardarEntidadFiscalResultado {}

class GuardarEntidadFiscalExitoso extends GuardarEntidadFiscalResultado {
  GuardarEntidadFiscalExitoso(this.entidadFiscal);
  final EntidadFiscalData entidadFiscal;
}

class GuardarEntidadFiscalErroresValidacion extends GuardarEntidadFiscalResultado {
  GuardarEntidadFiscalErroresValidacion(this.errores);
  final List<ErrorGuardarEntidadFiscal> errores;
}

/// Solo posible en `ActualizarEntidadFiscalUseCase`: una Entidad fiscal
/// archivada es de solo consulta — no puede editarse hasta reactivarse.
class GuardarEntidadFiscalArchivada extends GuardarEntidadFiscalResultado {}

class GuardarEntidadFiscalErrorInesperado extends GuardarEntidadFiscalResultado {
  GuardarEntidadFiscalErrorInesperado(this.mensaje);
  final String mensaje;
}
