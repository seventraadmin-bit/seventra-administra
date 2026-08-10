import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../organizacion/organizacion_providers.dart';
import '../personal/personal_providers.dart';
import 'data/pdf/resguardo_pdf_renderer.dart';
import 'data/repositories/articulo_repository_impl.dart';
import 'data/repositories/asignacion_repository_impl.dart';
import 'data/repositories/categoria_articulo_repository_impl.dart';
import 'data/repositories/inventario_repository_impl.dart';
import 'domain/repositories/articulo_repository.dart';
import 'domain/repositories/asignacion_repository.dart';
import 'domain/repositories/categoria_articulo_repository.dart';
import 'domain/repositories/inventario_repository.dart';
import 'domain/usecases/adjuntar_comprobante_movimiento_usecase.dart';
import 'domain/usecases/adjuntar_resguardo_firmado_usecase.dart';
import 'domain/usecases/archivar_articulo_usecase.dart';
import 'domain/usecases/archivar_categoria_articulo_usecase.dart';
import 'domain/usecases/archivar_variante_articulo_usecase.dart';
import 'domain/usecases/buscar_inventario_usecase.dart';
import 'domain/usecases/cancelar_descuento_inventario_usecase.dart';
import 'domain/usecases/cerrar_asignacion_usecase.dart';
import 'domain/usecases/corregir_articulo_usecase.dart';
import 'domain/usecases/crear_articulo_usecase.dart';
import 'domain/usecases/crear_asignacion_usecase.dart';
import 'domain/usecases/crear_categoria_articulo_usecase.dart';
import 'domain/usecases/crear_variante_articulo_usecase.dart';
import 'domain/usecases/generar_documento_resguardo_usecase.dart';
import 'domain/usecases/obtener_empleados_responsables_servicio_usecase.dart';
import 'domain/usecases/registrar_ajuste_usecase.dart';
import 'domain/usecases/registrar_baja_unidad_usecase.dart';
import 'domain/usecases/registrar_baja_usecase.dart';
import 'domain/usecases/registrar_entrada_unidad_usecase.dart';
import 'domain/usecases/registrar_entrada_usecase.dart';
import 'domain/usecases/reemplazar_asignacion_usecase.dart';

/// Providers del dominio Inventario (Etapa 7A) — nace aquí, separado
/// de `organizacion`/`personal`/`finanzas`/`nomina` (mismo criterio
/// que cada dominio nuevo desde 4J.1).
final categoriaArticuloRepositoryProvider = Provider<CategoriaArticuloRepository>((ref) {
  return CategoriaArticuloRepositoryImpl(ref.watch(appDatabaseProvider));
});

final crearCategoriaArticuloUseCaseProvider = Provider<CrearCategoriaArticuloUseCase>((ref) {
  return CrearCategoriaArticuloUseCase(ref.watch(categoriaArticuloRepositoryProvider));
});

final archivarCategoriaArticuloUseCaseProvider = Provider<ArchivarCategoriaArticuloUseCase>((ref) {
  return ArchivarCategoriaArticuloUseCase(ref.watch(categoriaArticuloRepositoryProvider));
});

final articuloRepositoryProvider = Provider<ArticuloRepository>((ref) {
  return ArticuloRepositoryImpl(ref.watch(appDatabaseProvider));
});

final crearArticuloUseCaseProvider = Provider<CrearArticuloUseCase>((ref) {
  return CrearArticuloUseCase(
    ref.watch(articuloRepositoryProvider),
    ref.watch(categoriaArticuloRepositoryProvider),
    ref.watch(generarCodigoUseCaseProvider),
  );
});

final corregirArticuloUseCaseProvider = Provider<CorregirArticuloUseCase>((ref) {
  return CorregirArticuloUseCase(ref.watch(articuloRepositoryProvider), ref.watch(categoriaArticuloRepositoryProvider));
});

final archivarArticuloUseCaseProvider = Provider<ArchivarArticuloUseCase>((ref) {
  return ArchivarArticuloUseCase(ref.watch(articuloRepositoryProvider));
});

final crearVarianteArticuloUseCaseProvider = Provider<CrearVarianteArticuloUseCase>((ref) {
  return CrearVarianteArticuloUseCase(ref.watch(articuloRepositoryProvider));
});

final archivarVarianteArticuloUseCaseProvider = Provider<ArchivarVarianteArticuloUseCase>((ref) {
  return ArchivarVarianteArticuloUseCase(ref.watch(articuloRepositoryProvider));
});

final inventarioRepositoryProvider = Provider<InventarioRepository>((ref) {
  return InventarioRepositoryImpl(ref.watch(appDatabaseProvider));
});

final registrarEntradaUseCaseProvider = Provider<RegistrarEntradaUseCase>((ref) {
  return RegistrarEntradaUseCase(ref.watch(inventarioRepositoryProvider), ref.watch(articuloRepositoryProvider));
});

final registrarEntradaUnidadUseCaseProvider = Provider<RegistrarEntradaUnidadUseCase>((ref) {
  return RegistrarEntradaUnidadUseCase(
    ref.watch(inventarioRepositoryProvider),
    ref.watch(articuloRepositoryProvider),
    ref.watch(generarCodigoUseCaseProvider),
  );
});

final registrarBajaUseCaseProvider = Provider<RegistrarBajaUseCase>((ref) {
  return RegistrarBajaUseCase(ref.watch(inventarioRepositoryProvider), ref.watch(articuloRepositoryProvider));
});

final registrarBajaUnidadUseCaseProvider = Provider<RegistrarBajaUnidadUseCase>((ref) {
  return RegistrarBajaUnidadUseCase(ref.watch(inventarioRepositoryProvider));
});

final registrarAjusteUseCaseProvider = Provider<RegistrarAjusteUseCase>((ref) {
  return RegistrarAjusteUseCase(ref.watch(inventarioRepositoryProvider), ref.watch(articuloRepositoryProvider));
});

final adjuntarComprobanteMovimientoUseCaseProvider = Provider<AdjuntarComprobanteMovimientoUseCase>((ref) {
  return AdjuntarComprobanteMovimientoUseCase(ref.watch(inventarioRepositoryProvider), ref.watch(attachmentStorageProvider));
});

/// Providers de Asignaciones (Etapa 7B).
final asignacionRepositoryProvider = Provider<AsignacionRepository>((ref) {
  return AsignacionRepositoryImpl(ref.watch(appDatabaseProvider));
});

final crearAsignacionUseCaseProvider = Provider<CrearAsignacionUseCase>((ref) {
  return CrearAsignacionUseCase(
    ref.watch(asignacionRepositoryProvider),
    ref.watch(articuloRepositoryProvider),
    ref.watch(inventarioRepositoryProvider),
  );
});

final cerrarAsignacionUseCaseProvider = Provider<CerrarAsignacionUseCase>((ref) {
  return CerrarAsignacionUseCase(ref.watch(asignacionRepositoryProvider));
});

final reemplazarAsignacionUseCaseProvider = Provider<ReemplazarAsignacionUseCase>((ref) {
  return ReemplazarAsignacionUseCase(
    ref.watch(asignacionRepositoryProvider),
    ref.watch(articuloRepositoryProvider),
    ref.watch(inventarioRepositoryProvider),
  );
});

final cancelarDescuentoInventarioUseCaseProvider = Provider<CancelarDescuentoInventarioUseCase>((ref) {
  return CancelarDescuentoInventarioUseCase(ref.watch(asignacionRepositoryProvider));
});

/// Dependencia cruzada al dominio `personal` (lectura) — mismo patrón
/// ya establecido por `organizacion_providers.dart` al componer
/// `ObtenerExpedienteServicioUseCaseProvider`. La UI de Inventario
/// nunca importa `personal_providers.dart` directamente: solo conoce
/// este caso de uso.
final obtenerEmpleadosResponsablesServicioUseCaseProvider = Provider<ObtenerEmpleadosResponsablesServicioUseCase>((ref) {
  return ObtenerEmpleadosResponsablesServicioUseCase(
    ref.watch(asignacionServicioRepositoryProvider),
    ref.watch(empleadoRepositoryProvider),
  );
});

/// Providers de Documentos de resguardo (Etapa 7C).
final resguardoPdfRendererProvider = Provider<ResguardoPdfRenderer>((ref) => ResguardoPdfRenderer());

final generarDocumentoResguardoUseCaseProvider = Provider<GenerarDocumentoResguardoUseCase>((ref) {
  return GenerarDocumentoResguardoUseCase(
    ref.watch(asignacionRepositoryProvider),
    ref.watch(articuloRepositoryProvider),
    ref.watch(inventarioRepositoryProvider),
    ref.watch(empleadoRepositoryProvider),
    ref.watch(servicioRepositoryProvider),
    ref.watch(empresaRepositoryProvider),
    ref.watch(attachmentRepositoryProvider),
    ref.watch(attachmentStorageProvider),
    ref.watch(resguardoPdfRendererProvider),
  );
});

final adjuntarResguardoFirmadoUseCaseProvider = Provider<AdjuntarResguardoFirmadoUseCase>((ref) {
  return AdjuntarResguardoFirmadoUseCase(ref.watch(asignacionRepositoryProvider), ref.watch(attachmentStorageProvider));
});

/// Providers de Reportes (Etapa 7D) — cero tablas nuevas, todo se
/// deriva de los repositorios ya existentes.
final buscarInventarioUseCaseProvider = Provider<BuscarInventarioUseCase>((ref) {
  return BuscarInventarioUseCase(
    ref.watch(articuloRepositoryProvider),
    ref.watch(inventarioRepositoryProvider),
    ref.watch(empleadoRepositoryProvider),
    ref.watch(servicioRepositoryProvider),
  );
});
