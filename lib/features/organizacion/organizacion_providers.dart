import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/attachments/attachment_repository.dart';
import '../../core/attachments/attachment_storage.dart';
import '../../core/codigos/codigo_secuencia_service.dart';
import '../../core/codigos/generar_codigo_usecase.dart';
import '../../core/codigos/generar_numero_usecase.dart';
import '../../core/database/app_database.dart';
import '../../core/di/providers.dart';
import '../../core/error/failure.dart';
import '../../core/error/result.dart';
import '../../core/permissions/authorization_service.dart';
import '../finanzas/finanzas_providers.dart';
import '../personal/personal_providers.dart';
import '../usuarios/presentation/sesion_controller.dart';
import '../usuarios/usuarios_providers.dart';
import 'data/repositories/area_repository_impl.dart';
import 'data/repositories/catalogo_repository_impl.dart';
import 'data/repositories/cliente_repository_impl.dart';
import 'data/repositories/configuracion_cobro_repository_impl.dart';
import 'data/repositories/documento_por_emitir_repository_impl.dart';
import 'data/repositories/empresa_repository_impl.dart';
import 'data/repositories/entidad_fiscal_repository_impl.dart';
import 'data/repositories/puesto_repository_impl.dart';
import 'data/repositories/servicio_comercial_repository_impl.dart';
import 'data/repositories/servicio_repository_impl.dart';
import 'data/repositories/sucursal_repository_impl.dart';
import 'data/repositories/ubicacion_repository_impl.dart';
import 'domain/repositories/area_repository.dart';
import 'domain/repositories/catalogo_repository.dart';
import 'domain/repositories/cliente_repository.dart';
import 'domain/repositories/configuracion_cobro_repository.dart';
import 'domain/repositories/documento_por_emitir_repository.dart';
import 'domain/repositories/empresa_repository.dart';
import 'domain/repositories/entidad_fiscal_repository.dart';
import 'domain/repositories/puesto_repository.dart';
import 'domain/repositories/servicio_comercial_repository.dart';
import 'domain/repositories/servicio_repository.dart';
import 'domain/repositories/sucursal_repository.dart';
import 'domain/repositories/ubicacion_repository.dart';
import 'domain/usecases/activar_area_usecase.dart';
import 'domain/usecases/actualizar_ajuste_manual_documento_por_emitir_usecase.dart';
import 'domain/usecases/adjuntar_archivo_documento_por_emitir_usecase.dart';
import 'domain/usecases/actualizar_anotaciones_vigencia_usecase.dart';
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
import 'domain/usecases/actualizar_observaciones_configuracion_cobro_vigencia_usecase.dart';
import 'domain/usecases/cambiar_ciclo_vida_entidad_fiscal_usecase.dart';
import 'domain/usecases/cambiar_ciclo_vida_puesto_usecase.dart';
import 'domain/usecases/cambiar_estado_operativo_sucursal_usecase.dart';
import 'domain/usecases/cambiar_estatus_cliente_usecase.dart';
import 'domain/usecases/cambiar_estatus_documento_por_emitir_usecase.dart';
import 'domain/usecases/cambiar_estatus_servicio_usecase.dart';
import 'domain/usecases/cambiar_vigencia_configuracion_cobro_usecase.dart';
import 'domain/usecases/cambiar_vigencia_linea_comercial_usecase.dart';
import 'domain/usecases/cancelar_vigencia_programada_configuracion_cobro_usecase.dart';
import 'domain/usecases/cancelar_vigencia_programada_usecase.dart';
import 'domain/usecases/cerrar_configuracion_cobro_usecase.dart';
import 'domain/usecases/cerrar_linea_comercial_usecase.dart';
import 'domain/usecases/configuracion_cobro_regla_evento_validator.dart';
import 'domain/usecases/configuracion_cobro_validator.dart';
import 'domain/usecases/crear_area_usecase.dart';
import 'domain/usecases/crear_cliente_usecase.dart';
import 'domain/usecases/corregir_datos_emision_documento_por_emitir_usecase.dart';
import 'domain/usecases/crear_configuracion_cobro_usecase.dart';
import 'domain/usecases/crear_documento_manual_usecase.dart';
import 'domain/usecases/crear_entidad_fiscal_usecase.dart';
import 'domain/usecases/crear_linea_comercial_usecase.dart';
import 'domain/usecases/crear_puesto_usecase.dart';
import 'domain/usecases/crear_servicio_usecase.dart';
import 'domain/usecases/crear_sucursal_usecase.dart';
import 'domain/usecases/crear_ubicacion_usecase.dart';
import 'domain/usecases/eliminar_area_fisicamente_usecase.dart';
import 'domain/usecases/eliminar_puesto_fisicamente_usecase.dart';
import 'domain/usecases/eliminar_sucursal_fisicamente_usecase.dart';
import 'domain/usecases/ensamblar_documento_por_emitir_usecase.dart';
import 'domain/usecases/generar_agenda_usecase.dart';
import 'domain/usecases/desactivar_area_usecase.dart';
import 'domain/usecases/entidad_fiscal_validator.dart';
import 'domain/usecases/guardar_area_resultado.dart';
import 'domain/usecases/guardar_direccion_operativa_servicio_usecase.dart';
import 'domain/usecases/guardar_domicilio_fiscal_usecase.dart';
import 'domain/usecases/guardar_expediente_cliente_usecase.dart';
import 'domain/usecases/guardar_expediente_empresa_usecase.dart';
import 'domain/usecases/guardar_expediente_sucursal_usecase.dart';
import 'domain/usecases/guardar_puesto_resultado.dart';
import 'domain/usecases/guardar_responsable_interno_usecase.dart';
import 'domain/usecases/guardar_servicio_resultado.dart';
import 'domain/usecases/guardar_sueldo_referencia_servicio_usecase.dart';
import 'domain/usecases/linea_comercial_validator.dart';
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
import 'domain/usecases/registrar_emision_documento_por_emitir_usecase.dart';
import 'domain/usecases/registrar_envio_documento_por_emitir_usecase.dart';
import 'domain/usecases/reemplazar_archivo_documento_por_emitir_usecase.dart';
import 'domain/usecases/obtener_arbol_ubicaciones_usecase.dart';
import 'domain/usecases/obtener_empresa_activa_usecase.dart';
import 'domain/usecases/obtener_expediente_cliente_usecase.dart';
import 'domain/usecases/obtener_expediente_empresa_usecase.dart';
import 'domain/usecases/obtener_expediente_puesto_usecase.dart';
import 'domain/usecases/obtener_expediente_servicio_usecase.dart';
import 'domain/usecases/obtener_expediente_sucursal_usecase.dart';
import 'domain/usecases/obtener_historial_configuracion_cobro_usecase.dart';
import 'domain/usecases/obtener_historial_linea_comercial_usecase.dart';
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

final generarNumeroUseCaseProvider = Provider<GenerarNumeroUseCase>((ref) {
  return GenerarNumeroUseCase(ref.watch(codigoSecuenciaServiceProvider));
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
  return ServicioRepositoryImpl(ref.watch(appDatabaseProvider), ref.watch(asignacionServicioRepositoryProvider));
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

final servicioComercialRepositoryProvider = Provider<ServicioComercialRepository>((ref) {
  return ServicioComercialRepositoryImpl(ref.watch(appDatabaseProvider), clock: ref.watch(clockProvider));
});

final configuracionCobroRepositoryProvider = Provider<ConfiguracionCobroRepository>((ref) {
  return ConfiguracionCobroRepositoryImpl(ref.watch(appDatabaseProvider), clock: ref.watch(clockProvider));
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
    ref.watch(servicioComercialRepositoryProvider),
    ref.watch(configuracionCobroRepositoryProvider),
    ref.watch(asignacionServicioRepositoryProvider),
    ref.watch(empleadoRepositoryProvider),
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

final guardarSueldoReferenciaServicioUseCaseProvider = Provider<GuardarSueldoReferenciaServicioUseCase>((ref) {
  return GuardarSueldoReferenciaServicioUseCase(ref.watch(servicioRepositoryProvider), ref.watch(servicioValidatorProvider));
});

final lineaComercialValidatorProvider = Provider<LineaComercialValidator>((ref) {
  return LineaComercialValidator(
    ref.watch(puestoRepositoryProvider),
    ref.watch(catalogoRepositoryProvider),
    ref.watch(servicioRepositoryProvider),
    ref.watch(configuracionCobroRepositoryProvider),
  );
});

final configuracionCobroValidatorProvider = Provider<ConfiguracionCobroValidator>((ref) {
  return ConfiguracionCobroValidator(
    ref.watch(servicioRepositoryProvider),
    ref.watch(entidadFiscalRepositoryProvider),
    ref.watch(catalogoRepositoryProvider),
    ref.watch(servicioComercialRepositoryProvider),
  );
});

final configuracionCobroReglaEventoValidatorProvider = Provider<ConfiguracionCobroReglaEventoValidator>((ref) {
  return const ConfiguracionCobroReglaEventoValidator();
});

final crearConfiguracionCobroUseCaseProvider = Provider<CrearConfiguracionCobroUseCase>((ref) {
  return CrearConfiguracionCobroUseCase(
    ref.watch(configuracionCobroRepositoryProvider),
    ref.watch(servicioRepositoryProvider),
    ref.watch(configuracionCobroValidatorProvider),
    ref.watch(configuracionCobroReglaEventoValidatorProvider),
  );
});

final cambiarVigenciaConfiguracionCobroUseCaseProvider = Provider<CambiarVigenciaConfiguracionCobroUseCase>((ref) {
  return CambiarVigenciaConfiguracionCobroUseCase(
    ref.watch(configuracionCobroRepositoryProvider),
    ref.watch(servicioRepositoryProvider),
    ref.watch(configuracionCobroValidatorProvider),
    ref.watch(configuracionCobroReglaEventoValidatorProvider),
  );
});

final cerrarConfiguracionCobroUseCaseProvider = Provider<CerrarConfiguracionCobroUseCase>((ref) {
  return CerrarConfiguracionCobroUseCase(ref.watch(configuracionCobroRepositoryProvider), ref.watch(clockProvider));
});

final cancelarVigenciaProgramadaConfiguracionCobroUseCaseProvider =
    Provider<CancelarVigenciaProgramadaConfiguracionCobroUseCase>((ref) {
  return CancelarVigenciaProgramadaConfiguracionCobroUseCase(
    ref.watch(configuracionCobroRepositoryProvider),
    ref.watch(clockProvider),
  );
});

final actualizarObservacionesConfiguracionCobroVigenciaUseCaseProvider =
    Provider<ActualizarObservacionesConfiguracionCobroVigenciaUseCase>((ref) {
  return ActualizarObservacionesConfiguracionCobroVigenciaUseCase(
    ref.watch(configuracionCobroRepositoryProvider),
    ref.watch(clockProvider),
  );
});

final obtenerHistorialConfiguracionCobroUseCaseProvider = Provider<ObtenerHistorialConfiguracionCobroUseCase>((ref) {
  return ObtenerHistorialConfiguracionCobroUseCase(
    ref.watch(configuracionCobroRepositoryProvider),
    ref.watch(entidadFiscalRepositoryProvider),
    ref.watch(catalogoRepositoryProvider),
    ref.watch(clockProvider),
  );
});

final crearLineaComercialUseCaseProvider = Provider<CrearLineaComercialUseCase>((ref) {
  return CrearLineaComercialUseCase(
    ref.watch(servicioComercialRepositoryProvider),
    ref.watch(servicioRepositoryProvider),
    ref.watch(lineaComercialValidatorProvider),
  );
});

final cambiarVigenciaLineaComercialUseCaseProvider = Provider<CambiarVigenciaLineaComercialUseCase>((ref) {
  return CambiarVigenciaLineaComercialUseCase(
    ref.watch(servicioComercialRepositoryProvider),
    ref.watch(servicioRepositoryProvider),
    ref.watch(lineaComercialValidatorProvider),
  );
});

final cerrarLineaComercialUseCaseProvider = Provider<CerrarLineaComercialUseCase>((ref) {
  return CerrarLineaComercialUseCase(ref.watch(servicioComercialRepositoryProvider), ref.watch(clockProvider));
});

final cancelarVigenciaProgramadaUseCaseProvider = Provider<CancelarVigenciaProgramadaUseCase>((ref) {
  return CancelarVigenciaProgramadaUseCase(ref.watch(servicioComercialRepositoryProvider), ref.watch(clockProvider));
});

final actualizarAnotacionesVigenciaUseCaseProvider = Provider<ActualizarAnotacionesVigenciaUseCase>((ref) {
  return ActualizarAnotacionesVigenciaUseCase(ref.watch(servicioComercialRepositoryProvider), ref.watch(clockProvider));
});

final obtenerHistorialLineaComercialUseCaseProvider = Provider<ObtenerHistorialLineaComercialUseCase>((ref) {
  return ObtenerHistorialLineaComercialUseCase(
    ref.watch(servicioComercialRepositoryProvider),
    ref.watch(puestoRepositoryProvider),
    ref.watch(catalogoRepositoryProvider),
    ref.watch(clockProvider),
  );
});

// --- Etapa 4I.1 — Agenda de documentos por emitir ---

final attachmentRepositoryProvider = Provider<AttachmentRepository>((ref) {
  return AttachmentRepository(ref.watch(appDatabaseProvider));
});

final attachmentStorageProvider = Provider<AttachmentStorage>((ref) {
  return AttachmentStorage(ref.watch(appPathsProvider).attachmentsDir);
});

final documentoPorEmitirRepositoryProvider = Provider<DocumentoPorEmitirRepository>((ref) {
  return DocumentoPorEmitirRepositoryImpl(
    ref.watch(appDatabaseProvider),
    ref.watch(attachmentRepositoryProvider),
    ref.watch(cuentaPorCobrarRepositoryProvider),
  );
});

final ensamblarDocumentoPorEmitirUseCaseProvider = Provider<EnsamblarDocumentoPorEmitirUseCase>((ref) {
  return EnsamblarDocumentoPorEmitirUseCase(
    ref.watch(servicioComercialRepositoryProvider),
    ref.watch(configuracionCobroRepositoryProvider),
  );
});

final generarAgendaUseCaseProvider = Provider<GenerarAgendaUseCase>((ref) {
  return GenerarAgendaUseCase(
    ref.watch(documentoPorEmitirRepositoryProvider),
    ref.watch(configuracionCobroRepositoryProvider),
    ref.watch(servicioRepositoryProvider),
    ref.watch(ensamblarDocumentoPorEmitirUseCaseProvider),
    ref.watch(generarCodigoUseCaseProvider),
  );
});

final crearDocumentoManualUseCaseProvider = Provider<CrearDocumentoManualUseCase>((ref) {
  return CrearDocumentoManualUseCase(
    ref.watch(documentoPorEmitirRepositoryProvider),
    ref.watch(configuracionCobroRepositoryProvider),
    ref.watch(ensamblarDocumentoPorEmitirUseCaseProvider),
    ref.watch(generarCodigoUseCaseProvider),
  );
});

final cambiarEstatusDocumentoPorEmitirUseCaseProvider = Provider<CambiarEstatusDocumentoPorEmitirUseCase>((ref) {
  return CambiarEstatusDocumentoPorEmitirUseCase(ref.watch(documentoPorEmitirRepositoryProvider));
});

final actualizarAjusteManualDocumentoPorEmitirUseCaseProvider =
    Provider<ActualizarAjusteManualDocumentoPorEmitirUseCase>((ref) {
  return ActualizarAjusteManualDocumentoPorEmitirUseCase(ref.watch(documentoPorEmitirRepositoryProvider));
});

// --- Etapa 4I.2.1 — Emisión, envío e historial administrativo ---

final registrarEmisionDocumentoPorEmitirUseCaseProvider =
    Provider<RegistrarEmisionDocumentoPorEmitirUseCase>((ref) {
  return RegistrarEmisionDocumentoPorEmitirUseCase(ref.watch(documentoPorEmitirRepositoryProvider));
});

final corregirDatosEmisionDocumentoPorEmitirUseCaseProvider =
    Provider<CorregirDatosEmisionDocumentoPorEmitirUseCase>((ref) {
  return CorregirDatosEmisionDocumentoPorEmitirUseCase(ref.watch(documentoPorEmitirRepositoryProvider));
});

final registrarEnvioDocumentoPorEmitirUseCaseProvider = Provider<RegistrarEnvioDocumentoPorEmitirUseCase>((ref) {
  return RegistrarEnvioDocumentoPorEmitirUseCase(ref.watch(documentoPorEmitirRepositoryProvider));
});

// --- Etapa 4I.2.2 — Adjuntos, ajuste manual e historial administrativo ---

final adjuntarArchivoDocumentoPorEmitirUseCaseProvider = Provider<AdjuntarArchivoDocumentoPorEmitirUseCase>((ref) {
  return AdjuntarArchivoDocumentoPorEmitirUseCase(
    ref.watch(documentoPorEmitirRepositoryProvider),
    ref.watch(attachmentStorageProvider),
  );
});

final reemplazarArchivoDocumentoPorEmitirUseCaseProvider = Provider<ReemplazarArchivoDocumentoPorEmitirUseCase>((ref) {
  return ReemplazarArchivoDocumentoPorEmitirUseCase(
    ref.watch(documentoPorEmitirRepositoryProvider),
    ref.watch(attachmentRepositoryProvider),
    ref.watch(attachmentStorageProvider),
  );
});

// --- Fachadas de aplicación autorizadas (Etapa 11C) ---
//
// Solo para operaciones de escritura que ninguna pantalla invoca a
// través de un Controller — el alta de Área/Puesto/Sucursal/Cliente/
// Servicio se llama directo desde el diálogo de alta contra su propio
// caso de uso (el Controller de listado de cada uno solo carga/recarga,
// nunca escribe), así que estas fachadas son el punto de entrada de
// aplicación más bajo y reutilizable que representa cada operación
// protegida. Mismo criterio que `personal_providers.dart` (Personal no
// tiene Controller de escritura en absoluto) — expuestas como
// `Provider<Función>`, nunca como función suelta que reciba `Ref`,
// porque `WidgetRef` (diálogos) y `ProviderContainer` (pruebas) no
// comparten más interfaz que `.read(provider)`.
//
// `ActivarAreaUseCase`/`ArchivarContactoUseCase`-style casos de uso sin
// tipo sellado propio (aquí: `ActivarAreaUseCase`, que devuelve
// `AreaData` a secas) usan `null` como su propio "no autorizado" en vez
// de inventar un tipo nuevo; los que devuelven `Result<T>` (Cliente,
// Sucursal) reutilizan `PermissionFailure`, ya definida en
// `core/error/failure.dart` para exactamente este caso y hasta ahora sin
// ningún uso real.

typedef CrearAreaAutorizado = Future<GuardarAreaResultado> Function({required String nombre, String? descripcion});

final crearAreaAutorizadoProvider = Provider<CrearAreaAutorizado>((ref) {
  return ({required String nombre, String? descripcion}) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'organizacion.crear',
      () => ref.read(crearAreaUseCaseProvider).ejecutar(nombre: nombre, descripcion: descripcion),
      GuardarAreaErrorInesperado.new,
    );
  };
});

typedef ActualizarAreaAutorizado = Future<GuardarAreaResultado> Function({
  required String id,
  required String nombre,
  String? descripcion,
});

final actualizarAreaAutorizadoProvider = Provider<ActualizarAreaAutorizado>((ref) {
  return ({required String id, required String nombre, String? descripcion}) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'organizacion.modificar',
      () => ref.read(actualizarAreaUseCaseProvider).ejecutar(id: id, nombre: nombre, descripcion: descripcion),
      GuardarAreaErrorInesperado.new,
    );
  };
});

typedef ActivarAreaAutorizado = Future<AreaData?> Function(String areaId);

final activarAreaAutorizadoProvider = Provider<ActivarAreaAutorizado>((ref) {
  return (String areaId) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'organizacion.archivar',
      () => ref.read(activarAreaUseCaseProvider).ejecutar(areaId),
      (mensaje) => null,
    );
  };
});

typedef DesactivarAreaAutorizado = Future<DesactivarAreaResultado> Function(String areaId);

final desactivarAreaAutorizadoProvider = Provider<DesactivarAreaAutorizado>((ref) {
  return (String areaId) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'organizacion.archivar',
      () => ref.read(desactivarAreaUseCaseProvider).ejecutar(areaId),
      DesactivarAreaErrorInesperado.new,
    );
  };
});

typedef CrearPuestoAutorizado = Future<GuardarPuestoResultado> Function(PuestoBorrador borrador);

final crearPuestoAutorizadoProvider = Provider<CrearPuestoAutorizado>((ref) {
  return (PuestoBorrador borrador) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'organizacion.crear',
      () => ref.read(crearPuestoUseCaseProvider).ejecutar(borrador),
      GuardarPuestoErrorInesperado.new,
    );
  };
});

typedef CrearSucursalAutorizado = Future<Result<SucursalData>> Function({
  required String nombre,
  required String tipoSucursalId,
});

final crearSucursalAutorizadoProvider = Provider<CrearSucursalAutorizado>((ref) {
  return ({required String nombre, required String tipoSucursalId}) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'organizacion.crear',
      () => ref.read(crearSucursalUseCaseProvider).ejecutar(nombre: nombre, tipoSucursalId: tipoSucursalId),
      (mensaje) => Result<SucursalData>.failure(PermissionFailure(mensaje)),
    );
  };
});

typedef CrearClienteAutorizado = Future<Result<ClienteData>> Function({
  required String nombreComercial,
  String? observaciones,
});

final crearClienteAutorizadoProvider = Provider<CrearClienteAutorizado>((ref) {
  return ({required String nombreComercial, String? observaciones}) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'comercial.crear',
      () => ref.read(crearClienteUseCaseProvider).ejecutar(nombreComercial: nombreComercial, observaciones: observaciones),
      (mensaje) => Result<ClienteData>.failure(PermissionFailure(mensaje)),
    );
  };
});

typedef CrearServicioAutorizado = Future<GuardarServicioResultado> Function({
  required String clienteId,
  required ServicioBorrador borrador,
});

final crearServicioAutorizadoProvider = Provider<CrearServicioAutorizado>((ref) {
  return ({required String clienteId, required ServicioBorrador borrador}) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'comercial.crear',
      () => ref.read(crearServicioUseCaseProvider).ejecutar(clienteId: clienteId, borrador: borrador),
      GuardarServicioErrorInesperado.new,
    );
  };
});

// --- Eliminación física extraordinaria (Etapa 11D) ---
//
// Facultad exclusiva del Usuario Maestro — `exigirMaestro` nunca
// consulta `PermisoUsuario`/`AuthorizationService.verificar`, así que
// ningún permiso dinámico puede otorgarla. El actor se resuelve aquí
// mismo, dentro del cierre — el diálogo nunca lo provee (mismo
// criterio que la resolución del permiso).
final eliminarAreaFisicamenteUseCaseProvider = Provider<EliminarAreaFisicamenteUseCase>((ref) {
  return EliminarAreaFisicamenteUseCase(ref.watch(areaRepositoryProvider));
});

typedef EliminarAreaFisicamenteAutorizado = Future<EliminarAreaFisicamenteResultado> Function({
  required String areaId,
  required String motivo,
});

final eliminarAreaFisicamenteAutorizadoProvider = Provider<EliminarAreaFisicamenteAutorizado>((ref) {
  return ({required String areaId, required String motivo}) {
    return exigirMaestro(
      ref.read(permissionServiceProvider),
      () => ref.read(eliminarAreaFisicamenteUseCaseProvider).ejecutar(
            areaId: areaId,
            motivo: motivo,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      EliminarAreaFisicamenteErrorInesperado.new,
    );
  };
});

final eliminarPuestoFisicamenteUseCaseProvider = Provider<EliminarPuestoFisicamenteUseCase>((ref) {
  return EliminarPuestoFisicamenteUseCase(ref.watch(puestoRepositoryProvider));
});

typedef EliminarPuestoFisicamenteAutorizado = Future<EliminarPuestoFisicamenteResultado> Function({
  required String puestoId,
  required String motivo,
});

final eliminarPuestoFisicamenteAutorizadoProvider = Provider<EliminarPuestoFisicamenteAutorizado>((ref) {
  return ({required String puestoId, required String motivo}) {
    return exigirMaestro(
      ref.read(permissionServiceProvider),
      () => ref.read(eliminarPuestoFisicamenteUseCaseProvider).ejecutar(
            puestoId: puestoId,
            motivo: motivo,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      EliminarPuestoFisicamenteErrorInesperado.new,
    );
  };
});

final eliminarSucursalFisicamenteUseCaseProvider = Provider<EliminarSucursalFisicamenteUseCase>((ref) {
  return EliminarSucursalFisicamenteUseCase(ref.watch(sucursalRepositoryProvider));
});

typedef EliminarSucursalFisicamenteAutorizado = Future<EliminarSucursalFisicamenteResultado> Function({
  required String sucursalId,
  required String motivo,
});

final eliminarSucursalFisicamenteAutorizadoProvider = Provider<EliminarSucursalFisicamenteAutorizado>((ref) {
  return ({required String sucursalId, required String motivo}) {
    return exigirMaestro(
      ref.read(permissionServiceProvider),
      () => ref.read(eliminarSucursalFisicamenteUseCaseProvider).ejecutar(
            sucursalId: sucursalId,
            motivo: motivo,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      EliminarSucursalFisicamenteErrorInesperado.new,
    );
  };
});
