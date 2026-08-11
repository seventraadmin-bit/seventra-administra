import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:riseg_one/features/finanzas/domain/usecases/cuenta_por_cobrar_antiguedad.dart';
import 'package:riseg_one/features/finanzas/finanzas_providers.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

import '../../reportes_permisos.dart';
import '../../reportes_providers.dart';
import 'reportes_finanzas_state.dart';

part 'reportes_finanzas_controller.g.dart';

/// Controlador de la pestaña Finanzas de Reportes (Etapa 12A).
///
/// Guardia de permiso real (no solo la pestaña oculta en
/// `ReportesShellScreen`): si la sesión no tiene `finanzas.ver`, esta
/// función retorna sin ejecutar ninguna consulta — `state` se queda en
/// ceros/listas vacías y `sinAutorizacion == true` para que la pantalla
/// muestre un estado explícito, nunca datos parciales.
@riverpod
class ReportesFinanzasController extends _$ReportesFinanzasController {
  @override
  ReportesFinanzasState build() {
    final hoy = DateTime.now();
    final inicioMes = DateTime(hoy.year, hoy.month, 1);
    Future.microtask(_cargar);
    return ReportesFinanzasState(rangoInicio: inicioMes, rangoFin: hoy);
  }

  bool get sinAutorizacion => !tienePermisoSeccionReportes(ref.read(permissionServiceProvider), 'finanzas.ver');

  Future<void> _cargar() async {
    state = state.copyWith(cargando: true, errorCarga: null);

    if (sinAutorizacion) {
      state = state.copyWith(cargando: false);
      return;
    }

    try {
      final rangoInicio = state.rangoInicio;
      final rangoFin = state.rangoFin;

      final resumenFinanciero =
          await ref.read(obtenerResumenFinancieroUseCaseProvider).ejecutar(rangoInicio: rangoInicio, rangoFin: rangoFin);

      final pagos = await ref.read(pagoRepositoryProvider).listar(
            estatus: 'registrado',
            rangoInicio: rangoInicio,
            rangoFin: rangoFin,
          );
      final totalPagosRecibidos = pagos.fold<int>(0, (s, p) => s + p.montoTotal);

      final cuentasPorCobrar = await ref.read(cuentaPorCobrarRepositoryProvider).listar();
      final cuentasNoPagadas = cuentasPorCobrar.where((c) => c.estatus != 'pagada');
      final hoy = DateTime.now();
      final cuentasPorRango = <RangoAntiguedadCuentaPorCobrar, int>{};
      final montoPorRango = <RangoAntiguedadCuentaPorCobrar, int>{};
      for (final cuenta in cuentasNoPagadas) {
        final rango = calcularRangoAntiguedad(cuenta, hoy);
        cuentasPorRango[rango] = (cuentasPorRango[rango] ?? 0) + 1;
        montoPorRango[rango] = (montoPorRango[rango] ?? 0) + cuenta.saldoPendiente;
      }

      final categorias = await ref.read(categoriaFinancieraRepositoryProvider).listar();
      final nombrePorCategoria = {for (final c in categorias) c.id: c.nombre};
      String nombreCategoria(String? id) =>
          id == null ? '' : (nombrePorCategoria[id] ?? id);

      final ingresosPorCategoria = await ref
          .read(ingresoRepositoryProvider)
          .totalPorCategoria(rangoInicio: rangoInicio, rangoFin: rangoFin);
      final egresosPorCategoria = await ref
          .read(egresoRepositoryProvider)
          .totalPorCategoria(rangoInicio: rangoInicio, rangoFin: rangoFin);

      final egresosPorOrigen =
          await ref.read(clasificarEgresosPorOrigenUseCaseProvider).ejecutar(rangoInicio: rangoInicio, rangoFin: rangoFin);

      state = state.copyWith(
        cargando: false,
        totalIngresos: resumenFinanciero.totalIngresos,
        totalEgresos: resumenFinanciero.totalEgresos,
        resultadoOperativo: resumenFinanciero.resultadoOperativo,
        totalPagosRecibidos: totalPagosRecibidos,
        cuentasPorCobrarPorRango: cuentasPorRango,
        montoPorCobrarPorRango: montoPorRango,
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

  Future<void> cambiarRango({DateTime? rangoInicio, DateTime? rangoFin}) async {
    state = state.copyWith(rangoInicio: rangoInicio, rangoFin: rangoFin);
    await _cargar();
  }
}
