import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

import '../../reportes_permisos.dart';
import '../../reportes_providers.dart';
import 'reportes_personal_nomina_state.dart';

part 'reportes_personal_nomina_controller.g.dart';

/// Controlador de la pestaña Personal · Nómina de Reportes (Etapa 12B).
///
/// Cada subsección verifica su propio permiso **antes** de llamar a su
/// caso de uso — un usuario con `personal.ver` sin `nomina.ver` nunca
/// dispara ninguna consulta de Nómina, y viceversa. Mismo patrón que
/// `ReportesFinanzasController` (Etapa 12A).
@riverpod
class ReportesPersonalNominaController extends _$ReportesPersonalNominaController {
  @override
  ReportesPersonalNominaState build() {
    final hoy = DateTime.now();
    final inicioMes = DateTime(hoy.year, hoy.month, 1);
    Future.microtask(_cargar);
    return ReportesPersonalNominaState(rangoInicio: inicioMes, rangoFin: hoy);
  }

  bool get tienePersonal => tienePermisoSeccionReportes(ref.read(permissionServiceProvider), 'personal.ver');

  bool get tieneNomina => tienePermisoSeccionReportes(ref.read(permissionServiceProvider), 'nomina.ver');

  Future<void> _cargar() async {
    state = state.copyWith(cargando: true, errorCarga: null);
    try {
      final resumenPersonal = tienePersonal
          ? await ref.read(obtenerResumenPersonalUseCaseProvider).ejecutar(
                rangoInicio: state.rangoInicio,
                rangoFin: state.rangoFin,
              )
          : null;

      final resumenNomina = tieneNomina
          ? await ref.read(obtenerResumenNominaUseCaseProvider).ejecutar(
                rangoInicio: state.rangoInicio,
                rangoFin: state.rangoFin,
              )
          : null;

      state = ReportesPersonalNominaState(
        cargando: false,
        rangoInicio: state.rangoInicio,
        rangoFin: state.rangoFin,
        resumenPersonal: resumenPersonal,
        resumenNomina: resumenNomina,
      );
    } catch (e) {
      state = state.copyWith(cargando: false, errorCarga: e.toString());
    }
  }

  Future<void> cambiarRango({DateTime? rangoInicio, DateTime? rangoFin}) async {
    state = state.copyWith(rangoInicio: rangoInicio, rangoFin: rangoFin);
    await _cargar();
  }
}
