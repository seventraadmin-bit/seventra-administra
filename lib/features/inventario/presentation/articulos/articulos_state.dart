import 'package:riseg_one/core/database/app_database.dart';

import '../../domain/usecases/existencia_articulo.dart';

/// Una fila del listado de Artículos — el catálogo más su existencia
/// derivada (nunca guardada, ver el doc comment de
/// `MovimientoInventario`) y el nombre de su categoría ya resuelto.
class ArticuloResumen {
  const ArticuloResumen({required this.articulo, required this.categoriaNombre, required this.existencia});

  final ArticuloData articulo;
  final String categoriaNombre;
  final ExistenciaArticulo existencia;
}

/// Filtro por tipo de manejo (Etapa 18) — en memoria, sobre
/// `articulo.manejaSerie` ya cargado.
enum FiltroTipoArticulo { todos, cantidad, serie }

/// Filtro por estado de existencia (Etapa 18) — en memoria, sobre
/// `existencia` ya calculada en `_cargar()`; nunca una consulta nueva
/// por opción de filtro.
enum FiltroEstadoExistencia { todos, conDisponibilidad, sinDisponibilidad, conAsignaciones, danadoPerdido }

/// Estado del listado de Artículos (Etapa 7A) — mismo shape que
/// cualquier otro listado del proyecto.
class ArticulosState {
  const ArticulosState({
    this.cargando = true,
    this.articulos = const [],
    this.categorias = const [],
    this.texto,
    this.categoriaId,
    this.tipo = FiltroTipoArticulo.todos,
    this.estadoExistencia = FiltroEstadoExistencia.todos,
    this.errorCarga,
  });

  final bool cargando;
  final List<ArticuloResumen> articulos;
  final List<CategoriaArticuloData> categorias;

  final String? texto;
  final String? categoriaId;
  final FiltroTipoArticulo tipo;
  final FiltroEstadoExistencia estadoExistencia;
  final String? errorCarga;

  bool get hayFiltrosActivos =>
      (texto != null && texto!.trim().isNotEmpty) ||
      categoriaId != null ||
      tipo != FiltroTipoArticulo.todos ||
      estadoExistencia != FiltroEstadoExistencia.todos;

  List<ArticuloResumen> get visibles {
    final textoNormalizado = texto?.trim().toLowerCase();
    return articulos.where((r) {
      if (textoNormalizado != null && textoNormalizado.isNotEmpty) {
        final coincideTexto = r.articulo.nombre.toLowerCase().contains(textoNormalizado) ||
            r.articulo.folio.toLowerCase().contains(textoNormalizado);
        if (!coincideTexto) return false;
      }
      if (categoriaId != null && r.articulo.categoriaId != categoriaId) return false;
      switch (tipo) {
        case FiltroTipoArticulo.todos:
          break;
        case FiltroTipoArticulo.cantidad:
          if (r.articulo.manejaSerie) return false;
        case FiltroTipoArticulo.serie:
          if (!r.articulo.manejaSerie) return false;
      }
      switch (estadoExistencia) {
        case FiltroEstadoExistencia.todos:
          break;
        case FiltroEstadoExistencia.conDisponibilidad:
          if (r.existencia.disponible <= 0) return false;
        case FiltroEstadoExistencia.sinDisponibilidad:
          if (r.existencia.disponible > 0) return false;
        case FiltroEstadoExistencia.conAsignaciones:
          if (r.existencia.asignado <= 0) return false;
        case FiltroEstadoExistencia.danadoPerdido:
          if (r.existencia.danado + r.existencia.perdido <= 0) return false;
      }
      return true;
    }).toList();
  }

  /// Resumen KPI del conjunto YA FILTRADO (`visibles`) — Etapa 18: nunca
  /// mezcla catálogo (número de artículos) con existencia (suma de
  /// unidades); cada indicador es explícito sobre cuál de los dos mide.
  int get resumenArticulosRegistrados => visibles.length;
  int get resumenUnidadesTotales => visibles.fold(0, (s, r) => s + r.existencia.total);
  int get resumenUnidadesDisponibles => visibles.fold(0, (s, r) => s + r.existencia.disponible);

  /// Unidades que siguen siendo de RISEG pero no se pueden entregar:
  /// lavandería, reparación o pendientes de desecho. Se muestra para que
  /// `resumenUnidadesTotales` siga siendo la suma visible de sus partes.
  int get resumenUnidadesEnProceso => visibles.fold(0, (s, r) => s + r.existencia.enProceso);
  int get resumenUnidadesAsignadas => visibles.fold(0, (s, r) => s + r.existencia.asignado);
  int get resumenUnidadesDanadasPerdidas => visibles.fold(0, (s, r) => s + r.existencia.danado + r.existencia.perdido);

  ArticulosState copyWith({
    bool? cargando,
    List<ArticuloResumen>? articulos,
    List<CategoriaArticuloData>? categorias,
    String? texto,
    String? categoriaId,
    FiltroTipoArticulo? tipo,
    FiltroEstadoExistencia? estadoExistencia,
    bool limpiarTexto = false,
    bool limpiarCategoriaId = false,
    String? errorCarga,
  }) {
    return ArticulosState(
      cargando: cargando ?? this.cargando,
      articulos: articulos ?? this.articulos,
      categorias: categorias ?? this.categorias,
      texto: limpiarTexto ? null : (texto ?? this.texto),
      categoriaId: limpiarCategoriaId ? null : (categoriaId ?? this.categoriaId),
      tipo: tipo ?? this.tipo,
      estadoExistencia: estadoExistencia ?? this.estadoExistencia,
      errorCarga: errorCarga,
    );
  }
}
