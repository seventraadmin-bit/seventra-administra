import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/codigos/codigo_secuencia_service.dart';
import '../../core/codigos/generar_codigo_usecase.dart';
import '../../core/di/providers.dart';
import 'data/repositories/area_repository_impl.dart';
import 'data/repositories/catalogo_repository_impl.dart';
import 'data/repositories/cliente_repository_impl.dart';
import 'data/repositories/empresa_repository_impl.dart';
import 'data/repositories/entidad_fiscal_repository_impl.dart';
import 'data/repositories/puesto_repository_impl.dart';
import 'data/repositories/servicio_repository_impl.dart';
import 'data/repositories/sucursal_repository_impl.dart';
import 'data/repositories/ubicacion_repository_impl.dart';
import 'domain/repositories/area_repository.dart';
import 'domain/repositories/catalogo_repository.dart';
import 'domain/repositories/cliente_repository.dart';
import 'domain/repositories/empresa_repository.dart';
import 'domain/repositories/entidad_fiscal_repository.dart';
import 'domain/repositories/puesto_repository.dart';
import 'domain/repositories/servicio_repository.dart';
import 'domain/repositories/sucursal_repository.dart';
import 'domain/repositories/ubicacion_repository.dart';
import 'domain/usecases/activar_area_usecase.dart';
import 'domain/usecases/actualizar_area_usecase.dart';
import 'domain/usecases/actualizar_contacto_usecase.dart';
import 'domain/usecases/actualizar_empresa_usecase.dart';
import 'domain/usecases/actualizar_entidad_fiscal_usecase.dart';
import 'domain/usecases/actualizar_puesto_usecase.dart';
import 'domain/usecases/actualizar_servicio_usecase.dart';
import 'domain/usecases/agregar_contacto_usecase.dart';
import 'domain/usecases/archivar_contacto_usecase.dart';
import 'domain/usecases/asignar_entidad_fiscal_a_servicio_usecase.dart';
import 'domain/usecases/asignar_responsable_cliente_usecase.dart';
import 'domain/usecases/asignar_sucursal_administrativa_usecase.dart';
import 'domain/usecases/cambiar_ciclo_vida_entidad_fiscal_usecase.dart';
import 'domain/usecases/cambiar_ciclo_vida_puesto_usecase.dart';
import 'domain/usecases/cambiar_estado_operativo_sucursal_usecase.dart';
import 'domain/usecases/cambiar_estatus_cliente_usecase.dart';
import 'domain/usecases/cambiar_estatus_servicio_usecase.dart';
import 'domain/usecases/crear_area_usecase.dart';
import 'domain/usecases/crear_cliente_usecase.dart';
import 'domain/usecases/crear_entidad_fiscal_usecase.dart';
import 'domain/usecases/crear_puesto_usecase.dart';
import 'domain/usecases/crear_servicio_usecase.dart';
import 'domain/usecases/crear_sucursal_usecase.dart';
import 'domain/usecases/crear_ubicacion_usecase.dart';
import 'domain/usecases/desactivar_area_usecase.dart';
import 'domain/usecases/entidad_fiscal_validator.dart';
import 'domain/usecases/guardar_direccion_operativa_servicio_usecase.dart';
import 'domain/usecases/guardar_domicilio_fiscal_usecase.dart';
import 'domain/usecases/guardar_expediente_cliente_usecase.dart';
import 'domain/usecases/guardar_expediente_empresa_usecase.dart';
import 'domain/usecases/guardar_expediente_sucursal_usecase.dart';
import 'domain/usecases/guardar_responsable_interno_usecase.dart';
import 'domain/usecases/listar_areas_activas_usecase.dart';
import 'domain/usecases/listar_areas_usecase.dart';
import 'domain/usecases/listar_clientes_usecase.dart';
import 'domain/usecases/listar_entidades_fiscales_de_cliente_usecase.dart';
import 'domain/usecases/listar_puestos_usecase.dart';
import 'domain/usecases/listar_servicios_usecase.dart';
import 'domain/usecases/listar_sucursales_usecase.dart';
import 'domain/usecases/listar_tipos_sucursal_usecase.dart';
import 'domain/usecases/mover_ubicacion_usecase.dart';
import 'domain/usecases/obtener_arbol_ubicaciones_de_sucursal_usecase.dart';
import 'domain/usecases/obtener_arbol_ubicaciones_usecase.dart';
import 'domain/usecases/obtener_empresa_activa_usecase.dart';
import 'domain/usecases/obtener_expediente_cliente_usecase.dart';
import 'domain/usecases/obtener_expediente_empresa_usecase.dart';
import 'domain/usecases/obtener_expediente_puesto_usecase.dart';
import 'domain/usecases/obtener_expediente_servicio_usecase.dart';
import 'domain/usecases/obtener_expediente_sucursal_usecase.dart';
import 'domain/usecases/puesto_validator.dart';
import 'domain/usecases/servicio_validator.dart';

/// Providers de infraestructura de Organización (base de datos,
/// servicios, repositorios, casos de uso). Los providers de pantalla
/// (controladores de estado de UI) viven junto a cada pantalla, no aquí
/// — ver `presentation/empresa/empresa_expediente_controller.dart`.

final codigoSecuenciaServiceProvider = Provider<CodigoSecuenciaService>((ref) {
  return CodigoSecuenciaService(ref.watch(appDatabaseProvider));
});

final generarCodigoUseCaseProvider = Provider<GenerarCodigoUseCase>((ref) {
  return GenerarCodigoUseCase(ref.watch(codigoSecuenciaServiceProvider));
});

final empresaRepositoryProvider = Provider<EmpresaRepository>((ref) {
  return EmpresaRepositoryImpl(ref.watch(appDatabaseProvider));
});

final puestoRepositoryProvider = Provider<PuestoRepository>((ref) {
  return PuestoRepositoryImpl(ref.watch(appDatabaseProvider));
});

final sucursalRepositoryProvider = Provider<SucursalRepository>((ref) {
  return SucursalRepositoryImpl(ref.watch(appDatabaseProvider));
});

final ubicacionRepositoryProvider = Provider<UbicacionRepository>((ref) {
  return UbicacionRepositoryImpl(ref.watch(appDatabaseProvider));
});

final clienteRepositoryProvider = Provider<ClienteRepository>((ref) {
  return ClienteRepositoryImpl(ref.watch(appDatabaseProvider));
});

final servicioRepositoryProvider = Provider<ServicioRepository>((ref) {
  return ServicioRepositoryImpl(ref.watch(appDatabaseProvider));
});

final catalogoRepositoryProvider = Provider<CatalogoRepository>((ref) {
  return CatalogoRepositoryImpl(ref.watch(appDatabaseProvider));
});

final areaRepositoryProvider = Provider<AreaRepository>((ref) {
  return AreaRepositoryImpl(ref.watch(appDatabaseProvider));
});

final entidadFiscalRepositoryProvider = Provider<EntidadFiscalRepository>((ref) {
  return EntidadFiscalRepositoryImpl(ref.watch(appDatabaseProvider));
});

final obtenerEmpresaActivaUseCaseProvider = Provider<ObtenerEmpresaActivaUseCase>((ref) {
  return ObtenerEmpresaActivaUseCase(ref.watch(empresaRepositoryProvider));
});

final actualizarEmpresaUseCaseProvider = Provider<ActualizarEmpresaUseCase>((ref) {
  return ActualizarEmpresaUseCase(ref.watch(empresaRepositoryProvider));
});

final obtenerExpedienteEmpresaUseCaseProvider = Provider<ObtenerExpedienteEmpresaUseCase>((ref) {
  return ObtenerExpedienteEmpresaUseCase(
    ref.watch(obtenerEmpresaActivaUseCaseProvider),
    ref.watch(empresaRepositoryProvider),
  );
});

final guardarExpedienteEmpresaUseCaseProvider = Provider<GuardarExpedienteEmpresaUseCase>((ref) {
  return GuardarExpedienteEmpresaUseCase(ref.watch(empresaRepositoryProvider));
});

final puestoValidatorProvider = Provider<PuestoValidator>((ref) {
  return PuestoValidator(ref.watch(areaRepositoryProvider));
});

final crearPuestoUseCaseProvider = Provider<CrearPuestoUseCase>((ref) {
  return CrearPuestoUseCase(
    ref.watch(puestoRepositoryProvider),
    ref.watch(generarCodigoUseCaseProvider),
    ref.watch(puestoValidatorProvider),
  );
});

final actualizarPuestoUseCaseProvider = Provider<ActualizarPuestoUseCase>((ref) {
  return ActualizarPuestoUseCase(ref.watch(puestoRepositoryProvider), ref.watch(puestoValidatorProvider));
});

final cambiarCicloVidaPuestoUseCaseProvider = Provider<CambiarCicloVidaPuestoUseCase>((ref) {
  return CambiarCicloVidaPuestoUseCase(ref.watch(puestoRepositoryProvider), ref.watch(areaRepositoryProvider));
});

final listarPuestosUseCaseProvider = Provider<ListarPuestosUseCase>((ref) {
  return ListarPuestosUseCase(ref.watch(puestoRepositoryProvider));
});

final obtenerExpedientePuestoUseCaseProvider = Provider<ObtenerExpedientePuestoUseCase>((ref) {
  return ObtenerExpedientePuestoUseCase(ref.watch(puestoRepositoryProvider));
});

final listarAreasUseCaseProvider = Provider<ListarAreasUseCase>((ref) {
  return ListarAreasUseCase(ref.watch(areaRepositoryProvider));
});

final listarAreasActivasUseCaseProvider = Provider<ListarAreasActivasUseCase>((ref) {
  return ListarAreasActivasUseCase(ref.watch(areaRepositoryProvider));
});

final crearAreaUseCaseProvider = Provider<CrearAreaUseCase>((ref) {
  return CrearAreaUseCase(ref.watch(areaRepositoryProvider), ref.watch(generarCodigoUseCaseProvider));
});

final actualizarAreaUseCaseProvider = Provider<ActualizarAreaUseCase>((ref) {
  return ActualizarAreaUseCase(ref.watch(areaRepositoryProvider));
});

final activarAreaUseCaseProvider = Provider<ActivarAreaUseCase>((ref) {
  return ActivarAreaUseCase(ref.watch(areaRepositoryProvider));
});

final desactivarAreaUseCaseProvider = Provider<DesactivarAreaUseCase>((ref) {
  return DesactivarAreaUseCase(ref.watch(areaRepositoryProvider), ref.watch(puestoRepositoryProvider));
});

final crearSucursalUseCaseProvider = Provider<CrearSucursalUseCase>((ref) {
  return CrearSucursalUseCase(
    ref.watch(sucursalRepositoryProvider),
    ref.watch(generarCodigoUseCaseProvider),
  );
});

final listarSucursalesUseCaseProvider = Provider<ListarSucursalesUseCase>((ref) {
  return ListarSucursalesUseCase(ref.watch(sucursalRepositoryProvider));
});

final obtenerExpedienteSucursalUseCaseProvider = Provider<ObtenerExpedienteSucursalUseCase>((ref) {
  return ObtenerExpedienteSucursalUseCase(ref.watch(sucursalRepositoryProvider));
});

final guardarExpedienteSucursalUseCaseProvider = Provider<GuardarExpedienteSucursalUseCase>((ref) {
  return GuardarExpedienteSucursalUseCase(ref.watch(sucursalRepositoryProvider));
});

final cambiarEstadoOperativoSucursalUseCaseProvider = Provider<CambiarEstadoOperativoSucursalUseCase>((ref) {
  return CambiarEstadoOperativoSucursalUseCase(ref.watch(sucursalRepositoryProvider));
});

final listarTiposSucursalUseCaseProvider = Provider<ListarTiposSucursalUseCase>((ref) {
  return ListarTiposSucursalUseCase(ref.watch(catalogoRepositoryProvider));
});

final crearUbicacionUseCaseProvider = Provider<CrearUbicacionUseCase>((ref) {
  return CrearUbicacionUseCase(
    ref.watch(ubicacionRepositoryProvider),
    ref.watch(generarCodigoUseCaseProvider),
  );
});

final moverUbicacionUseCaseProvider = Provider<MoverUbicacionUseCase>((ref) {
  return MoverUbicacionUseCase(ref.watch(ubicacionRepositoryProvider));
});

final obtenerArbolUbicacionesUseCaseProvider = Provider<ObtenerArbolUbicacionesUseCase>((ref) {
  return ObtenerArbolUbicacionesUseCase(ref.watch(ubicacionRepositoryProvider));
});

final obtenerArbolUbicacionesDeSucursalUseCaseProvider =
    Provider<ObtenerArbolUbicacionesDeSucursalUseCase>((ref) {
  return ObtenerArbolUbicacionesDeSucursalUseCase(ref.watch(ubicacionRepositoryProvider));
});

final crearClienteUseCaseProvider = Provider<CrearClienteUseCase>((ref) {
  return CrearClienteUseCase(ref.watch(clienteRepositoryProvider), ref.watch(generarCodigoUseCaseProvider));
});

final guardarExpedienteClienteUseCaseProvider = Provider<GuardarExpedienteClienteUseCase>((ref) {
  return GuardarExpedienteClienteUseCase(ref.watch(clienteRepositoryProvider));
});

final cambiarEstatusClienteUseCaseProvider = Provider<CambiarEstatusClienteUseCase>((ref) {
  return CambiarEstatusClienteUseCase(ref.watch(clienteRepositoryProvider));
});

final listarClientesUseCaseProvider = Provider<ListarClientesUseCase>((ref) {
  return ListarClientesUseCase(ref.watch(clienteRepositoryProvider));
});

final obtenerExpedienteClienteUseCaseProvider = Provider<ObtenerExpedienteClienteUseCase>((ref) {
  return ObtenerExpedienteClienteUseCase(ref.watch(clienteRepositoryProvider), ref.watch(entidadFiscalRepositoryProvider));
});

final agregarContactoUseCaseProvider = Provider<AgregarContactoUseCase>((ref) {
  return AgregarContactoUseCase(ref.watch(clienteRepositoryProvider));
});

final actualizarContactoUseCaseProvider = Provider<ActualizarContactoUseCase>((ref) {
  return ActualizarContactoUseCase(ref.watch(clienteRepositoryProvider));
});

final archivarContactoUseCaseProvider = Provider<ArchivarContactoUseCase>((ref) {
  return ArchivarContactoUseCase(ref.watch(clienteRepositoryProvider));
});

final entidadFiscalValidatorProvider = Provider<EntidadFiscalValidator>((ref) {
  return EntidadFiscalValidator(ref.watch(clienteRepositoryProvider), ref.watch(entidadFiscalRepositoryProvider));
});

final crearEntidadFiscalUseCaseProvider = Provider<CrearEntidadFiscalUseCase>((ref) {
  return CrearEntidadFiscalUseCase(
    ref.watch(entidadFiscalRepositoryProvider),
    ref.watch(generarCodigoUseCaseProvider),
    ref.watch(entidadFiscalValidatorProvider),
  );
});

final actualizarEntidadFiscalUseCaseProvider = Provider<ActualizarEntidadFiscalUseCase>((ref) {
  return ActualizarEntidadFiscalUseCase(ref.watch(entidadFiscalRepositoryProvider), ref.watch(entidadFiscalValidatorProvider));
});

final cambiarCicloVidaEntidadFiscalUseCaseProvider = Provider<CambiarCicloVidaEntidadFiscalUseCase>((ref) {
  return CambiarCicloVidaEntidadFiscalUseCase(ref.watch(entidadFiscalRepositoryProvider));
});

final guardarDomicilioFiscalUseCaseProvider = Provider<GuardarDomicilioFiscalUseCase>((ref) {
  return GuardarDomicilioFiscalUseCase(ref.watch(entidadFiscalRepositoryProvider));
});

final listarEntidadesFiscalesDeClienteUseCaseProvider = Provider<ListarEntidadesFiscalesDeClienteUseCase>((ref) {
  return ListarEntidadesFiscalesDeClienteUseCase(ref.watch(entidadFiscalRepositoryProvider));
});

final servicioValidatorProvider = Provider<ServicioValidator>((ref) {
  return ServicioValidator(ref.watch(clienteRepositoryProvider), ref.watch(catalogoRepositoryProvider));
});

final crearServicioUseCaseProvider = Provider<CrearServicioUseCase>((ref) {
  return CrearServicioUseCase(
    ref.watch(servicioRepositoryProvider),
    ref.watch(generarCodigoUseCaseProvider),
    ref.watch(servicioValidatorProvider),
  );
});

final actualizarServicioUseCaseProvider = Provider<ActualizarServicioUseCase>((ref) {
  return ActualizarServicioUseCase(ref.watch(servicioRepositoryProvider), ref.watch(servicioValidatorProvider));
});

final cambiarEstatusServicioUseCaseProvider = Provider<CambiarEstatusServicioUseCase>((ref) {
  return CambiarEstatusServicioUseCase(ref.watch(servicioRepositoryProvider), ref.watch(clienteRepositoryProvider));
});

final listarServiciosUseCaseProvider = Provider<ListarServiciosUseCase>((ref) {
  return ListarServiciosUseCase(ref.watch(servicioRepositoryProvider));
});

final obtenerExpedienteServicioUseCaseProvider = Provider<ObtenerExpedienteServicioUseCase>((ref) {
  return ObtenerExpedienteServicioUseCase(
    ref.watch(servicioRepositoryProvider),
    ref.watch(clienteRepositoryProvider),
    ref.watch(entidadFiscalRepositoryProvider),
    ref.watch(sucursalRepositoryProvider),
  );
});

final asignarEntidadFiscalAServicioUseCaseProvider = Provider<AsignarEntidadFiscalAServicioUseCase>((ref) {
  return AsignarEntidadFiscalAServicioUseCase(ref.watch(servicioRepositoryProvider), ref.watch(entidadFiscalRepositoryProvider));
});

final asignarResponsableClienteUseCaseProvider = Provider<AsignarResponsableClienteUseCase>((ref) {
  return AsignarResponsableClienteUseCase(ref.watch(servicioRepositoryProvider), ref.watch(clienteRepositoryProvider));
});

final asignarSucursalAdministrativaUseCaseProvider = Provider<AsignarSucursalAdministrativaUseCase>((ref) {
  return AsignarSucursalAdministrativaUseCase(ref.watch(servicioRepositoryProvider), ref.watch(sucursalRepositoryProvider));
});

final guardarDireccionOperativaServicioUseCaseProvider = Provider<GuardarDireccionOperativaServicioUseCase>((ref) {
  return GuardarDireccionOperativaServicioUseCase(ref.watch(servicioRepositoryProvider));
});

final guardarResponsableInternoUseCaseProvider = Provider<GuardarResponsableInternoUseCase>((ref) {
  return GuardarResponsableInternoUseCase(ref.watch(servicioRepositoryProvider));
});
