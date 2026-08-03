// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $AppMetadataTable extends AppMetadata
    with TableInfo<$AppMetadataTable, AppMetadataData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppMetadataTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _installationIdMeta = const VerificationMeta(
    'installationId',
  );
  @override
  late final GeneratedColumn<String> installationId = GeneratedColumn<String>(
    'installation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _installedAtMeta = const VerificationMeta(
    'installedAt',
  );
  @override
  late final GeneratedColumn<DateTime> installedAt = GeneratedColumn<DateTime>(
    'installed_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastOpenedAtMeta = const VerificationMeta(
    'lastOpenedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastOpenedAt = GeneratedColumn<DateTime>(
    'last_opened_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _appVersionMeta = const VerificationMeta(
    'appVersion',
  );
  @override
  late final GeneratedColumn<String> appVersion = GeneratedColumn<String>(
    'app_version',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    installationId,
    installedAt,
    lastOpenedAt,
    appVersion,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_metadata';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppMetadataData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('installation_id')) {
      context.handle(
        _installationIdMeta,
        installationId.isAcceptableOrUnknown(
          data['installation_id']!,
          _installationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_installationIdMeta);
    }
    if (data.containsKey('installed_at')) {
      context.handle(
        _installedAtMeta,
        installedAt.isAcceptableOrUnknown(
          data['installed_at']!,
          _installedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_installedAtMeta);
    }
    if (data.containsKey('last_opened_at')) {
      context.handle(
        _lastOpenedAtMeta,
        lastOpenedAt.isAcceptableOrUnknown(
          data['last_opened_at']!,
          _lastOpenedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastOpenedAtMeta);
    }
    if (data.containsKey('app_version')) {
      context.handle(
        _appVersionMeta,
        appVersion.isAcceptableOrUnknown(data['app_version']!, _appVersionMeta),
      );
    } else if (isInserting) {
      context.missing(_appVersionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AppMetadataData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppMetadataData(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}id'],
          )!,
      installationId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}installation_id'],
          )!,
      installedAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}installed_at'],
          )!,
      lastOpenedAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}last_opened_at'],
          )!,
      appVersion:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}app_version'],
          )!,
    );
  }

  @override
  $AppMetadataTable createAlias(String alias) {
    return $AppMetadataTable(attachedDatabase, alias);
  }
}

class AppMetadataData extends DataClass implements Insertable<AppMetadataData> {
  final int id;
  final String installationId;
  final DateTime installedAt;
  final DateTime lastOpenedAt;
  final String appVersion;
  const AppMetadataData({
    required this.id,
    required this.installationId,
    required this.installedAt,
    required this.lastOpenedAt,
    required this.appVersion,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['installation_id'] = Variable<String>(installationId);
    map['installed_at'] = Variable<DateTime>(installedAt);
    map['last_opened_at'] = Variable<DateTime>(lastOpenedAt);
    map['app_version'] = Variable<String>(appVersion);
    return map;
  }

  AppMetadataCompanion toCompanion(bool nullToAbsent) {
    return AppMetadataCompanion(
      id: Value(id),
      installationId: Value(installationId),
      installedAt: Value(installedAt),
      lastOpenedAt: Value(lastOpenedAt),
      appVersion: Value(appVersion),
    );
  }

  factory AppMetadataData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppMetadataData(
      id: serializer.fromJson<int>(json['id']),
      installationId: serializer.fromJson<String>(json['installationId']),
      installedAt: serializer.fromJson<DateTime>(json['installedAt']),
      lastOpenedAt: serializer.fromJson<DateTime>(json['lastOpenedAt']),
      appVersion: serializer.fromJson<String>(json['appVersion']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'installationId': serializer.toJson<String>(installationId),
      'installedAt': serializer.toJson<DateTime>(installedAt),
      'lastOpenedAt': serializer.toJson<DateTime>(lastOpenedAt),
      'appVersion': serializer.toJson<String>(appVersion),
    };
  }

  AppMetadataData copyWith({
    int? id,
    String? installationId,
    DateTime? installedAt,
    DateTime? lastOpenedAt,
    String? appVersion,
  }) => AppMetadataData(
    id: id ?? this.id,
    installationId: installationId ?? this.installationId,
    installedAt: installedAt ?? this.installedAt,
    lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
    appVersion: appVersion ?? this.appVersion,
  );
  AppMetadataData copyWithCompanion(AppMetadataCompanion data) {
    return AppMetadataData(
      id: data.id.present ? data.id.value : this.id,
      installationId:
          data.installationId.present
              ? data.installationId.value
              : this.installationId,
      installedAt:
          data.installedAt.present ? data.installedAt.value : this.installedAt,
      lastOpenedAt:
          data.lastOpenedAt.present
              ? data.lastOpenedAt.value
              : this.lastOpenedAt,
      appVersion:
          data.appVersion.present ? data.appVersion.value : this.appVersion,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppMetadataData(')
          ..write('id: $id, ')
          ..write('installationId: $installationId, ')
          ..write('installedAt: $installedAt, ')
          ..write('lastOpenedAt: $lastOpenedAt, ')
          ..write('appVersion: $appVersion')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, installationId, installedAt, lastOpenedAt, appVersion);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppMetadataData &&
          other.id == this.id &&
          other.installationId == this.installationId &&
          other.installedAt == this.installedAt &&
          other.lastOpenedAt == this.lastOpenedAt &&
          other.appVersion == this.appVersion);
}

class AppMetadataCompanion extends UpdateCompanion<AppMetadataData> {
  final Value<int> id;
  final Value<String> installationId;
  final Value<DateTime> installedAt;
  final Value<DateTime> lastOpenedAt;
  final Value<String> appVersion;
  const AppMetadataCompanion({
    this.id = const Value.absent(),
    this.installationId = const Value.absent(),
    this.installedAt = const Value.absent(),
    this.lastOpenedAt = const Value.absent(),
    this.appVersion = const Value.absent(),
  });
  AppMetadataCompanion.insert({
    this.id = const Value.absent(),
    required String installationId,
    required DateTime installedAt,
    required DateTime lastOpenedAt,
    required String appVersion,
  }) : installationId = Value(installationId),
       installedAt = Value(installedAt),
       lastOpenedAt = Value(lastOpenedAt),
       appVersion = Value(appVersion);
  static Insertable<AppMetadataData> custom({
    Expression<int>? id,
    Expression<String>? installationId,
    Expression<DateTime>? installedAt,
    Expression<DateTime>? lastOpenedAt,
    Expression<String>? appVersion,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (installationId != null) 'installation_id': installationId,
      if (installedAt != null) 'installed_at': installedAt,
      if (lastOpenedAt != null) 'last_opened_at': lastOpenedAt,
      if (appVersion != null) 'app_version': appVersion,
    });
  }

  AppMetadataCompanion copyWith({
    Value<int>? id,
    Value<String>? installationId,
    Value<DateTime>? installedAt,
    Value<DateTime>? lastOpenedAt,
    Value<String>? appVersion,
  }) {
    return AppMetadataCompanion(
      id: id ?? this.id,
      installationId: installationId ?? this.installationId,
      installedAt: installedAt ?? this.installedAt,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
      appVersion: appVersion ?? this.appVersion,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (installationId.present) {
      map['installation_id'] = Variable<String>(installationId.value);
    }
    if (installedAt.present) {
      map['installed_at'] = Variable<DateTime>(installedAt.value);
    }
    if (lastOpenedAt.present) {
      map['last_opened_at'] = Variable<DateTime>(lastOpenedAt.value);
    }
    if (appVersion.present) {
      map['app_version'] = Variable<String>(appVersion.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppMetadataCompanion(')
          ..write('id: $id, ')
          ..write('installationId: $installationId, ')
          ..write('installedAt: $installedAt, ')
          ..write('lastOpenedAt: $lastOpenedAt, ')
          ..write('appVersion: $appVersion')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $AppMetadataTable appMetadata = $AppMetadataTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [appMetadata];
}

typedef $$AppMetadataTableCreateCompanionBuilder =
    AppMetadataCompanion Function({
      Value<int> id,
      required String installationId,
      required DateTime installedAt,
      required DateTime lastOpenedAt,
      required String appVersion,
    });
typedef $$AppMetadataTableUpdateCompanionBuilder =
    AppMetadataCompanion Function({
      Value<int> id,
      Value<String> installationId,
      Value<DateTime> installedAt,
      Value<DateTime> lastOpenedAt,
      Value<String> appVersion,
    });

class $$AppMetadataTableFilterComposer
    extends Composer<_$AppDatabase, $AppMetadataTable> {
  $$AppMetadataTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get installationId => $composableBuilder(
    column: $table.installationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get installedAt => $composableBuilder(
    column: $table.installedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastOpenedAt => $composableBuilder(
    column: $table.lastOpenedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get appVersion => $composableBuilder(
    column: $table.appVersion,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AppMetadataTableOrderingComposer
    extends Composer<_$AppDatabase, $AppMetadataTable> {
  $$AppMetadataTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get installationId => $composableBuilder(
    column: $table.installationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get installedAt => $composableBuilder(
    column: $table.installedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastOpenedAt => $composableBuilder(
    column: $table.lastOpenedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get appVersion => $composableBuilder(
    column: $table.appVersion,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AppMetadataTableAnnotationComposer
    extends Composer<_$AppDatabase, $AppMetadataTable> {
  $$AppMetadataTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get installationId => $composableBuilder(
    column: $table.installationId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get installedAt => $composableBuilder(
    column: $table.installedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastOpenedAt => $composableBuilder(
    column: $table.lastOpenedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get appVersion => $composableBuilder(
    column: $table.appVersion,
    builder: (column) => column,
  );
}

class $$AppMetadataTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AppMetadataTable,
          AppMetadataData,
          $$AppMetadataTableFilterComposer,
          $$AppMetadataTableOrderingComposer,
          $$AppMetadataTableAnnotationComposer,
          $$AppMetadataTableCreateCompanionBuilder,
          $$AppMetadataTableUpdateCompanionBuilder,
          (
            AppMetadataData,
            BaseReferences<_$AppDatabase, $AppMetadataTable, AppMetadataData>,
          ),
          AppMetadataData,
          PrefetchHooks Function()
        > {
  $$AppMetadataTableTableManager(_$AppDatabase db, $AppMetadataTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$AppMetadataTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$AppMetadataTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () =>
                  $$AppMetadataTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> installationId = const Value.absent(),
                Value<DateTime> installedAt = const Value.absent(),
                Value<DateTime> lastOpenedAt = const Value.absent(),
                Value<String> appVersion = const Value.absent(),
              }) => AppMetadataCompanion(
                id: id,
                installationId: installationId,
                installedAt: installedAt,
                lastOpenedAt: lastOpenedAt,
                appVersion: appVersion,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String installationId,
                required DateTime installedAt,
                required DateTime lastOpenedAt,
                required String appVersion,
              }) => AppMetadataCompanion.insert(
                id: id,
                installationId: installationId,
                installedAt: installedAt,
                lastOpenedAt: lastOpenedAt,
                appVersion: appVersion,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AppMetadataTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AppMetadataTable,
      AppMetadataData,
      $$AppMetadataTableFilterComposer,
      $$AppMetadataTableOrderingComposer,
      $$AppMetadataTableAnnotationComposer,
      $$AppMetadataTableCreateCompanionBuilder,
      $$AppMetadataTableUpdateCompanionBuilder,
      (
        AppMetadataData,
        BaseReferences<_$AppDatabase, $AppMetadataTable, AppMetadataData>,
      ),
      AppMetadataData,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$AppMetadataTableTableManager get appMetadata =>
      $$AppMetadataTableTableManager(_db, _db.appMetadata);
}
