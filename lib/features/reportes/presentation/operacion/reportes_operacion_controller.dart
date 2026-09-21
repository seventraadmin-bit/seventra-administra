import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

import '../../reportes_permisos.dart';
import '../reportes_rango_controller.dart';
import '../../reportes_providers.dart';
import 'reportes_operacion_state.dart';

part 'reportes_operacion_controller.g.dart';

/// Controlador de la pestaña Operación de Reportes (Etapa 12C).
///
/// Cada bloque (Compras/Inventario/Vehículos/Telefonía) verifica su
/// propio permiso **antes** de llamar a su caso de uso — mismo patrón
/// que `ReportesPersonalNominaController` (Etapa 12B), extendido de 2 a
/// 4 subsecciones independientes.
@riverpod
class ReportesOperacionController extends _$ReportesOperacionController {
  @override
  ReportesOperacionState build() {
    final seleccion = ref.watch(reportesRangoControllerProvider);
    Future.microtask(() => _cargar(seleccion));
    return ReportesOperacionState(seleccion: seleccion);
  }

  bool get tieneCompras => tienePermisoSeccionReportes(ref.read(permissionServiceProvider), 'compras.ver');

  bool get tieneInventario => tienePermisoSeccionReportes(ref.read(permissionServiceProvider), 'inventario.ver');

  bool get tieneVehiculos => tienePermisoSeccionReportes(ref.read(permissionServiceProvider), 'vehiculos.ver');

  bool get tieneTelefonia => tienePermisoSeccionReportes(ref.read(permissionServiceProvider), 'telefonia.ver');

  Future<void> _cargar(SeleccionRangoReportes seleccion) async {
    state = state.copyWith(cargando: true, errorCarga: null);
    try {
      final resumenCompras = tieneCompras
          ? await ref.read(obtenerResumenComprasUseCaseProvider).ejecutar(
                rangoInicio: seleccion.rango.inicio,
                rangoFin: seleccion.rango.fin,
              )
          : null;

      final resumenInventario = tieneInventario
          ? await ref.read(obtenerResumenInventarioUseCaseProvider).ejecutar(
                rangoInicio: seleccion.rango.inicio,
                rangoFin: seleccion.rango.fin,
              )
          : null;

      final resumenVehiculos = tieneVehiculos
          ? await ref.read(obtenerResumenVehiculosUseCaseProvider).ejecutar(
                rangoInicio: seleccion.rango.inicio,
                rangoFin: seleccion.rango.fin,
              )
          : null;

      final resumenTelefonia = tieneTelefonia
          ? await ref.read(obtenerResumenTelefoniaUseCaseProvider).ejecutar(
                rangoInicio: seleccion.rango.inicio,
                rangoFin: seleccion.rango.fin,
              )
          : null;

      state = ReportesOperacionState(
        seleccion: seleccion,
        cargando: false,
        resumenCompras: resumenCompras,
        resumenInventario: resumenInventario,
        resumenVehiculos: resumenVehiculos,
        resumenTelefonia: resumenTelefonia,
      );
    } catch (e) {
      state = state.copyWith(cargando: false, errorCarga: e.toString());
    }
  }

  Future<void> recargar() => _cargar(state.seleccion);
}
