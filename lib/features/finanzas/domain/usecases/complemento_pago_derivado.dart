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

/// El Complemento VIGENTE de un Pago dentro de su histórico — `null` si
/// ninguno lo está. Un Pago puede acumular varios Complementos
/// cancelados y un sustituto vigente (schemaVersion 79); el índice
/// único parcial garantiza que a lo más uno esté `registrado`.
ComplementoPagoData? complementoVigente(List<ComplementoPagoData> complementosDelPago) {
  for (final c in complementosDelPago) {
    if (EstatusComplementoPago.values.byName(c.estatus) == EstatusComplementoPago.registrado) return c;
  }
  return null;
}

/// La obligación sigue pendiente mientras NO exista un Complemento
/// vigente. Da igual cuántos cancelados haya en el histórico: un CFDI
/// cancelado no documenta nada.
///
/// Recibe el histórico COMPLETO del Pago y no una fila suelta a
/// propósito (schemaVersion 79): mientras la relación era 1:1 bastaba
/// pasar "el" Complemento, pero ahora una fila suelta puede ser
/// cualquiera de varias y la respuesta dependería de cuál tocó — un
/// error silencioso. Con la lista, la función no se puede usar mal.
bool complementoPendiente({
  required bool requiereComplemento,
  required List<ComplementoPagoData> complementosDelPago,
}) {
  if (!requiereComplemento) return false;
  return complementoVigente(complementosDelPago) == null;
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
