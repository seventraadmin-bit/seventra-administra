import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';
import '../../../finanzas/data/tables/egreso_table.dart';
import 'nomina_empleado_table.dart';
import 'nomina_table.dart';

enum EstatusPagoNomina { registrado, cancelado }

/// Tipos de evento del historial de un `PagoNomina` — mismo criterio
/// append-only que `PagoEvento`/`IngresoEvento`/`EgresoEvento`.
enum TipoEventoPagoNomina { registrado, corregido, cancelado, comprobanteAdjuntado }

/// Un lote real de pago de Nómina (Etapa 6D) — "hoy salieron $X hacia
/// estos empleados", nunca un pago agendado a futuro. Deliberadamente
/// **no** uno por Nómina completa (Resolución explícita de Marlon, tras
/// reevaluar el diseño): los empleados de una misma Nómina pueden
/// cobrar en fechas distintas, así que una Nómina puede tener 0, 1 o
/// varios `PagoNomina` a lo largo del tiempo — cada uno cubre solo a
/// quienes efectivamente cobraron en esa fecha. A qué renglón(es) de
/// `NominaEmpleado` cubre y cuánto es responsabilidad exclusiva de
/// `AplicacionPagoNomina` (mismo modelo N:M aprobado en 4J.2 para
/// `Pago`/`AplicacionPago`, trasplantado a este dominio — nunca
/// compartido entre dominios).
///
/// `egresoId` referencia a `Egreso` (tabla ya existente desde 4K.1) —
/// deliberadamente en esta dirección (la tabla nueva referencia a la
/// vieja) para que `Egreso` no necesite ningún cambio de esquema: un
/// `UNIQUE` agregado por `ALTER TABLE ... ADD COLUMN` no es soportado
/// por SQLite, así que la FK tenía que nacer en la tabla nueva. Un solo
/// `Egreso` por `PagoNomina` — Fiscal/No fiscal nunca genera un segundo
/// Egreso (Resolución explícita de Marlon): el desglose Fiscal/No
/// fiscal ya vive en cada `NominaEmpleado`, aquí solo importa cuánto
/// dinero salió y cuándo.
class PagoNomina extends Table with AuditColumns {
  TextColumn get folioPagoNomina => text().unique()();

  TextColumn get nominaId => text().references(Nomina, #id, onDelete: KeyAction.restrict)();

  TextColumn get egresoId => text().nullable().unique().references(Egreso, #id, onDelete: KeyAction.restrict)();

  /// Suma de sus `AplicacionPagoNomina` activas — mantenido
  /// transaccionalmente, mismo criterio que `Pago.montoTotal`.
  IntColumn get montoTotal => integer()();

  DateTimeColumn get fechaPago => dateTime()();

  TextColumn get formaPago => text()();

  TextColumn get referencia => text().nullable()();

  TextColumn get cuentaBancariaOrigen => text().nullable()();

  TextColumn get observaciones => text().nullable()();

  TextColumn get estatus => text().withDefault(const Constant('registrado'))();

  TextColumn get motivoCancelacion => text().nullable()();

  @override
  List<String> get customConstraints => ['CHECK (monto_total > 0)'];
}

enum EstatusAplicacionPagoNomina { aplicada, cancelada }

/// Cuánto de un `PagoNomina` se aplicó a un renglón de `NominaEmpleado`
/// (Etapa 6D) — la tabla intermedia N:M, misma forma exacta que
/// `AplicacionPago`. El "saldo pendiente de pago" de un renglón nunca
/// se guarda como columna en `NominaEmpleado`: se deriva sumando las
/// `AplicacionPagoNomina` activas de ese renglón — la aplicación es la
/// única fuente de verdad, nunca una columna cacheada que se pueda
/// desincronizar.
///
/// `saldoAntes`/`saldoDespues` son snapshot inmutable del saldo
/// pendiente de pago del renglón en el momento de esta aplicación
/// específica — nunca se recalculan, ni siquiera al cancelarse
/// (cancelar revierte el efecto vivo sobre el renglón, no reescribe
/// este registro histórico). Nunca se elimina una fila, solo
/// `aplicada`/`cancelada`, siempre con historial.
class AplicacionPagoNomina extends Table with AuditColumns {
  TextColumn get pagoNominaId => text().references(PagoNomina, #id, onDelete: KeyAction.restrict)();

  TextColumn get nominaEmpleadoId => text().references(NominaEmpleado, #id, onDelete: KeyAction.restrict)();

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

/// Historial administrativo de un `PagoNomina` (Etapa 6D) — tabla de
/// solo inserción, mismo criterio exacto que `PagoEvento`.
class PagoNominaEvento extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get pagoNominaId => text().references(PagoNomina, #id, onDelete: KeyAction.cascade)();

  DateTimeColumn get fechaHora => dateTime()();

  TextColumn get tipoEvento => text()();

  TextColumn get estadoAnterior => text().nullable()();

  TextColumn get estadoNuevo => text().nullable()();

  TextColumn get observacion => text().nullable()();

  TextColumn get actor => text().nullable()();

  TextColumn get datosRelevantes => text().nullable()();
}
