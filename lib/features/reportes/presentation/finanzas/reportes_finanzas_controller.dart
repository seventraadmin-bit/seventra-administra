import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:riseg_one/features/finanzas/finanzas_providers.dart';
import 'package:riseg_one/features/reportes/domain/analitica/obtener_analisis_cobranza_usecase.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

import '../../reportes_permisos.dart';
import '../../reportes_providers.dart';
import '../reportes_rango_controller.dart';
import 'reportes_finanzas_state.dart';

part 'reportes_finanzas_controller.g.dart';

/// Controlador de la pestaña Finanzas de Reportes.
///
/// Guardia de permiso real (no solo la pestaña oculta en
/// `ReportesShellScreen`): si la sesión no tiene `finanzas.ver`, esta
/// función retorna sin ejecutar ninguna consulta — `state` se queda en
/// ceros/listas vacías y `sinAutorizacion == true` para que la pantalla
/// muestre un estado explícito, nunca datos parciales.
///
/// Dos universos temporales distintos conviven aquí y la pantalla los
/// distingue siempre: el **periodo** (operativo, pagos, movimientos de
/// deuda) y la **fecha de hoy** (cartera, saldos de deuda). Cambiar el
/// rango recalcula el primero; los segundos no dependen de él.
@riverpod
class ReportesFinanzasController extends _$ReportesFinanzasController {
  @override
  ReportesFinanzasState build() {
    final seleccion = ref.watch(reportesRangoControllerProvider);
    Future.microtask(() => _cargar(seleccion));
    return ReportesFinanzasState(seleccion: seleccion);
  }

  bool get sinAutorizacion => !tienePermisoSeccionReportes(ref.read(permissionServiceProvider), 'finanzas.ver');

  void cambiarSeccion(SeccionFinanzas seccion) => state = state.copyWith(seccion: seccion);

  /// Cambiar un filtro de cartera sólo recarga la cartera: el periodo,
  /// los pagos y la deuda no dependen de él.
  Future<void> cambiarFiltroCobranza(FiltroCobranza filtro) async {
    state = state.copyWith(filtroCobranza: filtro);
    if (sinAutorizacion) return;
    try {
      final cobranza = await ref.read(obtenerAnalisisCobranzaUseCaseProvider).ejecutar(filtro: filtro);
      state = state.copyWith(cobranza: cobranza, errorCarga: null);
    } catch (e) {
      state = state.copyWith(errorCarga: e.toString());
    }
  }

  Future<void> _cargar(SeleccionRangoReportes seleccion) async {
    state = state.copyWith(cargando: true, errorCarga: null);

    if (sinAutorizacion) {
      state = state.copyWith(cargando: false);
      return;
    }

    try {
      final rango = seleccion.rango;
      final rangoInicio = rango.inicio;
      final rangoFin = rango.fin;

      // Fuente única: el mismo caso de uso que alimenta la pestaña
      // General. Ingresos, gasto operativo, serie y composición salen de
      // aquí — nunca de una segunda aritmética local.
      final analisis = await ref.read(obtenerAnalisisOperativoUseCaseProvider).ejecutar(rango: rango);
      final analisisAnterior = await ref
          .read(obtenerAnalisisOperativoUseCaseProvider)
          .ejecutar(rango: rango.anterior, granularidad: analisis.granularidad);

      // Cartera: foto de hoy, acotada sólo por sus propios filtros.
      final cobranza =
          await ref.read(obtenerAnalisisCobranzaUseCaseProvider).ejecutar(filtro: state.filtroCobranza);

      // Pagos y movimientos de deuda: del periodo.
      final pagos = await ref.read(obtenerAnalisisPagosUseCaseProvider).ejecutar(rango: rango);
      final deuda = await ref.read(obtenerAnalisisDeudaUseCaseProvider).ejecutar(rango: rango);

      final categorias = await ref.read(categoriaFinancieraRepositoryProvider).listar();
      final nombrePorCategoria = {for (final c in categorias) c.id: c.nombre};
      String nombreCategoria(String? id) => id == null ? '' : (nombrePorCategoria[id] ?? id);

      final ingresosPorCategoria =
          await ref.read(ingresoRepositoryProvider).totalPorCategoria(rangoInicio: rangoInicio, rangoFin: rangoFin);
      final egresosPorCategoria =
          await ref.read(egresoRepositoryProvider).totalPorCategoria(rangoInicio: rangoInicio, rangoFin: rangoFin);

      final egresosPorOrigen = await ref
          .read(clasificarEgresosPorOrigenUseCaseProvider)
          .ejecutar(rangoInicio: rangoInicio, rangoFin: rangoFin);

      state = state.copyWith(
        cargando: false,
        analisis: analisis,
        analisisAnterior: analisisAnterior,
        cobranza: cobranza,
        pagos: pagos,
        deuda: deuda,
        ingresosPorCategoria: [
          for (final entrada in ingresosPorCategoria.entries)
            TotalPorCategoria(
              categoriaId: entrada.key,
              nombreCategoria: entrada.key == null ? _sinCategoria : nombreCategoria(entrada.key),
              total: entrada.value,
            ),
        ],
        egresosPorCategoria: [
          for (final entrada in egresosPorCategoria.entries)
            TotalPorCategoria(
              categoriaId: entrada.key,
              nombreCategoria: entrada.key == null ? _sinCategoria : nombreCategoria(entrada.key),
              total: entrada.value,
            ),
        ],
        egresosPorOrigen: egresosPorOrigen,
        errorCarga: null,
      );
    } catch (e) {
      state = state.copyWith(cargando: false, errorCarga: e.toString());
    }
  }

  static const _sinCategoria = '—';

  Future<void> recargar() => _cargar(state.seleccion);
}
