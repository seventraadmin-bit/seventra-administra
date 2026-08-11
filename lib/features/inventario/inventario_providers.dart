import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/permissions/authorization_service.dart';
import '../compras/compras_providers.dart' show compraRepositoryProvider;
import '../organizacion/organizacion_providers.dart';
import '../personal/personal_providers.dart';
import '../usuarios/presentation/sesion_controller.dart';
import '../usuarios/usuarios_providers.dart';
import 'data/pdf/resguardo_pdf_renderer.dart';
import 'data/repositories/articulo_repository_impl.dart';
import 'data/repositories/asignacion_repository_impl.dart';
import 'data/repositories/categoria_articulo_repository_impl.dart';
import 'data/repositories/inventario_repository_impl.dart';
import 'data/tables/asignacion_table.dart' show MotivoCierreAsignacion;
import 'domain/repositories/articulo_repository.dart';
import 'domain/repositories/asignacion_repository.dart';
import 'domain/repositories/categoria_articulo_repository.dart';
import 'domain/repositories/inventario_repository.dart';
import 'domain/usecases/actualizar_categoria_articulo_usecase.dart';
import 'domain/usecases/adjuntar_comprobante_movimiento_usecase.dart';
import 'domain/usecases/adjuntar_resguardo_firmado_usecase.dart';
import 'domain/usecases/archivar_articulo_usecase.dart';
import 'domain/usecases/archivar_categoria_articulo_usecase.dart';
import 'domain/usecases/archivar_variante_articulo_usecase.dart';
import 'domain/usecases/buscar_inventario_usecase.dart';
import 'domain/usecases/cambiar_responsable_asignacion_usecase.dart';
import 'domain/usecases/cancelar_descuento_inventario_usecase.dart';
import 'domain/usecases/cerrar_asignacion_usecase.dart';
import 'domain/usecases/corregir_articulo_usecase.dart';
import 'domain/usecases/crear_articulo_usecase.dart';
import 'domain/usecases/crear_asignacion_usecase.dart';
import 'domain/usecases/crear_categoria_articulo_usecase.dart';
import 'domain/usecases/crear_variante_articulo_usecase.dart';
import 'domain/usecases/eliminar_articulo_fisicamente_usecase.dart';
import 'domain/usecases/eliminar_categoria_articulo_fisicamente_usecase.dart';
import 'domain/usecases/generar_documento_resguardo_usecase.dart';
import 'domain/usecases/obtener_empleados_responsables_servicio_usecase.dart';
import 'domain/usecases/obtener_opciones_responsable_asignacion_usecase.dart';
import 'domain/usecases/obtener_origen_compra_usecase.dart';
import 'domain/usecases/registrar_ajuste_usecase.dart';
import 'domain/usecases/registrar_baja_unidad_usecase.dart';
import 'domain/usecases/registrar_baja_usecase.dart';
import 'domain/usecases/registrar_entrada_unidad_usecase.dart';
import 'domain/usecases/registrar_entrada_usecase.dart';
import 'domain/usecases/regularizar_articulo_serializado_usecase.dart';
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

final actualizarCategoriaArticuloUseCaseProvider = Provider<ActualizarCategoriaArticuloUseCase>((ref) {
  return ActualizarCategoriaArticuloUseCase(ref.watch(categoriaArticuloRepositoryProvider));
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

/// Lectura cruzada hacia Compras (Etapa 10) — ver el doc comment de
/// `ObtenerOrigenCompraUseCase`.
final obtenerOrigenCompraUseCaseProvider = Provider<ObtenerOrigenCompraUseCase>((ref) {
  return ObtenerOrigenCompraUseCase(ref.watch(compraRepositoryProvider));
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

/// Etapa 9D (ajuste posterior a la aprobación inicial) — "cambiar
/// responsable" del mismo bien, distinto de `reemplazar` (cambia el
/// bien). Vive en Inventario porque `Asignacion` sigue siendo la única
/// fuente de verdad de la custodia física — Telefonía solo la consume
/// desde el expediente del Equipo, nunca la reimplementa.
final cambiarResponsableAsignacionUseCaseProvider = Provider<CambiarResponsableAsignacionUseCase>((ref) {
  return CambiarResponsableAsignacionUseCase(ref.watch(asignacionRepositoryProvider));
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

/// Etapa 9D (ajuste posterior) — candidatos a nuevo responsable al
/// cambiar quién tiene un bien, sin acotar a un Servicio en particular.
final obtenerOpcionesResponsableAsignacionUseCaseProvider =
    Provider<ObtenerOpcionesResponsableAsignacionUseCase>((ref) {
  return ObtenerOpcionesResponsableAsignacionUseCase(
    ref.watch(empleadoRepositoryProvider),
    ref.watch(servicioRepositoryProvider),
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

// --- Fachadas autorizadas (Etapa 11C) ---
//
// Asignaciones se opera desde diálogos que llaman directamente a estos
// casos de uso (sin pasar por `ArticulosController`), mismo motivo que
// las fachadas de `personal_providers.dart`: la verificación tiene que
// vivir en un punto reutilizable incluso sin UI, y `WidgetRef`/`Ref` no
// son intercambiables, así que la fachada es un `Provider` que
// devuelve un cierre ya cerrado sobre `ref`.
typedef CrearAsignacionAutorizado = Future<CrearAsignacionResultado> Function({
  required String articuloId,
  String? varianteId,
  String? unidadId,
  required int cantidad,
  String? empleadoId,
  String? servicioId,
  required DateTime fechaEntrega,
  String? condicionEntrega,
  String? observaciones,
});

final crearAsignacionAutorizadoProvider = Provider<CrearAsignacionAutorizado>((ref) {
  return ({
    required String articuloId,
    String? varianteId,
    String? unidadId,
    required int cantidad,
    String? empleadoId,
    String? servicioId,
    required DateTime fechaEntrega,
    String? condicionEntrega,
    String? observaciones,
  }) {
    final actorUsuarioId = ref.read(sesionControllerProvider)?.usuarioId;
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'inventario.crear',
      () => ref.read(crearAsignacionUseCaseProvider).ejecutar(
            articuloId: articuloId,
            varianteId: varianteId,
            unidadId: unidadId,
            cantidad: cantidad,
            empleadoId: empleadoId,
            servicioId: servicioId,
            fechaEntrega: fechaEntrega,
            condicionEntrega: condicionEntrega,
            observaciones: observaciones,
            actorUsuarioId: actorUsuarioId,
          ),
      CrearAsignacionErrorInesperado.new,
    );
  };
});

typedef CerrarAsignacionAutorizado = Future<CerrarAsignacionResultado> Function({
  required String asignacionId,
  required MotivoCierreAsignacion motivo,
  required DateTime fechaCierre,
  String? observacionesCierre,
  bool? atribuibleAlEmpleado,
  bool generaDescuento,
  int? importeDescuento,
  String? empleadoResponsableDescuentoId,
});

final cerrarAsignacionAutorizadoProvider = Provider<CerrarAsignacionAutorizado>((ref) {
  return ({
    required String asignacionId,
    required MotivoCierreAsignacion motivo,
    required DateTime fechaCierre,
    String? observacionesCierre,
    bool? atribuibleAlEmpleado,
    bool generaDescuento = false,
    int? importeDescuento,
    String? empleadoResponsableDescuentoId,
  }) {
    final actorUsuarioId = ref.read(sesionControllerProvider)?.usuarioId;
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'inventario.modificar',
      () => ref.read(cerrarAsignacionUseCaseProvider).ejecutar(
            asignacionId: asignacionId,
            motivo: motivo,
            fechaCierre: fechaCierre,
            observacionesCierre: observacionesCierre,
            atribuibleAlEmpleado: atribuibleAlEmpleado,
            generaDescuento: generaDescuento,
            importeDescuento: importeDescuento,
            empleadoResponsableDescuentoId: empleadoResponsableDescuentoId,
            actorUsuarioId: actorUsuarioId,
          ),
      CerrarAsignacionErrorInesperado.new,
    );
  };
});

typedef CambiarResponsableAsignacionAutorizado = Future<CambiarResponsableAsignacionResultado> Function({
  required String asignacionId,
  String? nuevoEmpleadoId,
  String? nuevoServicioId,
  required DateTime fecha,
  String? observaciones,
});

final cambiarResponsableAsignacionAutorizadoProvider = Provider<CambiarResponsableAsignacionAutorizado>((ref) {
  return ({
    required String asignacionId,
    String? nuevoEmpleadoId,
    String? nuevoServicioId,
    required DateTime fecha,
    String? observaciones,
  }) {
    final actorUsuarioId = ref.read(sesionControllerProvider)?.usuarioId;
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'inventario.modificar',
      () => ref.read(cambiarResponsableAsignacionUseCaseProvider).ejecutar(
            asignacionId: asignacionId,
            nuevoEmpleadoId: nuevoEmpleadoId,
            nuevoServicioId: nuevoServicioId,
            fecha: fecha,
            observaciones: observaciones,
            actorUsuarioId: actorUsuarioId,
          ),
      CambiarResponsableAsignacionErrorInesperado.new,
    );
  };
});

typedef ReemplazarAsignacionAutorizado = Future<ReemplazarAsignacionResultado> Function({
  required String asignacionId,
  required MotivoCierreAsignacion motivo,
  required DateTime fechaCierre,
  String? observacionesCierre,
  bool? atribuibleAlEmpleado,
  bool generaDescuento,
  int? importeDescuento,
  String? empleadoResponsableDescuentoId,
  required String articuloIdReemplazo,
  String? varianteIdReemplazo,
  String? unidadIdReemplazo,
  required int cantidadReemplazo,
  String? condicionEntregaReemplazo,
  String? observacionesReemplazo,
});

final reemplazarAsignacionAutorizadoProvider = Provider<ReemplazarAsignacionAutorizado>((ref) {
  return ({
    required String asignacionId,
    required MotivoCierreAsignacion motivo,
    required DateTime fechaCierre,
    String? observacionesCierre,
    bool? atribuibleAlEmpleado,
    bool generaDescuento = false,
    int? importeDescuento,
    String? empleadoResponsableDescuentoId,
    required String articuloIdReemplazo,
    String? varianteIdReemplazo,
    String? unidadIdReemplazo,
    required int cantidadReemplazo,
    String? condicionEntregaReemplazo,
    String? observacionesReemplazo,
  }) {
    final actorUsuarioId = ref.read(sesionControllerProvider)?.usuarioId;
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'inventario.modificar',
      () => ref.read(reemplazarAsignacionUseCaseProvider).ejecutar(
            asignacionId: asignacionId,
            motivo: motivo,
            fechaCierre: fechaCierre,
            observacionesCierre: observacionesCierre,
            atribuibleAlEmpleado: atribuibleAlEmpleado,
            generaDescuento: generaDescuento,
            importeDescuento: importeDescuento,
            empleadoResponsableDescuentoId: empleadoResponsableDescuentoId,
            articuloIdReemplazo: articuloIdReemplazo,
            varianteIdReemplazo: varianteIdReemplazo,
            unidadIdReemplazo: unidadIdReemplazo,
            cantidadReemplazo: cantidadReemplazo,
            condicionEntregaReemplazo: condicionEntregaReemplazo,
            observacionesReemplazo: observacionesReemplazo,
            actorUsuarioId: actorUsuarioId,
          ),
      ReemplazarAsignacionErrorInesperado.new,
    );
  };
});

typedef AdjuntarResguardoFirmadoAutorizado = Future<AdjuntarResguardoFirmadoResultado> Function({
  required List<String> asignacionIds,
  required String sourceFilePath,
  required String originalFileName,
  required String mimeType,
});

final adjuntarResguardoFirmadoAutorizadoProvider = Provider<AdjuntarResguardoFirmadoAutorizado>((ref) {
  return ({
    required List<String> asignacionIds,
    required String sourceFilePath,
    required String originalFileName,
    required String mimeType,
  }) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'inventario.modificar',
      () => ref.read(adjuntarResguardoFirmadoUseCaseProvider).ejecutar(
            asignacionIds: asignacionIds,
            sourceFilePath: sourceFilePath,
            originalFileName: originalFileName,
            mimeType: mimeType,
          ),
      AdjuntarResguardoFirmadoErrorInesperado.new,
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
final eliminarArticuloFisicamenteUseCaseProvider = Provider<EliminarArticuloFisicamenteUseCase>((ref) {
  return EliminarArticuloFisicamenteUseCase(ref.watch(articuloRepositoryProvider));
});

typedef EliminarArticuloFisicamenteAutorizado = Future<EliminarArticuloFisicamenteResultado> Function({
  required String articuloId,
  required String motivo,
});

final eliminarArticuloFisicamenteAutorizadoProvider = Provider<EliminarArticuloFisicamenteAutorizado>((ref) {
  return ({required String articuloId, required String motivo}) {
    return exigirMaestro(
      ref.read(permissionServiceProvider),
      () => ref.read(eliminarArticuloFisicamenteUseCaseProvider).ejecutar(
            articuloId: articuloId,
            motivo: motivo,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      EliminarArticuloFisicamenteErrorInesperado.new,
    );
  };
});

final eliminarCategoriaArticuloFisicamenteUseCaseProvider =
    Provider<EliminarCategoriaArticuloFisicamenteUseCase>((ref) {
  return EliminarCategoriaArticuloFisicamenteUseCase(ref.watch(categoriaArticuloRepositoryProvider));
});

typedef EliminarCategoriaArticuloFisicamenteAutorizado = Future<EliminarCategoriaArticuloFisicamenteResultado>
    Function({required String categoriaArticuloId, required String motivo});

final eliminarCategoriaArticuloFisicamenteAutorizadoProvider =
    Provider<EliminarCategoriaArticuloFisicamenteAutorizado>((ref) {
  return ({required String categoriaArticuloId, required String motivo}) {
    return exigirMaestro(
      ref.read(permissionServiceProvider),
      () => ref.read(eliminarCategoriaArticuloFisicamenteUseCaseProvider).ejecutar(
            categoriaArticuloId: categoriaArticuloId,
            motivo: motivo,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      EliminarCategoriaArticuloFisicamenteErrorInesperado.new,
    );
  };
});

// --- Regularización de existencia legacy (Etapa 9D, ajuste posterior) ---
//
// Misma facultad exclusiva del Usuario Maestro que la eliminación
// física de arriba — `exigirMaestro`, actor resuelto aquí mismo.
final regularizarArticuloSerializadoUseCaseProvider = Provider<RegularizarArticuloSerializadoUseCase>((ref) {
  return RegularizarArticuloSerializadoUseCase(
    ref.watch(articuloRepositoryProvider),
    ref.watch(inventarioRepositoryProvider),
    ref.watch(generarCodigoUseCaseProvider),
  );
});

typedef RegularizarArticuloSerializadoAutorizado = Future<RegularizarArticuloSerializadoResultado> Function({
  required String articuloId,
  required String movimientoInventarioId,
  required List<DatosUnidadRegularizacionInput> unidades,
});

final regularizarArticuloSerializadoAutorizadoProvider = Provider<RegularizarArticuloSerializadoAutorizado>((ref) {
  return ({required String articuloId, required String movimientoInventarioId, required List<DatosUnidadRegularizacionInput> unidades}) {
    return exigirMaestro(
      ref.read(permissionServiceProvider),
      () => ref.read(regularizarArticuloSerializadoUseCaseProvider).ejecutar(
            articuloId: articuloId,
            movimientoInventarioId: movimientoInventarioId,
            unidades: unidades,
          ),
      RegularizarArticuloSerializadoErrorInesperado.new,
    );
  };
});
