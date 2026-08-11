import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';
import 'package:riseg_one/core/permissions/authorization_service.dart';
import 'package:riseg_one/core/validation/direccion_validator.dart';
import 'package:riseg_one/features/organizacion/data/tables/cliente_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_ciclo_vida_entidad_fiscal_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_estatus_cliente_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cliente_expediente_data.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cliente_expediente_input.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/contacto_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/entidad_fiscal_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_contacto_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_domicilio_fiscal_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_entidad_fiscal_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_expediente_cliente_usecase.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

import '../../organizacion_providers.dart';
import 'cliente_expediente_state.dart';

part 'cliente_expediente_controller.g.dart';

/// Controlador de la pantalla de expediente de Cliente — un `family` por
/// `clienteId`. Mismo diseño que `PuestoExpedienteController`; el
/// cambio de estatus es una acción independiente del guardado del
/// formulario, y los Contactos y Entidades fiscales se agregan/editan/
/// archivan también de forma independiente (cada uno refresca solo su
/// propia lista del estado, sin tocar `modo` ni los datos generales ya
/// cargados). No guarda ningún `TextEditingController` ni objeto de UI
/// — esos viven en el `State` de la pantalla, nunca aquí.
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

    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'comercial.modificar',
      () => ref.read(guardarExpedienteClienteUseCaseProvider).ejecutar(clienteId: clienteId, input: input),
      GuardarExpedienteClienteErrorInesperado.new,
    );

    switch (resultado) {
      case GuardarExpedienteClienteExitoso(datos: final actualizado):
        state = state.copyWith(
          guardando: false,
          datos: ClienteExpedienteData(
            cliente: actualizado.cliente,
            direccionReferencia: actualizado.direccionReferencia,
            contactos: state.datos!.contactos,
            entidadesFiscales: state.datos!.entidadesFiscales,
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
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'comercial.modificar',
      () => ref.read(cambiarEstatusClienteUseCaseProvider).ejecutar(clienteId: clienteId, nuevo: nuevo),
      CambiarEstatusClienteErrorInesperado.new,
    );

    switch (resultado) {
      case CambiarEstatusClienteExitoso(cliente: final cliente):
        state = state.copyWith(
          cambiandoEstatus: false,
          datos: ClienteExpedienteData(
            cliente: cliente,
            direccionReferencia: datosActuales.direccionReferencia,
            contactos: datosActuales.contactos,
            entidadesFiscales: datosActuales.entidadesFiscales,
          ),
        );
        return true;
      case CambiarEstatusClienteErrorInesperado():
        state = state.copyWith(cambiandoEstatus: false);
        return false;
    }
  }

  Future<GuardarContactoResultado> agregarContacto(ContactoBorrador borrador) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'comercial.modificar',
      () => ref.read(agregarContactoUseCaseProvider).ejecutar(clienteId: clienteId, borrador: borrador),
      GuardarContactoErrorInesperado.new,
    );
    if (resultado is GuardarContactoExitoso) {
      await _recargarExpediente();
    }
    return resultado;
  }

  Future<GuardarContactoResultado> actualizarContacto(String contactoId, ContactoBorrador borrador) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'comercial.modificar',
      () => ref.read(actualizarContactoUseCaseProvider).ejecutar(id: contactoId, borrador: borrador),
      GuardarContactoErrorInesperado.new,
    );
    if (resultado is GuardarContactoExitoso) {
      await _recargarExpediente();
    }
    return resultado;
  }

  /// Devuelve `true` si el archivado tuvo éxito — `ArchivarContactoUseCase`
  /// no tiene un tipo sellado propio (archivar un Contacto nunca falla por
  /// reglas de negocio), así que la frontera de autorización usa `null`
  /// como su propio "no autorizado" en vez de introducir un tipo nuevo.
  Future<bool> archivarContacto(String contactoId) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'comercial.archivar',
      () => ref.read(archivarContactoUseCaseProvider).ejecutar(contactoId).then<ContactoData?>((v) => v),
      (mensaje) => null,
    );
    final exito = resultado != null;
    if (exito) await _recargarExpediente();
    return exito;
  }

  Future<GuardarEntidadFiscalResultado?> agregarEntidadFiscal(EntidadFiscalBorrador borrador) async {
    if (state.operandoEntidadFiscal) return null;
    state = state.copyWith(operandoEntidadFiscal: true);

    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'comercial.modificar',
      () => ref.read(crearEntidadFiscalUseCaseProvider).ejecutar(clienteId: clienteId, borrador: borrador),
      GuardarEntidadFiscalErrorInesperado.new,
    );
    if (resultado is GuardarEntidadFiscalExitoso) {
      await _recargarExpediente();
    }
    state = state.copyWith(operandoEntidadFiscal: false);
    return resultado;
  }

  Future<GuardarEntidadFiscalResultado?> actualizarEntidadFiscal(
    String entidadFiscalId,
    EntidadFiscalBorrador borrador,
  ) async {
    if (state.operandoEntidadFiscal) return null;
    state = state.copyWith(operandoEntidadFiscal: true);

    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'comercial.modificar',
      () => ref.read(actualizarEntidadFiscalUseCaseProvider).ejecutar(id: entidadFiscalId, borrador: borrador),
      GuardarEntidadFiscalErrorInesperado.new,
    );
    if (resultado is GuardarEntidadFiscalExitoso) {
      await _recargarExpediente();
    }
    state = state.copyWith(operandoEntidadFiscal: false);
    return resultado;
  }

  Future<bool> cambiarCicloVidaEntidadFiscal(String entidadFiscalId, CicloVidaRegistro nuevo) async {
    if (state.operandoEntidadFiscal) return false;
    state = state.copyWith(operandoEntidadFiscal: true);

    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'comercial.archivar',
      () => ref.read(cambiarCicloVidaEntidadFiscalUseCaseProvider).ejecutar(entidadFiscalId: entidadFiscalId, nuevo: nuevo),
      CambiarCicloVidaEntidadFiscalErrorInesperado.new,
    );
    final exito = resultado is CambiarCicloVidaEntidadFiscalExitoso;
    if (exito) {
      await _recargarExpediente();
    }
    state = state.copyWith(operandoEntidadFiscal: false);
    return exito;
  }

  Future<GuardarDomicilioFiscalResultado?> guardarDomicilioFiscal(
    String entidadFiscalId,
    DireccionBorrador? domicilio,
  ) async {
    if (state.operandoEntidadFiscal) return null;
    state = state.copyWith(operandoEntidadFiscal: true);

    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'comercial.modificar',
      () => ref.read(guardarDomicilioFiscalUseCaseProvider).ejecutar(entidadFiscalId: entidadFiscalId, domicilio: domicilio),
      GuardarDomicilioFiscalErrorInesperado.new,
    );
    if (resultado is GuardarDomicilioFiscalExitoso) {
      await _recargarExpediente();
    }
    state = state.copyWith(operandoEntidadFiscal: false);
    return resultado;
  }

  /// Refresca el expediente completo (contactos **y** Entidades
  /// fiscales) preservando `cliente`/`direccionReferencia` ya cargados
  /// y sin tocar `modo` ni los errores de guardado del formulario
  /// principal — esas cosas son independientes de estas acciones.
  Future<void> _recargarExpediente() async {
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
            entidadesFiscales: expediente.entidadesFiscales,
          ),
        );
      },
      failure: (_) {},
    );
  }
}
