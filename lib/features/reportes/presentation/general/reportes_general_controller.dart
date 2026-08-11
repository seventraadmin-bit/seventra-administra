import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

import '../../reportes_permisos.dart';
import '../../reportes_providers.dart';
import 'reportes_general_state.dart';

part 'reportes_general_controller.g.dart';

/// Controlador de la pestaña General de Reportes (Etapa 12A).
///
/// La guardia de permiso real vive **aquí** (punto de carga de datos),
/// no solo en `ReportesShellScreen` ocultando la pestaña — cada sección
/// del resumen solo se calcula si la sesión tiene el permiso del
/// dominio correspondiente (ver `ObtenerResumenGeneralUseCase`, que
/// deja cada campo en `null` cuando no se incluyó).
@riverpod
class ReportesGeneralController extends _$ReportesGeneralController {
  @override
  ReportesGeneralState build() {
    final hoy = DateTime.now();
    final inicioMes = DateTime(hoy.year, hoy.month, 1);
    Future.microtask(_cargar);
    return ReportesGeneralState(rangoInicio: inicioMes, rangoFin: hoy);
  }

  Future<void> _cargar() async {
    state = state.copyWith(cargando: true, errorCarga: null);
    try {
      final permissionService = ref.read(permissionServiceProvider);
      final resumen = await ref.read(obtenerResumenGeneralUseCaseProvider).ejecutar(
            rangoInicio: state.rangoInicio,
            rangoFin: state.rangoFin,
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

  Future<void> cambiarRango({DateTime? rangoInicio, DateTime? rangoFin}) async {
    state = state.copyWith(rangoInicio: rangoInicio, rangoFin: rangoFin);
    await _cargar();
  }
}
