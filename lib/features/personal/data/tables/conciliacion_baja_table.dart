import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';
import '../../../descuentos_personal/data/tables/descuento_programado_empleado_table.dart';
import '../../../inventario/data/tables/articulo_unidad_table.dart';
import '../../../inventario/data/tables/asignacion_table.dart';
import '../../../usuarios/data/tables/usuario_table.dart';
import '../../../vehiculos/data/tables/asignacion_vehiculo_table.dart';
import 'empleado_table.dart';

/// Qué ocurrió realmente con un bien al cerrar la relación laboral
/// (schemaVersion 83).
///
/// Una baja ya no puede confirmarse dejando bienes sin explicación: cada
/// asignación vigente exige una de estas resoluciones. Lo obligatorio es
/// SABER qué pasó, no haber recuperado todo.
///
/// Para un vehículo, `devuelto` se lee como "entregado" — es el mismo
/// hecho (el bien volvió a manos de RISEG) y no se inventa un segundo
/// vocabulario para decir lo mismo.
enum ResolucionResguardoBaja {
  /// El bien volvió a RISEG. Exige condición y destino.
  devuelto(exigeCondicionYDestino: true),

  /// Sigue con la persona, o ya no se recuperará. Exige motivo.
  noEntregado(exigeMotivoNoEntrega: true),

  /// Pasó directo a otra persona sin volver al almacén — se resuelve con
  /// `AsignacionRepository.cambiarResponsable`, que ya existe justo para
  /// esto (`EstatusAsignacion.reasignada`): nunca una devolución
  /// ficticia seguida de un alta.
  transferido(exigeNuevoResponsable: true),

  /// Extraviado: sale del patrimonio recuperable.
  perdido(),

  /// Devuelto pero inservible: no regresa a existencias.
  desecho();

  const ResolucionResguardoBaja({
    this.exigeCondicionYDestino = false,
    this.exigeMotivoNoEntrega = false,
    this.exigeNuevoResponsable = false,
  });

  final bool exigeCondicionYDestino;
  final bool exigeMotivoNoEntrega;
  final bool exigeNuevoResponsable;

  /// Las que aplican a un vehículo (§13): entregado / no entregado /
  /// transferido. Un vehículo no tiene "desecho" desde una baja laboral
  /// — esa es la baja del propio vehículo, otro flujo.
  bool get aplicaAVehiculo =>
      this == devuelto || this == noEntregado || this == transferido || this == perdido;
}

/// Condición del bien AL RECIBIRLO (schemaVersion 83).
///
/// Deliberadamente distinta de `Asignacion.condicionEntrega`, que es la
/// condición con la que se ENTREGÓ a la persona: son dos momentos y dos
/// hechos, y reutilizar aquel campo sería darle una semántica que no
/// tiene.
enum CondicionDevolucionResguardo {
  bueno,
  usado,
  /// Prendas/equipo lavable: habilita el costo de limpieza (§6).
  sucio(admiteLimpieza: true),
  malEstado,
  danado;

  const CondicionDevolucionResguardo({this.admiteLimpieza = false});

  final bool admiteLimpieza;
}

/// A dónde va el bien recibido (schemaVersion 83).
///
/// Determina DÓNDE queda físicamente la unidad, y con eso si puede
/// asignarse:
///
///  - `inventarioDisponible`/`inventarioUsado` → vuelve al anaquel.
///  - `lavanderia`/`reparacion` → recuperada del empleado, pero todavía
///    fuera: no asignable hasta que alguien registre su retorno.
///  - `desecho` → decisión de desechar; la baja física la ejecuta
///    después `RegistrarBajaUnidadUseCase`, el ciclo oficial que ya
///    existe en Inventario.
///
/// Recuperar un bien y tenerlo disponible NO son lo mismo. Esa
/// confusión es justo la que este enum deja de cometer.
enum DestinoDevolucionResguardo {
  inventarioDisponible(),
  inventarioUsado(),

  /// La prenda está EN la tintorería. Recuperada del empleado, sí; lista
  /// para entregar, todavía no. Antes este destino dejaba la unidad
  /// `disponible`, es decir reasignable mientras seguía fuera.
  lavanderia(ubicacion: EstatusArticuloUnidad.enLavanderia),

  reparacion(ubicacion: EstatusArticuloUnidad.enReparacion),

  /// DECISIÓN de desechar, no el hecho consumado: la unidad sale de
  /// disponibilidad y queda esperando que Inventario ejecute su baja
  /// con `RegistrarBajaUnidadUseCase`, el ciclo oficial que ya existe.
  desecho(ubicacion: EstatusArticuloUnidad.pendienteDesecho);

  const DestinoDevolucionResguardo({this.ubicacion});

  /// Dónde queda físicamente la unidad. `null` = vuelve a existencias
  /// disponibles.
  final EstatusArticuloUnidad? ubicacion;

  bool get vuelveAExistencias => ubicacion == null;
}

/// Por qué un bien no se entregó (schemaVersion 83) — catálogo cerrado,
/// nunca un string mágico en la lógica (§7).
///
/// `dejaPendiente` es lo que hace que `pendienteRecuperacionDesde` deje
/// de ser automático: solo se marca cuando el bien SIGUE con la persona
/// y RISEG espera recuperarlo.
///
/// `exigeAutorizacion` cubre los casos en que RISEG renuncia a
/// recuperar: alguien con responsabilidad administrativa tiene que
/// ponerle su nombre (§9).
enum MotivoNoEntregaResguardo {
  abandonoServicio(dejaPendiente: true),
  noLocalizado(dejaPendiente: true),
  seNegoAEntregar(dejaPendiente: true),
  entregaAcordadaPosteriormente(dejaPendiente: true, admiteFechaCompromiso: true),
  perdida(),
  robo(),
  noSeSolicitoDevolucion(exigeAutorizacion: true),
  autorizadoAConservarlo(exigeAutorizacion: true),
  otro(dejaPendiente: true, requiereTexto: true);

  const MotivoNoEntregaResguardo({
    this.dejaPendiente = false,
    this.exigeAutorizacion = false,
    this.admiteFechaCompromiso = false,
    this.requiereTexto = false,
  });

  final bool dejaPendiente;
  final bool exigeAutorizacion;
  final bool admiteFechaCompromiso;
  final bool requiereTexto;
}

/// Quién absorbe un costo derivado de la conciliación (§6).
///
/// Etapa 5B.3: el primer valor se llamaba `riseg`, que daba por sentado que
/// la empresa del sistema es la piloto. Se guarda como texto libre vía
/// `.name` y nunca se vuelve a leer como enum, así que el cambio no necesita
/// migración: las filas antiguas conservan su valor y nada lo interpreta.
enum ResponsableCostoResguardo { empresa, trabajador }

/// La conciliación de resguardos de UNA baja laboral (schemaVersion 83).
///
/// Cabecera de la operación: agrupa los renglones para poder responder
/// "¿qué pasó en la baja de Juan?" como una sola cosa, y para que los
/// reportes que vendrán después (cartera de ex empleados, compromisos
/// vencidos) tengan una entidad que consultar en vez de reconstruirla
/// cruzando tablas.
///
/// NO duplica nada de la baja: `Empleado.fechaBaja`/`motivoBaja` siguen
/// siendo la fuente de verdad de la baja misma.
class ConciliacionBaja extends Table with AuditColumns {
  TextColumn get empleadoId => text().references(Empleado, #id, onDelete: KeyAction.restrict)();

  /// Misma fecha efectiva que la baja laboral que la originó.
  DateTimeColumn get fechaBaja => dateTime()();

  TextColumn get observaciones => text().nullable()();

  TextColumn get actorUsuarioId => text().nullable().references(Usuario, #id, onDelete: KeyAction.setNull)();
}

/// Un bien conciliado dentro de una baja (schemaVersion 83).
///
/// Apunta por FK a la asignación real —de Inventario o de Vehículos—,
/// exactamente una de las dos. Nunca por nombre de artículo ni por
/// texto: el renglón es una anotación SOBRE la asignación existente, no
/// una copia de ella.
///
/// Los datos que Inventario/Vehículos ya saben expresar (estatus,
/// movimientos, fecha de cierre) viven allá y no se duplican aquí. Aquí
/// vive únicamente lo que ningún dominio sabía registrar: con qué
/// condición se recibió, a dónde fue, por qué no se entregó, quién lo
/// autorizó, quién lo recibió y para cuándo se comprometió.
class ConciliacionBajaRenglon extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get conciliacionBajaId => text().references(ConciliacionBaja, #id, onDelete: KeyAction.cascade)();

  TextColumn get asignacionId => text().nullable().references(Asignacion, #id, onDelete: KeyAction.restrict)();

  TextColumn get asignacionVehiculoId =>
      text().nullable().references(AsignacionVehiculo, #id, onDelete: KeyAction.restrict)();

  /// [ResolucionResguardoBaja.name].
  TextColumn get resolucion => text()();

  /// [CondicionDevolucionResguardo.name] — solo en `devuelto`.
  TextColumn get condicion => text().nullable()();

  /// [DestinoDevolucionResguardo.name] — solo en `devuelto`.
  TextColumn get destino => text().nullable()();

  /// [MotivoNoEntregaResguardo.name] — solo en `noEntregado`.
  TextColumn get motivoNoEntrega => text().nullable()();

  /// Texto libre obligatorio cuando el motivo es `otro`.
  TextColumn get motivoNoEntregaOtro => text().nullable()();

  DateTimeColumn get fechaCompromiso => dateTime().nullable()();

  /// Empleado ADMINISTRATIVO activo que autorizó no recuperar o no
  /// cobrar (§9). FK real, nunca un nombre escrito a mano.
  TextColumn get autorizadorEmpleadoId =>
      text().nullable().references(Empleado, #id, onDelete: KeyAction.restrict)();

  /// Empleado ADMINISTRATIVO activo que recibió físicamente el bien
  /// (§14) — permite reconstruir quién entregó, cuándo y quién recibió.
  TextColumn get receptorEmpleadoId => text().nullable().references(Empleado, #id, onDelete: KeyAction.restrict)();

  /// La obligación económica REAL creada por este renglón, si la hubo —
  /// `DescuentoProgramadoEmpleado`, con sus cuotas. Nunca un importe
  /// suelto informativo.
  TextColumn get descuentoProgramadoId =>
      text().nullable().references(DescuentoProgramadoEmpleado, #id, onDelete: KeyAction.restrict)();

  /// Por qué se decidió NO cobrar algo que sí generaba un costo (§11).
  /// Junto con [autorizadorEmpleadoId], impide que la responsabilidad
  /// desaparezca con un "No" sin explicación.
  TextColumn get motivoNoCobro => text().nullable()();

  /// Costo de limpieza cuando la condición es `sucio` (§6) y quién lo
  /// absorbe ([ResponsableCostoResguardo.name]). Si lo paga el
  /// trabajador, [descuentoProgramadoId] apunta a la obligación real.
  IntColumn get costoLimpieza => integer().nullable()();

  TextColumn get responsableCostoLimpieza => text().nullable()();

  // --- Solo vehículos (§13) ---

  TextColumn get lugarEntrega => text().nullable()();

  /// Nivel de combustible reportado al recibir (texto corto libre: no
  /// existe un catálogo en el dominio y no se inventa uno).
  TextColumn get combustible => text().nullable()();

  TextColumn get danos => text().nullable()();

  TextColumn get observaciones => text().nullable()();

  @override
  List<String> get customConstraints => [
        // Exactamente una de las dos asignaciones — mismo criterio que
        // `empleadoId`/`servicioId` en las propias tablas de asignación.
        'CHECK ((asignacion_id IS NOT NULL AND asignacion_vehiculo_id IS NULL) OR '
            '(asignacion_id IS NULL AND asignacion_vehiculo_id IS NOT NULL))',
        'CHECK (costo_limpieza IS NULL OR costo_limpieza > 0)',
      ];
}
