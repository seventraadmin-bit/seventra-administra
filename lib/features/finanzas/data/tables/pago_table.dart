import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';
import '../../../organizacion/data/tables/cliente_table.dart';
import 'cuenta_por_cobrar_table.dart';

/// Cómo se recibió el dinero (Etapa 4J.2) — enum cerrado y acotado
/// deliberadamente (Marlon no pidió un catálogo administrable). `otro`
/// es la válvula de escape, mismo criterio que `otroSoporte` en
/// Adjuntos (4I.2.2): agregar una forma de pago no anticipada es un
/// nuevo valor de enum, nunca una migración de tabla.
enum FormaPago { efectivo, transferencia, cheque, tarjeta, otro }

enum EstatusPago { registrado, cancelado }

/// Tipos de evento del historial de un Pago (`PagoEvento`) — mismo
/// criterio append-only que `CuentaPorCobrarEvento`/
/// `DocumentoPorEmitirEvento`. `comprobanteAdjuntado` mismo criterio
/// que `archivoAdjuntado` en `DocumentoPorEmitirEvento`.
enum TipoEventoPago { registrado, corregido, cancelado, comprobanteAdjuntado }

/// El dinero recibido (Etapa 4J.2, modelo N:M aprobado por Marlon) —
/// deliberadamente **sin** referencia a ninguna `CuentaPorCobrar`: a
/// qué Cuenta(s) se aplica y cuánto es responsabilidad exclusiva de
/// `AplicacionPago`. Un `Pago` con `montoAplicado == 0` es un estado
/// válido y esperado (Resolución 8 de Marlon) — la interfaz de 4J.2
/// solo ofrece un flujo simplificado que crea el Pago y su única
/// aplicación en el mismo paso, pero el modelo nunca lo exige.
///
/// `clienteId` sí es una FK real (a diferencia de
/// `CuentaPorCobrar.clienteId`, que es un snapshot copiado del
/// documento de origen): aquí es la única relación de negocio que
/// tiene el Pago antes de aplicarse a nada, y sostiene la regla de
/// dominio "un Pago solo se aplica a Cuentas por cobrar del mismo
/// Cliente".
class Pago extends Table with AuditColumns {
  /// Identificador visible (`PAG-000001`, vía `CodigoSecuencia`) —
  /// nunca capturado por el usuario (Resolución 2 de Marlon: sirve
  /// para referirse a "el pago que liquidó estas cuatro cuentas" sin
  /// usar el UUID interno).
  TextColumn get folioPago => text().unique()();

  TextColumn get clienteId => text().references(Cliente, #id, onDelete: KeyAction.restrict)();

  IntColumn get montoTotal => integer()();

  /// Denormalizado, mantenido transaccionalmente por
  /// `AplicarPagoACuentaUseCase`/`CancelarAplicacionPagoUseCase` —
  /// mismo criterio que `CuentaPorCobrar.saldoPendiente`.
  /// `montoTotal - montoAplicado` (el dinero sin aplicar) se deriva
  /// donde se necesite, nunca se guarda una tercera columna redundante.
  IntColumn get montoAplicado => integer().withDefault(const Constant(0))();

  DateTimeColumn get fechaPago => dateTime()();

  TextColumn get formaPago => text()();

  TextColumn get referencia => text().nullable()();

  /// Texto libre (Resolución 3 de Marlon) — el administrativo suele
  /// recordar "vino de Banorte" aunque no tenga el comprobante a la
  /// mano; sin catálogo de Bancos todavía.
  TextColumn get bancoOrigen => text().nullable()();

  /// Texto libre, mismo criterio ya usado por
  /// `ConfiguracionCobroVigencia.cuentaBancaria` — sin catálogo de
  /// Bancos todavía.
  TextColumn get cuentaBancariaDestino => text().nullable()();

  TextColumn get observaciones => text().nullable()();

  TextColumn get estatus => text().withDefault(const Constant('registrado'))();

  @override
  List<String> get customConstraints => [
        'CHECK (monto_total > 0)',
        'CHECK (monto_aplicado >= 0 AND monto_aplicado <= monto_total)',
      ];
}

enum EstatusAplicacionPago { aplicada, cancelada }

/// Cuánto de un `Pago` se aplicó a una `CuentaPorCobrar` (Etapa 4J.2)
/// — la tabla intermedia N:M que permite que un mismo Pago liquide
/// varias Cuentas y que una misma Cuenta reciba abonos de varios
/// Pagos. Nunca se elimina una fila (Resolución 6 de Marlon): solo
/// `aplicada`/`cancelada`, siempre con historial.
///
/// `saldoAntes`/`saldoDespues` son snapshot inmutable del
/// `saldoPendiente` de la Cuenta en el momento de esta aplicación
/// específica — nunca se recalculan, incluso después de cancelarse
/// (cancelar revierte el efecto vivo sobre la Cuenta, no reescribe
/// este registro histórico).
class AplicacionPago extends Table with AuditColumns {
  TextColumn get pagoId => text().references(Pago, #id, onDelete: KeyAction.restrict)();

  TextColumn get cuentaPorCobrarId =>
      text().references(CuentaPorCobrar, #id, onDelete: KeyAction.restrict)();

  IntColumn get monto => integer()();

  IntColumn get saldoAntes => integer()();

  IntColumn get saldoDespues => integer()();

  TextColumn get estatus => text().withDefault(const Constant('aplicada'))();

  TextColumn get motivoCancelacion => text().nullable()();

  @override
  List<String> get customConstraints => [
        'CHECK (monto > 0)',
        'CHECK (saldo_despues = saldo_antes - monto)',
        'CHECK (saldo_despues >= 0)',
      ];
}

/// Historial administrativo de un Pago (Etapa 4J.2) — tabla de solo
/// inserción, mismo criterio exacto que `CuentaPorCobrarEvento`. Vive
/// separada de `CuentaPorCobrarEvento` porque el ciclo de vida del
/// Pago (registrado/corregido/cancelado) ya no pertenece a una sola
/// Cuenta por cobrar bajo el modelo N:M — el efecto de cada aplicación
/// sobre una Cuenta específica sigue viviendo en
/// `CuentaPorCobrarEvento` (valores nuevos `pagoAplicado`/
/// `pagoAplicacionCancelada` de `TipoEventoCuentaPorCobrar`).
class PagoEvento extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get pagoId => text().references(Pago, #id, onDelete: KeyAction.cascade)();

  DateTimeColumn get fechaHora => dateTime()();

  TextColumn get tipoEvento => text()();

  TextColumn get estadoAnterior => text().nullable()();

  TextColumn get estadoNuevo => text().nullable()();

  TextColumn get observacion => text().nullable()();

  TextColumn get actor => text().nullable()();

  TextColumn get datosRelevantes => text().nullable()();
}
