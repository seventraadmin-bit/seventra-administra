import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:riseg_one/features/organizacion/data/tables/cliente_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_estatus_cliente_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cliente_expediente_data.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cliente_expediente_input.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/contacto_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_contacto_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_expediente_cliente_usecase.dart';

import '../../organizacion_providers.dart';
import 'cliente_expediente_state.dart';

part 'cliente_expediente_controller.g.dart';

/// Controlador de la pantalla de expediente de Cliente — un `family` por
/// `clienteId`. Mismo diseño que `PuestoExpedienteController`; el
/// cambio de estatus es una acción independiente del guardado del
/// formulario, y los Contactos se agregan/editan/archivan también de
/// forma independiente (cada uno refresca solo la lista de contactos
/// del estado, sin tocar `modo` ni los datos generales ya cargados).
@riverpod
class ClienteExpedienteController extends _$ClienteExpedienteController {
  @override
  ClienteExpedienteState build(String clienteId) {
    Future.microtask(_cargar);
    return const ClienteExpedienteState();
  }

  Future<void> _cargar() async {
    state = state.copyWith(cargando: true, errorCarga: null);
    final resultado = await ref.read(obtenerExpedienteClienteUseCaseProvider).ejecutar(clienteId);

    resultado.when(
      ok: (cliente) {
        state = state.copyWith(
          cargando: false,
          datos: cliente,
          modo: ClienteExpedienteModo.consulta,
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
      modo: ClienteExpedienteModo.edicion,
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
      modo: ClienteExpedienteModo.consulta,
      tieneCambiosSinGuardar: false,
      erroresGuardado: const [],
      errorGuardadoGeneral: false,
    );
  }

  Future<bool> guardar(ClienteExpedienteInput input) async {
    if (state.guardando || state.datos == null) return false;

    state = state.copyWith(guardando: true, erroresGuardado: const [], errorGuardadoGeneral: false);

    final resultado = await ref
        .read(guardarExpedienteClienteUseCaseProvider)
        .ejecutar(clienteId: clienteId, input: input);

    switch (resultado) {
      case GuardarExpedienteClienteExitoso(datos: final actualizado):
        state = state.copyWith(
          guardando: false,
          datos: ClienteExpedienteData(
            cliente: actualizado.cliente,
            direccionReferencia: actualizado.direccionReferencia,
            contactos: state.datos!.contactos,
          ),
          modo: ClienteExpedienteModo.consulta,
          tieneCambiosSinGuardar: false,
          erroresGuardado: const [],
          errorGuardadoGeneral: false,
        );
        return true;
      case GuardarExpedienteClienteErroresValidacion(errores: final errores):
        state = state.copyWith(guardando: false, erroresGuardado: errores, errorGuardadoGeneral: false);
        return false;
      case GuardarExpedienteClienteErrorInesperado():
        state = state.copyWith(guardando: false, erroresGuardado: const [], errorGuardadoGeneral: true);
        return false;
    }
  }

  Future<bool> cambiarEstatus(EstatusCliente nuevo) async {
    final datosActuales = state.datos;
    if (state.cambiandoEstatus || datosActuales == null) return false;

    state = state.copyWith(cambiandoEstatus: true);
    final resultado = await ref.read(cambiarEstatusClienteUseCaseProvider).ejecutar(clienteId: clienteId, nuevo: nuevo);

    switch (resultado) {
      case CambiarEstatusClienteExitoso(cliente: final cliente):
        state = state.copyWith(
          cambiandoEstatus: false,
          datos: ClienteExpedienteData(
            cliente: cliente,
            direccionReferencia: datosActuales.direccionReferencia,
            contactos: datosActuales.contactos,
          ),
        );
        return true;
      case CambiarEstatusClienteErrorInesperado():
        state = state.copyWith(cambiandoEstatus: false);
        return false;
    }
  }

  Future<GuardarContactoResultado> agregarContacto(ContactoBorrador borrador) async {
    final resultado = await ref.read(agregarContactoUseCaseProvider).ejecutar(clienteId: clienteId, borrador: borrador);
    if (resultado is GuardarContactoExitoso) {
      await _recargarContactos();
    }
    return resultado;
  }

  Future<GuardarContactoResultado> actualizarContacto(String contactoId, ContactoBorrador borrador) async {
    final resultado = await ref.read(actualizarContactoUseCaseProvider).ejecutar(id: contactoId, borrador: borrador);
    if (resultado is GuardarContactoExitoso) {
      await _recargarContactos();
    }
    return resultado;
  }

  Future<void> archivarContacto(String contactoId) async {
    await ref.read(archivarContactoUseCaseProvider).ejecutar(contactoId);
    await _recargarContactos();
  }

  /// Refresca únicamente la lista de contactos del estado ya cargado —
  /// nunca toca `modo` ni reinicia errores de guardado del formulario
  /// principal, que son independientes de esta acción.
  Future<void> _recargarContactos() async {
    final datosActuales = state.datos;
    if (datosActuales == null) return;

    final resultado = await ref.read(obtenerExpedienteClienteUseCaseProvider).ejecutar(clienteId);
    resultado.when(
      ok: (expediente) {
        state = state.copyWith(
          datos: ClienteExpedienteData(
            cliente: datosActuales.cliente,
            direccionReferencia: datosActuales.direccionReferencia,
            contactos: expediente.contactos,
          ),
        );
      },
      failure: (_) {},
    );
  }
}
