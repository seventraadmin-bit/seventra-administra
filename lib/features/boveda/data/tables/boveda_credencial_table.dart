import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';
import '../../../usuarios/data/tables/usuario_table.dart';

enum TipoAccesoBoveda { pcr, correo, portal, proveedor, software, pagina, otro }

/// Credencial interna de la Bóveda de Accesos del Maestro (Etapa 14D)
/// — PCR, correos, portales, proveedores, software, páginas y otros
/// accesos de RISEG. Reutiliza [AuditColumns] (`cicloVidaRegistro`
/// `activo`/`baja` cubre alta/baja/reactivación, sin campo "estatus"
/// aparte — mismo criterio que casi toda tabla de negocio del
/// proyecto). `secretoCifrado` es un string autodescriptivo
/// (`'aesgcm$1$<ivBase64>$<ciphertextBase64>'`, ver
/// `lib/core/security/credential_cipher.dart`) — nunca texto plano, y
/// **nunca conserva un valor anterior**: al cambiar se sobreescribe
/// esta fila, quién/cuándo lo hizo vive en [BovedaCredencialEvento].
/// `usuarioAcceso` es el usuario del sistema externo (ej. el login de
/// un portal) — deliberadamente no es una FK a [Usuario], que son las
/// cuentas de acceso a RISEG ONE mismo; la Bóveda nunca es una segunda
/// fuente de autenticación.
class BovedaCredencial extends Table with AuditColumns {
  TextColumn get nombre => text()();

  /// [TipoAccesoBoveda.name].
  TextColumn get tipo => text()();

  TextColumn get usuarioAcceso => text().nullable()();

  TextColumn get correo => text().nullable()();

  TextColumn get secretoCifrado => text().nullable()();

  DateTimeColumn get fechaActualizacionSecreto => dateTime().nullable()();

  TextColumn get url => text().nullable()();

  TextColumn get observaciones => text().nullable()();
}

/// Bitácora de la Bóveda (Etapa 14D) — mismo molde que
/// `EquipoTelefonicoEvento`: FK real a la credencial (que nunca se
/// elimina físicamente, solo se da de baja, así que `restrict` es
/// seguro), `actorUsuarioId` nullable con `SET NULL`. `observacion`
/// puede anotar datos no sensibles (ej. "correo actualizado") pero
/// **nunca** el secreto ni su forma cifrada.
class BovedaCredencialEvento extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get credencialId => text().references(BovedaCredencial, #id, onDelete: KeyAction.restrict)();

  TextColumn get actorUsuarioId => text().nullable().references(Usuario, #id, onDelete: KeyAction.setNull)();

  DateTimeColumn get fechaHora => dateTime()();

  /// creada|editada|secretoCambiado|secretoRevelado|secretoCopiado|dadaDeBaja|reactivada
  TextColumn get tipoEvento => text()();

  TextColumn get observacion => text().nullable()();
}
