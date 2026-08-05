import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';
import '../../../../core/database/tables/catalogos_tables.dart';
import 'cliente_table.dart';
import 'contacto_table.dart';
import 'entidad_fiscal_table.dart';
import 'sucursal_table.dart';

/// Ciclo comercial de un Servicio — independiente de `cicloVidaRegistro`,
/// mismo razonamiento que [EstatusCliente].
enum EstatusServicio { cotizado, activo, suspendido, terminado }

/// Servicio prestado a un Cliente.
///
/// Sin columnas `direccionId` ni `ubicacionRaizId`: ambas se resuelven
/// por consulta (`Direccion`/`Ubicacion` con `servicio_id` poblado en su
/// fila raíz/principal) — el mismo principio que en `Sucursal`, para no
/// introducir una referencia circular Servicio↔Dirección/Ubicación.
///
/// La creación de un Servicio garantiza transaccionalmente, en una sola
/// transacción de `ServicioRepository`: el propio Servicio y su nodo raíz
/// de Ubicación — desde la Etapa 4F.1, la Dirección operativa es
/// opcional al alta (se captura después desde el expediente, Etapa
/// 4F.2); la Ubicación raíz es solo el ancla estructural del árbol, no
/// depende de que exista una Dirección.
class Servicio extends Table with AuditColumns {
  TextColumn get codigo => text().unique()();

  TextColumn get clienteId =>
      text().references(Cliente, #id, onDelete: KeyAction.restrict)();

  TextColumn get nombre => text()();

  TextColumn get tipoServicioId => text().references(TipoServicio, #id)();

  /// Opcional desde la Etapa 4F.1 — RISEG no tiene hoy varias oficinas
  /// administrativas y no se inventa una Sucursal solo para satisfacer
  /// esta FK. Queda disponible para cuando una empresa (propia o de un
  /// escenario futuro reutilizando este sistema) sí las tenga.
  TextColumn get sucursalAdministrativaId =>
      text().nullable().references(Sucursal, #id, onDelete: KeyAction.restrict)();

  // Literal en vez de referencia al enum: ver la nota en
  // `AuditColumns.cicloVidaRegistro` sobre por qué (mismo SQL resultante).
  TextColumn get estatus => text().withDefault(const Constant('cotizado'))();

  DateTimeColumn get fechaInicio => dateTime()();

  DateTimeColumn get fechaTermino => dateTime().nullable()();

  IntColumn get elementosAutorizados => integer().withDefault(const Constant(0))();

  /// Debe pertenecer al mismo Cliente de este Servicio — no expresable
  /// como `CHECK` (requeriría una subconsulta entre tablas); se valida
  /// en `CrearServicioUseCase`/`ActualizarServicioUseCase` y se cubre
  /// con tests.
  TextColumn get responsableClienteContactoId =>
      text().nullable().references(Contacto, #id, onDelete: KeyAction.restrict)();

  TextColumn get observaciones => text().nullable()();

  /// Opcional — Etapa 4F.2. Debe pertenecer al mismo Cliente de este
  /// Servicio (igual razón que `responsableClienteContactoId`: no
  /// expresable como `CHECK`, se valida en
  /// `AsignarEntidadFiscalAServicioUseCase`). Una Entidad fiscal
  /// archivada después de asignada no se desvincula automáticamente —
  /// el expediente solo muestra una advertencia.
  TextColumn get entidadFiscalId =>
      text().nullable().references(EntidadFiscal, #id, onDelete: KeyAction.restrict)();

  /// Texto libre transitorio — Etapa 4F.2. Personal/Usuario todavía no
  /// existen; cuando existan, este campo migrará a una FK real
  /// conservando el texto histórico de los Servicios ya creados (mismo
  /// criterio ya aplicado a `Empresa.representanteLegal` en la Etapa
  /// 4A). No representa todavía ningún rol específico (supervisor,
  /// coordinador, ejecutivo comercial, etc.) — es deliberadamente
  /// genérico hasta que exista ese dominio.
  TextColumn get responsableInterno => text().nullable()();

  /// Referencia comercial de origen — típicamente un número de
  /// cotización hoy, pero deliberadamente sin acoplarse a ese origen:
  /// puede contener referencias de CRM, propuestas u otras fuentes
  /// futuras. Texto libre, opcional.
  TextColumn get referenciaComercial => text().nullable()();

  TextColumn get referenciaContractual => text().nullable()();

  @override
  List<String> get customConstraints => [
        'CHECK (elementos_autorizados >= 0)',
        'CHECK (fecha_termino IS NULL OR fecha_termino >= fecha_inicio)',
      ];
}
