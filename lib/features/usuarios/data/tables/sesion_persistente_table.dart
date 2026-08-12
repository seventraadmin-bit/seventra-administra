import 'package:drift/drift.dart';

import 'usuario_table.dart';

/// "Recuérdame en este equipo" (Etapa 15) — nunca guarda la contraseña
/// ni un token en texto plano; `tokenHash` es el hash SHA-256
/// (`hashTokenSesion`) del token real, que vive solo en el Almacén de
/// Credenciales de Windows (`AlmacenSesionRecordada`). Como ese almacén
/// tiene una única entrada por equipo, esta tabla nunca acumula más de
/// una fila viva en la práctica — un `recordarme` nuevo (de cualquier
/// Usuario) reemplaza la anterior. `onDelete: cascade` (no `setNull`
/// como los eventos): si el Usuario se elimina físicamente, la sesión
/// recordada no tiene ningún sentido de sobrevivir.
class SesionPersistente extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get usuarioId => text().references(Usuario, #id, onDelete: KeyAction.cascade)();

  TextColumn get tokenHash => text().unique()();

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get ultimoUsoAt => dateTime().nullable()();
}
