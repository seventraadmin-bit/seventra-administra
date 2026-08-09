import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';

/// En qué formularios puede aparecer una categoría — `ambos` cubre
/// conceptos que existen en los dos sentidos (ej. "Ajustes varios").
enum TipoCategoriaFinanciera { ingreso, egreso, ambos }

/// Eje informativo para reportes futuros (Etapa 4K.1) — sin ninguna
/// regla de negocio todavía, solo prepara el dato (Resolución de
/// Marlon, explícita: "por ahora no tendrá reglas de negocio").
enum TipoMovimientoCategoriaFinanciera { operativo, administrativo, financiero }

/// Catálogo de categorías financieras (Etapa 4K.1) — a diferencia de
/// `Area`/`TipoServicio` (que usan `CatalogoColumns`, sembrados con IDs
/// fijos, nunca creados desde una pantalla), este catálogo lo
/// administra RISEG desde una pantalla propia, así que usa
/// `AuditColumns` completo (id autogenerado vía `clientDefault`,
/// `cicloVidaRegistro` para archivar en vez de un booleano `activo`
/// redundante). Nace vacío — ninguna categoría se inventa ni se
/// siembra; Marlon no ha confirmado un catálogo real todavía.
class CategoriaFinanciera extends Table with AuditColumns {
  TextColumn get codigo => text().unique()();

  TextColumn get nombre => text()();

  TextColumn get tipo => text()();

  TextColumn get tipoMovimiento => text()();
}
