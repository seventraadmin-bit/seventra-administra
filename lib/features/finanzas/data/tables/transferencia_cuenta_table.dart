import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';
import '../../../usuarios/data/tables/usuario_table.dart';
import 'cuenta_financiera_table.dart';

enum EstatusTransferenciaCuenta { registrada, cancelada }

/// Tipos de evento del historial de una Transferencia — mismo criterio
/// append-only que `EgresoEvento`/`IngresoEvento`.
enum TipoEventoTransferenciaCuenta { creada, corregida, cancelada }

/// Movimiento interno de dinero entre dos cuentas propias
/// (schemaVersion 91).
///
/// **No es un Ingreso ni un Egreso, y deliberadamente no los crea.**
/// Representarla como un par Egreso+Ingreso habría inflado "Ingresos" y
/// "Egresos" del Resumen financiero y contaminado el resultado
/// operativo con dinero que nunca entró ni salió de la empresa: sólo
/// cambió de bolsillo. Por eso es una entidad propia y por eso
/// `calcularSaldos` la suma aparte.
///
/// Efecto, y ninguno más:
///
/// ```
/// cuenta origen   −= importe
/// cuenta destino  += importe
/// Caja y bancos   sin cambio
/// Resultado operativo, Ingresos, Gasto operativo: sin cambio
/// ```
///
/// **Una sola entidad lógica, nunca dos movimientos sueltos**: sale de
/// A y entra a B, o no ocurre nada. La atomicidad la da la transacción
/// del repositorio; que aquí haya una sola fila es lo que impide que
/// los dos lados queden desparejados.
class TransferenciaCuenta extends Table with AuditColumns {
  TextColumn get folioTransferencia => text().unique()();

  TextColumn get cuentaOrigenId =>
      text().references(CuentaFinanciera, #id, onDelete: KeyAction.restrict)();

  TextColumn get cuentaDestinoId =>
      text().references(CuentaFinanciera, #id, onDelete: KeyAction.restrict)();

  /// Centavos, siempre `> 0`.
  IntColumn get importe => integer()();

  DateTimeColumn get fecha => dateTime()();

  TextColumn get concepto => text().nullable()();

  TextColumn get observaciones => text().nullable()();

  TextColumn get estatus => text().withDefault(const Constant('registrada'))();

  TextColumn get motivoCancelacion => text().nullable()();

  @override
  List<String> get customConstraints => [
        'CHECK (importe > 0)',
        // Transferirse a sí misma no movería nada y sólo ensuciaría el
        // historial; se bloquea en dominio y también aquí.
        'CHECK (cuenta_origen_id <> cuenta_destino_id)',
      ];
}

/// Historial administrativo de una Transferencia — mismo patrón que los
/// otros 15 historiales del proyecto.
class TransferenciaCuentaEvento extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get transferenciaCuentaId =>
      text().references(TransferenciaCuenta, #id, onDelete: KeyAction.cascade)();

  DateTimeColumn get fechaHora => dateTime().withDefault(currentDateAndTime)();

  TextColumn get tipoEvento => text()();

  TextColumn get estadoAnterior => text().nullable()();

  TextColumn get estadoNuevo => text().nullable()();

  TextColumn get observacion => text().nullable()();

  /// JSON con el antes/después de una corrección — mismo `DiffEvento`
  /// que `EgresoEvento`.
  TextColumn get datosRelevantes => text().nullable()();

  TextColumn get actorUsuarioId =>
      text().nullable().references(Usuario, #id, onDelete: KeyAction.setNull)();
}
