import 'package:riseg_one/features/organizacion/domain/usecases/servicio_errors.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_expediente_data.dart';

enum ServicioExpedienteModo { consulta, edicion }

/// Estado de la pantalla de expediente de Servicio — mismo shape que
/// `ClienteExpedienteState`, con el cambio de estatus como acción
/// independiente del guardado del formulario.
class ServicioExpedienteState {
  const ServicioExpedienteState({
    this.cargando = true,
    this.guardando = false,
    this.cambiandoEstatus = false,
    this.operandoRelacion = false,
    this.operandoComercial = false,
    this.operandoCobro = false,
    this.tieneCambiosSinGuardar = false,
    this.modo = ServicioExpedienteModo.consulta,
    this.datos,
    this.errorCarga,
    this.erroresGuardado = const [],
    this.errorGuardadoGeneral = false,
  });

  final bool cargando;
  final bool guardando;
  final bool cambiandoEstatus;

  /// Bloquea las 5 acciones de vinculación (Entidad fiscal, Responsable
  /// del Cliente, Sucursal administrativa, Responsable interno,
  /// Dirección operativa) contra doble-clic — mismo patrón que
  /// `operandoEntidadFiscal` en `ClienteExpedienteState`.
  final bool operandoRelacion;

  /// Bloquea el alta de una línea comercial (Etapa 4G.1) contra
  /// doble-clic — independiente de `operandoRelacion` porque es un
  /// dominio propio (Configuración comercial), no una vinculación.
  final bool operandoComercial;

  /// Bloquea el alta de la Configuración de cobro (Etapa 4H.1) contra
  /// doble-clic — dominio propio, independiente de `operandoComercial`.
  final bool operandoCobro;
  final bool tieneCambiosSinGuardar;
  final ServicioExpedienteModo modo;
  final ServicioExpedienteData? datos;
  final String? errorCarga;
  final List<ErrorCampoServicio> erroresGuardado;
  final bool errorGuardadoGeneral;

  ServicioExpedienteState copyWith({
    bool? cargando,
    bool? guardando,
    bool? cambiandoEstatus,
    bool? operandoRelacion,
    bool? operandoComercial,
    bool? operandoCobro,
    bool? tieneCambiosSinGuardar,
    ServicioExpedienteModo? modo,
    ServicioExpedienteData? datos,
    String? errorCarga,
    List<ErrorCampoServicio>? erroresGuardado,
    bool? errorGuardadoGeneral,
  }) {
    return ServicioExpedienteState(
      cargando: cargando ?? this.cargando,
      guardando: guardando ?? this.guardando,
      cambiandoEstatus: cambiandoEstatus ?? this.cambiandoEstatus,
      operandoRelacion: operandoRelacion ?? this.operandoRelacion,
      operandoComercial: operandoComercial ?? this.operandoComercial,
      operandoCobro: operandoCobro ?? this.operandoCobro,
      tieneCambiosSinGuardar: tieneCambiosSinGuardar ?? this.tieneCambiosSinGuardar,
      modo: modo ?? this.modo,
      datos: datos ?? this.datos,
      errorCarga: errorCarga,
      erroresGuardado: erroresGuardado ?? this.erroresGuardado,
      errorGuardadoGeneral: errorGuardadoGeneral ?? this.errorGuardadoGeneral,
    );
  }
}
