import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';
import '../../../organizacion/data/tables/puesto_table.dart';
import '../../../personal/data/tables/empleado_table.dart';

/// Cuenta de acceso al sistema (Etapa 11A). `puesto` es descriptivo
/// (ver el doc comment de `Puesto`), nunca determina permisos — esos
/// viven en `PermisoUsuario`, y JAMÁS se derivan del nombre del puesto.
///
/// Etapa "Usuarios y permisos" (schemaVersion 78): gana [empleadoId],
/// revirtiendo la decisión original de no vincular con `Empleado`. El
/// motivo de entonces —"un Usuario puede ser un administrador externo"—
/// no compensó el costo real: `nombre` y `puestoId` propios crean una
/// SEGUNDA identidad que puede divergir de la del expediente de
/// Personal (Empleado Javier / Gerente RH frente a Usuario Javier /
/// otro puesto), sin que nada detecte la divergencia. El vínculo es
/// opcional, así que el caso del administrador externo sigue cabiendo:
/// ver el doc comment de [empleadoId].
///
/// Sin columna `estatus` propia: activo/inactivo es exactamente el caso
/// "existe/no existe puede operar" que ya cubre `cicloVidaRegistro`
/// (ver `AuditColumns`) — desactivar nunca borra la fila.
class Usuario extends Table with AuditColumns {
  TextColumn get nombre => text()();

  TextColumn get nombreUsuario => text().unique()();

  // Autodescriptivo: 'pbkdf2$<iteraciones>$<saltB64>$<hashB64>' — nunca
  // la contraseña en texto plano (ver `PasswordHasher`).
  TextColumn get passwordHash => text()();

  // Nullable a nivel de base — el primer Maestro (bootstrap, antes de
  // que exista ninguna sesión) no captura Puesto, y en una instalación
  // recién creada el catálogo de Puestos puede estar vacío todavía (no
  // se siembra automáticamente como Área). El alta normal vía
  // Configuración → Usuarios sí lo exige, pero esa regla vive en
  // `CrearUsuarioUseCase`, no aquí.
  TextColumn get puestoId => text().nullable().references(Puesto, #id, onDelete: KeyAction.restrict)();

  /// Etapa "Usuarios y permisos" (schemaVersion 78) — el Empleado que
  /// ESTÁ detrás de esta cuenta. `Usuario` guarda solo lo propio de
  /// autenticación/autorización; la identidad laboral (nombre real,
  /// puesto, sucursal, estado laboral) vive en `Empleado`, que ya es la
  /// fuente de verdad de la plantilla.
  ///
  /// Nullable a propósito, nunca obligatorio: el primer Maestro se crea
  /// en el bootstrap, ANTES de que exista ningún Empleado, y las
  /// cuentas anteriores a esta etapa no tienen a quién apuntar. Sin
  /// backfill heurístico — emparejar por nombre sería exactamente la
  /// adivinanza que este proyecto no hace. Una cuenta con `null` sigue
  /// mostrando su `nombre`/`puestoId` propios, como siempre.
  ///
  /// `restrict`: un Empleado con cuenta no se puede borrar físicamente
  /// sin resolver antes la cuenta.
  ///
  /// **Una baja laboral NUNCA borra ni desvincula la cuenta** (regla
  /// explícita de Marlon): el vínculo se conserva para auditoría, y lo
  /// que corresponde es desactivarla (`cicloVidaRegistro`), que es
  /// reversible si la persona reingresa. Cambiar de puesto o de
  /// sucursal no toca nada aquí: esos datos se leen del Empleado en
  /// cada consulta, así que no pueden divergir.
  TextColumn get empleadoId => text().nullable().references(Empleado, #id, onDelete: KeyAction.restrict)();

  BoolColumn get esMaestro => boolean().withDefault(const Constant(false))();

  /// Etapa "Usuarios y permisos" (schemaVersion 78) — la contraseña
  /// vigente es TEMPORAL: la fijó un Maestro al crear la cuenta y el
  /// titular debe cambiarla antes de poder usar el sistema.
  ///
  /// `false` por defecto y en toda cuenta existente: nadie que ya venía
  /// usando el sistema se ve obligado a cambiar nada. Se enciende solo
  /// al crear una cuenta desde Configuración → Usuarios, y se apaga en
  /// cuanto el titular cambia su contraseña.
  ///
  /// La contraseña temporal nunca se guarda ni se muestra en claro —
  /// vive únicamente como hash PBKDF2 en [passwordHash], igual que
  /// cualquier otra, y jamás aparece en `UsuarioEvento`.
  BoolColumn get debeCambiarPassword => boolean().withDefault(const Constant(false))();

  DateTimeColumn get ultimoAccesoAt => dateTime().nullable()();
}

/// Historial append-only de un Usuario (Etapa 11A) — mismo molde que
/// `CompraEvento`/`NominaEvento`. Una sola tabla cubre alta, edición,
/// cambio de contraseña, activar/desactivar y (desde la Etapa 11B)
/// cambios de permisos — es la auditoría administrativa completa sobre
/// el propio Usuario, sin una tabla de auditoría genérica paralela.
enum TipoEventoUsuario {
  creado,
  datosCorregidos,
  contrasenaCambiada,
  activado,
  desactivado,
  permisosModificados,
}

class UsuarioEvento extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get usuarioId => text().references(Usuario, #id, onDelete: KeyAction.cascade)();

  // Nulo solo en el evento de bootstrap (creación del primer Maestro,
  // cuando todavía no existe ninguna sesión) — la UI lo muestra como
  // "Actor no registrado", nunca como un actor `null` crudo: sin una marca
  TextColumn get actorUsuarioId => text().nullable().references(Usuario, #id, onDelete: KeyAction.setNull)();

  DateTimeColumn get fechaHora => dateTime()();

  // Literal en vez de referencia al enum — mismo motivo de siempre (ver
  // `NominaEvento`).
  TextColumn get tipoEvento => text()();

  TextColumn get observacion => text().nullable()();

  TextColumn get datosRelevantes => text().nullable()();
}

/// Evidencia de una eliminación física (Etapa 11D) — la única forma de
/// borrado real de una entidad de negocio en todo el proyecto,
/// facultad extraordinaria exclusiva del Usuario Maestro (`esMaestro
/// == true`, validado en cada `EliminarXxxFisicamenteUseCase`, nunca a
/// través de `PermisoUsuario` — ningún permiso dinámico puede otorgar
/// esta capacidad).
///
/// Deliberadamente **sin FK** hacia el registro eliminado: para cuando
/// esta fila se lee, ese registro ya no existe. `entidadIdOriginal` es
/// texto plano (el id que tenía la fila borrada, sin restricción de
/// referencia), y `snapshotJson` es la única fuente de qué era ese
/// registro — se serializa completo *antes* del `DELETE`, dentro de la
/// misma transacción que lo ejecuta.
class EliminacionFisicaEvento extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Ej. `'vehiculo'`, `'lineaTelefonica'`, `'articulo'`,
  /// `'categoriaArticulo'`, `'area'`, `'puesto'`, `'sucursal'` — texto
  /// libre, mismo criterio que `tipoEvento` en el resto del proyecto
  /// (nunca una referencia a un enum de base de datos).
  TextColumn get tipoEntidad => text()();

  TextColumn get entidadIdOriginal => text()();

  /// Obligatorio siempre que exista sesión — la única excepción teórica
  /// (`null`) sería una eliminación disparada sin sesión activa, que
  /// `exigirMaestro` ya rechaza antes de llegar aquí; se deja nullable
  /// únicamente por el mismo criterio estructural que `UsuarioEvento.actorUsuarioId`
  /// (`ON DELETE SET NULL` — el evento sobrevive aunque el Usuario que
  /// lo generó se elimine más adelante).
  TextColumn get actorUsuarioId =>
      text().nullable().references(Usuario, #id, onDelete: KeyAction.setNull)();

  DateTimeColumn get fechaHora => dateTime()();

  /// Texto libre (siempre poblado) — la mayoría de los dominios que
  /// usan esta tabla compartida todavía capturan un motivo en texto
  /// libre sin más estructura. Para un dominio que sí estructura su
  /// motivo (Etapa 15, primer caso: Compra), este campo recibe la
  /// etiqueta ya traducida (nunca el código crudo), para que cualquier
  /// vista/reporte que ya lea esta columna siga funcionando sin
  /// cambios.
  TextColumn get motivo => text()();

  /// Nombre estable del enum de motivo del dominio que originó esta
  /// eliminación (Etapa 15) — `null` para cualquier dominio que
  /// todavía no estructura su motivo (compatibilidad hacia atrás
  /// total: el resto de `tipoEntidad` nunca escribe esta columna).
  /// Nunca se reutiliza el mismo código entre dominios distintos —
  /// interpretarlo siempre requiere leer también `tipoEntidad`.
  TextColumn get motivoCodigo => text().nullable()();

  /// Detalle libre asociado al motivo estructurado — obligatorio solo
  /// cuando `motivoCodigo == 'otro'` (validado por el caso de uso del
  /// dominio correspondiente, nunca aquí). `null` en cualquier fila sin
  /// `motivoCodigo`.
  TextColumn get detalle => text().nullable()();

  TextColumn get snapshotJson => text()();
}
