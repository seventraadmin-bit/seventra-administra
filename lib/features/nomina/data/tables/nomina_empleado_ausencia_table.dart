import 'package:drift/drift.dart';

import '../../../organizacion/data/tables/servicio_table.dart';
import '../../../tiempos_extra/data/tables/tiempo_extra_table.dart';
import 'nomina_empleado_table.dart';

/// Anotación de que el titular de este renglón faltó y su turno se
/// cubrió (Etapa Tiempos Extra, pedido explícito de Marlon: "poner en
/// su nómina... para quien hace los cálculos lo tome en cuenta") —
/// **puramente informativa**, nunca toca `faltas`/`descuentoPorFaltas`/
/// ningún monto de este renglón. Mismo criterio exacto que
/// `NominaEmpleadoTramo`: se borra y reinserta por completo en cada
/// llamada a `NominaRepositoryImpl.guardarRenglon` (tanto desde
/// `generar()` como desde "Actualizar desde Personal"), resolviendo los
/// `TiempoExtra` `registrado` de este Empleado cuya `fecha` cae dentro
/// del periodo de la Nómina — nunca se edita una fila individual, nunca
/// se escribe directo sobre una Nómina ya existente desde fuera de ese
/// mecanismo. Separada a propósito de `NominaEmpleado.observaciones`
/// (que sigue siendo texto libre editado a mano, intacto).
///
/// Si el `TiempoExtra` de origen se cancela mientras esta Nómina sigue
/// en Borrador, la siguiente `guardarRenglon` simplemente deja de
/// traerlo (autocorrección natural, sin borrado especial). Si la Nómina
/// ya cerró/pagó, esta fila queda como historial — igual que el resto
/// de la auditoría del proyecto, append-only.
class NominaEmpleadoAusencia extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get nominaEmpleadoId => text().references(NominaEmpleado, #id, onDelete: KeyAction.cascade)();

  TextColumn get tiempoExtraId => text().references(TiempoExtra, #id, onDelete: KeyAction.restrict)();

  DateTimeColumn get fecha => dateTime()();

  // Literal en vez de referencia al enum — mismo motivo de siempre.
  TextColumn get motivoAusencia => text()();

  TextColumn get servicioId => text().nullable().references(Servicio, #id, onDelete: KeyAction.restrict)();

  /// Nombre y quien cubrió — resueltos una sola vez al derivar esta
  /// fila (`TiempoExtraRepository.listarAusenciasParaNomina`), mismo
  /// criterio exacto que `NominaEmpleadoTramo.servicioNombre`/
  /// `turnoNombre`: para mostrarse sin un join adicional.
  TextColumn get servicioNombre => text()();

  TextColumn get nombreEmpleadoCubrio => text()();
}
