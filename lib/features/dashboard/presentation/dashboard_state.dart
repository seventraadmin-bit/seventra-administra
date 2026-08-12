import 'package:riseg_one/features/reportes/domain/usecases/obtener_resumen_general_usecase.dart';
import 'package:riseg_one/features/reportes/domain/usecases/obtener_resumen_inventario_usecase.dart';
import 'package:riseg_one/features/reportes/domain/usecases/obtener_resumen_nomina_usecase.dart';
import 'package:riseg_one/features/reportes/domain/usecases/obtener_resumen_personal_usecase.dart';
import 'package:riseg_one/features/reportes/domain/usecases/obtener_resumen_telefonia_usecase.dart';
import 'package:riseg_one/features/reportes/domain/usecases/obtener_resumen_vehiculos_usecase.dart';

import '../domain/usecases/obtener_actividad_reciente_usecase.dart';
import '../domain/usecases/obtener_alertas_dashboard_usecase.dart';

/// Estado del Dashboard (Etapa 13) — cada `resumenXxx` es `null`
/// cuando la sesión no tiene el permiso `xxx.ver` correspondiente
/// (nunca se calcula ni se consulta en ese caso, guardia real en el
/// controller). `alertas`/`actividad` sí se calculan siempre — sus
/// propios campos internos son `null` por sección, mismo criterio.
///
/// Un solo DTO por dominio alimenta más de una zona de la pantalla
/// (Resumen/Atención/Actividad) — nunca se pide el mismo dato dos
/// veces.
class DashboardState {
  const DashboardState({
    this.cargando = true,
    this.resumenGeneral,
    this.resumenPersonal,
    this.resumenNomina,
    this.resumenInventario,
    this.resumenVehiculos,
    this.resumenTelefonia,
    this.alertas,
    this.actividad,
    this.errorCarga,
  });

  final bool cargando;

  final ResumenGeneralReportes? resumenGeneral;
  final ResumenPersonalReportes? resumenPersonal;
  final ResumenNominaReportes? resumenNomina;
  final ResumenInventarioReportes? resumenInventario;
  final ResumenVehiculosReportes? resumenVehiculos;
  final ResumenTelefoniaReportes? resumenTelefonia;

  final AlertasDashboard? alertas;
  final ActividadRecienteDashboard? actividad;

  final String? errorCarga;

  DashboardState copyWith({
    bool? cargando,
    ResumenGeneralReportes? resumenGeneral,
    ResumenPersonalReportes? resumenPersonal,
    ResumenNominaReportes? resumenNomina,
    ResumenInventarioReportes? resumenInventario,
    ResumenVehiculosReportes? resumenVehiculos,
    ResumenTelefoniaReportes? resumenTelefonia,
    AlertasDashboard? alertas,
    ActividadRecienteDashboard? actividad,
    String? errorCarga,
  }) {
    return DashboardState(
      cargando: cargando ?? this.cargando,
      resumenGeneral: resumenGeneral ?? this.resumenGeneral,
      resumenPersonal: resumenPersonal ?? this.resumenPersonal,
      resumenNomina: resumenNomina ?? this.resumenNomina,
      resumenInventario: resumenInventario ?? this.resumenInventario,
      resumenVehiculos: resumenVehiculos ?? this.resumenVehiculos,
      resumenTelefonia: resumenTelefonia ?? this.resumenTelefonia,
      alertas: alertas ?? this.alertas,
      actividad: actividad ?? this.actividad,
      errorCarga: errorCarga,
    );
  }
}
