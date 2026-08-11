import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';
import '../../../organizacion/data/tables/puesto_table.dart';

/// Cuenta de acceso al sistema (Etapa 11A) — deliberadamente **sin** FK a
/// `Empleado`: `nombre` y `puesto` se capturan directo en el alta, un
/// Usuario no es necesariamente el mismo registro que un expediente de
/// Personal (puede ser un administrador externo, por ejemplo). `puesto`
/// es descriptivo (ver el doc comment de `Puesto`), nunca determina
/// permisos — esos viven en `PermisoUsuario`.
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

  BoolColumn get esMaestro => boolean().withDefault(const Constant(false))();

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
  // "Configuración inicial", nunca como un actor `null` crudo.
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

  TextColumn get motivo => text()();

  TextColumn get snapshotJson => text()();
}
