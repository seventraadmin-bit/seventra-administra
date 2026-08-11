import 'package:riseg_one/features/reportes/domain/usecases/obtener_resumen_compras_usecase.dart';
import 'package:riseg_one/features/reportes/domain/usecases/obtener_resumen_inventario_usecase.dart';
import 'package:riseg_one/features/reportes/domain/usecases/obtener_resumen_telefonia_usecase.dart';
import 'package:riseg_one/features/reportes/domain/usecases/obtener_resumen_vehiculos_usecase.dart';

/// Estado de la pestaña Operación de Reportes (Etapa 12C).
///
/// Cada `resumenXxx` es `null` cuando la sesión no tiene el permiso de
/// ese bloque (`compras.ver`/`inventario.ver`/`vehiculos.ver`/
/// `telefonia.ver`) — nunca se calcula ni se consulta en ese caso
/// (guardia real en el controller, antes de tocar cualquier
/// repositorio). Mismo patrón que la pestaña Personal · Nómina (12B).
class ReportesOperacionState {
  const ReportesOperacionState({
    this.cargando = true,
    this.rangoInicio,
    this.rangoFin,
    this.resumenCompras,
    this.resumenInventario,
    this.resumenVehiculos,
    this.resumenTelefonia,
    this.errorCarga,
  });

  final bool cargando;
  final DateTime? rangoInicio;
  final DateTime? rangoFin;
  final ResumenComprasReportes? resumenCompras;
  final ResumenInventarioReportes? resumenInventario;
  final ResumenVehiculosReportes? resumenVehiculos;
  final ResumenTelefoniaReportes? resumenTelefonia;
  final String? errorCarga;

  ReportesOperacionState copyWith({
    bool? cargando,
    DateTime? rangoInicio,
    DateTime? rangoFin,
    ResumenComprasReportes? resumenCompras,
    ResumenInventarioReportes? resumenInventario,
    ResumenVehiculosReportes? resumenVehiculos,
    ResumenTelefoniaReportes? resumenTelefonia,
    String? errorCarga,
  }) {
    return ReportesOperacionState(
      cargando: cargando ?? this.cargando,
      rangoInicio: rangoInicio ?? this.rangoInicio,
      rangoFin: rangoFin ?? this.rangoFin,
      resumenCompras: resumenCompras ?? this.resumenCompras,
      resumenInventario: resumenInventario ?? this.resumenInventario,
      resumenVehiculos: resumenVehiculos ?? this.resumenVehiculos,
      resumenTelefonia: resumenTelefonia ?? this.resumenTelefonia,
      errorCarga: errorCarga,
    );
  }
}
