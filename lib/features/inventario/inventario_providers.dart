import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../organizacion/organizacion_providers.dart';
import 'data/repositories/articulo_repository_impl.dart';
import 'data/repositories/categoria_articulo_repository_impl.dart';
import 'data/repositories/inventario_repository_impl.dart';
import 'domain/repositories/articulo_repository.dart';
import 'domain/repositories/categoria_articulo_repository.dart';
import 'domain/repositories/inventario_repository.dart';
import 'domain/usecases/adjuntar_comprobante_movimiento_usecase.dart';
import 'domain/usecases/archivar_articulo_usecase.dart';
import 'domain/usecases/archivar_categoria_articulo_usecase.dart';
import 'domain/usecases/archivar_variante_articulo_usecase.dart';
import 'domain/usecases/corregir_articulo_usecase.dart';
import 'domain/usecases/crear_articulo_usecase.dart';
import 'domain/usecases/crear_categoria_articulo_usecase.dart';
import 'domain/usecases/crear_variante_articulo_usecase.dart';
import 'domain/usecases/registrar_ajuste_usecase.dart';
import 'domain/usecases/registrar_baja_unidad_usecase.dart';
import 'domain/usecases/registrar_baja_usecase.dart';
import 'domain/usecases/registrar_entrada_unidad_usecase.dart';
import 'domain/usecases/registrar_entrada_usecase.dart';

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
