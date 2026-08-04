import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:riseg_one/features/organizacion/data/tables/sucursal_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_expediente_sucursal_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/sucursal_expediente_data.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/sucursal_expediente_input.dart';

import '../../organizacion_providers.dart';
import 'sucursal_expediente_state.dart';

part 'sucursal_expediente_controller.g.dart';

/// Controlador de la pantalla de expediente de Sucursal — un `family`
/// por `sucursalId`. Mismo diseño que `EmpresaExpedienteController`
/// (carga, consulta/edición, guardado, errores, estado sucio); guarda
/// datos y estado, nunca `TextEditingController`s (esos viven en la
/// pantalla).
@riverpod
class SucursalExpedienteController extends _$SucursalExpedienteController {
  @override
  SucursalExpedienteState build(String sucursalId) {
    Future.microtask(_cargar);
    return const SucursalExpedienteState();
  }

  Future<void> _cargar() async {
    state = state.copyWith(cargando: true, errorCarga: null);
    final resultado = await ref.read(obtenerExpedienteSucursalUseCaseProvider).ejecutar(sucursalId);
    final tipos = await ref.read(listarTiposSucursalUseCaseProvider).ejecutar();

    resultado.when(
      ok: (datos) {
        state = state.copyWith(
          cargando: false,
          datos: datos,
          tipos: tipos,
          modo: SucursalExpedienteModo.consulta,
          errorCarga: null,
        );
      },
      failure: (f) {
        state = state.copyWith(cargando: false, tipos: tipos, errorCarga: f.message);
      },
    );
  }

  Future<void> reintentarCarga() => _cargar();

  void entrarModoEdicion() {
    state = state.copyWith(
      modo: SucursalExpedienteModo.edicion,
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
      modo: SucursalExpedienteModo.consulta,
      tieneCambiosSinGuardar: false,
      erroresGuardado: const [],
      errorGuardadoGeneral: false,
    );
  }

  Future<bool> guardar(SucursalExpedienteInput input) async {
    if (state.guardando || state.datos == null) return false;

    state = state.copyWith(guardando: true, erroresGuardado: const [], errorGuardadoGeneral: false);

    final resultado = await ref
        .read(guardarExpedienteSucursalUseCaseProvider)
        .ejecutar(sucursalId: sucursalId, input: input);

    switch (resultado) {
      case GuardarExpedienteSucursalExitoso(datos: final datos):
        state = state.copyWith(
          guardando: false,
          datos: datos,
          modo: SucursalExpedienteModo.consulta,
          tieneCambiosSinGuardar: false,
          erroresGuardado: const [],
          errorGuardadoGeneral: false,
        );
        return true;
      case GuardarExpedienteSucursalErroresValidacion(errores: final errores):
        state = state.copyWith(guardando: false, erroresGuardado: errores, errorGuardadoGeneral: false);
        return false;
      case GuardarExpedienteSucursalErrorInesperado():
        state = state.copyWith(guardando: false, erroresGuardado: const [], errorGuardadoGeneral: true);
        return false;
    }
  }

  /// Transición de negocio independiente del guardado del formulario — la
  /// pantalla ya pidió confirmación antes de llamar esto.
  Future<bool> cambiarEstadoOperativo(EstadoOperativoSucursal nuevo) async {
    final datosActuales = state.datos;
    if (state.cambiandoEstadoOperativo || datosActuales == null) return false;

    state = state.copyWith(cambiandoEstadoOperativo: true);
    final resultado = await ref
        .read(cambiarEstadoOperativoSucursalUseCaseProvider)
        .ejecutar(sucursalId: sucursalId, nuevo: nuevo);

    return resultado.when(
      ok: (sucursalActualizada) {
        state = state.copyWith(
          cambiandoEstadoOperativo: false,
          datos: SucursalExpedienteData(
            sucursal: sucursalActualizada,
            direccionPrincipal: datosActuales.direccionPrincipal,
            horario: datosActuales.horario,
          ),
        );
        return true;
      },
      failure: (_) {
        state = state.copyWith(cambiandoEstadoOperativo: false);
        return false;
      },
    );
  }
}
