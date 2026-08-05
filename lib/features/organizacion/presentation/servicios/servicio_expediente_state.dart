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
      tieneCambiosSinGuardar: tieneCambiosSinGuardar ?? this.tieneCambiosSinGuardar,
      modo: modo ?? this.modo,
      datos: datos ?? this.datos,
      errorCarga: errorCarga,
      erroresGuardado: erroresGuardado ?? this.erroresGuardado,
      errorGuardadoGeneral: errorGuardadoGeneral ?? this.errorGuardadoGeneral,
    );
  }
}
