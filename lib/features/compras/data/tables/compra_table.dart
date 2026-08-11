import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';
import '../../../finanzas/data/tables/egreso_table.dart';
import '../../../usuarios/data/tables/usuario_table.dart';

enum EstatusCompra { registrada, cancelada }

/// Tipos de evento del historial de una `Compra` — mismo criterio
/// append-only que `EgresoEvento`/`PagoNominaEvento`.
enum TipoEventoCompra { registrada, corregida, cancelada, comprobanteAdjuntado }

/// Una compra de contado ya realizada y ya pagada (Etapa 10) — RISEG no
/// maneja crédito con proveedores, así que registrar una `Compra` aquí
/// es registrar un hecho ya consumado, nunca una orden pendiente. Sus
/// `CompraPartida` (ver esa tabla) determinan si generó entrada(s) de
/// Inventario, un gasto directo, o ambos — pero siempre genera
/// exactamente un `Egreso` por el total combinado.
///
/// `egresoId` referencia a `Egreso` (tabla ya existente desde 4K.1) —
/// deliberadamente en esta dirección (mismo criterio que
/// `PagoNomina.egresoId`, Etapa 6D): SQLite no soporta agregar una
/// restricción `UNIQUE` a una tabla ya existente vía `ALTER TABLE`, así
/// que la FK nace en la tabla nueva y `Egreso` no sufre ningún cambio
/// de esquema.
///
/// Sin columna `total`: se deriva siempre como
/// `SUM(cantidad × costo_unitario)` sobre `CompraPartida` — nunca se
/// guarda un total aparte que se pueda desincronizar (mismo criterio
/// que `MovimientoInventario` nunca guarda costo total). Sin riesgo de
/// desincronización: una `Compra` `registrada` nunca vuelve a aceptar
/// cambios de cantidad/costo en sus partidas (ver
/// `CompraRepositoryImpl`, no existe ningún método `corregirPartida`).
///
/// `estatus` es columna propia, no `cicloVidaRegistro` — mismo criterio
/// que `Egreso`/`PagoNomina`/`Vehiculo`/`Asignacion`: un ciclo de vida
/// de negocio real (aquí, cancelable con reversión estructurada) usa su
/// propia columna; `cicloVidaRegistro` es solo para catálogos puros
/// "existe/no existe".
class Compra extends Table with AuditColumns {
  TextColumn get folioCompra => text().unique()();

  DateTimeColumn get fecha => dateTime()();

  /// Texto libre — sin catálogo de proveedores (Resolución explícita de
  /// Marlon: "no obligues a crear primero una ficha de proveedor"),
  /// mismo criterio que `Egreso.beneficiario`.
  TextColumn get proveedor => text().nullable()();

  /// Literal — reutiliza el enum `FormaPago` ya existente en
  /// `pago_table.dart` (efectivo/transferencia/cheque/tarjeta/otro),
  /// nunca uno nuevo.
  TextColumn get formaPago => text()();

  /// Solo aplica cuando `formaPago == otro`.
  TextColumn get formaPagoOtroDescripcion => text().nullable()();

  TextColumn get observaciones => text().nullable()();

  TextColumn get estatus => text().withDefault(const Constant('registrada'))();

  TextColumn get motivoCancelacion => text().nullable()();

  TextColumn get egresoId => text().nullable().unique().references(Egreso, #id, onDelete: KeyAction.restrict)();
}

/// Historial administrativo de una `Compra` (Etapa 10) — tabla de solo
/// inserción, mismo criterio exacto que `EgresoEvento`/`PagoNominaEvento`.
class CompraEvento extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get compraId => text().references(Compra, #id, onDelete: KeyAction.cascade)();

  DateTimeColumn get fechaHora => dateTime()();

  TextColumn get tipoEvento => text()();

  TextColumn get estadoAnterior => text().nullable()();

  TextColumn get estadoNuevo => text().nullable()();

  TextColumn get observacion => text().nullable()();

  /// **Legacy (Etapa 11D)** — nunca se pobló con un valor real; se
  /// conserva la columna físicamente por seguridad de migración pero
  /// ningún código desde 11D en adelante la lee ni la escribe. La única
  /// fuente funcional de "quién" es `actorUsuarioId`.
  TextColumn get actor => text().nullable()();

  TextColumn get actorUsuarioId => text().nullable().references(Usuario, #id, onDelete: KeyAction.setNull)();

  TextColumn get datosRelevantes => text().nullable()();
}
