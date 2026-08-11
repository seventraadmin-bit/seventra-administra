import 'package:riseg_one/core/database/app_database.dart';

import '../usecases/eliminar_articulo_fisicamente_usecase.dart';

/// El catálogo central de Inventario (Etapa 7A) — `Articulo` y sus
/// `ArticuloVariante` (talla). La creación/consulta de `ArticuloUnidad`
/// (unidad serializada) vive en `InventarioRepository`, porque dar de
/// alta una unidad siempre implica también su movimiento `entrada`
/// (ver el doc comment de esa interfaz) — nunca se crea una unidad
/// suelta sin su propio historial.
abstract interface class ArticuloRepository {
  Future<ArticuloData?> obtenerPorId(String id);

  /// Solo `cicloVidaRegistro == activo` salvo que se pida lo contrario.
  Future<List<ArticuloData>> listar({String? categoriaId, bool soloActivos = true});

  Future<ArticuloData> crear({
    required String folio,
    required String categoriaId,
    required String nombre,
    String? descripcion,
    String? unidadMedida,
    required bool manejaVariante,
    required bool manejaSerie,
    int? costoReferencia,
  });

  /// Nunca toca `manejaVariante`/`manejaSerie` — esas banderas quedan
  /// fijas desde la creación (ver `CorregirArticuloUseCase`).
  Future<ArticuloData> corregir({
    required String articuloId,
    String? categoriaId,
    String? nombre,
    String? descripcion,
    String? unidadMedida,
    int? costoReferencia,
    bool limpiarDescripcion = false,
    bool limpiarCostoReferencia = false,
  });

  /// Única excepción controlada a "`manejaVariante`/`manejaSerie`
  /// quedan fijas desde la creación" (Etapa 9D, ajuste posterior) —
  /// exclusiva de `RegularizarArticuloSerializadoUseCase`, Maestro-only,
  /// para corregir un Artículo que se dio de alta sin marcar
  /// `manejaSerie` por error y ya tiene existencia real por cantidad.
  /// Nunca la llama ningún otro caso de uso.
  Future<ArticuloData> marcarManejaSerie(String articuloId);

  Future<ArticuloData> archivar(String articuloId);

  Future<List<ArticuloVarianteData>> listarVariantes(String articuloId, {bool soloActivas = true});

  Future<ArticuloVarianteData> crearVariante({required String articuloId, required String valor});

  Future<ArticuloVarianteData> archivarVariante(String varianteId);

  /// Eliminación física extraordinaria (Etapa 11D) — ver el doc comment
  /// de la implementación para las condiciones exactas.
  Future<EliminarArticuloFisicamenteResultado> eliminarFisicamente({
    required String articuloId,
    required String motivo,
    String? actorUsuarioId,
  });
}
