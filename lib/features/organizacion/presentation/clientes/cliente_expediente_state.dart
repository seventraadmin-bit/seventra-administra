import 'package:riseg_one/features/organizacion/domain/usecases/cliente_expediente_data.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cliente_expediente_errors.dart';

enum ClienteExpedienteModo { consulta, edicion }

/// Estado de la pantalla de expediente de Cliente — mismo shape que
/// `PuestoExpedienteState`, con el cambio de estatus como acción
/// independiente del guardado del formulario (igual que el ciclo de
/// vida de Puesto o el estado operativo de Sucursal), y los Contactos
/// administrados dentro del mismo expediente sin pantalla propia.
class ClienteExpedienteState {
  const ClienteExpedienteState({
    this.cargando = true,
    this.guardando = false,
    this.cambiandoEstatus = false,
    this.operandoEntidadFiscal = false,
    this.operandoClientePortal = false,
    this.tieneCambiosSinGuardar = false,
    this.modo = ClienteExpedienteModo.consulta,
    this.datos,
    this.errorCarga,
    this.erroresGuardado = const [],
    this.errorGuardadoGeneral = false,
  });

  final bool cargando;
  final bool guardando;
  final bool cambiandoEstatus;

  /// Bloquea las acciones de Entidad fiscal (agregar/editar/archivar/
  /// reactivar/domicilio) mientras una está en curso — evita doble
  /// ejecución por doble clic (punto 8 de la Etapa 4E.2).
  final bool operandoEntidadFiscal;

  /// Mismo criterio que `operandoEntidadFiscal`, para las acciones de
  /// portal (Etapa 15).
  final bool operandoClientePortal;
  final bool tieneCambiosSinGuardar;
  final ClienteExpedienteModo modo;
  final ClienteExpedienteData? datos;
  final String? errorCarga;
  final List<ErrorExpedienteCliente> erroresGuardado;
  final bool errorGuardadoGeneral;

  ClienteExpedienteState copyWith({
    bool? cargando,
    bool? guardando,
    bool? cambiandoEstatus,
    bool? operandoEntidadFiscal,
    bool? operandoClientePortal,
    bool? tieneCambiosSinGuardar,
    ClienteExpedienteModo? modo,
    ClienteExpedienteData? datos,
    String? errorCarga,
    List<ErrorExpedienteCliente>? erroresGuardado,
    bool? errorGuardadoGeneral,
  }) {
    return ClienteExpedienteState(
      cargando: cargando ?? this.cargando,
      guardando: guardando ?? this.guardando,
      cambiandoEstatus: cambiandoEstatus ?? this.cambiandoEstatus,
      operandoEntidadFiscal: operandoEntidadFiscal ?? this.operandoEntidadFiscal,
      operandoClientePortal: operandoClientePortal ?? this.operandoClientePortal,
      tieneCambiosSinGuardar: tieneCambiosSinGuardar ?? this.tieneCambiosSinGuardar,
      modo: modo ?? this.modo,
      datos: datos ?? this.datos,
      errorCarga: errorCarga,
      erroresGuardado: erroresGuardado ?? this.erroresGuardado,
      errorGuardadoGeneral: errorGuardadoGeneral ?? this.errorGuardadoGeneral,
    );
  }
}
