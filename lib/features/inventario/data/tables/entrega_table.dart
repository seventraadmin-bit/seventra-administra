import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';
import '../../../organizacion/data/tables/servicio_table.dart';
import '../../../personal/data/tables/empleado_table.dart';
import '../../../usuarios/data/tables/usuario_table.dart';

/// Agrupa varias [Asignacion] creadas en un mismo acto de entrega real
/// (un guardia recibe uniforme completo + equipo de una sola vez) —
/// nunca inferido por fecha/empleado/observaciones coincidentes, solo
/// por este vínculo explícito (`Asignacion.entregaId`). Cada Asignacion
/// del lote sigue siendo completamente independiente después (se puede
/// devolver/reemplazar/reportar dañada-perdida una por una): `Entrega`
/// es solo la cabecera documental, nunca el dueño de su estado.
///
/// `empleadoId`/`servicioId` mutuamente excluyentes, mismo criterio
/// exacto que `Asignacion` — el esquema ya soporta destino Servicio
/// aunque esta etapa solo construye el diálogo/flujo para Empleado.
///
/// Sin `condicionEntrega`/`observaciones` propios: esos valores se
/// escriben tal cual en cada `Asignacion` del lote (pueden heredarse al
/// capturar, pero viven en la fila que realmente los usa después) —
/// evita una segunda fuente de verdad que se desincronice si alguien
/// edita una Asignacion individual más adelante.
class Entrega extends Table with AuditColumns {
  TextColumn get folio => text().unique()();

  TextColumn get empleadoId => text().nullable().references(Empleado, #id, onDelete: KeyAction.restrict)();

  TextColumn get servicioId => text().nullable().references(Servicio, #id, onDelete: KeyAction.restrict)();

  DateTimeColumn get fechaEntrega => dateTime()();

  TextColumn get actorUsuarioId => text().nullable().references(Usuario, #id, onDelete: KeyAction.setNull)();

  @override
  List<String> get customConstraints => [
        'CHECK ((empleado_id IS NOT NULL AND servicio_id IS NULL) OR '
            '(empleado_id IS NULL AND servicio_id IS NOT NULL))',
      ];
}
