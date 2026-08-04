import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';
import '../../../../core/database/tables/catalogos_tables.dart';

/// Estado operativo de una Sucursal — distinto de `cicloVidaRegistro`.
/// Deliberadamente sin valores `activo`/`inactivo`: ese eje ya lo cubre
/// el ciclo de vida técnico; esto solo expresa el hecho de negocio
/// genuinamente distinto de un cierre temporal.
enum EstadoOperativoSucursal { operando, cerradaTemporalmente }

/// Sucursal física de RISEG.
///
/// No tiene columna `ubicacionRaizId`: su nodo raíz de [Ubicacion] se
/// resuelve por consulta (`WHERE sucursal_id = ? AND parent_id IS NULL`),
/// nunca al revés — evita la referencia circular Sucursal↔Ubicación que
/// habría surgido de guardarla en ambos sentidos.
class Sucursal extends Table with AuditColumns {
  TextColumn get codigo => text().unique()();

  TextColumn get nombre => text()();

  TextColumn get tipoSucursalId => text().references(TipoSucursal, #id)();

  // Literal en vez de referencia al enum: ver la nota en
  // `AuditColumns.cicloVidaRegistro` sobre por qué (mismo SQL resultante).
  TextColumn get estadoOperativo => text().withDefault(const Constant('operando'))();
}
