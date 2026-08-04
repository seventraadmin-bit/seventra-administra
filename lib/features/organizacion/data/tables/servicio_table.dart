import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';
import '../../../../core/database/tables/catalogos_tables.dart';
import 'cliente_table.dart';
import 'contacto_table.dart';
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
/// transacción de `ServicioRepository`: el propio Servicio, su Dirección
/// operativa principal y su nodo raíz de Ubicación — no existe un estado
/// "borrador sin dirección"; la dirección operativa es obligatoria desde
/// el alta (no hay todavía UI que justifique diferirla).
class Servicio extends Table with AuditColumns {
  TextColumn get codigo => text().unique()();

  TextColumn get clienteId =>
      text().references(Cliente, #id, onDelete: KeyAction.restrict)();

  TextColumn get nombre => text()();

  TextColumn get tipoServicioId => text().references(TipoServicio, #id)();

  TextColumn get sucursalAdministrativaId =>
      text().references(Sucursal, #id, onDelete: KeyAction.restrict)();

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

  @override
  List<String> get customConstraints => [
        'CHECK (elementos_autorizados >= 0)',
        'CHECK (fecha_termino IS NULL OR fecha_termino >= fecha_inicio)',
      ];
}
