import 'package:drift/drift.dart';

import 'servicio_linea_comercial_vigencia_table.dart';

/// Un bloque horario de un día de la semana dentro del horario
/// personalizado de una vigencia de línea comercial (Etapa 15,
/// "Modalidad de turno: Personalizado") — mismo shape exacto que
/// `HorarioDetalle` (Sucursal/Servicio), pero con FK directa a
/// [ServicioLineaComercialVigencia] en vez de a una tabla cabecera
/// propia: a diferencia de Sucursal (donde un `Horario` puede
/// reactivarse/desactivarse repetidas veces sobre el mismo dueño), cada
/// vigencia de línea comercial ya es, por sí misma, la identidad
/// versionada correcta — nunca se reutiliza entre vigencias, así que no
/// hace falta resolver un arco exclusivo ni una fila cabecera.
///
/// Solo existen filas aquí cuando la vigencia dueña tiene
/// `modalidadTurnoId` = Personalizado; si se corrige o se abre una
/// nueva vigencia con otra modalidad, las filas de la vigencia afectada
/// se eliminan explícitamente (nunca basura huérfana). `onDelete:
/// cascade` porque estas filas no tienen ninguna identidad ni ciclo de
/// vida fuera de su vigencia dueña — se borran siempre junto con ella
/// (mismo criterio que `HorarioDetalle.horarioId`).
class ServicioLineaComercialVigenciaHorario extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get lineaComercialVigenciaId =>
      text().references(ServicioLineaComercialVigencia, #id, onDelete: KeyAction.cascade)();

  /// 0 = lunes ... 6 = domingo.
  IntColumn get diaSemana => integer()();

  IntColumn get horaInicio => integer()();

  IntColumn get horaFin => integer()();

  BoolColumn get cruzaMedianoche => boolean().withDefault(const Constant(false))();

  /// `true` si ese día se trabaja — `false` significa descanso (sin
  /// importar el valor de `horaInicio`/`horaFin`, que quedan en `0`).
  BoolColumn get activo => boolean().withDefault(const Constant(true))();

  @override
  List<String> get customConstraints => [
        'CHECK (dia_semana BETWEEN 0 AND 6)',
        'CHECK (hora_inicio BETWEEN 0 AND 1439)',
        'CHECK (hora_fin BETWEEN 0 AND 1439)',
      ];
}
