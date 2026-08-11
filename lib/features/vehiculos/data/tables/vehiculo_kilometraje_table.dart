import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';
import '../../../usuarios/data/tables/usuario_table.dart';
import 'vehiculo_table.dart';

/// Origen/motivo de una lectura de kilometraje (Etapa 8B) — catálogo
/// mínimo pedido explícitamente por Marlon, sin ubicación/GPS.
/// `entrega`/`devolucion` se generan automáticamente al capturar
/// kilometraje opcional en `AsignarVehiculoUseCase`/
/// `RetirarAsignacionVehiculoUseCase` — nunca los captura el usuario
/// desde una pantalla de "kilometraje" suelta.
enum OrigenKilometrajeVehiculo { lecturaManual, entrega, devolucion, mantenimiento, correccion }

/// Ledger append-only de kilometraje (Etapa 8B) — misma filosofía
/// exacta que `MovimientoInventario` (Inventario, 7A): una sola fuente
/// de verdad, nunca un total guardado en paralelo.
/// `Vehiculo.kilometrajeActual` no existe como columna — el
/// "kilometraje actual" siempre se deriva como el `kilometraje` de la
/// fila con `fecha` más reciente (ver
/// `VehiculoKilometrajeRepository.obtenerActual`).
///
/// "Nunca permitir que el kilometraje disminuya silenciosamente. Si
/// existe una corrección, debe quedar registrada" (instrucción
/// explícita de Marlon) — regla de dominio, no de `CHECK`: se aplica en
/// `RegistrarKilometrajeVehiculoUseCase`, mismo criterio que
/// `RegistrarAjusteUseCase` (Inventario) exige `observaciones` para
/// cualquier ajuste manual de existencia. Una corrección (`origen =
/// correccion`) puede subir o bajar el valor, pero siempre exige
/// `observaciones` no vacías — el `CHECK` de esta tabla solo protege lo
/// que es universalmente cierto (`kilometraje >= 0`), nunca la
/// comparación contra la lectura anterior (eso requiere leer otra
/// fila, imposible desde un `CHECK`).
///
/// Usa `AuditColumns` igual que `MovimientoInventario` — `updatedAt`/
/// `cicloVidaRegistro` quedan inertes (nunca se edita ni se archiva una
/// lectura), mismo criterio ya aceptado ahí: una fila nueva siempre
/// gana a corregir una existente.
class VehiculoKilometraje extends Table with AuditColumns {
  TextColumn get vehiculoId => text().references(Vehiculo, #id, onDelete: KeyAction.restrict)();

  DateTimeColumn get fecha => dateTime()();

  IntColumn get kilometraje => integer()();

  TextColumn get origen => text()();

  TextColumn get observaciones => text().nullable()();

  /// **Legacy (Etapa 11D)** — nunca se pobló con un valor real; se
  /// conserva la columna físicamente por seguridad de migración pero
  /// ningún código desde 11D en adelante la lee ni la escribe. La única
  /// fuente funcional de "quién" es `actorUsuarioId`.
  TextColumn get actor => text().nullable()();

  TextColumn get actorUsuarioId => text().nullable().references(Usuario, #id, onDelete: KeyAction.setNull)();

  @override
  List<String> get customConstraints => ['CHECK (kilometraje >= 0)'];
}
