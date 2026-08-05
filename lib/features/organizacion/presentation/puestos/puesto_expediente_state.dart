import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/puesto_errors.dart';

enum PuestoExpedienteModo { consulta, edicion }

/// Estado de la pantalla de expediente de Puesto — mismo shape que
/// `SucursalExpedienteState`, sin sub-entidades (Puesto no tiene
/// dirección/horario/árbol), más `areas` (catálogo para el selector).
class PuestoExpedienteState {
  const PuestoExpedienteState({
    this.cargando = true,
    this.guardando = false,
    this.cambiandoCicloVida = false,
    this.tieneCambiosSinGuardar = false,
    this.modo = PuestoExpedienteModo.consulta,
    this.datos,
    this.areas = const [],
    this.errorCarga,
    this.erroresGuardado = const [],
    this.errorGuardadoGeneral = false,
  });

  final bool cargando;
  final bool guardando;
  final bool cambiandoCicloVida;
  final bool tieneCambiosSinGuardar;
  final PuestoExpedienteModo modo;
  final PuestoData? datos;
  final List<AreaData> areas;
  final String? errorCarga;
  final List<ErrorCampoPuesto> erroresGuardado;
  final bool errorGuardadoGeneral;

  PuestoExpedienteState copyWith({
    bool? cargando,
    bool? guardando,
    bool? cambiandoCicloVida,
    bool? tieneCambiosSinGuardar,
    PuestoExpedienteModo? modo,
    PuestoData? datos,
    List<AreaData>? areas,
    String? errorCarga,
    List<ErrorCampoPuesto>? erroresGuardado,
    bool? errorGuardadoGeneral,
  }) {
    return PuestoExpedienteState(
      cargando: cargando ?? this.cargando,
      guardando: guardando ?? this.guardando,
      cambiandoCicloVida: cambiandoCicloVida ?? this.cambiandoCicloVida,
      tieneCambiosSinGuardar: tieneCambiosSinGuardar ?? this.tieneCambiosSinGuardar,
      modo: modo ?? this.modo,
      datos: datos ?? this.datos,
      areas: areas ?? this.areas,
      errorCarga: errorCarga,
      erroresGuardado: erroresGuardado ?? this.erroresGuardado,
      errorGuardadoGeneral: errorGuardadoGeneral ?? this.errorGuardadoGeneral,
    );
  }
}
