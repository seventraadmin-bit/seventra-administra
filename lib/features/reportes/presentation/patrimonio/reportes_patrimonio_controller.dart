import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:riseg_one/features/reportes/domain/analitica/obtener_analisis_patrimonio_usecase.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

import '../../reportes_permisos.dart';
import '../../reportes_providers.dart';
import '../reportes_rango_controller.dart';
import 'reportes_patrimonio_state.dart';

part 'reportes_patrimonio_controller.g.dart';

/// Controlador de la pestaña Patrimonio y bajas.
///
/// La guardia real vive aquí, no sólo en la pestaña oculta: el reporte
/// cruza personas con bienes, así que exige **ambos** permisos. Con uno
/// solo no se consulta nada y la pantalla lo dice — nunca media verdad.
@riverpod
class ReportesPatrimonioController extends _$ReportesPatrimonioController {
  @override
  ReportesPatrimonioState build() {
    final seleccion = ref.watch(reportesRangoControllerProvider);
    Future.microtask(() => _cargar(seleccion, state.filtro));
    return ReportesPatrimonioState(seleccion: seleccion);
  }

  bool get sinAutorizacion {
    final permisos = ref.read(permissionServiceProvider);
    return !tienePermisoSeccionReportes(permisos, 'personal.ver') ||
        !tienePermisoSeccionReportes(permisos, 'inventario.ver');
  }

  Future<void> cambiarFiltro(FiltroPatrimonio filtro) => _cargar(state.seleccion, filtro);

  Future<void> recargar() => _cargar(state.seleccion, state.filtro);

  Future<void> _cargar(SeleccionRangoReportes seleccion, FiltroPatrimonio filtro) async {
    state = state.copyWith(cargando: true, filtro: filtro, errorCarga: null);

    if (sinAutorizacion) {
      state = state.copyWith(cargando: false);
      return;
    }

    try {
      final analisis = await ref
          .read(obtenerAnalisisPatrimonioUseCaseProvider)
          .ejecutar(rango: seleccion.rango, filtro: filtro);
      state = state.copyWith(cargando: false, analisis: analisis, errorCarga: null);
    } catch (e) {
      state = state.copyWith(cargando: false, errorCarga: e.toString());
    }
  }
}
