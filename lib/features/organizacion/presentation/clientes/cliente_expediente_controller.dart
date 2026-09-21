import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:riseg_one/core/database/tables/audit_columns.dart';
import 'package:riseg_one/core/permissions/authorization_service.dart';
import 'package:riseg_one/core/validation/direccion_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/archivar_contacto_usecase.dart';
import 'package:riseg_one/features/organizacion/data/tables/cliente_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_ciclo_vida_cliente_portal_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_ciclo_vida_entidad_fiscal_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_estatus_cliente_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cliente_expediente_data.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cliente_expediente_input.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cliente_portal_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/contacto_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/entidad_fiscal_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_cliente_portal_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_contacto_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_domicilio_fiscal_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_entidad_fiscal_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_expediente_cliente_usecase.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

import '../../organizacion_providers.dart';
import 'cliente_expediente_state.dart';
import 'clientes_list_controller.dart';

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

  /// [motivo] es obligatorio y viaja a la bitácora junto con el usuario
  /// de la sesión.
  Future<bool> guardar(ClienteExpedienteInput input, {required String motivo}) async {
    if (state.guardando || state.datos == null) return false;

    state = state.copyWith(guardando: true, erroresGuardado: const [], errorGuardadoGeneral: false);

    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'clientes.corregir',
      () => ref.read(guardarExpedienteClienteUseCaseProvider).ejecutar(
            clienteId: clienteId,
            input: input,
            motivo: motivo,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
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
            portales: state.datos!.portales,
          ),
          modo: ClienteExpedienteModo.consulta,
          tieneCambiosSinGuardar: false,
          erroresGuardado: const [],
          errorGuardadoGeneral: false,
        );
        // El listado de Clientes (`ClientesListController`) no observa
        // este `family` — sin esta invalidación explícita, el listado
        // queda con los datos previos a la edición hasta que su propio
        // `autoDispose` se dispare por otro motivo (Etapa 15, hallazgo
        // real: un Cliente editado como Activo seguía viéndose como
        // Prospecto en el listado hasta cambiar de pestaña y volver).
        ref.invalidate(clientesListControllerProvider);
        return true;
      case GuardarExpedienteClienteErroresValidacion(errores: final errores):
        state = state.copyWith(guardando: false, erroresGuardado: errores, errorGuardadoGeneral: false);
        return false;
      case GuardarExpedienteClienteMotivoRequerido():
      case GuardarExpedienteClienteErrorInesperado():
        state = state.copyWith(guardando: false, erroresGuardado: const [], errorGuardadoGeneral: true);
        return false;
    }
  }

  /// [motivo] es obligatorio: un Cliente suspendido o terminado sin
  /// explicación deja una decisión comercial sin dueño. Junto con el
  /// usuario de la sesión, alimenta la bitácora del Cliente.
  Future<bool> cambiarEstatus(EstatusCliente nuevo, {required String motivo}) async {
    final datosActuales = state.datos;
    if (state.cambiandoEstatus || datosActuales == null) return false;

    state = state.copyWith(cambiandoEstatus: true);
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'clientes.corregir',
      () => ref.read(cambiarEstatusClienteUseCaseProvider).ejecutar(
            clienteId: clienteId,
            nuevo: nuevo,
            motivo: motivo,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
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
            portales: datosActuales.portales,
          ),
        );
        // Mismo motivo que en `guardar` — el listado no se refresca
        // solo con un cambio de estatus hecho desde el expediente.
        ref.invalidate(clientesListControllerProvider);
        return true;
      case CambiarEstatusClienteMotivoRequerido():
      case CambiarEstatusClienteErrorInesperado():
        state = state.copyWith(cambiandoEstatus: false);
        return false;
    }
  }

  Future<GuardarContactoResultado> agregarContacto(ContactoBorrador borrador) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'clientes.corregir',
      () => ref.read(agregarContactoUseCaseProvider).ejecutar(
            clienteId: clienteId,
            borrador: borrador,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      GuardarContactoErrorInesperado.new,
    );
    if (resultado is GuardarContactoExitoso) {
      await _recargarExpediente();
    }
    return resultado;
  }

  /// [motivo] obligatorio. Teléfono y correo llegan enmascarados a la
  /// bitácora.
  Future<GuardarContactoResultado> actualizarContacto(
    String contactoId,
    ContactoBorrador borrador, {
    required String motivo,
  }) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'clientes.corregir',
      () => ref.read(actualizarContactoUseCaseProvider).ejecutar(
            id: contactoId,
            borrador: borrador,
            motivo: motivo,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      GuardarContactoErrorInesperado.new,
    );
    if (resultado is GuardarContactoExitoso) {
      await _recargarExpediente();
    }
    return resultado;
  }

  /// Devuelve `true` si el archivado tuvo éxito. La frontera de
  /// autorización usa `null` como su propio "no autorizado"; el caso de
  /// uso distingue aparte el motivo faltante.
  Future<bool> archivarContacto(String contactoId, {required String motivo}) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'clientes.archivar',
      () => ref.read(archivarContactoUseCaseProvider).ejecutar(
            contactoId,
            motivo: motivo,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ).then<ArchivarContactoResultado?>((v) => v),
      (mensaje) => null,
    );
    final exito = resultado is ArchivarContactoExitoso;
    if (exito) await _recargarExpediente();
    return exito;
  }

  Future<GuardarEntidadFiscalResultado?> agregarEntidadFiscal(EntidadFiscalBorrador borrador) async {
    if (state.operandoEntidadFiscal) return null;
    state = state.copyWith(operandoEntidadFiscal: true);

    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'clientes.corregir',
      () => ref.read(crearEntidadFiscalUseCaseProvider).ejecutar(
            clienteId: clienteId,
            borrador: borrador,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      GuardarEntidadFiscalErrorInesperado.new,
    );
    if (resultado is GuardarEntidadFiscalExitoso) {
      await _recargarExpediente();
    }
    state = state.copyWith(operandoEntidadFiscal: false);
    return resultado;
  }

  /// [motivo] obligatorio: corregir RFC o razón social es un cambio
  /// fiscal, y tiene que poder explicarse después.
  Future<GuardarEntidadFiscalResultado?> actualizarEntidadFiscal(
    String entidadFiscalId,
    EntidadFiscalBorrador borrador, {
    required String motivo,
  }) async {
    if (state.operandoEntidadFiscal) return null;
    state = state.copyWith(operandoEntidadFiscal: true);

    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'clientes.corregir',
      () => ref.read(actualizarEntidadFiscalUseCaseProvider).ejecutar(
            id: entidadFiscalId,
            borrador: borrador,
            motivo: motivo,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      GuardarEntidadFiscalErrorInesperado.new,
    );
    if (resultado is GuardarEntidadFiscalExitoso) {
      await _recargarExpediente();
    }
    state = state.copyWith(operandoEntidadFiscal: false);
    return resultado;
  }

  Future<bool> cambiarCicloVidaEntidadFiscal(
    String entidadFiscalId,
    CicloVidaRegistro nuevo, {
    required String motivo,
  }) async {
    if (state.operandoEntidadFiscal) return false;
    state = state.copyWith(operandoEntidadFiscal: true);

    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'clientes.archivar',
      () => ref.read(cambiarCicloVidaEntidadFiscalUseCaseProvider).ejecutar(
            entidadFiscalId: entidadFiscalId,
            nuevo: nuevo,
            motivo: motivo,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
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
      'clientes.corregir',
      () => ref.read(guardarDomicilioFiscalUseCaseProvider).ejecutar(entidadFiscalId: entidadFiscalId, domicilio: domicilio),
      GuardarDomicilioFiscalErrorInesperado.new,
    );
    if (resultado is GuardarDomicilioFiscalExitoso) {
      await _recargarExpediente();
    }
    state = state.copyWith(operandoEntidadFiscal: false);
    return resultado;
  }

  Future<GuardarClientePortalResultado?> agregarClientePortal(ClientePortalBorrador borrador) async {
    if (state.operandoClientePortal) return null;
    state = state.copyWith(operandoClientePortal: true);

    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'clientes.corregir',
      () => ref.read(crearClientePortalUseCaseProvider).ejecutar(
            clienteId: clienteId,
            borrador: borrador,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      GuardarClientePortalErrorInesperado.new,
    );
    if (resultado is GuardarClientePortalExitoso) {
      await _recargarExpediente();
    }
    state = state.copyWith(operandoClientePortal: false);
    return resultado;
  }

  Future<GuardarClientePortalResultado?> actualizarClientePortal(
    String clientePortalId,
    ClientePortalBorrador borrador, {
    required String motivo,
  }) async {
    if (state.operandoClientePortal) return null;
    state = state.copyWith(operandoClientePortal: true);

    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'clientes.corregir',
      () => ref.read(actualizarClientePortalUseCaseProvider).ejecutar(
            id: clientePortalId,
            borrador: borrador,
            motivo: motivo,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      GuardarClientePortalErrorInesperado.new,
    );
    if (resultado is GuardarClientePortalExitoso) {
      await _recargarExpediente();
    }
    state = state.copyWith(operandoClientePortal: false);
    return resultado;
  }

  Future<bool> cambiarCicloVidaClientePortal(
    String clientePortalId,
    CicloVidaRegistro nuevo, {
    required String motivo,
  }) async {
    if (state.operandoClientePortal) return false;
    state = state.copyWith(operandoClientePortal: true);

    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'clientes.archivar',
      () => ref.read(cambiarCicloVidaClientePortalUseCaseProvider).ejecutar(
            clientePortalId: clientePortalId,
            nuevo: nuevo,
            motivo: motivo,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      CambiarCicloVidaClientePortalErrorInesperado.new,
    );
    final exito = resultado is CambiarCicloVidaClientePortalExitoso;
    if (exito) {
      await _recargarExpediente();
    }
    state = state.copyWith(operandoClientePortal: false);
    return exito;
  }

  /// Refresca el expediente completo (contactos, Entidades fiscales **y**
  /// portales) preservando `cliente`/`direccionReferencia` ya cargados
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
            portales: expediente.portales,
          ),
        );
      },
      failure: (_) {},
    );
  }
}
