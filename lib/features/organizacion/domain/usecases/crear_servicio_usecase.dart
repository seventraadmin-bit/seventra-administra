import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/error/failure.dart';
import 'package:riseg_one/core/error/result.dart';

import '../repositories/cliente_repository.dart';
import '../repositories/servicio_repository.dart';

/// Crea un Servicio garantizando transaccionalmente (vía
/// `ServicioRepository`) el propio Servicio, su Dirección operativa
/// principal y su nodo raíz de Ubicación — no hay estado de "borrador
/// sin dirección" en esta etapa.
class CrearServicioUseCase {
  CrearServicioUseCase(this._servicioRepository, this._clienteRepository, this._generarCodigo);

  final ServicioRepository _servicioRepository;
  final ClienteRepository _clienteRepository;
  final GenerarCodigoUseCase _generarCodigo;

  Future<Result<ServicioData>> ejecutar({
    required String clienteId,
    required String nombre,
    required String tipoServicioId,
    required String sucursalAdministrativaId,
    required DateTime fechaInicio,
    required DireccionOperativaInput direccionOperativa,
    DateTime? fechaTermino,
    int elementosAutorizados = 0,
    String? responsableClienteContactoId,
    String? observaciones,
  }) async {
    if (elementosAutorizados < 0) {
      return const Result.failure(ValidationFailure('elementosAutorizados no puede ser negativo.'));
    }
    if (fechaTermino != null && fechaTermino.isBefore(fechaInicio)) {
      return const Result.failure(
        ValidationFailure('fechaTermino no puede ser anterior a fechaInicio.'),
      );
    }

    if (responsableClienteContactoId != null) {
      final contactos = await _clienteRepository.obtenerContactos(clienteId);
      final pertenece = contactos.any((c) => c.id == responsableClienteContactoId);
      if (!pertenece) {
        return const Result.failure(
          ValidationFailure('El contacto responsable no pertenece a este Cliente.'),
        );
      }
    }

    final codigoServicioResult = await _generarCodigo.ejecutar('servicio');
    final String codigoServicio;
    switch (codigoServicioResult) {
      case Ok<String>(value: final v):
        codigoServicio = v;
      case Err<String>(failure: final f):
        return Result.failure(f);
    }

    final codigoUbicacionResult = await _generarCodigo.ejecutar('ubicacion');
    final String codigoUbicacion;
    switch (codigoUbicacionResult) {
      case Ok<String>(value: final v):
        codigoUbicacion = v;
      case Err<String>(failure: final f):
        return Result.failure(f);
    }

    final servicio = await _servicioRepository.crear(
      codigoServicio: codigoServicio,
      clienteId: clienteId,
      nombre: nombre,
      tipoServicioId: tipoServicioId,
      sucursalAdministrativaId: sucursalAdministrativaId,
      fechaInicio: fechaInicio,
      fechaTermino: fechaTermino,
      elementosAutorizados: elementosAutorizados,
      responsableClienteContactoId: responsableClienteContactoId,
      observaciones: observaciones,
      codigoUbicacionRaiz: codigoUbicacion,
      direccionOperativa: direccionOperativa,
    );
    return Result.ok(servicio);
  }
}
