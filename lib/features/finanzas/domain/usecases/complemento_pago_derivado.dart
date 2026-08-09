import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/tables/complemento_pago_table.dart';
import 'package:riseg_one/features/finanzas/data/tables/cuenta_por_cobrar_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart';

/// Indicadores derivados de Complemento de pago (Etapa 4J.3) — nunca
/// almacenados, mismo criterio que `estaVencida`/`calcularRangoAntiguedad`
/// en `cuenta_por_cobrar_antiguedad.dart`. Corrige la simplificación de
/// 4J.2 (ahí `complementoPendiente` solo se mencionaba a nivel de
/// Cuenta ya `pagada`) — la obligación fiscal real nace por cada Pago
/// aplicado a una Cuenta PPD-con-complemento, no solo cuando la Cuenta
/// queda saldada por completo.

/// Una Cuenta por cobrar exige Complemento cuando es PPD y quedó
/// marcada `requiereComplemento` al generarse (snapshot congelado
/// desde 4J.1).
bool cuentaRequiereComplemento(CuentaPorCobrarData cuenta) {
  return MetodoPagoCobro.values.byName(cuenta.metodo) == MetodoPagoCobro.ppd && cuenta.requiereComplemento;
}

/// Un Pago exige Complemento si alguna de las Cuentas que liquidó
/// (vía sus `AplicacionPago`) lo exige.
bool pagoRequiereComplemento(List<CuentaPorCobrarData> cuentasDeAplicacionesActivas) {
  return cuentasDeAplicacionesActivas.any(cuentaRequiereComplemento);
}

/// La obligación sigue pendiente si no hay Complemento, o si el único
/// que existía fue cancelado.
bool complementoPendiente({required bool requiereComplemento, required ComplementoPagoData? complemento}) {
  if (!requiereComplemento) return false;
  if (complemento == null) return true;
  return EstatusComplementoPago.values.byName(complemento.estatus) == EstatusComplementoPago.cancelado;
}

/// Una Cuenta por cobrar está verdaderamente cerrada (cobrada Y, si
/// aplica, fiscalmente completa) cuando ya está `pagada` y, si exige
/// Complemento, ninguno de los Pagos que la liquidaron sigue con la
/// obligación pendiente.
bool cierreCobranzaCompleto({
  required CuentaPorCobrarData cuenta,
  required bool algunPagoConComplementoPendiente,
}) {
  if (EstatusCuentaPorCobrar.values.byName(cuenta.estatus) != EstatusCuentaPorCobrar.pagada) return false;
  if (!cuentaRequiereComplemento(cuenta)) return true;
  return !algunPagoConComplementoPendiente;
}
