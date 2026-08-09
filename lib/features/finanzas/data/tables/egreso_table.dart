import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';
import '../../../../core/database/tables/catalogos_tables.dart';
import '../../../organizacion/data/tables/servicio_table.dart';
import '../../../organizacion/data/tables/sucursal_table.dart';
import 'categoria_financiera_table.dart';

enum EstatusEgreso { registrado, cancelado }

/// Tipos de evento del historial de un Egreso (`EgresoEvento`) — mismo
/// criterio append-only que `IngresoEvento`.
enum TipoEventoEgreso { registrado, corregido, cancelado, comprobanteAdjuntado }

/// Dinero pagado por RISEG (Etapa 4K.1) — 100% captura manual en esta
/// etapa: no existe todavía ninguna fuente automática (Nómina/Compras
/// no están construidos). Mismas tres relaciones opcionales e
/// independientes que `Ingreso` (`servicioId`/`sucursalId`/`areaId`,
/// ver esa tabla para el razonamiento completo).
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

  TextColumn get actor => text().nullable()();

  TextColumn get datosRelevantes => text().nullable()();
}
