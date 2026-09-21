import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

import '../../reportes_permisos.dart';
import '../../reportes_providers.dart';
import '../reportes_rango_controller.dart';
import 'reportes_general_state.dart';

part 'reportes_general_controller.g.dart';

/// Controlador de la pestaña General de Reportes.
///
/// La guardia de permiso real vive **aquí** (punto de carga de datos),
/// no solo en `ReportesShellScreen` ocultando la pestaña — cada sección
/// del resumen solo se calcula si la sesión tiene el permiso del
/// dominio correspondiente (ver `ObtenerResumenGeneralUseCase`, que
/// deja cada campo en `null` cuando no se incluyó).
///
/// El rango se **observa** del controlador compartido: cambiarlo desde
/// la barra de filtro reconstruye este provider una sola vez y dispara
/// exactamente una carga, nunca una cascada de consultas por cada campo
/// del filtro.
@riverpod
class ReportesGeneralController extends _$ReportesGeneralController {
  @override
  ReportesGeneralState build() {
    final seleccion = ref.watch(reportesRangoControllerProvider);
    Future.microtask(() => _cargar(seleccion));
    return ReportesGeneralState(seleccion: seleccion);
  }

  Future<void> _cargar(SeleccionRangoReportes seleccion) async {
    state = state.copyWith(cargando: true, errorCarga: null);
    try {
      final permissionService = ref.read(permissionServiceProvider);
      final resumen = await ref.read(obtenerResumenGeneralUseCaseProvider).ejecutar(
            rango: seleccion.rango,
            incluirFinanzas: tienePermisoSeccionReportes(permissionService, 'finanzas.ver'),
            incluirCompras: tienePermisoSeccionReportes(permissionService, 'compras.ver'),
            incluirNomina: tienePermisoSeccionReportes(permissionService, 'nomina.ver'),
            incluirPersonal: tienePermisoSeccionReportes(permissionService, 'personal.ver'),
            incluirComercial: tienePermisoSeccionReportes(permissionService, 'comercial.ver'),
          );
      state = state.copyWith(cargando: false, resumen: resumen, errorCarga: null);
    } catch (e) {
      state = state.copyWith(cargando: false, errorCarga: e.toString());
    }
  }

  Future<void> recargar() => _cargar(state.seleccion);
}
