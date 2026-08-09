import 'package:riseg_one/core/error/failure.dart';
import 'package:riseg_one/core/error/result.dart';
import 'package:riseg_one/features/personal/domain/repositories/asignacion_servicio_repository.dart';
import 'package:riseg_one/features/personal/domain/repositories/empleado_repository.dart';

import '../repositories/cliente_repository.dart';
import '../repositories/configuracion_cobro_repository.dart';
import '../repositories/entidad_fiscal_repository.dart';
import '../repositories/servicio_comercial_repository.dart';
import '../repositories/servicio_repository.dart';
import '../repositories/sucursal_repository.dart';
import 'personal_asignado_servicio.dart';
import 'servicio_expediente_data.dart';

/// Ensambla el expediente completo de un Servicio (Servicio + Cliente +
/// Dirección operativa + Entidad fiscal + Responsable del Cliente +
/// Sucursal administrativa + Configuración comercial + Configuración de
/// cobro) — mismo patrón que `ObtenerExpedienteClienteUseCase`, ahora
/// componiendo 6 repositorios porque el expediente de Servicio ya
/// vincula entidades de otros 3 dominios (Cliente, Entidad fiscal,
/// Sucursal) además del propio Contacto (vía `ClienteRepository`) y, desde
/// las Etapas 4G.1/4H.1, sus propias Configuración comercial y
/// Configuración de cobro.
class ObtenerExpedienteServicioUseCase {
  ObtenerExpedienteServicioUseCase(
    this._servicioRepository,
    this._clienteRepository,
    this._entidadFiscalRepository,
    this._sucursalRepository,
    this._servicioComercialRepository,
    this._configuracionCobroRepository,
    this._asignacionServicioRepository,
    this._empleadoRepository,
  );

  final ServicioRepository _servicioRepository;
  final ClienteRepository _clienteRepository;
  final EntidadFiscalRepository _entidadFiscalRepository;
  final SucursalRepository _sucursalRepository;
  final ServicioComercialRepository _servicioComercialRepository;
  final ConfiguracionCobroRepository _configuracionCobroRepository;

  /// Dependencias del dominio `personal` (Etapa 5D) — solo lectura,
  /// para armar la sección "Personal asignado" del expediente. Primera
  /// vez que `organizacion` lee de `personal`; la dirección inversa
  /// (Personal leyendo Puesto/Empresa/Sucursal) ya existe desde 5A.
  final AsignacionServicioRepository _asignacionServicioRepository;
  final EmpleadoRepository _empleadoRepository;

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

    final lineasComerciales = await _servicioComercialRepository.listarLineas(servicioId);
    final configuracionCobro = await _configuracionCobroRepository.obtenerConfiguracion(servicioId);

    // Personal asignado (Etapa 5D) — solo consulta, nunca duplica
    // nombre/puesto: cada fila se resuelve contra Empleado.
    final asignaciones = await _asignacionServicioRepository.listarPorServicio(servicioId);
    final personalAsignado = <PersonalAsignadoServicio>[];
    for (final asignacion in asignaciones) {
      final empleado = await _empleadoRepository.obtenerPorId(asignacion.empleadoId);
      if (empleado != null) {
        personalAsignado.add(PersonalAsignadoServicio(empleado: empleado, asignacion: asignacion));
      }
    }

    return Result.ok(
      ServicioExpedienteData(
        servicio: servicio,
        cliente: cliente,
        tieneDireccionOperativaActiva: tieneDireccion,
        direccionOperativa: direccionOperativa,
        entidadFiscal: entidadFiscal,
        responsableCliente: responsableCliente,
        sucursalAdministrativa: sucursalAdministrativa,
        lineasComerciales: lineasComerciales,
        configuracionCobro: configuracionCobro,
        personalAsignado: personalAsignado,
      ),
    );
  }
}
