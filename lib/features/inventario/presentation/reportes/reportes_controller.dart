import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:riseg_one/core/database/app_database.dart';

import '../../../organizacion/organizacion_providers.dart';
import '../../../personal/personal_providers.dart';
import '../../domain/usecases/buscar_inventario_usecase.dart';
import '../../inventario_providers.dart';
import 'reportes_state.dart';

part 'reportes_controller.g.dart';

/// Controlador de Reportes (Etapa 7D) — cada sección es una consulta
/// derivada de los repositorios ya existentes, recalculada al cargar;
/// nunca se guarda un total ni un resumen aparte ("cero tablas de
/// resumen o totales persistidos", instrucción explícita de Marlon).
///
/// El costo promedio se omite (`null`) para Artículos con
/// `manejaVariante`: un solo número no representa de forma consistente
/// costos que legítimamente pueden diferir por talla — mostrarlo ahí
/// sería inventar precisión que la fuente no tiene.
@riverpod
class ReportesController extends _$ReportesController {
  @override
  ReportesState build() {
    Future.microtask(_cargar);
    return const ReportesState();
  }

  Future<void> _cargar() async {
    state = state.copyWith(cargando: true, errorCarga: null);
    try {
      final articuloRepo = ref.read(articuloRepositoryProvider);
      final categoriaRepo = ref.read(categoriaArticuloRepositoryProvider);
      final inventarioRepo = ref.read(inventarioRepositoryProvider);
      final asignacionRepo = ref.read(asignacionRepositoryProvider);
      final empleadoRepo = ref.read(empleadoRepositoryProvider);
      final servicioRepo = ref.read(servicioRepositoryProvider);

      final articulos = await articuloRepo.listar();
      final categorias = await categoriaRepo.listar();
      final categoriasPorId = {for (final c in categorias) c.id: c.nombre};
      final articulosPorId = {for (final a in articulos) a.id: a};

      // Existencias actuales (+ costo promedio cuando aplica).
      final existencias = <ExistenciaResumen>[];
      for (final articulo in articulos) {
        final existencia = articulo.manejaSerie
            ? await inventarioRepo.calcularExistenciaUnidades(articulo.id)
            : await inventarioRepo.calcularExistencia(articuloId: articulo.id);
        final costoPromedio =
            articulo.manejaVariante ? null : await inventarioRepo.calcularCostoPromedio(articuloId: articulo.id);
        existencias.add(
          ExistenciaResumen(
            articulo: articulo,
            categoriaNombre: categoriasPorId[articulo.categoriaId] ?? '',
            existencia: existencia,
            costoPromedio: costoPromedio,
          ),
        );
      }

      // Mapas de resolución — una sola consulta masiva por dominio,
      // nunca N+1 por fila de reporte.
      final variantesPorArticulo = <String, Map<String, String>>{};
      final unidadesPorId = <String, ArticuloUnidadData>{};
      for (final articulo in articulos) {
        if (articulo.manejaVariante) {
          final variantes = await articuloRepo.listarVariantes(articulo.id, soloActivas: false);
          variantesPorArticulo[articulo.id] = {for (final v in variantes) v.id: v.valor};
        }
      }
      for (final unidad in await inventarioRepo.listarTodasUnidades()) {
        unidadesPorId[unidad.id] = unidad;
      }
      final empleados = await empleadoRepo.listar();
      final empleadosPorId = {
        for (final e in empleados)
          e.id: [e.nombres, e.apellidoPaterno, e.apellidoMaterno].whereType<String>().where((p) => p.trim().isNotEmpty).join(' '),
      };
      final servicios = await servicioRepo.listar();
      final serviciosPorId = {for (final s in servicios) s.servicio.id: s.servicio.nombre};

      String detalleArticulo(AsignacionData a) {
        final articulo = articulosPorId[a.articuloId];
        final nombre = articulo?.nombre ?? a.articuloId;
        if (a.unidadId != null) {
          final unidad = unidadesPorId[a.unidadId];
          return unidad == null ? nombre : '$nombre · ${unidad.codigo}';
        }
        if (a.varianteId != null) {
          final talla = variantesPorArticulo[a.articuloId]?[a.varianteId];
          return talla == null ? nombre : '${a.cantidad} × $nombre ($talla)';
        }
        return '${a.cantidad} × $nombre';
      }

      String destino(AsignacionData a) {
        if (a.empleadoId != null) return empleadosPorId[a.empleadoId] ?? a.empleadoId!;
        if (a.servicioId != null) return serviciosPorId[a.servicioId] ?? a.servicioId!;
        return '—';
      }

      final asignacionesVigentes = (await asignacionRepo.listarTodasActivas())
          .map((a) => AsignacionResumenReporte(asignacion: a, articuloDetalle: detalleArticulo(a), destino: destino(a)))
          .toList();

      final danadosPerdidos = (await asignacionRepo.listarDanadasPerdidas())
          .map((a) => AsignacionResumenReporte(asignacion: a, articuloDetalle: detalleArticulo(a), destino: destino(a)))
          .toList();

      final descuentosData = await asignacionRepo.listarTodosDescuentosPendientes();
      final asignacionesPorDescuentoId = <String, AsignacionData?>{};
      for (final d in descuentosData) {
        asignacionesPorDescuentoId[d.asignacionId] ??= await asignacionRepo.obtenerPorId(d.asignacionId);
      }
      final descuentosPendientes = descuentosData
          .map(
            (d) => DescuentoResumenReporte(
              descuento: d,
              empleadoNombre: empleadosPorId[d.empleadoId] ?? d.empleadoId,
              articuloDetalle: switch (asignacionesPorDescuentoId[d.asignacionId]) {
                final a? => detalleArticulo(a),
                null => '—',
              },
            ),
          )
          .toList();

      // Historial de movimientos: ya viene ordenado por fecha
      // descendente — se toma solo lo más reciente ("UI compacta y
      // operativa", nunca una tabla sin límite).
      const limiteMovimientosRecientes = 100;
      final movimientosRecientes = (await inventarioRepo.listarMovimientos())
          .take(limiteMovimientosRecientes)
          .map(
            (m) => MovimientoResumenReporte(
              movimiento: m,
              articuloNombre: articulosPorId[m.articuloId]?.nombre ?? m.articuloId,
            ),
          )
          .toList();

      state = state.copyWith(
        cargando: false,
        existencias: existencias,
        asignacionesVigentes: asignacionesVigentes,
        danadosPerdidos: danadosPerdidos,
        descuentosPendientes: descuentosPendientes,
        movimientosRecientes: movimientosRecientes,
      );
    } catch (e) {
      state = state.copyWith(cargando: false, errorCarga: e.toString());
    }
  }

  Future<void> reintentarCarga() => _cargar();

  Future<void> buscar(String consulta) async {
    state = state.copyWith(consultaBusqueda: consulta);
    final resultado = await ref.read(buscarInventarioUseCaseProvider).ejecutar(consulta);
    // La consulta pudo cambiar mientras esperábamos el resultado —
    // nunca pisar una búsqueda más nueva con una respuesta vieja.
    if (state.consultaBusqueda != consulta) return;
    state = state.copyWith(resultadoBusqueda: resultado);
  }

  void limpiarBusqueda() {
    state = state.copyWith(consultaBusqueda: '', resultadoBusqueda: ResultadoBusquedaInventario.vacia);
  }
}
