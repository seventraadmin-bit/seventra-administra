import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:riseg_one/features/reportes/reportes_providers.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

import '../dashboard_providers.dart';
import 'dashboard_state.dart';

part 'dashboard_controller.g.dart';

/// Controlador del Dashboard (Etapa 13) — pantalla inicial dinámica
/// por permisos. Cada bloque verifica su propio `hasCode('xxx.ver')`
/// **antes** de invocar el use case correspondiente; si falta el
/// permiso, ese use case nunca se ejecuta (mismo patrón que cada
/// controller de Reportes, nunca "se consulta y se oculta después").
///
/// Reutiliza directamente los 6 use cases de Reportes 12A–12D
/// (`obtenerResumenGeneralUseCaseProvider` y análogos) — nunca
/// redefine una consulta que Reportes ya resuelve.
@riverpod
class DashboardController extends _$DashboardController {
  @override
  DashboardState build() {
    Future.microtask(_cargar);
    return const DashboardState();
  }

  Future<void> _cargar() async {
    state = state.copyWith(cargando: true, errorCarga: null);
    try {
      final permissionService = ref.read(permissionServiceProvider);
      bool tiene(String codigo) => permissionService.hasCode(codigo);

      final incluirFinanzas = tiene('finanzas.ver');
      final incluirCompras = tiene('compras.ver');
      final incluirNomina = tiene('nomina.ver');
      final incluirComercial = tiene('comercial.ver');
      final incluirPersonal = tiene('personal.ver');
      final incluirInventario = tiene('inventario.ver');
      final incluirVehiculos = tiene('vehiculos.ver');
      final incluirTelefonia = tiene('telefonia.ver');

      final hoy = DateTime.now();
      final inicioMes = DateTime(hoy.year, hoy.month, 1);

      final resumenGeneral = await ref.read(obtenerResumenGeneralUseCaseProvider).ejecutar(
            rangoInicio: inicioMes,
            rangoFin: hoy,
            incluirFinanzas: incluirFinanzas,
            incluirCompras: incluirCompras,
            incluirNomina: incluirNomina,
            // Personal activo se toma de resumenPersonal.totalActivos —
            // nunca se pide dos veces la misma cuenta.
            incluirPersonal: false,
            incluirComercial: incluirComercial,
          );

      final resumenPersonal = incluirPersonal
          ? await ref.read(obtenerResumenPersonalUseCaseProvider).ejecutar(rangoInicio: inicioMes, rangoFin: hoy)
          : null;

      final resumenNomina = incluirNomina
          ? await ref.read(obtenerResumenNominaUseCaseProvider).ejecutar(rangoInicio: inicioMes, rangoFin: hoy)
          : null;

      final resumenInventario = incluirInventario
          ? await ref.read(obtenerResumenInventarioUseCaseProvider).ejecutar(rangoInicio: inicioMes, rangoFin: hoy)
          : null;

      final resumenVehiculos = incluirVehiculos
          ? await ref.read(obtenerResumenVehiculosUseCaseProvider).ejecutar(rangoInicio: inicioMes, rangoFin: hoy)
          : null;

      final resumenTelefonia = incluirTelefonia
          ? await ref.read(obtenerResumenTelefoniaUseCaseProvider).ejecutar(rangoInicio: inicioMes, rangoFin: hoy)
          : null;

      final alertas = await ref.read(obtenerAlertasDashboardUseCaseProvider).ejecutar(
            incluirCxC: incluirFinanzas,
            incluirEmpleadosBajaConPendiente: incluirPersonal && incluirInventario,
            hoy: hoy,
          );

      final actividad = await ref.read(obtenerActividadRecienteUseCaseProvider).ejecutar(
            incluirCompras: incluirCompras,
            incluirPagos: incluirFinanzas,
            incluirInventario: incluirInventario,
            incluirTelefonia: incluirTelefonia,
            rangoInicio: inicioMes,
            rangoFin: hoy,
          );

      state = DashboardState(
        cargando: false,
        resumenGeneral: resumenGeneral,
        resumenPersonal: resumenPersonal,
        resumenNomina: resumenNomina,
        resumenInventario: resumenInventario,
        resumenVehiculos: resumenVehiculos,
        resumenTelefonia: resumenTelefonia,
        alertas: alertas,
        actividad: actividad,
      );
    } catch (e) {
      state = state.copyWith(cargando: false, errorCarga: e.toString());
    }
  }
}
