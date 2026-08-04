import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/codigos/codigo_secuencia_service.dart';
import '../../core/codigos/generar_codigo_usecase.dart';
import '../../core/di/providers.dart';
import 'data/repositories/cliente_repository_impl.dart';
import 'data/repositories/empresa_repository_impl.dart';
import 'data/repositories/puesto_repository_impl.dart';
import 'data/repositories/servicio_repository_impl.dart';
import 'data/repositories/sucursal_repository_impl.dart';
import 'data/repositories/ubicacion_repository_impl.dart';
import 'domain/repositories/cliente_repository.dart';
import 'domain/repositories/empresa_repository.dart';
import 'domain/repositories/puesto_repository.dart';
import 'domain/repositories/servicio_repository.dart';
import 'domain/repositories/sucursal_repository.dart';
import 'domain/repositories/ubicacion_repository.dart';
import 'domain/usecases/actualizar_empresa_usecase.dart';
import 'domain/usecases/crear_cliente_usecase.dart';
import 'domain/usecases/crear_puesto_usecase.dart';
import 'domain/usecases/crear_servicio_usecase.dart';
import 'domain/usecases/crear_sucursal_usecase.dart';
import 'domain/usecases/crear_ubicacion_usecase.dart';
import 'domain/usecases/mover_ubicacion_usecase.dart';
import 'domain/usecases/obtener_arbol_ubicaciones_usecase.dart';
import 'domain/usecases/obtener_empresa_activa_usecase.dart';

/// Providers de la Etapa 4A (Fundamentos de Organización).
///
/// Deliberadamente solo expone base de datos/servicios/repositorios/
/// casos de uso — ningún controlador de pantalla, estado de formulario
/// ni provider de listas para UI todavía. Eso empieza en la Etapa 4B.

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

final obtenerEmpresaActivaUseCaseProvider = Provider<ObtenerEmpresaActivaUseCase>((ref) {
  return ObtenerEmpresaActivaUseCase(ref.watch(empresaRepositoryProvider));
});

final actualizarEmpresaUseCaseProvider = Provider<ActualizarEmpresaUseCase>((ref) {
  return ActualizarEmpresaUseCase(ref.watch(empresaRepositoryProvider));
});

final crearPuestoUseCaseProvider = Provider<CrearPuestoUseCase>((ref) {
  return CrearPuestoUseCase(ref.watch(puestoRepositoryProvider), ref.watch(generarCodigoUseCaseProvider));
});

final crearSucursalUseCaseProvider = Provider<CrearSucursalUseCase>((ref) {
  return CrearSucursalUseCase(
    ref.watch(sucursalRepositoryProvider),
    ref.watch(generarCodigoUseCaseProvider),
  );
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

final crearClienteUseCaseProvider = Provider<CrearClienteUseCase>((ref) {
  return CrearClienteUseCase(ref.watch(clienteRepositoryProvider), ref.watch(generarCodigoUseCaseProvider));
});

final crearServicioUseCaseProvider = Provider<CrearServicioUseCase>((ref) {
  return CrearServicioUseCase(
    ref.watch(servicioRepositoryProvider),
    ref.watch(clienteRepositoryProvider),
    ref.watch(generarCodigoUseCaseProvider),
  );
});
