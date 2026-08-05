import 'package:drift/drift.dart';

import 'audit_columns.dart';

/// Tipo de una [Direccion] — determina qué dueño puede usarla (ver los
/// `CHECK` de la tabla) y, para Cliente, permite varias por tipo distinto.
enum TipoDireccion { fiscal, administrativa, operativa, entrega, otra, referencia }

/// Dirección física, compartida por Empresa, Sucursal, Cliente, Servicio
/// y (desde la Etapa 4E.2) Entidad fiscal.
///
/// En vez de una tabla polimórfica (`ownerType`/`ownerId`, sin FK real),
/// cada posible dueño tiene su propia columna nullable con una FK real —
/// el "arco exclusivo": exactamente una debe estar poblada (ver
/// `customConstraints`). Nunca es realmente muchos-a-muchos (una
/// dirección no se comparte entre dos clientes), así que esto da
/// integridad referencial real sin necesitar una tabla puente por cada
/// combinación dueño×valor-compartido.
///
/// Las FK hacia `empresa`/`sucursal`/`cliente`/`servicio` se declaran como
/// SQL crudo en `customConstraints` (no con `.references()` tipado) a
/// propósito: esas tablas viven en `features/organizacion`, y esta tabla
/// vive en `core` — importar las clases de tabla de una feature desde
/// `core` invertiría la dirección de dependencia de la arquitectura. El
/// SQL generado es exactamente el mismo; solo cambia si Dart conoce el
/// tipo en tiempo de compilación.
///
/// `empresaId`/`sucursalId`/`servicioId`/`entidadFiscalId` usan
/// `.unique()` a pesar de ser nulables: SQLite trata cada NULL como
/// distinto de cualquier otro para efectos de un índice único, así que
/// `.unique()` en una columna nulable ya equivale a "único entre los
/// valores no nulos" — no hace falta un índice parcial con
/// `WHERE ... IS NOT NULL` a mano para estos cuatro. `clienteId` no
/// lleva `.unique()` (1:N) — su única/parcial real es la de "una
/// principal por tipo", que sí necesita un índice explícito porque no
/// es una distinción de nulabilidad sino de `esPrincipal`.
@TableIndex.sql(
  'CREATE UNIQUE INDEX idx_direccion_cliente_tipo_principal '
  'ON direccion (cliente_id, tipo_direccion) '
  'WHERE es_principal = 1 AND cliente_id IS NOT NULL',
)
@TableIndex.sql('CREATE INDEX idx_direccion_cliente ON direccion (cliente_id)')
class Direccion extends Table with AuditColumns {
  TextColumn get empresaId => text().nullable().unique()();

  TextColumn get sucursalId => text().nullable().unique()();

  TextColumn get clienteId => text().nullable()();

  TextColumn get servicioId => text().nullable().unique()();

  TextColumn get entidadFiscalId => text().nullable().unique()();

  TextColumn get tipoDireccion => text()();

  BoolColumn get esPrincipal => boolean().withDefault(const Constant(true))();

  TextColumn get calle => text()();

  TextColumn get numeroExterior => text()();

  TextColumn get numeroInterior => text().nullable()();

  TextColumn get colonia => text()();

  TextColumn get municipioAlcaldia => text()();

  TextColumn get ciudadLocalidad => text().nullable()();

  TextColumn get estado => text()();

  TextColumn get codigoPostal => text()();

  TextColumn get pais => text().withDefault(const Constant('México'))();

  TextColumn get referencias => text().nullable()();

  @override
  List<String> get customConstraints => [
        'FOREIGN KEY (empresa_id) REFERENCES empresa (id) ON DELETE RESTRICT',
        'FOREIGN KEY (sucursal_id) REFERENCES sucursal (id) ON DELETE RESTRICT',
        'FOREIGN KEY (cliente_id) REFERENCES cliente (id) ON DELETE RESTRICT',
        'FOREIGN KEY (servicio_id) REFERENCES servicio (id) ON DELETE RESTRICT',
        'FOREIGN KEY (entidad_fiscal_id) REFERENCES entidad_fiscal (id) ON DELETE RESTRICT',
        // Arco exclusivo: exactamente un dueño por fila.
        'CHECK ('
            '(CASE WHEN empresa_id IS NOT NULL THEN 1 ELSE 0 END + '
            'CASE WHEN sucursal_id IS NOT NULL THEN 1 ELSE 0 END + '
            'CASE WHEN cliente_id IS NOT NULL THEN 1 ELSE 0 END + '
            'CASE WHEN servicio_id IS NOT NULL THEN 1 ELSE 0 END + '
            'CASE WHEN entidad_fiscal_id IS NOT NULL THEN 1 ELSE 0 END) = 1'
            ')',
        // Reglas de tipo por dueño, ya acordadas.
        "CHECK (empresa_id IS NULL OR tipo_direccion = 'fiscal')",
        "CHECK (servicio_id IS NULL OR tipo_direccion = 'operativa')",
        "CHECK (sucursal_id IS NULL OR tipo_direccion IN ('administrativa', 'operativa'))",
        "CHECK (entidad_fiscal_id IS NULL OR tipo_direccion = 'fiscal')",
      ];
}
