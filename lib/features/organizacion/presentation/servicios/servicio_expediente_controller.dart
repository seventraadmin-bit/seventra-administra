import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/validation/direccion_validator.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/actualizar_observaciones_configuracion_cobro_vigencia_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/asignar_entidad_fiscal_a_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/asignar_responsable_cliente_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/actualizar_anotaciones_vigencia_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/asignar_sucursal_administrativa_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_estatus_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_vigencia_configuracion_cobro_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_vigencia_linea_comercial_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cancelar_vigencia_programada_configuracion_cobro_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cancelar_vigencia_programada_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cerrar_configuracion_cobro_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cerrar_linea_comercial_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_regla_evento_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_configuracion_cobro_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_linea_comercial_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_direccion_operativa_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_servicio_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_sueldo_referencia_servicio_usecase.dart';
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

  Future<CrearConfiguracionCobroResultado?> agregarConfiguracionCobro(
    ConfiguracionCobroBorrador borrador, {
    List<ReglaEventoBorrador> reglas = const [],
  }) async {
    if (state.operandoCobro) return null;
    state = state.copyWith(operandoCobro: true);

    final resultado = await ref
        .read(crearConfiguracionCobroUseCaseProvider)
        .ejecutar(servicioId: servicioId, borrador: borrador, reglas: reglas);
    if (resultado is CrearConfiguracionCobroExitoso) {
      await _recargarDatos();
    }
    state = state.copyWith(operandoCobro: false);
    return resultado;
  }

  Future<CambiarVigenciaConfiguracionCobroResultado?> cambiarVigenciaConfiguracionCobro(
    String configuracionCobroId,
    ConfiguracionCobroBorrador borrador, {
    List<ReglaEventoBorrador> reglas = const [],
  }) async {
    if (state.operandoCobro) return null;
    state = state.copyWith(operandoCobro: true);

    final resultado = await ref.read(cambiarVigenciaConfiguracionCobroUseCaseProvider).ejecutar(
          configuracionCobroId: configuracionCobroId,
          borrador: borrador,
          reglas: reglas,
        );
    if (resultado is CambiarVigenciaConfiguracionCobroExitoso) {
      await _recargarDatos();
    }
    state = state.copyWith(operandoCobro: false);
    return resultado;
  }

  Future<CerrarConfiguracionCobroResultado?> cerrarConfiguracionCobro(
    String configuracionCobroId,
    DateTime fechaEfectiva,
  ) async {
    if (state.operandoCobro) return null;
    state = state.copyWith(operandoCobro: true);

    final resultado = await ref
        .read(cerrarConfiguracionCobroUseCaseProvider)
        .ejecutar(configuracionCobroId: configuracionCobroId, fechaEfectiva: fechaEfectiva);
    if (resultado is CerrarConfiguracionCobroExitoso) {
      await _recargarDatos();
    }
    state = state.copyWith(operandoCobro: false);
    return resultado;
  }

  Future<CancelarVigenciaProgramadaConfiguracionCobroResultado?> cancelarVigenciaProgramadaConfiguracionCobro(
    String vigenciaId,
  ) async {
    if (state.operandoCobro) return null;
    state = state.copyWith(operandoCobro: true);

    final resultado =
        await ref.read(cancelarVigenciaProgramadaConfiguracionCobroUseCaseProvider).ejecutar(vigenciaId: vigenciaId);
    if (resultado is CancelarVigenciaProgramadaConfiguracionCobroExitoso) {
      await _recargarDatos();
    }
    state = state.copyWith(operandoCobro: false);
    return resultado;
  }

  Future<ActualizarObservacionesConfiguracionCobroVigenciaResultado?> actualizarObservacionesConfiguracionCobroVigencia({
    required String vigenciaId,
    String? observaciones,
  }) async {
    if (state.operandoCobro) return null;
    state = state.copyWith(operandoCobro: true);

    final resultado = await ref
        .read(actualizarObservacionesConfiguracionCobroVigenciaUseCaseProvider)
        .ejecutar(vigenciaId: vigenciaId, observaciones: observaciones);
    if (resultado is ActualizarObservacionesConfiguracionCobroVigenciaExitoso) {
      await _recargarDatos();
    }
    state = state.copyWith(operandoCobro: false);
    return resultado;
  }

  Future<CambiarVigenciaLineaComercialResultado?> cambiarVigenciaLinea(
    String lineaComercialId,
    LineaComercialBorrador borrador,
  ) async {
    if (state.operandoComercial) return null;
    state = state.copyWith(operandoComercial: true);

    final resultado = await ref
        .read(cambiarVigenciaLineaComercialUseCaseProvider)
        .ejecutar(lineaComercialId: lineaComercialId, borrador: borrador);
    if (resultado is CambiarVigenciaLineaComercialExitoso) {
      await _recargarDatos();
    }
    state = state.copyWith(operandoComercial: false);
    return resultado;
  }

  Future<CerrarLineaComercialResultado?> cerrarLineaComercial(
    String lineaComercialId,
    DateTime fechaEfectiva,
  ) async {
    if (state.operandoComercial) return null;
    state = state.copyWith(operandoComercial: true);

    final resultado = await ref
        .read(cerrarLineaComercialUseCaseProvider)
        .ejecutar(lineaComercialId: lineaComercialId, fechaEfectiva: fechaEfectiva);
    if (resultado is CerrarLineaComercialExitoso) {
      await _recargarDatos();
    }
    state = state.copyWith(operandoComercial: false);
    return resultado;
  }

  Future<CancelarVigenciaProgramadaResultado?> cancelarVigenciaProgramada(String vigenciaId) async {
    if (state.operandoComercial) return null;
    state = state.copyWith(operandoComercial: true);

    final resultado = await ref.read(cancelarVigenciaProgramadaUseCaseProvider).ejecutar(vigenciaId: vigenciaId);
    if (resultado is CancelarVigenciaProgramadaExitoso) {
      await _recargarDatos();
    }
    state = state.copyWith(operandoComercial: false);
    return resultado;
  }

  Future<ActualizarAnotacionesVigenciaResultado?> actualizarAnotacionesVigencia({
    required String vigenciaId,
    String? descripcion,
    String? observaciones,
  }) async {
    if (state.operandoComercial) return null;
    state = state.copyWith(operandoComercial: true);

    final resultado = await ref.read(actualizarAnotacionesVigenciaUseCaseProvider).ejecutar(
          vigenciaId: vigenciaId,
          descripcion: descripcion,
          observaciones: observaciones,
        );
    if (resultado is ActualizarAnotacionesVigenciaExitoso) {
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

  Future<GuardarSueldoReferenciaServicioResultado?> guardarSueldoReferencia({
    required int? sueldoMensualReferenciaPersonal,
    required int? bonoMensualReferenciaPersonal,
  }) async {
    if (state.operandoRelacion) return null;
    state = state.copyWith(operandoRelacion: true);

    final resultado = await ref.read(guardarSueldoReferenciaServicioUseCaseProvider).ejecutar(
          servicioId: servicioId,
          sueldoMensualReferenciaPersonal: sueldoMensualReferenciaPersonal,
          bonoMensualReferenciaPersonal: bonoMensualReferenciaPersonal,
        );
    if (resultado is GuardarSueldoReferenciaServicioExitoso) {
      await _recargarDatos();
    }
    state = state.copyWith(operandoRelacion: false);
    return resultado;
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
      configuracionCobro: datosActuales.configuracionCobro,
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
