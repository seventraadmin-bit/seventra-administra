import 'package:riseg_one/core/error/failure.dart';
import 'package:riseg_one/core/error/result.dart';

import '../repositories/cliente_repository.dart';
import '../repositories/entidad_fiscal_repository.dart';
import '../repositories/servicio_repository.dart';
import '../repositories/sucursal_repository.dart';
import 'servicio_expediente_data.dart';

/// Ensambla el expediente completo de un Servicio (Servicio + Cliente +
/// Dirección operativa + Entidad fiscal + Responsable del Cliente +
/// Sucursal administrativa) — mismo patrón que
/// `ObtenerExpedienteClienteUseCase`, ahora componiendo 4 repositorios
/// en vez de 2 porque el expediente de Servicio ya vincula entidades de
/// otros 3 dominios (Cliente, Entidad fiscal, Sucursal) además del
/// propio Contacto (vía `ClienteRepository`).
class ObtenerExpedienteServicioUseCase {
  ObtenerExpedienteServicioUseCase(
    this._servicioRepository,
    this._clienteRepository,
    this._entidadFiscalRepository,
    this._sucursalRepository,
  );

  final ServicioRepository _servicioRepository;
  final ClienteRepository _clienteRepository;
  final EntidadFiscalRepository _entidadFiscalRepository;
  final SucursalRepository _sucursalRepository;

  Future<Result<ServicioExpedienteData>> ejecutar(String servicioId) async {
    final servicio = await _servicioRepository.obtenerPorId(servicioId);
    if (servicio == null) {
      return Result.failure(NotFoundFailure('Servicio no encontrado: $servicioId'));
    }

    final cliente = await _clienteRepository.obtenerPorId(servicio.clienteId);
    if (cliente == null) {
      return Result.failure(NotFoundFailure('Cliente no encontrado: ${servicio.clienteId}'));
    }

    final tieneDireccion = await _servicioRepository.tieneDireccionOperativaActiva(servicioId);
    final direccionOperativa = await _servicioRepository.obtenerDireccionOperativa(servicioId);

    final entidadFiscalId = servicio.entidadFiscalId;
    final entidadFiscal = entidadFiscalId == null ? null : await _entidadFiscalRepository.obtenerPorId(entidadFiscalId);

    final contactoId = servicio.responsableClienteContactoId;
    final responsableCliente = contactoId == null ? null : await _clienteRepository.obtenerContactoPorId(contactoId);

    final sucursalId = servicio.sucursalAdministrativaId;
    final sucursalAdministrativa = sucursalId == null ? null : await _sucursalRepository.obtenerPorId(sucursalId);

    return Result.ok(
      ServicioExpedienteData(
        servicio: servicio,
        cliente: cliente,
        tieneDireccionOperativaActiva: tieneDireccion,
        direccionOperativa: direccionOperativa,
        entidadFiscal: entidadFiscal,
        responsableCliente: responsableCliente,
        sucursalAdministrativa: sucursalAdministrativa,
      ),
    );
  }
}
