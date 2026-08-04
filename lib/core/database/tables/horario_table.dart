import 'package:drift/drift.dart';

import 'audit_columns.dart';

/// Horario relacional de una Sucursal o Servicio — nunca un JSON libre.
///
/// Una fila "cabecera" por dueño (arco exclusivo, igual que [Direccion]);
/// el detalle día por día vive en [HorarioDetalle]. Consultable y
/// filtrable por SQL directamente (ej. "qué sucursales operan ahora"),
/// algo que un blob JSON no permite sin deserializar todo.
class Horario extends Table with AuditColumns {
  TextColumn get sucursalId => text().nullable().unique()();

  TextColumn get servicioId => text().nullable().unique()();

  @override
  List<String> get customConstraints => [
        'FOREIGN KEY (sucursal_id) REFERENCES sucursal (id) ON DELETE RESTRICT',
        'FOREIGN KEY (servicio_id) REFERENCES servicio (id) ON DELETE RESTRICT',
        'CHECK ('
            '(CASE WHEN sucursal_id IS NOT NULL THEN 1 ELSE 0 END + '
            'CASE WHEN servicio_id IS NOT NULL THEN 1 ELSE 0 END) = 1'
            ')',
      ];
}

/// Un bloque horario de un día de la semana dentro de un [Horario].
///
/// `horaInicio`/`horaFin` se guardan como minutos desde medianoche
/// (0-1439) — comparable y ordenable directamente en SQL, sin ambigüedad
/// de formato ni zona horaria.
class HorarioDetalle extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get horarioId =>
      text().references(Horario, #id, onDelete: KeyAction.cascade)();

  /// 0 = lunes ... 6 = domingo.
  IntColumn get diaSemana => integer()();

  IntColumn get horaInicio => integer()();

  IntColumn get horaFin => integer()();

  BoolColumn get cruzaMedianoche => boolean().withDefault(const Constant(false))();

  BoolColumn get activo => boolean().withDefault(const Constant(true))();

  @override
  List<String> get customConstraints => [
        'CHECK (dia_semana BETWEEN 0 AND 6)',
        'CHECK (hora_inicio BETWEEN 0 AND 1439)',
        'CHECK (hora_fin BETWEEN 0 AND 1439)',
      ];
}
