import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

import '../notificaciones_providers.dart';
import 'notificaciones_state.dart';

part 'notificaciones_controller.g.dart';

/// Controlador del Centro de notificaciones (Etapa 14B) — mismo
/// principio de guardia real que Reportes/Dashboard/Búsqueda: cada
/// grupo se consulta solo si la sesión tiene su permiso, antes de
/// invocar `ObtenerNotificacionesUseCase`. Se carga al iniciar la
/// sesión y se vuelve a cargar cada vez que se abre la campana
/// (`recargar()`) — sin temporizadores ni tareas en segundo plano.
@riverpod
class NotificacionesController extends _$NotificacionesController {
  @override
  NotificacionesState build() {
    Future.microtask(_cargar);
    return const NotificacionesState();
  }

  Future<void> _cargar() async {
    state = state.copyWith(cargando: true, errorCarga: null);
    try {
      final permissionService = ref.read(permissionServiceProvider);
      bool tiene(String codigo) => permissionService.hasCode(codigo);

      final resultados = await ref.read(obtenerNotificacionesUseCaseProvider).ejecutar(
            incluirVehiculos: tiene('vehiculos.ver'),
            incluirComercial: tiene('comercial.ver'),
            incluirFinanzas: tiene('finanzas.ver'),
          );

      state = NotificacionesState(cargando: false, resultados: resultados);
    } catch (e) {
      state = state.copyWith(cargando: false, errorCarga: e.toString());
    }
  }

  Future<void> recargar() => _cargar();
}
