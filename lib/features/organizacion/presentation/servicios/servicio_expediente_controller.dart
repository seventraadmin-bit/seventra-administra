import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:riseg_one/features/organizacion/data/tables/servicio_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_estatus_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_servicio_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_expediente_data.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';

import '../../organizacion_providers.dart';
import 'servicio_expediente_state.dart';

part 'servicio_expediente_controller.g.dart';

/// Controlador de la pantalla de expediente de Servicio — un `family`
/// por `servicioId`. Mismo diseño que `ClienteExpedienteController`; el
/// cambio de estatus es una acción independiente del guardado del
/// formulario principal.
@riverpod
class ServicioExpedienteController extends _$ServicioExpedienteController {
  @override
  ServicioExpedienteState build(String servicioId) {
    Future.microtask(_cargar);
    return const ServicioExpedienteState();
  }

  Future<void> _cargar() async {
    state = state.copyWith(cargando: true, errorCarga: null);
    final resultado = await ref.read(obtenerExpedienteServicioUseCaseProvider).ejecutar(servicioId);

    resultado.when(
      ok: (datos) {
        state = state.copyWith(
          cargando: false,
          datos: datos,
          modo: ServicioExpedienteModo.consulta,
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
      modo: ServicioExpedienteModo.edicion,
      tieneCambiosSinGuardar: false,
      erroresGuardado: const [],
      errorGuardadoGeneral: false,
    );
  }

  void marcarCambiosSinGuardar() {
    if (!state.tieneCambiosSinGuardar) {
      state = state.copyWith(tieneCambiosSinGuardar: true);
    }
  }

  void cancelarEdicion() {
    state = state.copyWith(
      modo: ServicioExpedienteModo.consulta,
      tieneCambiosSinGuardar: false,
      erroresGuardado: const [],
      errorGuardadoGeneral: false,
    );
  }

  Future<bool> guardar(ServicioBorrador borrador) async {
    if (state.guardando || state.datos == null) return false;

    state = state.copyWith(guardando: true, erroresGuardado: const [], errorGuardadoGeneral: false);

    final resultado = await ref.read(actualizarServicioUseCaseProvider).ejecutar(id: servicioId, borrador: borrador);

    switch (resultado) {
      case GuardarServicioExitoso(servicio: final servicio):
        state = state.copyWith(
          guardando: false,
          datos: ServicioExpedienteData(
            servicio: servicio,
            tieneDireccionOperativaActiva: state.datos!.tieneDireccionOperativaActiva,
          ),
          modo: ServicioExpedienteModo.consulta,
          tieneCambiosSinGuardar: false,
          erroresGuardado: const [],
          errorGuardadoGeneral: false,
        );
        return true;
      case GuardarServicioErroresValidacion(errores: final errores):
        state = state.copyWith(guardando: false, erroresGuardado: errores, errorGuardadoGeneral: false);
        return false;
      case GuardarServicioErrorInesperado():
        state = state.copyWith(guardando: false, erroresGuardado: const [], errorGuardadoGeneral: true);
        return false;
    }
  }

  Future<CambiarEstatusServicioResultado?> cambiarEstatus(
    EstatusServicio nuevo, {
    DateTime? fechaTerminoEfectiva,
  }) async {
    final datosActuales = state.datos;
    if (state.cambiandoEstatus || datosActuales == null) return null;

    state = state.copyWith(cambiandoEstatus: true);
    final resultado = await ref.read(cambiarEstatusServicioUseCaseProvider).ejecutar(
          servicioId: servicioId,
          nuevo: nuevo,
          fechaTerminoEfectiva: fechaTerminoEfectiva,
        );

    if (resultado is CambiarEstatusServicioExitoso) {
      state = state.copyWith(
        cambiandoEstatus: false,
        datos: ServicioExpedienteData(
          servicio: resultado.servicio,
          tieneDireccionOperativaActiva: datosActuales.tieneDireccionOperativaActiva,
        ),
      );
    } else {
      state = state.copyWith(cambiandoEstatus: false);
    }
    return resultado;
  }
}
