import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';
import '../../../personal/data/tables/empleado_table.dart';
import 'asignacion_table.dart';

/// Solo `crear`/`cancelar` existen en Etapa 7B — `aplicado` queda
/// reservado para una futura integración con Nómina (mismo criterio
/// que `EstatusNomina.pagada`, que vivió en el esquema desde 6C pero
/// solo se activó en 6D).
enum EstatusDescuentoInventario { pendiente, aplicado, cancelado }

/// Reclamo pendiente por daño/pérdida atribuible a un Empleado (Etapa
/// 7B) — estructura mínima para que una etapa futura pueda consultar
/// "quién debe qué, por qué artículo, cuánto, pendiente o no" sin que
/// Inventario se convierta en un módulo de cobranza: aquí solo se
/// registra el reclamo, nunca se cobra ni se descuenta de Nómina.
///
/// Se crea únicamente cuando, al cerrar una `Asignacion` como
/// `danada`/`perdida`, el operador marca "Genera descuento: Sí".
///
/// `empleadoId` es explícito, elegido por el operador al cerrar — no
/// siempre es `Asignacion.empleadoId` (puede ser `null` si el bien
/// estaba asignado a un Servicio, y aun así alguien es responsable).
///
/// Sin folio/`CodigoSecuencia` propio — se consulta siempre en
/// contexto de una Asignación/Empleado, nunca por búsqueda directa
/// (mismo criterio que `AsignacionServicio`, que tampoco tiene folio).
class DescuentoInventario extends Table with AuditColumns {
  TextColumn get asignacionId => text().references(Asignacion, #id, onDelete: KeyAction.restrict)();

  TextColumn get empleadoId => text().references(Empleado, #id, onDelete: KeyAction.restrict)();

  /// Snapshot del motivo de cierre que lo originó (`dano`/`perdida`).
  TextColumn get motivo => text()();

  IntColumn get importe => integer()();

  TextColumn get estatus => text().withDefault(const Constant('pendiente'))();

  /// La escribe una futura integración con Nómina — nunca en 7B.
  DateTimeColumn get fechaAplicacion => dateTime().nullable()();

  TextColumn get observaciones => text().nullable()();

  @override
  List<String> get customConstraints => ['CHECK (importe > 0)'];
}
