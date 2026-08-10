import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';
import 'asignacion_servicio_table.dart';

/// Un período histórico de sueldo/bono de una [AsignacionServicio] (Etapa
/// 6B) — mismo patrón que `ServicioLineaComercialVigencia` (Etapa 4G.1):
/// la identidad (`AsignacionServicio`) permanece estable, y cada cambio
/// de sueldo/bono dentro de la misma asignación cierra la vigencia
/// vigente y crea una nueva, nunca se actualiza in place. Permite
/// programar una vigencia futura (Resolución explícita de Marlon) — no
/// sustituye de inmediato a la vigente, se distingue únicamente por
/// fecha en tiempo de lectura (ver `clasificarVigenciasSueldo`).
///
/// `sueldoMensual` debe ser `> 0`; `bonoMensual` acepta `0` — mismo
/// criterio que `Servicio.sueldoMensualReferenciaPersonal`/
/// `bonoMensualReferenciaPersonal` y `Empleado.sueldoMensualAdministrativo`/
/// `bonoMensualAdministrativo` (Etapa 6A). En centavos, nunca `real`.
///
/// A diferencia de `ServicioLineaComercialVigencia`, no acepta una
/// `fechaFinVigencia` capturada a mano: se calcula siempre
/// automáticamente (predecesora cerrada el día anterior a la nueva
/// vigencia, sucesora ya programada limita el fin) — no hay ningún caso
/// de uso aprobado para una vigencia de sueldo con fin manual todavía
/// (sin sobrearquitectura, Resolución explícita de Marlon).
///
/// La primera vigencia de cada asignación se crea en la misma
/// transacción que la propia `AsignacionServicio`
/// (`AsignacionServicioRepositoryImpl.asignar`/`cambiarServicio`) — nunca
/// existe una asignación sin al menos una vigencia de sueldo. Cuando la
/// asignación termina (retiro, cambio de Servicio, baja), la vigencia
/// vigente no se cierra explícitamente: el propio rango
/// `AsignacionServicio.fechaInicio..fechaTermino` ya delimita qué parte
/// de una vigencia abierta aplica — Nómina (Etapa 6C) intersecta ambos
/// rangos, nunca lee una vigencia de sueldo más allá del fin de la
/// asignación que la contiene.
class AsignacionServicioSueldoVigencia extends Table with AuditColumns {
  TextColumn get asignacionServicioId =>
      text().references(AsignacionServicio, #id, onDelete: KeyAction.restrict)();

  IntColumn get sueldoMensual => integer()();

  IntColumn get bonoMensual => integer()();

  DateTimeColumn get fechaInicioVigencia => dateTime()();

  DateTimeColumn get fechaFinVigencia => dateTime().nullable()();

  TextColumn get observaciones => text().nullable()();

  @override
  List<String> get customConstraints => [
        'CHECK (sueldo_mensual > 0)',
        'CHECK (bono_mensual >= 0)',
        'CHECK (fecha_fin_vigencia IS NULL OR fecha_fin_vigencia >= fecha_inicio_vigencia)',
      ];
}
