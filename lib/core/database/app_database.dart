import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

part 'app_database.g.dart';

/// Tabla mínima usada únicamente para comprobar que Drift funciona de
/// extremo a extremo en esta etapa. No es una tabla de negocio.
///
/// `schemaVersion` NO se guarda aquí: Drift ya lo gestiona internamente
/// mediante [AppDatabase.schemaVersion] y su tabla interna de versiones.
class AppMetadata extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get installationId => text()();

  DateTimeColumn get installedAt => dateTime()();

  DateTimeColumn get lastOpenedAt => dateTime()();

  TextColumn get appVersion => text()();
}

@DriftDatabase(tables: [AppMetadata])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
      },
    );
  }

  /// Garantiza que exista exactamente un renglón de metadata de instalación.
  ///
  /// Si es la primera vez que se abre la aplicación, lo crea con un
  /// identificador de instalación nuevo. En cualquier otro caso, actualiza
  /// `lastOpenedAt` y `appVersion` y devuelve el renglón resultante.
  ///
  /// Sirve, en esta etapa, únicamente para comprobar que Drift funciona de
  /// extremo a extremo (lectura, inserción y actualización).
  Future<AppMetadataData> ensureMetadata({required String appVersion}) async {
    final existing = await select(appMetadata).getSingleOrNull();
    final now = DateTime.now();

    if (existing == null) {
      final id = await into(appMetadata).insert(
        AppMetadataCompanion.insert(
          installationId: _generateInstallationId(),
          installedAt: now,
          lastOpenedAt: now,
          appVersion: appVersion,
        ),
      );
      return (select(appMetadata)..where((t) => t.id.equals(id))).getSingle();
    }

    final updated = existing.copyWith(lastOpenedAt: now, appVersion: appVersion);
    await update(appMetadata).replace(updated);
    return updated;
  }

  static String _generateInstallationId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

/// Abre (o crea) el archivo de base de datos en [databaseFile].
///
/// Se asegura de que la carpeta contenedora exista antes de abrir la
/// conexión, ya que en una instalación nueva la carpeta de datos de la
/// aplicación todavía no existe.
QueryExecutor openAppDatabaseConnection(String databaseFile) {
  final directory = File(databaseFile).parent;
  if (!directory.existsSync()) {
    directory.createSync(recursive: true);
  }
  return NativeDatabase.createInBackground(File(databaseFile));
}
