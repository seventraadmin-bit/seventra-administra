import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';
import '../../../../core/database/tables/catalogos_tables.dart';
import '../../../organizacion/data/tables/servicio_table.dart';
import '../../../organizacion/data/tables/sucursal_table.dart';
import '../../../usuarios/data/tables/usuario_table.dart';
import 'categoria_financiera_table.dart';
import 'cuenta_financiera_table.dart';
import 'deuda_table.dart';

enum EstatusEgreso { registrado, cancelado }

/// Tipos de evento del historial de un Egreso (`EgresoEvento`) — mismo
/// criterio append-only que `IngresoEvento`.
enum TipoEventoEgreso { registrado, corregido, cancelado, comprobanteAdjuntado }

/// Dinero pagado por RISEG (Etapa 4K.1) — nace 100% manual en esta
/// etapa; desde entonces Nómina (Etapa 6D) y Compras (Etapa 10) generan
/// su propio Egreso automático (`PagoNomina.egresoId`/`Compra.egresoId`,
/// ambos FK únicas hacia esta tabla). QUÉ MÓDULO originó un Egreso
/// sigue sin columna propia — se deriva por esa FK inversa
/// (`ClasificarEgresosPorOrigenUseCase`, Etapa 17), nunca almacenado.
/// Mismas tres relaciones opcionales e independientes que `Ingreso`
/// (`servicioId`/`sucursalId`/`areaId`, ver esa tabla para el
/// razonamiento completo).
///
/// Etapa "Origen financiero de Egresos manuales: Cuenta vs. TDC"
/// (schemaVersion 76) — distinto de lo anterior: CÓMO se financió el
/// gasto sí vive aquí, en el par mutuamente excluyente
/// [cuentaFinancieraId]/[deudaId]. Un Egreso manual es a la vez el
/// DOCUMENTO del gasto (concepto, categoría, servicio, comprobante) y
/// —solo cuando lo financia una cuenta— el movimiento de caja; cuando
/// lo financia una TDC sigue siendo el documento del gasto pero no
/// mueve caja: el peso sale después, al pagar la tarjeta
/// (`RegistrarPagoDeudaUseCase`). Por eso no hizo falta una entidad
/// `GastoManual` separada — ver el doc comment de [deudaId].
class Egreso extends Table with AuditColumns {
  TextColumn get folioEgreso => text().unique()();

  IntColumn get monto => integer()();

  DateTimeColumn get fecha => dateTime()();

  TextColumn get categoriaFinancieraId =>
      text().nullable().references(CategoriaFinanciera, #id, onDelete: KeyAction.restrict)();

  TextColumn get servicioId => text().nullable().references(Servicio, #id, onDelete: KeyAction.restrict)();

  TextColumn get sucursalId => text().nullable().references(Sucursal, #id, onDelete: KeyAction.restrict)();

  TextColumn get areaId => text().nullable().references(Area, #id, onDelete: KeyAction.restrict)();

  TextColumn get cuentaCaja => text().nullable()();

  /// Etapa 19C — vínculo real y determinista a la `CuentaFinanciera`
  /// de la que salió el dinero (nunca inferido de `cuentaCaja`, que
  /// sigue siendo texto libre sin tocar). Nullable: todo Egreso
  /// histórico anterior a esta etapa queda "Cuenta no especificada" —
  /// nunca se adivina ni se hace backfill heurístico.
  ///
  /// Etapa "Origen financiero de Egresos manuales: Cuenta vs. TDC"
  /// (schemaVersion 76) — mutuamente excluyente con [deudaId]: un gasto
  /// se financia desde una cuenta (sale efectivo) O se carga a una
  /// tarjeta (no sale efectivo todavía), nunca ambas. `null` en las dos
  /// sigue significando "sin especificar" — el estado de todo Egreso
  /// histórico, nunca un tercer caso nuevo.
  ///
  /// **LEGACY desde schemaVersion 91.** La verdad sobre de qué
  /// cuenta(s) salió el dinero vive ahora en `EgresoFuente`, y
  /// `calcularSaldosCanonico` lee **sólo** esa tabla: esta columna no
  /// participa en ningún cálculo de saldo. Se conserva, y el
  /// repositorio la sigue escribiendo, por sus consumidores actuales
  /// —el diff de corrección de Compras y el nombre de cuenta que
  /// muestra el detalle de un Descuento programado—, que sólo la usan
  /// para **mostrar** información.
  ///
  /// Con varias fuentes queda `null`, porque ninguna cuenta sola
  /// representa al Egreso; eso delata a cualquiera que intente volver
  /// a tratarla como la verdad. **Ningún cálculo nuevo debe decidir la
  /// cuenta desde aquí**: para eso está `EgresoFuente`.
  TextColumn get cuentaFinancieraId =>
      text().nullable().references(CuentaFinanciera, #id, onDelete: KeyAction.restrict)();

  /// Etapa "Origen financiero de Egresos manuales: Cuenta vs. TDC"
  /// (schemaVersion 76) — la tarjeta de crédito que financió este
  /// gasto, cuando NO salió dinero de ninguna `CuentaFinanciera`.
  /// Mutuamente excluyente con [cuentaFinancieraId]; la invariante la
  /// garantiza la ruta de escritura (`EgresoRepository.crear`/
  /// `corregir`), nunca un `CHECK` de esquema — agregarlo a una tabla
  /// existente exigiría recrearla, mismo criterio que la unicidad de
  /// `TiempoExtraCostoAdicional.egresoId`.
  ///
  /// Poblarlo tiene dos efectos inseparables, ambos en la misma
  /// transacción que escribe esta columna: (1) un `MovimientoDeuda`
  /// tipo `cargoCompra` vinculado por `egresoGastoId` aumenta el saldo
  /// de esa Deuda — mismo mecanismo exacto que ya usan `Compra.deudaId`
  /// y `TiempoExtra.deudaId`; (2) este Egreso deja de contar como
  /// salida de efectivo (`EgresoRepository.totalEgresos` lo excluye),
  /// porque su gasto operativo se reconoce por la vía del cargo
  /// (`ResumenFinancieroState.cargosTarjetaPeriodo`) — contarlo por las
  /// dos vías sería doble conteo exacto del mismo peso.
  ///
  /// A diferencia de `Compra`/`TiempoExtra` — donde la fila fuente es
  /// el documento del gasto y su `Egreso` es desechable (se cancela y
  /// se recrea al cambiar de origen) — aquí el `Egreso` ES el documento
  /// del gasto: una transición Cuenta↔TDC nunca lo cancela ni crea uno
  /// nuevo, solo intercambia estas dos columnas conservando id, folio,
  /// historial y comprobantes adjuntos.
  TextColumn get deudaId => text().nullable().references(Deuda, #id, onDelete: KeyAction.restrict)();

  TextColumn get formaPago => text()();

  /// Texto libre — sin catálogo de Proveedores todavía, mismo criterio
  /// que `cuentaCaja`.
  TextColumn get beneficiario => text().nullable()();

  TextColumn get concepto => text()();

  TextColumn get observaciones => text().nullable()();

  TextColumn get estatus => text().withDefault(const Constant('registrado'))();

  TextColumn get motivoCancelacion => text().nullable()();

  @override
  List<String> get customConstraints => ['CHECK (monto > 0)'];
}

/// Historial administrativo de un Egreso (Etapa 4K.1) — tabla de solo
/// inserción, mismo criterio exacto que `IngresoEvento`.
class EgresoEvento extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get egresoId => text().references(Egreso, #id, onDelete: KeyAction.cascade)();

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
