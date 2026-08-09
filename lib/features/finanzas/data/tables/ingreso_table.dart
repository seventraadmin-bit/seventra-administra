import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';
import '../../../../core/database/tables/catalogos_tables.dart';
import '../../../organizacion/data/tables/servicio_table.dart';
import '../../../organizacion/data/tables/sucursal_table.dart';
import 'categoria_financiera_table.dart';
import 'pago_table.dart';

enum EstatusIngreso { registrado, cancelado }

/// Tipos de evento del historial de un Ingreso (`IngresoEvento`) —
/// mismo criterio append-only que `PagoEvento`/`ComplementoPagoEvento`.
enum TipoEventoIngreso { registrado, corregido, cancelado, comprobanteAdjuntado }

/// Dinero reconocido como ingreso de RISEG (Etapa 4K.1) — automático
/// cuando proviene de un `Pago` ya recibido (`pagoId` único, 1:1,
/// mismo criterio que `ComplementoPago`), o manual cuando no pasa por
/// ninguna Cuenta por cobrar.
///
/// `servicioId`/`sucursalId`/`areaId` son tres relaciones **opcionales
/// e independientes** (Resolución de Marlon, explícita: "no quiero
/// crear un catálogo independiente de CentroCosto en esta etapa" — el
/// análisis financiero real de RISEG gira alrededor del Servicio, no
/// de un centro de costo abstracto). Ninguna es excluyente de las
/// otras — a diferencia del arco de `Attachment`, aquí pueden
/// coexistir las tres, una, o ninguna.
class Ingreso extends Table with AuditColumns {
  TextColumn get pagoId => text().nullable().unique().references(Pago, #id, onDelete: KeyAction.restrict)();

  TextColumn get folioIngreso => text().unique()();

  IntColumn get monto => integer()();

  DateTimeColumn get fecha => dateTime()();

  TextColumn get categoriaFinancieraId =>
      text().nullable().references(CategoriaFinanciera, #id, onDelete: KeyAction.restrict)();

  TextColumn get servicioId => text().nullable().references(Servicio, #id, onDelete: KeyAction.restrict)();

  TextColumn get sucursalId => text().nullable().references(Sucursal, #id, onDelete: KeyAction.restrict)();

  TextColumn get areaId => text().nullable().references(Area, #id, onDelete: KeyAction.restrict)();

  /// Texto libre — mismo criterio que `Pago.cuentaBancariaDestino`, sin
  /// catálogo de Bancos todavía.
  TextColumn get cuentaCaja => text().nullable()();

  /// Reutiliza el enum `FormaPago` de `Pago` (Etapa 4J.2) — nunca un
  /// enum paralelo para el mismo concepto.
  TextColumn get formaPago => text()();

  TextColumn get concepto => text()();

  TextColumn get observaciones => text().nullable()();

  TextColumn get estatus => text().withDefault(const Constant('registrado'))();

  TextColumn get motivoCancelacion => text().nullable()();

  @override
  List<String> get customConstraints => ['CHECK (monto > 0)'];
}

/// Historial administrativo de un Ingreso (Etapa 4K.1) — tabla de solo
/// inserción, mismo criterio exacto que `PagoEvento`.
class IngresoEvento extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get ingresoId => text().references(Ingreso, #id, onDelete: KeyAction.cascade)();

  DateTimeColumn get fechaHora => dateTime()();

  TextColumn get tipoEvento => text()();

  TextColumn get estadoAnterior => text().nullable()();

  TextColumn get estadoNuevo => text().nullable()();

  TextColumn get observacion => text().nullable()();

  TextColumn get actor => text().nullable()();

  TextColumn get datosRelevantes => text().nullable()();
}
