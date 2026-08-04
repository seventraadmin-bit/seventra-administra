import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:uuid/uuid.dart';

import '../../features/organizacion/data/tables/cliente_table.dart';
import '../../features/organizacion/data/tables/contacto_table.dart';
import '../../features/organizacion/data/tables/empresa_table.dart';
import '../../features/organizacion/data/tables/puesto_table.dart';
import '../../features/organizacion/data/tables/servicio_table.dart';
import '../../features/organizacion/data/tables/sucursal_table.dart';
import '../../features/organizacion/data/tables/ubicacion_table.dart';
import 'seed/seed_data.dart';
import 'tables/attachment_table.dart';
import 'tables/catalogos_tables.dart';
import 'tables/codigo_secuencia_table.dart';
import 'tables/direccion_table.dart';
import 'tables/horario_table.dart';
import 'tables/medio_contacto_table.dart';

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

@DriftDatabase(tables: [
  AppMetadata,
  CodigoSecuencia,
  TipoSucursal,
  Industria,
  TipoServicio,
  Area,
  Direccion,
  MedioContacto,
  Attachment,
  Horario,
  HorarioDetalle,
  Empresa,
  Sucursal,
  Ubicacion,
  Puesto,
  Cliente,
  Contacto,
  Servicio,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
        await runSeed(this);
      },
      onUpgrade: (Migrator m, int from, int to) async {
        if (from == 1) {
          await _createEtapa4ATables(m);
        }
        await runSeed(this);
      },
    );
  }

  /// Tablas agregadas por la Etapa 4A (Fundamentos de Organización) —
  /// puramente aditivo, no toca `AppMetadata`.
  Future<void> _createEtapa4ATables(Migrator m) async {
    await m.createTable(codigoSecuencia);
    await m.createTable(tipoSucursal);
    await m.createTable(industria);
    await m.createTable(tipoServicio);
    await m.createTable(area);
    await m.createTable(direccion);
    await m.createTable(medioContacto);
    await m.createTable(attachment);
    await m.createTable(horario);
    await m.createTable(horarioDetalle);
    await m.createTable(empresa);
    await m.createTable(sucursal);
    await m.createTable(cliente);
    await m.createTable(contacto);
    await m.createTable(servicio);
    await m.createTable(ubicacion);
    await m.createTable(puesto);
    await m.createIndex(idxDireccionClienteTipoPrincipal);
    await m.createIndex(idxDireccionCliente);
    await m.createIndex(idxEmpresaActivaUnica);
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
