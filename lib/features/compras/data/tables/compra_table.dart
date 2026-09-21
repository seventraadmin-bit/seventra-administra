import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';
import '../../../finanzas/data/tables/deuda_table.dart';
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
/// Inventario, un gasto directo, o ambos.
///
/// `egresoId` referencia a `Egreso` (tabla ya existente desde 4K.1) —
/// deliberadamente en esta dirección (mismo criterio que
/// `PagoNomina.egresoId`, Etapa 6D): SQLite no soporta agregar una
/// restricción `UNIQUE` a una tabla ya existente vía `ALTER TABLE`, así
/// que la FK nace en la tabla nueva y `Egreso` no sufre ningún cambio
/// de esquema.
///
/// **Etapa 19B**: cuando `formaPago == tarjeta`, la Compra ya NO genera
/// `Egreso` (`egresoId` queda `null`) — en su lugar puebla `deudaId` y
/// genera un `MovimientoDeuda` de tipo `cargoCompra`. El gasto
/// operativo se reconoce una sola vez, en el momento de la compra, vía
/// `ResumenFinancieroState.egresosOperativos`; el pago posterior de la
/// tarjeta (`DeudaRepository.registrarPago`) sigue generando su propio
/// Egreso real (la salida de caja), pero queda excluido de
/// `egresosOperativos` — así nunca se cuenta dos veces. `egresoId` y
/// `deudaId` son mutuamente excluyentes: toda Compra puebla exactamente
/// uno de los dos, nunca ambos ni ninguno.
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

  // --- LEGACY (Etapa 10, retirado en la Etapa 15 al estructurar el
  // motivo de cancelación) — texto libre capturado directamente aquí.
  // Reemplazado por `motivoCancelacionCodigo`/`motivoCancelacionDetalle`/
  // `motivoCancelacionObservaciones`. Se conserva en BD por
  // compatibilidad con Compras ya canceladas antes de este cambio —
  // ningún flujo nuevo la lee ni la escribe (la UI cae de vuelta a
  // esta columna solo cuando `motivoCancelacionCodigo` es nulo, para no
  // perder el texto de cancelaciones históricas).
  TextColumn get motivoCancelacion => text().nullable()();

  /// Nombre estable del enum `MotivoCancelacionCompra` (Etapa 15) —
  /// nunca la etiqueta traducida que ve el usuario, para que un cambio
  /// de texto en la UI no reescriba el histórico ni rompa reportes.
  TextColumn get motivoCancelacionCodigo => text().nullable()();

  /// Obligatorio cuando `motivoCancelacionCodigo == 'otro'` — validado
  /// en `CancelarCompraUseCase`, no aquí.
  TextColumn get motivoCancelacionDetalle => text().nullable()();

  /// Siempre opcional, sin importar el motivo elegido.
  TextColumn get motivoCancelacionObservaciones => text().nullable()();

  TextColumn get egresoId => text().nullable().unique().references(Egreso, #id, onDelete: KeyAction.restrict)();

  /// Etapa 19B — poblado únicamente cuando `formaPago == tarjeta`.
  /// `restrict`: no se puede borrar la tarjeta mientras exista una
  /// Compra financiada por ella (misma dirección que `egresoId`, por la
  /// misma razón: `Deuda` no puede agregar `UNIQUE` a una relación
  /// 1-a-muchos vía `ALTER TABLE`, y aquí ni siquiera aplica — una
  /// tarjeta financia muchas Compras).
  TextColumn get deudaId => text().nullable().references(Deuda, #id, onDelete: KeyAction.restrict)();
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
