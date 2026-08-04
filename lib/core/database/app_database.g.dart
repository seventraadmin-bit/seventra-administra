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

class $CodigoSecuenciaTable extends CodigoSecuencia
    with TableInfo<$CodigoSecuenciaTable, CodigoSecuenciaData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CodigoSecuenciaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _entityTypeMeta = const VerificationMeta(
    'entityType',
  );
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
    'entity_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _prefijoMeta = const VerificationMeta(
    'prefijo',
  );
  @override
  late final GeneratedColumn<String> prefijo = GeneratedColumn<String>(
    'prefijo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _digitosMeta = const VerificationMeta(
    'digitos',
  );
  @override
  late final GeneratedColumn<int> digitos = GeneratedColumn<int>(
    'digitos',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _reseteaAnualmenteMeta = const VerificationMeta(
    'reseteaAnualmente',
  );
  @override
  late final GeneratedColumn<bool> reseteaAnualmente = GeneratedColumn<bool>(
    'resetea_anualmente',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("resetea_anualmente" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _anioActualMeta = const VerificationMeta(
    'anioActual',
  );
  @override
  late final GeneratedColumn<int> anioActual = GeneratedColumn<int>(
    'anio_actual',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _contadorActualMeta = const VerificationMeta(
    'contadorActual',
  );
  @override
  late final GeneratedColumn<int> contadorActual = GeneratedColumn<int>(
    'contador_actual',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    entityType,
    prefijo,
    digitos,
    reseteaAnualmente,
    anioActual,
    contadorActual,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'codigo_secuencia';
  @override
  VerificationContext validateIntegrity(
    Insertable<CodigoSecuenciaData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('entity_type')) {
      context.handle(
        _entityTypeMeta,
        entityType.isAcceptableOrUnknown(data['entity_type']!, _entityTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_entityTypeMeta);
    }
    if (data.containsKey('prefijo')) {
      context.handle(
        _prefijoMeta,
        prefijo.isAcceptableOrUnknown(data['prefijo']!, _prefijoMeta),
      );
    } else if (isInserting) {
      context.missing(_prefijoMeta);
    }
    if (data.containsKey('digitos')) {
      context.handle(
        _digitosMeta,
        digitos.isAcceptableOrUnknown(data['digitos']!, _digitosMeta),
      );
    } else if (isInserting) {
      context.missing(_digitosMeta);
    }
    if (data.containsKey('resetea_anualmente')) {
      context.handle(
        _reseteaAnualmenteMeta,
        reseteaAnualmente.isAcceptableOrUnknown(
          data['resetea_anualmente']!,
          _reseteaAnualmenteMeta,
        ),
      );
    }
    if (data.containsKey('anio_actual')) {
      context.handle(
        _anioActualMeta,
        anioActual.isAcceptableOrUnknown(data['anio_actual']!, _anioActualMeta),
      );
    }
    if (data.containsKey('contador_actual')) {
      context.handle(
        _contadorActualMeta,
        contadorActual.isAcceptableOrUnknown(
          data['contador_actual']!,
          _contadorActualMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {entityType};
  @override
  CodigoSecuenciaData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CodigoSecuenciaData(
      entityType:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}entity_type'],
          )!,
      prefijo:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}prefijo'],
          )!,
      digitos:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}digitos'],
          )!,
      reseteaAnualmente:
          attachedDatabase.typeMapping.read(
            DriftSqlType.bool,
            data['${effectivePrefix}resetea_anualmente'],
          )!,
      anioActual: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}anio_actual'],
      ),
      contadorActual:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}contador_actual'],
          )!,
    );
  }

  @override
  $CodigoSecuenciaTable createAlias(String alias) {
    return $CodigoSecuenciaTable(attachedDatabase, alias);
  }
}

class CodigoSecuenciaData extends DataClass
    implements Insertable<CodigoSecuenciaData> {
  final String entityType;
  final String prefijo;
  final int digitos;
  final bool reseteaAnualmente;
  final int? anioActual;
  final int contadorActual;
  const CodigoSecuenciaData({
    required this.entityType,
    required this.prefijo,
    required this.digitos,
    required this.reseteaAnualmente,
    this.anioActual,
    required this.contadorActual,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['entity_type'] = Variable<String>(entityType);
    map['prefijo'] = Variable<String>(prefijo);
    map['digitos'] = Variable<int>(digitos);
    map['resetea_anualmente'] = Variable<bool>(reseteaAnualmente);
    if (!nullToAbsent || anioActual != null) {
      map['anio_actual'] = Variable<int>(anioActual);
    }
    map['contador_actual'] = Variable<int>(contadorActual);
    return map;
  }

  CodigoSecuenciaCompanion toCompanion(bool nullToAbsent) {
    return CodigoSecuenciaCompanion(
      entityType: Value(entityType),
      prefijo: Value(prefijo),
      digitos: Value(digitos),
      reseteaAnualmente: Value(reseteaAnualmente),
      anioActual:
          anioActual == null && nullToAbsent
              ? const Value.absent()
              : Value(anioActual),
      contadorActual: Value(contadorActual),
    );
  }

  factory CodigoSecuenciaData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CodigoSecuenciaData(
      entityType: serializer.fromJson<String>(json['entityType']),
      prefijo: serializer.fromJson<String>(json['prefijo']),
      digitos: serializer.fromJson<int>(json['digitos']),
      reseteaAnualmente: serializer.fromJson<bool>(json['reseteaAnualmente']),
      anioActual: serializer.fromJson<int?>(json['anioActual']),
      contadorActual: serializer.fromJson<int>(json['contadorActual']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'entityType': serializer.toJson<String>(entityType),
      'prefijo': serializer.toJson<String>(prefijo),
      'digitos': serializer.toJson<int>(digitos),
      'reseteaAnualmente': serializer.toJson<bool>(reseteaAnualmente),
      'anioActual': serializer.toJson<int?>(anioActual),
      'contadorActual': serializer.toJson<int>(contadorActual),
    };
  }

  CodigoSecuenciaData copyWith({
    String? entityType,
    String? prefijo,
    int? digitos,
    bool? reseteaAnualmente,
    Value<int?> anioActual = const Value.absent(),
    int? contadorActual,
  }) => CodigoSecuenciaData(
    entityType: entityType ?? this.entityType,
    prefijo: prefijo ?? this.prefijo,
    digitos: digitos ?? this.digitos,
    reseteaAnualmente: reseteaAnualmente ?? this.reseteaAnualmente,
    anioActual: anioActual.present ? anioActual.value : this.anioActual,
    contadorActual: contadorActual ?? this.contadorActual,
  );
  CodigoSecuenciaData copyWithCompanion(CodigoSecuenciaCompanion data) {
    return CodigoSecuenciaData(
      entityType:
          data.entityType.present ? data.entityType.value : this.entityType,
      prefijo: data.prefijo.present ? data.prefijo.value : this.prefijo,
      digitos: data.digitos.present ? data.digitos.value : this.digitos,
      reseteaAnualmente:
          data.reseteaAnualmente.present
              ? data.reseteaAnualmente.value
              : this.reseteaAnualmente,
      anioActual:
          data.anioActual.present ? data.anioActual.value : this.anioActual,
      contadorActual:
          data.contadorActual.present
              ? data.contadorActual.value
              : this.contadorActual,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CodigoSecuenciaData(')
          ..write('entityType: $entityType, ')
          ..write('prefijo: $prefijo, ')
          ..write('digitos: $digitos, ')
          ..write('reseteaAnualmente: $reseteaAnualmente, ')
          ..write('anioActual: $anioActual, ')
          ..write('contadorActual: $contadorActual')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    entityType,
    prefijo,
    digitos,
    reseteaAnualmente,
    anioActual,
    contadorActual,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CodigoSecuenciaData &&
          other.entityType == this.entityType &&
          other.prefijo == this.prefijo &&
          other.digitos == this.digitos &&
          other.reseteaAnualmente == this.reseteaAnualmente &&
          other.anioActual == this.anioActual &&
          other.contadorActual == this.contadorActual);
}

class CodigoSecuenciaCompanion extends UpdateCompanion<CodigoSecuenciaData> {
  final Value<String> entityType;
  final Value<String> prefijo;
  final Value<int> digitos;
  final Value<bool> reseteaAnualmente;
  final Value<int?> anioActual;
  final Value<int> contadorActual;
  final Value<int> rowid;
  const CodigoSecuenciaCompanion({
    this.entityType = const Value.absent(),
    this.prefijo = const Value.absent(),
    this.digitos = const Value.absent(),
    this.reseteaAnualmente = const Value.absent(),
    this.anioActual = const Value.absent(),
    this.contadorActual = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CodigoSecuenciaCompanion.insert({
    required String entityType,
    required String prefijo,
    required int digitos,
    this.reseteaAnualmente = const Value.absent(),
    this.anioActual = const Value.absent(),
    this.contadorActual = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : entityType = Value(entityType),
       prefijo = Value(prefijo),
       digitos = Value(digitos);
  static Insertable<CodigoSecuenciaData> custom({
    Expression<String>? entityType,
    Expression<String>? prefijo,
    Expression<int>? digitos,
    Expression<bool>? reseteaAnualmente,
    Expression<int>? anioActual,
    Expression<int>? contadorActual,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (entityType != null) 'entity_type': entityType,
      if (prefijo != null) 'prefijo': prefijo,
      if (digitos != null) 'digitos': digitos,
      if (reseteaAnualmente != null) 'resetea_anualmente': reseteaAnualmente,
      if (anioActual != null) 'anio_actual': anioActual,
      if (contadorActual != null) 'contador_actual': contadorActual,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CodigoSecuenciaCompanion copyWith({
    Value<String>? entityType,
    Value<String>? prefijo,
    Value<int>? digitos,
    Value<bool>? reseteaAnualmente,
    Value<int?>? anioActual,
    Value<int>? contadorActual,
    Value<int>? rowid,
  }) {
    return CodigoSecuenciaCompanion(
      entityType: entityType ?? this.entityType,
      prefijo: prefijo ?? this.prefijo,
      digitos: digitos ?? this.digitos,
      reseteaAnualmente: reseteaAnualmente ?? this.reseteaAnualmente,
      anioActual: anioActual ?? this.anioActual,
      contadorActual: contadorActual ?? this.contadorActual,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (prefijo.present) {
      map['prefijo'] = Variable<String>(prefijo.value);
    }
    if (digitos.present) {
      map['digitos'] = Variable<int>(digitos.value);
    }
    if (reseteaAnualmente.present) {
      map['resetea_anualmente'] = Variable<bool>(reseteaAnualmente.value);
    }
    if (anioActual.present) {
      map['anio_actual'] = Variable<int>(anioActual.value);
    }
    if (contadorActual.present) {
      map['contador_actual'] = Variable<int>(contadorActual.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CodigoSecuenciaCompanion(')
          ..write('entityType: $entityType, ')
          ..write('prefijo: $prefijo, ')
          ..write('digitos: $digitos, ')
          ..write('reseteaAnualmente: $reseteaAnualmente, ')
          ..write('anioActual: $anioActual, ')
          ..write('contadorActual: $contadorActual, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TipoSucursalTable extends TipoSucursal
    with TableInfo<$TipoSucursalTable, TipoSucursalData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TipoSucursalTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _codigoMeta = const VerificationMeta('codigo');
  @override
  late final GeneratedColumn<String> codigo = GeneratedColumn<String>(
    'codigo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nombreMeta = const VerificationMeta('nombre');
  @override
  late final GeneratedColumn<String> nombre = GeneratedColumn<String>(
    'nombre',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descripcionMeta = const VerificationMeta(
    'descripcion',
  );
  @override
  late final GeneratedColumn<String> descripcion = GeneratedColumn<String>(
    'descripcion',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _activoMeta = const VerificationMeta('activo');
  @override
  late final GeneratedColumn<bool> activo = GeneratedColumn<bool>(
    'activo',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("activo" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _ordenMeta = const VerificationMeta('orden');
  @override
  late final GeneratedColumn<int> orden = GeneratedColumn<int>(
    'orden',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    codigo,
    nombre,
    descripcion,
    activo,
    orden,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tipo_sucursal';
  @override
  VerificationContext validateIntegrity(
    Insertable<TipoSucursalData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('codigo')) {
      context.handle(
        _codigoMeta,
        codigo.isAcceptableOrUnknown(data['codigo']!, _codigoMeta),
      );
    } else if (isInserting) {
      context.missing(_codigoMeta);
    }
    if (data.containsKey('nombre')) {
      context.handle(
        _nombreMeta,
        nombre.isAcceptableOrUnknown(data['nombre']!, _nombreMeta),
      );
    } else if (isInserting) {
      context.missing(_nombreMeta);
    }
    if (data.containsKey('descripcion')) {
      context.handle(
        _descripcionMeta,
        descripcion.isAcceptableOrUnknown(
          data['descripcion']!,
          _descripcionMeta,
        ),
      );
    }
    if (data.containsKey('activo')) {
      context.handle(
        _activoMeta,
        activo.isAcceptableOrUnknown(data['activo']!, _activoMeta),
      );
    }
    if (data.containsKey('orden')) {
      context.handle(
        _ordenMeta,
        orden.isAcceptableOrUnknown(data['orden']!, _ordenMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TipoSucursalData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TipoSucursalData(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}id'],
          )!,
      codigo:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}codigo'],
          )!,
      nombre:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}nombre'],
          )!,
      descripcion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}descripcion'],
      ),
      activo:
          attachedDatabase.typeMapping.read(
            DriftSqlType.bool,
            data['${effectivePrefix}activo'],
          )!,
      orden: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}orden'],
      ),
      createdAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}created_at'],
          )!,
      updatedAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}updated_at'],
          )!,
    );
  }

  @override
  $TipoSucursalTable createAlias(String alias) {
    return $TipoSucursalTable(attachedDatabase, alias);
  }
}

class TipoSucursalData extends DataClass
    implements Insertable<TipoSucursalData> {
  final String id;
  final String codigo;
  final String nombre;
  final String? descripcion;
  final bool activo;
  final int? orden;
  final DateTime createdAt;
  final DateTime updatedAt;
  const TipoSucursalData({
    required this.id,
    required this.codigo,
    required this.nombre,
    this.descripcion,
    required this.activo,
    this.orden,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['codigo'] = Variable<String>(codigo);
    map['nombre'] = Variable<String>(nombre);
    if (!nullToAbsent || descripcion != null) {
      map['descripcion'] = Variable<String>(descripcion);
    }
    map['activo'] = Variable<bool>(activo);
    if (!nullToAbsent || orden != null) {
      map['orden'] = Variable<int>(orden);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  TipoSucursalCompanion toCompanion(bool nullToAbsent) {
    return TipoSucursalCompanion(
      id: Value(id),
      codigo: Value(codigo),
      nombre: Value(nombre),
      descripcion:
          descripcion == null && nullToAbsent
              ? const Value.absent()
              : Value(descripcion),
      activo: Value(activo),
      orden:
          orden == null && nullToAbsent ? const Value.absent() : Value(orden),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory TipoSucursalData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TipoSucursalData(
      id: serializer.fromJson<String>(json['id']),
      codigo: serializer.fromJson<String>(json['codigo']),
      nombre: serializer.fromJson<String>(json['nombre']),
      descripcion: serializer.fromJson<String?>(json['descripcion']),
      activo: serializer.fromJson<bool>(json['activo']),
      orden: serializer.fromJson<int?>(json['orden']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'codigo': serializer.toJson<String>(codigo),
      'nombre': serializer.toJson<String>(nombre),
      'descripcion': serializer.toJson<String?>(descripcion),
      'activo': serializer.toJson<bool>(activo),
      'orden': serializer.toJson<int?>(orden),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  TipoSucursalData copyWith({
    String? id,
    String? codigo,
    String? nombre,
    Value<String?> descripcion = const Value.absent(),
    bool? activo,
    Value<int?> orden = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => TipoSucursalData(
    id: id ?? this.id,
    codigo: codigo ?? this.codigo,
    nombre: nombre ?? this.nombre,
    descripcion: descripcion.present ? descripcion.value : this.descripcion,
    activo: activo ?? this.activo,
    orden: orden.present ? orden.value : this.orden,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  TipoSucursalData copyWithCompanion(TipoSucursalCompanion data) {
    return TipoSucursalData(
      id: data.id.present ? data.id.value : this.id,
      codigo: data.codigo.present ? data.codigo.value : this.codigo,
      nombre: data.nombre.present ? data.nombre.value : this.nombre,
      descripcion:
          data.descripcion.present ? data.descripcion.value : this.descripcion,
      activo: data.activo.present ? data.activo.value : this.activo,
      orden: data.orden.present ? data.orden.value : this.orden,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TipoSucursalData(')
          ..write('id: $id, ')
          ..write('codigo: $codigo, ')
          ..write('nombre: $nombre, ')
          ..write('descripcion: $descripcion, ')
          ..write('activo: $activo, ')
          ..write('orden: $orden, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    codigo,
    nombre,
    descripcion,
    activo,
    orden,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TipoSucursalData &&
          other.id == this.id &&
          other.codigo == this.codigo &&
          other.nombre == this.nombre &&
          other.descripcion == this.descripcion &&
          other.activo == this.activo &&
          other.orden == this.orden &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class TipoSucursalCompanion extends UpdateCompanion<TipoSucursalData> {
  final Value<String> id;
  final Value<String> codigo;
  final Value<String> nombre;
  final Value<String?> descripcion;
  final Value<bool> activo;
  final Value<int?> orden;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const TipoSucursalCompanion({
    this.id = const Value.absent(),
    this.codigo = const Value.absent(),
    this.nombre = const Value.absent(),
    this.descripcion = const Value.absent(),
    this.activo = const Value.absent(),
    this.orden = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TipoSucursalCompanion.insert({
    required String id,
    required String codigo,
    required String nombre,
    this.descripcion = const Value.absent(),
    this.activo = const Value.absent(),
    this.orden = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       codigo = Value(codigo),
       nombre = Value(nombre);
  static Insertable<TipoSucursalData> custom({
    Expression<String>? id,
    Expression<String>? codigo,
    Expression<String>? nombre,
    Expression<String>? descripcion,
    Expression<bool>? activo,
    Expression<int>? orden,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (codigo != null) 'codigo': codigo,
      if (nombre != null) 'nombre': nombre,
      if (descripcion != null) 'descripcion': descripcion,
      if (activo != null) 'activo': activo,
      if (orden != null) 'orden': orden,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TipoSucursalCompanion copyWith({
    Value<String>? id,
    Value<String>? codigo,
    Value<String>? nombre,
    Value<String?>? descripcion,
    Value<bool>? activo,
    Value<int?>? orden,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return TipoSucursalCompanion(
      id: id ?? this.id,
      codigo: codigo ?? this.codigo,
      nombre: nombre ?? this.nombre,
      descripcion: descripcion ?? this.descripcion,
      activo: activo ?? this.activo,
      orden: orden ?? this.orden,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (codigo.present) {
      map['codigo'] = Variable<String>(codigo.value);
    }
    if (nombre.present) {
      map['nombre'] = Variable<String>(nombre.value);
    }
    if (descripcion.present) {
      map['descripcion'] = Variable<String>(descripcion.value);
    }
    if (activo.present) {
      map['activo'] = Variable<bool>(activo.value);
    }
    if (orden.present) {
      map['orden'] = Variable<int>(orden.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TipoSucursalCompanion(')
          ..write('id: $id, ')
          ..write('codigo: $codigo, ')
          ..write('nombre: $nombre, ')
          ..write('descripcion: $descripcion, ')
          ..write('activo: $activo, ')
          ..write('orden: $orden, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $IndustriaTable extends Industria
    with TableInfo<$IndustriaTable, IndustriaData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $IndustriaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _codigoMeta = const VerificationMeta('codigo');
  @override
  late final GeneratedColumn<String> codigo = GeneratedColumn<String>(
    'codigo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nombreMeta = const VerificationMeta('nombre');
  @override
  late final GeneratedColumn<String> nombre = GeneratedColumn<String>(
    'nombre',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descripcionMeta = const VerificationMeta(
    'descripcion',
  );
  @override
  late final GeneratedColumn<String> descripcion = GeneratedColumn<String>(
    'descripcion',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _activoMeta = const VerificationMeta('activo');
  @override
  late final GeneratedColumn<bool> activo = GeneratedColumn<bool>(
    'activo',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("activo" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _ordenMeta = const VerificationMeta('orden');
  @override
  late final GeneratedColumn<int> orden = GeneratedColumn<int>(
    'orden',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    codigo,
    nombre,
    descripcion,
    activo,
    orden,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'industria';
  @override
  VerificationContext validateIntegrity(
    Insertable<IndustriaData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('codigo')) {
      context.handle(
        _codigoMeta,
        codigo.isAcceptableOrUnknown(data['codigo']!, _codigoMeta),
      );
    } else if (isInserting) {
      context.missing(_codigoMeta);
    }
    if (data.containsKey('nombre')) {
      context.handle(
        _nombreMeta,
        nombre.isAcceptableOrUnknown(data['nombre']!, _nombreMeta),
      );
    } else if (isInserting) {
      context.missing(_nombreMeta);
    }
    if (data.containsKey('descripcion')) {
      context.handle(
        _descripcionMeta,
        descripcion.isAcceptableOrUnknown(
          data['descripcion']!,
          _descripcionMeta,
        ),
      );
    }
    if (data.containsKey('activo')) {
      context.handle(
        _activoMeta,
        activo.isAcceptableOrUnknown(data['activo']!, _activoMeta),
      );
    }
    if (data.containsKey('orden')) {
      context.handle(
        _ordenMeta,
        orden.isAcceptableOrUnknown(data['orden']!, _ordenMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  IndustriaData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return IndustriaData(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}id'],
          )!,
      codigo:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}codigo'],
          )!,
      nombre:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}nombre'],
          )!,
      descripcion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}descripcion'],
      ),
      activo:
          attachedDatabase.typeMapping.read(
            DriftSqlType.bool,
            data['${effectivePrefix}activo'],
          )!,
      orden: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}orden'],
      ),
      createdAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}created_at'],
          )!,
      updatedAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}updated_at'],
          )!,
    );
  }

  @override
  $IndustriaTable createAlias(String alias) {
    return $IndustriaTable(attachedDatabase, alias);
  }
}

class IndustriaData extends DataClass implements Insertable<IndustriaData> {
  final String id;
  final String codigo;
  final String nombre;
  final String? descripcion;
  final bool activo;
  final int? orden;
  final DateTime createdAt;
  final DateTime updatedAt;
  const IndustriaData({
    required this.id,
    required this.codigo,
    required this.nombre,
    this.descripcion,
    required this.activo,
    this.orden,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['codigo'] = Variable<String>(codigo);
    map['nombre'] = Variable<String>(nombre);
    if (!nullToAbsent || descripcion != null) {
      map['descripcion'] = Variable<String>(descripcion);
    }
    map['activo'] = Variable<bool>(activo);
    if (!nullToAbsent || orden != null) {
      map['orden'] = Variable<int>(orden);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  IndustriaCompanion toCompanion(bool nullToAbsent) {
    return IndustriaCompanion(
      id: Value(id),
      codigo: Value(codigo),
      nombre: Value(nombre),
      descripcion:
          descripcion == null && nullToAbsent
              ? const Value.absent()
              : Value(descripcion),
      activo: Value(activo),
      orden:
          orden == null && nullToAbsent ? const Value.absent() : Value(orden),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory IndustriaData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return IndustriaData(
      id: serializer.fromJson<String>(json['id']),
      codigo: serializer.fromJson<String>(json['codigo']),
      nombre: serializer.fromJson<String>(json['nombre']),
      descripcion: serializer.fromJson<String?>(json['descripcion']),
      activo: serializer.fromJson<bool>(json['activo']),
      orden: serializer.fromJson<int?>(json['orden']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'codigo': serializer.toJson<String>(codigo),
      'nombre': serializer.toJson<String>(nombre),
      'descripcion': serializer.toJson<String?>(descripcion),
      'activo': serializer.toJson<bool>(activo),
      'orden': serializer.toJson<int?>(orden),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  IndustriaData copyWith({
    String? id,
    String? codigo,
    String? nombre,
    Value<String?> descripcion = const Value.absent(),
    bool? activo,
    Value<int?> orden = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => IndustriaData(
    id: id ?? this.id,
    codigo: codigo ?? this.codigo,
    nombre: nombre ?? this.nombre,
    descripcion: descripcion.present ? descripcion.value : this.descripcion,
    activo: activo ?? this.activo,
    orden: orden.present ? orden.value : this.orden,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  IndustriaData copyWithCompanion(IndustriaCompanion data) {
    return IndustriaData(
      id: data.id.present ? data.id.value : this.id,
      codigo: data.codigo.present ? data.codigo.value : this.codigo,
      nombre: data.nombre.present ? data.nombre.value : this.nombre,
      descripcion:
          data.descripcion.present ? data.descripcion.value : this.descripcion,
      activo: data.activo.present ? data.activo.value : this.activo,
      orden: data.orden.present ? data.orden.value : this.orden,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('IndustriaData(')
          ..write('id: $id, ')
          ..write('codigo: $codigo, ')
          ..write('nombre: $nombre, ')
          ..write('descripcion: $descripcion, ')
          ..write('activo: $activo, ')
          ..write('orden: $orden, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    codigo,
    nombre,
    descripcion,
    activo,
    orden,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is IndustriaData &&
          other.id == this.id &&
          other.codigo == this.codigo &&
          other.nombre == this.nombre &&
          other.descripcion == this.descripcion &&
          other.activo == this.activo &&
          other.orden == this.orden &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class IndustriaCompanion extends UpdateCompanion<IndustriaData> {
  final Value<String> id;
  final Value<String> codigo;
  final Value<String> nombre;
  final Value<String?> descripcion;
  final Value<bool> activo;
  final Value<int?> orden;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const IndustriaCompanion({
    this.id = const Value.absent(),
    this.codigo = const Value.absent(),
    this.nombre = const Value.absent(),
    this.descripcion = const Value.absent(),
    this.activo = const Value.absent(),
    this.orden = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  IndustriaCompanion.insert({
    required String id,
    required String codigo,
    required String nombre,
    this.descripcion = const Value.absent(),
    this.activo = const Value.absent(),
    this.orden = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       codigo = Value(codigo),
       nombre = Value(nombre);
  static Insertable<IndustriaData> custom({
    Expression<String>? id,
    Expression<String>? codigo,
    Expression<String>? nombre,
    Expression<String>? descripcion,
    Expression<bool>? activo,
    Expression<int>? orden,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (codigo != null) 'codigo': codigo,
      if (nombre != null) 'nombre': nombre,
      if (descripcion != null) 'descripcion': descripcion,
      if (activo != null) 'activo': activo,
      if (orden != null) 'orden': orden,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  IndustriaCompanion copyWith({
    Value<String>? id,
    Value<String>? codigo,
    Value<String>? nombre,
    Value<String?>? descripcion,
    Value<bool>? activo,
    Value<int?>? orden,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return IndustriaCompanion(
      id: id ?? this.id,
      codigo: codigo ?? this.codigo,
      nombre: nombre ?? this.nombre,
      descripcion: descripcion ?? this.descripcion,
      activo: activo ?? this.activo,
      orden: orden ?? this.orden,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (codigo.present) {
      map['codigo'] = Variable<String>(codigo.value);
    }
    if (nombre.present) {
      map['nombre'] = Variable<String>(nombre.value);
    }
    if (descripcion.present) {
      map['descripcion'] = Variable<String>(descripcion.value);
    }
    if (activo.present) {
      map['activo'] = Variable<bool>(activo.value);
    }
    if (orden.present) {
      map['orden'] = Variable<int>(orden.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('IndustriaCompanion(')
          ..write('id: $id, ')
          ..write('codigo: $codigo, ')
          ..write('nombre: $nombre, ')
          ..write('descripcion: $descripcion, ')
          ..write('activo: $activo, ')
          ..write('orden: $orden, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TipoServicioTable extends TipoServicio
    with TableInfo<$TipoServicioTable, TipoServicioData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TipoServicioTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _codigoMeta = const VerificationMeta('codigo');
  @override
  late final GeneratedColumn<String> codigo = GeneratedColumn<String>(
    'codigo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nombreMeta = const VerificationMeta('nombre');
  @override
  late final GeneratedColumn<String> nombre = GeneratedColumn<String>(
    'nombre',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descripcionMeta = const VerificationMeta(
    'descripcion',
  );
  @override
  late final GeneratedColumn<String> descripcion = GeneratedColumn<String>(
    'descripcion',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _activoMeta = const VerificationMeta('activo');
  @override
  late final GeneratedColumn<bool> activo = GeneratedColumn<bool>(
    'activo',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("activo" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _ordenMeta = const VerificationMeta('orden');
  @override
  late final GeneratedColumn<int> orden = GeneratedColumn<int>(
    'orden',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    codigo,
    nombre,
    descripcion,
    activo,
    orden,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tipo_servicio';
  @override
  VerificationContext validateIntegrity(
    Insertable<TipoServicioData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('codigo')) {
      context.handle(
        _codigoMeta,
        codigo.isAcceptableOrUnknown(data['codigo']!, _codigoMeta),
      );
    } else if (isInserting) {
      context.missing(_codigoMeta);
    }
    if (data.containsKey('nombre')) {
      context.handle(
        _nombreMeta,
        nombre.isAcceptableOrUnknown(data['nombre']!, _nombreMeta),
      );
    } else if (isInserting) {
      context.missing(_nombreMeta);
    }
    if (data.containsKey('descripcion')) {
      context.handle(
        _descripcionMeta,
        descripcion.isAcceptableOrUnknown(
          data['descripcion']!,
          _descripcionMeta,
        ),
      );
    }
    if (data.containsKey('activo')) {
      context.handle(
        _activoMeta,
        activo.isAcceptableOrUnknown(data['activo']!, _activoMeta),
      );
    }
    if (data.containsKey('orden')) {
      context.handle(
        _ordenMeta,
        orden.isAcceptableOrUnknown(data['orden']!, _ordenMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TipoServicioData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TipoServicioData(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}id'],
          )!,
      codigo:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}codigo'],
          )!,
      nombre:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}nombre'],
          )!,
      descripcion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}descripcion'],
      ),
      activo:
          attachedDatabase.typeMapping.read(
            DriftSqlType.bool,
            data['${effectivePrefix}activo'],
          )!,
      orden: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}orden'],
      ),
      createdAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}created_at'],
          )!,
      updatedAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}updated_at'],
          )!,
    );
  }

  @override
  $TipoServicioTable createAlias(String alias) {
    return $TipoServicioTable(attachedDatabase, alias);
  }
}

class TipoServicioData extends DataClass
    implements Insertable<TipoServicioData> {
  final String id;
  final String codigo;
  final String nombre;
  final String? descripcion;
  final bool activo;
  final int? orden;
  final DateTime createdAt;
  final DateTime updatedAt;
  const TipoServicioData({
    required this.id,
    required this.codigo,
    required this.nombre,
    this.descripcion,
    required this.activo,
    this.orden,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['codigo'] = Variable<String>(codigo);
    map['nombre'] = Variable<String>(nombre);
    if (!nullToAbsent || descripcion != null) {
      map['descripcion'] = Variable<String>(descripcion);
    }
    map['activo'] = Variable<bool>(activo);
    if (!nullToAbsent || orden != null) {
      map['orden'] = Variable<int>(orden);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  TipoServicioCompanion toCompanion(bool nullToAbsent) {
    return TipoServicioCompanion(
      id: Value(id),
      codigo: Value(codigo),
      nombre: Value(nombre),
      descripcion:
          descripcion == null && nullToAbsent
              ? const Value.absent()
              : Value(descripcion),
      activo: Value(activo),
      orden:
          orden == null && nullToAbsent ? const Value.absent() : Value(orden),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory TipoServicioData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TipoServicioData(
      id: serializer.fromJson<String>(json['id']),
      codigo: serializer.fromJson<String>(json['codigo']),
      nombre: serializer.fromJson<String>(json['nombre']),
      descripcion: serializer.fromJson<String?>(json['descripcion']),
      activo: serializer.fromJson<bool>(json['activo']),
      orden: serializer.fromJson<int?>(json['orden']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'codigo': serializer.toJson<String>(codigo),
      'nombre': serializer.toJson<String>(nombre),
      'descripcion': serializer.toJson<String?>(descripcion),
      'activo': serializer.toJson<bool>(activo),
      'orden': serializer.toJson<int?>(orden),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  TipoServicioData copyWith({
    String? id,
    String? codigo,
    String? nombre,
    Value<String?> descripcion = const Value.absent(),
    bool? activo,
    Value<int?> orden = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => TipoServicioData(
    id: id ?? this.id,
    codigo: codigo ?? this.codigo,
    nombre: nombre ?? this.nombre,
    descripcion: descripcion.present ? descripcion.value : this.descripcion,
    activo: activo ?? this.activo,
    orden: orden.present ? orden.value : this.orden,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  TipoServicioData copyWithCompanion(TipoServicioCompanion data) {
    return TipoServicioData(
      id: data.id.present ? data.id.value : this.id,
      codigo: data.codigo.present ? data.codigo.value : this.codigo,
      nombre: data.nombre.present ? data.nombre.value : this.nombre,
      descripcion:
          data.descripcion.present ? data.descripcion.value : this.descripcion,
      activo: data.activo.present ? data.activo.value : this.activo,
      orden: data.orden.present ? data.orden.value : this.orden,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TipoServicioData(')
          ..write('id: $id, ')
          ..write('codigo: $codigo, ')
          ..write('nombre: $nombre, ')
          ..write('descripcion: $descripcion, ')
          ..write('activo: $activo, ')
          ..write('orden: $orden, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    codigo,
    nombre,
    descripcion,
    activo,
    orden,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TipoServicioData &&
          other.id == this.id &&
          other.codigo == this.codigo &&
          other.nombre == this.nombre &&
          other.descripcion == this.descripcion &&
          other.activo == this.activo &&
          other.orden == this.orden &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class TipoServicioCompanion extends UpdateCompanion<TipoServicioData> {
  final Value<String> id;
  final Value<String> codigo;
  final Value<String> nombre;
  final Value<String?> descripcion;
  final Value<bool> activo;
  final Value<int?> orden;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const TipoServicioCompanion({
    this.id = const Value.absent(),
    this.codigo = const Value.absent(),
    this.nombre = const Value.absent(),
    this.descripcion = const Value.absent(),
    this.activo = const Value.absent(),
    this.orden = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TipoServicioCompanion.insert({
    required String id,
    required String codigo,
    required String nombre,
    this.descripcion = const Value.absent(),
    this.activo = const Value.absent(),
    this.orden = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       codigo = Value(codigo),
       nombre = Value(nombre);
  static Insertable<TipoServicioData> custom({
    Expression<String>? id,
    Expression<String>? codigo,
    Expression<String>? nombre,
    Expression<String>? descripcion,
    Expression<bool>? activo,
    Expression<int>? orden,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (codigo != null) 'codigo': codigo,
      if (nombre != null) 'nombre': nombre,
      if (descripcion != null) 'descripcion': descripcion,
      if (activo != null) 'activo': activo,
      if (orden != null) 'orden': orden,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TipoServicioCompanion copyWith({
    Value<String>? id,
    Value<String>? codigo,
    Value<String>? nombre,
    Value<String?>? descripcion,
    Value<bool>? activo,
    Value<int?>? orden,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return TipoServicioCompanion(
      id: id ?? this.id,
      codigo: codigo ?? this.codigo,
      nombre: nombre ?? this.nombre,
      descripcion: descripcion ?? this.descripcion,
      activo: activo ?? this.activo,
      orden: orden ?? this.orden,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (codigo.present) {
      map['codigo'] = Variable<String>(codigo.value);
    }
    if (nombre.present) {
      map['nombre'] = Variable<String>(nombre.value);
    }
    if (descripcion.present) {
      map['descripcion'] = Variable<String>(descripcion.value);
    }
    if (activo.present) {
      map['activo'] = Variable<bool>(activo.value);
    }
    if (orden.present) {
      map['orden'] = Variable<int>(orden.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TipoServicioCompanion(')
          ..write('id: $id, ')
          ..write('codigo: $codigo, ')
          ..write('nombre: $nombre, ')
          ..write('descripcion: $descripcion, ')
          ..write('activo: $activo, ')
          ..write('orden: $orden, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AreaTable extends Area with TableInfo<$AreaTable, AreaData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AreaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _codigoMeta = const VerificationMeta('codigo');
  @override
  late final GeneratedColumn<String> codigo = GeneratedColumn<String>(
    'codigo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nombreMeta = const VerificationMeta('nombre');
  @override
  late final GeneratedColumn<String> nombre = GeneratedColumn<String>(
    'nombre',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descripcionMeta = const VerificationMeta(
    'descripcion',
  );
  @override
  late final GeneratedColumn<String> descripcion = GeneratedColumn<String>(
    'descripcion',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _activoMeta = const VerificationMeta('activo');
  @override
  late final GeneratedColumn<bool> activo = GeneratedColumn<bool>(
    'activo',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("activo" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _ordenMeta = const VerificationMeta('orden');
  @override
  late final GeneratedColumn<int> orden = GeneratedColumn<int>(
    'orden',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    codigo,
    nombre,
    descripcion,
    activo,
    orden,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'area';
  @override
  VerificationContext validateIntegrity(
    Insertable<AreaData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('codigo')) {
      context.handle(
        _codigoMeta,
        codigo.isAcceptableOrUnknown(data['codigo']!, _codigoMeta),
      );
    } else if (isInserting) {
      context.missing(_codigoMeta);
    }
    if (data.containsKey('nombre')) {
      context.handle(
        _nombreMeta,
        nombre.isAcceptableOrUnknown(data['nombre']!, _nombreMeta),
      );
    } else if (isInserting) {
      context.missing(_nombreMeta);
    }
    if (data.containsKey('descripcion')) {
      context.handle(
        _descripcionMeta,
        descripcion.isAcceptableOrUnknown(
          data['descripcion']!,
          _descripcionMeta,
        ),
      );
    }
    if (data.containsKey('activo')) {
      context.handle(
        _activoMeta,
        activo.isAcceptableOrUnknown(data['activo']!, _activoMeta),
      );
    }
    if (data.containsKey('orden')) {
      context.handle(
        _ordenMeta,
        orden.isAcceptableOrUnknown(data['orden']!, _ordenMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AreaData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AreaData(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}id'],
          )!,
      codigo:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}codigo'],
          )!,
      nombre:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}nombre'],
          )!,
      descripcion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}descripcion'],
      ),
      activo:
          attachedDatabase.typeMapping.read(
            DriftSqlType.bool,
            data['${effectivePrefix}activo'],
          )!,
      orden: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}orden'],
      ),
      createdAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}created_at'],
          )!,
      updatedAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}updated_at'],
          )!,
    );
  }

  @override
  $AreaTable createAlias(String alias) {
    return $AreaTable(attachedDatabase, alias);
  }
}

class AreaData extends DataClass implements Insertable<AreaData> {
  final String id;
  final String codigo;
  final String nombre;
  final String? descripcion;
  final bool activo;
  final int? orden;
  final DateTime createdAt;
  final DateTime updatedAt;
  const AreaData({
    required this.id,
    required this.codigo,
    required this.nombre,
    this.descripcion,
    required this.activo,
    this.orden,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['codigo'] = Variable<String>(codigo);
    map['nombre'] = Variable<String>(nombre);
    if (!nullToAbsent || descripcion != null) {
      map['descripcion'] = Variable<String>(descripcion);
    }
    map['activo'] = Variable<bool>(activo);
    if (!nullToAbsent || orden != null) {
      map['orden'] = Variable<int>(orden);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  AreaCompanion toCompanion(bool nullToAbsent) {
    return AreaCompanion(
      id: Value(id),
      codigo: Value(codigo),
      nombre: Value(nombre),
      descripcion:
          descripcion == null && nullToAbsent
              ? const Value.absent()
              : Value(descripcion),
      activo: Value(activo),
      orden:
          orden == null && nullToAbsent ? const Value.absent() : Value(orden),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory AreaData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AreaData(
      id: serializer.fromJson<String>(json['id']),
      codigo: serializer.fromJson<String>(json['codigo']),
      nombre: serializer.fromJson<String>(json['nombre']),
      descripcion: serializer.fromJson<String?>(json['descripcion']),
      activo: serializer.fromJson<bool>(json['activo']),
      orden: serializer.fromJson<int?>(json['orden']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'codigo': serializer.toJson<String>(codigo),
      'nombre': serializer.toJson<String>(nombre),
      'descripcion': serializer.toJson<String?>(descripcion),
      'activo': serializer.toJson<bool>(activo),
      'orden': serializer.toJson<int?>(orden),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  AreaData copyWith({
    String? id,
    String? codigo,
    String? nombre,
    Value<String?> descripcion = const Value.absent(),
    bool? activo,
    Value<int?> orden = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => AreaData(
    id: id ?? this.id,
    codigo: codigo ?? this.codigo,
    nombre: nombre ?? this.nombre,
    descripcion: descripcion.present ? descripcion.value : this.descripcion,
    activo: activo ?? this.activo,
    orden: orden.present ? orden.value : this.orden,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  AreaData copyWithCompanion(AreaCompanion data) {
    return AreaData(
      id: data.id.present ? data.id.value : this.id,
      codigo: data.codigo.present ? data.codigo.value : this.codigo,
      nombre: data.nombre.present ? data.nombre.value : this.nombre,
      descripcion:
          data.descripcion.present ? data.descripcion.value : this.descripcion,
      activo: data.activo.present ? data.activo.value : this.activo,
      orden: data.orden.present ? data.orden.value : this.orden,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AreaData(')
          ..write('id: $id, ')
          ..write('codigo: $codigo, ')
          ..write('nombre: $nombre, ')
          ..write('descripcion: $descripcion, ')
          ..write('activo: $activo, ')
          ..write('orden: $orden, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    codigo,
    nombre,
    descripcion,
    activo,
    orden,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AreaData &&
          other.id == this.id &&
          other.codigo == this.codigo &&
          other.nombre == this.nombre &&
          other.descripcion == this.descripcion &&
          other.activo == this.activo &&
          other.orden == this.orden &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class AreaCompanion extends UpdateCompanion<AreaData> {
  final Value<String> id;
  final Value<String> codigo;
  final Value<String> nombre;
  final Value<String?> descripcion;
  final Value<bool> activo;
  final Value<int?> orden;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const AreaCompanion({
    this.id = const Value.absent(),
    this.codigo = const Value.absent(),
    this.nombre = const Value.absent(),
    this.descripcion = const Value.absent(),
    this.activo = const Value.absent(),
    this.orden = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AreaCompanion.insert({
    required String id,
    required String codigo,
    required String nombre,
    this.descripcion = const Value.absent(),
    this.activo = const Value.absent(),
    this.orden = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       codigo = Value(codigo),
       nombre = Value(nombre);
  static Insertable<AreaData> custom({
    Expression<String>? id,
    Expression<String>? codigo,
    Expression<String>? nombre,
    Expression<String>? descripcion,
    Expression<bool>? activo,
    Expression<int>? orden,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (codigo != null) 'codigo': codigo,
      if (nombre != null) 'nombre': nombre,
      if (descripcion != null) 'descripcion': descripcion,
      if (activo != null) 'activo': activo,
      if (orden != null) 'orden': orden,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AreaCompanion copyWith({
    Value<String>? id,
    Value<String>? codigo,
    Value<String>? nombre,
    Value<String?>? descripcion,
    Value<bool>? activo,
    Value<int?>? orden,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return AreaCompanion(
      id: id ?? this.id,
      codigo: codigo ?? this.codigo,
      nombre: nombre ?? this.nombre,
      descripcion: descripcion ?? this.descripcion,
      activo: activo ?? this.activo,
      orden: orden ?? this.orden,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (codigo.present) {
      map['codigo'] = Variable<String>(codigo.value);
    }
    if (nombre.present) {
      map['nombre'] = Variable<String>(nombre.value);
    }
    if (descripcion.present) {
      map['descripcion'] = Variable<String>(descripcion.value);
    }
    if (activo.present) {
      map['activo'] = Variable<bool>(activo.value);
    }
    if (orden.present) {
      map['orden'] = Variable<int>(orden.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AreaCompanion(')
          ..write('id: $id, ')
          ..write('codigo: $codigo, ')
          ..write('nombre: $nombre, ')
          ..write('descripcion: $descripcion, ')
          ..write('activo: $activo, ')
          ..write('orden: $orden, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DireccionTable extends Direccion
    with TableInfo<$DireccionTable, DireccionData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DireccionTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: () => const Uuid().v4(),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _cicloVidaRegistroMeta = const VerificationMeta(
    'cicloVidaRegistro',
  );
  @override
  late final GeneratedColumn<String> cicloVidaRegistro =
      GeneratedColumn<String>(
        'ciclo_vida_registro',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('activo'),
      );
  static const VerificationMeta _empresaIdMeta = const VerificationMeta(
    'empresaId',
  );
  @override
  late final GeneratedColumn<String> empresaId = GeneratedColumn<String>(
    'empresa_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _sucursalIdMeta = const VerificationMeta(
    'sucursalId',
  );
  @override
  late final GeneratedColumn<String> sucursalId = GeneratedColumn<String>(
    'sucursal_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _clienteIdMeta = const VerificationMeta(
    'clienteId',
  );
  @override
  late final GeneratedColumn<String> clienteId = GeneratedColumn<String>(
    'cliente_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _servicioIdMeta = const VerificationMeta(
    'servicioId',
  );
  @override
  late final GeneratedColumn<String> servicioId = GeneratedColumn<String>(
    'servicio_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _tipoDireccionMeta = const VerificationMeta(
    'tipoDireccion',
  );
  @override
  late final GeneratedColumn<String> tipoDireccion = GeneratedColumn<String>(
    'tipo_direccion',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _esPrincipalMeta = const VerificationMeta(
    'esPrincipal',
  );
  @override
  late final GeneratedColumn<bool> esPrincipal = GeneratedColumn<bool>(
    'es_principal',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("es_principal" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _calleMeta = const VerificationMeta('calle');
  @override
  late final GeneratedColumn<String> calle = GeneratedColumn<String>(
    'calle',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _numeroExteriorMeta = const VerificationMeta(
    'numeroExterior',
  );
  @override
  late final GeneratedColumn<String> numeroExterior = GeneratedColumn<String>(
    'numero_exterior',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _numeroInteriorMeta = const VerificationMeta(
    'numeroInterior',
  );
  @override
  late final GeneratedColumn<String> numeroInterior = GeneratedColumn<String>(
    'numero_interior',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _coloniaMeta = const VerificationMeta(
    'colonia',
  );
  @override
  late final GeneratedColumn<String> colonia = GeneratedColumn<String>(
    'colonia',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _municipioAlcaldiaMeta = const VerificationMeta(
    'municipioAlcaldia',
  );
  @override
  late final GeneratedColumn<String> municipioAlcaldia =
      GeneratedColumn<String>(
        'municipio_alcaldia',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _ciudadLocalidadMeta = const VerificationMeta(
    'ciudadLocalidad',
  );
  @override
  late final GeneratedColumn<String> ciudadLocalidad = GeneratedColumn<String>(
    'ciudad_localidad',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _estadoMeta = const VerificationMeta('estado');
  @override
  late final GeneratedColumn<String> estado = GeneratedColumn<String>(
    'estado',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _codigoPostalMeta = const VerificationMeta(
    'codigoPostal',
  );
  @override
  late final GeneratedColumn<String> codigoPostal = GeneratedColumn<String>(
    'codigo_postal',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _paisMeta = const VerificationMeta('pais');
  @override
  late final GeneratedColumn<String> pais = GeneratedColumn<String>(
    'pais',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('México'),
  );
  static const VerificationMeta _referenciasMeta = const VerificationMeta(
    'referencias',
  );
  @override
  late final GeneratedColumn<String> referencias = GeneratedColumn<String>(
    'referencias',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    createdAt,
    updatedAt,
    cicloVidaRegistro,
    empresaId,
    sucursalId,
    clienteId,
    servicioId,
    tipoDireccion,
    esPrincipal,
    calle,
    numeroExterior,
    numeroInterior,
    colonia,
    municipioAlcaldia,
    ciudadLocalidad,
    estado,
    codigoPostal,
    pais,
    referencias,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'direccion';
  @override
  VerificationContext validateIntegrity(
    Insertable<DireccionData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('ciclo_vida_registro')) {
      context.handle(
        _cicloVidaRegistroMeta,
        cicloVidaRegistro.isAcceptableOrUnknown(
          data['ciclo_vida_registro']!,
          _cicloVidaRegistroMeta,
        ),
      );
    }
    if (data.containsKey('empresa_id')) {
      context.handle(
        _empresaIdMeta,
        empresaId.isAcceptableOrUnknown(data['empresa_id']!, _empresaIdMeta),
      );
    }
    if (data.containsKey('sucursal_id')) {
      context.handle(
        _sucursalIdMeta,
        sucursalId.isAcceptableOrUnknown(data['sucursal_id']!, _sucursalIdMeta),
      );
    }
    if (data.containsKey('cliente_id')) {
      context.handle(
        _clienteIdMeta,
        clienteId.isAcceptableOrUnknown(data['cliente_id']!, _clienteIdMeta),
      );
    }
    if (data.containsKey('servicio_id')) {
      context.handle(
        _servicioIdMeta,
        servicioId.isAcceptableOrUnknown(data['servicio_id']!, _servicioIdMeta),
      );
    }
    if (data.containsKey('tipo_direccion')) {
      context.handle(
        _tipoDireccionMeta,
        tipoDireccion.isAcceptableOrUnknown(
          data['tipo_direccion']!,
          _tipoDireccionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_tipoDireccionMeta);
    }
    if (data.containsKey('es_principal')) {
      context.handle(
        _esPrincipalMeta,
        esPrincipal.isAcceptableOrUnknown(
          data['es_principal']!,
          _esPrincipalMeta,
        ),
      );
    }
    if (data.containsKey('calle')) {
      context.handle(
        _calleMeta,
        calle.isAcceptableOrUnknown(data['calle']!, _calleMeta),
      );
    } else if (isInserting) {
      context.missing(_calleMeta);
    }
    if (data.containsKey('numero_exterior')) {
      context.handle(
        _numeroExteriorMeta,
        numeroExterior.isAcceptableOrUnknown(
          data['numero_exterior']!,
          _numeroExteriorMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_numeroExteriorMeta);
    }
    if (data.containsKey('numero_interior')) {
      context.handle(
        _numeroInteriorMeta,
        numeroInterior.isAcceptableOrUnknown(
          data['numero_interior']!,
          _numeroInteriorMeta,
        ),
      );
    }
    if (data.containsKey('colonia')) {
      context.handle(
        _coloniaMeta,
        colonia.isAcceptableOrUnknown(data['colonia']!, _coloniaMeta),
      );
    } else if (isInserting) {
      context.missing(_coloniaMeta);
    }
    if (data.containsKey('municipio_alcaldia')) {
      context.handle(
        _municipioAlcaldiaMeta,
        municipioAlcaldia.isAcceptableOrUnknown(
          data['municipio_alcaldia']!,
          _municipioAlcaldiaMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_municipioAlcaldiaMeta);
    }
    if (data.containsKey('ciudad_localidad')) {
      context.handle(
        _ciudadLocalidadMeta,
        ciudadLocalidad.isAcceptableOrUnknown(
          data['ciudad_localidad']!,
          _ciudadLocalidadMeta,
        ),
      );
    }
    if (data.containsKey('estado')) {
      context.handle(
        _estadoMeta,
        estado.isAcceptableOrUnknown(data['estado']!, _estadoMeta),
      );
    } else if (isInserting) {
      context.missing(_estadoMeta);
    }
    if (data.containsKey('codigo_postal')) {
      context.handle(
        _codigoPostalMeta,
        codigoPostal.isAcceptableOrUnknown(
          data['codigo_postal']!,
          _codigoPostalMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_codigoPostalMeta);
    }
    if (data.containsKey('pais')) {
      context.handle(
        _paisMeta,
        pais.isAcceptableOrUnknown(data['pais']!, _paisMeta),
      );
    }
    if (data.containsKey('referencias')) {
      context.handle(
        _referenciasMeta,
        referencias.isAcceptableOrUnknown(
          data['referencias']!,
          _referenciasMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DireccionData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DireccionData(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}id'],
          )!,
      createdAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}created_at'],
          )!,
      updatedAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}updated_at'],
          )!,
      cicloVidaRegistro:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}ciclo_vida_registro'],
          )!,
      empresaId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}empresa_id'],
      ),
      sucursalId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sucursal_id'],
      ),
      clienteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cliente_id'],
      ),
      servicioId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}servicio_id'],
      ),
      tipoDireccion:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}tipo_direccion'],
          )!,
      esPrincipal:
          attachedDatabase.typeMapping.read(
            DriftSqlType.bool,
            data['${effectivePrefix}es_principal'],
          )!,
      calle:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}calle'],
          )!,
      numeroExterior:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}numero_exterior'],
          )!,
      numeroInterior: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}numero_interior'],
      ),
      colonia:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}colonia'],
          )!,
      municipioAlcaldia:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}municipio_alcaldia'],
          )!,
      ciudadLocalidad: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ciudad_localidad'],
      ),
      estado:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}estado'],
          )!,
      codigoPostal:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}codigo_postal'],
          )!,
      pais:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}pais'],
          )!,
      referencias: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}referencias'],
      ),
    );
  }

  @override
  $DireccionTable createAlias(String alias) {
    return $DireccionTable(attachedDatabase, alias);
  }
}

class DireccionData extends DataClass implements Insertable<DireccionData> {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String cicloVidaRegistro;
  final String? empresaId;
  final String? sucursalId;
  final String? clienteId;
  final String? servicioId;
  final String tipoDireccion;
  final bool esPrincipal;
  final String calle;
  final String numeroExterior;
  final String? numeroInterior;
  final String colonia;
  final String municipioAlcaldia;
  final String? ciudadLocalidad;
  final String estado;
  final String codigoPostal;
  final String pais;
  final String? referencias;
  const DireccionData({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required this.cicloVidaRegistro,
    this.empresaId,
    this.sucursalId,
    this.clienteId,
    this.servicioId,
    required this.tipoDireccion,
    required this.esPrincipal,
    required this.calle,
    required this.numeroExterior,
    this.numeroInterior,
    required this.colonia,
    required this.municipioAlcaldia,
    this.ciudadLocalidad,
    required this.estado,
    required this.codigoPostal,
    required this.pais,
    this.referencias,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['ciclo_vida_registro'] = Variable<String>(cicloVidaRegistro);
    if (!nullToAbsent || empresaId != null) {
      map['empresa_id'] = Variable<String>(empresaId);
    }
    if (!nullToAbsent || sucursalId != null) {
      map['sucursal_id'] = Variable<String>(sucursalId);
    }
    if (!nullToAbsent || clienteId != null) {
      map['cliente_id'] = Variable<String>(clienteId);
    }
    if (!nullToAbsent || servicioId != null) {
      map['servicio_id'] = Variable<String>(servicioId);
    }
    map['tipo_direccion'] = Variable<String>(tipoDireccion);
    map['es_principal'] = Variable<bool>(esPrincipal);
    map['calle'] = Variable<String>(calle);
    map['numero_exterior'] = Variable<String>(numeroExterior);
    if (!nullToAbsent || numeroInterior != null) {
      map['numero_interior'] = Variable<String>(numeroInterior);
    }
    map['colonia'] = Variable<String>(colonia);
    map['municipio_alcaldia'] = Variable<String>(municipioAlcaldia);
    if (!nullToAbsent || ciudadLocalidad != null) {
      map['ciudad_localidad'] = Variable<String>(ciudadLocalidad);
    }
    map['estado'] = Variable<String>(estado);
    map['codigo_postal'] = Variable<String>(codigoPostal);
    map['pais'] = Variable<String>(pais);
    if (!nullToAbsent || referencias != null) {
      map['referencias'] = Variable<String>(referencias);
    }
    return map;
  }

  DireccionCompanion toCompanion(bool nullToAbsent) {
    return DireccionCompanion(
      id: Value(id),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      cicloVidaRegistro: Value(cicloVidaRegistro),
      empresaId:
          empresaId == null && nullToAbsent
              ? const Value.absent()
              : Value(empresaId),
      sucursalId:
          sucursalId == null && nullToAbsent
              ? const Value.absent()
              : Value(sucursalId),
      clienteId:
          clienteId == null && nullToAbsent
              ? const Value.absent()
              : Value(clienteId),
      servicioId:
          servicioId == null && nullToAbsent
              ? const Value.absent()
              : Value(servicioId),
      tipoDireccion: Value(tipoDireccion),
      esPrincipal: Value(esPrincipal),
      calle: Value(calle),
      numeroExterior: Value(numeroExterior),
      numeroInterior:
          numeroInterior == null && nullToAbsent
              ? const Value.absent()
              : Value(numeroInterior),
      colonia: Value(colonia),
      municipioAlcaldia: Value(municipioAlcaldia),
      ciudadLocalidad:
          ciudadLocalidad == null && nullToAbsent
              ? const Value.absent()
              : Value(ciudadLocalidad),
      estado: Value(estado),
      codigoPostal: Value(codigoPostal),
      pais: Value(pais),
      referencias:
          referencias == null && nullToAbsent
              ? const Value.absent()
              : Value(referencias),
    );
  }

  factory DireccionData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DireccionData(
      id: serializer.fromJson<String>(json['id']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      cicloVidaRegistro: serializer.fromJson<String>(json['cicloVidaRegistro']),
      empresaId: serializer.fromJson<String?>(json['empresaId']),
      sucursalId: serializer.fromJson<String?>(json['sucursalId']),
      clienteId: serializer.fromJson<String?>(json['clienteId']),
      servicioId: serializer.fromJson<String?>(json['servicioId']),
      tipoDireccion: serializer.fromJson<String>(json['tipoDireccion']),
      esPrincipal: serializer.fromJson<bool>(json['esPrincipal']),
      calle: serializer.fromJson<String>(json['calle']),
      numeroExterior: serializer.fromJson<String>(json['numeroExterior']),
      numeroInterior: serializer.fromJson<String?>(json['numeroInterior']),
      colonia: serializer.fromJson<String>(json['colonia']),
      municipioAlcaldia: serializer.fromJson<String>(json['municipioAlcaldia']),
      ciudadLocalidad: serializer.fromJson<String?>(json['ciudadLocalidad']),
      estado: serializer.fromJson<String>(json['estado']),
      codigoPostal: serializer.fromJson<String>(json['codigoPostal']),
      pais: serializer.fromJson<String>(json['pais']),
      referencias: serializer.fromJson<String?>(json['referencias']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'cicloVidaRegistro': serializer.toJson<String>(cicloVidaRegistro),
      'empresaId': serializer.toJson<String?>(empresaId),
      'sucursalId': serializer.toJson<String?>(sucursalId),
      'clienteId': serializer.toJson<String?>(clienteId),
      'servicioId': serializer.toJson<String?>(servicioId),
      'tipoDireccion': serializer.toJson<String>(tipoDireccion),
      'esPrincipal': serializer.toJson<bool>(esPrincipal),
      'calle': serializer.toJson<String>(calle),
      'numeroExterior': serializer.toJson<String>(numeroExterior),
      'numeroInterior': serializer.toJson<String?>(numeroInterior),
      'colonia': serializer.toJson<String>(colonia),
      'municipioAlcaldia': serializer.toJson<String>(municipioAlcaldia),
      'ciudadLocalidad': serializer.toJson<String?>(ciudadLocalidad),
      'estado': serializer.toJson<String>(estado),
      'codigoPostal': serializer.toJson<String>(codigoPostal),
      'pais': serializer.toJson<String>(pais),
      'referencias': serializer.toJson<String?>(referencias),
    };
  }

  DireccionData copyWith({
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? cicloVidaRegistro,
    Value<String?> empresaId = const Value.absent(),
    Value<String?> sucursalId = const Value.absent(),
    Value<String?> clienteId = const Value.absent(),
    Value<String?> servicioId = const Value.absent(),
    String? tipoDireccion,
    bool? esPrincipal,
    String? calle,
    String? numeroExterior,
    Value<String?> numeroInterior = const Value.absent(),
    String? colonia,
    String? municipioAlcaldia,
    Value<String?> ciudadLocalidad = const Value.absent(),
    String? estado,
    String? codigoPostal,
    String? pais,
    Value<String?> referencias = const Value.absent(),
  }) => DireccionData(
    id: id ?? this.id,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    cicloVidaRegistro: cicloVidaRegistro ?? this.cicloVidaRegistro,
    empresaId: empresaId.present ? empresaId.value : this.empresaId,
    sucursalId: sucursalId.present ? sucursalId.value : this.sucursalId,
    clienteId: clienteId.present ? clienteId.value : this.clienteId,
    servicioId: servicioId.present ? servicioId.value : this.servicioId,
    tipoDireccion: tipoDireccion ?? this.tipoDireccion,
    esPrincipal: esPrincipal ?? this.esPrincipal,
    calle: calle ?? this.calle,
    numeroExterior: numeroExterior ?? this.numeroExterior,
    numeroInterior:
        numeroInterior.present ? numeroInterior.value : this.numeroInterior,
    colonia: colonia ?? this.colonia,
    municipioAlcaldia: municipioAlcaldia ?? this.municipioAlcaldia,
    ciudadLocalidad:
        ciudadLocalidad.present ? ciudadLocalidad.value : this.ciudadLocalidad,
    estado: estado ?? this.estado,
    codigoPostal: codigoPostal ?? this.codigoPostal,
    pais: pais ?? this.pais,
    referencias: referencias.present ? referencias.value : this.referencias,
  );
  DireccionData copyWithCompanion(DireccionCompanion data) {
    return DireccionData(
      id: data.id.present ? data.id.value : this.id,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      cicloVidaRegistro:
          data.cicloVidaRegistro.present
              ? data.cicloVidaRegistro.value
              : this.cicloVidaRegistro,
      empresaId: data.empresaId.present ? data.empresaId.value : this.empresaId,
      sucursalId:
          data.sucursalId.present ? data.sucursalId.value : this.sucursalId,
      clienteId: data.clienteId.present ? data.clienteId.value : this.clienteId,
      servicioId:
          data.servicioId.present ? data.servicioId.value : this.servicioId,
      tipoDireccion:
          data.tipoDireccion.present
              ? data.tipoDireccion.value
              : this.tipoDireccion,
      esPrincipal:
          data.esPrincipal.present ? data.esPrincipal.value : this.esPrincipal,
      calle: data.calle.present ? data.calle.value : this.calle,
      numeroExterior:
          data.numeroExterior.present
              ? data.numeroExterior.value
              : this.numeroExterior,
      numeroInterior:
          data.numeroInterior.present
              ? data.numeroInterior.value
              : this.numeroInterior,
      colonia: data.colonia.present ? data.colonia.value : this.colonia,
      municipioAlcaldia:
          data.municipioAlcaldia.present
              ? data.municipioAlcaldia.value
              : this.municipioAlcaldia,
      ciudadLocalidad:
          data.ciudadLocalidad.present
              ? data.ciudadLocalidad.value
              : this.ciudadLocalidad,
      estado: data.estado.present ? data.estado.value : this.estado,
      codigoPostal:
          data.codigoPostal.present
              ? data.codigoPostal.value
              : this.codigoPostal,
      pais: data.pais.present ? data.pais.value : this.pais,
      referencias:
          data.referencias.present ? data.referencias.value : this.referencias,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DireccionData(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('cicloVidaRegistro: $cicloVidaRegistro, ')
          ..write('empresaId: $empresaId, ')
          ..write('sucursalId: $sucursalId, ')
          ..write('clienteId: $clienteId, ')
          ..write('servicioId: $servicioId, ')
          ..write('tipoDireccion: $tipoDireccion, ')
          ..write('esPrincipal: $esPrincipal, ')
          ..write('calle: $calle, ')
          ..write('numeroExterior: $numeroExterior, ')
          ..write('numeroInterior: $numeroInterior, ')
          ..write('colonia: $colonia, ')
          ..write('municipioAlcaldia: $municipioAlcaldia, ')
          ..write('ciudadLocalidad: $ciudadLocalidad, ')
          ..write('estado: $estado, ')
          ..write('codigoPostal: $codigoPostal, ')
          ..write('pais: $pais, ')
          ..write('referencias: $referencias')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    createdAt,
    updatedAt,
    cicloVidaRegistro,
    empresaId,
    sucursalId,
    clienteId,
    servicioId,
    tipoDireccion,
    esPrincipal,
    calle,
    numeroExterior,
    numeroInterior,
    colonia,
    municipioAlcaldia,
    ciudadLocalidad,
    estado,
    codigoPostal,
    pais,
    referencias,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DireccionData &&
          other.id == this.id &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.cicloVidaRegistro == this.cicloVidaRegistro &&
          other.empresaId == this.empresaId &&
          other.sucursalId == this.sucursalId &&
          other.clienteId == this.clienteId &&
          other.servicioId == this.servicioId &&
          other.tipoDireccion == this.tipoDireccion &&
          other.esPrincipal == this.esPrincipal &&
          other.calle == this.calle &&
          other.numeroExterior == this.numeroExterior &&
          other.numeroInterior == this.numeroInterior &&
          other.colonia == this.colonia &&
          other.municipioAlcaldia == this.municipioAlcaldia &&
          other.ciudadLocalidad == this.ciudadLocalidad &&
          other.estado == this.estado &&
          other.codigoPostal == this.codigoPostal &&
          other.pais == this.pais &&
          other.referencias == this.referencias);
}

class DireccionCompanion extends UpdateCompanion<DireccionData> {
  final Value<String> id;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<String> cicloVidaRegistro;
  final Value<String?> empresaId;
  final Value<String?> sucursalId;
  final Value<String?> clienteId;
  final Value<String?> servicioId;
  final Value<String> tipoDireccion;
  final Value<bool> esPrincipal;
  final Value<String> calle;
  final Value<String> numeroExterior;
  final Value<String?> numeroInterior;
  final Value<String> colonia;
  final Value<String> municipioAlcaldia;
  final Value<String?> ciudadLocalidad;
  final Value<String> estado;
  final Value<String> codigoPostal;
  final Value<String> pais;
  final Value<String?> referencias;
  final Value<int> rowid;
  const DireccionCompanion({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.cicloVidaRegistro = const Value.absent(),
    this.empresaId = const Value.absent(),
    this.sucursalId = const Value.absent(),
    this.clienteId = const Value.absent(),
    this.servicioId = const Value.absent(),
    this.tipoDireccion = const Value.absent(),
    this.esPrincipal = const Value.absent(),
    this.calle = const Value.absent(),
    this.numeroExterior = const Value.absent(),
    this.numeroInterior = const Value.absent(),
    this.colonia = const Value.absent(),
    this.municipioAlcaldia = const Value.absent(),
    this.ciudadLocalidad = const Value.absent(),
    this.estado = const Value.absent(),
    this.codigoPostal = const Value.absent(),
    this.pais = const Value.absent(),
    this.referencias = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DireccionCompanion.insert({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.cicloVidaRegistro = const Value.absent(),
    this.empresaId = const Value.absent(),
    this.sucursalId = const Value.absent(),
    this.clienteId = const Value.absent(),
    this.servicioId = const Value.absent(),
    required String tipoDireccion,
    this.esPrincipal = const Value.absent(),
    required String calle,
    required String numeroExterior,
    this.numeroInterior = const Value.absent(),
    required String colonia,
    required String municipioAlcaldia,
    this.ciudadLocalidad = const Value.absent(),
    required String estado,
    required String codigoPostal,
    this.pais = const Value.absent(),
    this.referencias = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : tipoDireccion = Value(tipoDireccion),
       calle = Value(calle),
       numeroExterior = Value(numeroExterior),
       colonia = Value(colonia),
       municipioAlcaldia = Value(municipioAlcaldia),
       estado = Value(estado),
       codigoPostal = Value(codigoPostal);
  static Insertable<DireccionData> custom({
    Expression<String>? id,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<String>? cicloVidaRegistro,
    Expression<String>? empresaId,
    Expression<String>? sucursalId,
    Expression<String>? clienteId,
    Expression<String>? servicioId,
    Expression<String>? tipoDireccion,
    Expression<bool>? esPrincipal,
    Expression<String>? calle,
    Expression<String>? numeroExterior,
    Expression<String>? numeroInterior,
    Expression<String>? colonia,
    Expression<String>? municipioAlcaldia,
    Expression<String>? ciudadLocalidad,
    Expression<String>? estado,
    Expression<String>? codigoPostal,
    Expression<String>? pais,
    Expression<String>? referencias,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (cicloVidaRegistro != null) 'ciclo_vida_registro': cicloVidaRegistro,
      if (empresaId != null) 'empresa_id': empresaId,
      if (sucursalId != null) 'sucursal_id': sucursalId,
      if (clienteId != null) 'cliente_id': clienteId,
      if (servicioId != null) 'servicio_id': servicioId,
      if (tipoDireccion != null) 'tipo_direccion': tipoDireccion,
      if (esPrincipal != null) 'es_principal': esPrincipal,
      if (calle != null) 'calle': calle,
      if (numeroExterior != null) 'numero_exterior': numeroExterior,
      if (numeroInterior != null) 'numero_interior': numeroInterior,
      if (colonia != null) 'colonia': colonia,
      if (municipioAlcaldia != null) 'municipio_alcaldia': municipioAlcaldia,
      if (ciudadLocalidad != null) 'ciudad_localidad': ciudadLocalidad,
      if (estado != null) 'estado': estado,
      if (codigoPostal != null) 'codigo_postal': codigoPostal,
      if (pais != null) 'pais': pais,
      if (referencias != null) 'referencias': referencias,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DireccionCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<String>? cicloVidaRegistro,
    Value<String?>? empresaId,
    Value<String?>? sucursalId,
    Value<String?>? clienteId,
    Value<String?>? servicioId,
    Value<String>? tipoDireccion,
    Value<bool>? esPrincipal,
    Value<String>? calle,
    Value<String>? numeroExterior,
    Value<String?>? numeroInterior,
    Value<String>? colonia,
    Value<String>? municipioAlcaldia,
    Value<String?>? ciudadLocalidad,
    Value<String>? estado,
    Value<String>? codigoPostal,
    Value<String>? pais,
    Value<String?>? referencias,
    Value<int>? rowid,
  }) {
    return DireccionCompanion(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      cicloVidaRegistro: cicloVidaRegistro ?? this.cicloVidaRegistro,
      empresaId: empresaId ?? this.empresaId,
      sucursalId: sucursalId ?? this.sucursalId,
      clienteId: clienteId ?? this.clienteId,
      servicioId: servicioId ?? this.servicioId,
      tipoDireccion: tipoDireccion ?? this.tipoDireccion,
      esPrincipal: esPrincipal ?? this.esPrincipal,
      calle: calle ?? this.calle,
      numeroExterior: numeroExterior ?? this.numeroExterior,
      numeroInterior: numeroInterior ?? this.numeroInterior,
      colonia: colonia ?? this.colonia,
      municipioAlcaldia: municipioAlcaldia ?? this.municipioAlcaldia,
      ciudadLocalidad: ciudadLocalidad ?? this.ciudadLocalidad,
      estado: estado ?? this.estado,
      codigoPostal: codigoPostal ?? this.codigoPostal,
      pais: pais ?? this.pais,
      referencias: referencias ?? this.referencias,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (cicloVidaRegistro.present) {
      map['ciclo_vida_registro'] = Variable<String>(cicloVidaRegistro.value);
    }
    if (empresaId.present) {
      map['empresa_id'] = Variable<String>(empresaId.value);
    }
    if (sucursalId.present) {
      map['sucursal_id'] = Variable<String>(sucursalId.value);
    }
    if (clienteId.present) {
      map['cliente_id'] = Variable<String>(clienteId.value);
    }
    if (servicioId.present) {
      map['servicio_id'] = Variable<String>(servicioId.value);
    }
    if (tipoDireccion.present) {
      map['tipo_direccion'] = Variable<String>(tipoDireccion.value);
    }
    if (esPrincipal.present) {
      map['es_principal'] = Variable<bool>(esPrincipal.value);
    }
    if (calle.present) {
      map['calle'] = Variable<String>(calle.value);
    }
    if (numeroExterior.present) {
      map['numero_exterior'] = Variable<String>(numeroExterior.value);
    }
    if (numeroInterior.present) {
      map['numero_interior'] = Variable<String>(numeroInterior.value);
    }
    if (colonia.present) {
      map['colonia'] = Variable<String>(colonia.value);
    }
    if (municipioAlcaldia.present) {
      map['municipio_alcaldia'] = Variable<String>(municipioAlcaldia.value);
    }
    if (ciudadLocalidad.present) {
      map['ciudad_localidad'] = Variable<String>(ciudadLocalidad.value);
    }
    if (estado.present) {
      map['estado'] = Variable<String>(estado.value);
    }
    if (codigoPostal.present) {
      map['codigo_postal'] = Variable<String>(codigoPostal.value);
    }
    if (pais.present) {
      map['pais'] = Variable<String>(pais.value);
    }
    if (referencias.present) {
      map['referencias'] = Variable<String>(referencias.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DireccionCompanion(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('cicloVidaRegistro: $cicloVidaRegistro, ')
          ..write('empresaId: $empresaId, ')
          ..write('sucursalId: $sucursalId, ')
          ..write('clienteId: $clienteId, ')
          ..write('servicioId: $servicioId, ')
          ..write('tipoDireccion: $tipoDireccion, ')
          ..write('esPrincipal: $esPrincipal, ')
          ..write('calle: $calle, ')
          ..write('numeroExterior: $numeroExterior, ')
          ..write('numeroInterior: $numeroInterior, ')
          ..write('colonia: $colonia, ')
          ..write('municipioAlcaldia: $municipioAlcaldia, ')
          ..write('ciudadLocalidad: $ciudadLocalidad, ')
          ..write('estado: $estado, ')
          ..write('codigoPostal: $codigoPostal, ')
          ..write('pais: $pais, ')
          ..write('referencias: $referencias, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MedioContactoTable extends MedioContacto
    with TableInfo<$MedioContactoTable, MedioContactoData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MedioContactoTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: () => const Uuid().v4(),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _cicloVidaRegistroMeta = const VerificationMeta(
    'cicloVidaRegistro',
  );
  @override
  late final GeneratedColumn<String> cicloVidaRegistro =
      GeneratedColumn<String>(
        'ciclo_vida_registro',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('activo'),
      );
  static const VerificationMeta _empresaIdMeta = const VerificationMeta(
    'empresaId',
  );
  @override
  late final GeneratedColumn<String> empresaId = GeneratedColumn<String>(
    'empresa_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sucursalIdMeta = const VerificationMeta(
    'sucursalId',
  );
  @override
  late final GeneratedColumn<String> sucursalId = GeneratedColumn<String>(
    'sucursal_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _telefonoMeta = const VerificationMeta(
    'telefono',
  );
  @override
  late final GeneratedColumn<String> telefono = GeneratedColumn<String>(
    'telefono',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _correoMeta = const VerificationMeta('correo');
  @override
  late final GeneratedColumn<String> correo = GeneratedColumn<String>(
    'correo',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sitioWebMeta = const VerificationMeta(
    'sitioWeb',
  );
  @override
  late final GeneratedColumn<String> sitioWeb = GeneratedColumn<String>(
    'sitio_web',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _etiquetaMeta = const VerificationMeta(
    'etiqueta',
  );
  @override
  late final GeneratedColumn<String> etiqueta = GeneratedColumn<String>(
    'etiqueta',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    createdAt,
    updatedAt,
    cicloVidaRegistro,
    empresaId,
    sucursalId,
    telefono,
    correo,
    sitioWeb,
    etiqueta,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'medio_contacto';
  @override
  VerificationContext validateIntegrity(
    Insertable<MedioContactoData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('ciclo_vida_registro')) {
      context.handle(
        _cicloVidaRegistroMeta,
        cicloVidaRegistro.isAcceptableOrUnknown(
          data['ciclo_vida_registro']!,
          _cicloVidaRegistroMeta,
        ),
      );
    }
    if (data.containsKey('empresa_id')) {
      context.handle(
        _empresaIdMeta,
        empresaId.isAcceptableOrUnknown(data['empresa_id']!, _empresaIdMeta),
      );
    }
    if (data.containsKey('sucursal_id')) {
      context.handle(
        _sucursalIdMeta,
        sucursalId.isAcceptableOrUnknown(data['sucursal_id']!, _sucursalIdMeta),
      );
    }
    if (data.containsKey('telefono')) {
      context.handle(
        _telefonoMeta,
        telefono.isAcceptableOrUnknown(data['telefono']!, _telefonoMeta),
      );
    }
    if (data.containsKey('correo')) {
      context.handle(
        _correoMeta,
        correo.isAcceptableOrUnknown(data['correo']!, _correoMeta),
      );
    }
    if (data.containsKey('sitio_web')) {
      context.handle(
        _sitioWebMeta,
        sitioWeb.isAcceptableOrUnknown(data['sitio_web']!, _sitioWebMeta),
      );
    }
    if (data.containsKey('etiqueta')) {
      context.handle(
        _etiquetaMeta,
        etiqueta.isAcceptableOrUnknown(data['etiqueta']!, _etiquetaMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MedioContactoData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MedioContactoData(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}id'],
          )!,
      createdAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}created_at'],
          )!,
      updatedAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}updated_at'],
          )!,
      cicloVidaRegistro:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}ciclo_vida_registro'],
          )!,
      empresaId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}empresa_id'],
      ),
      sucursalId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sucursal_id'],
      ),
      telefono: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}telefono'],
      ),
      correo: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}correo'],
      ),
      sitioWeb: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sitio_web'],
      ),
      etiqueta: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}etiqueta'],
      ),
    );
  }

  @override
  $MedioContactoTable createAlias(String alias) {
    return $MedioContactoTable(attachedDatabase, alias);
  }
}

class MedioContactoData extends DataClass
    implements Insertable<MedioContactoData> {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String cicloVidaRegistro;
  final String? empresaId;
  final String? sucursalId;
  final String? telefono;
  final String? correo;
  final String? sitioWeb;
  final String? etiqueta;
  const MedioContactoData({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required this.cicloVidaRegistro,
    this.empresaId,
    this.sucursalId,
    this.telefono,
    this.correo,
    this.sitioWeb,
    this.etiqueta,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['ciclo_vida_registro'] = Variable<String>(cicloVidaRegistro);
    if (!nullToAbsent || empresaId != null) {
      map['empresa_id'] = Variable<String>(empresaId);
    }
    if (!nullToAbsent || sucursalId != null) {
      map['sucursal_id'] = Variable<String>(sucursalId);
    }
    if (!nullToAbsent || telefono != null) {
      map['telefono'] = Variable<String>(telefono);
    }
    if (!nullToAbsent || correo != null) {
      map['correo'] = Variable<String>(correo);
    }
    if (!nullToAbsent || sitioWeb != null) {
      map['sitio_web'] = Variable<String>(sitioWeb);
    }
    if (!nullToAbsent || etiqueta != null) {
      map['etiqueta'] = Variable<String>(etiqueta);
    }
    return map;
  }

  MedioContactoCompanion toCompanion(bool nullToAbsent) {
    return MedioContactoCompanion(
      id: Value(id),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      cicloVidaRegistro: Value(cicloVidaRegistro),
      empresaId:
          empresaId == null && nullToAbsent
              ? const Value.absent()
              : Value(empresaId),
      sucursalId:
          sucursalId == null && nullToAbsent
              ? const Value.absent()
              : Value(sucursalId),
      telefono:
          telefono == null && nullToAbsent
              ? const Value.absent()
              : Value(telefono),
      correo:
          correo == null && nullToAbsent ? const Value.absent() : Value(correo),
      sitioWeb:
          sitioWeb == null && nullToAbsent
              ? const Value.absent()
              : Value(sitioWeb),
      etiqueta:
          etiqueta == null && nullToAbsent
              ? const Value.absent()
              : Value(etiqueta),
    );
  }

  factory MedioContactoData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MedioContactoData(
      id: serializer.fromJson<String>(json['id']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      cicloVidaRegistro: serializer.fromJson<String>(json['cicloVidaRegistro']),
      empresaId: serializer.fromJson<String?>(json['empresaId']),
      sucursalId: serializer.fromJson<String?>(json['sucursalId']),
      telefono: serializer.fromJson<String?>(json['telefono']),
      correo: serializer.fromJson<String?>(json['correo']),
      sitioWeb: serializer.fromJson<String?>(json['sitioWeb']),
      etiqueta: serializer.fromJson<String?>(json['etiqueta']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'cicloVidaRegistro': serializer.toJson<String>(cicloVidaRegistro),
      'empresaId': serializer.toJson<String?>(empresaId),
      'sucursalId': serializer.toJson<String?>(sucursalId),
      'telefono': serializer.toJson<String?>(telefono),
      'correo': serializer.toJson<String?>(correo),
      'sitioWeb': serializer.toJson<String?>(sitioWeb),
      'etiqueta': serializer.toJson<String?>(etiqueta),
    };
  }

  MedioContactoData copyWith({
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? cicloVidaRegistro,
    Value<String?> empresaId = const Value.absent(),
    Value<String?> sucursalId = const Value.absent(),
    Value<String?> telefono = const Value.absent(),
    Value<String?> correo = const Value.absent(),
    Value<String?> sitioWeb = const Value.absent(),
    Value<String?> etiqueta = const Value.absent(),
  }) => MedioContactoData(
    id: id ?? this.id,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    cicloVidaRegistro: cicloVidaRegistro ?? this.cicloVidaRegistro,
    empresaId: empresaId.present ? empresaId.value : this.empresaId,
    sucursalId: sucursalId.present ? sucursalId.value : this.sucursalId,
    telefono: telefono.present ? telefono.value : this.telefono,
    correo: correo.present ? correo.value : this.correo,
    sitioWeb: sitioWeb.present ? sitioWeb.value : this.sitioWeb,
    etiqueta: etiqueta.present ? etiqueta.value : this.etiqueta,
  );
  MedioContactoData copyWithCompanion(MedioContactoCompanion data) {
    return MedioContactoData(
      id: data.id.present ? data.id.value : this.id,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      cicloVidaRegistro:
          data.cicloVidaRegistro.present
              ? data.cicloVidaRegistro.value
              : this.cicloVidaRegistro,
      empresaId: data.empresaId.present ? data.empresaId.value : this.empresaId,
      sucursalId:
          data.sucursalId.present ? data.sucursalId.value : this.sucursalId,
      telefono: data.telefono.present ? data.telefono.value : this.telefono,
      correo: data.correo.present ? data.correo.value : this.correo,
      sitioWeb: data.sitioWeb.present ? data.sitioWeb.value : this.sitioWeb,
      etiqueta: data.etiqueta.present ? data.etiqueta.value : this.etiqueta,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MedioContactoData(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('cicloVidaRegistro: $cicloVidaRegistro, ')
          ..write('empresaId: $empresaId, ')
          ..write('sucursalId: $sucursalId, ')
          ..write('telefono: $telefono, ')
          ..write('correo: $correo, ')
          ..write('sitioWeb: $sitioWeb, ')
          ..write('etiqueta: $etiqueta')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    createdAt,
    updatedAt,
    cicloVidaRegistro,
    empresaId,
    sucursalId,
    telefono,
    correo,
    sitioWeb,
    etiqueta,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MedioContactoData &&
          other.id == this.id &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.cicloVidaRegistro == this.cicloVidaRegistro &&
          other.empresaId == this.empresaId &&
          other.sucursalId == this.sucursalId &&
          other.telefono == this.telefono &&
          other.correo == this.correo &&
          other.sitioWeb == this.sitioWeb &&
          other.etiqueta == this.etiqueta);
}

class MedioContactoCompanion extends UpdateCompanion<MedioContactoData> {
  final Value<String> id;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<String> cicloVidaRegistro;
  final Value<String?> empresaId;
  final Value<String?> sucursalId;
  final Value<String?> telefono;
  final Value<String?> correo;
  final Value<String?> sitioWeb;
  final Value<String?> etiqueta;
  final Value<int> rowid;
  const MedioContactoCompanion({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.cicloVidaRegistro = const Value.absent(),
    this.empresaId = const Value.absent(),
    this.sucursalId = const Value.absent(),
    this.telefono = const Value.absent(),
    this.correo = const Value.absent(),
    this.sitioWeb = const Value.absent(),
    this.etiqueta = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MedioContactoCompanion.insert({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.cicloVidaRegistro = const Value.absent(),
    this.empresaId = const Value.absent(),
    this.sucursalId = const Value.absent(),
    this.telefono = const Value.absent(),
    this.correo = const Value.absent(),
    this.sitioWeb = const Value.absent(),
    this.etiqueta = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  static Insertable<MedioContactoData> custom({
    Expression<String>? id,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<String>? cicloVidaRegistro,
    Expression<String>? empresaId,
    Expression<String>? sucursalId,
    Expression<String>? telefono,
    Expression<String>? correo,
    Expression<String>? sitioWeb,
    Expression<String>? etiqueta,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (cicloVidaRegistro != null) 'ciclo_vida_registro': cicloVidaRegistro,
      if (empresaId != null) 'empresa_id': empresaId,
      if (sucursalId != null) 'sucursal_id': sucursalId,
      if (telefono != null) 'telefono': telefono,
      if (correo != null) 'correo': correo,
      if (sitioWeb != null) 'sitio_web': sitioWeb,
      if (etiqueta != null) 'etiqueta': etiqueta,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MedioContactoCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<String>? cicloVidaRegistro,
    Value<String?>? empresaId,
    Value<String?>? sucursalId,
    Value<String?>? telefono,
    Value<String?>? correo,
    Value<String?>? sitioWeb,
    Value<String?>? etiqueta,
    Value<int>? rowid,
  }) {
    return MedioContactoCompanion(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      cicloVidaRegistro: cicloVidaRegistro ?? this.cicloVidaRegistro,
      empresaId: empresaId ?? this.empresaId,
      sucursalId: sucursalId ?? this.sucursalId,
      telefono: telefono ?? this.telefono,
      correo: correo ?? this.correo,
      sitioWeb: sitioWeb ?? this.sitioWeb,
      etiqueta: etiqueta ?? this.etiqueta,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (cicloVidaRegistro.present) {
      map['ciclo_vida_registro'] = Variable<String>(cicloVidaRegistro.value);
    }
    if (empresaId.present) {
      map['empresa_id'] = Variable<String>(empresaId.value);
    }
    if (sucursalId.present) {
      map['sucursal_id'] = Variable<String>(sucursalId.value);
    }
    if (telefono.present) {
      map['telefono'] = Variable<String>(telefono.value);
    }
    if (correo.present) {
      map['correo'] = Variable<String>(correo.value);
    }
    if (sitioWeb.present) {
      map['sitio_web'] = Variable<String>(sitioWeb.value);
    }
    if (etiqueta.present) {
      map['etiqueta'] = Variable<String>(etiqueta.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MedioContactoCompanion(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('cicloVidaRegistro: $cicloVidaRegistro, ')
          ..write('empresaId: $empresaId, ')
          ..write('sucursalId: $sucursalId, ')
          ..write('telefono: $telefono, ')
          ..write('correo: $correo, ')
          ..write('sitioWeb: $sitioWeb, ')
          ..write('etiqueta: $etiqueta, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AttachmentTable extends Attachment
    with TableInfo<$AttachmentTable, AttachmentData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AttachmentTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _empresaIdMeta = const VerificationMeta(
    'empresaId',
  );
  @override
  late final GeneratedColumn<String> empresaId = GeneratedColumn<String>(
    'empresa_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _clienteIdMeta = const VerificationMeta(
    'clienteId',
  );
  @override
  late final GeneratedColumn<String> clienteId = GeneratedColumn<String>(
    'cliente_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _originalFileNameMeta = const VerificationMeta(
    'originalFileName',
  );
  @override
  late final GeneratedColumn<String> originalFileName = GeneratedColumn<String>(
    'original_file_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _storedFileNameMeta = const VerificationMeta(
    'storedFileName',
  );
  @override
  late final GeneratedColumn<String> storedFileName = GeneratedColumn<String>(
    'stored_file_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mimeTypeMeta = const VerificationMeta(
    'mimeType',
  );
  @override
  late final GeneratedColumn<String> mimeType = GeneratedColumn<String>(
    'mime_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sizeBytesMeta = const VerificationMeta(
    'sizeBytes',
  );
  @override
  late final GeneratedColumn<int> sizeBytes = GeneratedColumn<int>(
    'size_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hashMeta = const VerificationMeta('hash');
  @override
  late final GeneratedColumn<String> hash = GeneratedColumn<String>(
    'hash',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    empresaId,
    clienteId,
    originalFileName,
    storedFileName,
    path,
    mimeType,
    sizeBytes,
    hash,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'attachment';
  @override
  VerificationContext validateIntegrity(
    Insertable<AttachmentData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('empresa_id')) {
      context.handle(
        _empresaIdMeta,
        empresaId.isAcceptableOrUnknown(data['empresa_id']!, _empresaIdMeta),
      );
    }
    if (data.containsKey('cliente_id')) {
      context.handle(
        _clienteIdMeta,
        clienteId.isAcceptableOrUnknown(data['cliente_id']!, _clienteIdMeta),
      );
    }
    if (data.containsKey('original_file_name')) {
      context.handle(
        _originalFileNameMeta,
        originalFileName.isAcceptableOrUnknown(
          data['original_file_name']!,
          _originalFileNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_originalFileNameMeta);
    }
    if (data.containsKey('stored_file_name')) {
      context.handle(
        _storedFileNameMeta,
        storedFileName.isAcceptableOrUnknown(
          data['stored_file_name']!,
          _storedFileNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_storedFileNameMeta);
    }
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('mime_type')) {
      context.handle(
        _mimeTypeMeta,
        mimeType.isAcceptableOrUnknown(data['mime_type']!, _mimeTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_mimeTypeMeta);
    }
    if (data.containsKey('size_bytes')) {
      context.handle(
        _sizeBytesMeta,
        sizeBytes.isAcceptableOrUnknown(data['size_bytes']!, _sizeBytesMeta),
      );
    } else if (isInserting) {
      context.missing(_sizeBytesMeta);
    }
    if (data.containsKey('hash')) {
      context.handle(
        _hashMeta,
        hash.isAcceptableOrUnknown(data['hash']!, _hashMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AttachmentData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AttachmentData(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}id'],
          )!,
      empresaId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}empresa_id'],
      ),
      clienteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cliente_id'],
      ),
      originalFileName:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}original_file_name'],
          )!,
      storedFileName:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}stored_file_name'],
          )!,
      path:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}path'],
          )!,
      mimeType:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}mime_type'],
          )!,
      sizeBytes:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}size_bytes'],
          )!,
      hash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hash'],
      ),
      createdAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}created_at'],
          )!,
    );
  }

  @override
  $AttachmentTable createAlias(String alias) {
    return $AttachmentTable(attachedDatabase, alias);
  }
}

class AttachmentData extends DataClass implements Insertable<AttachmentData> {
  final String id;
  final String? empresaId;
  final String? clienteId;
  final String originalFileName;
  final String storedFileName;
  final String path;
  final String mimeType;
  final int sizeBytes;
  final String? hash;
  final DateTime createdAt;
  const AttachmentData({
    required this.id,
    this.empresaId,
    this.clienteId,
    required this.originalFileName,
    required this.storedFileName,
    required this.path,
    required this.mimeType,
    required this.sizeBytes,
    this.hash,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || empresaId != null) {
      map['empresa_id'] = Variable<String>(empresaId);
    }
    if (!nullToAbsent || clienteId != null) {
      map['cliente_id'] = Variable<String>(clienteId);
    }
    map['original_file_name'] = Variable<String>(originalFileName);
    map['stored_file_name'] = Variable<String>(storedFileName);
    map['path'] = Variable<String>(path);
    map['mime_type'] = Variable<String>(mimeType);
    map['size_bytes'] = Variable<int>(sizeBytes);
    if (!nullToAbsent || hash != null) {
      map['hash'] = Variable<String>(hash);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  AttachmentCompanion toCompanion(bool nullToAbsent) {
    return AttachmentCompanion(
      id: Value(id),
      empresaId:
          empresaId == null && nullToAbsent
              ? const Value.absent()
              : Value(empresaId),
      clienteId:
          clienteId == null && nullToAbsent
              ? const Value.absent()
              : Value(clienteId),
      originalFileName: Value(originalFileName),
      storedFileName: Value(storedFileName),
      path: Value(path),
      mimeType: Value(mimeType),
      sizeBytes: Value(sizeBytes),
      hash: hash == null && nullToAbsent ? const Value.absent() : Value(hash),
      createdAt: Value(createdAt),
    );
  }

  factory AttachmentData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AttachmentData(
      id: serializer.fromJson<String>(json['id']),
      empresaId: serializer.fromJson<String?>(json['empresaId']),
      clienteId: serializer.fromJson<String?>(json['clienteId']),
      originalFileName: serializer.fromJson<String>(json['originalFileName']),
      storedFileName: serializer.fromJson<String>(json['storedFileName']),
      path: serializer.fromJson<String>(json['path']),
      mimeType: serializer.fromJson<String>(json['mimeType']),
      sizeBytes: serializer.fromJson<int>(json['sizeBytes']),
      hash: serializer.fromJson<String?>(json['hash']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'empresaId': serializer.toJson<String?>(empresaId),
      'clienteId': serializer.toJson<String?>(clienteId),
      'originalFileName': serializer.toJson<String>(originalFileName),
      'storedFileName': serializer.toJson<String>(storedFileName),
      'path': serializer.toJson<String>(path),
      'mimeType': serializer.toJson<String>(mimeType),
      'sizeBytes': serializer.toJson<int>(sizeBytes),
      'hash': serializer.toJson<String?>(hash),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  AttachmentData copyWith({
    String? id,
    Value<String?> empresaId = const Value.absent(),
    Value<String?> clienteId = const Value.absent(),
    String? originalFileName,
    String? storedFileName,
    String? path,
    String? mimeType,
    int? sizeBytes,
    Value<String?> hash = const Value.absent(),
    DateTime? createdAt,
  }) => AttachmentData(
    id: id ?? this.id,
    empresaId: empresaId.present ? empresaId.value : this.empresaId,
    clienteId: clienteId.present ? clienteId.value : this.clienteId,
    originalFileName: originalFileName ?? this.originalFileName,
    storedFileName: storedFileName ?? this.storedFileName,
    path: path ?? this.path,
    mimeType: mimeType ?? this.mimeType,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    hash: hash.present ? hash.value : this.hash,
    createdAt: createdAt ?? this.createdAt,
  );
  AttachmentData copyWithCompanion(AttachmentCompanion data) {
    return AttachmentData(
      id: data.id.present ? data.id.value : this.id,
      empresaId: data.empresaId.present ? data.empresaId.value : this.empresaId,
      clienteId: data.clienteId.present ? data.clienteId.value : this.clienteId,
      originalFileName:
          data.originalFileName.present
              ? data.originalFileName.value
              : this.originalFileName,
      storedFileName:
          data.storedFileName.present
              ? data.storedFileName.value
              : this.storedFileName,
      path: data.path.present ? data.path.value : this.path,
      mimeType: data.mimeType.present ? data.mimeType.value : this.mimeType,
      sizeBytes: data.sizeBytes.present ? data.sizeBytes.value : this.sizeBytes,
      hash: data.hash.present ? data.hash.value : this.hash,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AttachmentData(')
          ..write('id: $id, ')
          ..write('empresaId: $empresaId, ')
          ..write('clienteId: $clienteId, ')
          ..write('originalFileName: $originalFileName, ')
          ..write('storedFileName: $storedFileName, ')
          ..write('path: $path, ')
          ..write('mimeType: $mimeType, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('hash: $hash, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    empresaId,
    clienteId,
    originalFileName,
    storedFileName,
    path,
    mimeType,
    sizeBytes,
    hash,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AttachmentData &&
          other.id == this.id &&
          other.empresaId == this.empresaId &&
          other.clienteId == this.clienteId &&
          other.originalFileName == this.originalFileName &&
          other.storedFileName == this.storedFileName &&
          other.path == this.path &&
          other.mimeType == this.mimeType &&
          other.sizeBytes == this.sizeBytes &&
          other.hash == this.hash &&
          other.createdAt == this.createdAt);
}

class AttachmentCompanion extends UpdateCompanion<AttachmentData> {
  final Value<String> id;
  final Value<String?> empresaId;
  final Value<String?> clienteId;
  final Value<String> originalFileName;
  final Value<String> storedFileName;
  final Value<String> path;
  final Value<String> mimeType;
  final Value<int> sizeBytes;
  final Value<String?> hash;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const AttachmentCompanion({
    this.id = const Value.absent(),
    this.empresaId = const Value.absent(),
    this.clienteId = const Value.absent(),
    this.originalFileName = const Value.absent(),
    this.storedFileName = const Value.absent(),
    this.path = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.hash = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AttachmentCompanion.insert({
    required String id,
    this.empresaId = const Value.absent(),
    this.clienteId = const Value.absent(),
    required String originalFileName,
    required String storedFileName,
    required String path,
    required String mimeType,
    required int sizeBytes,
    this.hash = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       originalFileName = Value(originalFileName),
       storedFileName = Value(storedFileName),
       path = Value(path),
       mimeType = Value(mimeType),
       sizeBytes = Value(sizeBytes);
  static Insertable<AttachmentData> custom({
    Expression<String>? id,
    Expression<String>? empresaId,
    Expression<String>? clienteId,
    Expression<String>? originalFileName,
    Expression<String>? storedFileName,
    Expression<String>? path,
    Expression<String>? mimeType,
    Expression<int>? sizeBytes,
    Expression<String>? hash,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (empresaId != null) 'empresa_id': empresaId,
      if (clienteId != null) 'cliente_id': clienteId,
      if (originalFileName != null) 'original_file_name': originalFileName,
      if (storedFileName != null) 'stored_file_name': storedFileName,
      if (path != null) 'path': path,
      if (mimeType != null) 'mime_type': mimeType,
      if (sizeBytes != null) 'size_bytes': sizeBytes,
      if (hash != null) 'hash': hash,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AttachmentCompanion copyWith({
    Value<String>? id,
    Value<String?>? empresaId,
    Value<String?>? clienteId,
    Value<String>? originalFileName,
    Value<String>? storedFileName,
    Value<String>? path,
    Value<String>? mimeType,
    Value<int>? sizeBytes,
    Value<String?>? hash,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return AttachmentCompanion(
      id: id ?? this.id,
      empresaId: empresaId ?? this.empresaId,
      clienteId: clienteId ?? this.clienteId,
      originalFileName: originalFileName ?? this.originalFileName,
      storedFileName: storedFileName ?? this.storedFileName,
      path: path ?? this.path,
      mimeType: mimeType ?? this.mimeType,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      hash: hash ?? this.hash,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (empresaId.present) {
      map['empresa_id'] = Variable<String>(empresaId.value);
    }
    if (clienteId.present) {
      map['cliente_id'] = Variable<String>(clienteId.value);
    }
    if (originalFileName.present) {
      map['original_file_name'] = Variable<String>(originalFileName.value);
    }
    if (storedFileName.present) {
      map['stored_file_name'] = Variable<String>(storedFileName.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (mimeType.present) {
      map['mime_type'] = Variable<String>(mimeType.value);
    }
    if (sizeBytes.present) {
      map['size_bytes'] = Variable<int>(sizeBytes.value);
    }
    if (hash.present) {
      map['hash'] = Variable<String>(hash.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AttachmentCompanion(')
          ..write('id: $id, ')
          ..write('empresaId: $empresaId, ')
          ..write('clienteId: $clienteId, ')
          ..write('originalFileName: $originalFileName, ')
          ..write('storedFileName: $storedFileName, ')
          ..write('path: $path, ')
          ..write('mimeType: $mimeType, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('hash: $hash, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $HorarioTable extends Horario with TableInfo<$HorarioTable, HorarioData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HorarioTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: () => const Uuid().v4(),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _cicloVidaRegistroMeta = const VerificationMeta(
    'cicloVidaRegistro',
  );
  @override
  late final GeneratedColumn<String> cicloVidaRegistro =
      GeneratedColumn<String>(
        'ciclo_vida_registro',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('activo'),
      );
  static const VerificationMeta _sucursalIdMeta = const VerificationMeta(
    'sucursalId',
  );
  @override
  late final GeneratedColumn<String> sucursalId = GeneratedColumn<String>(
    'sucursal_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _servicioIdMeta = const VerificationMeta(
    'servicioId',
  );
  @override
  late final GeneratedColumn<String> servicioId = GeneratedColumn<String>(
    'servicio_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    createdAt,
    updatedAt,
    cicloVidaRegistro,
    sucursalId,
    servicioId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'horario';
  @override
  VerificationContext validateIntegrity(
    Insertable<HorarioData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('ciclo_vida_registro')) {
      context.handle(
        _cicloVidaRegistroMeta,
        cicloVidaRegistro.isAcceptableOrUnknown(
          data['ciclo_vida_registro']!,
          _cicloVidaRegistroMeta,
        ),
      );
    }
    if (data.containsKey('sucursal_id')) {
      context.handle(
        _sucursalIdMeta,
        sucursalId.isAcceptableOrUnknown(data['sucursal_id']!, _sucursalIdMeta),
      );
    }
    if (data.containsKey('servicio_id')) {
      context.handle(
        _servicioIdMeta,
        servicioId.isAcceptableOrUnknown(data['servicio_id']!, _servicioIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  HorarioData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HorarioData(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}id'],
          )!,
      createdAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}created_at'],
          )!,
      updatedAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}updated_at'],
          )!,
      cicloVidaRegistro:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}ciclo_vida_registro'],
          )!,
      sucursalId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sucursal_id'],
      ),
      servicioId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}servicio_id'],
      ),
    );
  }

  @override
  $HorarioTable createAlias(String alias) {
    return $HorarioTable(attachedDatabase, alias);
  }
}

class HorarioData extends DataClass implements Insertable<HorarioData> {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String cicloVidaRegistro;
  final String? sucursalId;
  final String? servicioId;
  const HorarioData({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required this.cicloVidaRegistro,
    this.sucursalId,
    this.servicioId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['ciclo_vida_registro'] = Variable<String>(cicloVidaRegistro);
    if (!nullToAbsent || sucursalId != null) {
      map['sucursal_id'] = Variable<String>(sucursalId);
    }
    if (!nullToAbsent || servicioId != null) {
      map['servicio_id'] = Variable<String>(servicioId);
    }
    return map;
  }

  HorarioCompanion toCompanion(bool nullToAbsent) {
    return HorarioCompanion(
      id: Value(id),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      cicloVidaRegistro: Value(cicloVidaRegistro),
      sucursalId:
          sucursalId == null && nullToAbsent
              ? const Value.absent()
              : Value(sucursalId),
      servicioId:
          servicioId == null && nullToAbsent
              ? const Value.absent()
              : Value(servicioId),
    );
  }

  factory HorarioData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HorarioData(
      id: serializer.fromJson<String>(json['id']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      cicloVidaRegistro: serializer.fromJson<String>(json['cicloVidaRegistro']),
      sucursalId: serializer.fromJson<String?>(json['sucursalId']),
      servicioId: serializer.fromJson<String?>(json['servicioId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'cicloVidaRegistro': serializer.toJson<String>(cicloVidaRegistro),
      'sucursalId': serializer.toJson<String?>(sucursalId),
      'servicioId': serializer.toJson<String?>(servicioId),
    };
  }

  HorarioData copyWith({
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? cicloVidaRegistro,
    Value<String?> sucursalId = const Value.absent(),
    Value<String?> servicioId = const Value.absent(),
  }) => HorarioData(
    id: id ?? this.id,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    cicloVidaRegistro: cicloVidaRegistro ?? this.cicloVidaRegistro,
    sucursalId: sucursalId.present ? sucursalId.value : this.sucursalId,
    servicioId: servicioId.present ? servicioId.value : this.servicioId,
  );
  HorarioData copyWithCompanion(HorarioCompanion data) {
    return HorarioData(
      id: data.id.present ? data.id.value : this.id,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      cicloVidaRegistro:
          data.cicloVidaRegistro.present
              ? data.cicloVidaRegistro.value
              : this.cicloVidaRegistro,
      sucursalId:
          data.sucursalId.present ? data.sucursalId.value : this.sucursalId,
      servicioId:
          data.servicioId.present ? data.servicioId.value : this.servicioId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HorarioData(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('cicloVidaRegistro: $cicloVidaRegistro, ')
          ..write('sucursalId: $sucursalId, ')
          ..write('servicioId: $servicioId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    createdAt,
    updatedAt,
    cicloVidaRegistro,
    sucursalId,
    servicioId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HorarioData &&
          other.id == this.id &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.cicloVidaRegistro == this.cicloVidaRegistro &&
          other.sucursalId == this.sucursalId &&
          other.servicioId == this.servicioId);
}

class HorarioCompanion extends UpdateCompanion<HorarioData> {
  final Value<String> id;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<String> cicloVidaRegistro;
  final Value<String?> sucursalId;
  final Value<String?> servicioId;
  final Value<int> rowid;
  const HorarioCompanion({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.cicloVidaRegistro = const Value.absent(),
    this.sucursalId = const Value.absent(),
    this.servicioId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  HorarioCompanion.insert({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.cicloVidaRegistro = const Value.absent(),
    this.sucursalId = const Value.absent(),
    this.servicioId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  static Insertable<HorarioData> custom({
    Expression<String>? id,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<String>? cicloVidaRegistro,
    Expression<String>? sucursalId,
    Expression<String>? servicioId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (cicloVidaRegistro != null) 'ciclo_vida_registro': cicloVidaRegistro,
      if (sucursalId != null) 'sucursal_id': sucursalId,
      if (servicioId != null) 'servicio_id': servicioId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  HorarioCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<String>? cicloVidaRegistro,
    Value<String?>? sucursalId,
    Value<String?>? servicioId,
    Value<int>? rowid,
  }) {
    return HorarioCompanion(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      cicloVidaRegistro: cicloVidaRegistro ?? this.cicloVidaRegistro,
      sucursalId: sucursalId ?? this.sucursalId,
      servicioId: servicioId ?? this.servicioId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (cicloVidaRegistro.present) {
      map['ciclo_vida_registro'] = Variable<String>(cicloVidaRegistro.value);
    }
    if (sucursalId.present) {
      map['sucursal_id'] = Variable<String>(sucursalId.value);
    }
    if (servicioId.present) {
      map['servicio_id'] = Variable<String>(servicioId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HorarioCompanion(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('cicloVidaRegistro: $cicloVidaRegistro, ')
          ..write('sucursalId: $sucursalId, ')
          ..write('servicioId: $servicioId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $HorarioDetalleTable extends HorarioDetalle
    with TableInfo<$HorarioDetalleTable, HorarioDetalleData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HorarioDetalleTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _horarioIdMeta = const VerificationMeta(
    'horarioId',
  );
  @override
  late final GeneratedColumn<String> horarioId = GeneratedColumn<String>(
    'horario_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES horario (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _diaSemanaMeta = const VerificationMeta(
    'diaSemana',
  );
  @override
  late final GeneratedColumn<int> diaSemana = GeneratedColumn<int>(
    'dia_semana',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _horaInicioMeta = const VerificationMeta(
    'horaInicio',
  );
  @override
  late final GeneratedColumn<int> horaInicio = GeneratedColumn<int>(
    'hora_inicio',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _horaFinMeta = const VerificationMeta(
    'horaFin',
  );
  @override
  late final GeneratedColumn<int> horaFin = GeneratedColumn<int>(
    'hora_fin',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cruzaMedianocheMeta = const VerificationMeta(
    'cruzaMedianoche',
  );
  @override
  late final GeneratedColumn<bool> cruzaMedianoche = GeneratedColumn<bool>(
    'cruza_medianoche',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("cruza_medianoche" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _activoMeta = const VerificationMeta('activo');
  @override
  late final GeneratedColumn<bool> activo = GeneratedColumn<bool>(
    'activo',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("activo" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    horarioId,
    diaSemana,
    horaInicio,
    horaFin,
    cruzaMedianoche,
    activo,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'horario_detalle';
  @override
  VerificationContext validateIntegrity(
    Insertable<HorarioDetalleData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('horario_id')) {
      context.handle(
        _horarioIdMeta,
        horarioId.isAcceptableOrUnknown(data['horario_id']!, _horarioIdMeta),
      );
    } else if (isInserting) {
      context.missing(_horarioIdMeta);
    }
    if (data.containsKey('dia_semana')) {
      context.handle(
        _diaSemanaMeta,
        diaSemana.isAcceptableOrUnknown(data['dia_semana']!, _diaSemanaMeta),
      );
    } else if (isInserting) {
      context.missing(_diaSemanaMeta);
    }
    if (data.containsKey('hora_inicio')) {
      context.handle(
        _horaInicioMeta,
        horaInicio.isAcceptableOrUnknown(data['hora_inicio']!, _horaInicioMeta),
      );
    } else if (isInserting) {
      context.missing(_horaInicioMeta);
    }
    if (data.containsKey('hora_fin')) {
      context.handle(
        _horaFinMeta,
        horaFin.isAcceptableOrUnknown(data['hora_fin']!, _horaFinMeta),
      );
    } else if (isInserting) {
      context.missing(_horaFinMeta);
    }
    if (data.containsKey('cruza_medianoche')) {
      context.handle(
        _cruzaMedianocheMeta,
        cruzaMedianoche.isAcceptableOrUnknown(
          data['cruza_medianoche']!,
          _cruzaMedianocheMeta,
        ),
      );
    }
    if (data.containsKey('activo')) {
      context.handle(
        _activoMeta,
        activo.isAcceptableOrUnknown(data['activo']!, _activoMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  HorarioDetalleData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HorarioDetalleData(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}id'],
          )!,
      horarioId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}horario_id'],
          )!,
      diaSemana:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}dia_semana'],
          )!,
      horaInicio:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}hora_inicio'],
          )!,
      horaFin:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}hora_fin'],
          )!,
      cruzaMedianoche:
          attachedDatabase.typeMapping.read(
            DriftSqlType.bool,
            data['${effectivePrefix}cruza_medianoche'],
          )!,
      activo:
          attachedDatabase.typeMapping.read(
            DriftSqlType.bool,
            data['${effectivePrefix}activo'],
          )!,
    );
  }

  @override
  $HorarioDetalleTable createAlias(String alias) {
    return $HorarioDetalleTable(attachedDatabase, alias);
  }
}

class HorarioDetalleData extends DataClass
    implements Insertable<HorarioDetalleData> {
  final int id;
  final String horarioId;

  /// 0 = lunes ... 6 = domingo.
  final int diaSemana;
  final int horaInicio;
  final int horaFin;
  final bool cruzaMedianoche;
  final bool activo;
  const HorarioDetalleData({
    required this.id,
    required this.horarioId,
    required this.diaSemana,
    required this.horaInicio,
    required this.horaFin,
    required this.cruzaMedianoche,
    required this.activo,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['horario_id'] = Variable<String>(horarioId);
    map['dia_semana'] = Variable<int>(diaSemana);
    map['hora_inicio'] = Variable<int>(horaInicio);
    map['hora_fin'] = Variable<int>(horaFin);
    map['cruza_medianoche'] = Variable<bool>(cruzaMedianoche);
    map['activo'] = Variable<bool>(activo);
    return map;
  }

  HorarioDetalleCompanion toCompanion(bool nullToAbsent) {
    return HorarioDetalleCompanion(
      id: Value(id),
      horarioId: Value(horarioId),
      diaSemana: Value(diaSemana),
      horaInicio: Value(horaInicio),
      horaFin: Value(horaFin),
      cruzaMedianoche: Value(cruzaMedianoche),
      activo: Value(activo),
    );
  }

  factory HorarioDetalleData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HorarioDetalleData(
      id: serializer.fromJson<int>(json['id']),
      horarioId: serializer.fromJson<String>(json['horarioId']),
      diaSemana: serializer.fromJson<int>(json['diaSemana']),
      horaInicio: serializer.fromJson<int>(json['horaInicio']),
      horaFin: serializer.fromJson<int>(json['horaFin']),
      cruzaMedianoche: serializer.fromJson<bool>(json['cruzaMedianoche']),
      activo: serializer.fromJson<bool>(json['activo']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'horarioId': serializer.toJson<String>(horarioId),
      'diaSemana': serializer.toJson<int>(diaSemana),
      'horaInicio': serializer.toJson<int>(horaInicio),
      'horaFin': serializer.toJson<int>(horaFin),
      'cruzaMedianoche': serializer.toJson<bool>(cruzaMedianoche),
      'activo': serializer.toJson<bool>(activo),
    };
  }

  HorarioDetalleData copyWith({
    int? id,
    String? horarioId,
    int? diaSemana,
    int? horaInicio,
    int? horaFin,
    bool? cruzaMedianoche,
    bool? activo,
  }) => HorarioDetalleData(
    id: id ?? this.id,
    horarioId: horarioId ?? this.horarioId,
    diaSemana: diaSemana ?? this.diaSemana,
    horaInicio: horaInicio ?? this.horaInicio,
    horaFin: horaFin ?? this.horaFin,
    cruzaMedianoche: cruzaMedianoche ?? this.cruzaMedianoche,
    activo: activo ?? this.activo,
  );
  HorarioDetalleData copyWithCompanion(HorarioDetalleCompanion data) {
    return HorarioDetalleData(
      id: data.id.present ? data.id.value : this.id,
      horarioId: data.horarioId.present ? data.horarioId.value : this.horarioId,
      diaSemana: data.diaSemana.present ? data.diaSemana.value : this.diaSemana,
      horaInicio:
          data.horaInicio.present ? data.horaInicio.value : this.horaInicio,
      horaFin: data.horaFin.present ? data.horaFin.value : this.horaFin,
      cruzaMedianoche:
          data.cruzaMedianoche.present
              ? data.cruzaMedianoche.value
              : this.cruzaMedianoche,
      activo: data.activo.present ? data.activo.value : this.activo,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HorarioDetalleData(')
          ..write('id: $id, ')
          ..write('horarioId: $horarioId, ')
          ..write('diaSemana: $diaSemana, ')
          ..write('horaInicio: $horaInicio, ')
          ..write('horaFin: $horaFin, ')
          ..write('cruzaMedianoche: $cruzaMedianoche, ')
          ..write('activo: $activo')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    horarioId,
    diaSemana,
    horaInicio,
    horaFin,
    cruzaMedianoche,
    activo,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HorarioDetalleData &&
          other.id == this.id &&
          other.horarioId == this.horarioId &&
          other.diaSemana == this.diaSemana &&
          other.horaInicio == this.horaInicio &&
          other.horaFin == this.horaFin &&
          other.cruzaMedianoche == this.cruzaMedianoche &&
          other.activo == this.activo);
}

class HorarioDetalleCompanion extends UpdateCompanion<HorarioDetalleData> {
  final Value<int> id;
  final Value<String> horarioId;
  final Value<int> diaSemana;
  final Value<int> horaInicio;
  final Value<int> horaFin;
  final Value<bool> cruzaMedianoche;
  final Value<bool> activo;
  const HorarioDetalleCompanion({
    this.id = const Value.absent(),
    this.horarioId = const Value.absent(),
    this.diaSemana = const Value.absent(),
    this.horaInicio = const Value.absent(),
    this.horaFin = const Value.absent(),
    this.cruzaMedianoche = const Value.absent(),
    this.activo = const Value.absent(),
  });
  HorarioDetalleCompanion.insert({
    this.id = const Value.absent(),
    required String horarioId,
    required int diaSemana,
    required int horaInicio,
    required int horaFin,
    this.cruzaMedianoche = const Value.absent(),
    this.activo = const Value.absent(),
  }) : horarioId = Value(horarioId),
       diaSemana = Value(diaSemana),
       horaInicio = Value(horaInicio),
       horaFin = Value(horaFin);
  static Insertable<HorarioDetalleData> custom({
    Expression<int>? id,
    Expression<String>? horarioId,
    Expression<int>? diaSemana,
    Expression<int>? horaInicio,
    Expression<int>? horaFin,
    Expression<bool>? cruzaMedianoche,
    Expression<bool>? activo,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (horarioId != null) 'horario_id': horarioId,
      if (diaSemana != null) 'dia_semana': diaSemana,
      if (horaInicio != null) 'hora_inicio': horaInicio,
      if (horaFin != null) 'hora_fin': horaFin,
      if (cruzaMedianoche != null) 'cruza_medianoche': cruzaMedianoche,
      if (activo != null) 'activo': activo,
    });
  }

  HorarioDetalleCompanion copyWith({
    Value<int>? id,
    Value<String>? horarioId,
    Value<int>? diaSemana,
    Value<int>? horaInicio,
    Value<int>? horaFin,
    Value<bool>? cruzaMedianoche,
    Value<bool>? activo,
  }) {
    return HorarioDetalleCompanion(
      id: id ?? this.id,
      horarioId: horarioId ?? this.horarioId,
      diaSemana: diaSemana ?? this.diaSemana,
      horaInicio: horaInicio ?? this.horaInicio,
      horaFin: horaFin ?? this.horaFin,
      cruzaMedianoche: cruzaMedianoche ?? this.cruzaMedianoche,
      activo: activo ?? this.activo,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (horarioId.present) {
      map['horario_id'] = Variable<String>(horarioId.value);
    }
    if (diaSemana.present) {
      map['dia_semana'] = Variable<int>(diaSemana.value);
    }
    if (horaInicio.present) {
      map['hora_inicio'] = Variable<int>(horaInicio.value);
    }
    if (horaFin.present) {
      map['hora_fin'] = Variable<int>(horaFin.value);
    }
    if (cruzaMedianoche.present) {
      map['cruza_medianoche'] = Variable<bool>(cruzaMedianoche.value);
    }
    if (activo.present) {
      map['activo'] = Variable<bool>(activo.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HorarioDetalleCompanion(')
          ..write('id: $id, ')
          ..write('horarioId: $horarioId, ')
          ..write('diaSemana: $diaSemana, ')
          ..write('horaInicio: $horaInicio, ')
          ..write('horaFin: $horaFin, ')
          ..write('cruzaMedianoche: $cruzaMedianoche, ')
          ..write('activo: $activo')
          ..write(')'))
        .toString();
  }
}

class $EmpresaTable extends Empresa with TableInfo<$EmpresaTable, EmpresaData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EmpresaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: () => const Uuid().v4(),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _cicloVidaRegistroMeta = const VerificationMeta(
    'cicloVidaRegistro',
  );
  @override
  late final GeneratedColumn<String> cicloVidaRegistro =
      GeneratedColumn<String>(
        'ciclo_vida_registro',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('activo'),
      );
  static const VerificationMeta _codigoMeta = const VerificationMeta('codigo');
  @override
  late final GeneratedColumn<String> codigo = GeneratedColumn<String>(
    'codigo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _razonSocialMeta = const VerificationMeta(
    'razonSocial',
  );
  @override
  late final GeneratedColumn<String> razonSocial = GeneratedColumn<String>(
    'razon_social',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nombreComercialMeta = const VerificationMeta(
    'nombreComercial',
  );
  @override
  late final GeneratedColumn<String> nombreComercial = GeneratedColumn<String>(
    'nombre_comercial',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rfcMeta = const VerificationMeta('rfc');
  @override
  late final GeneratedColumn<String> rfc = GeneratedColumn<String>(
    'rfc',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _representanteLegalMeta =
      const VerificationMeta('representanteLegal');
  @override
  late final GeneratedColumn<String> representanteLegal =
      GeneratedColumn<String>(
        'representante_legal',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _esloganMeta = const VerificationMeta(
    'eslogan',
  );
  @override
  late final GeneratedColumn<String> eslogan = GeneratedColumn<String>(
    'eslogan',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _logoAttachmentIdMeta = const VerificationMeta(
    'logoAttachmentId',
  );
  @override
  late final GeneratedColumn<String> logoAttachmentId = GeneratedColumn<String>(
    'logo_attachment_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES attachment (id) ON DELETE RESTRICT',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    createdAt,
    updatedAt,
    cicloVidaRegistro,
    codigo,
    razonSocial,
    nombreComercial,
    rfc,
    representanteLegal,
    eslogan,
    logoAttachmentId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'empresa';
  @override
  VerificationContext validateIntegrity(
    Insertable<EmpresaData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('ciclo_vida_registro')) {
      context.handle(
        _cicloVidaRegistroMeta,
        cicloVidaRegistro.isAcceptableOrUnknown(
          data['ciclo_vida_registro']!,
          _cicloVidaRegistroMeta,
        ),
      );
    }
    if (data.containsKey('codigo')) {
      context.handle(
        _codigoMeta,
        codigo.isAcceptableOrUnknown(data['codigo']!, _codigoMeta),
      );
    } else if (isInserting) {
      context.missing(_codigoMeta);
    }
    if (data.containsKey('razon_social')) {
      context.handle(
        _razonSocialMeta,
        razonSocial.isAcceptableOrUnknown(
          data['razon_social']!,
          _razonSocialMeta,
        ),
      );
    }
    if (data.containsKey('nombre_comercial')) {
      context.handle(
        _nombreComercialMeta,
        nombreComercial.isAcceptableOrUnknown(
          data['nombre_comercial']!,
          _nombreComercialMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_nombreComercialMeta);
    }
    if (data.containsKey('rfc')) {
      context.handle(
        _rfcMeta,
        rfc.isAcceptableOrUnknown(data['rfc']!, _rfcMeta),
      );
    }
    if (data.containsKey('representante_legal')) {
      context.handle(
        _representanteLegalMeta,
        representanteLegal.isAcceptableOrUnknown(
          data['representante_legal']!,
          _representanteLegalMeta,
        ),
      );
    }
    if (data.containsKey('eslogan')) {
      context.handle(
        _esloganMeta,
        eslogan.isAcceptableOrUnknown(data['eslogan']!, _esloganMeta),
      );
    }
    if (data.containsKey('logo_attachment_id')) {
      context.handle(
        _logoAttachmentIdMeta,
        logoAttachmentId.isAcceptableOrUnknown(
          data['logo_attachment_id']!,
          _logoAttachmentIdMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  EmpresaData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EmpresaData(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}id'],
          )!,
      createdAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}created_at'],
          )!,
      updatedAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}updated_at'],
          )!,
      cicloVidaRegistro:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}ciclo_vida_registro'],
          )!,
      codigo:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}codigo'],
          )!,
      razonSocial: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}razon_social'],
      ),
      nombreComercial:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}nombre_comercial'],
          )!,
      rfc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rfc'],
      ),
      representanteLegal: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}representante_legal'],
      ),
      eslogan: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}eslogan'],
      ),
      logoAttachmentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}logo_attachment_id'],
      ),
    );
  }

  @override
  $EmpresaTable createAlias(String alias) {
    return $EmpresaTable(attachedDatabase, alias);
  }
}

class EmpresaData extends DataClass implements Insertable<EmpresaData> {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String cicloVidaRegistro;
  final String codigo;
  final String? razonSocial;
  final String nombreComercial;
  final String? rfc;
  final String? representanteLegal;
  final String? eslogan;
  final String? logoAttachmentId;
  const EmpresaData({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required this.cicloVidaRegistro,
    required this.codigo,
    this.razonSocial,
    required this.nombreComercial,
    this.rfc,
    this.representanteLegal,
    this.eslogan,
    this.logoAttachmentId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['ciclo_vida_registro'] = Variable<String>(cicloVidaRegistro);
    map['codigo'] = Variable<String>(codigo);
    if (!nullToAbsent || razonSocial != null) {
      map['razon_social'] = Variable<String>(razonSocial);
    }
    map['nombre_comercial'] = Variable<String>(nombreComercial);
    if (!nullToAbsent || rfc != null) {
      map['rfc'] = Variable<String>(rfc);
    }
    if (!nullToAbsent || representanteLegal != null) {
      map['representante_legal'] = Variable<String>(representanteLegal);
    }
    if (!nullToAbsent || eslogan != null) {
      map['eslogan'] = Variable<String>(eslogan);
    }
    if (!nullToAbsent || logoAttachmentId != null) {
      map['logo_attachment_id'] = Variable<String>(logoAttachmentId);
    }
    return map;
  }

  EmpresaCompanion toCompanion(bool nullToAbsent) {
    return EmpresaCompanion(
      id: Value(id),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      cicloVidaRegistro: Value(cicloVidaRegistro),
      codigo: Value(codigo),
      razonSocial:
          razonSocial == null && nullToAbsent
              ? const Value.absent()
              : Value(razonSocial),
      nombreComercial: Value(nombreComercial),
      rfc: rfc == null && nullToAbsent ? const Value.absent() : Value(rfc),
      representanteLegal:
          representanteLegal == null && nullToAbsent
              ? const Value.absent()
              : Value(representanteLegal),
      eslogan:
          eslogan == null && nullToAbsent
              ? const Value.absent()
              : Value(eslogan),
      logoAttachmentId:
          logoAttachmentId == null && nullToAbsent
              ? const Value.absent()
              : Value(logoAttachmentId),
    );
  }

  factory EmpresaData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EmpresaData(
      id: serializer.fromJson<String>(json['id']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      cicloVidaRegistro: serializer.fromJson<String>(json['cicloVidaRegistro']),
      codigo: serializer.fromJson<String>(json['codigo']),
      razonSocial: serializer.fromJson<String?>(json['razonSocial']),
      nombreComercial: serializer.fromJson<String>(json['nombreComercial']),
      rfc: serializer.fromJson<String?>(json['rfc']),
      representanteLegal: serializer.fromJson<String?>(
        json['representanteLegal'],
      ),
      eslogan: serializer.fromJson<String?>(json['eslogan']),
      logoAttachmentId: serializer.fromJson<String?>(json['logoAttachmentId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'cicloVidaRegistro': serializer.toJson<String>(cicloVidaRegistro),
      'codigo': serializer.toJson<String>(codigo),
      'razonSocial': serializer.toJson<String?>(razonSocial),
      'nombreComercial': serializer.toJson<String>(nombreComercial),
      'rfc': serializer.toJson<String?>(rfc),
      'representanteLegal': serializer.toJson<String?>(representanteLegal),
      'eslogan': serializer.toJson<String?>(eslogan),
      'logoAttachmentId': serializer.toJson<String?>(logoAttachmentId),
    };
  }

  EmpresaData copyWith({
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? cicloVidaRegistro,
    String? codigo,
    Value<String?> razonSocial = const Value.absent(),
    String? nombreComercial,
    Value<String?> rfc = const Value.absent(),
    Value<String?> representanteLegal = const Value.absent(),
    Value<String?> eslogan = const Value.absent(),
    Value<String?> logoAttachmentId = const Value.absent(),
  }) => EmpresaData(
    id: id ?? this.id,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    cicloVidaRegistro: cicloVidaRegistro ?? this.cicloVidaRegistro,
    codigo: codigo ?? this.codigo,
    razonSocial: razonSocial.present ? razonSocial.value : this.razonSocial,
    nombreComercial: nombreComercial ?? this.nombreComercial,
    rfc: rfc.present ? rfc.value : this.rfc,
    representanteLegal:
        representanteLegal.present
            ? representanteLegal.value
            : this.representanteLegal,
    eslogan: eslogan.present ? eslogan.value : this.eslogan,
    logoAttachmentId:
        logoAttachmentId.present
            ? logoAttachmentId.value
            : this.logoAttachmentId,
  );
  EmpresaData copyWithCompanion(EmpresaCompanion data) {
    return EmpresaData(
      id: data.id.present ? data.id.value : this.id,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      cicloVidaRegistro:
          data.cicloVidaRegistro.present
              ? data.cicloVidaRegistro.value
              : this.cicloVidaRegistro,
      codigo: data.codigo.present ? data.codigo.value : this.codigo,
      razonSocial:
          data.razonSocial.present ? data.razonSocial.value : this.razonSocial,
      nombreComercial:
          data.nombreComercial.present
              ? data.nombreComercial.value
              : this.nombreComercial,
      rfc: data.rfc.present ? data.rfc.value : this.rfc,
      representanteLegal:
          data.representanteLegal.present
              ? data.representanteLegal.value
              : this.representanteLegal,
      eslogan: data.eslogan.present ? data.eslogan.value : this.eslogan,
      logoAttachmentId:
          data.logoAttachmentId.present
              ? data.logoAttachmentId.value
              : this.logoAttachmentId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EmpresaData(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('cicloVidaRegistro: $cicloVidaRegistro, ')
          ..write('codigo: $codigo, ')
          ..write('razonSocial: $razonSocial, ')
          ..write('nombreComercial: $nombreComercial, ')
          ..write('rfc: $rfc, ')
          ..write('representanteLegal: $representanteLegal, ')
          ..write('eslogan: $eslogan, ')
          ..write('logoAttachmentId: $logoAttachmentId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    createdAt,
    updatedAt,
    cicloVidaRegistro,
    codigo,
    razonSocial,
    nombreComercial,
    rfc,
    representanteLegal,
    eslogan,
    logoAttachmentId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EmpresaData &&
          other.id == this.id &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.cicloVidaRegistro == this.cicloVidaRegistro &&
          other.codigo == this.codigo &&
          other.razonSocial == this.razonSocial &&
          other.nombreComercial == this.nombreComercial &&
          other.rfc == this.rfc &&
          other.representanteLegal == this.representanteLegal &&
          other.eslogan == this.eslogan &&
          other.logoAttachmentId == this.logoAttachmentId);
}

class EmpresaCompanion extends UpdateCompanion<EmpresaData> {
  final Value<String> id;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<String> cicloVidaRegistro;
  final Value<String> codigo;
  final Value<String?> razonSocial;
  final Value<String> nombreComercial;
  final Value<String?> rfc;
  final Value<String?> representanteLegal;
  final Value<String?> eslogan;
  final Value<String?> logoAttachmentId;
  final Value<int> rowid;
  const EmpresaCompanion({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.cicloVidaRegistro = const Value.absent(),
    this.codigo = const Value.absent(),
    this.razonSocial = const Value.absent(),
    this.nombreComercial = const Value.absent(),
    this.rfc = const Value.absent(),
    this.representanteLegal = const Value.absent(),
    this.eslogan = const Value.absent(),
    this.logoAttachmentId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EmpresaCompanion.insert({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.cicloVidaRegistro = const Value.absent(),
    required String codigo,
    this.razonSocial = const Value.absent(),
    required String nombreComercial,
    this.rfc = const Value.absent(),
    this.representanteLegal = const Value.absent(),
    this.eslogan = const Value.absent(),
    this.logoAttachmentId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : codigo = Value(codigo),
       nombreComercial = Value(nombreComercial);
  static Insertable<EmpresaData> custom({
    Expression<String>? id,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<String>? cicloVidaRegistro,
    Expression<String>? codigo,
    Expression<String>? razonSocial,
    Expression<String>? nombreComercial,
    Expression<String>? rfc,
    Expression<String>? representanteLegal,
    Expression<String>? eslogan,
    Expression<String>? logoAttachmentId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (cicloVidaRegistro != null) 'ciclo_vida_registro': cicloVidaRegistro,
      if (codigo != null) 'codigo': codigo,
      if (razonSocial != null) 'razon_social': razonSocial,
      if (nombreComercial != null) 'nombre_comercial': nombreComercial,
      if (rfc != null) 'rfc': rfc,
      if (representanteLegal != null) 'representante_legal': representanteLegal,
      if (eslogan != null) 'eslogan': eslogan,
      if (logoAttachmentId != null) 'logo_attachment_id': logoAttachmentId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EmpresaCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<String>? cicloVidaRegistro,
    Value<String>? codigo,
    Value<String?>? razonSocial,
    Value<String>? nombreComercial,
    Value<String?>? rfc,
    Value<String?>? representanteLegal,
    Value<String?>? eslogan,
    Value<String?>? logoAttachmentId,
    Value<int>? rowid,
  }) {
    return EmpresaCompanion(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      cicloVidaRegistro: cicloVidaRegistro ?? this.cicloVidaRegistro,
      codigo: codigo ?? this.codigo,
      razonSocial: razonSocial ?? this.razonSocial,
      nombreComercial: nombreComercial ?? this.nombreComercial,
      rfc: rfc ?? this.rfc,
      representanteLegal: representanteLegal ?? this.representanteLegal,
      eslogan: eslogan ?? this.eslogan,
      logoAttachmentId: logoAttachmentId ?? this.logoAttachmentId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (cicloVidaRegistro.present) {
      map['ciclo_vida_registro'] = Variable<String>(cicloVidaRegistro.value);
    }
    if (codigo.present) {
      map['codigo'] = Variable<String>(codigo.value);
    }
    if (razonSocial.present) {
      map['razon_social'] = Variable<String>(razonSocial.value);
    }
    if (nombreComercial.present) {
      map['nombre_comercial'] = Variable<String>(nombreComercial.value);
    }
    if (rfc.present) {
      map['rfc'] = Variable<String>(rfc.value);
    }
    if (representanteLegal.present) {
      map['representante_legal'] = Variable<String>(representanteLegal.value);
    }
    if (eslogan.present) {
      map['eslogan'] = Variable<String>(eslogan.value);
    }
    if (logoAttachmentId.present) {
      map['logo_attachment_id'] = Variable<String>(logoAttachmentId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EmpresaCompanion(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('cicloVidaRegistro: $cicloVidaRegistro, ')
          ..write('codigo: $codigo, ')
          ..write('razonSocial: $razonSocial, ')
          ..write('nombreComercial: $nombreComercial, ')
          ..write('rfc: $rfc, ')
          ..write('representanteLegal: $representanteLegal, ')
          ..write('eslogan: $eslogan, ')
          ..write('logoAttachmentId: $logoAttachmentId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SucursalTable extends Sucursal
    with TableInfo<$SucursalTable, SucursalData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SucursalTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: () => const Uuid().v4(),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _cicloVidaRegistroMeta = const VerificationMeta(
    'cicloVidaRegistro',
  );
  @override
  late final GeneratedColumn<String> cicloVidaRegistro =
      GeneratedColumn<String>(
        'ciclo_vida_registro',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('activo'),
      );
  static const VerificationMeta _codigoMeta = const VerificationMeta('codigo');
  @override
  late final GeneratedColumn<String> codigo = GeneratedColumn<String>(
    'codigo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _nombreMeta = const VerificationMeta('nombre');
  @override
  late final GeneratedColumn<String> nombre = GeneratedColumn<String>(
    'nombre',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tipoSucursalIdMeta = const VerificationMeta(
    'tipoSucursalId',
  );
  @override
  late final GeneratedColumn<String> tipoSucursalId = GeneratedColumn<String>(
    'tipo_sucursal_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES tipo_sucursal (id)',
    ),
  );
  static const VerificationMeta _estadoOperativoMeta = const VerificationMeta(
    'estadoOperativo',
  );
  @override
  late final GeneratedColumn<String> estadoOperativo = GeneratedColumn<String>(
    'estado_operativo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('operando'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    createdAt,
    updatedAt,
    cicloVidaRegistro,
    codigo,
    nombre,
    tipoSucursalId,
    estadoOperativo,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sucursal';
  @override
  VerificationContext validateIntegrity(
    Insertable<SucursalData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('ciclo_vida_registro')) {
      context.handle(
        _cicloVidaRegistroMeta,
        cicloVidaRegistro.isAcceptableOrUnknown(
          data['ciclo_vida_registro']!,
          _cicloVidaRegistroMeta,
        ),
      );
    }
    if (data.containsKey('codigo')) {
      context.handle(
        _codigoMeta,
        codigo.isAcceptableOrUnknown(data['codigo']!, _codigoMeta),
      );
    } else if (isInserting) {
      context.missing(_codigoMeta);
    }
    if (data.containsKey('nombre')) {
      context.handle(
        _nombreMeta,
        nombre.isAcceptableOrUnknown(data['nombre']!, _nombreMeta),
      );
    } else if (isInserting) {
      context.missing(_nombreMeta);
    }
    if (data.containsKey('tipo_sucursal_id')) {
      context.handle(
        _tipoSucursalIdMeta,
        tipoSucursalId.isAcceptableOrUnknown(
          data['tipo_sucursal_id']!,
          _tipoSucursalIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_tipoSucursalIdMeta);
    }
    if (data.containsKey('estado_operativo')) {
      context.handle(
        _estadoOperativoMeta,
        estadoOperativo.isAcceptableOrUnknown(
          data['estado_operativo']!,
          _estadoOperativoMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SucursalData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SucursalData(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}id'],
          )!,
      createdAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}created_at'],
          )!,
      updatedAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}updated_at'],
          )!,
      cicloVidaRegistro:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}ciclo_vida_registro'],
          )!,
      codigo:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}codigo'],
          )!,
      nombre:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}nombre'],
          )!,
      tipoSucursalId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}tipo_sucursal_id'],
          )!,
      estadoOperativo:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}estado_operativo'],
          )!,
    );
  }

  @override
  $SucursalTable createAlias(String alias) {
    return $SucursalTable(attachedDatabase, alias);
  }
}

class SucursalData extends DataClass implements Insertable<SucursalData> {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String cicloVidaRegistro;
  final String codigo;
  final String nombre;
  final String tipoSucursalId;
  final String estadoOperativo;
  const SucursalData({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required this.cicloVidaRegistro,
    required this.codigo,
    required this.nombre,
    required this.tipoSucursalId,
    required this.estadoOperativo,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['ciclo_vida_registro'] = Variable<String>(cicloVidaRegistro);
    map['codigo'] = Variable<String>(codigo);
    map['nombre'] = Variable<String>(nombre);
    map['tipo_sucursal_id'] = Variable<String>(tipoSucursalId);
    map['estado_operativo'] = Variable<String>(estadoOperativo);
    return map;
  }

  SucursalCompanion toCompanion(bool nullToAbsent) {
    return SucursalCompanion(
      id: Value(id),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      cicloVidaRegistro: Value(cicloVidaRegistro),
      codigo: Value(codigo),
      nombre: Value(nombre),
      tipoSucursalId: Value(tipoSucursalId),
      estadoOperativo: Value(estadoOperativo),
    );
  }

  factory SucursalData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SucursalData(
      id: serializer.fromJson<String>(json['id']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      cicloVidaRegistro: serializer.fromJson<String>(json['cicloVidaRegistro']),
      codigo: serializer.fromJson<String>(json['codigo']),
      nombre: serializer.fromJson<String>(json['nombre']),
      tipoSucursalId: serializer.fromJson<String>(json['tipoSucursalId']),
      estadoOperativo: serializer.fromJson<String>(json['estadoOperativo']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'cicloVidaRegistro': serializer.toJson<String>(cicloVidaRegistro),
      'codigo': serializer.toJson<String>(codigo),
      'nombre': serializer.toJson<String>(nombre),
      'tipoSucursalId': serializer.toJson<String>(tipoSucursalId),
      'estadoOperativo': serializer.toJson<String>(estadoOperativo),
    };
  }

  SucursalData copyWith({
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? cicloVidaRegistro,
    String? codigo,
    String? nombre,
    String? tipoSucursalId,
    String? estadoOperativo,
  }) => SucursalData(
    id: id ?? this.id,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    cicloVidaRegistro: cicloVidaRegistro ?? this.cicloVidaRegistro,
    codigo: codigo ?? this.codigo,
    nombre: nombre ?? this.nombre,
    tipoSucursalId: tipoSucursalId ?? this.tipoSucursalId,
    estadoOperativo: estadoOperativo ?? this.estadoOperativo,
  );
  SucursalData copyWithCompanion(SucursalCompanion data) {
    return SucursalData(
      id: data.id.present ? data.id.value : this.id,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      cicloVidaRegistro:
          data.cicloVidaRegistro.present
              ? data.cicloVidaRegistro.value
              : this.cicloVidaRegistro,
      codigo: data.codigo.present ? data.codigo.value : this.codigo,
      nombre: data.nombre.present ? data.nombre.value : this.nombre,
      tipoSucursalId:
          data.tipoSucursalId.present
              ? data.tipoSucursalId.value
              : this.tipoSucursalId,
      estadoOperativo:
          data.estadoOperativo.present
              ? data.estadoOperativo.value
              : this.estadoOperativo,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SucursalData(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('cicloVidaRegistro: $cicloVidaRegistro, ')
          ..write('codigo: $codigo, ')
          ..write('nombre: $nombre, ')
          ..write('tipoSucursalId: $tipoSucursalId, ')
          ..write('estadoOperativo: $estadoOperativo')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    createdAt,
    updatedAt,
    cicloVidaRegistro,
    codigo,
    nombre,
    tipoSucursalId,
    estadoOperativo,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SucursalData &&
          other.id == this.id &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.cicloVidaRegistro == this.cicloVidaRegistro &&
          other.codigo == this.codigo &&
          other.nombre == this.nombre &&
          other.tipoSucursalId == this.tipoSucursalId &&
          other.estadoOperativo == this.estadoOperativo);
}

class SucursalCompanion extends UpdateCompanion<SucursalData> {
  final Value<String> id;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<String> cicloVidaRegistro;
  final Value<String> codigo;
  final Value<String> nombre;
  final Value<String> tipoSucursalId;
  final Value<String> estadoOperativo;
  final Value<int> rowid;
  const SucursalCompanion({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.cicloVidaRegistro = const Value.absent(),
    this.codigo = const Value.absent(),
    this.nombre = const Value.absent(),
    this.tipoSucursalId = const Value.absent(),
    this.estadoOperativo = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SucursalCompanion.insert({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.cicloVidaRegistro = const Value.absent(),
    required String codigo,
    required String nombre,
    required String tipoSucursalId,
    this.estadoOperativo = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : codigo = Value(codigo),
       nombre = Value(nombre),
       tipoSucursalId = Value(tipoSucursalId);
  static Insertable<SucursalData> custom({
    Expression<String>? id,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<String>? cicloVidaRegistro,
    Expression<String>? codigo,
    Expression<String>? nombre,
    Expression<String>? tipoSucursalId,
    Expression<String>? estadoOperativo,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (cicloVidaRegistro != null) 'ciclo_vida_registro': cicloVidaRegistro,
      if (codigo != null) 'codigo': codigo,
      if (nombre != null) 'nombre': nombre,
      if (tipoSucursalId != null) 'tipo_sucursal_id': tipoSucursalId,
      if (estadoOperativo != null) 'estado_operativo': estadoOperativo,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SucursalCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<String>? cicloVidaRegistro,
    Value<String>? codigo,
    Value<String>? nombre,
    Value<String>? tipoSucursalId,
    Value<String>? estadoOperativo,
    Value<int>? rowid,
  }) {
    return SucursalCompanion(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      cicloVidaRegistro: cicloVidaRegistro ?? this.cicloVidaRegistro,
      codigo: codigo ?? this.codigo,
      nombre: nombre ?? this.nombre,
      tipoSucursalId: tipoSucursalId ?? this.tipoSucursalId,
      estadoOperativo: estadoOperativo ?? this.estadoOperativo,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (cicloVidaRegistro.present) {
      map['ciclo_vida_registro'] = Variable<String>(cicloVidaRegistro.value);
    }
    if (codigo.present) {
      map['codigo'] = Variable<String>(codigo.value);
    }
    if (nombre.present) {
      map['nombre'] = Variable<String>(nombre.value);
    }
    if (tipoSucursalId.present) {
      map['tipo_sucursal_id'] = Variable<String>(tipoSucursalId.value);
    }
    if (estadoOperativo.present) {
      map['estado_operativo'] = Variable<String>(estadoOperativo.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SucursalCompanion(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('cicloVidaRegistro: $cicloVidaRegistro, ')
          ..write('codigo: $codigo, ')
          ..write('nombre: $nombre, ')
          ..write('tipoSucursalId: $tipoSucursalId, ')
          ..write('estadoOperativo: $estadoOperativo, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ClienteTable extends Cliente with TableInfo<$ClienteTable, ClienteData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ClienteTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: () => const Uuid().v4(),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _cicloVidaRegistroMeta = const VerificationMeta(
    'cicloVidaRegistro',
  );
  @override
  late final GeneratedColumn<String> cicloVidaRegistro =
      GeneratedColumn<String>(
        'ciclo_vida_registro',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('activo'),
      );
  static const VerificationMeta _codigoMeta = const VerificationMeta('codigo');
  @override
  late final GeneratedColumn<String> codigo = GeneratedColumn<String>(
    'codigo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _razonSocialMeta = const VerificationMeta(
    'razonSocial',
  );
  @override
  late final GeneratedColumn<String> razonSocial = GeneratedColumn<String>(
    'razon_social',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nombreComercialMeta = const VerificationMeta(
    'nombreComercial',
  );
  @override
  late final GeneratedColumn<String> nombreComercial = GeneratedColumn<String>(
    'nombre_comercial',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rfcMeta = const VerificationMeta('rfc');
  @override
  late final GeneratedColumn<String> rfc = GeneratedColumn<String>(
    'rfc',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _industriaIdMeta = const VerificationMeta(
    'industriaId',
  );
  @override
  late final GeneratedColumn<String> industriaId = GeneratedColumn<String>(
    'industria_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES industria (id)',
    ),
  );
  static const VerificationMeta _estatusMeta = const VerificationMeta(
    'estatus',
  );
  @override
  late final GeneratedColumn<String> estatus = GeneratedColumn<String>(
    'estatus',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('prospecto'),
  );
  static const VerificationMeta _fechaAltaMeta = const VerificationMeta(
    'fechaAlta',
  );
  @override
  late final GeneratedColumn<DateTime> fechaAlta = GeneratedColumn<DateTime>(
    'fecha_alta',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _observacionesMeta = const VerificationMeta(
    'observaciones',
  );
  @override
  late final GeneratedColumn<String> observaciones = GeneratedColumn<String>(
    'observaciones',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    createdAt,
    updatedAt,
    cicloVidaRegistro,
    codigo,
    razonSocial,
    nombreComercial,
    rfc,
    industriaId,
    estatus,
    fechaAlta,
    observaciones,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cliente';
  @override
  VerificationContext validateIntegrity(
    Insertable<ClienteData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('ciclo_vida_registro')) {
      context.handle(
        _cicloVidaRegistroMeta,
        cicloVidaRegistro.isAcceptableOrUnknown(
          data['ciclo_vida_registro']!,
          _cicloVidaRegistroMeta,
        ),
      );
    }
    if (data.containsKey('codigo')) {
      context.handle(
        _codigoMeta,
        codigo.isAcceptableOrUnknown(data['codigo']!, _codigoMeta),
      );
    } else if (isInserting) {
      context.missing(_codigoMeta);
    }
    if (data.containsKey('razon_social')) {
      context.handle(
        _razonSocialMeta,
        razonSocial.isAcceptableOrUnknown(
          data['razon_social']!,
          _razonSocialMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_razonSocialMeta);
    }
    if (data.containsKey('nombre_comercial')) {
      context.handle(
        _nombreComercialMeta,
        nombreComercial.isAcceptableOrUnknown(
          data['nombre_comercial']!,
          _nombreComercialMeta,
        ),
      );
    }
    if (data.containsKey('rfc')) {
      context.handle(
        _rfcMeta,
        rfc.isAcceptableOrUnknown(data['rfc']!, _rfcMeta),
      );
    }
    if (data.containsKey('industria_id')) {
      context.handle(
        _industriaIdMeta,
        industriaId.isAcceptableOrUnknown(
          data['industria_id']!,
          _industriaIdMeta,
        ),
      );
    }
    if (data.containsKey('estatus')) {
      context.handle(
        _estatusMeta,
        estatus.isAcceptableOrUnknown(data['estatus']!, _estatusMeta),
      );
    }
    if (data.containsKey('fecha_alta')) {
      context.handle(
        _fechaAltaMeta,
        fechaAlta.isAcceptableOrUnknown(data['fecha_alta']!, _fechaAltaMeta),
      );
    }
    if (data.containsKey('observaciones')) {
      context.handle(
        _observacionesMeta,
        observaciones.isAcceptableOrUnknown(
          data['observaciones']!,
          _observacionesMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ClienteData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ClienteData(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}id'],
          )!,
      createdAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}created_at'],
          )!,
      updatedAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}updated_at'],
          )!,
      cicloVidaRegistro:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}ciclo_vida_registro'],
          )!,
      codigo:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}codigo'],
          )!,
      razonSocial:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}razon_social'],
          )!,
      nombreComercial: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}nombre_comercial'],
      ),
      rfc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rfc'],
      ),
      industriaId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}industria_id'],
      ),
      estatus:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}estatus'],
          )!,
      fechaAlta:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}fecha_alta'],
          )!,
      observaciones: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}observaciones'],
      ),
    );
  }

  @override
  $ClienteTable createAlias(String alias) {
    return $ClienteTable(attachedDatabase, alias);
  }
}

class ClienteData extends DataClass implements Insertable<ClienteData> {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String cicloVidaRegistro;
  final String codigo;
  final String razonSocial;
  final String? nombreComercial;

  /// Nullable — un Prospecto puede no tener RFC todavía. Normalización
  /// (mayúsculas, sin espacios) y validación de forma ocurren en
  /// `CrearClienteUseCase`, no aquí.
  final String? rfc;
  final String? industriaId;
  final String estatus;
  final DateTime fechaAlta;
  final String? observaciones;
  const ClienteData({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required this.cicloVidaRegistro,
    required this.codigo,
    required this.razonSocial,
    this.nombreComercial,
    this.rfc,
    this.industriaId,
    required this.estatus,
    required this.fechaAlta,
    this.observaciones,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['ciclo_vida_registro'] = Variable<String>(cicloVidaRegistro);
    map['codigo'] = Variable<String>(codigo);
    map['razon_social'] = Variable<String>(razonSocial);
    if (!nullToAbsent || nombreComercial != null) {
      map['nombre_comercial'] = Variable<String>(nombreComercial);
    }
    if (!nullToAbsent || rfc != null) {
      map['rfc'] = Variable<String>(rfc);
    }
    if (!nullToAbsent || industriaId != null) {
      map['industria_id'] = Variable<String>(industriaId);
    }
    map['estatus'] = Variable<String>(estatus);
    map['fecha_alta'] = Variable<DateTime>(fechaAlta);
    if (!nullToAbsent || observaciones != null) {
      map['observaciones'] = Variable<String>(observaciones);
    }
    return map;
  }

  ClienteCompanion toCompanion(bool nullToAbsent) {
    return ClienteCompanion(
      id: Value(id),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      cicloVidaRegistro: Value(cicloVidaRegistro),
      codigo: Value(codigo),
      razonSocial: Value(razonSocial),
      nombreComercial:
          nombreComercial == null && nullToAbsent
              ? const Value.absent()
              : Value(nombreComercial),
      rfc: rfc == null && nullToAbsent ? const Value.absent() : Value(rfc),
      industriaId:
          industriaId == null && nullToAbsent
              ? const Value.absent()
              : Value(industriaId),
      estatus: Value(estatus),
      fechaAlta: Value(fechaAlta),
      observaciones:
          observaciones == null && nullToAbsent
              ? const Value.absent()
              : Value(observaciones),
    );
  }

  factory ClienteData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ClienteData(
      id: serializer.fromJson<String>(json['id']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      cicloVidaRegistro: serializer.fromJson<String>(json['cicloVidaRegistro']),
      codigo: serializer.fromJson<String>(json['codigo']),
      razonSocial: serializer.fromJson<String>(json['razonSocial']),
      nombreComercial: serializer.fromJson<String?>(json['nombreComercial']),
      rfc: serializer.fromJson<String?>(json['rfc']),
      industriaId: serializer.fromJson<String?>(json['industriaId']),
      estatus: serializer.fromJson<String>(json['estatus']),
      fechaAlta: serializer.fromJson<DateTime>(json['fechaAlta']),
      observaciones: serializer.fromJson<String?>(json['observaciones']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'cicloVidaRegistro': serializer.toJson<String>(cicloVidaRegistro),
      'codigo': serializer.toJson<String>(codigo),
      'razonSocial': serializer.toJson<String>(razonSocial),
      'nombreComercial': serializer.toJson<String?>(nombreComercial),
      'rfc': serializer.toJson<String?>(rfc),
      'industriaId': serializer.toJson<String?>(industriaId),
      'estatus': serializer.toJson<String>(estatus),
      'fechaAlta': serializer.toJson<DateTime>(fechaAlta),
      'observaciones': serializer.toJson<String?>(observaciones),
    };
  }

  ClienteData copyWith({
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? cicloVidaRegistro,
    String? codigo,
    String? razonSocial,
    Value<String?> nombreComercial = const Value.absent(),
    Value<String?> rfc = const Value.absent(),
    Value<String?> industriaId = const Value.absent(),
    String? estatus,
    DateTime? fechaAlta,
    Value<String?> observaciones = const Value.absent(),
  }) => ClienteData(
    id: id ?? this.id,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    cicloVidaRegistro: cicloVidaRegistro ?? this.cicloVidaRegistro,
    codigo: codigo ?? this.codigo,
    razonSocial: razonSocial ?? this.razonSocial,
    nombreComercial:
        nombreComercial.present ? nombreComercial.value : this.nombreComercial,
    rfc: rfc.present ? rfc.value : this.rfc,
    industriaId: industriaId.present ? industriaId.value : this.industriaId,
    estatus: estatus ?? this.estatus,
    fechaAlta: fechaAlta ?? this.fechaAlta,
    observaciones:
        observaciones.present ? observaciones.value : this.observaciones,
  );
  ClienteData copyWithCompanion(ClienteCompanion data) {
    return ClienteData(
      id: data.id.present ? data.id.value : this.id,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      cicloVidaRegistro:
          data.cicloVidaRegistro.present
              ? data.cicloVidaRegistro.value
              : this.cicloVidaRegistro,
      codigo: data.codigo.present ? data.codigo.value : this.codigo,
      razonSocial:
          data.razonSocial.present ? data.razonSocial.value : this.razonSocial,
      nombreComercial:
          data.nombreComercial.present
              ? data.nombreComercial.value
              : this.nombreComercial,
      rfc: data.rfc.present ? data.rfc.value : this.rfc,
      industriaId:
          data.industriaId.present ? data.industriaId.value : this.industriaId,
      estatus: data.estatus.present ? data.estatus.value : this.estatus,
      fechaAlta: data.fechaAlta.present ? data.fechaAlta.value : this.fechaAlta,
      observaciones:
          data.observaciones.present
              ? data.observaciones.value
              : this.observaciones,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ClienteData(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('cicloVidaRegistro: $cicloVidaRegistro, ')
          ..write('codigo: $codigo, ')
          ..write('razonSocial: $razonSocial, ')
          ..write('nombreComercial: $nombreComercial, ')
          ..write('rfc: $rfc, ')
          ..write('industriaId: $industriaId, ')
          ..write('estatus: $estatus, ')
          ..write('fechaAlta: $fechaAlta, ')
          ..write('observaciones: $observaciones')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    createdAt,
    updatedAt,
    cicloVidaRegistro,
    codigo,
    razonSocial,
    nombreComercial,
    rfc,
    industriaId,
    estatus,
    fechaAlta,
    observaciones,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ClienteData &&
          other.id == this.id &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.cicloVidaRegistro == this.cicloVidaRegistro &&
          other.codigo == this.codigo &&
          other.razonSocial == this.razonSocial &&
          other.nombreComercial == this.nombreComercial &&
          other.rfc == this.rfc &&
          other.industriaId == this.industriaId &&
          other.estatus == this.estatus &&
          other.fechaAlta == this.fechaAlta &&
          other.observaciones == this.observaciones);
}

class ClienteCompanion extends UpdateCompanion<ClienteData> {
  final Value<String> id;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<String> cicloVidaRegistro;
  final Value<String> codigo;
  final Value<String> razonSocial;
  final Value<String?> nombreComercial;
  final Value<String?> rfc;
  final Value<String?> industriaId;
  final Value<String> estatus;
  final Value<DateTime> fechaAlta;
  final Value<String?> observaciones;
  final Value<int> rowid;
  const ClienteCompanion({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.cicloVidaRegistro = const Value.absent(),
    this.codigo = const Value.absent(),
    this.razonSocial = const Value.absent(),
    this.nombreComercial = const Value.absent(),
    this.rfc = const Value.absent(),
    this.industriaId = const Value.absent(),
    this.estatus = const Value.absent(),
    this.fechaAlta = const Value.absent(),
    this.observaciones = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ClienteCompanion.insert({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.cicloVidaRegistro = const Value.absent(),
    required String codigo,
    required String razonSocial,
    this.nombreComercial = const Value.absent(),
    this.rfc = const Value.absent(),
    this.industriaId = const Value.absent(),
    this.estatus = const Value.absent(),
    this.fechaAlta = const Value.absent(),
    this.observaciones = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : codigo = Value(codigo),
       razonSocial = Value(razonSocial);
  static Insertable<ClienteData> custom({
    Expression<String>? id,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<String>? cicloVidaRegistro,
    Expression<String>? codigo,
    Expression<String>? razonSocial,
    Expression<String>? nombreComercial,
    Expression<String>? rfc,
    Expression<String>? industriaId,
    Expression<String>? estatus,
    Expression<DateTime>? fechaAlta,
    Expression<String>? observaciones,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (cicloVidaRegistro != null) 'ciclo_vida_registro': cicloVidaRegistro,
      if (codigo != null) 'codigo': codigo,
      if (razonSocial != null) 'razon_social': razonSocial,
      if (nombreComercial != null) 'nombre_comercial': nombreComercial,
      if (rfc != null) 'rfc': rfc,
      if (industriaId != null) 'industria_id': industriaId,
      if (estatus != null) 'estatus': estatus,
      if (fechaAlta != null) 'fecha_alta': fechaAlta,
      if (observaciones != null) 'observaciones': observaciones,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ClienteCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<String>? cicloVidaRegistro,
    Value<String>? codigo,
    Value<String>? razonSocial,
    Value<String?>? nombreComercial,
    Value<String?>? rfc,
    Value<String?>? industriaId,
    Value<String>? estatus,
    Value<DateTime>? fechaAlta,
    Value<String?>? observaciones,
    Value<int>? rowid,
  }) {
    return ClienteCompanion(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      cicloVidaRegistro: cicloVidaRegistro ?? this.cicloVidaRegistro,
      codigo: codigo ?? this.codigo,
      razonSocial: razonSocial ?? this.razonSocial,
      nombreComercial: nombreComercial ?? this.nombreComercial,
      rfc: rfc ?? this.rfc,
      industriaId: industriaId ?? this.industriaId,
      estatus: estatus ?? this.estatus,
      fechaAlta: fechaAlta ?? this.fechaAlta,
      observaciones: observaciones ?? this.observaciones,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (cicloVidaRegistro.present) {
      map['ciclo_vida_registro'] = Variable<String>(cicloVidaRegistro.value);
    }
    if (codigo.present) {
      map['codigo'] = Variable<String>(codigo.value);
    }
    if (razonSocial.present) {
      map['razon_social'] = Variable<String>(razonSocial.value);
    }
    if (nombreComercial.present) {
      map['nombre_comercial'] = Variable<String>(nombreComercial.value);
    }
    if (rfc.present) {
      map['rfc'] = Variable<String>(rfc.value);
    }
    if (industriaId.present) {
      map['industria_id'] = Variable<String>(industriaId.value);
    }
    if (estatus.present) {
      map['estatus'] = Variable<String>(estatus.value);
    }
    if (fechaAlta.present) {
      map['fecha_alta'] = Variable<DateTime>(fechaAlta.value);
    }
    if (observaciones.present) {
      map['observaciones'] = Variable<String>(observaciones.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ClienteCompanion(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('cicloVidaRegistro: $cicloVidaRegistro, ')
          ..write('codigo: $codigo, ')
          ..write('razonSocial: $razonSocial, ')
          ..write('nombreComercial: $nombreComercial, ')
          ..write('rfc: $rfc, ')
          ..write('industriaId: $industriaId, ')
          ..write('estatus: $estatus, ')
          ..write('fechaAlta: $fechaAlta, ')
          ..write('observaciones: $observaciones, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ContactoTable extends Contacto
    with TableInfo<$ContactoTable, ContactoData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ContactoTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: () => const Uuid().v4(),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _cicloVidaRegistroMeta = const VerificationMeta(
    'cicloVidaRegistro',
  );
  @override
  late final GeneratedColumn<String> cicloVidaRegistro =
      GeneratedColumn<String>(
        'ciclo_vida_registro',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('activo'),
      );
  static const VerificationMeta _clienteIdMeta = const VerificationMeta(
    'clienteId',
  );
  @override
  late final GeneratedColumn<String> clienteId = GeneratedColumn<String>(
    'cliente_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES cliente (id) ON DELETE RESTRICT',
    ),
  );
  static const VerificationMeta _nombreMeta = const VerificationMeta('nombre');
  @override
  late final GeneratedColumn<String> nombre = GeneratedColumn<String>(
    'nombre',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _puestoMeta = const VerificationMeta('puesto');
  @override
  late final GeneratedColumn<String> puesto = GeneratedColumn<String>(
    'puesto',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _telefonoMeta = const VerificationMeta(
    'telefono',
  );
  @override
  late final GeneratedColumn<String> telefono = GeneratedColumn<String>(
    'telefono',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _correoMeta = const VerificationMeta('correo');
  @override
  late final GeneratedColumn<String> correo = GeneratedColumn<String>(
    'correo',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _esPrincipalMeta = const VerificationMeta(
    'esPrincipal',
  );
  @override
  late final GeneratedColumn<bool> esPrincipal = GeneratedColumn<bool>(
    'es_principal',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("es_principal" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    createdAt,
    updatedAt,
    cicloVidaRegistro,
    clienteId,
    nombre,
    puesto,
    telefono,
    correo,
    esPrincipal,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'contacto';
  @override
  VerificationContext validateIntegrity(
    Insertable<ContactoData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('ciclo_vida_registro')) {
      context.handle(
        _cicloVidaRegistroMeta,
        cicloVidaRegistro.isAcceptableOrUnknown(
          data['ciclo_vida_registro']!,
          _cicloVidaRegistroMeta,
        ),
      );
    }
    if (data.containsKey('cliente_id')) {
      context.handle(
        _clienteIdMeta,
        clienteId.isAcceptableOrUnknown(data['cliente_id']!, _clienteIdMeta),
      );
    } else if (isInserting) {
      context.missing(_clienteIdMeta);
    }
    if (data.containsKey('nombre')) {
      context.handle(
        _nombreMeta,
        nombre.isAcceptableOrUnknown(data['nombre']!, _nombreMeta),
      );
    } else if (isInserting) {
      context.missing(_nombreMeta);
    }
    if (data.containsKey('puesto')) {
      context.handle(
        _puestoMeta,
        puesto.isAcceptableOrUnknown(data['puesto']!, _puestoMeta),
      );
    }
    if (data.containsKey('telefono')) {
      context.handle(
        _telefonoMeta,
        telefono.isAcceptableOrUnknown(data['telefono']!, _telefonoMeta),
      );
    }
    if (data.containsKey('correo')) {
      context.handle(
        _correoMeta,
        correo.isAcceptableOrUnknown(data['correo']!, _correoMeta),
      );
    }
    if (data.containsKey('es_principal')) {
      context.handle(
        _esPrincipalMeta,
        esPrincipal.isAcceptableOrUnknown(
          data['es_principal']!,
          _esPrincipalMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ContactoData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ContactoData(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}id'],
          )!,
      createdAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}created_at'],
          )!,
      updatedAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}updated_at'],
          )!,
      cicloVidaRegistro:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}ciclo_vida_registro'],
          )!,
      clienteId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}cliente_id'],
          )!,
      nombre:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}nombre'],
          )!,
      puesto: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}puesto'],
      ),
      telefono: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}telefono'],
      ),
      correo: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}correo'],
      ),
      esPrincipal:
          attachedDatabase.typeMapping.read(
            DriftSqlType.bool,
            data['${effectivePrefix}es_principal'],
          )!,
    );
  }

  @override
  $ContactoTable createAlias(String alias) {
    return $ContactoTable(attachedDatabase, alias);
  }
}

class ContactoData extends DataClass implements Insertable<ContactoData> {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String cicloVidaRegistro;
  final String clienteId;
  final String nombre;
  final String? puesto;
  final String? telefono;
  final String? correo;
  final bool esPrincipal;
  const ContactoData({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required this.cicloVidaRegistro,
    required this.clienteId,
    required this.nombre,
    this.puesto,
    this.telefono,
    this.correo,
    required this.esPrincipal,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['ciclo_vida_registro'] = Variable<String>(cicloVidaRegistro);
    map['cliente_id'] = Variable<String>(clienteId);
    map['nombre'] = Variable<String>(nombre);
    if (!nullToAbsent || puesto != null) {
      map['puesto'] = Variable<String>(puesto);
    }
    if (!nullToAbsent || telefono != null) {
      map['telefono'] = Variable<String>(telefono);
    }
    if (!nullToAbsent || correo != null) {
      map['correo'] = Variable<String>(correo);
    }
    map['es_principal'] = Variable<bool>(esPrincipal);
    return map;
  }

  ContactoCompanion toCompanion(bool nullToAbsent) {
    return ContactoCompanion(
      id: Value(id),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      cicloVidaRegistro: Value(cicloVidaRegistro),
      clienteId: Value(clienteId),
      nombre: Value(nombre),
      puesto:
          puesto == null && nullToAbsent ? const Value.absent() : Value(puesto),
      telefono:
          telefono == null && nullToAbsent
              ? const Value.absent()
              : Value(telefono),
      correo:
          correo == null && nullToAbsent ? const Value.absent() : Value(correo),
      esPrincipal: Value(esPrincipal),
    );
  }

  factory ContactoData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ContactoData(
      id: serializer.fromJson<String>(json['id']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      cicloVidaRegistro: serializer.fromJson<String>(json['cicloVidaRegistro']),
      clienteId: serializer.fromJson<String>(json['clienteId']),
      nombre: serializer.fromJson<String>(json['nombre']),
      puesto: serializer.fromJson<String?>(json['puesto']),
      telefono: serializer.fromJson<String?>(json['telefono']),
      correo: serializer.fromJson<String?>(json['correo']),
      esPrincipal: serializer.fromJson<bool>(json['esPrincipal']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'cicloVidaRegistro': serializer.toJson<String>(cicloVidaRegistro),
      'clienteId': serializer.toJson<String>(clienteId),
      'nombre': serializer.toJson<String>(nombre),
      'puesto': serializer.toJson<String?>(puesto),
      'telefono': serializer.toJson<String?>(telefono),
      'correo': serializer.toJson<String?>(correo),
      'esPrincipal': serializer.toJson<bool>(esPrincipal),
    };
  }

  ContactoData copyWith({
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? cicloVidaRegistro,
    String? clienteId,
    String? nombre,
    Value<String?> puesto = const Value.absent(),
    Value<String?> telefono = const Value.absent(),
    Value<String?> correo = const Value.absent(),
    bool? esPrincipal,
  }) => ContactoData(
    id: id ?? this.id,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    cicloVidaRegistro: cicloVidaRegistro ?? this.cicloVidaRegistro,
    clienteId: clienteId ?? this.clienteId,
    nombre: nombre ?? this.nombre,
    puesto: puesto.present ? puesto.value : this.puesto,
    telefono: telefono.present ? telefono.value : this.telefono,
    correo: correo.present ? correo.value : this.correo,
    esPrincipal: esPrincipal ?? this.esPrincipal,
  );
  ContactoData copyWithCompanion(ContactoCompanion data) {
    return ContactoData(
      id: data.id.present ? data.id.value : this.id,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      cicloVidaRegistro:
          data.cicloVidaRegistro.present
              ? data.cicloVidaRegistro.value
              : this.cicloVidaRegistro,
      clienteId: data.clienteId.present ? data.clienteId.value : this.clienteId,
      nombre: data.nombre.present ? data.nombre.value : this.nombre,
      puesto: data.puesto.present ? data.puesto.value : this.puesto,
      telefono: data.telefono.present ? data.telefono.value : this.telefono,
      correo: data.correo.present ? data.correo.value : this.correo,
      esPrincipal:
          data.esPrincipal.present ? data.esPrincipal.value : this.esPrincipal,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ContactoData(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('cicloVidaRegistro: $cicloVidaRegistro, ')
          ..write('clienteId: $clienteId, ')
          ..write('nombre: $nombre, ')
          ..write('puesto: $puesto, ')
          ..write('telefono: $telefono, ')
          ..write('correo: $correo, ')
          ..write('esPrincipal: $esPrincipal')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    createdAt,
    updatedAt,
    cicloVidaRegistro,
    clienteId,
    nombre,
    puesto,
    telefono,
    correo,
    esPrincipal,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ContactoData &&
          other.id == this.id &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.cicloVidaRegistro == this.cicloVidaRegistro &&
          other.clienteId == this.clienteId &&
          other.nombre == this.nombre &&
          other.puesto == this.puesto &&
          other.telefono == this.telefono &&
          other.correo == this.correo &&
          other.esPrincipal == this.esPrincipal);
}

class ContactoCompanion extends UpdateCompanion<ContactoData> {
  final Value<String> id;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<String> cicloVidaRegistro;
  final Value<String> clienteId;
  final Value<String> nombre;
  final Value<String?> puesto;
  final Value<String?> telefono;
  final Value<String?> correo;
  final Value<bool> esPrincipal;
  final Value<int> rowid;
  const ContactoCompanion({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.cicloVidaRegistro = const Value.absent(),
    this.clienteId = const Value.absent(),
    this.nombre = const Value.absent(),
    this.puesto = const Value.absent(),
    this.telefono = const Value.absent(),
    this.correo = const Value.absent(),
    this.esPrincipal = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ContactoCompanion.insert({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.cicloVidaRegistro = const Value.absent(),
    required String clienteId,
    required String nombre,
    this.puesto = const Value.absent(),
    this.telefono = const Value.absent(),
    this.correo = const Value.absent(),
    this.esPrincipal = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : clienteId = Value(clienteId),
       nombre = Value(nombre);
  static Insertable<ContactoData> custom({
    Expression<String>? id,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<String>? cicloVidaRegistro,
    Expression<String>? clienteId,
    Expression<String>? nombre,
    Expression<String>? puesto,
    Expression<String>? telefono,
    Expression<String>? correo,
    Expression<bool>? esPrincipal,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (cicloVidaRegistro != null) 'ciclo_vida_registro': cicloVidaRegistro,
      if (clienteId != null) 'cliente_id': clienteId,
      if (nombre != null) 'nombre': nombre,
      if (puesto != null) 'puesto': puesto,
      if (telefono != null) 'telefono': telefono,
      if (correo != null) 'correo': correo,
      if (esPrincipal != null) 'es_principal': esPrincipal,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ContactoCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<String>? cicloVidaRegistro,
    Value<String>? clienteId,
    Value<String>? nombre,
    Value<String?>? puesto,
    Value<String?>? telefono,
    Value<String?>? correo,
    Value<bool>? esPrincipal,
    Value<int>? rowid,
  }) {
    return ContactoCompanion(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      cicloVidaRegistro: cicloVidaRegistro ?? this.cicloVidaRegistro,
      clienteId: clienteId ?? this.clienteId,
      nombre: nombre ?? this.nombre,
      puesto: puesto ?? this.puesto,
      telefono: telefono ?? this.telefono,
      correo: correo ?? this.correo,
      esPrincipal: esPrincipal ?? this.esPrincipal,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (cicloVidaRegistro.present) {
      map['ciclo_vida_registro'] = Variable<String>(cicloVidaRegistro.value);
    }
    if (clienteId.present) {
      map['cliente_id'] = Variable<String>(clienteId.value);
    }
    if (nombre.present) {
      map['nombre'] = Variable<String>(nombre.value);
    }
    if (puesto.present) {
      map['puesto'] = Variable<String>(puesto.value);
    }
    if (telefono.present) {
      map['telefono'] = Variable<String>(telefono.value);
    }
    if (correo.present) {
      map['correo'] = Variable<String>(correo.value);
    }
    if (esPrincipal.present) {
      map['es_principal'] = Variable<bool>(esPrincipal.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ContactoCompanion(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('cicloVidaRegistro: $cicloVidaRegistro, ')
          ..write('clienteId: $clienteId, ')
          ..write('nombre: $nombre, ')
          ..write('puesto: $puesto, ')
          ..write('telefono: $telefono, ')
          ..write('correo: $correo, ')
          ..write('esPrincipal: $esPrincipal, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ServicioTable extends Servicio
    with TableInfo<$ServicioTable, ServicioData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ServicioTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: () => const Uuid().v4(),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _cicloVidaRegistroMeta = const VerificationMeta(
    'cicloVidaRegistro',
  );
  @override
  late final GeneratedColumn<String> cicloVidaRegistro =
      GeneratedColumn<String>(
        'ciclo_vida_registro',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('activo'),
      );
  static const VerificationMeta _codigoMeta = const VerificationMeta('codigo');
  @override
  late final GeneratedColumn<String> codigo = GeneratedColumn<String>(
    'codigo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _clienteIdMeta = const VerificationMeta(
    'clienteId',
  );
  @override
  late final GeneratedColumn<String> clienteId = GeneratedColumn<String>(
    'cliente_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES cliente (id) ON DELETE RESTRICT',
    ),
  );
  static const VerificationMeta _nombreMeta = const VerificationMeta('nombre');
  @override
  late final GeneratedColumn<String> nombre = GeneratedColumn<String>(
    'nombre',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tipoServicioIdMeta = const VerificationMeta(
    'tipoServicioId',
  );
  @override
  late final GeneratedColumn<String> tipoServicioId = GeneratedColumn<String>(
    'tipo_servicio_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES tipo_servicio (id)',
    ),
  );
  static const VerificationMeta _sucursalAdministrativaIdMeta =
      const VerificationMeta('sucursalAdministrativaId');
  @override
  late final GeneratedColumn<String> sucursalAdministrativaId =
      GeneratedColumn<String>(
        'sucursal_administrativa_id',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES sucursal (id) ON DELETE RESTRICT',
        ),
      );
  static const VerificationMeta _estatusMeta = const VerificationMeta(
    'estatus',
  );
  @override
  late final GeneratedColumn<String> estatus = GeneratedColumn<String>(
    'estatus',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('cotizado'),
  );
  static const VerificationMeta _fechaInicioMeta = const VerificationMeta(
    'fechaInicio',
  );
  @override
  late final GeneratedColumn<DateTime> fechaInicio = GeneratedColumn<DateTime>(
    'fecha_inicio',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fechaTerminoMeta = const VerificationMeta(
    'fechaTermino',
  );
  @override
  late final GeneratedColumn<DateTime> fechaTermino = GeneratedColumn<DateTime>(
    'fecha_termino',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _elementosAutorizadosMeta =
      const VerificationMeta('elementosAutorizados');
  @override
  late final GeneratedColumn<int> elementosAutorizados = GeneratedColumn<int>(
    'elementos_autorizados',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _responsableClienteContactoIdMeta =
      const VerificationMeta('responsableClienteContactoId');
  @override
  late final GeneratedColumn<String> responsableClienteContactoId =
      GeneratedColumn<String>(
        'responsable_cliente_contacto_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES contacto (id) ON DELETE RESTRICT',
        ),
      );
  static const VerificationMeta _observacionesMeta = const VerificationMeta(
    'observaciones',
  );
  @override
  late final GeneratedColumn<String> observaciones = GeneratedColumn<String>(
    'observaciones',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    createdAt,
    updatedAt,
    cicloVidaRegistro,
    codigo,
    clienteId,
    nombre,
    tipoServicioId,
    sucursalAdministrativaId,
    estatus,
    fechaInicio,
    fechaTermino,
    elementosAutorizados,
    responsableClienteContactoId,
    observaciones,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'servicio';
  @override
  VerificationContext validateIntegrity(
    Insertable<ServicioData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('ciclo_vida_registro')) {
      context.handle(
        _cicloVidaRegistroMeta,
        cicloVidaRegistro.isAcceptableOrUnknown(
          data['ciclo_vida_registro']!,
          _cicloVidaRegistroMeta,
        ),
      );
    }
    if (data.containsKey('codigo')) {
      context.handle(
        _codigoMeta,
        codigo.isAcceptableOrUnknown(data['codigo']!, _codigoMeta),
      );
    } else if (isInserting) {
      context.missing(_codigoMeta);
    }
    if (data.containsKey('cliente_id')) {
      context.handle(
        _clienteIdMeta,
        clienteId.isAcceptableOrUnknown(data['cliente_id']!, _clienteIdMeta),
      );
    } else if (isInserting) {
      context.missing(_clienteIdMeta);
    }
    if (data.containsKey('nombre')) {
      context.handle(
        _nombreMeta,
        nombre.isAcceptableOrUnknown(data['nombre']!, _nombreMeta),
      );
    } else if (isInserting) {
      context.missing(_nombreMeta);
    }
    if (data.containsKey('tipo_servicio_id')) {
      context.handle(
        _tipoServicioIdMeta,
        tipoServicioId.isAcceptableOrUnknown(
          data['tipo_servicio_id']!,
          _tipoServicioIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_tipoServicioIdMeta);
    }
    if (data.containsKey('sucursal_administrativa_id')) {
      context.handle(
        _sucursalAdministrativaIdMeta,
        sucursalAdministrativaId.isAcceptableOrUnknown(
          data['sucursal_administrativa_id']!,
          _sucursalAdministrativaIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sucursalAdministrativaIdMeta);
    }
    if (data.containsKey('estatus')) {
      context.handle(
        _estatusMeta,
        estatus.isAcceptableOrUnknown(data['estatus']!, _estatusMeta),
      );
    }
    if (data.containsKey('fecha_inicio')) {
      context.handle(
        _fechaInicioMeta,
        fechaInicio.isAcceptableOrUnknown(
          data['fecha_inicio']!,
          _fechaInicioMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_fechaInicioMeta);
    }
    if (data.containsKey('fecha_termino')) {
      context.handle(
        _fechaTerminoMeta,
        fechaTermino.isAcceptableOrUnknown(
          data['fecha_termino']!,
          _fechaTerminoMeta,
        ),
      );
    }
    if (data.containsKey('elementos_autorizados')) {
      context.handle(
        _elementosAutorizadosMeta,
        elementosAutorizados.isAcceptableOrUnknown(
          data['elementos_autorizados']!,
          _elementosAutorizadosMeta,
        ),
      );
    }
    if (data.containsKey('responsable_cliente_contacto_id')) {
      context.handle(
        _responsableClienteContactoIdMeta,
        responsableClienteContactoId.isAcceptableOrUnknown(
          data['responsable_cliente_contacto_id']!,
          _responsableClienteContactoIdMeta,
        ),
      );
    }
    if (data.containsKey('observaciones')) {
      context.handle(
        _observacionesMeta,
        observaciones.isAcceptableOrUnknown(
          data['observaciones']!,
          _observacionesMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ServicioData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ServicioData(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}id'],
          )!,
      createdAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}created_at'],
          )!,
      updatedAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}updated_at'],
          )!,
      cicloVidaRegistro:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}ciclo_vida_registro'],
          )!,
      codigo:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}codigo'],
          )!,
      clienteId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}cliente_id'],
          )!,
      nombre:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}nombre'],
          )!,
      tipoServicioId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}tipo_servicio_id'],
          )!,
      sucursalAdministrativaId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}sucursal_administrativa_id'],
          )!,
      estatus:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}estatus'],
          )!,
      fechaInicio:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}fecha_inicio'],
          )!,
      fechaTermino: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}fecha_termino'],
      ),
      elementosAutorizados:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}elementos_autorizados'],
          )!,
      responsableClienteContactoId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}responsable_cliente_contacto_id'],
      ),
      observaciones: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}observaciones'],
      ),
    );
  }

  @override
  $ServicioTable createAlias(String alias) {
    return $ServicioTable(attachedDatabase, alias);
  }
}

class ServicioData extends DataClass implements Insertable<ServicioData> {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String cicloVidaRegistro;
  final String codigo;
  final String clienteId;
  final String nombre;
  final String tipoServicioId;
  final String sucursalAdministrativaId;
  final String estatus;
  final DateTime fechaInicio;
  final DateTime? fechaTermino;
  final int elementosAutorizados;

  /// Debe pertenecer al mismo Cliente de este Servicio — no expresable
  /// como `CHECK` (requeriría una subconsulta entre tablas); se valida
  /// en `CrearServicioUseCase`/`ActualizarServicioUseCase` y se cubre
  /// con tests.
  final String? responsableClienteContactoId;
  final String? observaciones;
  const ServicioData({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required this.cicloVidaRegistro,
    required this.codigo,
    required this.clienteId,
    required this.nombre,
    required this.tipoServicioId,
    required this.sucursalAdministrativaId,
    required this.estatus,
    required this.fechaInicio,
    this.fechaTermino,
    required this.elementosAutorizados,
    this.responsableClienteContactoId,
    this.observaciones,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['ciclo_vida_registro'] = Variable<String>(cicloVidaRegistro);
    map['codigo'] = Variable<String>(codigo);
    map['cliente_id'] = Variable<String>(clienteId);
    map['nombre'] = Variable<String>(nombre);
    map['tipo_servicio_id'] = Variable<String>(tipoServicioId);
    map['sucursal_administrativa_id'] = Variable<String>(
      sucursalAdministrativaId,
    );
    map['estatus'] = Variable<String>(estatus);
    map['fecha_inicio'] = Variable<DateTime>(fechaInicio);
    if (!nullToAbsent || fechaTermino != null) {
      map['fecha_termino'] = Variable<DateTime>(fechaTermino);
    }
    map['elementos_autorizados'] = Variable<int>(elementosAutorizados);
    if (!nullToAbsent || responsableClienteContactoId != null) {
      map['responsable_cliente_contacto_id'] = Variable<String>(
        responsableClienteContactoId,
      );
    }
    if (!nullToAbsent || observaciones != null) {
      map['observaciones'] = Variable<String>(observaciones);
    }
    return map;
  }

  ServicioCompanion toCompanion(bool nullToAbsent) {
    return ServicioCompanion(
      id: Value(id),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      cicloVidaRegistro: Value(cicloVidaRegistro),
      codigo: Value(codigo),
      clienteId: Value(clienteId),
      nombre: Value(nombre),
      tipoServicioId: Value(tipoServicioId),
      sucursalAdministrativaId: Value(sucursalAdministrativaId),
      estatus: Value(estatus),
      fechaInicio: Value(fechaInicio),
      fechaTermino:
          fechaTermino == null && nullToAbsent
              ? const Value.absent()
              : Value(fechaTermino),
      elementosAutorizados: Value(elementosAutorizados),
      responsableClienteContactoId:
          responsableClienteContactoId == null && nullToAbsent
              ? const Value.absent()
              : Value(responsableClienteContactoId),
      observaciones:
          observaciones == null && nullToAbsent
              ? const Value.absent()
              : Value(observaciones),
    );
  }

  factory ServicioData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ServicioData(
      id: serializer.fromJson<String>(json['id']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      cicloVidaRegistro: serializer.fromJson<String>(json['cicloVidaRegistro']),
      codigo: serializer.fromJson<String>(json['codigo']),
      clienteId: serializer.fromJson<String>(json['clienteId']),
      nombre: serializer.fromJson<String>(json['nombre']),
      tipoServicioId: serializer.fromJson<String>(json['tipoServicioId']),
      sucursalAdministrativaId: serializer.fromJson<String>(
        json['sucursalAdministrativaId'],
      ),
      estatus: serializer.fromJson<String>(json['estatus']),
      fechaInicio: serializer.fromJson<DateTime>(json['fechaInicio']),
      fechaTermino: serializer.fromJson<DateTime?>(json['fechaTermino']),
      elementosAutorizados: serializer.fromJson<int>(
        json['elementosAutorizados'],
      ),
      responsableClienteContactoId: serializer.fromJson<String?>(
        json['responsableClienteContactoId'],
      ),
      observaciones: serializer.fromJson<String?>(json['observaciones']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'cicloVidaRegistro': serializer.toJson<String>(cicloVidaRegistro),
      'codigo': serializer.toJson<String>(codigo),
      'clienteId': serializer.toJson<String>(clienteId),
      'nombre': serializer.toJson<String>(nombre),
      'tipoServicioId': serializer.toJson<String>(tipoServicioId),
      'sucursalAdministrativaId': serializer.toJson<String>(
        sucursalAdministrativaId,
      ),
      'estatus': serializer.toJson<String>(estatus),
      'fechaInicio': serializer.toJson<DateTime>(fechaInicio),
      'fechaTermino': serializer.toJson<DateTime?>(fechaTermino),
      'elementosAutorizados': serializer.toJson<int>(elementosAutorizados),
      'responsableClienteContactoId': serializer.toJson<String?>(
        responsableClienteContactoId,
      ),
      'observaciones': serializer.toJson<String?>(observaciones),
    };
  }

  ServicioData copyWith({
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? cicloVidaRegistro,
    String? codigo,
    String? clienteId,
    String? nombre,
    String? tipoServicioId,
    String? sucursalAdministrativaId,
    String? estatus,
    DateTime? fechaInicio,
    Value<DateTime?> fechaTermino = const Value.absent(),
    int? elementosAutorizados,
    Value<String?> responsableClienteContactoId = const Value.absent(),
    Value<String?> observaciones = const Value.absent(),
  }) => ServicioData(
    id: id ?? this.id,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    cicloVidaRegistro: cicloVidaRegistro ?? this.cicloVidaRegistro,
    codigo: codigo ?? this.codigo,
    clienteId: clienteId ?? this.clienteId,
    nombre: nombre ?? this.nombre,
    tipoServicioId: tipoServicioId ?? this.tipoServicioId,
    sucursalAdministrativaId:
        sucursalAdministrativaId ?? this.sucursalAdministrativaId,
    estatus: estatus ?? this.estatus,
    fechaInicio: fechaInicio ?? this.fechaInicio,
    fechaTermino: fechaTermino.present ? fechaTermino.value : this.fechaTermino,
    elementosAutorizados: elementosAutorizados ?? this.elementosAutorizados,
    responsableClienteContactoId:
        responsableClienteContactoId.present
            ? responsableClienteContactoId.value
            : this.responsableClienteContactoId,
    observaciones:
        observaciones.present ? observaciones.value : this.observaciones,
  );
  ServicioData copyWithCompanion(ServicioCompanion data) {
    return ServicioData(
      id: data.id.present ? data.id.value : this.id,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      cicloVidaRegistro:
          data.cicloVidaRegistro.present
              ? data.cicloVidaRegistro.value
              : this.cicloVidaRegistro,
      codigo: data.codigo.present ? data.codigo.value : this.codigo,
      clienteId: data.clienteId.present ? data.clienteId.value : this.clienteId,
      nombre: data.nombre.present ? data.nombre.value : this.nombre,
      tipoServicioId:
          data.tipoServicioId.present
              ? data.tipoServicioId.value
              : this.tipoServicioId,
      sucursalAdministrativaId:
          data.sucursalAdministrativaId.present
              ? data.sucursalAdministrativaId.value
              : this.sucursalAdministrativaId,
      estatus: data.estatus.present ? data.estatus.value : this.estatus,
      fechaInicio:
          data.fechaInicio.present ? data.fechaInicio.value : this.fechaInicio,
      fechaTermino:
          data.fechaTermino.present
              ? data.fechaTermino.value
              : this.fechaTermino,
      elementosAutorizados:
          data.elementosAutorizados.present
              ? data.elementosAutorizados.value
              : this.elementosAutorizados,
      responsableClienteContactoId:
          data.responsableClienteContactoId.present
              ? data.responsableClienteContactoId.value
              : this.responsableClienteContactoId,
      observaciones:
          data.observaciones.present
              ? data.observaciones.value
              : this.observaciones,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ServicioData(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('cicloVidaRegistro: $cicloVidaRegistro, ')
          ..write('codigo: $codigo, ')
          ..write('clienteId: $clienteId, ')
          ..write('nombre: $nombre, ')
          ..write('tipoServicioId: $tipoServicioId, ')
          ..write('sucursalAdministrativaId: $sucursalAdministrativaId, ')
          ..write('estatus: $estatus, ')
          ..write('fechaInicio: $fechaInicio, ')
          ..write('fechaTermino: $fechaTermino, ')
          ..write('elementosAutorizados: $elementosAutorizados, ')
          ..write(
            'responsableClienteContactoId: $responsableClienteContactoId, ',
          )
          ..write('observaciones: $observaciones')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    createdAt,
    updatedAt,
    cicloVidaRegistro,
    codigo,
    clienteId,
    nombre,
    tipoServicioId,
    sucursalAdministrativaId,
    estatus,
    fechaInicio,
    fechaTermino,
    elementosAutorizados,
    responsableClienteContactoId,
    observaciones,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ServicioData &&
          other.id == this.id &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.cicloVidaRegistro == this.cicloVidaRegistro &&
          other.codigo == this.codigo &&
          other.clienteId == this.clienteId &&
          other.nombre == this.nombre &&
          other.tipoServicioId == this.tipoServicioId &&
          other.sucursalAdministrativaId == this.sucursalAdministrativaId &&
          other.estatus == this.estatus &&
          other.fechaInicio == this.fechaInicio &&
          other.fechaTermino == this.fechaTermino &&
          other.elementosAutorizados == this.elementosAutorizados &&
          other.responsableClienteContactoId ==
              this.responsableClienteContactoId &&
          other.observaciones == this.observaciones);
}

class ServicioCompanion extends UpdateCompanion<ServicioData> {
  final Value<String> id;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<String> cicloVidaRegistro;
  final Value<String> codigo;
  final Value<String> clienteId;
  final Value<String> nombre;
  final Value<String> tipoServicioId;
  final Value<String> sucursalAdministrativaId;
  final Value<String> estatus;
  final Value<DateTime> fechaInicio;
  final Value<DateTime?> fechaTermino;
  final Value<int> elementosAutorizados;
  final Value<String?> responsableClienteContactoId;
  final Value<String?> observaciones;
  final Value<int> rowid;
  const ServicioCompanion({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.cicloVidaRegistro = const Value.absent(),
    this.codigo = const Value.absent(),
    this.clienteId = const Value.absent(),
    this.nombre = const Value.absent(),
    this.tipoServicioId = const Value.absent(),
    this.sucursalAdministrativaId = const Value.absent(),
    this.estatus = const Value.absent(),
    this.fechaInicio = const Value.absent(),
    this.fechaTermino = const Value.absent(),
    this.elementosAutorizados = const Value.absent(),
    this.responsableClienteContactoId = const Value.absent(),
    this.observaciones = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ServicioCompanion.insert({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.cicloVidaRegistro = const Value.absent(),
    required String codigo,
    required String clienteId,
    required String nombre,
    required String tipoServicioId,
    required String sucursalAdministrativaId,
    this.estatus = const Value.absent(),
    required DateTime fechaInicio,
    this.fechaTermino = const Value.absent(),
    this.elementosAutorizados = const Value.absent(),
    this.responsableClienteContactoId = const Value.absent(),
    this.observaciones = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : codigo = Value(codigo),
       clienteId = Value(clienteId),
       nombre = Value(nombre),
       tipoServicioId = Value(tipoServicioId),
       sucursalAdministrativaId = Value(sucursalAdministrativaId),
       fechaInicio = Value(fechaInicio);
  static Insertable<ServicioData> custom({
    Expression<String>? id,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<String>? cicloVidaRegistro,
    Expression<String>? codigo,
    Expression<String>? clienteId,
    Expression<String>? nombre,
    Expression<String>? tipoServicioId,
    Expression<String>? sucursalAdministrativaId,
    Expression<String>? estatus,
    Expression<DateTime>? fechaInicio,
    Expression<DateTime>? fechaTermino,
    Expression<int>? elementosAutorizados,
    Expression<String>? responsableClienteContactoId,
    Expression<String>? observaciones,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (cicloVidaRegistro != null) 'ciclo_vida_registro': cicloVidaRegistro,
      if (codigo != null) 'codigo': codigo,
      if (clienteId != null) 'cliente_id': clienteId,
      if (nombre != null) 'nombre': nombre,
      if (tipoServicioId != null) 'tipo_servicio_id': tipoServicioId,
      if (sucursalAdministrativaId != null)
        'sucursal_administrativa_id': sucursalAdministrativaId,
      if (estatus != null) 'estatus': estatus,
      if (fechaInicio != null) 'fecha_inicio': fechaInicio,
      if (fechaTermino != null) 'fecha_termino': fechaTermino,
      if (elementosAutorizados != null)
        'elementos_autorizados': elementosAutorizados,
      if (responsableClienteContactoId != null)
        'responsable_cliente_contacto_id': responsableClienteContactoId,
      if (observaciones != null) 'observaciones': observaciones,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ServicioCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<String>? cicloVidaRegistro,
    Value<String>? codigo,
    Value<String>? clienteId,
    Value<String>? nombre,
    Value<String>? tipoServicioId,
    Value<String>? sucursalAdministrativaId,
    Value<String>? estatus,
    Value<DateTime>? fechaInicio,
    Value<DateTime?>? fechaTermino,
    Value<int>? elementosAutorizados,
    Value<String?>? responsableClienteContactoId,
    Value<String?>? observaciones,
    Value<int>? rowid,
  }) {
    return ServicioCompanion(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      cicloVidaRegistro: cicloVidaRegistro ?? this.cicloVidaRegistro,
      codigo: codigo ?? this.codigo,
      clienteId: clienteId ?? this.clienteId,
      nombre: nombre ?? this.nombre,
      tipoServicioId: tipoServicioId ?? this.tipoServicioId,
      sucursalAdministrativaId:
          sucursalAdministrativaId ?? this.sucursalAdministrativaId,
      estatus: estatus ?? this.estatus,
      fechaInicio: fechaInicio ?? this.fechaInicio,
      fechaTermino: fechaTermino ?? this.fechaTermino,
      elementosAutorizados: elementosAutorizados ?? this.elementosAutorizados,
      responsableClienteContactoId:
          responsableClienteContactoId ?? this.responsableClienteContactoId,
      observaciones: observaciones ?? this.observaciones,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (cicloVidaRegistro.present) {
      map['ciclo_vida_registro'] = Variable<String>(cicloVidaRegistro.value);
    }
    if (codigo.present) {
      map['codigo'] = Variable<String>(codigo.value);
    }
    if (clienteId.present) {
      map['cliente_id'] = Variable<String>(clienteId.value);
    }
    if (nombre.present) {
      map['nombre'] = Variable<String>(nombre.value);
    }
    if (tipoServicioId.present) {
      map['tipo_servicio_id'] = Variable<String>(tipoServicioId.value);
    }
    if (sucursalAdministrativaId.present) {
      map['sucursal_administrativa_id'] = Variable<String>(
        sucursalAdministrativaId.value,
      );
    }
    if (estatus.present) {
      map['estatus'] = Variable<String>(estatus.value);
    }
    if (fechaInicio.present) {
      map['fecha_inicio'] = Variable<DateTime>(fechaInicio.value);
    }
    if (fechaTermino.present) {
      map['fecha_termino'] = Variable<DateTime>(fechaTermino.value);
    }
    if (elementosAutorizados.present) {
      map['elementos_autorizados'] = Variable<int>(elementosAutorizados.value);
    }
    if (responsableClienteContactoId.present) {
      map['responsable_cliente_contacto_id'] = Variable<String>(
        responsableClienteContactoId.value,
      );
    }
    if (observaciones.present) {
      map['observaciones'] = Variable<String>(observaciones.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ServicioCompanion(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('cicloVidaRegistro: $cicloVidaRegistro, ')
          ..write('codigo: $codigo, ')
          ..write('clienteId: $clienteId, ')
          ..write('nombre: $nombre, ')
          ..write('tipoServicioId: $tipoServicioId, ')
          ..write('sucursalAdministrativaId: $sucursalAdministrativaId, ')
          ..write('estatus: $estatus, ')
          ..write('fechaInicio: $fechaInicio, ')
          ..write('fechaTermino: $fechaTermino, ')
          ..write('elementosAutorizados: $elementosAutorizados, ')
          ..write(
            'responsableClienteContactoId: $responsableClienteContactoId, ',
          )
          ..write('observaciones: $observaciones, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $UbicacionTable extends Ubicacion
    with TableInfo<$UbicacionTable, UbicacionData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UbicacionTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: () => const Uuid().v4(),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _cicloVidaRegistroMeta = const VerificationMeta(
    'cicloVidaRegistro',
  );
  @override
  late final GeneratedColumn<String> cicloVidaRegistro =
      GeneratedColumn<String>(
        'ciclo_vida_registro',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('activo'),
      );
  static const VerificationMeta _codigoMeta = const VerificationMeta('codigo');
  @override
  late final GeneratedColumn<String> codigo = GeneratedColumn<String>(
    'codigo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _nombreMeta = const VerificationMeta('nombre');
  @override
  late final GeneratedColumn<String> nombre = GeneratedColumn<String>(
    'nombre',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tipoUbicacionMeta = const VerificationMeta(
    'tipoUbicacion',
  );
  @override
  late final GeneratedColumn<String> tipoUbicacion = GeneratedColumn<String>(
    'tipo_ubicacion',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _parentIdMeta = const VerificationMeta(
    'parentId',
  );
  @override
  late final GeneratedColumn<String> parentId = GeneratedColumn<String>(
    'parent_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES ubicacion (id) ON DELETE RESTRICT',
    ),
  );
  static const VerificationMeta _sucursalIdMeta = const VerificationMeta(
    'sucursalId',
  );
  @override
  late final GeneratedColumn<String> sucursalId = GeneratedColumn<String>(
    'sucursal_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'UNIQUE REFERENCES sucursal (id) ON DELETE RESTRICT',
    ),
  );
  static const VerificationMeta _servicioIdMeta = const VerificationMeta(
    'servicioId',
  );
  @override
  late final GeneratedColumn<String> servicioId = GeneratedColumn<String>(
    'servicio_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'UNIQUE REFERENCES servicio (id) ON DELETE RESTRICT',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    createdAt,
    updatedAt,
    cicloVidaRegistro,
    codigo,
    nombre,
    tipoUbicacion,
    parentId,
    sucursalId,
    servicioId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ubicacion';
  @override
  VerificationContext validateIntegrity(
    Insertable<UbicacionData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('ciclo_vida_registro')) {
      context.handle(
        _cicloVidaRegistroMeta,
        cicloVidaRegistro.isAcceptableOrUnknown(
          data['ciclo_vida_registro']!,
          _cicloVidaRegistroMeta,
        ),
      );
    }
    if (data.containsKey('codigo')) {
      context.handle(
        _codigoMeta,
        codigo.isAcceptableOrUnknown(data['codigo']!, _codigoMeta),
      );
    } else if (isInserting) {
      context.missing(_codigoMeta);
    }
    if (data.containsKey('nombre')) {
      context.handle(
        _nombreMeta,
        nombre.isAcceptableOrUnknown(data['nombre']!, _nombreMeta),
      );
    } else if (isInserting) {
      context.missing(_nombreMeta);
    }
    if (data.containsKey('tipo_ubicacion')) {
      context.handle(
        _tipoUbicacionMeta,
        tipoUbicacion.isAcceptableOrUnknown(
          data['tipo_ubicacion']!,
          _tipoUbicacionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_tipoUbicacionMeta);
    }
    if (data.containsKey('parent_id')) {
      context.handle(
        _parentIdMeta,
        parentId.isAcceptableOrUnknown(data['parent_id']!, _parentIdMeta),
      );
    }
    if (data.containsKey('sucursal_id')) {
      context.handle(
        _sucursalIdMeta,
        sucursalId.isAcceptableOrUnknown(data['sucursal_id']!, _sucursalIdMeta),
      );
    }
    if (data.containsKey('servicio_id')) {
      context.handle(
        _servicioIdMeta,
        servicioId.isAcceptableOrUnknown(data['servicio_id']!, _servicioIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  UbicacionData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return UbicacionData(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}id'],
          )!,
      createdAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}created_at'],
          )!,
      updatedAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}updated_at'],
          )!,
      cicloVidaRegistro:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}ciclo_vida_registro'],
          )!,
      codigo:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}codigo'],
          )!,
      nombre:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}nombre'],
          )!,
      tipoUbicacion:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}tipo_ubicacion'],
          )!,
      parentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_id'],
      ),
      sucursalId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sucursal_id'],
      ),
      servicioId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}servicio_id'],
      ),
    );
  }

  @override
  $UbicacionTable createAlias(String alias) {
    return $UbicacionTable(attachedDatabase, alias);
  }
}

class UbicacionData extends DataClass implements Insertable<UbicacionData> {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String cicloVidaRegistro;
  final String codigo;
  final String nombre;
  final String tipoUbicacion;
  final String? parentId;
  final String? sucursalId;
  final String? servicioId;
  const UbicacionData({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required this.cicloVidaRegistro,
    required this.codigo,
    required this.nombre,
    required this.tipoUbicacion,
    this.parentId,
    this.sucursalId,
    this.servicioId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['ciclo_vida_registro'] = Variable<String>(cicloVidaRegistro);
    map['codigo'] = Variable<String>(codigo);
    map['nombre'] = Variable<String>(nombre);
    map['tipo_ubicacion'] = Variable<String>(tipoUbicacion);
    if (!nullToAbsent || parentId != null) {
      map['parent_id'] = Variable<String>(parentId);
    }
    if (!nullToAbsent || sucursalId != null) {
      map['sucursal_id'] = Variable<String>(sucursalId);
    }
    if (!nullToAbsent || servicioId != null) {
      map['servicio_id'] = Variable<String>(servicioId);
    }
    return map;
  }

  UbicacionCompanion toCompanion(bool nullToAbsent) {
    return UbicacionCompanion(
      id: Value(id),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      cicloVidaRegistro: Value(cicloVidaRegistro),
      codigo: Value(codigo),
      nombre: Value(nombre),
      tipoUbicacion: Value(tipoUbicacion),
      parentId:
          parentId == null && nullToAbsent
              ? const Value.absent()
              : Value(parentId),
      sucursalId:
          sucursalId == null && nullToAbsent
              ? const Value.absent()
              : Value(sucursalId),
      servicioId:
          servicioId == null && nullToAbsent
              ? const Value.absent()
              : Value(servicioId),
    );
  }

  factory UbicacionData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return UbicacionData(
      id: serializer.fromJson<String>(json['id']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      cicloVidaRegistro: serializer.fromJson<String>(json['cicloVidaRegistro']),
      codigo: serializer.fromJson<String>(json['codigo']),
      nombre: serializer.fromJson<String>(json['nombre']),
      tipoUbicacion: serializer.fromJson<String>(json['tipoUbicacion']),
      parentId: serializer.fromJson<String?>(json['parentId']),
      sucursalId: serializer.fromJson<String?>(json['sucursalId']),
      servicioId: serializer.fromJson<String?>(json['servicioId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'cicloVidaRegistro': serializer.toJson<String>(cicloVidaRegistro),
      'codigo': serializer.toJson<String>(codigo),
      'nombre': serializer.toJson<String>(nombre),
      'tipoUbicacion': serializer.toJson<String>(tipoUbicacion),
      'parentId': serializer.toJson<String?>(parentId),
      'sucursalId': serializer.toJson<String?>(sucursalId),
      'servicioId': serializer.toJson<String?>(servicioId),
    };
  }

  UbicacionData copyWith({
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? cicloVidaRegistro,
    String? codigo,
    String? nombre,
    String? tipoUbicacion,
    Value<String?> parentId = const Value.absent(),
    Value<String?> sucursalId = const Value.absent(),
    Value<String?> servicioId = const Value.absent(),
  }) => UbicacionData(
    id: id ?? this.id,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    cicloVidaRegistro: cicloVidaRegistro ?? this.cicloVidaRegistro,
    codigo: codigo ?? this.codigo,
    nombre: nombre ?? this.nombre,
    tipoUbicacion: tipoUbicacion ?? this.tipoUbicacion,
    parentId: parentId.present ? parentId.value : this.parentId,
    sucursalId: sucursalId.present ? sucursalId.value : this.sucursalId,
    servicioId: servicioId.present ? servicioId.value : this.servicioId,
  );
  UbicacionData copyWithCompanion(UbicacionCompanion data) {
    return UbicacionData(
      id: data.id.present ? data.id.value : this.id,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      cicloVidaRegistro:
          data.cicloVidaRegistro.present
              ? data.cicloVidaRegistro.value
              : this.cicloVidaRegistro,
      codigo: data.codigo.present ? data.codigo.value : this.codigo,
      nombre: data.nombre.present ? data.nombre.value : this.nombre,
      tipoUbicacion:
          data.tipoUbicacion.present
              ? data.tipoUbicacion.value
              : this.tipoUbicacion,
      parentId: data.parentId.present ? data.parentId.value : this.parentId,
      sucursalId:
          data.sucursalId.present ? data.sucursalId.value : this.sucursalId,
      servicioId:
          data.servicioId.present ? data.servicioId.value : this.servicioId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('UbicacionData(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('cicloVidaRegistro: $cicloVidaRegistro, ')
          ..write('codigo: $codigo, ')
          ..write('nombre: $nombre, ')
          ..write('tipoUbicacion: $tipoUbicacion, ')
          ..write('parentId: $parentId, ')
          ..write('sucursalId: $sucursalId, ')
          ..write('servicioId: $servicioId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    createdAt,
    updatedAt,
    cicloVidaRegistro,
    codigo,
    nombre,
    tipoUbicacion,
    parentId,
    sucursalId,
    servicioId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UbicacionData &&
          other.id == this.id &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.cicloVidaRegistro == this.cicloVidaRegistro &&
          other.codigo == this.codigo &&
          other.nombre == this.nombre &&
          other.tipoUbicacion == this.tipoUbicacion &&
          other.parentId == this.parentId &&
          other.sucursalId == this.sucursalId &&
          other.servicioId == this.servicioId);
}

class UbicacionCompanion extends UpdateCompanion<UbicacionData> {
  final Value<String> id;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<String> cicloVidaRegistro;
  final Value<String> codigo;
  final Value<String> nombre;
  final Value<String> tipoUbicacion;
  final Value<String?> parentId;
  final Value<String?> sucursalId;
  final Value<String?> servicioId;
  final Value<int> rowid;
  const UbicacionCompanion({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.cicloVidaRegistro = const Value.absent(),
    this.codigo = const Value.absent(),
    this.nombre = const Value.absent(),
    this.tipoUbicacion = const Value.absent(),
    this.parentId = const Value.absent(),
    this.sucursalId = const Value.absent(),
    this.servicioId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  UbicacionCompanion.insert({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.cicloVidaRegistro = const Value.absent(),
    required String codigo,
    required String nombre,
    required String tipoUbicacion,
    this.parentId = const Value.absent(),
    this.sucursalId = const Value.absent(),
    this.servicioId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : codigo = Value(codigo),
       nombre = Value(nombre),
       tipoUbicacion = Value(tipoUbicacion);
  static Insertable<UbicacionData> custom({
    Expression<String>? id,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<String>? cicloVidaRegistro,
    Expression<String>? codigo,
    Expression<String>? nombre,
    Expression<String>? tipoUbicacion,
    Expression<String>? parentId,
    Expression<String>? sucursalId,
    Expression<String>? servicioId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (cicloVidaRegistro != null) 'ciclo_vida_registro': cicloVidaRegistro,
      if (codigo != null) 'codigo': codigo,
      if (nombre != null) 'nombre': nombre,
      if (tipoUbicacion != null) 'tipo_ubicacion': tipoUbicacion,
      if (parentId != null) 'parent_id': parentId,
      if (sucursalId != null) 'sucursal_id': sucursalId,
      if (servicioId != null) 'servicio_id': servicioId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  UbicacionCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<String>? cicloVidaRegistro,
    Value<String>? codigo,
    Value<String>? nombre,
    Value<String>? tipoUbicacion,
    Value<String?>? parentId,
    Value<String?>? sucursalId,
    Value<String?>? servicioId,
    Value<int>? rowid,
  }) {
    return UbicacionCompanion(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      cicloVidaRegistro: cicloVidaRegistro ?? this.cicloVidaRegistro,
      codigo: codigo ?? this.codigo,
      nombre: nombre ?? this.nombre,
      tipoUbicacion: tipoUbicacion ?? this.tipoUbicacion,
      parentId: parentId ?? this.parentId,
      sucursalId: sucursalId ?? this.sucursalId,
      servicioId: servicioId ?? this.servicioId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (cicloVidaRegistro.present) {
      map['ciclo_vida_registro'] = Variable<String>(cicloVidaRegistro.value);
    }
    if (codigo.present) {
      map['codigo'] = Variable<String>(codigo.value);
    }
    if (nombre.present) {
      map['nombre'] = Variable<String>(nombre.value);
    }
    if (tipoUbicacion.present) {
      map['tipo_ubicacion'] = Variable<String>(tipoUbicacion.value);
    }
    if (parentId.present) {
      map['parent_id'] = Variable<String>(parentId.value);
    }
    if (sucursalId.present) {
      map['sucursal_id'] = Variable<String>(sucursalId.value);
    }
    if (servicioId.present) {
      map['servicio_id'] = Variable<String>(servicioId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UbicacionCompanion(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('cicloVidaRegistro: $cicloVidaRegistro, ')
          ..write('codigo: $codigo, ')
          ..write('nombre: $nombre, ')
          ..write('tipoUbicacion: $tipoUbicacion, ')
          ..write('parentId: $parentId, ')
          ..write('sucursalId: $sucursalId, ')
          ..write('servicioId: $servicioId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PuestoTable extends Puesto with TableInfo<$PuestoTable, PuestoData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PuestoTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: () => const Uuid().v4(),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _cicloVidaRegistroMeta = const VerificationMeta(
    'cicloVidaRegistro',
  );
  @override
  late final GeneratedColumn<String> cicloVidaRegistro =
      GeneratedColumn<String>(
        'ciclo_vida_registro',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('activo'),
      );
  static const VerificationMeta _codigoMeta = const VerificationMeta('codigo');
  @override
  late final GeneratedColumn<String> codigo = GeneratedColumn<String>(
    'codigo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _nombreMeta = const VerificationMeta('nombre');
  @override
  late final GeneratedColumn<String> nombre = GeneratedColumn<String>(
    'nombre',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _areaIdMeta = const VerificationMeta('areaId');
  @override
  late final GeneratedColumn<String> areaId = GeneratedColumn<String>(
    'area_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES area (id)',
    ),
  );
  static const VerificationMeta _tipoMeta = const VerificationMeta('tipo');
  @override
  late final GeneratedColumn<String> tipo = GeneratedColumn<String>(
    'tipo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descripcionMeta = const VerificationMeta(
    'descripcion',
  );
  @override
  late final GeneratedColumn<String> descripcion = GeneratedColumn<String>(
    'descripcion',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nivelJerarquicoMeta = const VerificationMeta(
    'nivelJerarquico',
  );
  @override
  late final GeneratedColumn<int> nivelJerarquico = GeneratedColumn<int>(
    'nivel_jerarquico',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    createdAt,
    updatedAt,
    cicloVidaRegistro,
    codigo,
    nombre,
    areaId,
    tipo,
    descripcion,
    nivelJerarquico,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'puesto';
  @override
  VerificationContext validateIntegrity(
    Insertable<PuestoData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('ciclo_vida_registro')) {
      context.handle(
        _cicloVidaRegistroMeta,
        cicloVidaRegistro.isAcceptableOrUnknown(
          data['ciclo_vida_registro']!,
          _cicloVidaRegistroMeta,
        ),
      );
    }
    if (data.containsKey('codigo')) {
      context.handle(
        _codigoMeta,
        codigo.isAcceptableOrUnknown(data['codigo']!, _codigoMeta),
      );
    } else if (isInserting) {
      context.missing(_codigoMeta);
    }
    if (data.containsKey('nombre')) {
      context.handle(
        _nombreMeta,
        nombre.isAcceptableOrUnknown(data['nombre']!, _nombreMeta),
      );
    } else if (isInserting) {
      context.missing(_nombreMeta);
    }
    if (data.containsKey('area_id')) {
      context.handle(
        _areaIdMeta,
        areaId.isAcceptableOrUnknown(data['area_id']!, _areaIdMeta),
      );
    } else if (isInserting) {
      context.missing(_areaIdMeta);
    }
    if (data.containsKey('tipo')) {
      context.handle(
        _tipoMeta,
        tipo.isAcceptableOrUnknown(data['tipo']!, _tipoMeta),
      );
    } else if (isInserting) {
      context.missing(_tipoMeta);
    }
    if (data.containsKey('descripcion')) {
      context.handle(
        _descripcionMeta,
        descripcion.isAcceptableOrUnknown(
          data['descripcion']!,
          _descripcionMeta,
        ),
      );
    }
    if (data.containsKey('nivel_jerarquico')) {
      context.handle(
        _nivelJerarquicoMeta,
        nivelJerarquico.isAcceptableOrUnknown(
          data['nivel_jerarquico']!,
          _nivelJerarquicoMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_nivelJerarquicoMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PuestoData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PuestoData(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}id'],
          )!,
      createdAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}created_at'],
          )!,
      updatedAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}updated_at'],
          )!,
      cicloVidaRegistro:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}ciclo_vida_registro'],
          )!,
      codigo:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}codigo'],
          )!,
      nombre:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}nombre'],
          )!,
      areaId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}area_id'],
          )!,
      tipo:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}tipo'],
          )!,
      descripcion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}descripcion'],
      ),
      nivelJerarquico:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}nivel_jerarquico'],
          )!,
    );
  }

  @override
  $PuestoTable createAlias(String alias) {
    return $PuestoTable(attachedDatabase, alias);
  }
}

class PuestoData extends DataClass implements Insertable<PuestoData> {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String cicloVidaRegistro;
  final String codigo;
  final String nombre;
  final String areaId;
  final String tipo;
  final String? descripcion;
  final int nivelJerarquico;
  const PuestoData({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required this.cicloVidaRegistro,
    required this.codigo,
    required this.nombre,
    required this.areaId,
    required this.tipo,
    this.descripcion,
    required this.nivelJerarquico,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['ciclo_vida_registro'] = Variable<String>(cicloVidaRegistro);
    map['codigo'] = Variable<String>(codigo);
    map['nombre'] = Variable<String>(nombre);
    map['area_id'] = Variable<String>(areaId);
    map['tipo'] = Variable<String>(tipo);
    if (!nullToAbsent || descripcion != null) {
      map['descripcion'] = Variable<String>(descripcion);
    }
    map['nivel_jerarquico'] = Variable<int>(nivelJerarquico);
    return map;
  }

  PuestoCompanion toCompanion(bool nullToAbsent) {
    return PuestoCompanion(
      id: Value(id),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      cicloVidaRegistro: Value(cicloVidaRegistro),
      codigo: Value(codigo),
      nombre: Value(nombre),
      areaId: Value(areaId),
      tipo: Value(tipo),
      descripcion:
          descripcion == null && nullToAbsent
              ? const Value.absent()
              : Value(descripcion),
      nivelJerarquico: Value(nivelJerarquico),
    );
  }

  factory PuestoData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PuestoData(
      id: serializer.fromJson<String>(json['id']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      cicloVidaRegistro: serializer.fromJson<String>(json['cicloVidaRegistro']),
      codigo: serializer.fromJson<String>(json['codigo']),
      nombre: serializer.fromJson<String>(json['nombre']),
      areaId: serializer.fromJson<String>(json['areaId']),
      tipo: serializer.fromJson<String>(json['tipo']),
      descripcion: serializer.fromJson<String?>(json['descripcion']),
      nivelJerarquico: serializer.fromJson<int>(json['nivelJerarquico']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'cicloVidaRegistro': serializer.toJson<String>(cicloVidaRegistro),
      'codigo': serializer.toJson<String>(codigo),
      'nombre': serializer.toJson<String>(nombre),
      'areaId': serializer.toJson<String>(areaId),
      'tipo': serializer.toJson<String>(tipo),
      'descripcion': serializer.toJson<String?>(descripcion),
      'nivelJerarquico': serializer.toJson<int>(nivelJerarquico),
    };
  }

  PuestoData copyWith({
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? cicloVidaRegistro,
    String? codigo,
    String? nombre,
    String? areaId,
    String? tipo,
    Value<String?> descripcion = const Value.absent(),
    int? nivelJerarquico,
  }) => PuestoData(
    id: id ?? this.id,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    cicloVidaRegistro: cicloVidaRegistro ?? this.cicloVidaRegistro,
    codigo: codigo ?? this.codigo,
    nombre: nombre ?? this.nombre,
    areaId: areaId ?? this.areaId,
    tipo: tipo ?? this.tipo,
    descripcion: descripcion.present ? descripcion.value : this.descripcion,
    nivelJerarquico: nivelJerarquico ?? this.nivelJerarquico,
  );
  PuestoData copyWithCompanion(PuestoCompanion data) {
    return PuestoData(
      id: data.id.present ? data.id.value : this.id,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      cicloVidaRegistro:
          data.cicloVidaRegistro.present
              ? data.cicloVidaRegistro.value
              : this.cicloVidaRegistro,
      codigo: data.codigo.present ? data.codigo.value : this.codigo,
      nombre: data.nombre.present ? data.nombre.value : this.nombre,
      areaId: data.areaId.present ? data.areaId.value : this.areaId,
      tipo: data.tipo.present ? data.tipo.value : this.tipo,
      descripcion:
          data.descripcion.present ? data.descripcion.value : this.descripcion,
      nivelJerarquico:
          data.nivelJerarquico.present
              ? data.nivelJerarquico.value
              : this.nivelJerarquico,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PuestoData(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('cicloVidaRegistro: $cicloVidaRegistro, ')
          ..write('codigo: $codigo, ')
          ..write('nombre: $nombre, ')
          ..write('areaId: $areaId, ')
          ..write('tipo: $tipo, ')
          ..write('descripcion: $descripcion, ')
          ..write('nivelJerarquico: $nivelJerarquico')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    createdAt,
    updatedAt,
    cicloVidaRegistro,
    codigo,
    nombre,
    areaId,
    tipo,
    descripcion,
    nivelJerarquico,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PuestoData &&
          other.id == this.id &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.cicloVidaRegistro == this.cicloVidaRegistro &&
          other.codigo == this.codigo &&
          other.nombre == this.nombre &&
          other.areaId == this.areaId &&
          other.tipo == this.tipo &&
          other.descripcion == this.descripcion &&
          other.nivelJerarquico == this.nivelJerarquico);
}

class PuestoCompanion extends UpdateCompanion<PuestoData> {
  final Value<String> id;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<String> cicloVidaRegistro;
  final Value<String> codigo;
  final Value<String> nombre;
  final Value<String> areaId;
  final Value<String> tipo;
  final Value<String?> descripcion;
  final Value<int> nivelJerarquico;
  final Value<int> rowid;
  const PuestoCompanion({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.cicloVidaRegistro = const Value.absent(),
    this.codigo = const Value.absent(),
    this.nombre = const Value.absent(),
    this.areaId = const Value.absent(),
    this.tipo = const Value.absent(),
    this.descripcion = const Value.absent(),
    this.nivelJerarquico = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PuestoCompanion.insert({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.cicloVidaRegistro = const Value.absent(),
    required String codigo,
    required String nombre,
    required String areaId,
    required String tipo,
    this.descripcion = const Value.absent(),
    required int nivelJerarquico,
    this.rowid = const Value.absent(),
  }) : codigo = Value(codigo),
       nombre = Value(nombre),
       areaId = Value(areaId),
       tipo = Value(tipo),
       nivelJerarquico = Value(nivelJerarquico);
  static Insertable<PuestoData> custom({
    Expression<String>? id,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<String>? cicloVidaRegistro,
    Expression<String>? codigo,
    Expression<String>? nombre,
    Expression<String>? areaId,
    Expression<String>? tipo,
    Expression<String>? descripcion,
    Expression<int>? nivelJerarquico,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (cicloVidaRegistro != null) 'ciclo_vida_registro': cicloVidaRegistro,
      if (codigo != null) 'codigo': codigo,
      if (nombre != null) 'nombre': nombre,
      if (areaId != null) 'area_id': areaId,
      if (tipo != null) 'tipo': tipo,
      if (descripcion != null) 'descripcion': descripcion,
      if (nivelJerarquico != null) 'nivel_jerarquico': nivelJerarquico,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PuestoCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<String>? cicloVidaRegistro,
    Value<String>? codigo,
    Value<String>? nombre,
    Value<String>? areaId,
    Value<String>? tipo,
    Value<String?>? descripcion,
    Value<int>? nivelJerarquico,
    Value<int>? rowid,
  }) {
    return PuestoCompanion(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      cicloVidaRegistro: cicloVidaRegistro ?? this.cicloVidaRegistro,
      codigo: codigo ?? this.codigo,
      nombre: nombre ?? this.nombre,
      areaId: areaId ?? this.areaId,
      tipo: tipo ?? this.tipo,
      descripcion: descripcion ?? this.descripcion,
      nivelJerarquico: nivelJerarquico ?? this.nivelJerarquico,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (cicloVidaRegistro.present) {
      map['ciclo_vida_registro'] = Variable<String>(cicloVidaRegistro.value);
    }
    if (codigo.present) {
      map['codigo'] = Variable<String>(codigo.value);
    }
    if (nombre.present) {
      map['nombre'] = Variable<String>(nombre.value);
    }
    if (areaId.present) {
      map['area_id'] = Variable<String>(areaId.value);
    }
    if (tipo.present) {
      map['tipo'] = Variable<String>(tipo.value);
    }
    if (descripcion.present) {
      map['descripcion'] = Variable<String>(descripcion.value);
    }
    if (nivelJerarquico.present) {
      map['nivel_jerarquico'] = Variable<int>(nivelJerarquico.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PuestoCompanion(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('cicloVidaRegistro: $cicloVidaRegistro, ')
          ..write('codigo: $codigo, ')
          ..write('nombre: $nombre, ')
          ..write('areaId: $areaId, ')
          ..write('tipo: $tipo, ')
          ..write('descripcion: $descripcion, ')
          ..write('nivelJerarquico: $nivelJerarquico, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $AppMetadataTable appMetadata = $AppMetadataTable(this);
  late final $CodigoSecuenciaTable codigoSecuencia = $CodigoSecuenciaTable(
    this,
  );
  late final $TipoSucursalTable tipoSucursal = $TipoSucursalTable(this);
  late final $IndustriaTable industria = $IndustriaTable(this);
  late final $TipoServicioTable tipoServicio = $TipoServicioTable(this);
  late final $AreaTable area = $AreaTable(this);
  late final $DireccionTable direccion = $DireccionTable(this);
  late final $MedioContactoTable medioContacto = $MedioContactoTable(this);
  late final $AttachmentTable attachment = $AttachmentTable(this);
  late final $HorarioTable horario = $HorarioTable(this);
  late final $HorarioDetalleTable horarioDetalle = $HorarioDetalleTable(this);
  late final $EmpresaTable empresa = $EmpresaTable(this);
  late final $SucursalTable sucursal = $SucursalTable(this);
  late final $ClienteTable cliente = $ClienteTable(this);
  late final $ContactoTable contacto = $ContactoTable(this);
  late final $ServicioTable servicio = $ServicioTable(this);
  late final $UbicacionTable ubicacion = $UbicacionTable(this);
  late final $PuestoTable puesto = $PuestoTable(this);
  late final Index idxDireccionClienteTipoPrincipal = Index(
    'idx_direccion_cliente_tipo_principal',
    'CREATE UNIQUE INDEX idx_direccion_cliente_tipo_principal ON direccion (cliente_id, tipo_direccion) WHERE es_principal = 1 AND cliente_id IS NOT NULL',
  );
  late final Index idxDireccionCliente = Index(
    'idx_direccion_cliente',
    'CREATE INDEX idx_direccion_cliente ON direccion (cliente_id)',
  );
  late final Index idxEmpresaActivaUnica = Index(
    'idx_empresa_activa_unica',
    'CREATE UNIQUE INDEX idx_empresa_activa_unica ON empresa (ciclo_vida_registro) WHERE ciclo_vida_registro = \'activo\'',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    appMetadata,
    codigoSecuencia,
    tipoSucursal,
    industria,
    tipoServicio,
    area,
    direccion,
    medioContacto,
    attachment,
    horario,
    horarioDetalle,
    empresa,
    sucursal,
    cliente,
    contacto,
    servicio,
    ubicacion,
    puesto,
    idxDireccionClienteTipoPrincipal,
    idxDireccionCliente,
    idxEmpresaActivaUnica,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'horario',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('horario_detalle', kind: UpdateKind.delete)],
    ),
  ]);
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
typedef $$CodigoSecuenciaTableCreateCompanionBuilder =
    CodigoSecuenciaCompanion Function({
      required String entityType,
      required String prefijo,
      required int digitos,
      Value<bool> reseteaAnualmente,
      Value<int?> anioActual,
      Value<int> contadorActual,
      Value<int> rowid,
    });
typedef $$CodigoSecuenciaTableUpdateCompanionBuilder =
    CodigoSecuenciaCompanion Function({
      Value<String> entityType,
      Value<String> prefijo,
      Value<int> digitos,
      Value<bool> reseteaAnualmente,
      Value<int?> anioActual,
      Value<int> contadorActual,
      Value<int> rowid,
    });

class $$CodigoSecuenciaTableFilterComposer
    extends Composer<_$AppDatabase, $CodigoSecuenciaTable> {
  $$CodigoSecuenciaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get prefijo => $composableBuilder(
    column: $table.prefijo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get digitos => $composableBuilder(
    column: $table.digitos,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get reseteaAnualmente => $composableBuilder(
    column: $table.reseteaAnualmente,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get anioActual => $composableBuilder(
    column: $table.anioActual,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get contadorActual => $composableBuilder(
    column: $table.contadorActual,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CodigoSecuenciaTableOrderingComposer
    extends Composer<_$AppDatabase, $CodigoSecuenciaTable> {
  $$CodigoSecuenciaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get prefijo => $composableBuilder(
    column: $table.prefijo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get digitos => $composableBuilder(
    column: $table.digitos,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get reseteaAnualmente => $composableBuilder(
    column: $table.reseteaAnualmente,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get anioActual => $composableBuilder(
    column: $table.anioActual,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get contadorActual => $composableBuilder(
    column: $table.contadorActual,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CodigoSecuenciaTableAnnotationComposer
    extends Composer<_$AppDatabase, $CodigoSecuenciaTable> {
  $$CodigoSecuenciaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get prefijo =>
      $composableBuilder(column: $table.prefijo, builder: (column) => column);

  GeneratedColumn<int> get digitos =>
      $composableBuilder(column: $table.digitos, builder: (column) => column);

  GeneratedColumn<bool> get reseteaAnualmente => $composableBuilder(
    column: $table.reseteaAnualmente,
    builder: (column) => column,
  );

  GeneratedColumn<int> get anioActual => $composableBuilder(
    column: $table.anioActual,
    builder: (column) => column,
  );

  GeneratedColumn<int> get contadorActual => $composableBuilder(
    column: $table.contadorActual,
    builder: (column) => column,
  );
}

class $$CodigoSecuenciaTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CodigoSecuenciaTable,
          CodigoSecuenciaData,
          $$CodigoSecuenciaTableFilterComposer,
          $$CodigoSecuenciaTableOrderingComposer,
          $$CodigoSecuenciaTableAnnotationComposer,
          $$CodigoSecuenciaTableCreateCompanionBuilder,
          $$CodigoSecuenciaTableUpdateCompanionBuilder,
          (
            CodigoSecuenciaData,
            BaseReferences<
              _$AppDatabase,
              $CodigoSecuenciaTable,
              CodigoSecuenciaData
            >,
          ),
          CodigoSecuenciaData,
          PrefetchHooks Function()
        > {
  $$CodigoSecuenciaTableTableManager(
    _$AppDatabase db,
    $CodigoSecuenciaTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () =>
                  $$CodigoSecuenciaTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$CodigoSecuenciaTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer:
              () => $$CodigoSecuenciaTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> entityType = const Value.absent(),
                Value<String> prefijo = const Value.absent(),
                Value<int> digitos = const Value.absent(),
                Value<bool> reseteaAnualmente = const Value.absent(),
                Value<int?> anioActual = const Value.absent(),
                Value<int> contadorActual = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CodigoSecuenciaCompanion(
                entityType: entityType,
                prefijo: prefijo,
                digitos: digitos,
                reseteaAnualmente: reseteaAnualmente,
                anioActual: anioActual,
                contadorActual: contadorActual,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String entityType,
                required String prefijo,
                required int digitos,
                Value<bool> reseteaAnualmente = const Value.absent(),
                Value<int?> anioActual = const Value.absent(),
                Value<int> contadorActual = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CodigoSecuenciaCompanion.insert(
                entityType: entityType,
                prefijo: prefijo,
                digitos: digitos,
                reseteaAnualmente: reseteaAnualmente,
                anioActual: anioActual,
                contadorActual: contadorActual,
                rowid: rowid,
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

typedef $$CodigoSecuenciaTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CodigoSecuenciaTable,
      CodigoSecuenciaData,
      $$CodigoSecuenciaTableFilterComposer,
      $$CodigoSecuenciaTableOrderingComposer,
      $$CodigoSecuenciaTableAnnotationComposer,
      $$CodigoSecuenciaTableCreateCompanionBuilder,
      $$CodigoSecuenciaTableUpdateCompanionBuilder,
      (
        CodigoSecuenciaData,
        BaseReferences<
          _$AppDatabase,
          $CodigoSecuenciaTable,
          CodigoSecuenciaData
        >,
      ),
      CodigoSecuenciaData,
      PrefetchHooks Function()
    >;
typedef $$TipoSucursalTableCreateCompanionBuilder =
    TipoSucursalCompanion Function({
      required String id,
      required String codigo,
      required String nombre,
      Value<String?> descripcion,
      Value<bool> activo,
      Value<int?> orden,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$TipoSucursalTableUpdateCompanionBuilder =
    TipoSucursalCompanion Function({
      Value<String> id,
      Value<String> codigo,
      Value<String> nombre,
      Value<String?> descripcion,
      Value<bool> activo,
      Value<int?> orden,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$TipoSucursalTableReferences
    extends
        BaseReferences<_$AppDatabase, $TipoSucursalTable, TipoSucursalData> {
  $$TipoSucursalTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$SucursalTable, List<SucursalData>>
  _sucursalRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.sucursal,
    aliasName: $_aliasNameGenerator(
      db.tipoSucursal.id,
      db.sucursal.tipoSucursalId,
    ),
  );

  $$SucursalTableProcessedTableManager get sucursalRefs {
    final manager = $$SucursalTableTableManager(
      $_db,
      $_db.sucursal,
    ).filter((f) => f.tipoSucursalId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_sucursalRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$TipoSucursalTableFilterComposer
    extends Composer<_$AppDatabase, $TipoSucursalTable> {
  $$TipoSucursalTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get codigo => $composableBuilder(
    column: $table.codigo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nombre => $composableBuilder(
    column: $table.nombre,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get descripcion => $composableBuilder(
    column: $table.descripcion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get activo => $composableBuilder(
    column: $table.activo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get orden => $composableBuilder(
    column: $table.orden,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> sucursalRefs(
    Expression<bool> Function($$SucursalTableFilterComposer f) f,
  ) {
    final $$SucursalTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.sucursal,
      getReferencedColumn: (t) => t.tipoSucursalId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SucursalTableFilterComposer(
            $db: $db,
            $table: $db.sucursal,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TipoSucursalTableOrderingComposer
    extends Composer<_$AppDatabase, $TipoSucursalTable> {
  $$TipoSucursalTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get codigo => $composableBuilder(
    column: $table.codigo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nombre => $composableBuilder(
    column: $table.nombre,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get descripcion => $composableBuilder(
    column: $table.descripcion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get activo => $composableBuilder(
    column: $table.activo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get orden => $composableBuilder(
    column: $table.orden,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TipoSucursalTableAnnotationComposer
    extends Composer<_$AppDatabase, $TipoSucursalTable> {
  $$TipoSucursalTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get codigo =>
      $composableBuilder(column: $table.codigo, builder: (column) => column);

  GeneratedColumn<String> get nombre =>
      $composableBuilder(column: $table.nombre, builder: (column) => column);

  GeneratedColumn<String> get descripcion => $composableBuilder(
    column: $table.descripcion,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get activo =>
      $composableBuilder(column: $table.activo, builder: (column) => column);

  GeneratedColumn<int> get orden =>
      $composableBuilder(column: $table.orden, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> sucursalRefs<T extends Object>(
    Expression<T> Function($$SucursalTableAnnotationComposer a) f,
  ) {
    final $$SucursalTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.sucursal,
      getReferencedColumn: (t) => t.tipoSucursalId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SucursalTableAnnotationComposer(
            $db: $db,
            $table: $db.sucursal,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TipoSucursalTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TipoSucursalTable,
          TipoSucursalData,
          $$TipoSucursalTableFilterComposer,
          $$TipoSucursalTableOrderingComposer,
          $$TipoSucursalTableAnnotationComposer,
          $$TipoSucursalTableCreateCompanionBuilder,
          $$TipoSucursalTableUpdateCompanionBuilder,
          (TipoSucursalData, $$TipoSucursalTableReferences),
          TipoSucursalData,
          PrefetchHooks Function({bool sucursalRefs})
        > {
  $$TipoSucursalTableTableManager(_$AppDatabase db, $TipoSucursalTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$TipoSucursalTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$TipoSucursalTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () =>
                  $$TipoSucursalTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> codigo = const Value.absent(),
                Value<String> nombre = const Value.absent(),
                Value<String?> descripcion = const Value.absent(),
                Value<bool> activo = const Value.absent(),
                Value<int?> orden = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TipoSucursalCompanion(
                id: id,
                codigo: codigo,
                nombre: nombre,
                descripcion: descripcion,
                activo: activo,
                orden: orden,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String codigo,
                required String nombre,
                Value<String?> descripcion = const Value.absent(),
                Value<bool> activo = const Value.absent(),
                Value<int?> orden = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TipoSucursalCompanion.insert(
                id: id,
                codigo: codigo,
                nombre: nombre,
                descripcion: descripcion,
                activo: activo,
                orden: orden,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          $$TipoSucursalTableReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: ({sucursalRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (sucursalRefs) db.sucursal],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (sucursalRefs)
                    await $_getPrefetchedData<
                      TipoSucursalData,
                      $TipoSucursalTable,
                      SucursalData
                    >(
                      currentTable: table,
                      referencedTable: $$TipoSucursalTableReferences
                          ._sucursalRefsTable(db),
                      managerFromTypedResult:
                          (p0) =>
                              $$TipoSucursalTableReferences(
                                db,
                                table,
                                p0,
                              ).sucursalRefs,
                      referencedItemsForCurrentItem:
                          (item, referencedItems) => referencedItems.where(
                            (e) => e.tipoSucursalId == item.id,
                          ),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$TipoSucursalTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TipoSucursalTable,
      TipoSucursalData,
      $$TipoSucursalTableFilterComposer,
      $$TipoSucursalTableOrderingComposer,
      $$TipoSucursalTableAnnotationComposer,
      $$TipoSucursalTableCreateCompanionBuilder,
      $$TipoSucursalTableUpdateCompanionBuilder,
      (TipoSucursalData, $$TipoSucursalTableReferences),
      TipoSucursalData,
      PrefetchHooks Function({bool sucursalRefs})
    >;
typedef $$IndustriaTableCreateCompanionBuilder =
    IndustriaCompanion Function({
      required String id,
      required String codigo,
      required String nombre,
      Value<String?> descripcion,
      Value<bool> activo,
      Value<int?> orden,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$IndustriaTableUpdateCompanionBuilder =
    IndustriaCompanion Function({
      Value<String> id,
      Value<String> codigo,
      Value<String> nombre,
      Value<String?> descripcion,
      Value<bool> activo,
      Value<int?> orden,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$IndustriaTableReferences
    extends BaseReferences<_$AppDatabase, $IndustriaTable, IndustriaData> {
  $$IndustriaTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$ClienteTable, List<ClienteData>>
  _clienteRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.cliente,
    aliasName: $_aliasNameGenerator(db.industria.id, db.cliente.industriaId),
  );

  $$ClienteTableProcessedTableManager get clienteRefs {
    final manager = $$ClienteTableTableManager(
      $_db,
      $_db.cliente,
    ).filter((f) => f.industriaId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_clienteRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$IndustriaTableFilterComposer
    extends Composer<_$AppDatabase, $IndustriaTable> {
  $$IndustriaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get codigo => $composableBuilder(
    column: $table.codigo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nombre => $composableBuilder(
    column: $table.nombre,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get descripcion => $composableBuilder(
    column: $table.descripcion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get activo => $composableBuilder(
    column: $table.activo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get orden => $composableBuilder(
    column: $table.orden,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> clienteRefs(
    Expression<bool> Function($$ClienteTableFilterComposer f) f,
  ) {
    final $$ClienteTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.cliente,
      getReferencedColumn: (t) => t.industriaId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ClienteTableFilterComposer(
            $db: $db,
            $table: $db.cliente,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$IndustriaTableOrderingComposer
    extends Composer<_$AppDatabase, $IndustriaTable> {
  $$IndustriaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get codigo => $composableBuilder(
    column: $table.codigo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nombre => $composableBuilder(
    column: $table.nombre,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get descripcion => $composableBuilder(
    column: $table.descripcion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get activo => $composableBuilder(
    column: $table.activo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get orden => $composableBuilder(
    column: $table.orden,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$IndustriaTableAnnotationComposer
    extends Composer<_$AppDatabase, $IndustriaTable> {
  $$IndustriaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get codigo =>
      $composableBuilder(column: $table.codigo, builder: (column) => column);

  GeneratedColumn<String> get nombre =>
      $composableBuilder(column: $table.nombre, builder: (column) => column);

  GeneratedColumn<String> get descripcion => $composableBuilder(
    column: $table.descripcion,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get activo =>
      $composableBuilder(column: $table.activo, builder: (column) => column);

  GeneratedColumn<int> get orden =>
      $composableBuilder(column: $table.orden, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> clienteRefs<T extends Object>(
    Expression<T> Function($$ClienteTableAnnotationComposer a) f,
  ) {
    final $$ClienteTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.cliente,
      getReferencedColumn: (t) => t.industriaId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ClienteTableAnnotationComposer(
            $db: $db,
            $table: $db.cliente,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$IndustriaTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $IndustriaTable,
          IndustriaData,
          $$IndustriaTableFilterComposer,
          $$IndustriaTableOrderingComposer,
          $$IndustriaTableAnnotationComposer,
          $$IndustriaTableCreateCompanionBuilder,
          $$IndustriaTableUpdateCompanionBuilder,
          (IndustriaData, $$IndustriaTableReferences),
          IndustriaData,
          PrefetchHooks Function({bool clienteRefs})
        > {
  $$IndustriaTableTableManager(_$AppDatabase db, $IndustriaTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$IndustriaTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$IndustriaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$IndustriaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> codigo = const Value.absent(),
                Value<String> nombre = const Value.absent(),
                Value<String?> descripcion = const Value.absent(),
                Value<bool> activo = const Value.absent(),
                Value<int?> orden = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => IndustriaCompanion(
                id: id,
                codigo: codigo,
                nombre: nombre,
                descripcion: descripcion,
                activo: activo,
                orden: orden,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String codigo,
                required String nombre,
                Value<String?> descripcion = const Value.absent(),
                Value<bool> activo = const Value.absent(),
                Value<int?> orden = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => IndustriaCompanion.insert(
                id: id,
                codigo: codigo,
                nombre: nombre,
                descripcion: descripcion,
                activo: activo,
                orden: orden,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          $$IndustriaTableReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: ({clienteRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (clienteRefs) db.cliente],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (clienteRefs)
                    await $_getPrefetchedData<
                      IndustriaData,
                      $IndustriaTable,
                      ClienteData
                    >(
                      currentTable: table,
                      referencedTable: $$IndustriaTableReferences
                          ._clienteRefsTable(db),
                      managerFromTypedResult:
                          (p0) =>
                              $$IndustriaTableReferences(
                                db,
                                table,
                                p0,
                              ).clienteRefs,
                      referencedItemsForCurrentItem:
                          (item, referencedItems) => referencedItems.where(
                            (e) => e.industriaId == item.id,
                          ),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$IndustriaTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $IndustriaTable,
      IndustriaData,
      $$IndustriaTableFilterComposer,
      $$IndustriaTableOrderingComposer,
      $$IndustriaTableAnnotationComposer,
      $$IndustriaTableCreateCompanionBuilder,
      $$IndustriaTableUpdateCompanionBuilder,
      (IndustriaData, $$IndustriaTableReferences),
      IndustriaData,
      PrefetchHooks Function({bool clienteRefs})
    >;
typedef $$TipoServicioTableCreateCompanionBuilder =
    TipoServicioCompanion Function({
      required String id,
      required String codigo,
      required String nombre,
      Value<String?> descripcion,
      Value<bool> activo,
      Value<int?> orden,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$TipoServicioTableUpdateCompanionBuilder =
    TipoServicioCompanion Function({
      Value<String> id,
      Value<String> codigo,
      Value<String> nombre,
      Value<String?> descripcion,
      Value<bool> activo,
      Value<int?> orden,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$TipoServicioTableReferences
    extends
        BaseReferences<_$AppDatabase, $TipoServicioTable, TipoServicioData> {
  $$TipoServicioTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$ServicioTable, List<ServicioData>>
  _servicioRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.servicio,
    aliasName: $_aliasNameGenerator(
      db.tipoServicio.id,
      db.servicio.tipoServicioId,
    ),
  );

  $$ServicioTableProcessedTableManager get servicioRefs {
    final manager = $$ServicioTableTableManager(
      $_db,
      $_db.servicio,
    ).filter((f) => f.tipoServicioId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_servicioRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$TipoServicioTableFilterComposer
    extends Composer<_$AppDatabase, $TipoServicioTable> {
  $$TipoServicioTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get codigo => $composableBuilder(
    column: $table.codigo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nombre => $composableBuilder(
    column: $table.nombre,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get descripcion => $composableBuilder(
    column: $table.descripcion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get activo => $composableBuilder(
    column: $table.activo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get orden => $composableBuilder(
    column: $table.orden,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> servicioRefs(
    Expression<bool> Function($$ServicioTableFilterComposer f) f,
  ) {
    final $$ServicioTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.servicio,
      getReferencedColumn: (t) => t.tipoServicioId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ServicioTableFilterComposer(
            $db: $db,
            $table: $db.servicio,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TipoServicioTableOrderingComposer
    extends Composer<_$AppDatabase, $TipoServicioTable> {
  $$TipoServicioTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get codigo => $composableBuilder(
    column: $table.codigo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nombre => $composableBuilder(
    column: $table.nombre,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get descripcion => $composableBuilder(
    column: $table.descripcion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get activo => $composableBuilder(
    column: $table.activo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get orden => $composableBuilder(
    column: $table.orden,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TipoServicioTableAnnotationComposer
    extends Composer<_$AppDatabase, $TipoServicioTable> {
  $$TipoServicioTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get codigo =>
      $composableBuilder(column: $table.codigo, builder: (column) => column);

  GeneratedColumn<String> get nombre =>
      $composableBuilder(column: $table.nombre, builder: (column) => column);

  GeneratedColumn<String> get descripcion => $composableBuilder(
    column: $table.descripcion,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get activo =>
      $composableBuilder(column: $table.activo, builder: (column) => column);

  GeneratedColumn<int> get orden =>
      $composableBuilder(column: $table.orden, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> servicioRefs<T extends Object>(
    Expression<T> Function($$ServicioTableAnnotationComposer a) f,
  ) {
    final $$ServicioTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.servicio,
      getReferencedColumn: (t) => t.tipoServicioId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ServicioTableAnnotationComposer(
            $db: $db,
            $table: $db.servicio,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TipoServicioTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TipoServicioTable,
          TipoServicioData,
          $$TipoServicioTableFilterComposer,
          $$TipoServicioTableOrderingComposer,
          $$TipoServicioTableAnnotationComposer,
          $$TipoServicioTableCreateCompanionBuilder,
          $$TipoServicioTableUpdateCompanionBuilder,
          (TipoServicioData, $$TipoServicioTableReferences),
          TipoServicioData,
          PrefetchHooks Function({bool servicioRefs})
        > {
  $$TipoServicioTableTableManager(_$AppDatabase db, $TipoServicioTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$TipoServicioTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$TipoServicioTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () =>
                  $$TipoServicioTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> codigo = const Value.absent(),
                Value<String> nombre = const Value.absent(),
                Value<String?> descripcion = const Value.absent(),
                Value<bool> activo = const Value.absent(),
                Value<int?> orden = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TipoServicioCompanion(
                id: id,
                codigo: codigo,
                nombre: nombre,
                descripcion: descripcion,
                activo: activo,
                orden: orden,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String codigo,
                required String nombre,
                Value<String?> descripcion = const Value.absent(),
                Value<bool> activo = const Value.absent(),
                Value<int?> orden = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TipoServicioCompanion.insert(
                id: id,
                codigo: codigo,
                nombre: nombre,
                descripcion: descripcion,
                activo: activo,
                orden: orden,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          $$TipoServicioTableReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: ({servicioRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (servicioRefs) db.servicio],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (servicioRefs)
                    await $_getPrefetchedData<
                      TipoServicioData,
                      $TipoServicioTable,
                      ServicioData
                    >(
                      currentTable: table,
                      referencedTable: $$TipoServicioTableReferences
                          ._servicioRefsTable(db),
                      managerFromTypedResult:
                          (p0) =>
                              $$TipoServicioTableReferences(
                                db,
                                table,
                                p0,
                              ).servicioRefs,
                      referencedItemsForCurrentItem:
                          (item, referencedItems) => referencedItems.where(
                            (e) => e.tipoServicioId == item.id,
                          ),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$TipoServicioTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TipoServicioTable,
      TipoServicioData,
      $$TipoServicioTableFilterComposer,
      $$TipoServicioTableOrderingComposer,
      $$TipoServicioTableAnnotationComposer,
      $$TipoServicioTableCreateCompanionBuilder,
      $$TipoServicioTableUpdateCompanionBuilder,
      (TipoServicioData, $$TipoServicioTableReferences),
      TipoServicioData,
      PrefetchHooks Function({bool servicioRefs})
    >;
typedef $$AreaTableCreateCompanionBuilder =
    AreaCompanion Function({
      required String id,
      required String codigo,
      required String nombre,
      Value<String?> descripcion,
      Value<bool> activo,
      Value<int?> orden,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$AreaTableUpdateCompanionBuilder =
    AreaCompanion Function({
      Value<String> id,
      Value<String> codigo,
      Value<String> nombre,
      Value<String?> descripcion,
      Value<bool> activo,
      Value<int?> orden,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$AreaTableReferences
    extends BaseReferences<_$AppDatabase, $AreaTable, AreaData> {
  $$AreaTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$PuestoTable, List<PuestoData>> _puestoRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.puesto,
    aliasName: $_aliasNameGenerator(db.area.id, db.puesto.areaId),
  );

  $$PuestoTableProcessedTableManager get puestoRefs {
    final manager = $$PuestoTableTableManager(
      $_db,
      $_db.puesto,
    ).filter((f) => f.areaId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_puestoRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$AreaTableFilterComposer extends Composer<_$AppDatabase, $AreaTable> {
  $$AreaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get codigo => $composableBuilder(
    column: $table.codigo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nombre => $composableBuilder(
    column: $table.nombre,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get descripcion => $composableBuilder(
    column: $table.descripcion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get activo => $composableBuilder(
    column: $table.activo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get orden => $composableBuilder(
    column: $table.orden,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> puestoRefs(
    Expression<bool> Function($$PuestoTableFilterComposer f) f,
  ) {
    final $$PuestoTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.puesto,
      getReferencedColumn: (t) => t.areaId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PuestoTableFilterComposer(
            $db: $db,
            $table: $db.puesto,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$AreaTableOrderingComposer extends Composer<_$AppDatabase, $AreaTable> {
  $$AreaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get codigo => $composableBuilder(
    column: $table.codigo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nombre => $composableBuilder(
    column: $table.nombre,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get descripcion => $composableBuilder(
    column: $table.descripcion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get activo => $composableBuilder(
    column: $table.activo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get orden => $composableBuilder(
    column: $table.orden,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AreaTableAnnotationComposer
    extends Composer<_$AppDatabase, $AreaTable> {
  $$AreaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get codigo =>
      $composableBuilder(column: $table.codigo, builder: (column) => column);

  GeneratedColumn<String> get nombre =>
      $composableBuilder(column: $table.nombre, builder: (column) => column);

  GeneratedColumn<String> get descripcion => $composableBuilder(
    column: $table.descripcion,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get activo =>
      $composableBuilder(column: $table.activo, builder: (column) => column);

  GeneratedColumn<int> get orden =>
      $composableBuilder(column: $table.orden, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> puestoRefs<T extends Object>(
    Expression<T> Function($$PuestoTableAnnotationComposer a) f,
  ) {
    final $$PuestoTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.puesto,
      getReferencedColumn: (t) => t.areaId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PuestoTableAnnotationComposer(
            $db: $db,
            $table: $db.puesto,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$AreaTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AreaTable,
          AreaData,
          $$AreaTableFilterComposer,
          $$AreaTableOrderingComposer,
          $$AreaTableAnnotationComposer,
          $$AreaTableCreateCompanionBuilder,
          $$AreaTableUpdateCompanionBuilder,
          (AreaData, $$AreaTableReferences),
          AreaData,
          PrefetchHooks Function({bool puestoRefs})
        > {
  $$AreaTableTableManager(_$AppDatabase db, $AreaTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$AreaTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$AreaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$AreaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> codigo = const Value.absent(),
                Value<String> nombre = const Value.absent(),
                Value<String?> descripcion = const Value.absent(),
                Value<bool> activo = const Value.absent(),
                Value<int?> orden = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AreaCompanion(
                id: id,
                codigo: codigo,
                nombre: nombre,
                descripcion: descripcion,
                activo: activo,
                orden: orden,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String codigo,
                required String nombre,
                Value<String?> descripcion = const Value.absent(),
                Value<bool> activo = const Value.absent(),
                Value<int?> orden = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AreaCompanion.insert(
                id: id,
                codigo: codigo,
                nombre: nombre,
                descripcion: descripcion,
                activo: activo,
                orden: orden,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          $$AreaTableReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: ({puestoRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (puestoRefs) db.puesto],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (puestoRefs)
                    await $_getPrefetchedData<AreaData, $AreaTable, PuestoData>(
                      currentTable: table,
                      referencedTable: $$AreaTableReferences._puestoRefsTable(
                        db,
                      ),
                      managerFromTypedResult:
                          (p0) =>
                              $$AreaTableReferences(db, table, p0).puestoRefs,
                      referencedItemsForCurrentItem:
                          (item, referencedItems) =>
                              referencedItems.where((e) => e.areaId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$AreaTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AreaTable,
      AreaData,
      $$AreaTableFilterComposer,
      $$AreaTableOrderingComposer,
      $$AreaTableAnnotationComposer,
      $$AreaTableCreateCompanionBuilder,
      $$AreaTableUpdateCompanionBuilder,
      (AreaData, $$AreaTableReferences),
      AreaData,
      PrefetchHooks Function({bool puestoRefs})
    >;
typedef $$DireccionTableCreateCompanionBuilder =
    DireccionCompanion Function({
      Value<String> id,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<String> cicloVidaRegistro,
      Value<String?> empresaId,
      Value<String?> sucursalId,
      Value<String?> clienteId,
      Value<String?> servicioId,
      required String tipoDireccion,
      Value<bool> esPrincipal,
      required String calle,
      required String numeroExterior,
      Value<String?> numeroInterior,
      required String colonia,
      required String municipioAlcaldia,
      Value<String?> ciudadLocalidad,
      required String estado,
      required String codigoPostal,
      Value<String> pais,
      Value<String?> referencias,
      Value<int> rowid,
    });
typedef $$DireccionTableUpdateCompanionBuilder =
    DireccionCompanion Function({
      Value<String> id,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<String> cicloVidaRegistro,
      Value<String?> empresaId,
      Value<String?> sucursalId,
      Value<String?> clienteId,
      Value<String?> servicioId,
      Value<String> tipoDireccion,
      Value<bool> esPrincipal,
      Value<String> calle,
      Value<String> numeroExterior,
      Value<String?> numeroInterior,
      Value<String> colonia,
      Value<String> municipioAlcaldia,
      Value<String?> ciudadLocalidad,
      Value<String> estado,
      Value<String> codigoPostal,
      Value<String> pais,
      Value<String?> referencias,
      Value<int> rowid,
    });

class $$DireccionTableFilterComposer
    extends Composer<_$AppDatabase, $DireccionTable> {
  $$DireccionTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cicloVidaRegistro => $composableBuilder(
    column: $table.cicloVidaRegistro,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get empresaId => $composableBuilder(
    column: $table.empresaId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sucursalId => $composableBuilder(
    column: $table.sucursalId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get clienteId => $composableBuilder(
    column: $table.clienteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get servicioId => $composableBuilder(
    column: $table.servicioId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tipoDireccion => $composableBuilder(
    column: $table.tipoDireccion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get esPrincipal => $composableBuilder(
    column: $table.esPrincipal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get calle => $composableBuilder(
    column: $table.calle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get numeroExterior => $composableBuilder(
    column: $table.numeroExterior,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get numeroInterior => $composableBuilder(
    column: $table.numeroInterior,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get colonia => $composableBuilder(
    column: $table.colonia,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get municipioAlcaldia => $composableBuilder(
    column: $table.municipioAlcaldia,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ciudadLocalidad => $composableBuilder(
    column: $table.ciudadLocalidad,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get estado => $composableBuilder(
    column: $table.estado,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get codigoPostal => $composableBuilder(
    column: $table.codigoPostal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pais => $composableBuilder(
    column: $table.pais,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get referencias => $composableBuilder(
    column: $table.referencias,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DireccionTableOrderingComposer
    extends Composer<_$AppDatabase, $DireccionTable> {
  $$DireccionTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cicloVidaRegistro => $composableBuilder(
    column: $table.cicloVidaRegistro,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get empresaId => $composableBuilder(
    column: $table.empresaId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sucursalId => $composableBuilder(
    column: $table.sucursalId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get clienteId => $composableBuilder(
    column: $table.clienteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get servicioId => $composableBuilder(
    column: $table.servicioId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tipoDireccion => $composableBuilder(
    column: $table.tipoDireccion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get esPrincipal => $composableBuilder(
    column: $table.esPrincipal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get calle => $composableBuilder(
    column: $table.calle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get numeroExterior => $composableBuilder(
    column: $table.numeroExterior,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get numeroInterior => $composableBuilder(
    column: $table.numeroInterior,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get colonia => $composableBuilder(
    column: $table.colonia,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get municipioAlcaldia => $composableBuilder(
    column: $table.municipioAlcaldia,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ciudadLocalidad => $composableBuilder(
    column: $table.ciudadLocalidad,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get estado => $composableBuilder(
    column: $table.estado,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get codigoPostal => $composableBuilder(
    column: $table.codigoPostal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pais => $composableBuilder(
    column: $table.pais,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get referencias => $composableBuilder(
    column: $table.referencias,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DireccionTableAnnotationComposer
    extends Composer<_$AppDatabase, $DireccionTable> {
  $$DireccionTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get cicloVidaRegistro => $composableBuilder(
    column: $table.cicloVidaRegistro,
    builder: (column) => column,
  );

  GeneratedColumn<String> get empresaId =>
      $composableBuilder(column: $table.empresaId, builder: (column) => column);

  GeneratedColumn<String> get sucursalId => $composableBuilder(
    column: $table.sucursalId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get clienteId =>
      $composableBuilder(column: $table.clienteId, builder: (column) => column);

  GeneratedColumn<String> get servicioId => $composableBuilder(
    column: $table.servicioId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get tipoDireccion => $composableBuilder(
    column: $table.tipoDireccion,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get esPrincipal => $composableBuilder(
    column: $table.esPrincipal,
    builder: (column) => column,
  );

  GeneratedColumn<String> get calle =>
      $composableBuilder(column: $table.calle, builder: (column) => column);

  GeneratedColumn<String> get numeroExterior => $composableBuilder(
    column: $table.numeroExterior,
    builder: (column) => column,
  );

  GeneratedColumn<String> get numeroInterior => $composableBuilder(
    column: $table.numeroInterior,
    builder: (column) => column,
  );

  GeneratedColumn<String> get colonia =>
      $composableBuilder(column: $table.colonia, builder: (column) => column);

  GeneratedColumn<String> get municipioAlcaldia => $composableBuilder(
    column: $table.municipioAlcaldia,
    builder: (column) => column,
  );

  GeneratedColumn<String> get ciudadLocalidad => $composableBuilder(
    column: $table.ciudadLocalidad,
    builder: (column) => column,
  );

  GeneratedColumn<String> get estado =>
      $composableBuilder(column: $table.estado, builder: (column) => column);

  GeneratedColumn<String> get codigoPostal => $composableBuilder(
    column: $table.codigoPostal,
    builder: (column) => column,
  );

  GeneratedColumn<String> get pais =>
      $composableBuilder(column: $table.pais, builder: (column) => column);

  GeneratedColumn<String> get referencias => $composableBuilder(
    column: $table.referencias,
    builder: (column) => column,
  );
}

class $$DireccionTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DireccionTable,
          DireccionData,
          $$DireccionTableFilterComposer,
          $$DireccionTableOrderingComposer,
          $$DireccionTableAnnotationComposer,
          $$DireccionTableCreateCompanionBuilder,
          $$DireccionTableUpdateCompanionBuilder,
          (
            DireccionData,
            BaseReferences<_$AppDatabase, $DireccionTable, DireccionData>,
          ),
          DireccionData,
          PrefetchHooks Function()
        > {
  $$DireccionTableTableManager(_$AppDatabase db, $DireccionTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$DireccionTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$DireccionTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$DireccionTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> cicloVidaRegistro = const Value.absent(),
                Value<String?> empresaId = const Value.absent(),
                Value<String?> sucursalId = const Value.absent(),
                Value<String?> clienteId = const Value.absent(),
                Value<String?> servicioId = const Value.absent(),
                Value<String> tipoDireccion = const Value.absent(),
                Value<bool> esPrincipal = const Value.absent(),
                Value<String> calle = const Value.absent(),
                Value<String> numeroExterior = const Value.absent(),
                Value<String?> numeroInterior = const Value.absent(),
                Value<String> colonia = const Value.absent(),
                Value<String> municipioAlcaldia = const Value.absent(),
                Value<String?> ciudadLocalidad = const Value.absent(),
                Value<String> estado = const Value.absent(),
                Value<String> codigoPostal = const Value.absent(),
                Value<String> pais = const Value.absent(),
                Value<String?> referencias = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DireccionCompanion(
                id: id,
                createdAt: createdAt,
                updatedAt: updatedAt,
                cicloVidaRegistro: cicloVidaRegistro,
                empresaId: empresaId,
                sucursalId: sucursalId,
                clienteId: clienteId,
                servicioId: servicioId,
                tipoDireccion: tipoDireccion,
                esPrincipal: esPrincipal,
                calle: calle,
                numeroExterior: numeroExterior,
                numeroInterior: numeroInterior,
                colonia: colonia,
                municipioAlcaldia: municipioAlcaldia,
                ciudadLocalidad: ciudadLocalidad,
                estado: estado,
                codigoPostal: codigoPostal,
                pais: pais,
                referencias: referencias,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> cicloVidaRegistro = const Value.absent(),
                Value<String?> empresaId = const Value.absent(),
                Value<String?> sucursalId = const Value.absent(),
                Value<String?> clienteId = const Value.absent(),
                Value<String?> servicioId = const Value.absent(),
                required String tipoDireccion,
                Value<bool> esPrincipal = const Value.absent(),
                required String calle,
                required String numeroExterior,
                Value<String?> numeroInterior = const Value.absent(),
                required String colonia,
                required String municipioAlcaldia,
                Value<String?> ciudadLocalidad = const Value.absent(),
                required String estado,
                required String codigoPostal,
                Value<String> pais = const Value.absent(),
                Value<String?> referencias = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DireccionCompanion.insert(
                id: id,
                createdAt: createdAt,
                updatedAt: updatedAt,
                cicloVidaRegistro: cicloVidaRegistro,
                empresaId: empresaId,
                sucursalId: sucursalId,
                clienteId: clienteId,
                servicioId: servicioId,
                tipoDireccion: tipoDireccion,
                esPrincipal: esPrincipal,
                calle: calle,
                numeroExterior: numeroExterior,
                numeroInterior: numeroInterior,
                colonia: colonia,
                municipioAlcaldia: municipioAlcaldia,
                ciudadLocalidad: ciudadLocalidad,
                estado: estado,
                codigoPostal: codigoPostal,
                pais: pais,
                referencias: referencias,
                rowid: rowid,
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

typedef $$DireccionTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DireccionTable,
      DireccionData,
      $$DireccionTableFilterComposer,
      $$DireccionTableOrderingComposer,
      $$DireccionTableAnnotationComposer,
      $$DireccionTableCreateCompanionBuilder,
      $$DireccionTableUpdateCompanionBuilder,
      (
        DireccionData,
        BaseReferences<_$AppDatabase, $DireccionTable, DireccionData>,
      ),
      DireccionData,
      PrefetchHooks Function()
    >;
typedef $$MedioContactoTableCreateCompanionBuilder =
    MedioContactoCompanion Function({
      Value<String> id,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<String> cicloVidaRegistro,
      Value<String?> empresaId,
      Value<String?> sucursalId,
      Value<String?> telefono,
      Value<String?> correo,
      Value<String?> sitioWeb,
      Value<String?> etiqueta,
      Value<int> rowid,
    });
typedef $$MedioContactoTableUpdateCompanionBuilder =
    MedioContactoCompanion Function({
      Value<String> id,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<String> cicloVidaRegistro,
      Value<String?> empresaId,
      Value<String?> sucursalId,
      Value<String?> telefono,
      Value<String?> correo,
      Value<String?> sitioWeb,
      Value<String?> etiqueta,
      Value<int> rowid,
    });

class $$MedioContactoTableFilterComposer
    extends Composer<_$AppDatabase, $MedioContactoTable> {
  $$MedioContactoTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cicloVidaRegistro => $composableBuilder(
    column: $table.cicloVidaRegistro,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get empresaId => $composableBuilder(
    column: $table.empresaId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sucursalId => $composableBuilder(
    column: $table.sucursalId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get telefono => $composableBuilder(
    column: $table.telefono,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get correo => $composableBuilder(
    column: $table.correo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sitioWeb => $composableBuilder(
    column: $table.sitioWeb,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get etiqueta => $composableBuilder(
    column: $table.etiqueta,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MedioContactoTableOrderingComposer
    extends Composer<_$AppDatabase, $MedioContactoTable> {
  $$MedioContactoTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cicloVidaRegistro => $composableBuilder(
    column: $table.cicloVidaRegistro,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get empresaId => $composableBuilder(
    column: $table.empresaId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sucursalId => $composableBuilder(
    column: $table.sucursalId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get telefono => $composableBuilder(
    column: $table.telefono,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get correo => $composableBuilder(
    column: $table.correo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sitioWeb => $composableBuilder(
    column: $table.sitioWeb,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get etiqueta => $composableBuilder(
    column: $table.etiqueta,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MedioContactoTableAnnotationComposer
    extends Composer<_$AppDatabase, $MedioContactoTable> {
  $$MedioContactoTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get cicloVidaRegistro => $composableBuilder(
    column: $table.cicloVidaRegistro,
    builder: (column) => column,
  );

  GeneratedColumn<String> get empresaId =>
      $composableBuilder(column: $table.empresaId, builder: (column) => column);

  GeneratedColumn<String> get sucursalId => $composableBuilder(
    column: $table.sucursalId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get telefono =>
      $composableBuilder(column: $table.telefono, builder: (column) => column);

  GeneratedColumn<String> get correo =>
      $composableBuilder(column: $table.correo, builder: (column) => column);

  GeneratedColumn<String> get sitioWeb =>
      $composableBuilder(column: $table.sitioWeb, builder: (column) => column);

  GeneratedColumn<String> get etiqueta =>
      $composableBuilder(column: $table.etiqueta, builder: (column) => column);
}

class $$MedioContactoTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MedioContactoTable,
          MedioContactoData,
          $$MedioContactoTableFilterComposer,
          $$MedioContactoTableOrderingComposer,
          $$MedioContactoTableAnnotationComposer,
          $$MedioContactoTableCreateCompanionBuilder,
          $$MedioContactoTableUpdateCompanionBuilder,
          (
            MedioContactoData,
            BaseReferences<
              _$AppDatabase,
              $MedioContactoTable,
              MedioContactoData
            >,
          ),
          MedioContactoData,
          PrefetchHooks Function()
        > {
  $$MedioContactoTableTableManager(_$AppDatabase db, $MedioContactoTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$MedioContactoTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () =>
                  $$MedioContactoTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$MedioContactoTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> cicloVidaRegistro = const Value.absent(),
                Value<String?> empresaId = const Value.absent(),
                Value<String?> sucursalId = const Value.absent(),
                Value<String?> telefono = const Value.absent(),
                Value<String?> correo = const Value.absent(),
                Value<String?> sitioWeb = const Value.absent(),
                Value<String?> etiqueta = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MedioContactoCompanion(
                id: id,
                createdAt: createdAt,
                updatedAt: updatedAt,
                cicloVidaRegistro: cicloVidaRegistro,
                empresaId: empresaId,
                sucursalId: sucursalId,
                telefono: telefono,
                correo: correo,
                sitioWeb: sitioWeb,
                etiqueta: etiqueta,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> cicloVidaRegistro = const Value.absent(),
                Value<String?> empresaId = const Value.absent(),
                Value<String?> sucursalId = const Value.absent(),
                Value<String?> telefono = const Value.absent(),
                Value<String?> correo = const Value.absent(),
                Value<String?> sitioWeb = const Value.absent(),
                Value<String?> etiqueta = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MedioContactoCompanion.insert(
                id: id,
                createdAt: createdAt,
                updatedAt: updatedAt,
                cicloVidaRegistro: cicloVidaRegistro,
                empresaId: empresaId,
                sucursalId: sucursalId,
                telefono: telefono,
                correo: correo,
                sitioWeb: sitioWeb,
                etiqueta: etiqueta,
                rowid: rowid,
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

typedef $$MedioContactoTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MedioContactoTable,
      MedioContactoData,
      $$MedioContactoTableFilterComposer,
      $$MedioContactoTableOrderingComposer,
      $$MedioContactoTableAnnotationComposer,
      $$MedioContactoTableCreateCompanionBuilder,
      $$MedioContactoTableUpdateCompanionBuilder,
      (
        MedioContactoData,
        BaseReferences<_$AppDatabase, $MedioContactoTable, MedioContactoData>,
      ),
      MedioContactoData,
      PrefetchHooks Function()
    >;
typedef $$AttachmentTableCreateCompanionBuilder =
    AttachmentCompanion Function({
      required String id,
      Value<String?> empresaId,
      Value<String?> clienteId,
      required String originalFileName,
      required String storedFileName,
      required String path,
      required String mimeType,
      required int sizeBytes,
      Value<String?> hash,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });
typedef $$AttachmentTableUpdateCompanionBuilder =
    AttachmentCompanion Function({
      Value<String> id,
      Value<String?> empresaId,
      Value<String?> clienteId,
      Value<String> originalFileName,
      Value<String> storedFileName,
      Value<String> path,
      Value<String> mimeType,
      Value<int> sizeBytes,
      Value<String?> hash,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$AttachmentTableReferences
    extends BaseReferences<_$AppDatabase, $AttachmentTable, AttachmentData> {
  $$AttachmentTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$EmpresaTable, List<EmpresaData>>
  _empresaRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.empresa,
    aliasName: $_aliasNameGenerator(
      db.attachment.id,
      db.empresa.logoAttachmentId,
    ),
  );

  $$EmpresaTableProcessedTableManager get empresaRefs {
    final manager = $$EmpresaTableTableManager($_db, $_db.empresa).filter(
      (f) => f.logoAttachmentId.id.sqlEquals($_itemColumn<String>('id')!),
    );

    final cache = $_typedResult.readTableOrNull(_empresaRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$AttachmentTableFilterComposer
    extends Composer<_$AppDatabase, $AttachmentTable> {
  $$AttachmentTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get empresaId => $composableBuilder(
    column: $table.empresaId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get clienteId => $composableBuilder(
    column: $table.clienteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get originalFileName => $composableBuilder(
    column: $table.originalFileName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get storedFileName => $composableBuilder(
    column: $table.storedFileName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hash => $composableBuilder(
    column: $table.hash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> empresaRefs(
    Expression<bool> Function($$EmpresaTableFilterComposer f) f,
  ) {
    final $$EmpresaTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.empresa,
      getReferencedColumn: (t) => t.logoAttachmentId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EmpresaTableFilterComposer(
            $db: $db,
            $table: $db.empresa,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$AttachmentTableOrderingComposer
    extends Composer<_$AppDatabase, $AttachmentTable> {
  $$AttachmentTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get empresaId => $composableBuilder(
    column: $table.empresaId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get clienteId => $composableBuilder(
    column: $table.clienteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get originalFileName => $composableBuilder(
    column: $table.originalFileName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get storedFileName => $composableBuilder(
    column: $table.storedFileName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hash => $composableBuilder(
    column: $table.hash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AttachmentTableAnnotationComposer
    extends Composer<_$AppDatabase, $AttachmentTable> {
  $$AttachmentTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get empresaId =>
      $composableBuilder(column: $table.empresaId, builder: (column) => column);

  GeneratedColumn<String> get clienteId =>
      $composableBuilder(column: $table.clienteId, builder: (column) => column);

  GeneratedColumn<String> get originalFileName => $composableBuilder(
    column: $table.originalFileName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get storedFileName => $composableBuilder(
    column: $table.storedFileName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<String> get mimeType =>
      $composableBuilder(column: $table.mimeType, builder: (column) => column);

  GeneratedColumn<int> get sizeBytes =>
      $composableBuilder(column: $table.sizeBytes, builder: (column) => column);

  GeneratedColumn<String> get hash =>
      $composableBuilder(column: $table.hash, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  Expression<T> empresaRefs<T extends Object>(
    Expression<T> Function($$EmpresaTableAnnotationComposer a) f,
  ) {
    final $$EmpresaTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.empresa,
      getReferencedColumn: (t) => t.logoAttachmentId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EmpresaTableAnnotationComposer(
            $db: $db,
            $table: $db.empresa,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$AttachmentTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AttachmentTable,
          AttachmentData,
          $$AttachmentTableFilterComposer,
          $$AttachmentTableOrderingComposer,
          $$AttachmentTableAnnotationComposer,
          $$AttachmentTableCreateCompanionBuilder,
          $$AttachmentTableUpdateCompanionBuilder,
          (AttachmentData, $$AttachmentTableReferences),
          AttachmentData,
          PrefetchHooks Function({bool empresaRefs})
        > {
  $$AttachmentTableTableManager(_$AppDatabase db, $AttachmentTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$AttachmentTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$AttachmentTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$AttachmentTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> empresaId = const Value.absent(),
                Value<String?> clienteId = const Value.absent(),
                Value<String> originalFileName = const Value.absent(),
                Value<String> storedFileName = const Value.absent(),
                Value<String> path = const Value.absent(),
                Value<String> mimeType = const Value.absent(),
                Value<int> sizeBytes = const Value.absent(),
                Value<String?> hash = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AttachmentCompanion(
                id: id,
                empresaId: empresaId,
                clienteId: clienteId,
                originalFileName: originalFileName,
                storedFileName: storedFileName,
                path: path,
                mimeType: mimeType,
                sizeBytes: sizeBytes,
                hash: hash,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String?> empresaId = const Value.absent(),
                Value<String?> clienteId = const Value.absent(),
                required String originalFileName,
                required String storedFileName,
                required String path,
                required String mimeType,
                required int sizeBytes,
                Value<String?> hash = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AttachmentCompanion.insert(
                id: id,
                empresaId: empresaId,
                clienteId: clienteId,
                originalFileName: originalFileName,
                storedFileName: storedFileName,
                path: path,
                mimeType: mimeType,
                sizeBytes: sizeBytes,
                hash: hash,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          $$AttachmentTableReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: ({empresaRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (empresaRefs) db.empresa],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (empresaRefs)
                    await $_getPrefetchedData<
                      AttachmentData,
                      $AttachmentTable,
                      EmpresaData
                    >(
                      currentTable: table,
                      referencedTable: $$AttachmentTableReferences
                          ._empresaRefsTable(db),
                      managerFromTypedResult:
                          (p0) =>
                              $$AttachmentTableReferences(
                                db,
                                table,
                                p0,
                              ).empresaRefs,
                      referencedItemsForCurrentItem:
                          (item, referencedItems) => referencedItems.where(
                            (e) => e.logoAttachmentId == item.id,
                          ),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$AttachmentTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AttachmentTable,
      AttachmentData,
      $$AttachmentTableFilterComposer,
      $$AttachmentTableOrderingComposer,
      $$AttachmentTableAnnotationComposer,
      $$AttachmentTableCreateCompanionBuilder,
      $$AttachmentTableUpdateCompanionBuilder,
      (AttachmentData, $$AttachmentTableReferences),
      AttachmentData,
      PrefetchHooks Function({bool empresaRefs})
    >;
typedef $$HorarioTableCreateCompanionBuilder =
    HorarioCompanion Function({
      Value<String> id,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<String> cicloVidaRegistro,
      Value<String?> sucursalId,
      Value<String?> servicioId,
      Value<int> rowid,
    });
typedef $$HorarioTableUpdateCompanionBuilder =
    HorarioCompanion Function({
      Value<String> id,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<String> cicloVidaRegistro,
      Value<String?> sucursalId,
      Value<String?> servicioId,
      Value<int> rowid,
    });

final class $$HorarioTableReferences
    extends BaseReferences<_$AppDatabase, $HorarioTable, HorarioData> {
  $$HorarioTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$HorarioDetalleTable, List<HorarioDetalleData>>
  _horarioDetalleRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.horarioDetalle,
    aliasName: $_aliasNameGenerator(db.horario.id, db.horarioDetalle.horarioId),
  );

  $$HorarioDetalleTableProcessedTableManager get horarioDetalleRefs {
    final manager = $$HorarioDetalleTableTableManager(
      $_db,
      $_db.horarioDetalle,
    ).filter((f) => f.horarioId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_horarioDetalleRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$HorarioTableFilterComposer
    extends Composer<_$AppDatabase, $HorarioTable> {
  $$HorarioTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cicloVidaRegistro => $composableBuilder(
    column: $table.cicloVidaRegistro,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sucursalId => $composableBuilder(
    column: $table.sucursalId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get servicioId => $composableBuilder(
    column: $table.servicioId,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> horarioDetalleRefs(
    Expression<bool> Function($$HorarioDetalleTableFilterComposer f) f,
  ) {
    final $$HorarioDetalleTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.horarioDetalle,
      getReferencedColumn: (t) => t.horarioId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HorarioDetalleTableFilterComposer(
            $db: $db,
            $table: $db.horarioDetalle,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$HorarioTableOrderingComposer
    extends Composer<_$AppDatabase, $HorarioTable> {
  $$HorarioTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cicloVidaRegistro => $composableBuilder(
    column: $table.cicloVidaRegistro,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sucursalId => $composableBuilder(
    column: $table.sucursalId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get servicioId => $composableBuilder(
    column: $table.servicioId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$HorarioTableAnnotationComposer
    extends Composer<_$AppDatabase, $HorarioTable> {
  $$HorarioTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get cicloVidaRegistro => $composableBuilder(
    column: $table.cicloVidaRegistro,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sucursalId => $composableBuilder(
    column: $table.sucursalId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get servicioId => $composableBuilder(
    column: $table.servicioId,
    builder: (column) => column,
  );

  Expression<T> horarioDetalleRefs<T extends Object>(
    Expression<T> Function($$HorarioDetalleTableAnnotationComposer a) f,
  ) {
    final $$HorarioDetalleTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.horarioDetalle,
      getReferencedColumn: (t) => t.horarioId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HorarioDetalleTableAnnotationComposer(
            $db: $db,
            $table: $db.horarioDetalle,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$HorarioTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $HorarioTable,
          HorarioData,
          $$HorarioTableFilterComposer,
          $$HorarioTableOrderingComposer,
          $$HorarioTableAnnotationComposer,
          $$HorarioTableCreateCompanionBuilder,
          $$HorarioTableUpdateCompanionBuilder,
          (HorarioData, $$HorarioTableReferences),
          HorarioData,
          PrefetchHooks Function({bool horarioDetalleRefs})
        > {
  $$HorarioTableTableManager(_$AppDatabase db, $HorarioTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$HorarioTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$HorarioTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$HorarioTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> cicloVidaRegistro = const Value.absent(),
                Value<String?> sucursalId = const Value.absent(),
                Value<String?> servicioId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => HorarioCompanion(
                id: id,
                createdAt: createdAt,
                updatedAt: updatedAt,
                cicloVidaRegistro: cicloVidaRegistro,
                sucursalId: sucursalId,
                servicioId: servicioId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> cicloVidaRegistro = const Value.absent(),
                Value<String?> sucursalId = const Value.absent(),
                Value<String?> servicioId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => HorarioCompanion.insert(
                id: id,
                createdAt: createdAt,
                updatedAt: updatedAt,
                cicloVidaRegistro: cicloVidaRegistro,
                sucursalId: sucursalId,
                servicioId: servicioId,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          $$HorarioTableReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: ({horarioDetalleRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (horarioDetalleRefs) db.horarioDetalle,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (horarioDetalleRefs)
                    await $_getPrefetchedData<
                      HorarioData,
                      $HorarioTable,
                      HorarioDetalleData
                    >(
                      currentTable: table,
                      referencedTable: $$HorarioTableReferences
                          ._horarioDetalleRefsTable(db),
                      managerFromTypedResult:
                          (p0) =>
                              $$HorarioTableReferences(
                                db,
                                table,
                                p0,
                              ).horarioDetalleRefs,
                      referencedItemsForCurrentItem:
                          (item, referencedItems) => referencedItems.where(
                            (e) => e.horarioId == item.id,
                          ),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$HorarioTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $HorarioTable,
      HorarioData,
      $$HorarioTableFilterComposer,
      $$HorarioTableOrderingComposer,
      $$HorarioTableAnnotationComposer,
      $$HorarioTableCreateCompanionBuilder,
      $$HorarioTableUpdateCompanionBuilder,
      (HorarioData, $$HorarioTableReferences),
      HorarioData,
      PrefetchHooks Function({bool horarioDetalleRefs})
    >;
typedef $$HorarioDetalleTableCreateCompanionBuilder =
    HorarioDetalleCompanion Function({
      Value<int> id,
      required String horarioId,
      required int diaSemana,
      required int horaInicio,
      required int horaFin,
      Value<bool> cruzaMedianoche,
      Value<bool> activo,
    });
typedef $$HorarioDetalleTableUpdateCompanionBuilder =
    HorarioDetalleCompanion Function({
      Value<int> id,
      Value<String> horarioId,
      Value<int> diaSemana,
      Value<int> horaInicio,
      Value<int> horaFin,
      Value<bool> cruzaMedianoche,
      Value<bool> activo,
    });

final class $$HorarioDetalleTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $HorarioDetalleTable,
          HorarioDetalleData
        > {
  $$HorarioDetalleTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $HorarioTable _horarioIdTable(_$AppDatabase db) =>
      db.horario.createAlias(
        $_aliasNameGenerator(db.horarioDetalle.horarioId, db.horario.id),
      );

  $$HorarioTableProcessedTableManager get horarioId {
    final $_column = $_itemColumn<String>('horario_id')!;

    final manager = $$HorarioTableTableManager(
      $_db,
      $_db.horario,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_horarioIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$HorarioDetalleTableFilterComposer
    extends Composer<_$AppDatabase, $HorarioDetalleTable> {
  $$HorarioDetalleTableFilterComposer({
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

  ColumnFilters<int> get diaSemana => $composableBuilder(
    column: $table.diaSemana,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get horaInicio => $composableBuilder(
    column: $table.horaInicio,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get horaFin => $composableBuilder(
    column: $table.horaFin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get cruzaMedianoche => $composableBuilder(
    column: $table.cruzaMedianoche,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get activo => $composableBuilder(
    column: $table.activo,
    builder: (column) => ColumnFilters(column),
  );

  $$HorarioTableFilterComposer get horarioId {
    final $$HorarioTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.horarioId,
      referencedTable: $db.horario,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HorarioTableFilterComposer(
            $db: $db,
            $table: $db.horario,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$HorarioDetalleTableOrderingComposer
    extends Composer<_$AppDatabase, $HorarioDetalleTable> {
  $$HorarioDetalleTableOrderingComposer({
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

  ColumnOrderings<int> get diaSemana => $composableBuilder(
    column: $table.diaSemana,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get horaInicio => $composableBuilder(
    column: $table.horaInicio,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get horaFin => $composableBuilder(
    column: $table.horaFin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get cruzaMedianoche => $composableBuilder(
    column: $table.cruzaMedianoche,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get activo => $composableBuilder(
    column: $table.activo,
    builder: (column) => ColumnOrderings(column),
  );

  $$HorarioTableOrderingComposer get horarioId {
    final $$HorarioTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.horarioId,
      referencedTable: $db.horario,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HorarioTableOrderingComposer(
            $db: $db,
            $table: $db.horario,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$HorarioDetalleTableAnnotationComposer
    extends Composer<_$AppDatabase, $HorarioDetalleTable> {
  $$HorarioDetalleTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get diaSemana =>
      $composableBuilder(column: $table.diaSemana, builder: (column) => column);

  GeneratedColumn<int> get horaInicio => $composableBuilder(
    column: $table.horaInicio,
    builder: (column) => column,
  );

  GeneratedColumn<int> get horaFin =>
      $composableBuilder(column: $table.horaFin, builder: (column) => column);

  GeneratedColumn<bool> get cruzaMedianoche => $composableBuilder(
    column: $table.cruzaMedianoche,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get activo =>
      $composableBuilder(column: $table.activo, builder: (column) => column);

  $$HorarioTableAnnotationComposer get horarioId {
    final $$HorarioTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.horarioId,
      referencedTable: $db.horario,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HorarioTableAnnotationComposer(
            $db: $db,
            $table: $db.horario,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$HorarioDetalleTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $HorarioDetalleTable,
          HorarioDetalleData,
          $$HorarioDetalleTableFilterComposer,
          $$HorarioDetalleTableOrderingComposer,
          $$HorarioDetalleTableAnnotationComposer,
          $$HorarioDetalleTableCreateCompanionBuilder,
          $$HorarioDetalleTableUpdateCompanionBuilder,
          (HorarioDetalleData, $$HorarioDetalleTableReferences),
          HorarioDetalleData,
          PrefetchHooks Function({bool horarioId})
        > {
  $$HorarioDetalleTableTableManager(
    _$AppDatabase db,
    $HorarioDetalleTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$HorarioDetalleTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () =>
                  $$HorarioDetalleTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$HorarioDetalleTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> horarioId = const Value.absent(),
                Value<int> diaSemana = const Value.absent(),
                Value<int> horaInicio = const Value.absent(),
                Value<int> horaFin = const Value.absent(),
                Value<bool> cruzaMedianoche = const Value.absent(),
                Value<bool> activo = const Value.absent(),
              }) => HorarioDetalleCompanion(
                id: id,
                horarioId: horarioId,
                diaSemana: diaSemana,
                horaInicio: horaInicio,
                horaFin: horaFin,
                cruzaMedianoche: cruzaMedianoche,
                activo: activo,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String horarioId,
                required int diaSemana,
                required int horaInicio,
                required int horaFin,
                Value<bool> cruzaMedianoche = const Value.absent(),
                Value<bool> activo = const Value.absent(),
              }) => HorarioDetalleCompanion.insert(
                id: id,
                horarioId: horarioId,
                diaSemana: diaSemana,
                horaInicio: horaInicio,
                horaFin: horaFin,
                cruzaMedianoche: cruzaMedianoche,
                activo: activo,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          $$HorarioDetalleTableReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: ({horarioId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                T extends TableManagerState<
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic
                >
              >(state) {
                if (horarioId) {
                  state =
                      state.withJoin(
                            currentTable: table,
                            currentColumn: table.horarioId,
                            referencedTable: $$HorarioDetalleTableReferences
                                ._horarioIdTable(db),
                            referencedColumn:
                                $$HorarioDetalleTableReferences
                                    ._horarioIdTable(db)
                                    .id,
                          )
                          as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$HorarioDetalleTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $HorarioDetalleTable,
      HorarioDetalleData,
      $$HorarioDetalleTableFilterComposer,
      $$HorarioDetalleTableOrderingComposer,
      $$HorarioDetalleTableAnnotationComposer,
      $$HorarioDetalleTableCreateCompanionBuilder,
      $$HorarioDetalleTableUpdateCompanionBuilder,
      (HorarioDetalleData, $$HorarioDetalleTableReferences),
      HorarioDetalleData,
      PrefetchHooks Function({bool horarioId})
    >;
typedef $$EmpresaTableCreateCompanionBuilder =
    EmpresaCompanion Function({
      Value<String> id,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<String> cicloVidaRegistro,
      required String codigo,
      Value<String?> razonSocial,
      required String nombreComercial,
      Value<String?> rfc,
      Value<String?> representanteLegal,
      Value<String?> eslogan,
      Value<String?> logoAttachmentId,
      Value<int> rowid,
    });
typedef $$EmpresaTableUpdateCompanionBuilder =
    EmpresaCompanion Function({
      Value<String> id,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<String> cicloVidaRegistro,
      Value<String> codigo,
      Value<String?> razonSocial,
      Value<String> nombreComercial,
      Value<String?> rfc,
      Value<String?> representanteLegal,
      Value<String?> eslogan,
      Value<String?> logoAttachmentId,
      Value<int> rowid,
    });

final class $$EmpresaTableReferences
    extends BaseReferences<_$AppDatabase, $EmpresaTable, EmpresaData> {
  $$EmpresaTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $AttachmentTable _logoAttachmentIdTable(_$AppDatabase db) =>
      db.attachment.createAlias(
        $_aliasNameGenerator(db.empresa.logoAttachmentId, db.attachment.id),
      );

  $$AttachmentTableProcessedTableManager? get logoAttachmentId {
    final $_column = $_itemColumn<String>('logo_attachment_id');
    if ($_column == null) return null;
    final manager = $$AttachmentTableTableManager(
      $_db,
      $_db.attachment,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_logoAttachmentIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$EmpresaTableFilterComposer
    extends Composer<_$AppDatabase, $EmpresaTable> {
  $$EmpresaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cicloVidaRegistro => $composableBuilder(
    column: $table.cicloVidaRegistro,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get codigo => $composableBuilder(
    column: $table.codigo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get razonSocial => $composableBuilder(
    column: $table.razonSocial,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nombreComercial => $composableBuilder(
    column: $table.nombreComercial,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rfc => $composableBuilder(
    column: $table.rfc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get representanteLegal => $composableBuilder(
    column: $table.representanteLegal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get eslogan => $composableBuilder(
    column: $table.eslogan,
    builder: (column) => ColumnFilters(column),
  );

  $$AttachmentTableFilterComposer get logoAttachmentId {
    final $$AttachmentTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.logoAttachmentId,
      referencedTable: $db.attachment,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AttachmentTableFilterComposer(
            $db: $db,
            $table: $db.attachment,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EmpresaTableOrderingComposer
    extends Composer<_$AppDatabase, $EmpresaTable> {
  $$EmpresaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cicloVidaRegistro => $composableBuilder(
    column: $table.cicloVidaRegistro,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get codigo => $composableBuilder(
    column: $table.codigo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get razonSocial => $composableBuilder(
    column: $table.razonSocial,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nombreComercial => $composableBuilder(
    column: $table.nombreComercial,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rfc => $composableBuilder(
    column: $table.rfc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get representanteLegal => $composableBuilder(
    column: $table.representanteLegal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get eslogan => $composableBuilder(
    column: $table.eslogan,
    builder: (column) => ColumnOrderings(column),
  );

  $$AttachmentTableOrderingComposer get logoAttachmentId {
    final $$AttachmentTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.logoAttachmentId,
      referencedTable: $db.attachment,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AttachmentTableOrderingComposer(
            $db: $db,
            $table: $db.attachment,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EmpresaTableAnnotationComposer
    extends Composer<_$AppDatabase, $EmpresaTable> {
  $$EmpresaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get cicloVidaRegistro => $composableBuilder(
    column: $table.cicloVidaRegistro,
    builder: (column) => column,
  );

  GeneratedColumn<String> get codigo =>
      $composableBuilder(column: $table.codigo, builder: (column) => column);

  GeneratedColumn<String> get razonSocial => $composableBuilder(
    column: $table.razonSocial,
    builder: (column) => column,
  );

  GeneratedColumn<String> get nombreComercial => $composableBuilder(
    column: $table.nombreComercial,
    builder: (column) => column,
  );

  GeneratedColumn<String> get rfc =>
      $composableBuilder(column: $table.rfc, builder: (column) => column);

  GeneratedColumn<String> get representanteLegal => $composableBuilder(
    column: $table.representanteLegal,
    builder: (column) => column,
  );

  GeneratedColumn<String> get eslogan =>
      $composableBuilder(column: $table.eslogan, builder: (column) => column);

  $$AttachmentTableAnnotationComposer get logoAttachmentId {
    final $$AttachmentTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.logoAttachmentId,
      referencedTable: $db.attachment,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AttachmentTableAnnotationComposer(
            $db: $db,
            $table: $db.attachment,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EmpresaTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $EmpresaTable,
          EmpresaData,
          $$EmpresaTableFilterComposer,
          $$EmpresaTableOrderingComposer,
          $$EmpresaTableAnnotationComposer,
          $$EmpresaTableCreateCompanionBuilder,
          $$EmpresaTableUpdateCompanionBuilder,
          (EmpresaData, $$EmpresaTableReferences),
          EmpresaData,
          PrefetchHooks Function({bool logoAttachmentId})
        > {
  $$EmpresaTableTableManager(_$AppDatabase db, $EmpresaTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$EmpresaTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$EmpresaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$EmpresaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> cicloVidaRegistro = const Value.absent(),
                Value<String> codigo = const Value.absent(),
                Value<String?> razonSocial = const Value.absent(),
                Value<String> nombreComercial = const Value.absent(),
                Value<String?> rfc = const Value.absent(),
                Value<String?> representanteLegal = const Value.absent(),
                Value<String?> eslogan = const Value.absent(),
                Value<String?> logoAttachmentId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EmpresaCompanion(
                id: id,
                createdAt: createdAt,
                updatedAt: updatedAt,
                cicloVidaRegistro: cicloVidaRegistro,
                codigo: codigo,
                razonSocial: razonSocial,
                nombreComercial: nombreComercial,
                rfc: rfc,
                representanteLegal: representanteLegal,
                eslogan: eslogan,
                logoAttachmentId: logoAttachmentId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> cicloVidaRegistro = const Value.absent(),
                required String codigo,
                Value<String?> razonSocial = const Value.absent(),
                required String nombreComercial,
                Value<String?> rfc = const Value.absent(),
                Value<String?> representanteLegal = const Value.absent(),
                Value<String?> eslogan = const Value.absent(),
                Value<String?> logoAttachmentId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EmpresaCompanion.insert(
                id: id,
                createdAt: createdAt,
                updatedAt: updatedAt,
                cicloVidaRegistro: cicloVidaRegistro,
                codigo: codigo,
                razonSocial: razonSocial,
                nombreComercial: nombreComercial,
                rfc: rfc,
                representanteLegal: representanteLegal,
                eslogan: eslogan,
                logoAttachmentId: logoAttachmentId,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          $$EmpresaTableReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: ({logoAttachmentId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                T extends TableManagerState<
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic
                >
              >(state) {
                if (logoAttachmentId) {
                  state =
                      state.withJoin(
                            currentTable: table,
                            currentColumn: table.logoAttachmentId,
                            referencedTable: $$EmpresaTableReferences
                                ._logoAttachmentIdTable(db),
                            referencedColumn:
                                $$EmpresaTableReferences
                                    ._logoAttachmentIdTable(db)
                                    .id,
                          )
                          as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$EmpresaTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $EmpresaTable,
      EmpresaData,
      $$EmpresaTableFilterComposer,
      $$EmpresaTableOrderingComposer,
      $$EmpresaTableAnnotationComposer,
      $$EmpresaTableCreateCompanionBuilder,
      $$EmpresaTableUpdateCompanionBuilder,
      (EmpresaData, $$EmpresaTableReferences),
      EmpresaData,
      PrefetchHooks Function({bool logoAttachmentId})
    >;
typedef $$SucursalTableCreateCompanionBuilder =
    SucursalCompanion Function({
      Value<String> id,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<String> cicloVidaRegistro,
      required String codigo,
      required String nombre,
      required String tipoSucursalId,
      Value<String> estadoOperativo,
      Value<int> rowid,
    });
typedef $$SucursalTableUpdateCompanionBuilder =
    SucursalCompanion Function({
      Value<String> id,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<String> cicloVidaRegistro,
      Value<String> codigo,
      Value<String> nombre,
      Value<String> tipoSucursalId,
      Value<String> estadoOperativo,
      Value<int> rowid,
    });

final class $$SucursalTableReferences
    extends BaseReferences<_$AppDatabase, $SucursalTable, SucursalData> {
  $$SucursalTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $TipoSucursalTable _tipoSucursalIdTable(_$AppDatabase db) =>
      db.tipoSucursal.createAlias(
        $_aliasNameGenerator(db.sucursal.tipoSucursalId, db.tipoSucursal.id),
      );

  $$TipoSucursalTableProcessedTableManager get tipoSucursalId {
    final $_column = $_itemColumn<String>('tipo_sucursal_id')!;

    final manager = $$TipoSucursalTableTableManager(
      $_db,
      $_db.tipoSucursal,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_tipoSucursalIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$ServicioTable, List<ServicioData>>
  _servicioRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.servicio,
    aliasName: $_aliasNameGenerator(
      db.sucursal.id,
      db.servicio.sucursalAdministrativaId,
    ),
  );

  $$ServicioTableProcessedTableManager get servicioRefs {
    final manager = $$ServicioTableTableManager($_db, $_db.servicio).filter(
      (f) =>
          f.sucursalAdministrativaId.id.sqlEquals($_itemColumn<String>('id')!),
    );

    final cache = $_typedResult.readTableOrNull(_servicioRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$UbicacionTable, List<UbicacionData>>
  _ubicacionRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.ubicacion,
    aliasName: $_aliasNameGenerator(db.sucursal.id, db.ubicacion.sucursalId),
  );

  $$UbicacionTableProcessedTableManager get ubicacionRefs {
    final manager = $$UbicacionTableTableManager(
      $_db,
      $_db.ubicacion,
    ).filter((f) => f.sucursalId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_ubicacionRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$SucursalTableFilterComposer
    extends Composer<_$AppDatabase, $SucursalTable> {
  $$SucursalTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cicloVidaRegistro => $composableBuilder(
    column: $table.cicloVidaRegistro,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get codigo => $composableBuilder(
    column: $table.codigo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nombre => $composableBuilder(
    column: $table.nombre,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get estadoOperativo => $composableBuilder(
    column: $table.estadoOperativo,
    builder: (column) => ColumnFilters(column),
  );

  $$TipoSucursalTableFilterComposer get tipoSucursalId {
    final $$TipoSucursalTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.tipoSucursalId,
      referencedTable: $db.tipoSucursal,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TipoSucursalTableFilterComposer(
            $db: $db,
            $table: $db.tipoSucursal,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> servicioRefs(
    Expression<bool> Function($$ServicioTableFilterComposer f) f,
  ) {
    final $$ServicioTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.servicio,
      getReferencedColumn: (t) => t.sucursalAdministrativaId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ServicioTableFilterComposer(
            $db: $db,
            $table: $db.servicio,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> ubicacionRefs(
    Expression<bool> Function($$UbicacionTableFilterComposer f) f,
  ) {
    final $$UbicacionTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.ubicacion,
      getReferencedColumn: (t) => t.sucursalId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UbicacionTableFilterComposer(
            $db: $db,
            $table: $db.ubicacion,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SucursalTableOrderingComposer
    extends Composer<_$AppDatabase, $SucursalTable> {
  $$SucursalTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cicloVidaRegistro => $composableBuilder(
    column: $table.cicloVidaRegistro,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get codigo => $composableBuilder(
    column: $table.codigo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nombre => $composableBuilder(
    column: $table.nombre,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get estadoOperativo => $composableBuilder(
    column: $table.estadoOperativo,
    builder: (column) => ColumnOrderings(column),
  );

  $$TipoSucursalTableOrderingComposer get tipoSucursalId {
    final $$TipoSucursalTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.tipoSucursalId,
      referencedTable: $db.tipoSucursal,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TipoSucursalTableOrderingComposer(
            $db: $db,
            $table: $db.tipoSucursal,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SucursalTableAnnotationComposer
    extends Composer<_$AppDatabase, $SucursalTable> {
  $$SucursalTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get cicloVidaRegistro => $composableBuilder(
    column: $table.cicloVidaRegistro,
    builder: (column) => column,
  );

  GeneratedColumn<String> get codigo =>
      $composableBuilder(column: $table.codigo, builder: (column) => column);

  GeneratedColumn<String> get nombre =>
      $composableBuilder(column: $table.nombre, builder: (column) => column);

  GeneratedColumn<String> get estadoOperativo => $composableBuilder(
    column: $table.estadoOperativo,
    builder: (column) => column,
  );

  $$TipoSucursalTableAnnotationComposer get tipoSucursalId {
    final $$TipoSucursalTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.tipoSucursalId,
      referencedTable: $db.tipoSucursal,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TipoSucursalTableAnnotationComposer(
            $db: $db,
            $table: $db.tipoSucursal,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> servicioRefs<T extends Object>(
    Expression<T> Function($$ServicioTableAnnotationComposer a) f,
  ) {
    final $$ServicioTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.servicio,
      getReferencedColumn: (t) => t.sucursalAdministrativaId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ServicioTableAnnotationComposer(
            $db: $db,
            $table: $db.servicio,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> ubicacionRefs<T extends Object>(
    Expression<T> Function($$UbicacionTableAnnotationComposer a) f,
  ) {
    final $$UbicacionTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.ubicacion,
      getReferencedColumn: (t) => t.sucursalId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UbicacionTableAnnotationComposer(
            $db: $db,
            $table: $db.ubicacion,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SucursalTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SucursalTable,
          SucursalData,
          $$SucursalTableFilterComposer,
          $$SucursalTableOrderingComposer,
          $$SucursalTableAnnotationComposer,
          $$SucursalTableCreateCompanionBuilder,
          $$SucursalTableUpdateCompanionBuilder,
          (SucursalData, $$SucursalTableReferences),
          SucursalData,
          PrefetchHooks Function({
            bool tipoSucursalId,
            bool servicioRefs,
            bool ubicacionRefs,
          })
        > {
  $$SucursalTableTableManager(_$AppDatabase db, $SucursalTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$SucursalTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$SucursalTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$SucursalTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> cicloVidaRegistro = const Value.absent(),
                Value<String> codigo = const Value.absent(),
                Value<String> nombre = const Value.absent(),
                Value<String> tipoSucursalId = const Value.absent(),
                Value<String> estadoOperativo = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SucursalCompanion(
                id: id,
                createdAt: createdAt,
                updatedAt: updatedAt,
                cicloVidaRegistro: cicloVidaRegistro,
                codigo: codigo,
                nombre: nombre,
                tipoSucursalId: tipoSucursalId,
                estadoOperativo: estadoOperativo,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> cicloVidaRegistro = const Value.absent(),
                required String codigo,
                required String nombre,
                required String tipoSucursalId,
                Value<String> estadoOperativo = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SucursalCompanion.insert(
                id: id,
                createdAt: createdAt,
                updatedAt: updatedAt,
                cicloVidaRegistro: cicloVidaRegistro,
                codigo: codigo,
                nombre: nombre,
                tipoSucursalId: tipoSucursalId,
                estadoOperativo: estadoOperativo,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          $$SucursalTableReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: ({
            tipoSucursalId = false,
            servicioRefs = false,
            ubicacionRefs = false,
          }) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (servicioRefs) db.servicio,
                if (ubicacionRefs) db.ubicacion,
              ],
              addJoins: <
                T extends TableManagerState<
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic
                >
              >(state) {
                if (tipoSucursalId) {
                  state =
                      state.withJoin(
                            currentTable: table,
                            currentColumn: table.tipoSucursalId,
                            referencedTable: $$SucursalTableReferences
                                ._tipoSucursalIdTable(db),
                            referencedColumn:
                                $$SucursalTableReferences
                                    ._tipoSucursalIdTable(db)
                                    .id,
                          )
                          as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (servicioRefs)
                    await $_getPrefetchedData<
                      SucursalData,
                      $SucursalTable,
                      ServicioData
                    >(
                      currentTable: table,
                      referencedTable: $$SucursalTableReferences
                          ._servicioRefsTable(db),
                      managerFromTypedResult:
                          (p0) =>
                              $$SucursalTableReferences(
                                db,
                                table,
                                p0,
                              ).servicioRefs,
                      referencedItemsForCurrentItem:
                          (item, referencedItems) => referencedItems.where(
                            (e) => e.sucursalAdministrativaId == item.id,
                          ),
                      typedResults: items,
                    ),
                  if (ubicacionRefs)
                    await $_getPrefetchedData<
                      SucursalData,
                      $SucursalTable,
                      UbicacionData
                    >(
                      currentTable: table,
                      referencedTable: $$SucursalTableReferences
                          ._ubicacionRefsTable(db),
                      managerFromTypedResult:
                          (p0) =>
                              $$SucursalTableReferences(
                                db,
                                table,
                                p0,
                              ).ubicacionRefs,
                      referencedItemsForCurrentItem:
                          (item, referencedItems) => referencedItems.where(
                            (e) => e.sucursalId == item.id,
                          ),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$SucursalTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SucursalTable,
      SucursalData,
      $$SucursalTableFilterComposer,
      $$SucursalTableOrderingComposer,
      $$SucursalTableAnnotationComposer,
      $$SucursalTableCreateCompanionBuilder,
      $$SucursalTableUpdateCompanionBuilder,
      (SucursalData, $$SucursalTableReferences),
      SucursalData,
      PrefetchHooks Function({
        bool tipoSucursalId,
        bool servicioRefs,
        bool ubicacionRefs,
      })
    >;
typedef $$ClienteTableCreateCompanionBuilder =
    ClienteCompanion Function({
      Value<String> id,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<String> cicloVidaRegistro,
      required String codigo,
      required String razonSocial,
      Value<String?> nombreComercial,
      Value<String?> rfc,
      Value<String?> industriaId,
      Value<String> estatus,
      Value<DateTime> fechaAlta,
      Value<String?> observaciones,
      Value<int> rowid,
    });
typedef $$ClienteTableUpdateCompanionBuilder =
    ClienteCompanion Function({
      Value<String> id,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<String> cicloVidaRegistro,
      Value<String> codigo,
      Value<String> razonSocial,
      Value<String?> nombreComercial,
      Value<String?> rfc,
      Value<String?> industriaId,
      Value<String> estatus,
      Value<DateTime> fechaAlta,
      Value<String?> observaciones,
      Value<int> rowid,
    });

final class $$ClienteTableReferences
    extends BaseReferences<_$AppDatabase, $ClienteTable, ClienteData> {
  $$ClienteTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $IndustriaTable _industriaIdTable(_$AppDatabase db) =>
      db.industria.createAlias(
        $_aliasNameGenerator(db.cliente.industriaId, db.industria.id),
      );

  $$IndustriaTableProcessedTableManager? get industriaId {
    final $_column = $_itemColumn<String>('industria_id');
    if ($_column == null) return null;
    final manager = $$IndustriaTableTableManager(
      $_db,
      $_db.industria,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_industriaIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$ContactoTable, List<ContactoData>>
  _contactoRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.contacto,
    aliasName: $_aliasNameGenerator(db.cliente.id, db.contacto.clienteId),
  );

  $$ContactoTableProcessedTableManager get contactoRefs {
    final manager = $$ContactoTableTableManager(
      $_db,
      $_db.contacto,
    ).filter((f) => f.clienteId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_contactoRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ServicioTable, List<ServicioData>>
  _servicioRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.servicio,
    aliasName: $_aliasNameGenerator(db.cliente.id, db.servicio.clienteId),
  );

  $$ServicioTableProcessedTableManager get servicioRefs {
    final manager = $$ServicioTableTableManager(
      $_db,
      $_db.servicio,
    ).filter((f) => f.clienteId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_servicioRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ClienteTableFilterComposer
    extends Composer<_$AppDatabase, $ClienteTable> {
  $$ClienteTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cicloVidaRegistro => $composableBuilder(
    column: $table.cicloVidaRegistro,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get codigo => $composableBuilder(
    column: $table.codigo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get razonSocial => $composableBuilder(
    column: $table.razonSocial,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nombreComercial => $composableBuilder(
    column: $table.nombreComercial,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rfc => $composableBuilder(
    column: $table.rfc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get estatus => $composableBuilder(
    column: $table.estatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get fechaAlta => $composableBuilder(
    column: $table.fechaAlta,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get observaciones => $composableBuilder(
    column: $table.observaciones,
    builder: (column) => ColumnFilters(column),
  );

  $$IndustriaTableFilterComposer get industriaId {
    final $$IndustriaTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.industriaId,
      referencedTable: $db.industria,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$IndustriaTableFilterComposer(
            $db: $db,
            $table: $db.industria,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> contactoRefs(
    Expression<bool> Function($$ContactoTableFilterComposer f) f,
  ) {
    final $$ContactoTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.contacto,
      getReferencedColumn: (t) => t.clienteId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ContactoTableFilterComposer(
            $db: $db,
            $table: $db.contacto,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> servicioRefs(
    Expression<bool> Function($$ServicioTableFilterComposer f) f,
  ) {
    final $$ServicioTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.servicio,
      getReferencedColumn: (t) => t.clienteId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ServicioTableFilterComposer(
            $db: $db,
            $table: $db.servicio,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ClienteTableOrderingComposer
    extends Composer<_$AppDatabase, $ClienteTable> {
  $$ClienteTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cicloVidaRegistro => $composableBuilder(
    column: $table.cicloVidaRegistro,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get codigo => $composableBuilder(
    column: $table.codigo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get razonSocial => $composableBuilder(
    column: $table.razonSocial,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nombreComercial => $composableBuilder(
    column: $table.nombreComercial,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rfc => $composableBuilder(
    column: $table.rfc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get estatus => $composableBuilder(
    column: $table.estatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get fechaAlta => $composableBuilder(
    column: $table.fechaAlta,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get observaciones => $composableBuilder(
    column: $table.observaciones,
    builder: (column) => ColumnOrderings(column),
  );

  $$IndustriaTableOrderingComposer get industriaId {
    final $$IndustriaTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.industriaId,
      referencedTable: $db.industria,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$IndustriaTableOrderingComposer(
            $db: $db,
            $table: $db.industria,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ClienteTableAnnotationComposer
    extends Composer<_$AppDatabase, $ClienteTable> {
  $$ClienteTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get cicloVidaRegistro => $composableBuilder(
    column: $table.cicloVidaRegistro,
    builder: (column) => column,
  );

  GeneratedColumn<String> get codigo =>
      $composableBuilder(column: $table.codigo, builder: (column) => column);

  GeneratedColumn<String> get razonSocial => $composableBuilder(
    column: $table.razonSocial,
    builder: (column) => column,
  );

  GeneratedColumn<String> get nombreComercial => $composableBuilder(
    column: $table.nombreComercial,
    builder: (column) => column,
  );

  GeneratedColumn<String> get rfc =>
      $composableBuilder(column: $table.rfc, builder: (column) => column);

  GeneratedColumn<String> get estatus =>
      $composableBuilder(column: $table.estatus, builder: (column) => column);

  GeneratedColumn<DateTime> get fechaAlta =>
      $composableBuilder(column: $table.fechaAlta, builder: (column) => column);

  GeneratedColumn<String> get observaciones => $composableBuilder(
    column: $table.observaciones,
    builder: (column) => column,
  );

  $$IndustriaTableAnnotationComposer get industriaId {
    final $$IndustriaTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.industriaId,
      referencedTable: $db.industria,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$IndustriaTableAnnotationComposer(
            $db: $db,
            $table: $db.industria,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> contactoRefs<T extends Object>(
    Expression<T> Function($$ContactoTableAnnotationComposer a) f,
  ) {
    final $$ContactoTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.contacto,
      getReferencedColumn: (t) => t.clienteId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ContactoTableAnnotationComposer(
            $db: $db,
            $table: $db.contacto,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> servicioRefs<T extends Object>(
    Expression<T> Function($$ServicioTableAnnotationComposer a) f,
  ) {
    final $$ServicioTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.servicio,
      getReferencedColumn: (t) => t.clienteId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ServicioTableAnnotationComposer(
            $db: $db,
            $table: $db.servicio,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ClienteTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ClienteTable,
          ClienteData,
          $$ClienteTableFilterComposer,
          $$ClienteTableOrderingComposer,
          $$ClienteTableAnnotationComposer,
          $$ClienteTableCreateCompanionBuilder,
          $$ClienteTableUpdateCompanionBuilder,
          (ClienteData, $$ClienteTableReferences),
          ClienteData,
          PrefetchHooks Function({
            bool industriaId,
            bool contactoRefs,
            bool servicioRefs,
          })
        > {
  $$ClienteTableTableManager(_$AppDatabase db, $ClienteTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$ClienteTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$ClienteTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$ClienteTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> cicloVidaRegistro = const Value.absent(),
                Value<String> codigo = const Value.absent(),
                Value<String> razonSocial = const Value.absent(),
                Value<String?> nombreComercial = const Value.absent(),
                Value<String?> rfc = const Value.absent(),
                Value<String?> industriaId = const Value.absent(),
                Value<String> estatus = const Value.absent(),
                Value<DateTime> fechaAlta = const Value.absent(),
                Value<String?> observaciones = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ClienteCompanion(
                id: id,
                createdAt: createdAt,
                updatedAt: updatedAt,
                cicloVidaRegistro: cicloVidaRegistro,
                codigo: codigo,
                razonSocial: razonSocial,
                nombreComercial: nombreComercial,
                rfc: rfc,
                industriaId: industriaId,
                estatus: estatus,
                fechaAlta: fechaAlta,
                observaciones: observaciones,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> cicloVidaRegistro = const Value.absent(),
                required String codigo,
                required String razonSocial,
                Value<String?> nombreComercial = const Value.absent(),
                Value<String?> rfc = const Value.absent(),
                Value<String?> industriaId = const Value.absent(),
                Value<String> estatus = const Value.absent(),
                Value<DateTime> fechaAlta = const Value.absent(),
                Value<String?> observaciones = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ClienteCompanion.insert(
                id: id,
                createdAt: createdAt,
                updatedAt: updatedAt,
                cicloVidaRegistro: cicloVidaRegistro,
                codigo: codigo,
                razonSocial: razonSocial,
                nombreComercial: nombreComercial,
                rfc: rfc,
                industriaId: industriaId,
                estatus: estatus,
                fechaAlta: fechaAlta,
                observaciones: observaciones,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          $$ClienteTableReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: ({
            industriaId = false,
            contactoRefs = false,
            servicioRefs = false,
          }) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (contactoRefs) db.contacto,
                if (servicioRefs) db.servicio,
              ],
              addJoins: <
                T extends TableManagerState<
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic
                >
              >(state) {
                if (industriaId) {
                  state =
                      state.withJoin(
                            currentTable: table,
                            currentColumn: table.industriaId,
                            referencedTable: $$ClienteTableReferences
                                ._industriaIdTable(db),
                            referencedColumn:
                                $$ClienteTableReferences
                                    ._industriaIdTable(db)
                                    .id,
                          )
                          as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (contactoRefs)
                    await $_getPrefetchedData<
                      ClienteData,
                      $ClienteTable,
                      ContactoData
                    >(
                      currentTable: table,
                      referencedTable: $$ClienteTableReferences
                          ._contactoRefsTable(db),
                      managerFromTypedResult:
                          (p0) =>
                              $$ClienteTableReferences(
                                db,
                                table,
                                p0,
                              ).contactoRefs,
                      referencedItemsForCurrentItem:
                          (item, referencedItems) => referencedItems.where(
                            (e) => e.clienteId == item.id,
                          ),
                      typedResults: items,
                    ),
                  if (servicioRefs)
                    await $_getPrefetchedData<
                      ClienteData,
                      $ClienteTable,
                      ServicioData
                    >(
                      currentTable: table,
                      referencedTable: $$ClienteTableReferences
                          ._servicioRefsTable(db),
                      managerFromTypedResult:
                          (p0) =>
                              $$ClienteTableReferences(
                                db,
                                table,
                                p0,
                              ).servicioRefs,
                      referencedItemsForCurrentItem:
                          (item, referencedItems) => referencedItems.where(
                            (e) => e.clienteId == item.id,
                          ),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$ClienteTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ClienteTable,
      ClienteData,
      $$ClienteTableFilterComposer,
      $$ClienteTableOrderingComposer,
      $$ClienteTableAnnotationComposer,
      $$ClienteTableCreateCompanionBuilder,
      $$ClienteTableUpdateCompanionBuilder,
      (ClienteData, $$ClienteTableReferences),
      ClienteData,
      PrefetchHooks Function({
        bool industriaId,
        bool contactoRefs,
        bool servicioRefs,
      })
    >;
typedef $$ContactoTableCreateCompanionBuilder =
    ContactoCompanion Function({
      Value<String> id,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<String> cicloVidaRegistro,
      required String clienteId,
      required String nombre,
      Value<String?> puesto,
      Value<String?> telefono,
      Value<String?> correo,
      Value<bool> esPrincipal,
      Value<int> rowid,
    });
typedef $$ContactoTableUpdateCompanionBuilder =
    ContactoCompanion Function({
      Value<String> id,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<String> cicloVidaRegistro,
      Value<String> clienteId,
      Value<String> nombre,
      Value<String?> puesto,
      Value<String?> telefono,
      Value<String?> correo,
      Value<bool> esPrincipal,
      Value<int> rowid,
    });

final class $$ContactoTableReferences
    extends BaseReferences<_$AppDatabase, $ContactoTable, ContactoData> {
  $$ContactoTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ClienteTable _clienteIdTable(_$AppDatabase db) => db.cliente
      .createAlias($_aliasNameGenerator(db.contacto.clienteId, db.cliente.id));

  $$ClienteTableProcessedTableManager get clienteId {
    final $_column = $_itemColumn<String>('cliente_id')!;

    final manager = $$ClienteTableTableManager(
      $_db,
      $_db.cliente,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_clienteIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$ServicioTable, List<ServicioData>>
  _servicioRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.servicio,
    aliasName: $_aliasNameGenerator(
      db.contacto.id,
      db.servicio.responsableClienteContactoId,
    ),
  );

  $$ServicioTableProcessedTableManager get servicioRefs {
    final manager = $$ServicioTableTableManager($_db, $_db.servicio).filter(
      (f) => f.responsableClienteContactoId.id.sqlEquals(
        $_itemColumn<String>('id')!,
      ),
    );

    final cache = $_typedResult.readTableOrNull(_servicioRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ContactoTableFilterComposer
    extends Composer<_$AppDatabase, $ContactoTable> {
  $$ContactoTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cicloVidaRegistro => $composableBuilder(
    column: $table.cicloVidaRegistro,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nombre => $composableBuilder(
    column: $table.nombre,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get puesto => $composableBuilder(
    column: $table.puesto,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get telefono => $composableBuilder(
    column: $table.telefono,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get correo => $composableBuilder(
    column: $table.correo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get esPrincipal => $composableBuilder(
    column: $table.esPrincipal,
    builder: (column) => ColumnFilters(column),
  );

  $$ClienteTableFilterComposer get clienteId {
    final $$ClienteTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.clienteId,
      referencedTable: $db.cliente,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ClienteTableFilterComposer(
            $db: $db,
            $table: $db.cliente,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> servicioRefs(
    Expression<bool> Function($$ServicioTableFilterComposer f) f,
  ) {
    final $$ServicioTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.servicio,
      getReferencedColumn: (t) => t.responsableClienteContactoId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ServicioTableFilterComposer(
            $db: $db,
            $table: $db.servicio,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ContactoTableOrderingComposer
    extends Composer<_$AppDatabase, $ContactoTable> {
  $$ContactoTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cicloVidaRegistro => $composableBuilder(
    column: $table.cicloVidaRegistro,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nombre => $composableBuilder(
    column: $table.nombre,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get puesto => $composableBuilder(
    column: $table.puesto,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get telefono => $composableBuilder(
    column: $table.telefono,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get correo => $composableBuilder(
    column: $table.correo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get esPrincipal => $composableBuilder(
    column: $table.esPrincipal,
    builder: (column) => ColumnOrderings(column),
  );

  $$ClienteTableOrderingComposer get clienteId {
    final $$ClienteTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.clienteId,
      referencedTable: $db.cliente,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ClienteTableOrderingComposer(
            $db: $db,
            $table: $db.cliente,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ContactoTableAnnotationComposer
    extends Composer<_$AppDatabase, $ContactoTable> {
  $$ContactoTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get cicloVidaRegistro => $composableBuilder(
    column: $table.cicloVidaRegistro,
    builder: (column) => column,
  );

  GeneratedColumn<String> get nombre =>
      $composableBuilder(column: $table.nombre, builder: (column) => column);

  GeneratedColumn<String> get puesto =>
      $composableBuilder(column: $table.puesto, builder: (column) => column);

  GeneratedColumn<String> get telefono =>
      $composableBuilder(column: $table.telefono, builder: (column) => column);

  GeneratedColumn<String> get correo =>
      $composableBuilder(column: $table.correo, builder: (column) => column);

  GeneratedColumn<bool> get esPrincipal => $composableBuilder(
    column: $table.esPrincipal,
    builder: (column) => column,
  );

  $$ClienteTableAnnotationComposer get clienteId {
    final $$ClienteTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.clienteId,
      referencedTable: $db.cliente,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ClienteTableAnnotationComposer(
            $db: $db,
            $table: $db.cliente,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> servicioRefs<T extends Object>(
    Expression<T> Function($$ServicioTableAnnotationComposer a) f,
  ) {
    final $$ServicioTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.servicio,
      getReferencedColumn: (t) => t.responsableClienteContactoId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ServicioTableAnnotationComposer(
            $db: $db,
            $table: $db.servicio,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ContactoTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ContactoTable,
          ContactoData,
          $$ContactoTableFilterComposer,
          $$ContactoTableOrderingComposer,
          $$ContactoTableAnnotationComposer,
          $$ContactoTableCreateCompanionBuilder,
          $$ContactoTableUpdateCompanionBuilder,
          (ContactoData, $$ContactoTableReferences),
          ContactoData,
          PrefetchHooks Function({bool clienteId, bool servicioRefs})
        > {
  $$ContactoTableTableManager(_$AppDatabase db, $ContactoTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$ContactoTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$ContactoTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$ContactoTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> cicloVidaRegistro = const Value.absent(),
                Value<String> clienteId = const Value.absent(),
                Value<String> nombre = const Value.absent(),
                Value<String?> puesto = const Value.absent(),
                Value<String?> telefono = const Value.absent(),
                Value<String?> correo = const Value.absent(),
                Value<bool> esPrincipal = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ContactoCompanion(
                id: id,
                createdAt: createdAt,
                updatedAt: updatedAt,
                cicloVidaRegistro: cicloVidaRegistro,
                clienteId: clienteId,
                nombre: nombre,
                puesto: puesto,
                telefono: telefono,
                correo: correo,
                esPrincipal: esPrincipal,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> cicloVidaRegistro = const Value.absent(),
                required String clienteId,
                required String nombre,
                Value<String?> puesto = const Value.absent(),
                Value<String?> telefono = const Value.absent(),
                Value<String?> correo = const Value.absent(),
                Value<bool> esPrincipal = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ContactoCompanion.insert(
                id: id,
                createdAt: createdAt,
                updatedAt: updatedAt,
                cicloVidaRegistro: cicloVidaRegistro,
                clienteId: clienteId,
                nombre: nombre,
                puesto: puesto,
                telefono: telefono,
                correo: correo,
                esPrincipal: esPrincipal,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          $$ContactoTableReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: ({clienteId = false, servicioRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (servicioRefs) db.servicio],
              addJoins: <
                T extends TableManagerState<
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic
                >
              >(state) {
                if (clienteId) {
                  state =
                      state.withJoin(
                            currentTable: table,
                            currentColumn: table.clienteId,
                            referencedTable: $$ContactoTableReferences
                                ._clienteIdTable(db),
                            referencedColumn:
                                $$ContactoTableReferences
                                    ._clienteIdTable(db)
                                    .id,
                          )
                          as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (servicioRefs)
                    await $_getPrefetchedData<
                      ContactoData,
                      $ContactoTable,
                      ServicioData
                    >(
                      currentTable: table,
                      referencedTable: $$ContactoTableReferences
                          ._servicioRefsTable(db),
                      managerFromTypedResult:
                          (p0) =>
                              $$ContactoTableReferences(
                                db,
                                table,
                                p0,
                              ).servicioRefs,
                      referencedItemsForCurrentItem:
                          (item, referencedItems) => referencedItems.where(
                            (e) => e.responsableClienteContactoId == item.id,
                          ),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$ContactoTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ContactoTable,
      ContactoData,
      $$ContactoTableFilterComposer,
      $$ContactoTableOrderingComposer,
      $$ContactoTableAnnotationComposer,
      $$ContactoTableCreateCompanionBuilder,
      $$ContactoTableUpdateCompanionBuilder,
      (ContactoData, $$ContactoTableReferences),
      ContactoData,
      PrefetchHooks Function({bool clienteId, bool servicioRefs})
    >;
typedef $$ServicioTableCreateCompanionBuilder =
    ServicioCompanion Function({
      Value<String> id,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<String> cicloVidaRegistro,
      required String codigo,
      required String clienteId,
      required String nombre,
      required String tipoServicioId,
      required String sucursalAdministrativaId,
      Value<String> estatus,
      required DateTime fechaInicio,
      Value<DateTime?> fechaTermino,
      Value<int> elementosAutorizados,
      Value<String?> responsableClienteContactoId,
      Value<String?> observaciones,
      Value<int> rowid,
    });
typedef $$ServicioTableUpdateCompanionBuilder =
    ServicioCompanion Function({
      Value<String> id,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<String> cicloVidaRegistro,
      Value<String> codigo,
      Value<String> clienteId,
      Value<String> nombre,
      Value<String> tipoServicioId,
      Value<String> sucursalAdministrativaId,
      Value<String> estatus,
      Value<DateTime> fechaInicio,
      Value<DateTime?> fechaTermino,
      Value<int> elementosAutorizados,
      Value<String?> responsableClienteContactoId,
      Value<String?> observaciones,
      Value<int> rowid,
    });

final class $$ServicioTableReferences
    extends BaseReferences<_$AppDatabase, $ServicioTable, ServicioData> {
  $$ServicioTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ClienteTable _clienteIdTable(_$AppDatabase db) => db.cliente
      .createAlias($_aliasNameGenerator(db.servicio.clienteId, db.cliente.id));

  $$ClienteTableProcessedTableManager get clienteId {
    final $_column = $_itemColumn<String>('cliente_id')!;

    final manager = $$ClienteTableTableManager(
      $_db,
      $_db.cliente,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_clienteIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $TipoServicioTable _tipoServicioIdTable(_$AppDatabase db) =>
      db.tipoServicio.createAlias(
        $_aliasNameGenerator(db.servicio.tipoServicioId, db.tipoServicio.id),
      );

  $$TipoServicioTableProcessedTableManager get tipoServicioId {
    final $_column = $_itemColumn<String>('tipo_servicio_id')!;

    final manager = $$TipoServicioTableTableManager(
      $_db,
      $_db.tipoServicio,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_tipoServicioIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $SucursalTable _sucursalAdministrativaIdTable(_$AppDatabase db) =>
      db.sucursal.createAlias(
        $_aliasNameGenerator(
          db.servicio.sucursalAdministrativaId,
          db.sucursal.id,
        ),
      );

  $$SucursalTableProcessedTableManager get sucursalAdministrativaId {
    final $_column = $_itemColumn<String>('sucursal_administrativa_id')!;

    final manager = $$SucursalTableTableManager(
      $_db,
      $_db.sucursal,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(
      _sucursalAdministrativaIdTable($_db),
    );
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $ContactoTable _responsableClienteContactoIdTable(_$AppDatabase db) =>
      db.contacto.createAlias(
        $_aliasNameGenerator(
          db.servicio.responsableClienteContactoId,
          db.contacto.id,
        ),
      );

  $$ContactoTableProcessedTableManager? get responsableClienteContactoId {
    final $_column = $_itemColumn<String>('responsable_cliente_contacto_id');
    if ($_column == null) return null;
    final manager = $$ContactoTableTableManager(
      $_db,
      $_db.contacto,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(
      _responsableClienteContactoIdTable($_db),
    );
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$UbicacionTable, List<UbicacionData>>
  _ubicacionRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.ubicacion,
    aliasName: $_aliasNameGenerator(db.servicio.id, db.ubicacion.servicioId),
  );

  $$UbicacionTableProcessedTableManager get ubicacionRefs {
    final manager = $$UbicacionTableTableManager(
      $_db,
      $_db.ubicacion,
    ).filter((f) => f.servicioId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_ubicacionRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ServicioTableFilterComposer
    extends Composer<_$AppDatabase, $ServicioTable> {
  $$ServicioTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cicloVidaRegistro => $composableBuilder(
    column: $table.cicloVidaRegistro,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get codigo => $composableBuilder(
    column: $table.codigo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nombre => $composableBuilder(
    column: $table.nombre,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get estatus => $composableBuilder(
    column: $table.estatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get fechaInicio => $composableBuilder(
    column: $table.fechaInicio,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get fechaTermino => $composableBuilder(
    column: $table.fechaTermino,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get elementosAutorizados => $composableBuilder(
    column: $table.elementosAutorizados,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get observaciones => $composableBuilder(
    column: $table.observaciones,
    builder: (column) => ColumnFilters(column),
  );

  $$ClienteTableFilterComposer get clienteId {
    final $$ClienteTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.clienteId,
      referencedTable: $db.cliente,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ClienteTableFilterComposer(
            $db: $db,
            $table: $db.cliente,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TipoServicioTableFilterComposer get tipoServicioId {
    final $$TipoServicioTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.tipoServicioId,
      referencedTable: $db.tipoServicio,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TipoServicioTableFilterComposer(
            $db: $db,
            $table: $db.tipoServicio,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SucursalTableFilterComposer get sucursalAdministrativaId {
    final $$SucursalTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sucursalAdministrativaId,
      referencedTable: $db.sucursal,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SucursalTableFilterComposer(
            $db: $db,
            $table: $db.sucursal,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ContactoTableFilterComposer get responsableClienteContactoId {
    final $$ContactoTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.responsableClienteContactoId,
      referencedTable: $db.contacto,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ContactoTableFilterComposer(
            $db: $db,
            $table: $db.contacto,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> ubicacionRefs(
    Expression<bool> Function($$UbicacionTableFilterComposer f) f,
  ) {
    final $$UbicacionTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.ubicacion,
      getReferencedColumn: (t) => t.servicioId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UbicacionTableFilterComposer(
            $db: $db,
            $table: $db.ubicacion,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ServicioTableOrderingComposer
    extends Composer<_$AppDatabase, $ServicioTable> {
  $$ServicioTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cicloVidaRegistro => $composableBuilder(
    column: $table.cicloVidaRegistro,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get codigo => $composableBuilder(
    column: $table.codigo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nombre => $composableBuilder(
    column: $table.nombre,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get estatus => $composableBuilder(
    column: $table.estatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get fechaInicio => $composableBuilder(
    column: $table.fechaInicio,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get fechaTermino => $composableBuilder(
    column: $table.fechaTermino,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get elementosAutorizados => $composableBuilder(
    column: $table.elementosAutorizados,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get observaciones => $composableBuilder(
    column: $table.observaciones,
    builder: (column) => ColumnOrderings(column),
  );

  $$ClienteTableOrderingComposer get clienteId {
    final $$ClienteTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.clienteId,
      referencedTable: $db.cliente,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ClienteTableOrderingComposer(
            $db: $db,
            $table: $db.cliente,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TipoServicioTableOrderingComposer get tipoServicioId {
    final $$TipoServicioTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.tipoServicioId,
      referencedTable: $db.tipoServicio,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TipoServicioTableOrderingComposer(
            $db: $db,
            $table: $db.tipoServicio,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SucursalTableOrderingComposer get sucursalAdministrativaId {
    final $$SucursalTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sucursalAdministrativaId,
      referencedTable: $db.sucursal,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SucursalTableOrderingComposer(
            $db: $db,
            $table: $db.sucursal,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ContactoTableOrderingComposer get responsableClienteContactoId {
    final $$ContactoTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.responsableClienteContactoId,
      referencedTable: $db.contacto,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ContactoTableOrderingComposer(
            $db: $db,
            $table: $db.contacto,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ServicioTableAnnotationComposer
    extends Composer<_$AppDatabase, $ServicioTable> {
  $$ServicioTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get cicloVidaRegistro => $composableBuilder(
    column: $table.cicloVidaRegistro,
    builder: (column) => column,
  );

  GeneratedColumn<String> get codigo =>
      $composableBuilder(column: $table.codigo, builder: (column) => column);

  GeneratedColumn<String> get nombre =>
      $composableBuilder(column: $table.nombre, builder: (column) => column);

  GeneratedColumn<String> get estatus =>
      $composableBuilder(column: $table.estatus, builder: (column) => column);

  GeneratedColumn<DateTime> get fechaInicio => $composableBuilder(
    column: $table.fechaInicio,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get fechaTermino => $composableBuilder(
    column: $table.fechaTermino,
    builder: (column) => column,
  );

  GeneratedColumn<int> get elementosAutorizados => $composableBuilder(
    column: $table.elementosAutorizados,
    builder: (column) => column,
  );

  GeneratedColumn<String> get observaciones => $composableBuilder(
    column: $table.observaciones,
    builder: (column) => column,
  );

  $$ClienteTableAnnotationComposer get clienteId {
    final $$ClienteTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.clienteId,
      referencedTable: $db.cliente,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ClienteTableAnnotationComposer(
            $db: $db,
            $table: $db.cliente,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TipoServicioTableAnnotationComposer get tipoServicioId {
    final $$TipoServicioTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.tipoServicioId,
      referencedTable: $db.tipoServicio,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TipoServicioTableAnnotationComposer(
            $db: $db,
            $table: $db.tipoServicio,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SucursalTableAnnotationComposer get sucursalAdministrativaId {
    final $$SucursalTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sucursalAdministrativaId,
      referencedTable: $db.sucursal,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SucursalTableAnnotationComposer(
            $db: $db,
            $table: $db.sucursal,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ContactoTableAnnotationComposer get responsableClienteContactoId {
    final $$ContactoTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.responsableClienteContactoId,
      referencedTable: $db.contacto,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ContactoTableAnnotationComposer(
            $db: $db,
            $table: $db.contacto,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> ubicacionRefs<T extends Object>(
    Expression<T> Function($$UbicacionTableAnnotationComposer a) f,
  ) {
    final $$UbicacionTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.ubicacion,
      getReferencedColumn: (t) => t.servicioId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UbicacionTableAnnotationComposer(
            $db: $db,
            $table: $db.ubicacion,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ServicioTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ServicioTable,
          ServicioData,
          $$ServicioTableFilterComposer,
          $$ServicioTableOrderingComposer,
          $$ServicioTableAnnotationComposer,
          $$ServicioTableCreateCompanionBuilder,
          $$ServicioTableUpdateCompanionBuilder,
          (ServicioData, $$ServicioTableReferences),
          ServicioData,
          PrefetchHooks Function({
            bool clienteId,
            bool tipoServicioId,
            bool sucursalAdministrativaId,
            bool responsableClienteContactoId,
            bool ubicacionRefs,
          })
        > {
  $$ServicioTableTableManager(_$AppDatabase db, $ServicioTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$ServicioTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$ServicioTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$ServicioTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> cicloVidaRegistro = const Value.absent(),
                Value<String> codigo = const Value.absent(),
                Value<String> clienteId = const Value.absent(),
                Value<String> nombre = const Value.absent(),
                Value<String> tipoServicioId = const Value.absent(),
                Value<String> sucursalAdministrativaId = const Value.absent(),
                Value<String> estatus = const Value.absent(),
                Value<DateTime> fechaInicio = const Value.absent(),
                Value<DateTime?> fechaTermino = const Value.absent(),
                Value<int> elementosAutorizados = const Value.absent(),
                Value<String?> responsableClienteContactoId =
                    const Value.absent(),
                Value<String?> observaciones = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ServicioCompanion(
                id: id,
                createdAt: createdAt,
                updatedAt: updatedAt,
                cicloVidaRegistro: cicloVidaRegistro,
                codigo: codigo,
                clienteId: clienteId,
                nombre: nombre,
                tipoServicioId: tipoServicioId,
                sucursalAdministrativaId: sucursalAdministrativaId,
                estatus: estatus,
                fechaInicio: fechaInicio,
                fechaTermino: fechaTermino,
                elementosAutorizados: elementosAutorizados,
                responsableClienteContactoId: responsableClienteContactoId,
                observaciones: observaciones,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> cicloVidaRegistro = const Value.absent(),
                required String codigo,
                required String clienteId,
                required String nombre,
                required String tipoServicioId,
                required String sucursalAdministrativaId,
                Value<String> estatus = const Value.absent(),
                required DateTime fechaInicio,
                Value<DateTime?> fechaTermino = const Value.absent(),
                Value<int> elementosAutorizados = const Value.absent(),
                Value<String?> responsableClienteContactoId =
                    const Value.absent(),
                Value<String?> observaciones = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ServicioCompanion.insert(
                id: id,
                createdAt: createdAt,
                updatedAt: updatedAt,
                cicloVidaRegistro: cicloVidaRegistro,
                codigo: codigo,
                clienteId: clienteId,
                nombre: nombre,
                tipoServicioId: tipoServicioId,
                sucursalAdministrativaId: sucursalAdministrativaId,
                estatus: estatus,
                fechaInicio: fechaInicio,
                fechaTermino: fechaTermino,
                elementosAutorizados: elementosAutorizados,
                responsableClienteContactoId: responsableClienteContactoId,
                observaciones: observaciones,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          $$ServicioTableReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: ({
            clienteId = false,
            tipoServicioId = false,
            sucursalAdministrativaId = false,
            responsableClienteContactoId = false,
            ubicacionRefs = false,
          }) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (ubicacionRefs) db.ubicacion],
              addJoins: <
                T extends TableManagerState<
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic
                >
              >(state) {
                if (clienteId) {
                  state =
                      state.withJoin(
                            currentTable: table,
                            currentColumn: table.clienteId,
                            referencedTable: $$ServicioTableReferences
                                ._clienteIdTable(db),
                            referencedColumn:
                                $$ServicioTableReferences
                                    ._clienteIdTable(db)
                                    .id,
                          )
                          as T;
                }
                if (tipoServicioId) {
                  state =
                      state.withJoin(
                            currentTable: table,
                            currentColumn: table.tipoServicioId,
                            referencedTable: $$ServicioTableReferences
                                ._tipoServicioIdTable(db),
                            referencedColumn:
                                $$ServicioTableReferences
                                    ._tipoServicioIdTable(db)
                                    .id,
                          )
                          as T;
                }
                if (sucursalAdministrativaId) {
                  state =
                      state.withJoin(
                            currentTable: table,
                            currentColumn: table.sucursalAdministrativaId,
                            referencedTable: $$ServicioTableReferences
                                ._sucursalAdministrativaIdTable(db),
                            referencedColumn:
                                $$ServicioTableReferences
                                    ._sucursalAdministrativaIdTable(db)
                                    .id,
                          )
                          as T;
                }
                if (responsableClienteContactoId) {
                  state =
                      state.withJoin(
                            currentTable: table,
                            currentColumn: table.responsableClienteContactoId,
                            referencedTable: $$ServicioTableReferences
                                ._responsableClienteContactoIdTable(db),
                            referencedColumn:
                                $$ServicioTableReferences
                                    ._responsableClienteContactoIdTable(db)
                                    .id,
                          )
                          as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (ubicacionRefs)
                    await $_getPrefetchedData<
                      ServicioData,
                      $ServicioTable,
                      UbicacionData
                    >(
                      currentTable: table,
                      referencedTable: $$ServicioTableReferences
                          ._ubicacionRefsTable(db),
                      managerFromTypedResult:
                          (p0) =>
                              $$ServicioTableReferences(
                                db,
                                table,
                                p0,
                              ).ubicacionRefs,
                      referencedItemsForCurrentItem:
                          (item, referencedItems) => referencedItems.where(
                            (e) => e.servicioId == item.id,
                          ),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$ServicioTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ServicioTable,
      ServicioData,
      $$ServicioTableFilterComposer,
      $$ServicioTableOrderingComposer,
      $$ServicioTableAnnotationComposer,
      $$ServicioTableCreateCompanionBuilder,
      $$ServicioTableUpdateCompanionBuilder,
      (ServicioData, $$ServicioTableReferences),
      ServicioData,
      PrefetchHooks Function({
        bool clienteId,
        bool tipoServicioId,
        bool sucursalAdministrativaId,
        bool responsableClienteContactoId,
        bool ubicacionRefs,
      })
    >;
typedef $$UbicacionTableCreateCompanionBuilder =
    UbicacionCompanion Function({
      Value<String> id,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<String> cicloVidaRegistro,
      required String codigo,
      required String nombre,
      required String tipoUbicacion,
      Value<String?> parentId,
      Value<String?> sucursalId,
      Value<String?> servicioId,
      Value<int> rowid,
    });
typedef $$UbicacionTableUpdateCompanionBuilder =
    UbicacionCompanion Function({
      Value<String> id,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<String> cicloVidaRegistro,
      Value<String> codigo,
      Value<String> nombre,
      Value<String> tipoUbicacion,
      Value<String?> parentId,
      Value<String?> sucursalId,
      Value<String?> servicioId,
      Value<int> rowid,
    });

final class $$UbicacionTableReferences
    extends BaseReferences<_$AppDatabase, $UbicacionTable, UbicacionData> {
  $$UbicacionTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $UbicacionTable _parentIdTable(_$AppDatabase db) =>
      db.ubicacion.createAlias(
        $_aliasNameGenerator(db.ubicacion.parentId, db.ubicacion.id),
      );

  $$UbicacionTableProcessedTableManager? get parentId {
    final $_column = $_itemColumn<String>('parent_id');
    if ($_column == null) return null;
    final manager = $$UbicacionTableTableManager(
      $_db,
      $_db.ubicacion,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_parentIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $SucursalTable _sucursalIdTable(_$AppDatabase db) =>
      db.sucursal.createAlias(
        $_aliasNameGenerator(db.ubicacion.sucursalId, db.sucursal.id),
      );

  $$SucursalTableProcessedTableManager? get sucursalId {
    final $_column = $_itemColumn<String>('sucursal_id');
    if ($_column == null) return null;
    final manager = $$SucursalTableTableManager(
      $_db,
      $_db.sucursal,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sucursalIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $ServicioTable _servicioIdTable(_$AppDatabase db) =>
      db.servicio.createAlias(
        $_aliasNameGenerator(db.ubicacion.servicioId, db.servicio.id),
      );

  $$ServicioTableProcessedTableManager? get servicioId {
    final $_column = $_itemColumn<String>('servicio_id');
    if ($_column == null) return null;
    final manager = $$ServicioTableTableManager(
      $_db,
      $_db.servicio,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_servicioIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$UbicacionTableFilterComposer
    extends Composer<_$AppDatabase, $UbicacionTable> {
  $$UbicacionTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cicloVidaRegistro => $composableBuilder(
    column: $table.cicloVidaRegistro,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get codigo => $composableBuilder(
    column: $table.codigo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nombre => $composableBuilder(
    column: $table.nombre,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tipoUbicacion => $composableBuilder(
    column: $table.tipoUbicacion,
    builder: (column) => ColumnFilters(column),
  );

  $$UbicacionTableFilterComposer get parentId {
    final $$UbicacionTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.parentId,
      referencedTable: $db.ubicacion,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UbicacionTableFilterComposer(
            $db: $db,
            $table: $db.ubicacion,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SucursalTableFilterComposer get sucursalId {
    final $$SucursalTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sucursalId,
      referencedTable: $db.sucursal,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SucursalTableFilterComposer(
            $db: $db,
            $table: $db.sucursal,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ServicioTableFilterComposer get servicioId {
    final $$ServicioTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.servicioId,
      referencedTable: $db.servicio,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ServicioTableFilterComposer(
            $db: $db,
            $table: $db.servicio,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$UbicacionTableOrderingComposer
    extends Composer<_$AppDatabase, $UbicacionTable> {
  $$UbicacionTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cicloVidaRegistro => $composableBuilder(
    column: $table.cicloVidaRegistro,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get codigo => $composableBuilder(
    column: $table.codigo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nombre => $composableBuilder(
    column: $table.nombre,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tipoUbicacion => $composableBuilder(
    column: $table.tipoUbicacion,
    builder: (column) => ColumnOrderings(column),
  );

  $$UbicacionTableOrderingComposer get parentId {
    final $$UbicacionTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.parentId,
      referencedTable: $db.ubicacion,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UbicacionTableOrderingComposer(
            $db: $db,
            $table: $db.ubicacion,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SucursalTableOrderingComposer get sucursalId {
    final $$SucursalTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sucursalId,
      referencedTable: $db.sucursal,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SucursalTableOrderingComposer(
            $db: $db,
            $table: $db.sucursal,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ServicioTableOrderingComposer get servicioId {
    final $$ServicioTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.servicioId,
      referencedTable: $db.servicio,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ServicioTableOrderingComposer(
            $db: $db,
            $table: $db.servicio,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$UbicacionTableAnnotationComposer
    extends Composer<_$AppDatabase, $UbicacionTable> {
  $$UbicacionTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get cicloVidaRegistro => $composableBuilder(
    column: $table.cicloVidaRegistro,
    builder: (column) => column,
  );

  GeneratedColumn<String> get codigo =>
      $composableBuilder(column: $table.codigo, builder: (column) => column);

  GeneratedColumn<String> get nombre =>
      $composableBuilder(column: $table.nombre, builder: (column) => column);

  GeneratedColumn<String> get tipoUbicacion => $composableBuilder(
    column: $table.tipoUbicacion,
    builder: (column) => column,
  );

  $$UbicacionTableAnnotationComposer get parentId {
    final $$UbicacionTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.parentId,
      referencedTable: $db.ubicacion,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UbicacionTableAnnotationComposer(
            $db: $db,
            $table: $db.ubicacion,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SucursalTableAnnotationComposer get sucursalId {
    final $$SucursalTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sucursalId,
      referencedTable: $db.sucursal,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SucursalTableAnnotationComposer(
            $db: $db,
            $table: $db.sucursal,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ServicioTableAnnotationComposer get servicioId {
    final $$ServicioTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.servicioId,
      referencedTable: $db.servicio,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ServicioTableAnnotationComposer(
            $db: $db,
            $table: $db.servicio,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$UbicacionTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $UbicacionTable,
          UbicacionData,
          $$UbicacionTableFilterComposer,
          $$UbicacionTableOrderingComposer,
          $$UbicacionTableAnnotationComposer,
          $$UbicacionTableCreateCompanionBuilder,
          $$UbicacionTableUpdateCompanionBuilder,
          (UbicacionData, $$UbicacionTableReferences),
          UbicacionData,
          PrefetchHooks Function({
            bool parentId,
            bool sucursalId,
            bool servicioId,
          })
        > {
  $$UbicacionTableTableManager(_$AppDatabase db, $UbicacionTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$UbicacionTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$UbicacionTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$UbicacionTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> cicloVidaRegistro = const Value.absent(),
                Value<String> codigo = const Value.absent(),
                Value<String> nombre = const Value.absent(),
                Value<String> tipoUbicacion = const Value.absent(),
                Value<String?> parentId = const Value.absent(),
                Value<String?> sucursalId = const Value.absent(),
                Value<String?> servicioId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UbicacionCompanion(
                id: id,
                createdAt: createdAt,
                updatedAt: updatedAt,
                cicloVidaRegistro: cicloVidaRegistro,
                codigo: codigo,
                nombre: nombre,
                tipoUbicacion: tipoUbicacion,
                parentId: parentId,
                sucursalId: sucursalId,
                servicioId: servicioId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> cicloVidaRegistro = const Value.absent(),
                required String codigo,
                required String nombre,
                required String tipoUbicacion,
                Value<String?> parentId = const Value.absent(),
                Value<String?> sucursalId = const Value.absent(),
                Value<String?> servicioId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UbicacionCompanion.insert(
                id: id,
                createdAt: createdAt,
                updatedAt: updatedAt,
                cicloVidaRegistro: cicloVidaRegistro,
                codigo: codigo,
                nombre: nombre,
                tipoUbicacion: tipoUbicacion,
                parentId: parentId,
                sucursalId: sucursalId,
                servicioId: servicioId,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          $$UbicacionTableReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: ({
            parentId = false,
            sucursalId = false,
            servicioId = false,
          }) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                T extends TableManagerState<
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic
                >
              >(state) {
                if (parentId) {
                  state =
                      state.withJoin(
                            currentTable: table,
                            currentColumn: table.parentId,
                            referencedTable: $$UbicacionTableReferences
                                ._parentIdTable(db),
                            referencedColumn:
                                $$UbicacionTableReferences
                                    ._parentIdTable(db)
                                    .id,
                          )
                          as T;
                }
                if (sucursalId) {
                  state =
                      state.withJoin(
                            currentTable: table,
                            currentColumn: table.sucursalId,
                            referencedTable: $$UbicacionTableReferences
                                ._sucursalIdTable(db),
                            referencedColumn:
                                $$UbicacionTableReferences
                                    ._sucursalIdTable(db)
                                    .id,
                          )
                          as T;
                }
                if (servicioId) {
                  state =
                      state.withJoin(
                            currentTable: table,
                            currentColumn: table.servicioId,
                            referencedTable: $$UbicacionTableReferences
                                ._servicioIdTable(db),
                            referencedColumn:
                                $$UbicacionTableReferences
                                    ._servicioIdTable(db)
                                    .id,
                          )
                          as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$UbicacionTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $UbicacionTable,
      UbicacionData,
      $$UbicacionTableFilterComposer,
      $$UbicacionTableOrderingComposer,
      $$UbicacionTableAnnotationComposer,
      $$UbicacionTableCreateCompanionBuilder,
      $$UbicacionTableUpdateCompanionBuilder,
      (UbicacionData, $$UbicacionTableReferences),
      UbicacionData,
      PrefetchHooks Function({bool parentId, bool sucursalId, bool servicioId})
    >;
typedef $$PuestoTableCreateCompanionBuilder =
    PuestoCompanion Function({
      Value<String> id,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<String> cicloVidaRegistro,
      required String codigo,
      required String nombre,
      required String areaId,
      required String tipo,
      Value<String?> descripcion,
      required int nivelJerarquico,
      Value<int> rowid,
    });
typedef $$PuestoTableUpdateCompanionBuilder =
    PuestoCompanion Function({
      Value<String> id,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<String> cicloVidaRegistro,
      Value<String> codigo,
      Value<String> nombre,
      Value<String> areaId,
      Value<String> tipo,
      Value<String?> descripcion,
      Value<int> nivelJerarquico,
      Value<int> rowid,
    });

final class $$PuestoTableReferences
    extends BaseReferences<_$AppDatabase, $PuestoTable, PuestoData> {
  $$PuestoTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $AreaTable _areaIdTable(_$AppDatabase db) =>
      db.area.createAlias($_aliasNameGenerator(db.puesto.areaId, db.area.id));

  $$AreaTableProcessedTableManager get areaId {
    final $_column = $_itemColumn<String>('area_id')!;

    final manager = $$AreaTableTableManager(
      $_db,
      $_db.area,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_areaIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$PuestoTableFilterComposer
    extends Composer<_$AppDatabase, $PuestoTable> {
  $$PuestoTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cicloVidaRegistro => $composableBuilder(
    column: $table.cicloVidaRegistro,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get codigo => $composableBuilder(
    column: $table.codigo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nombre => $composableBuilder(
    column: $table.nombre,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tipo => $composableBuilder(
    column: $table.tipo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get descripcion => $composableBuilder(
    column: $table.descripcion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get nivelJerarquico => $composableBuilder(
    column: $table.nivelJerarquico,
    builder: (column) => ColumnFilters(column),
  );

  $$AreaTableFilterComposer get areaId {
    final $$AreaTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.areaId,
      referencedTable: $db.area,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AreaTableFilterComposer(
            $db: $db,
            $table: $db.area,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PuestoTableOrderingComposer
    extends Composer<_$AppDatabase, $PuestoTable> {
  $$PuestoTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cicloVidaRegistro => $composableBuilder(
    column: $table.cicloVidaRegistro,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get codigo => $composableBuilder(
    column: $table.codigo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nombre => $composableBuilder(
    column: $table.nombre,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tipo => $composableBuilder(
    column: $table.tipo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get descripcion => $composableBuilder(
    column: $table.descripcion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get nivelJerarquico => $composableBuilder(
    column: $table.nivelJerarquico,
    builder: (column) => ColumnOrderings(column),
  );

  $$AreaTableOrderingComposer get areaId {
    final $$AreaTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.areaId,
      referencedTable: $db.area,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AreaTableOrderingComposer(
            $db: $db,
            $table: $db.area,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PuestoTableAnnotationComposer
    extends Composer<_$AppDatabase, $PuestoTable> {
  $$PuestoTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get cicloVidaRegistro => $composableBuilder(
    column: $table.cicloVidaRegistro,
    builder: (column) => column,
  );

  GeneratedColumn<String> get codigo =>
      $composableBuilder(column: $table.codigo, builder: (column) => column);

  GeneratedColumn<String> get nombre =>
      $composableBuilder(column: $table.nombre, builder: (column) => column);

  GeneratedColumn<String> get tipo =>
      $composableBuilder(column: $table.tipo, builder: (column) => column);

  GeneratedColumn<String> get descripcion => $composableBuilder(
    column: $table.descripcion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get nivelJerarquico => $composableBuilder(
    column: $table.nivelJerarquico,
    builder: (column) => column,
  );

  $$AreaTableAnnotationComposer get areaId {
    final $$AreaTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.areaId,
      referencedTable: $db.area,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AreaTableAnnotationComposer(
            $db: $db,
            $table: $db.area,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PuestoTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PuestoTable,
          PuestoData,
          $$PuestoTableFilterComposer,
          $$PuestoTableOrderingComposer,
          $$PuestoTableAnnotationComposer,
          $$PuestoTableCreateCompanionBuilder,
          $$PuestoTableUpdateCompanionBuilder,
          (PuestoData, $$PuestoTableReferences),
          PuestoData,
          PrefetchHooks Function({bool areaId})
        > {
  $$PuestoTableTableManager(_$AppDatabase db, $PuestoTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$PuestoTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$PuestoTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$PuestoTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> cicloVidaRegistro = const Value.absent(),
                Value<String> codigo = const Value.absent(),
                Value<String> nombre = const Value.absent(),
                Value<String> areaId = const Value.absent(),
                Value<String> tipo = const Value.absent(),
                Value<String?> descripcion = const Value.absent(),
                Value<int> nivelJerarquico = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PuestoCompanion(
                id: id,
                createdAt: createdAt,
                updatedAt: updatedAt,
                cicloVidaRegistro: cicloVidaRegistro,
                codigo: codigo,
                nombre: nombre,
                areaId: areaId,
                tipo: tipo,
                descripcion: descripcion,
                nivelJerarquico: nivelJerarquico,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> cicloVidaRegistro = const Value.absent(),
                required String codigo,
                required String nombre,
                required String areaId,
                required String tipo,
                Value<String?> descripcion = const Value.absent(),
                required int nivelJerarquico,
                Value<int> rowid = const Value.absent(),
              }) => PuestoCompanion.insert(
                id: id,
                createdAt: createdAt,
                updatedAt: updatedAt,
                cicloVidaRegistro: cicloVidaRegistro,
                codigo: codigo,
                nombre: nombre,
                areaId: areaId,
                tipo: tipo,
                descripcion: descripcion,
                nivelJerarquico: nivelJerarquico,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          $$PuestoTableReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: ({areaId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                T extends TableManagerState<
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic
                >
              >(state) {
                if (areaId) {
                  state =
                      state.withJoin(
                            currentTable: table,
                            currentColumn: table.areaId,
                            referencedTable: $$PuestoTableReferences
                                ._areaIdTable(db),
                            referencedColumn:
                                $$PuestoTableReferences._areaIdTable(db).id,
                          )
                          as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$PuestoTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PuestoTable,
      PuestoData,
      $$PuestoTableFilterComposer,
      $$PuestoTableOrderingComposer,
      $$PuestoTableAnnotationComposer,
      $$PuestoTableCreateCompanionBuilder,
      $$PuestoTableUpdateCompanionBuilder,
      (PuestoData, $$PuestoTableReferences),
      PuestoData,
      PrefetchHooks Function({bool areaId})
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$AppMetadataTableTableManager get appMetadata =>
      $$AppMetadataTableTableManager(_db, _db.appMetadata);
  $$CodigoSecuenciaTableTableManager get codigoSecuencia =>
      $$CodigoSecuenciaTableTableManager(_db, _db.codigoSecuencia);
  $$TipoSucursalTableTableManager get tipoSucursal =>
      $$TipoSucursalTableTableManager(_db, _db.tipoSucursal);
  $$IndustriaTableTableManager get industria =>
      $$IndustriaTableTableManager(_db, _db.industria);
  $$TipoServicioTableTableManager get tipoServicio =>
      $$TipoServicioTableTableManager(_db, _db.tipoServicio);
  $$AreaTableTableManager get area => $$AreaTableTableManager(_db, _db.area);
  $$DireccionTableTableManager get direccion =>
      $$DireccionTableTableManager(_db, _db.direccion);
  $$MedioContactoTableTableManager get medioContacto =>
      $$MedioContactoTableTableManager(_db, _db.medioContacto);
  $$AttachmentTableTableManager get attachment =>
      $$AttachmentTableTableManager(_db, _db.attachment);
  $$HorarioTableTableManager get horario =>
      $$HorarioTableTableManager(_db, _db.horario);
  $$HorarioDetalleTableTableManager get horarioDetalle =>
      $$HorarioDetalleTableTableManager(_db, _db.horarioDetalle);
  $$EmpresaTableTableManager get empresa =>
      $$EmpresaTableTableManager(_db, _db.empresa);
  $$SucursalTableTableManager get sucursal =>
      $$SucursalTableTableManager(_db, _db.sucursal);
  $$ClienteTableTableManager get cliente =>
      $$ClienteTableTableManager(_db, _db.cliente);
  $$ContactoTableTableManager get contacto =>
      $$ContactoTableTableManager(_db, _db.contacto);
  $$ServicioTableTableManager get servicio =>
      $$ServicioTableTableManager(_db, _db.servicio);
  $$UbicacionTableTableManager get ubicacion =>
      $$UbicacionTableTableManager(_db, _db.ubicacion);
  $$PuestoTableTableManager get puesto =>
      $$PuestoTableTableManager(_db, _db.puesto);
}
