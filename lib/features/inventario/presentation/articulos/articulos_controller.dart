import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/permissions/authorization_service.dart';
import 'package:riseg_one/features/inventario/domain/usecases/adjuntar_comprobante_movimiento_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/archivar_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/archivar_categoria_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/archivar_variante_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/corregir_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_categoria_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_variante_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/existencia_articulo.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_ajuste_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_baja_unidad_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_baja_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_entrada_unidad_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_entrada_usecase.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

import '../../inventario_providers.dart';
import 'articulos_state.dart';

part 'articulos_controller.g.dart';

/// Controlador de Artículos (Etapa 7A) — listado del catálogo con
/// existencia derivada, y todas las operaciones de expediente
/// (variantes, unidades, movimientos). Un solo controlador para
/// listado + expediente, mismo criterio que `NominasController`.
@riverpod
class ArticulosController extends _$ArticulosController {
  @override
  ArticulosState build() {
    Future.microtask(_cargar);
    return const ArticulosState();
  }

  /// Usuario autenticado que ejecuta la operación (Etapa 11D) — mismo
  /// criterio que `UsuariosController._actorUsuarioId`.
  String? get _actorUsuarioId => ref.read(sesionControllerProvider)?.usuarioId;

  Future<void> _cargar() async {
    state = state.copyWith(cargando: true, errorCarga: null);
    try {
      final articuloRepo = ref.read(articuloRepositoryProvider);
      final categoriaRepo = ref.read(categoriaArticuloRepositoryProvider);
      final inventarioRepo = ref.read(inventarioRepositoryProvider);

      final categorias = await categoriaRepo.listar();
      final categoriasPorId = {for (final c in categorias) c.id: c.nombre};

      final articulos = await articuloRepo.listar();
      final resumenes = <ArticuloResumen>[];
      for (final articulo in articulos) {
        final existencia = articulo.manejaSerie
            ? await inventarioRepo.calcularExistenciaUnidades(articulo.id)
            : await inventarioRepo.calcularExistencia(articuloId: articulo.id);
        resumenes.add(
          ArticuloResumen(
            articulo: articulo,
            categoriaNombre: categoriasPorId[articulo.categoriaId] ?? '',
            existencia: existencia,
          ),
        );
      }

      state = state.copyWith(cargando: false, articulos: resumenes, categorias: categorias, errorCarga: null);
    } catch (e) {
      state = state.copyWith(cargando: false, errorCarga: e.toString());
    }
  }

  Future<void> reintentarCarga() => _cargar();

  Future<void> recargar() => _cargar();

  Future<ArticuloData?> obtenerArticulo(String articuloId) {
    return ref.read(articuloRepositoryProvider).obtenerPorId(articuloId);
  }

  Future<String?> obtenerCategoriaNombre(String categoriaId) async {
    final categoria = await ref.read(categoriaArticuloRepositoryProvider).obtenerPorId(categoriaId);
    return categoria?.nombre;
  }

  Future<ExistenciaArticulo> calcularExistencia({required String articuloId, String? varianteId}) {
    return ref.read(inventarioRepositoryProvider).calcularExistencia(articuloId: articuloId, varianteId: varianteId);
  }

  Future<ExistenciaArticulo> calcularExistenciaUnidades(String articuloId) {
    return ref.read(inventarioRepositoryProvider).calcularExistenciaUnidades(articuloId);
  }

  Future<List<ArticuloVarianteData>> listarVariantes(String articuloId) {
    return ref.read(articuloRepositoryProvider).listarVariantes(articuloId);
  }

  Future<List<ArticuloUnidadData>> listarUnidades(String articuloId) {
    return ref.read(inventarioRepositoryProvider).listarUnidades(articuloId);
  }

  Future<List<MovimientoInventarioData>> listarMovimientos(String articuloId) {
    return ref.read(inventarioRepositoryProvider).listarMovimientos(articuloId: articuloId);
  }

  // --- Categorías ---

  Future<CrearCategoriaArticuloResultado> crearCategoria(String nombre) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'inventario.crear',
      () => ref.read(crearCategoriaArticuloUseCaseProvider).ejecutar(nombre: nombre),
      CrearCategoriaArticuloErrorInesperado.new,
    );
    if (resultado is CrearCategoriaArticuloExitoso) await _cargar();
    return resultado;
  }

  Future<ArchivarCategoriaArticuloResultado> archivarCategoria(String categoriaId) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'inventario.archivar',
      () => ref.read(archivarCategoriaArticuloUseCaseProvider).ejecutar(categoriaId),
      ArchivarCategoriaArticuloErrorInesperado.new,
    );
    if (resultado is ArchivarCategoriaArticuloExitoso) await _cargar();
    return resultado;
  }

  // --- Artículo ---

  Future<CrearArticuloResultado> crearArticulo({
    required String categoriaId,
    required String nombre,
    String? descripcion,
    String? unidadMedida,
    required bool manejaVariante,
    required bool manejaSerie,
    int? costoReferencia,
  }) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'inventario.crear',
      () => ref.read(crearArticuloUseCaseProvider).ejecutar(
            categoriaId: categoriaId,
            nombre: nombre,
            descripcion: descripcion,
            unidadMedida: unidadMedida,
            manejaVariante: manejaVariante,
            manejaSerie: manejaSerie,
            costoReferencia: costoReferencia,
          ),
      CrearArticuloErrorInesperado.new,
    );
    if (resultado is CrearArticuloExitoso) await _cargar();
    return resultado;
  }

  Future<CorregirArticuloResultado> corregirArticulo({
    required String articuloId,
    String? categoriaId,
    String? nombre,
    String? descripcion,
    String? unidadMedida,
    int? costoReferencia,
    bool limpiarDescripcion = false,
    bool limpiarCostoReferencia = false,
  }) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'inventario.modificar',
      () => ref.read(corregirArticuloUseCaseProvider).ejecutar(
            articuloId: articuloId,
            categoriaId: categoriaId,
            nombre: nombre,
            descripcion: descripcion,
            unidadMedida: unidadMedida,
            costoReferencia: costoReferencia,
            limpiarDescripcion: limpiarDescripcion,
            limpiarCostoReferencia: limpiarCostoReferencia,
          ),
      CorregirArticuloErrorInesperado.new,
    );
    if (resultado is CorregirArticuloExitoso) await _cargar();
    return resultado;
  }

  Future<ArchivarArticuloResultado> archivarArticulo(String articuloId) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'inventario.archivar',
      () => ref.read(archivarArticuloUseCaseProvider).ejecutar(articuloId),
      ArchivarArticuloErrorInesperado.new,
    );
    if (resultado is ArchivarArticuloExitoso) await _cargar();
    return resultado;
  }

  // --- Variantes ---

  Future<CrearVarianteArticuloResultado> crearVariante({required String articuloId, required String valor}) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'inventario.crear',
      () => ref.read(crearVarianteArticuloUseCaseProvider).ejecutar(articuloId: articuloId, valor: valor),
      CrearVarianteArticuloErrorInesperado.new,
    );
  }

  Future<ArchivarVarianteArticuloResultado> archivarVariante(String varianteId) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'inventario.archivar',
      () => ref.read(archivarVarianteArticuloUseCaseProvider).ejecutar(varianteId),
      ArchivarVarianteArticuloErrorInesperado.new,
    );
  }

  // --- Movimientos ---

  Future<RegistrarEntradaResultado> registrarEntrada({
    required String articuloId,
    String? varianteId,
    required int cantidad,
    int? costoUnitario,
    required DateTime fecha,
    String? observaciones,
  }) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'inventario.crear',
      () => ref.read(registrarEntradaUseCaseProvider).ejecutar(
            articuloId: articuloId,
            varianteId: varianteId,
            cantidad: cantidad,
            costoUnitario: costoUnitario,
            fecha: fecha,
            observaciones: observaciones,
            actorUsuarioId: _actorUsuarioId,
          ),
      RegistrarEntradaErrorInesperado.new,
    );
  }

  Future<RegistrarEntradaUnidadResultado> registrarEntradaUnidad({
    required String articuloId,
    required String numeroSerie,
    String? marca,
    String? modelo,
    String? imei,
    String? numeroTelefonico,
    int? costoUnitario,
    required DateTime fecha,
    String? observaciones,
  }) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'inventario.crear',
      () => ref.read(registrarEntradaUnidadUseCaseProvider).ejecutar(
            articuloId: articuloId,
            numeroSerie: numeroSerie,
            marca: marca,
            modelo: modelo,
            imei: imei,
            numeroTelefonico: numeroTelefonico,
            costoUnitario: costoUnitario,
            fecha: fecha,
            observaciones: observaciones,
            actorUsuarioId: _actorUsuarioId,
          ),
      RegistrarEntradaUnidadErrorInesperado.new,
    );
  }

  Future<RegistrarBajaResultado> registrarBaja({
    required String articuloId,
    String? varianteId,
    required int cantidad,
    required String observaciones,
  }) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'inventario.archivar',
      () => ref.read(registrarBajaUseCaseProvider).ejecutar(
            articuloId: articuloId,
            varianteId: varianteId,
            cantidad: cantidad,
            observaciones: observaciones,
            actorUsuarioId: _actorUsuarioId,
          ),
      RegistrarBajaErrorInesperado.new,
    );
  }

  Future<RegistrarBajaUnidadResultado> registrarBajaUnidad({required String unidadId, required String observaciones}) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'inventario.archivar',
      () => ref.read(registrarBajaUnidadUseCaseProvider).ejecutar(
            unidadId: unidadId,
            observaciones: observaciones,
            actorUsuarioId: _actorUsuarioId,
          ),
      RegistrarBajaUnidadErrorInesperado.new,
    );
  }

  Future<RegistrarAjusteResultado> registrarAjuste({
    required String articuloId,
    String? varianteId,
    required int cantidad,
    required bool esEntrada,
    required String observaciones,
  }) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'inventario.modificar',
      () => ref.read(registrarAjusteUseCaseProvider).ejecutar(
            articuloId: articuloId,
            varianteId: varianteId,
            cantidad: cantidad,
            esEntrada: esEntrada,
            observaciones: observaciones,
            actorUsuarioId: _actorUsuarioId,
          ),
      RegistrarAjusteErrorInesperado.new,
    );
  }

  Future<AdjuntarComprobanteMovimientoResultado> adjuntarComprobante({
    required String movimientoInventarioId,
    required String sourceFilePath,
    required String originalFileName,
    required String mimeType,
  }) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'inventario.modificar',
      () => ref.read(adjuntarComprobanteMovimientoUseCaseProvider).ejecutar(
            movimientoInventarioId: movimientoInventarioId,
            sourceFilePath: sourceFilePath,
            originalFileName: originalFileName,
            mimeType: mimeType,
          ),
      AdjuntarComprobanteMovimientoErrorInesperado.new,
    );
  }
}
