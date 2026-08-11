import 'package:drift/drift.dart';

import '../../../inventario/data/tables/articulo_unidad_table.dart';
import '../../../usuarios/data/tables/usuario_table.dart';

/// Credencial de la cuenta configurada para un teléfono físico (Etapa
/// 9D) — extensión 1:1 opcional de `ArticuloUnidad`, mismo patrón
/// `unidadId` como PK y FK a la vez que `ArticuloUnidadTelefono`.
/// Deliberadamente en su propia tabla y no como columnas agregadas a
/// `ArticuloUnidadTelefono`: esa tabla es la señal cross-domain que
/// Inventario ya consulta (`listarUnidadesTelefono`), y mezclar un
/// secreto cifrado ahí ensancha innecesariamente qué código "toca" un
/// dato sensible. `contrasenaCifrada` es un string autodescriptivo
/// (`'aesgcm$1$<ivBase64>$<ciphertextBase64>'`, ver
/// `lib/core/security/credential_cipher.dart`) — nunca texto plano.
/// Sin historial de contraseñas anteriores: al cambiarla se sobreescribe
/// esta fila; quién/cuándo lo hizo vive en `EquipoTelefonicoEvento`, no
/// aquí.
class EquipoTelefonicoCredencial extends Table {
  TextColumn get unidadId => text().references(ArticuloUnidad, #id, onDelete: KeyAction.cascade)();

  TextColumn get correo => text().nullable()();

  TextColumn get contrasenaCifrada => text().nullable()();

  DateTimeColumn get fechaActualizacionContrasena => dateTime().nullable()();

  TextColumn get observaciones => text().nullable()();

  @override
  Set<Column> get primaryKey => {unidadId};
}

/// Bitácora de acciones sensibles sobre el expediente de un teléfono
/// (Etapa 9D) — mismo molde que la mayoría de los `XxxEvento` del
/// proyecto (`IngresoEvento`, `CompraEvento`: FK real al sujeto,
/// `actorUsuarioId` nullable con `SET NULL`), no el de
/// `EliminacionFisicaEvento` (ese es un caso especial sin FK porque la
/// fila ya no existe al momento de leer el evento — aquí la
/// `ArticuloUnidad` siempre sigue existiendo). `observacion` puede
/// anotar datos no sensibles (ej. el nuevo correo) pero **nunca** la
/// contraseña ni su forma cifrada.
class EquipoTelefonicoEvento extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get unidadId => text().references(ArticuloUnidad, #id, onDelete: KeyAction.restrict)();

  TextColumn get actorUsuarioId => text().nullable().references(Usuario, #id, onDelete: KeyAction.setNull)();

  DateTimeColumn get fechaHora => dateTime()();

  TextColumn get tipoEvento => text()();

  TextColumn get observacion => text().nullable()();
}
