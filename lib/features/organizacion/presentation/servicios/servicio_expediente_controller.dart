import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/validation/direccion_validator.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/asignar_entidad_fiscal_a_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/asignar_responsable_cliente_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/asignar_sucursal_administrativa_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_estatus_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_linea_comercial_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_direccion_operativa_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_servicio_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/linea_comercial_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_expediente_data.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';

import '../../organizacion_providers.dart';
import 'servicio_expediente_state.dart';

part 'servicio_expediente_controller.g.dart';

/// Controlador de la pantalla de expediente de Servicio — un `family`
/// por `servicioId`. Mismo diseño que `ClienteExpedienteController`; el
/// cambio de estatus y las 5 acciones de vinculación (Entidad fiscal,
/// Responsable del Cliente, Sucursal administrativa, Responsable
/// interno, Dirección operativa) son todas independientes del guardado
/// del formulario principal — cada una refresca el expediente completo
/// (`_recargarDatos`) sin tocar `modo` ni los errores del formulario de
/// Datos generales/Referencias.
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
          datos: _conServicioActualizado(servicio),
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
    if (state.cambiandoEstatus || state.datos == null) return null;

    state = state.copyWith(cambiandoEstatus: true);
    final resultado = await ref.read(cambiarEstatusServicioUseCaseProvider).ejecutar(
          servicioId: servicioId,
          nuevo: nuevo,
          fechaTerminoEfectiva: fechaTerminoEfectiva,
        );

    if (resultado is CambiarEstatusServicioExitoso) {
      state = state.copyWith(cambiandoEstatus: false, datos: _conServicioActualizado(resultado.servicio));
    } else {
      state = state.copyWith(cambiandoEstatus: false);
    }
    return resultado;
  }

  Future<AsignarEntidadFiscalAServicioResultado?> asignarEntidadFiscal(String? entidadFiscalId) async {
    if (state.operandoRelacion) return null;
    state = state.copyWith(operandoRelacion: true);

    final resultado = await ref
        .read(asignarEntidadFiscalAServicioUseCaseProvider)
        .ejecutar(servicioId: servicioId, entidadFiscalId: entidadFiscalId);
    if (resultado is AsignarEntidadFiscalAServicioExitoso) {
      await _recargarDatos();
    }
    state = state.copyWith(operandoRelacion: false);
    return resultado;
  }

  Future<AsignarResponsableClienteResultado?> asignarResponsableCliente(String? contactoId) async {
    if (state.operandoRelacion) return null;
    state = state.copyWith(operandoRelacion: true);

    final resultado = await ref
        .read(asignarResponsableClienteUseCaseProvider)
        .ejecutar(servicioId: servicioId, contactoId: contactoId);
    if (resultado is AsignarResponsableClienteExitoso) {
      await _recargarDatos();
    }
    state = state.copyWith(operandoRelacion: false);
    return resultado;
  }

  Future<AsignarSucursalAdministrativaResultado?> asignarSucursalAdministrativa(String? sucursalId) async {
    if (state.operandoRelacion) return null;
    state = state.copyWith(operandoRelacion: true);

    final resultado = await ref
        .read(asignarSucursalAdministrativaUseCaseProvider)
        .ejecutar(servicioId: servicioId, sucursalId: sucursalId);
    if (resultado is AsignarSucursalAdministrativaExitoso) {
      await _recargarDatos();
    }
    state = state.copyWith(operandoRelacion: false);
    return resultado;
  }

  Future<GuardarDireccionOperativaServicioResultado?> guardarDireccionOperativa(DireccionBorrador? domicilio) async {
    if (state.operandoRelacion) return null;
    state = state.copyWith(operandoRelacion: true);

    final resultado = await ref
        .read(guardarDireccionOperativaServicioUseCaseProvider)
        .ejecutar(servicioId: servicioId, domicilio: domicilio);
    if (resultado is GuardarDireccionOperativaServicioExitoso) {
      await _recargarDatos();
    }
    state = state.copyWith(operandoRelacion: false);
    return resultado;
  }

  Future<CrearLineaComercialResultado?> agregarLineaComercial(LineaComercialBorrador borrador) async {
    if (state.operandoComercial) return null;
    state = state.copyWith(operandoComercial: true);

    final resultado =
        await ref.read(crearLineaComercialUseCaseProvider).ejecutar(servicioId: servicioId, borrador: borrador);
    if (resultado is CrearLineaComercialExitoso) {
      await _recargarDatos();
    }
    state = state.copyWith(operandoComercial: false);
    return resultado;
  }

  Future<bool> guardarResponsableInterno(String? texto) async {
    if (state.operandoRelacion) return false;
    state = state.copyWith(operandoRelacion: true);

    try {
      await ref.read(guardarResponsableInternoUseCaseProvider).ejecutar(servicioId: servicioId, texto: texto);
      await _recargarDatos();
      state = state.copyWith(operandoRelacion: false);
      return true;
    } catch (_) {
      state = state.copyWith(operandoRelacion: false);
      return false;
    }
  }

  /// Reemplaza únicamente el `ServicioData` dentro del expediente ya
  /// cargado, preservando el resto de la composición (`cliente`,
  /// Dirección operativa, Entidad fiscal, Responsable del Cliente,
  /// Sucursal administrativa) — usado por `guardar`/`cambiarEstatus`,
  /// que ya traen el `ServicioData` actualizado de vuelta y no
  /// necesitan una recarga completa.
  ServicioExpedienteData _conServicioActualizado(ServicioData servicio) {
    final datosActuales = state.datos!;
    return ServicioExpedienteData(
      servicio: servicio,
      cliente: datosActuales.cliente,
      tieneDireccionOperativaActiva: datosActuales.tieneDireccionOperativaActiva,
      direccionOperativa: datosActuales.direccionOperativa,
      entidadFiscal: datosActuales.entidadFiscal,
      responsableCliente: datosActuales.responsableCliente,
      sucursalAdministrativa: datosActuales.sucursalAdministrativa,
      lineasComerciales: datosActuales.lineasComerciales,
    );
  }

  /// Recarga el expediente completo — necesario tras cualquier acción de
  /// vinculación, ya que cada una puede cambiar más de un campo derivado
  /// a la vez (p. ej. asignar una Dirección operativa también cambia
  /// `tieneDireccionOperativaActiva`). Nunca toca `modo` ni los errores
  /// del formulario principal — son independientes de estas acciones.
  Future<void> _recargarDatos() async {
    final resultado = await ref.read(obtenerExpedienteServicioUseCaseProvider).ejecutar(servicioId);
    resultado.when(
      ok: (datos) => state = state.copyWith(datos: datos),
      failure: (_) {},
    );
  }
}
