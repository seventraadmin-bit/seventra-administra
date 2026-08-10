import 'package:drift/drift.dart';

import '../../../organizacion/data/tables/servicio_table.dart';
import 'nomina_empleado_table.dart';

/// El desglose de tramos de un `NominaEmpleado` (Etapa 6C) — normalmente
/// una sola fila; más de una cuando hay un cambio de Servicio/sueldo o
/// un hueco laboral (alta/baja/reingreso) dentro del mismo periodo. Ver
/// `calcularDiasPagablesEmpleado` para el algoritmo completo.
///
/// Guarda rangos de fecha reales y el `importeTramo` ya calculado —
/// deliberadamente **no** un "equivalente de días" artificial por
/// tramo: sumar los `diasReales` de todos los tramos de una Nómina con
/// cobertura laboral completa daría más de 15 en una segunda quincena
/// de 31 días, lo cual sería engañoso frente a `NominaEmpleado.
/// diasPagables` (que siempre vale 15 en ese caso). `diasReales` de
/// cada tramo es informativo (para mostrar el desglose), nunca se sube
/// a sumar contra `diasPagables`.
///
/// Tabla de solo inserción — se recrea por completo cada vez que
/// `GenerarNominaUseCase`/`ActualizarNominaDesdePersonalUseCase` corren
/// (mismo criterio que cualquier tabla de detalle regenerable de este
/// proyecto), nunca se edita una fila individual.
class NominaEmpleadoTramo extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get nominaEmpleadoId => text().references(NominaEmpleado, #id, onDelete: KeyAction.cascade)();

  DateTimeColumn get fechaInicio => dateTime()();

  DateTimeColumn get fechaFin => dateTime()();

  TextColumn get servicioId => text().nullable().references(Servicio, #id, onDelete: KeyAction.restrict)();

  TextColumn get servicioNombre => text().nullable()();

  TextColumn get turnoNombre => text().nullable()();

  // Literal en vez de referencia al enum — mismo motivo de siempre.
  TextColumn get fuenteSueldo => text()();

  IntColumn get sueldoMensual => integer()();

  IntColumn get bonoMensual => integer()();

  IntColumn get diasReales => integer()();

  IntColumn get importeTramo => integer()();

  @override
  List<String> get customConstraints => [
        'CHECK (fecha_fin >= fecha_inicio)',
        'CHECK (dias_reales > 0)',
        'CHECK (sueldo_mensual > 0)',
        'CHECK (bono_mensual >= 0)',
        'CHECK (importe_tramo >= 0)',
      ];
}
