import 'package:riseg_one/core/database/app_database.dart';

/// Veredicto de la política para una salida concreta desde una cuenta.
sealed class VeredictoSaldo {
  const VeredictoSaldo();
}

class SaldoSuficiente extends VeredictoSaldo {
  const SaldoSuficiente();
}

class SaldoInsuficiente extends VeredictoSaldo {
  const SaldoInsuficiente({
    required this.cuentaId,
    required this.cuentaNombre,
    required this.disponible,
    required this.requerido,
  });

  final String cuentaId;
  final String cuentaNombre;
  final int disponible;
  final int requerido;

  int get faltante => requerido - disponible;
}

/// La fecha del movimiento es anterior al saldo inicial de la cuenta.
///
/// Un movimiento así no se sumaría al saldo (ver el corte en
/// `calcularSaldosCanonico`), así que aceptarlo produciría un Egreso
/// real que el saldo no refleja: dinero que sale y no se ve.
class FechaAnteriorAlSaldoInicial extends VeredictoSaldo {
  const FechaAnteriorAlSaldoInicial({
    required this.cuentaId,
    required this.cuentaNombre,
    required this.fechaMovimiento,
    required this.fechaSaldoInicial,
  });

  final String cuentaId;
  final String cuentaNombre;
  final DateTime fechaMovimiento;
  final DateTime fechaSaldoInicial;
}

class CuentaNoDisponible extends VeredictoSaldo {
  const CuentaNoDisponible(this.cuentaId);
  final String cuentaId;
}

/// **La política de sobregiro del proyecto**, en un objeto de dominio
/// propio y no dentro de un repositorio.
///
/// El repositorio de Egresos la *aplica* —es el único punto de entrada
/// de escritura, así que es el único lugar desde donde nadie puede
/// saltársela— pero no la *decide*. Esa separación es lo que permite
/// que mañana una cuenta con línea de crédito o sobregiro autorizado
/// cambie la regla aquí, en una clase con pruebas propias, sin tocar
/// los diez orígenes que crean Egresos ni el repositorio.
///
/// Hoy la regla es simple y deliberadamente estricta: **ninguna cuenta
/// puede quedar en negativo por un movimiento nuevo**. Una cuenta que
/// ya esté en negativo por historia previa puede recibir dinero, pero
/// no puede volver a pagar hasta recuperarse — eso sale solo de
/// comparar `disponible >= requerido`, sin ningún caso especial.
///
/// Las tarjetas de crédito **no pasan por aquí**: no son
/// `CuentaFinanciera`, viven en `Deuda`/`MovimientoDeuda` y su límite
/// es crédito disponible, no saldo de caja.
class PoliticaSaldoCuenta {
  const PoliticaSaldoCuenta();

  /// Todo en centavos. `disponible == requerido` es **suficiente**: la
  /// cuenta queda exactamente en $0.00, que es un saldo válido.
  VeredictoSaldo verificar({
    required CuentaFinancieraData? cuenta,
    required int disponible,
    required int requerido,
    required DateTime fechaMovimiento,
  }) {
    if (cuenta == null || cuenta.cicloVidaRegistro != 'activo') {
      return CuentaNoDisponible(cuenta?.id ?? '');
    }

    final fecha = DateTime(fechaMovimiento.year, fechaMovimiento.month, fechaMovimiento.day);
    final corte = DateTime(
      cuenta.fechaSaldoInicial.year,
      cuenta.fechaSaldoInicial.month,
      cuenta.fechaSaldoInicial.day,
    );
    if (fecha.isBefore(corte)) {
      return FechaAnteriorAlSaldoInicial(
        cuentaId: cuenta.id,
        cuentaNombre: cuenta.nombre,
        fechaMovimiento: fecha,
        fechaSaldoInicial: corte,
      );
    }

    if (disponible < requerido) {
      return SaldoInsuficiente(
        cuentaId: cuenta.id,
        cuentaNombre: cuenta.nombre,
        disponible: disponible,
        requerido: requerido,
      );
    }

    return const SaldoSuficiente();
  }
}

/// Lo que el repositorio lanza cuando la política rechaza una escritura.
///
/// Es una excepción y no un valor de retorno a propósito: aborta la
/// transacción y con ella **todo** lo que el origen llevara escrito
/// (el `PagoNomina`, sus aplicaciones, la `Compra`, sus movimientos de
/// inventario…). Un rechazo parcial sería peor que no validar.
class SaldoInsuficienteException implements Exception {
  SaldoInsuficienteException(this.veredicto);

  final VeredictoSaldo veredicto;

  @override
  String toString() => 'SaldoInsuficienteException($veredicto)';
}
