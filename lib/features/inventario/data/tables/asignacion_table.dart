import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';
import '../../../organizacion/data/tables/servicio_table.dart';
import '../../../personal/data/tables/empleado_table.dart';
import 'articulo_table.dart';
import 'articulo_unidad_table.dart';
import 'articulo_variante_table.dart';

enum EstatusAsignacion { activa, devuelta, danada, perdida }

/// Motivo de cierre de una [Asignacion] (Etapa 7B) — enum enriquecido,
/// mismo criterio que `MotivoTerminoAsignacion` (5D) y
/// `MotivoBajaEmpleado` (5C). `dano`/`perdida` son los únicos que
/// disparan el flujo de atribución/descuento y cierran la Asignacion
/// con ese mismo `estatus`; cualquier otro motivo cierra en
/// `devuelta` — ver `CerrarAsignacionUseCase`.
enum MotivoCierreAsignacion {
  desgaste(disparaDanoPerdida: false),
  dano(disparaDanoPerdida: true),
  perdida(disparaDanoPerdida: true),
  cambioTalla(disparaDanoPerdida: false),
  defecto(disparaDanoPerdida: false),
  bajaEmpleado(disparaDanoPerdida: false),
  otro(disparaDanoPerdida: false, requiereObservaciones: true);

  const MotivoCierreAsignacion({required this.disparaDanoPerdida, this.requiereObservaciones = false});

  final bool disparaDanoPerdida;
  final bool requiereObservaciones;
}

/// La relación Inventario↔Empleado/Servicio (Etapa 7B) — "quién tiene
/// qué", ahora o históricamente. Ni `Empleado` ni `Servicio` ganan
/// columnas nuevas: ninguno de los dos "posee" la asignación, ambos la
/// consultan (mismo criterio exacto que `AsignacionServicio`, Etapa
/// 5D). `empleadoId`/`servicioId` son mutuamente excluyentes —
/// exactamente uno de los dos, nunca una tabla polimórfica.
///
/// `varianteId`/`unidadId` mutuamente excluyentes, mismo criterio que
/// `MovimientoInventario`. El cierre de una fila es siempre completo
/// — nunca parcial (Resolución de 7A, reconfirmada al abrir 7B): si
/// se anticipa una devolución parcial, la entrega se captura desde el
/// principio como varios renglones de cantidad menor.
///
/// `estatus == activa` es la única combinación con `fechaCierre` nulo
/// — ver el `CHECK` correspondiente. `atribuibleAlEmpleado` solo tiene
/// sentido cuando `estatus` es `danada`/`perdida`.
///
/// `asignacionReemplazoId` es una autorreferencia: la fila VIEJA
/// apunta a la NUEVA que la reemplazó (nunca al revés) — trazabilidad
/// de reemplazo sin tabla extra, consultable en ambas direcciones por
/// join.
///
/// Sin `AsignacionEvento` aparte — mismo criterio que
/// `AsignacionServicio` (tampoco tiene uno): entrega y cierre son dos
/// momentos que ya caben en la propia fila; `MovimientoInventario`
/// sigue siendo el ledger de auditoría de existencias por debajo.
@TableIndex.sql(
  'CREATE UNIQUE INDEX idx_asignacion_unidad_activa '
  "ON asignacion (unidad_id) WHERE unidad_id IS NOT NULL AND estatus = 'activa'",
)
class Asignacion extends Table with AuditColumns {
  TextColumn get articuloId => text().references(Articulo, #id, onDelete: KeyAction.restrict)();

  TextColumn get varianteId => text().nullable().references(ArticuloVariante, #id, onDelete: KeyAction.restrict)();

  TextColumn get unidadId => text().nullable().references(ArticuloUnidad, #id, onDelete: KeyAction.restrict)();

  IntColumn get cantidad => integer()();

  TextColumn get empleadoId => text().nullable().references(Empleado, #id, onDelete: KeyAction.restrict)();

  TextColumn get servicioId => text().nullable().references(Servicio, #id, onDelete: KeyAction.restrict)();

  DateTimeColumn get fechaEntrega => dateTime()();

  /// Condición física del artículo/unidad al momento de entregarlo —
  /// texto libre ("Nuevo", "Usado - buen estado"), sin catálogo propio
  /// (no aporta valor operativo forzar un enum aquí, mismo criterio
  /// que `Articulo.unidadMedida`).
  TextColumn get condicionEntrega => text().nullable()();

  TextColumn get observaciones => text().nullable()();

  TextColumn get estatus => text().withDefault(const Constant('activa'))();

  DateTimeColumn get fechaCierre => dateTime().nullable()();

  TextColumn get motivoCierre => text().nullable()();

  TextColumn get observacionesCierre => text().nullable()();

  BoolColumn get atribuibleAlEmpleado => boolean().nullable()();

  TextColumn get asignacionReemplazoId =>
      text().nullable().references(Asignacion, #id, onDelete: KeyAction.restrict)();

  @override
  List<String> get customConstraints => [
        'CHECK ((empleado_id IS NOT NULL AND servicio_id IS NULL) OR '
            '(empleado_id IS NULL AND servicio_id IS NOT NULL))',
        'CHECK (variante_id IS NULL OR unidad_id IS NULL)',
        'CHECK (cantidad > 0)',
        'CHECK (unidad_id IS NULL OR cantidad = 1)',
        "CHECK ((estatus = 'activa' AND fecha_cierre IS NULL) OR "
            "(estatus != 'activa' AND fecha_cierre IS NOT NULL))",
        'CHECK (fecha_cierre IS NULL OR fecha_cierre >= fecha_entrega)',
        "CHECK (atribuible_al_empleado IS NULL OR estatus = 'danada' OR estatus = 'perdida')",
      ];
}
