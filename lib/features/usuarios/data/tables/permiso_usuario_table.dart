import 'package:drift/drift.dart';

import 'usuario_table.dart';

/// Permiso concedido a un Usuario (Etapa 11B) — tabla puente, sin
/// `AuditColumns` (mismo molde que `CompraPartidaMovimiento`: existir
/// ya es el hecho completo, no hay historial propio de la fila — ese
/// vive en `UsuarioEvento(permisosModificados)`).
///
/// `codigo` es un string libre tipo `'personal.ver'`/`'nomina.cerrar'`
/// — nunca una columna nueva por módulo/acción. El catálogo real de
/// códigos válidos vive en Dart (`lib/core/permissions/modulos_permiso.dart`),
/// no en esta tabla: agregar un permiso nuevo (incluso uno "especial"
/// como `usuarios.administrar`) nunca requiere una migración.
///
/// El Maestro **nunca tiene filas aquí** — sus permisos se calculan en
/// memoria a partir del catálogo completo (ver `SessionPermissionService`),
/// así que agregar un módulo nuevo no exige tocar datos existentes para
/// que el Maestro ya lo tenga.
class PermisoUsuario extends Table {
  TextColumn get usuarioId => text().references(Usuario, #id, onDelete: KeyAction.cascade)();

  TextColumn get codigo => text()();

  @override
  Set<Column> get primaryKey => {usuarioId, codigo};
}
