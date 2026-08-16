import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/configuracion_cobro_repository.dart';
import 'configuracion_cobro_errors.dart';
import 'configuracion_cobro_etapa_errors.dart';
import 'configuracion_cobro_etapa_validator.dart';
import 'configuracion_cobro_validator.dart';

sealed class CorregirConfiguracionCobroResultado {}

class CorregirConfiguracionCobroExitoso extends CorregirConfiguracionCobroResultado {
  CorregirConfiguracionCobroExitoso(this.vigencia);
  final ConfiguracionCobroVigenciaData vigencia;
}

class CorregirConfiguracionCobroNoExiste extends CorregirConfiguracionCobroResultado {}

/// La configuración ya tiene más de una vigencia (pasó por "Nueva
/// vigencia") o su única vigencia ya generó al menos un documento de
/// Agenda — no es un simple error de captura, así que la corrección
/// in-place se rechaza siempre; el único camino seguro es "Nueva
/// vigencia".
class CorregirConfiguracionCobroTieneHistoria extends CorregirConfiguracionCobroResultado {}

class CorregirConfiguracionCobroErroresValidacion extends CorregirConfiguracionCobroResultado {
  CorregirConfiguracionCobroErroresValidacion(this.errores, [this.erroresEtapas = const []]);
  final List<ErrorConfiguracionCobro> errores;
  final List<ErrorEtapaCobro> erroresEtapas;
}

/// Reservado para la frontera de autorización (`autorizarUseCase`,
/// permiso dinámico `comercial.modificar`) — nunca lo produce el
/// propio caso de uso.
class CorregirConfiguracionCobroErrorInesperado extends CorregirConfiguracionCobroResultado {
  CorregirConfiguracionCobroErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Corrige, in-place, la única vigencia de una Configuración de cobro
/// recién creada (Etapa 15, hallazgo de Comercial) — misma excepción,
/// mismas condiciones de elegibilidad que
/// `CorregirLineaComercialUseCase`, aplicadas al modelo paralelo de
/// Configuración de cobro (`ConfiguracionCobroVigencia`, mismo doc
/// comment: "mismo modelo exacto que ServicioLineaComercialVigencia").
class CorregirConfiguracionCobroUseCase {
  CorregirConfiguracionCobroUseCase(this._repository, this._validator, this._etapaValidator);

  final ConfiguracionCobroRepository _repository;
  final ConfiguracionCobroValidator _validator;
  final ConfiguracionCobroEtapaValidator _etapaValidator;

  Future<CorregirConfiguracionCobroResultado> ejecutar({
    required String configuracionCobroId,
    required ConfiguracionCobroBorrador borrador,
    List<EtapaCobroBorrador> etapas = const [],
  }) async {
    final configuracion = await _repository.obtenerConfiguracionPorId(configuracionCobroId);
    if (configuracion == null) return CorregirConfiguracionCobroNoExiste();

    final historial = await _repository.listarHistorial(configuracionCobroId);
    if (historial.length != 1) return CorregirConfiguracionCobroTieneHistoria();

    final tieneDocumentos = await _repository.tieneDocumentosGenerados(historial.single.id);
    if (tieneDocumentos) return CorregirConfiguracionCobroTieneHistoria();

    final validacion = await _validator.validar(servicioId: configuracion.servicioId, borrador: borrador);
    final validacionEtapas = _etapaValidator.validar(etapas);
    if (validacion.errores.isNotEmpty || validacionEtapas.errores.isNotEmpty) {
      return CorregirConfiguracionCobroErroresValidacion(validacion.errores, validacionEtapas.errores);
    }

    final vigencia = await _repository.corregirVigencia(
      vigenciaId: historial.single.id,
      datos: validacion.resultado!,
      etapas: validacionEtapas.resultado,
    );
    return CorregirConfiguracionCobroExitoso(vigencia);
  }
}
