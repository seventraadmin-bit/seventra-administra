import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/usecases/empresa_expediente_input.dart';
import '../../domain/usecases/guardar_expediente_empresa_usecase.dart';
import '../../organizacion_providers.dart';
import 'empresa_expediente_state.dart';

part 'empresa_expediente_controller.g.dart';

/// Controlador de la pantalla de expediente de Empresa.
///
/// Guarda datos y estado (carga, modo, guardando, errores, "hay cambios
/// sin guardar") — nunca objetos de UI. Los `TextEditingController` del
/// formulario de edición viven en el widget de pantalla, con su propio
/// ciclo de vida; este controlador solo necesita saber *que* hubo un
/// cambio, no el contenido de cada campo.
@riverpod
class EmpresaExpedienteController extends _$EmpresaExpedienteController {
  @override
  EmpresaExpedienteState build() {
    // `_cargar` escribe en `state` de inmediato (antes de su primer
    // `await`) — llamarla de forma síncrona aquí chocaría con Riverpod,
    // que todavía no terminó de inicializar el estado en este punto.
    // `Future.microtask` la difiere justo después de que `build()` retorne.
    Future.microtask(_cargar);
    return const EmpresaExpedienteState();
  }

  Future<void> _cargar() async {
    state = state.copyWith(cargando: true, errorCarga: null);
    final resultado = await ref.read(obtenerExpedienteEmpresaUseCaseProvider).ejecutar();

    resultado.when(
      ok: (datos) {
        state = state.copyWith(
          cargando: false,
          datos: datos,
          modo: EmpresaExpedienteModo.consulta,
          errorCarga: null,
        );
      },
      failure: (f) {
        state = state.copyWith(cargando: false, errorCarga: f.message);
      },
    );
  }

  Future<void> reintentarCarga() => _cargar();

  void entrarModoEdicion() {
    state = state.copyWith(
      modo: EmpresaExpedienteModo.edicion,
      tieneCambiosSinGuardar: false,
      erroresGuardado: const [],
      errorGuardadoGeneral: false,
    );
  }

  /// El widget de edición llama esto la primera vez que el usuario
  /// modifica cualquier campo — el controlador solo registra el hecho.
  void marcarCambiosSinGuardar() {
    if (!state.tieneCambiosSinGuardar) {
      state = state.copyWith(tieneCambiosSinGuardar: true);
    }
  }

  void cancelarEdicion() {
    state = state.copyWith(
      modo: EmpresaExpedienteModo.consulta,
      tieneCambiosSinGuardar: false,
      erroresGuardado: const [],
      errorGuardadoGeneral: false,
    );
  }

  /// Devuelve `true` si el guardado tuvo éxito. Ignora una segunda
  /// invocación mientras ya hay un guardado en curso (protege contra
  /// doble clic).
  Future<bool> guardar(EmpresaExpedienteInput input) async {
    if (state.guardando || state.datos == null) return false;

    state = state.copyWith(guardando: true, erroresGuardado: const [], errorGuardadoGeneral: false);

    final resultado = await ref
        .read(guardarExpedienteEmpresaUseCaseProvider)
        .ejecutar(empresaId: state.datos!.empresa.id, input: input);

    switch (resultado) {
      case GuardarExpedienteExitoso(datos: final datos):
        state = state.copyWith(
          guardando: false,
          datos: datos,
          modo: EmpresaExpedienteModo.consulta,
          tieneCambiosSinGuardar: false,
          erroresGuardado: const [],
          errorGuardadoGeneral: false,
        );
        return true;
      case GuardarExpedienteErroresValidacion(errores: final errores):
        state = state.copyWith(guardando: false, erroresGuardado: errores, errorGuardadoGeneral: false);
        return false;
      case GuardarExpedienteErrorInesperado():
        state = state.copyWith(guardando: false, erroresGuardado: const [], errorGuardadoGeneral: true);
        return false;
    }
  }
}
