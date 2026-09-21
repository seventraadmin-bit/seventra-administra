import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';
import '../../../organizacion/data/tables/servicio_linea_comercial_table.dart';
import '../../../organizacion/data/tables/servicio_table.dart';
import 'asignacion_servicio_table.dart';

enum EstatusVacanteOperativa { abierta, cubierta }

/// Bitácora del ciclo "posición cubierta → vacante → nuevamente
/// cubierta" (Etapa 15, rediseño del Dashboard gerencial).
///
/// **Por qué existe esta tabla en vez de derivarse de
/// `AsignacionServicio`**: investigación previa (ver el reporte de la
/// Parte 0 del pedido de Marlon) confirmó que `AsignacionServicio.
/// fechaInicio`/`fechaTermino`/`motivoTermino` sí son sólidos y nunca se
/// sobrescriben, PERO: (a) las plazas de una misma línea comercial son
/// anónimas — no hay forma de saber "cuál" de N asignaciones cerradas
/// corresponde a "cuál" plaza reabierta después; (b) una posición que
/// **nunca** se cubrió (línea creada con `cantidadElementos > 0` sin
/// ninguna `AsignacionServicio` jamás) no tiene ninguna fila de la que
/// derivar su fecha de apertura. Reconstruir esto retroactivamente
/// habría sido adivinar datos que no existen — en vez de eso, esta
/// tabla se mantiene en tiempo real, hacia adelante, junto con cada
/// mutación real de `AsignacionServicio` que afecta la cobertura de una
/// línea comercial (ver `AsignacionServicioRepositoryImpl._reconciliarVacante`).
///
/// **Limitación conocida y documentada**: una línea comercial cuya
/// condición requiere N elementos pero que nunca recibió ninguna
/// `AsignacionServicio` (ni una sola, ni siquiera histórica) no genera
/// automáticamente una fila aquí hasta el primer evento de
/// asignación/retiro sobre ella — el conteo agregado de vacantes
/// (déficit `requerido - cubierto`) siempre es correcto porque se
/// deriva en vivo de `ServicioLineaComercialVigencia`/`AsignacionServicio`,
/// pero la antigüedad exacta de una plaza así quedará sin registrar
/// hasta ese primer evento. No se inventa una fecha de apertura donde
/// no hay ningún dato real que la respalde.
///
/// Las plazas de una línea son anónimas (`cantidadElementos`, no N
/// filas identificadas individualmente) — por eso esta tabla tampoco
/// intenta identificar "la plaza 2 de 3", solo cuenta cuántas vacantes
/// están abiertas para esa línea y desde cuándo la más antigua de ellas.
class VacanteOperativa extends Table with AuditColumns {
  TextColumn get servicioId => text().references(Servicio, #id, onDelete: KeyAction.restrict)();

  TextColumn get lineaComercialId => text().references(ServicioLineaComercial, #id, onDelete: KeyAction.restrict)();

  DateTimeColumn get fechaApertura => dateTime()();

  /// Nombre estable del motivo que abrió esta vacante — mismo criterio
  /// que `MotivoTerminoAsignacion` (texto libre, nunca referencia al
  /// enum): `bajaEmpleado`/`cambioServicio`/`servicioTerminado`/
  /// cualquier motivo manual de retiro, o `aumentoRequerimiento` cuando
  /// la vacante nace de que la línea pidió más elementos, nunca de que
  /// alguien se fue.
  TextColumn get motivoApertura => text()();

  /// La `AsignacionServicio` cuyo cierre originó esta vacante —
  /// `null` cuando la vacante nace de un aumento de `cantidadElementos`
  /// (nunca hubo una asignación previa que "se fuera").
  TextColumn get asignacionOrigenId =>
      text().nullable().references(AsignacionServicio, #id, onDelete: KeyAction.restrict)();

  TextColumn get estatus => text().withDefault(const Constant('abierta'))();

  DateTimeColumn get fechaCobertura => dateTime().nullable()();

  /// La nueva `AsignacionServicio` que cerró esta vacante — `null`
  /// cuando se cerró porque la línea redujo su `cantidadElementos`
  /// (nunca porque alguien la cubrió).
  TextColumn get asignacionCoberturaId =>
      text().nullable().references(AsignacionServicio, #id, onDelete: KeyAction.restrict)();

  @override
  List<String> get customConstraints => [
        "CHECK ((estatus = 'abierta' AND fecha_cobertura IS NULL) OR "
            "(estatus = 'cubierta' AND fecha_cobertura IS NOT NULL))",
        'CHECK (fecha_cobertura IS NULL OR fecha_cobertura >= fecha_apertura)',
      ];
}
