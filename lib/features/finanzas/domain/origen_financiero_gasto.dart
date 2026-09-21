import 'package:riseg_one/core/database/app_database.dart';

import '../data/tables/deuda_table.dart' show TipoDeuda, EstatusDeuda;
import 'usecases/calcular_fecha_tarjeta_usecase.dart' show creditoDisponibleTarjeta;

/// Origen financiero de un gasto — de dónde sale el dinero, o qué
/// pasivo se carga — independiente de la "forma de pago" descriptiva
/// (`FormaPago`). Reutilizado por cualquier módulo que reconozca un
/// gasto con un origen estructurado (Compras ya tenía esta bifurcación
/// duplicada 3 veces sin ningún tipo compartido; Tiempos Extra la
/// reutiliza desde aquí, nunca la reimplementa). `null` (no un tercer
/// caso) sigue significando "sin especificar" — mismo criterio que
/// `Egreso.cuentaFinancieraId` nullable hoy.
sealed class OrigenFinancieroGasto {}

class OrigenFinancieroCuenta extends OrigenFinancieroGasto {
  OrigenFinancieroCuenta(this.cuentaFinancieraId);
  final String cuentaFinancieraId;
}

class OrigenFinancieroTarjeta extends OrigenFinancieroGasto {
  OrigenFinancieroTarjeta(this.deudaId);
  final String deudaId;
}

/// Por qué una TDC propuesta como origen no es válida — mismos 3
/// checks que ya vivían inline en `RegistrarCompraUseCase` (existe,
/// `tipo == tarjetaCredito`, `estatus == activa`, límite suficiente),
/// extraídos aquí para que Tiempos Extra los reutilice sin duplicar la
/// regla.
enum ErrorOrigenTarjeta { noEsTarjetaActiva, sinLimiteConfigurado, excedeLimite }

class ValidacionOrigenTarjeta {
  const ValidacionOrigenTarjeta.valida()
      : error = null,
        disponible = null;
  const ValidacionOrigenTarjeta.invalida(this.error, {this.disponible});

  final ErrorOrigenTarjeta? error;

  /// Solo poblado cuando [error] es [ErrorOrigenTarjeta.excedeLimite] —
  /// el mensaje al usuario cita el monto exacto disponible.
  final int? disponible;

  bool get esValida => error == null;
}

/// Valida que [tarjeta] pueda cargar [monto] — única fuente de verdad,
/// reutilizada por `RegistrarCompraUseCase` y `RegistrarTiempoExtraUseCase`.
ValidacionOrigenTarjeta validarOrigenTarjeta({required DeudaData? tarjeta, required int monto}) {
  if (tarjeta == null || tarjeta.tipo != TipoDeuda.tarjetaCredito.name || tarjeta.estatus != EstatusDeuda.activa.name) {
    return const ValidacionOrigenTarjeta.invalida(ErrorOrigenTarjeta.noEsTarjetaActiva);
  }
  final disponible = creditoDisponibleTarjeta(limiteCredito: tarjeta.tarjetaLimiteCredito, saldoActual: tarjeta.saldoActual);
  if (disponible == null) return const ValidacionOrigenTarjeta.invalida(ErrorOrigenTarjeta.sinLimiteConfigurado);
  if (monto > disponible) return ValidacionOrigenTarjeta.invalida(ErrorOrigenTarjeta.excedeLimite, disponible: disponible);
  return const ValidacionOrigenTarjeta.valida();
}
