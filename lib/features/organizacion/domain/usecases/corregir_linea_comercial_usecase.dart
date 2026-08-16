import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/servicio_comercial_repository.dart';
import 'linea_comercial_errors.dart';
import 'linea_comercial_validator.dart';

/// Resultado de corregir una línea comercial recién creada (Etapa 15,
/// hallazgo de Comercial) — ver el doc comment de
/// `ServicioComercialRepositoryImpl.corregirVigencia` para las
/// condiciones exactas de elegibilidad.
sealed class CorregirLineaComercialResultado {}

class CorregirLineaComercialExitoso extends CorregirLineaComercialResultado {
  CorregirLineaComercialExitoso(this.vigencia);
  final ServicioLineaComercialVigenciaData vigencia;
}

class CorregirLineaComercialNoExiste extends CorregirLineaComercialResultado {}

/// La línea ya tiene más de una vigencia (pasó por "Nueva vigencia") o
/// su única vigencia ya generó al menos un documento de Agenda — no es
/// un simple error de captura, así que la corrección in-place se
/// rechaza siempre; el único camino seguro es "Nueva vigencia".
class CorregirLineaComercialTieneHistoria extends CorregirLineaComercialResultado {}

class CorregirLineaComercialErroresValidacion extends CorregirLineaComercialResultado {
  CorregirLineaComercialErroresValidacion(this.errores);
  final List<ErrorLineaComercial> errores;
}

/// Reservado para la frontera de autorización (`autorizarUseCase`,
/// permiso dinámico `comercial.modificar`) — nunca lo produce el
/// propio caso de uso.
class CorregirLineaComercialErrorInesperado extends CorregirLineaComercialResultado {
  CorregirLineaComercialErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Corrige, in-place, la única vigencia de una línea comercial recién
/// creada — la única excepción documentada del modelo de vigencias
/// (`ServicioLineaComercialVigencia`, Etapa 4G.1/4G.2) que muta una
/// fila en vez de cerrar+insertar, justificada porque no hay historia
/// real que proteger todavía. Nunca aplica si la línea ya pasó por
/// "Nueva vigencia" (`listarHistorial` con más de una fila) o si su
/// vigencia ya produjo un `DocumentoPorEmitirLinea` — en ambos casos el
/// único camino sigue siendo `CambiarVigenciaLineaComercialUseCase`.
class CorregirLineaComercialUseCase {
  CorregirLineaComercialUseCase(this._repository, this._validator);

  final ServicioComercialRepository _repository;
  final LineaComercialValidator _validator;

  Future<CorregirLineaComercialResultado> ejecutar({
    required String lineaComercialId,
    required LineaComercialBorrador borrador,
  }) async {
    final linea = await _repository.obtenerLinea(lineaComercialId);
    if (linea == null) return CorregirLineaComercialNoExiste();

    final historial = await _repository.listarHistorial(lineaComercialId);
    if (historial.length != 1) return CorregirLineaComercialTieneHistoria();

    final tieneDocumentos = await _repository.tieneDocumentosGenerados(historial.single.id);
    if (tieneDocumentos) return CorregirLineaComercialTieneHistoria();

    final validacion = await _validator.validar(servicioId: linea.servicioId, borrador: borrador);
    if (validacion.resultado == null) return CorregirLineaComercialErroresValidacion(validacion.errores);

    final vigencia = await _repository.corregirVigencia(vigenciaId: historial.single.id, datos: validacion.resultado!);
    return CorregirLineaComercialExitoso(vigencia);
  }
}
