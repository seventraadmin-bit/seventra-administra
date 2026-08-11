import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:riseg_one/core/database/tables/audit_columns.dart';
import 'package:riseg_one/core/permissions/authorization_service.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_ciclo_vida_puesto_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_puesto_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/puesto_validator.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

import '../../organizacion_providers.dart';
import 'puesto_expediente_state.dart';

part 'puesto_expediente_controller.g.dart';

/// Controlador de la pantalla de expediente de Puesto — un `family` por
/// `puestoId`. Mismo diseño que `SucursalExpedienteController`, sin las
/// secciones de sub-entidades; el ciclo de vida (archivar/reactivar) es
/// una acción independiente del guardado del formulario, igual que el
/// estado operativo de Sucursal.
@riverpod
class PuestoExpedienteController extends _$PuestoExpedienteController {
  @override
  PuestoExpedienteState build(String puestoId) {
    Future.microtask(_cargar);
    return const PuestoExpedienteState();
  }

  Future<void> _cargar() async {
    state = state.copyWith(cargando: true, errorCarga: null);
    final resultado = await ref.read(obtenerExpedientePuestoUseCaseProvider).ejecutar(puestoId);
    final areas = await ref.read(listarAreasActivasUseCaseProvider).ejecutar();

    resultado.when(
      ok: (puesto) {
        state = state.copyWith(
          cargando: false,
          datos: puesto,
          areas: areas,
          modo: PuestoExpedienteModo.consulta,
          errorCarga: null,
        );
      },
      failure: (f) {
        state = state.copyWith(cargando: false, areas: areas, errorCarga: f.message);
      },
    );
  }

  Future<void> reintentarCarga() => _cargar();

  void entrarModoEdicion() {
    state = state.copyWith(
      modo: PuestoExpedienteModo.edicion,
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
      modo: PuestoExpedienteModo.consulta,
      tieneCambiosSinGuardar: false,
      erroresGuardado: const [],
      errorGuardadoGeneral: false,
    );
  }

  Future<bool> guardar(PuestoBorrador borrador) async {
    if (state.guardando || state.datos == null) return false;

    state = state.copyWith(guardando: true, erroresGuardado: const [], errorGuardadoGeneral: false);

    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'organizacion.modificar',
      () => ref.read(actualizarPuestoUseCaseProvider).ejecutar(id: puestoId, borrador: borrador),
      GuardarPuestoErrorInesperado.new,
    );

    switch (resultado) {
      case GuardarPuestoExitoso(puesto: final puesto):
        state = state.copyWith(
          guardando: false,
          datos: puesto,
          modo: PuestoExpedienteModo.consulta,
          tieneCambiosSinGuardar: false,
          erroresGuardado: const [],
          errorGuardadoGeneral: false,
        );
        return true;
      case GuardarPuestoErroresValidacion(errores: final errores):
        state = state.copyWith(guardando: false, erroresGuardado: errores, errorGuardadoGeneral: false);
        return false;
      case GuardarPuestoErrorInesperado():
        state = state.copyWith(guardando: false, erroresGuardado: const [], errorGuardadoGeneral: true);
        return false;
    }
  }

  /// Transición de ciclo de vida independiente del guardado del
  /// formulario. Devuelve `true` si tuvo éxito; si el bloqueo por Área
  /// inactiva aplicó (solo posible al reactivar), devuelve `false` sin
  /// modificar el estado local del Puesto.
  Future<bool> cambiarCicloVida(CicloVidaRegistro nuevo) async {
    final datosActuales = state.datos;
    if (state.cambiandoCicloVida || datosActuales == null) return false;

    state = state.copyWith(cambiandoCicloVida: true);
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'organizacion.archivar',
      () => ref.read(cambiarCicloVidaPuestoUseCaseProvider).ejecutar(puestoId: puestoId, nuevo: nuevo),
      CambiarCicloVidaPuestoErrorInesperado.new,
    );

    switch (resultado) {
      case CambiarCicloVidaPuestoExitoso(puesto: final puesto):
        state = state.copyWith(cambiandoCicloVida: false, datos: puesto);
        return true;
      case CambiarCicloVidaPuestoAreaInactiva():
        state = state.copyWith(cambiandoCicloVida: false);
        return false;
      case CambiarCicloVidaPuestoErrorInesperado():
        state = state.copyWith(cambiandoCicloVida: false);
        return false;
    }
  }
}
