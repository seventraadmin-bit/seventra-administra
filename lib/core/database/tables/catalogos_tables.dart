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

/// Modalidad de turno de una vigencia de Configuración comercial (Etapa
/// 4G.1) — 24×24, 12×12, Nocturno, etc. Catálogo abierto (no un enum
/// Dart) deliberadamente: RISEG puede necesitar agregar una modalidad
/// nueva sin requerir una actualización de la aplicación.
class TipoModalidadTurno extends Table with CatalogoColumns {}

/// Frecuencia de una vigencia de Configuración de cobro (Etapa 4H.1) —
/// sembrado solo con "Mensual" por ahora, el único valor que los casos
/// reales conocidos confirman. Catálogo abierto, mismo motivo que
/// [TipoModalidadTurno].
class TipoFrecuenciaCobro extends Table with CatalogoColumns {}

/// Banco de los datos bancarios de un Empleado (Etapa 6A) — catálogo
/// simple y cerrado (sin pantalla de administración en esta etapa,
/// Resolución explícita de Marlon), reutilizable a futuro por
/// Finanzas si algún día formaliza `Pago.cuentaBancariaDestino`/
/// `Ingreso.cuentaCaja`/`Egreso.cuentaCaja` (hoy texto libre, sin
/// tocarse en esta etapa). Catálogo abierto, mismo motivo que
/// [TipoModalidadTurno] — RISEG puede necesitar agregar un banco sin
/// una actualización de la aplicación.
class Banco extends Table with CatalogoColumns {}
