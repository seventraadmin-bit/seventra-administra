import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';
import '../../../inventario/data/tables/articulo_unidad_table.dart';
import '../../../usuarios/data/tables/usuario_table.dart';
import 'linea_telefonica_table.dart';

/// Qué teléfono físico de Inventario trae la SIM de una línea, en el
/// tiempo (Etapa 9B) — tabla propia de Telefonía, separada de
/// `AsignacionLineaTelefonica` (quién usa la línea): el ejemplo del
/// propio Marlon (misma línea, el equipo cambia en julio sin que
/// cambie quién la usa) confirma que son dos ejes independientes;
/// combinarlos forzaría cerrar/reabrir la asignación de empleado/
/// Servicio cada vez que solo cambia el aparato físico.
///
/// **Nunca duplica custodia** — `Inventario.Asignacion` sigue siendo la
/// única tabla que almacena quién tiene físicamente la unidad; esta
/// tabla solo registra "esta unidad trajo la SIM de esta línea, en este
/// periodo". `unidadId` apunta a `ArticuloUnidad` (Inventario) — nunca
/// se vuelve a capturar marca/modelo/IMEI aquí, eso vive en
/// `ArticuloUnidadTelefono`.
///
/// La sincronización activa de custodia con Inventario (crear/cerrar la
/// `Asignacion` real cuando la línea tiene un destino) vive en
/// `LineaTelefonicaEquipoRepositoryImpl`, no en esta definición de
/// tabla — ver su doc comment para la decisión completa (memoria:
/// "Inventario dueño único, sincronización activa vía composición de
/// repositorios").
///
/// "Cambiar equipo" = cerrar el registro abierto (`fechaFin`) + insertar
/// uno nuevo, misma mecánica simple que `LineaTelefonicaPlan` — nunca
/// más de un registro abierto a la vez, por construcción.
class LineaTelefonicaEquipo extends Table with AuditColumns {
  TextColumn get lineaTelefonicaId => text().references(LineaTelefonica, #id, onDelete: KeyAction.restrict)();

  TextColumn get unidadId => text().references(ArticuloUnidad, #id, onDelete: KeyAction.restrict)();

  DateTimeColumn get fechaInicio => dateTime()();

  DateTimeColumn get fechaFin => dateTime().nullable()();

  TextColumn get observaciones => text().nullable()();

  /// **Etapa 9D** — mismo caso que `AsignacionLineaTelefonica.actorUsuarioId`:
  /// el UseCase/repositorio ya recibían `actorUsuarioId` desde la Etapa
  /// 9B, pero la columna nunca existió y el valor se descartaba
  /// silenciosamente.
  TextColumn get actorUsuarioId => text().nullable().references(Usuario, #id, onDelete: KeyAction.setNull)();

  @override
  List<String> get customConstraints => [
        'CHECK (fecha_fin IS NULL OR fecha_fin >= fecha_inicio)',
      ];
}
