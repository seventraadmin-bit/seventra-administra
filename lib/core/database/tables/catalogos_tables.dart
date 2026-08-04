import 'package:drift/drift.dart';

import 'catalogo_columns.dart';

/// Catálogos abiertos y editables de RISEG ONE.
///
/// Cada uno es su propia tabla (no un catálogo genérico compartido) para
/// conservar FK reales desde las tablas de negocio que los consumen —
/// decisión ya tomada y confirmada. `MotivoCambio` se deja fuera de esta
/// etapa: no tiene consumidor real hasta que exista `SituacionRecurso`.
class TipoSucursal extends Table with CatalogoColumns {}

class Industria extends Table with CatalogoColumns {}

class TipoServicio extends Table with CatalogoColumns {}

class Area extends Table with CatalogoColumns {}
