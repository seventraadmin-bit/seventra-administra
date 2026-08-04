import 'package:riseg_one/features/organizacion/domain/repositories/catalogo_repository.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/sucursal_expediente_data.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/sucursal_expediente_errors.dart';

enum SucursalExpedienteModo { consulta, edicion }

/// Estado de la pantalla de expediente de Sucursal — mismo shape que
/// `EmpresaExpedienteState`, más `tipos` (catálogo para el selector) y
/// `cambiandoEstadoOperativo` (la acción de botón es independiente del
/// guardado del formulario).
class SucursalExpedienteState {
  const SucursalExpedienteState({
    this.cargando = true,
    this.guardando = false,
    this.cambiandoEstadoOperativo = false,
    this.tieneCambiosSinGuardar = false,
    this.modo = SucursalExpedienteModo.consulta,
    this.datos,
    this.tipos = const [],
    this.errorCarga,
    this.erroresGuardado = const [],
    this.errorGuardadoGeneral = false,
  });

  final bool cargando;
  final bool guardando;
  final bool cambiandoEstadoOperativo;
  final bool tieneCambiosSinGuardar;
  final SucursalExpedienteModo modo;
  final SucursalExpedienteData? datos;
  final List<CatalogoItem> tipos;
  final String? errorCarga;
  final List<ErrorExpedienteSucursal> erroresGuardado;
  final bool errorGuardadoGeneral;

  SucursalExpedienteState copyWith({
    bool? cargando,
    bool? guardando,
    bool? cambiandoEstadoOperativo,
    bool? tieneCambiosSinGuardar,
    SucursalExpedienteModo? modo,
    SucursalExpedienteData? datos,
    List<CatalogoItem>? tipos,
    String? errorCarga,
    List<ErrorExpedienteSucursal>? erroresGuardado,
    bool? errorGuardadoGeneral,
  }) {
    return SucursalExpedienteState(
      cargando: cargando ?? this.cargando,
      guardando: guardando ?? this.guardando,
      cambiandoEstadoOperativo: cambiandoEstadoOperativo ?? this.cambiandoEstadoOperativo,
      tieneCambiosSinGuardar: tieneCambiosSinGuardar ?? this.tieneCambiosSinGuardar,
      modo: modo ?? this.modo,
      datos: datos ?? this.datos,
      tipos: tipos ?? this.tipos,
      errorCarga: errorCarga,
      erroresGuardado: erroresGuardado ?? this.erroresGuardado,
      errorGuardadoGeneral: errorGuardadoGeneral ?? this.errorGuardadoGeneral,
    );
  }
}
