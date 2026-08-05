import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/error/result.dart';

import '../repositories/servicio_repository.dart';
import 'guardar_servicio_resultado.dart';
import 'servicio_validator.dart';

/// Alta mínima de Servicio (Etapa 4F.1) — nombre, Cliente, Tipo de
/// Servicio, fecha de inicio y observaciones opcionales. Entidad fiscal,
/// Dirección operativa, responsables y referencias se capturan después
/// desde el expediente (Etapa 4F.2), nunca aquí.
///
/// La Ubicación raíz (ancla del árbol) se crea siempre, exista o no
/// todavía una Dirección operativa — ver `ServicioRepository.crear`.
class CrearServicioUseCase {
  CrearServicioUseCase(this._servicioRepository, this._generarCodigo, this._validator);

  final ServicioRepository _servicioRepository;
  final GenerarCodigoUseCase _generarCodigo;
  final ServicioValidator _validator;

  Future<GuardarServicioResultado> ejecutar({
    required String clienteId,
    required ServicioBorrador borrador,
  }) async {
    final validacion = await _validator.validar(clienteId: clienteId, borrador: borrador);
    if (validacion.errores.isNotEmpty) {
      return GuardarServicioErroresValidacion(validacion.errores);
    }
    final validado = validacion.resultado!;

    final codigoServicioResult = await _generarCodigo.ejecutar('servicio');
    final String codigoServicio;
    switch (codigoServicioResult) {
      case Ok<String>(value: final v):
        codigoServicio = v;
      case Err<String>(failure: final f):
        return GuardarServicioErrorInesperado(f.message);
    }

    final codigoUbicacionResult = await _generarCodigo.ejecutar('ubicacion');
    final String codigoUbicacion;
    switch (codigoUbicacionResult) {
      case Ok<String>(value: final v):
        codigoUbicacion = v;
      case Err<String>(failure: final f):
        return GuardarServicioErrorInesperado(f.message);
    }

    try {
      final servicio = await _servicioRepository.crear(
        codigoServicio: codigoServicio,
        clienteId: clienteId,
        nombre: validado.nombre,
        tipoServicioId: validado.tipoServicioId,
        fechaInicio: validado.fechaInicio,
        observaciones: validado.observaciones,
        codigoUbicacionRaiz: codigoUbicacion,
      );
      return GuardarServicioExitoso(servicio);
    } catch (e) {
      return GuardarServicioErrorInesperado(e.toString());
    }
  }
}
