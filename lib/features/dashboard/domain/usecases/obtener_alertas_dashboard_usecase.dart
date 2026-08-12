import 'package:riseg_one/features/finanzas/domain/repositories/cuenta_por_cobrar_repository.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cuenta_por_cobrar_antiguedad.dart';

import 'obtener_empleados_baja_con_pendiente_usecase.dart';

/// Cuentas por cobrar vencidas (cualquier rango de antigüedad distinto
/// de `alCorriente`) — a la fecha de hoy, mismo cálculo que ya usa
/// `ReportesFinanzasController` (reutiliza la misma función pura
/// `calcularRangoAntiguedad`, nunca la reimplementa).
class AlertaCxCVencida {
  const AlertaCxCVencida({required this.cantidadCuentas, required this.montoTotal});

  final int cantidadCuentas;
  final int montoTotal;
}

/// Alertas del Dashboard (Etapa 13) — cada campo `null` cuando el
/// llamador no incluyó esa sección (sin autorización), nunca `0`. La
/// alerta de empleados de baja con Inventario pendiente exige AMBOS
/// permisos (`personal.ver` y `inventario.ver`) — nunca se muestra a
/// quien solo tiene uno de los dos.
class AlertasDashboard {
  const AlertasDashboard({this.cxcVencida, this.empleadosBajaConPendiente});

  final AlertaCxCVencida? cxcVencida;
  final List<EmpleadoConAsignacionesPendientes>? empleadosBajaConPendiente;
}

class ObtenerAlertasDashboardUseCase {
  ObtenerAlertasDashboardUseCase(this._cuentaPorCobrarRepository, this._obtenerEmpleadosBajaConPendiente);

  final CuentaPorCobrarRepository _cuentaPorCobrarRepository;
  final ObtenerEmpleadosBajaConPendienteUseCase _obtenerEmpleadosBajaConPendiente;

  Future<AlertasDashboard> ejecutar({
    required bool incluirCxC,
    required bool incluirEmpleadosBajaConPendiente,
    DateTime? hoy,
  }) async {
    AlertaCxCVencida? cxcVencida;
    if (incluirCxC) {
      final referencia = hoy ?? DateTime.now();
      final cuentas = await _cuentaPorCobrarRepository.listar();
      var cantidad = 0;
      var monto = 0;
      for (final cuenta in cuentas) {
        if (cuenta.estatus == 'pagada') continue;
        if (calcularRangoAntiguedad(cuenta, referencia) == RangoAntiguedadCuentaPorCobrar.alCorriente) continue;
        cantidad++;
        monto += cuenta.saldoPendiente;
      }
      cxcVencida = AlertaCxCVencida(cantidadCuentas: cantidad, montoTotal: monto);
    }

    final empleadosBajaConPendiente =
        incluirEmpleadosBajaConPendiente ? await _obtenerEmpleadosBajaConPendiente.ejecutar() : null;

    return AlertasDashboard(cxcVencida: cxcVencida, empleadosBajaConPendiente: empleadosBajaConPendiente);
  }
}
