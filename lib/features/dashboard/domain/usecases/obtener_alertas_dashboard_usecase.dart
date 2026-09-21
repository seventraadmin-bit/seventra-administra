import 'package:riseg_one/features/finanzas/domain/repositories/cuenta_por_cobrar_repository.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/deuda_repository.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/calcular_fecha_tarjeta_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cuenta_por_cobrar_antiguedad.dart';
import 'package:riseg_one/features/notificaciones/domain/usecases/obtener_notificaciones_documentos_por_emitir_usecase.dart';
import 'package:riseg_one/features/notificaciones/domain/usecases/resultado_notificacion.dart';

import 'obtener_empleados_baja_con_pendiente_usecase.dart';

/// Umbral de "utilización alta" de una tarjeta de crédito empresarial
/// (Etapa 19B) — confirmado explícito en el pedido, mismo estilo que
/// `umbralDiasProximoAVencerDocumento` de Vehículos.
const umbralUtilizacionAltaTarjeta = 80;

/// Umbral de "pago próximo" de una tarjeta — días, mismo estilo que
/// `umbralDiasCxcProximaAVencer`.
const umbralDiasPagoProximoTarjeta = 7;

/// Tarjeta que requiere atención (Etapa 19B) — utilización >= 80% o
/// pago venciendo en <= 7 días, nunca si `saldoActual == 0` (una
/// tarjeta sin saldo no tiene nada accionable, sin importar su fecha de
/// corte/pago).
class AlertaTarjeta {
  const AlertaTarjeta({
    required this.deudaId,
    required this.nombre,
    required this.utilizacion,
    required this.diasParaPago,
    required this.saldoActual,
    required this.proximaFechaPago,
    required this.vencida,
  });

  final String deudaId;
  final String nombre;

  /// 0-100, `null` si la tarjeta no capturó límite de crédito.
  final double? utilizacion;
  final int? diasParaPago;
  final int saldoActual;

  /// Misma fuente que `diasParaPago` (`proximaFechaPagoDeuda`) — se
  /// expone la fecha completa para poder mostrarla en la alerta
  /// (Etapa "Dashboard: posición financiera"), `null` si la
  /// configuración de la tarjeta está incompleta.
  final DateTime? proximaFechaPago;

  /// `true` cuando [proximaFechaPago] ya quedó en el pasado — posible
  /// desde que `tarjetaVencimientoCubiertoHasta` existe: un ciclo
  /// cubierto viejo con ciclos reales saltados de por medio. Antes de
  /// ese campo era estructuralmente imposible (el cálculo solo sabía
  /// avanzar desde hoy).
  final bool vencida;
}

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
  const AlertasDashboard({
    this.cxcVencida,
    this.empleadosBajaConPendiente,
    this.tarjetasEnAlerta,
    this.documentosPorEmitirPendientes,
  });

  final AlertaCxCVencida? cxcVencida;
  final List<EmpleadoConAsignacionesPendientes>? empleadosBajaConPendiente;
  final List<AlertaTarjeta>? tarjetasEnAlerta;

  /// Documentos comerciales que ya corresponde emitir (Etapa 20) —
  /// reutiliza `ObtenerNotificacionesDocumentosPorEmitirUseCase`
  /// (Centro de notificaciones, Etapa 14B), nunca reimplementa la regla
  /// `documentoPorEmitirRequiereAccion`.
  final List<ResultadoNotificacion>? documentosPorEmitirPendientes;
}

class ObtenerAlertasDashboardUseCase {
  ObtenerAlertasDashboardUseCase(
    this._cuentaPorCobrarRepository,
    this._obtenerEmpleadosBajaConPendiente,
    this._deudaRepository,
    this._obtenerNotificacionesDocumentosPorEmitir,
  );

  final CuentaPorCobrarRepository _cuentaPorCobrarRepository;
  final ObtenerEmpleadosBajaConPendienteUseCase _obtenerEmpleadosBajaConPendiente;
  final DeudaRepository _deudaRepository;
  final ObtenerNotificacionesDocumentosPorEmitirUseCase _obtenerNotificacionesDocumentosPorEmitir;

  Future<AlertasDashboard> ejecutar({
    required bool incluirCxC,
    required bool incluirEmpleadosBajaConPendiente,
    required bool incluirTarjetas,
    required bool incluirDocumentosPorEmitir,
    DateTime? hoy,
  }) async {
    final referencia = hoy ?? DateTime.now();

    AlertaCxCVencida? cxcVencida;
    if (incluirCxC) {
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

    List<AlertaTarjeta>? tarjetasEnAlerta;
    if (incluirTarjetas) {
      final tarjetas = await _deudaRepository.listarTarjetasActivas();
      final referenciaSoloFecha = DateTime(referencia.year, referencia.month, referencia.day);
      tarjetasEnAlerta = [
        for (final t in tarjetas)
          if (t.saldoActual > 0)
            () {
              // Única fuente de verdad (`proximaFechaPagoDeuda`) — antes
              // ignoraba `tarjetaReglaFechaPago`/`tarjetaDiasDespuesCorte`,
              // así que una tarjeta configurada con "días después del
              // corte" (ej. Konfío Empresarial) nunca podía disparar
              // esta alerta, sin importar qué tan próximo estuviera su
              // pago real.
              final proximaFechaPago = proximaFechaPagoDeuda(t, referencia);
              return AlertaTarjeta(
                deudaId: t.id,
                nombre: t.nombre,
                utilizacion: (t.tarjetaLimiteCredito == null || t.tarjetaLimiteCredito == 0)
                    ? null
                    : (t.saldoActual / t.tarjetaLimiteCredito! * 100),
                diasParaPago: proximaFechaPago?.difference(referenciaSoloFecha).inDays,
                saldoActual: t.saldoActual,
                proximaFechaPago: proximaFechaPago,
                // `tarjetaVencimientoCubiertoHasta` es lo único que puede
                // hacer que `proximaFechaPagoDeuda` devuelva una fecha
                // anterior a hoy (ciclo cubierto viejo, ciclos reales
                // saltados de por medio) — antes de ese campo, esto era
                // estructuralmente imposible.
                vencida: proximaFechaPago != null && proximaFechaPago.isBefore(referenciaSoloFecha),
              );
            }(),
      ].where((a) => (a.utilizacion != null && a.utilizacion! >= umbralUtilizacionAltaTarjeta) ||
              (a.diasParaPago != null && a.diasParaPago! <= umbralDiasPagoProximoTarjeta)).toList();
    }

    final documentosPorEmitirPendientes =
        incluirDocumentosPorEmitir ? await _obtenerNotificacionesDocumentosPorEmitir.ejecutar(hoy: referencia) : null;

    return AlertasDashboard(
      cxcVencida: cxcVencida,
      empleadosBajaConPendiente: empleadosBajaConPendiente,
      tarjetasEnAlerta: tarjetasEnAlerta,
      documentosPorEmitirPendientes: documentosPorEmitirPendientes,
    );
  }
}
