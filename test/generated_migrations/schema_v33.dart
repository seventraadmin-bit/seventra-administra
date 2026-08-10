// dart format width=80
// GENERATED CODE, DO NOT EDIT BY HAND.
// ignore_for_file: type=lint
import 'package:drift/drift.dart';

class AppMetadata extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  AppMetadata(this.attachedDatabase, [this._alias]);
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
  late final GeneratedColumn<String> installationId = GeneratedColumn<String>(
    'installation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<DateTime> installedAt = GeneratedColumn<DateTime>(
    'installed_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<DateTime> lastOpenedAt = GeneratedColumn<DateTime>(
    'last_opened_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
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
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  AppMetadata createAlias(String alias) {
    return AppMetadata(attachedDatabase, alias);
  }
}

class CodigoSecuencia extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  CodigoSecuencia(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
    'entity_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> prefijo = GeneratedColumn<String>(
    'prefijo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<int> digitos = GeneratedColumn<int>(
    'digitos',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
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
  late final GeneratedColumn<int> anioActual = GeneratedColumn<int>(
    'anio_actual',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
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
  Set<GeneratedColumn> get $primaryKey => {entityType};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  CodigoSecuencia createAlias(String alias) {
    return CodigoSecuencia(attachedDatabase, alias);
  }
}

class TipoSucursal extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  TipoSucursal(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> codigo = GeneratedColumn<String>(
    'codigo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> nombre = GeneratedColumn<String>(
    'nombre',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> descripcion = GeneratedColumn<String>(
    'descripcion',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
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
  late final GeneratedColumn<int> orden = GeneratedColumn<int>(
    'orden',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
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
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  TipoSucursal createAlias(String alias) {
    return TipoSucursal(attachedDatabase, alias);
  }
}

class Industria extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Industria(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> codigo = GeneratedColumn<String>(
    'codigo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> nombre = GeneratedColumn<String>(
    'nombre',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> descripcion = GeneratedColumn<String>(
    'descripcion',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
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
  late final GeneratedColumn<int> orden = GeneratedColumn<int>(
    'orden',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
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
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  Industria createAlias(String alias) {
    return Industria(attachedDatabase, alias);
  }
}

class TipoServicio extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  TipoServicio(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> codigo = GeneratedColumn<String>(
    'codigo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> nombre = GeneratedColumn<String>(
    'nombre',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> descripcion = GeneratedColumn<String>(
    'descripcion',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
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
  late final GeneratedColumn<int> orden = GeneratedColumn<int>(
    'orden',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
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
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  TipoServicio createAlias(String alias) {
    return TipoServicio(attachedDatabase, alias);
  }
}

class Area extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Area(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> codigo = GeneratedColumn<String>(
    'codigo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> nombre = GeneratedColumn<String>(
    'nombre',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> descripcion = GeneratedColumn<String>(
    'descripcion',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
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
  late final GeneratedColumn<int> orden = GeneratedColumn<int>(
    'orden',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
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
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  Area createAlias(String alias) {
    return Area(attachedDatabase, alias);
  }
}

class TipoModalidadTurno extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  TipoModalidadTurno(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> codigo = GeneratedColumn<String>(
    'codigo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> nombre = GeneratedColumn<String>(
    'nombre',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> descripcion = GeneratedColumn<String>(
    'descripcion',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
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
  late final GeneratedColumn<int> orden = GeneratedColumn<int>(
    'orden',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
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
  static const String $name = 'tipo_modalidad_turno';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  TipoModalidadTurno createAlias(String alias) {
    return TipoModalidadTurno(attachedDatabase, alias);
  }
}

class TipoFrecuenciaCobro extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  TipoFrecuenciaCobro(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> codigo = GeneratedColumn<String>(
    'codigo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> nombre = GeneratedColumn<String>(
    'nombre',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> descripcion = GeneratedColumn<String>(
    'descripcion',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
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
  late final GeneratedColumn<int> orden = GeneratedColumn<int>(
    'orden',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
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
  static const String $name = 'tipo_frecuencia_cobro';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  TipoFrecuenciaCobro createAlias(String alias) {
    return TipoFrecuenciaCobro(attachedDatabase, alias);
  }
}

class Banco extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Banco(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> codigo = GeneratedColumn<String>(
    'codigo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> nombre = GeneratedColumn<String>(
    'nombre',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> descripcion = GeneratedColumn<String>(
    'descripcion',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
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
  late final GeneratedColumn<int> orden = GeneratedColumn<int>(
    'orden',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
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
  static const String $name = 'banco';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  Banco createAlias(String alias) {
    return Banco(attachedDatabase, alias);
  }
}

class Direccion extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Direccion(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<String> cicloVidaRegistro =
      GeneratedColumn<String>(
        'ciclo_vida_registro',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('activo'),
      );
  late final GeneratedColumn<String> empresaId = GeneratedColumn<String>(
    'empresa_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  late final GeneratedColumn<String> sucursalId = GeneratedColumn<String>(
    'sucursal_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  late final GeneratedColumn<String> clienteId = GeneratedColumn<String>(
    'cliente_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> servicioId = GeneratedColumn<String>(
    'servicio_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  late final GeneratedColumn<String> entidadFiscalId = GeneratedColumn<String>(
    'entidad_fiscal_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  late final GeneratedColumn<String> empleadoId = GeneratedColumn<String>(
    'empleado_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  late final GeneratedColumn<String> tipoDireccion = GeneratedColumn<String>(
    'tipo_direccion',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
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
  late final GeneratedColumn<String> calle = GeneratedColumn<String>(
    'calle',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> numeroExterior = GeneratedColumn<String>(
    'numero_exterior',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> numeroInterior = GeneratedColumn<String>(
    'numero_interior',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> colonia = GeneratedColumn<String>(
    'colonia',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> municipioAlcaldia =
      GeneratedColumn<String>(
        'municipio_alcaldia',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  late final GeneratedColumn<String> ciudadLocalidad = GeneratedColumn<String>(
    'ciudad_localidad',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> estado = GeneratedColumn<String>(
    'estado',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> codigoPostal = GeneratedColumn<String>(
    'codigo_postal',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> pais = GeneratedColumn<String>(
    'pais',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('México'),
  );
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
    entidadFiscalId,
    empleadoId,
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
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  Direccion createAlias(String alias) {
    return Direccion(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'FOREIGN KEY (empresa_id) REFERENCES empresa (id) ON DELETE RESTRICT',
    'FOREIGN KEY (sucursal_id) REFERENCES sucursal (id) ON DELETE RESTRICT',
    'FOREIGN KEY (cliente_id) REFERENCES cliente (id) ON DELETE RESTRICT',
    'FOREIGN KEY (servicio_id) REFERENCES servicio (id) ON DELETE RESTRICT',
    'FOREIGN KEY (entidad_fiscal_id) REFERENCES entidad_fiscal (id) ON DELETE RESTRICT',
    'FOREIGN KEY (empleado_id) REFERENCES empleado (id) ON DELETE RESTRICT',
    'CHECK ((CASE WHEN empresa_id IS NOT NULL THEN 1 ELSE 0 END + CASE WHEN sucursal_id IS NOT NULL THEN 1 ELSE 0 END + CASE WHEN cliente_id IS NOT NULL THEN 1 ELSE 0 END + CASE WHEN servicio_id IS NOT NULL THEN 1 ELSE 0 END + CASE WHEN entidad_fiscal_id IS NOT NULL THEN 1 ELSE 0 END + CASE WHEN empleado_id IS NOT NULL THEN 1 ELSE 0 END) = 1)',
    'CHECK (empresa_id IS NULL OR tipo_direccion = \'fiscal\')',
    'CHECK (servicio_id IS NULL OR tipo_direccion = \'operativa\')',
    'CHECK (sucursal_id IS NULL OR tipo_direccion IN (\'administrativa\', \'operativa\'))',
    'CHECK (entidad_fiscal_id IS NULL OR tipo_direccion = \'fiscal\')',
    'CHECK (empleado_id IS NULL OR tipo_direccion = \'domicilio\')',
  ];
}

class MedioContacto extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  MedioContacto(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<String> cicloVidaRegistro =
      GeneratedColumn<String>(
        'ciclo_vida_registro',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('activo'),
      );
  late final GeneratedColumn<String> empresaId = GeneratedColumn<String>(
    'empresa_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> sucursalId = GeneratedColumn<String>(
    'sucursal_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> telefono = GeneratedColumn<String>(
    'telefono',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> correo = GeneratedColumn<String>(
    'correo',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> sitioWeb = GeneratedColumn<String>(
    'sitio_web',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
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
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  MedioContacto createAlias(String alias) {
    return MedioContacto(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'FOREIGN KEY (empresa_id) REFERENCES empresa (id) ON DELETE RESTRICT',
    'FOREIGN KEY (sucursal_id) REFERENCES sucursal (id) ON DELETE RESTRICT',
    'CHECK ((CASE WHEN empresa_id IS NOT NULL THEN 1 ELSE 0 END + CASE WHEN sucursal_id IS NOT NULL THEN 1 ELSE 0 END) = 1)',
  ];
}

class Attachment extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Attachment(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> categoria = GeneratedColumn<String>(
    'categoria',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> originalFileName = GeneratedColumn<String>(
    'original_file_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> storedFileName = GeneratedColumn<String>(
    'stored_file_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> mimeType = GeneratedColumn<String>(
    'mime_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<int> sizeBytes = GeneratedColumn<int>(
    'size_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> hash = GeneratedColumn<String>(
    'hash',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> estado = GeneratedColumn<String>(
    'estado',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('activo'),
  );
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
    categoria,
    originalFileName,
    storedFileName,
    path,
    mimeType,
    sizeBytes,
    hash,
    estado,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'attachment';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  Attachment createAlias(String alias) {
    return Attachment(attachedDatabase, alias);
  }
}

class Horario extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Horario(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<String> cicloVidaRegistro =
      GeneratedColumn<String>(
        'ciclo_vida_registro',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('activo'),
      );
  late final GeneratedColumn<String> sucursalId = GeneratedColumn<String>(
    'sucursal_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
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
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  Horario createAlias(String alias) {
    return Horario(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'FOREIGN KEY (sucursal_id) REFERENCES sucursal (id) ON DELETE RESTRICT',
    'FOREIGN KEY (servicio_id) REFERENCES servicio (id) ON DELETE RESTRICT',
    'CHECK ((CASE WHEN sucursal_id IS NOT NULL THEN 1 ELSE 0 END + CASE WHEN servicio_id IS NOT NULL THEN 1 ELSE 0 END) = 1)',
  ];
}

class HorarioDetalle extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  HorarioDetalle(this.attachedDatabase, [this._alias]);
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
  late final GeneratedColumn<int> diaSemana = GeneratedColumn<int>(
    'dia_semana',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<int> horaInicio = GeneratedColumn<int>(
    'hora_inicio',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<int> horaFin = GeneratedColumn<int>(
    'hora_fin',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
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
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  HorarioDetalle createAlias(String alias) {
    return HorarioDetalle(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'CHECK (dia_semana BETWEEN 0 AND 6)',
    'CHECK (hora_inicio BETWEEN 0 AND 1439)',
    'CHECK (hora_fin BETWEEN 0 AND 1439)',
  ];
}

class Empresa extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Empresa(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<String> cicloVidaRegistro =
      GeneratedColumn<String>(
        'ciclo_vida_registro',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('activo'),
      );
  late final GeneratedColumn<String> codigo = GeneratedColumn<String>(
    'codigo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  late final GeneratedColumn<String> razonSocial = GeneratedColumn<String>(
    'razon_social',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> nombreComercial = GeneratedColumn<String>(
    'nombre_comercial',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> rfc = GeneratedColumn<String>(
    'rfc',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  late final GeneratedColumn<String> representanteLegal =
      GeneratedColumn<String>(
        'representante_legal',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  late final GeneratedColumn<String> eslogan = GeneratedColumn<String>(
    'eslogan',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
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
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  Empresa createAlias(String alias) {
    return Empresa(attachedDatabase, alias);
  }
}

class Sucursal extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Sucursal(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<String> cicloVidaRegistro =
      GeneratedColumn<String>(
        'ciclo_vida_registro',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('activo'),
      );
  late final GeneratedColumn<String> codigo = GeneratedColumn<String>(
    'codigo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  late final GeneratedColumn<String> nombre = GeneratedColumn<String>(
    'nombre',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
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
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  Sucursal createAlias(String alias) {
    return Sucursal(attachedDatabase, alias);
  }
}

class Cliente extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Cliente(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<String> cicloVidaRegistro =
      GeneratedColumn<String>(
        'ciclo_vida_registro',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('activo'),
      );
  late final GeneratedColumn<String> codigo = GeneratedColumn<String>(
    'codigo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  late final GeneratedColumn<String> nombreComercial = GeneratedColumn<String>(
    'nombre_comercial',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
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
  late final GeneratedColumn<String> estatus = GeneratedColumn<String>(
    'estatus',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('prospecto'),
  );
  late final GeneratedColumn<DateTime> fechaAlta = GeneratedColumn<DateTime>(
    'fecha_alta',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
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
    nombreComercial,
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
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  Cliente createAlias(String alias) {
    return Cliente(attachedDatabase, alias);
  }
}

class Contacto extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Contacto(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<String> cicloVidaRegistro =
      GeneratedColumn<String>(
        'ciclo_vida_registro',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('activo'),
      );
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
  late final GeneratedColumn<String> nombre = GeneratedColumn<String>(
    'nombre',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> puesto = GeneratedColumn<String>(
    'puesto',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> telefono = GeneratedColumn<String>(
    'telefono',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> correo = GeneratedColumn<String>(
    'correo',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
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
  late final GeneratedColumn<String> tipo = GeneratedColumn<String>(
    'tipo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
    tipo,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'contacto';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  Contacto createAlias(String alias) {
    return Contacto(attachedDatabase, alias);
  }
}

class EntidadFiscal extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  EntidadFiscal(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<String> cicloVidaRegistro =
      GeneratedColumn<String>(
        'ciclo_vida_registro',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('activo'),
      );
  late final GeneratedColumn<String> codigo = GeneratedColumn<String>(
    'codigo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
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
  late final GeneratedColumn<String> razonSocial = GeneratedColumn<String>(
    'razon_social',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> rfc = GeneratedColumn<String>(
    'rfc',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    createdAt,
    updatedAt,
    cicloVidaRegistro,
    codigo,
    clienteId,
    razonSocial,
    rfc,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'entidad_fiscal';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  EntidadFiscal createAlias(String alias) {
    return EntidadFiscal(attachedDatabase, alias);
  }
}

class Servicio extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Servicio(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<String> cicloVidaRegistro =
      GeneratedColumn<String>(
        'ciclo_vida_registro',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('activo'),
      );
  late final GeneratedColumn<String> codigo = GeneratedColumn<String>(
    'codigo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
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
  late final GeneratedColumn<String> nombre = GeneratedColumn<String>(
    'nombre',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
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
  late final GeneratedColumn<String> sucursalAdministrativaId =
      GeneratedColumn<String>(
        'sucursal_administrativa_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES sucursal (id) ON DELETE RESTRICT',
        ),
      );
  late final GeneratedColumn<String> estatus = GeneratedColumn<String>(
    'estatus',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('cotizado'),
  );
  late final GeneratedColumn<DateTime> fechaInicio = GeneratedColumn<DateTime>(
    'fecha_inicio',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<DateTime> fechaTermino = GeneratedColumn<DateTime>(
    'fecha_termino',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<int> elementosAutorizados = GeneratedColumn<int>(
    'elementos_autorizados',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
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
  late final GeneratedColumn<String> observaciones = GeneratedColumn<String>(
    'observaciones',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> entidadFiscalId = GeneratedColumn<String>(
    'entidad_fiscal_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES entidad_fiscal (id) ON DELETE RESTRICT',
    ),
  );
  late final GeneratedColumn<String> responsableInterno =
      GeneratedColumn<String>(
        'responsable_interno',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  late final GeneratedColumn<String> referenciaComercial =
      GeneratedColumn<String>(
        'referencia_comercial',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  late final GeneratedColumn<String> referenciaContractual =
      GeneratedColumn<String>(
        'referencia_contractual',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  late final GeneratedColumn<int> sueldoMensualReferenciaPersonal =
      GeneratedColumn<int>(
        'sueldo_mensual_referencia_personal',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      );
  late final GeneratedColumn<int> bonoMensualReferenciaPersonal =
      GeneratedColumn<int>(
        'bono_mensual_referencia_personal',
        aliasedName,
        true,
        type: DriftSqlType.int,
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
    entidadFiscalId,
    responsableInterno,
    referenciaComercial,
    referenciaContractual,
    sueldoMensualReferenciaPersonal,
    bonoMensualReferenciaPersonal,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'servicio';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  Servicio createAlias(String alias) {
    return Servicio(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'CHECK (elementos_autorizados >= 0)',
    'CHECK (fecha_termino IS NULL OR fecha_termino >= fecha_inicio)',
    'CHECK (sueldo_mensual_referencia_personal IS NULL OR sueldo_mensual_referencia_personal > 0)',
    'CHECK (bono_mensual_referencia_personal IS NULL OR bono_mensual_referencia_personal >= 0)',
  ];
}

class Ubicacion extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Ubicacion(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<String> cicloVidaRegistro =
      GeneratedColumn<String>(
        'ciclo_vida_registro',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('activo'),
      );
  late final GeneratedColumn<String> codigo = GeneratedColumn<String>(
    'codigo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  late final GeneratedColumn<String> nombre = GeneratedColumn<String>(
    'nombre',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> tipoUbicacion = GeneratedColumn<String>(
    'tipo_ubicacion',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
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
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  Ubicacion createAlias(String alias) {
    return Ubicacion(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'CHECK (parent_id IS NULL OR parent_id != id)',
    'CHECK ((parent_id IS NULL AND ((sucursal_id IS NOT NULL AND servicio_id IS NULL) OR (sucursal_id IS NULL AND servicio_id IS NOT NULL))) OR (parent_id IS NOT NULL AND sucursal_id IS NULL AND servicio_id IS NULL))',
  ];
}

class Puesto extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Puesto(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<String> cicloVidaRegistro =
      GeneratedColumn<String>(
        'ciclo_vida_registro',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('activo'),
      );
  late final GeneratedColumn<String> codigo = GeneratedColumn<String>(
    'codigo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  late final GeneratedColumn<String> nombre = GeneratedColumn<String>(
    'nombre',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
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
  late final GeneratedColumn<String> tipo = GeneratedColumn<String>(
    'tipo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> descripcion = GeneratedColumn<String>(
    'descripcion',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
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
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  Puesto createAlias(String alias) {
    return Puesto(attachedDatabase, alias);
  }
}

class ServicioLineaComercial extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  ServicioLineaComercial(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<String> cicloVidaRegistro =
      GeneratedColumn<String>(
        'ciclo_vida_registro',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('activo'),
      );
  late final GeneratedColumn<String> servicioId = GeneratedColumn<String>(
    'servicio_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES servicio (id) ON DELETE RESTRICT',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    createdAt,
    updatedAt,
    cicloVidaRegistro,
    servicioId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'servicio_linea_comercial';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  ServicioLineaComercial createAlias(String alias) {
    return ServicioLineaComercial(attachedDatabase, alias);
  }
}

class ServicioLineaComercialVigencia extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  ServicioLineaComercialVigencia(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<String> cicloVidaRegistro =
      GeneratedColumn<String>(
        'ciclo_vida_registro',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('activo'),
      );
  late final GeneratedColumn<String> lineaComercialId = GeneratedColumn<String>(
    'linea_comercial_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES servicio_linea_comercial (id) ON DELETE RESTRICT',
    ),
  );
  late final GeneratedColumn<String> puestoId = GeneratedColumn<String>(
    'puesto_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES puesto (id) ON DELETE RESTRICT',
    ),
  );
  late final GeneratedColumn<String> modalidadTurnoId = GeneratedColumn<String>(
    'modalidad_turno_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES tipo_modalidad_turno (id) ON DELETE RESTRICT',
    ),
  );
  late final GeneratedColumn<int> cantidadElementos = GeneratedColumn<int>(
    'cantidad_elementos',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<int> precioUnitario = GeneratedColumn<int>(
    'precio_unitario',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> tratamientoIva = GeneratedColumn<String>(
    'tratamiento_iva',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> descripcion = GeneratedColumn<String>(
    'descripcion',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<DateTime> fechaInicioVigencia =
      GeneratedColumn<DateTime>(
        'fecha_inicio_vigencia',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  late final GeneratedColumn<DateTime> fechaFinVigencia =
      GeneratedColumn<DateTime>(
        'fecha_fin_vigencia',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
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
    lineaComercialId,
    puestoId,
    modalidadTurnoId,
    cantidadElementos,
    precioUnitario,
    tratamientoIva,
    descripcion,
    fechaInicioVigencia,
    fechaFinVigencia,
    observaciones,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'servicio_linea_comercial_vigencia';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  ServicioLineaComercialVigencia createAlias(String alias) {
    return ServicioLineaComercialVigencia(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'CHECK (cantidad_elementos > 0)',
    'CHECK (precio_unitario > 0)',
    'CHECK (fecha_fin_vigencia IS NULL OR fecha_fin_vigencia >= fecha_inicio_vigencia)',
  ];
}

class ConfiguracionCobro extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  ConfiguracionCobro(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<String> cicloVidaRegistro =
      GeneratedColumn<String>(
        'ciclo_vida_registro',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('activo'),
      );
  late final GeneratedColumn<String> servicioId = GeneratedColumn<String>(
    'servicio_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
    servicioId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'configuracion_cobro';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  ConfiguracionCobro createAlias(String alias) {
    return ConfiguracionCobro(attachedDatabase, alias);
  }
}

class ConfiguracionCobroVigencia extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  ConfiguracionCobroVigencia(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<String> cicloVidaRegistro =
      GeneratedColumn<String>(
        'ciclo_vida_registro',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('activo'),
      );
  late final GeneratedColumn<String> configuracionCobroId =
      GeneratedColumn<String>(
        'configuracion_cobro_id',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES configuracion_cobro (id) ON DELETE RESTRICT',
        ),
      );
  late final GeneratedColumn<String> tipoDocumento = GeneratedColumn<String>(
    'tipo_documento',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> frecuenciaId = GeneratedColumn<String>(
    'frecuencia_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES tipo_frecuencia_cobro (id) ON DELETE RESTRICT',
    ),
  );
  late final GeneratedColumn<int> diaInicioPeriodo = GeneratedColumn<int>(
    'dia_inicio_periodo',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> agrupacion = GeneratedColumn<String>(
    'agrupacion',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> metodo = GeneratedColumn<String>(
    'metodo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<bool> requiereComplemento = GeneratedColumn<bool>(
    'requiere_complemento',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("requiere_complemento" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  late final GeneratedColumn<String> entidadFiscalId = GeneratedColumn<String>(
    'entidad_fiscal_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES entidad_fiscal (id) ON DELETE RESTRICT',
    ),
  );
  late final GeneratedColumn<String> portalNombre = GeneratedColumn<String>(
    'portal_nombre',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> portalUrl = GeneratedColumn<String>(
    'portal_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> portalUsuario = GeneratedColumn<String>(
    'portal_usuario',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> portalContrasena = GeneratedColumn<String>(
    'portal_contrasena',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> portalObservaciones =
      GeneratedColumn<String>(
        'portal_observaciones',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  late final GeneratedColumn<String> cuentaBancaria = GeneratedColumn<String>(
    'cuenta_bancaria',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> observaciones = GeneratedColumn<String>(
    'observaciones',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<DateTime> fechaInicioVigencia =
      GeneratedColumn<DateTime>(
        'fecha_inicio_vigencia',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  late final GeneratedColumn<DateTime> fechaFinVigencia =
      GeneratedColumn<DateTime>(
        'fecha_fin_vigencia',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    createdAt,
    updatedAt,
    cicloVidaRegistro,
    configuracionCobroId,
    tipoDocumento,
    frecuenciaId,
    diaInicioPeriodo,
    agrupacion,
    metodo,
    requiereComplemento,
    entidadFiscalId,
    portalNombre,
    portalUrl,
    portalUsuario,
    portalContrasena,
    portalObservaciones,
    cuentaBancaria,
    observaciones,
    fechaInicioVigencia,
    fechaFinVigencia,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'configuracion_cobro_vigencia';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  ConfiguracionCobroVigencia createAlias(String alias) {
    return ConfiguracionCobroVigencia(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'CHECK (dia_inicio_periodo BETWEEN 1 AND 31)',
    'CHECK (fecha_fin_vigencia IS NULL OR fecha_fin_vigencia >= fecha_inicio_vigencia)',
  ];
}

class ConfiguracionCobroCorreo extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  ConfiguracionCobroCorreo(this.attachedDatabase, [this._alias]);
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
  late final GeneratedColumn<String> configuracionCobroVigenciaId =
      GeneratedColumn<String>(
        'configuracion_cobro_vigencia_id',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES configuracion_cobro_vigencia (id) ON DELETE CASCADE',
        ),
      );
  late final GeneratedColumn<String> correo = GeneratedColumn<String>(
    'correo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    configuracionCobroVigenciaId,
    correo,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'configuracion_cobro_correo';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  ConfiguracionCobroCorreo createAlias(String alias) {
    return ConfiguracionCobroCorreo(attachedDatabase, alias);
  }
}

class ConfiguracionCobroReglaEvento extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  ConfiguracionCobroReglaEvento(this.attachedDatabase, [this._alias]);
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
  late final GeneratedColumn<String> configuracionCobroVigenciaId =
      GeneratedColumn<String>(
        'configuracion_cobro_vigencia_id',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES configuracion_cobro_vigencia (id) ON DELETE CASCADE',
        ),
      );
  late final GeneratedColumn<String> tipoEvento = GeneratedColumn<String>(
    'tipo_evento',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> tipoRegla = GeneratedColumn<String>(
    'tipo_regla',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> mesRelativo = GeneratedColumn<String>(
    'mes_relativo',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<int> diaDelMes = GeneratedColumn<int>(
    'dia_del_mes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> ordinalSemana = GeneratedColumn<String>(
    'ordinal_semana',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> diaSemana = GeneratedColumn<String>(
    'dia_semana',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<int> offsetDiasHabiles = GeneratedColumn<int>(
    'offset_dias_habiles',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> eventoReferencia = GeneratedColumn<String>(
    'evento_referencia',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    configuracionCobroVigenciaId,
    tipoEvento,
    tipoRegla,
    mesRelativo,
    diaDelMes,
    ordinalSemana,
    diaSemana,
    offsetDiasHabiles,
    eventoReferencia,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'configuracion_cobro_regla_evento';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  ConfiguracionCobroReglaEvento createAlias(String alias) {
    return ConfiguracionCobroReglaEvento(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'UNIQUE (configuracion_cobro_vigencia_id, tipo_evento)',
    'CHECK (dia_del_mes IS NULL OR dia_del_mes BETWEEN 1 AND 31)',
  ];
}

class DocumentoPorEmitir extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  DocumentoPorEmitir(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<String> cicloVidaRegistro =
      GeneratedColumn<String>(
        'ciclo_vida_registro',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('activo'),
      );
  late final GeneratedColumn<String> codigo = GeneratedColumn<String>(
    'codigo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
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
  late final GeneratedColumn<String> entidadFiscalId = GeneratedColumn<String>(
    'entidad_fiscal_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES entidad_fiscal (id) ON DELETE RESTRICT',
    ),
  );
  late final GeneratedColumn<String> tipoDocumento = GeneratedColumn<String>(
    'tipo_documento',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> agrupacion = GeneratedColumn<String>(
    'agrupacion',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> metodo = GeneratedColumn<String>(
    'metodo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<bool> requiereComplemento = GeneratedColumn<bool>(
    'requiere_complemento',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("requiere_complemento" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  late final GeneratedColumn<DateTime> periodoInicio =
      GeneratedColumn<DateTime>(
        'periodo_inicio',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  late final GeneratedColumn<DateTime> periodoFin = GeneratedColumn<DateTime>(
    'periodo_fin',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<DateTime> fechaEmisionProgramada =
      GeneratedColumn<DateTime>(
        'fecha_emision_programada',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  late final GeneratedColumn<DateTime> fechaProcesamientoProgramada =
      GeneratedColumn<DateTime>(
        'fecha_procesamiento_programada',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  late final GeneratedColumn<DateTime> fechaPagoEsperadoProgramada =
      GeneratedColumn<DateTime>(
        'fecha_pago_esperado_programada',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  late final GeneratedColumn<String> generationKey = GeneratedColumn<String>(
    'generation_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  late final GeneratedColumn<int> importeBaseEsperado = GeneratedColumn<int>(
    'importe_base_esperado',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<int> ajusteManual = GeneratedColumn<int>(
    'ajuste_manual',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> motivoAjuste = GeneratedColumn<String>(
    'motivo_ajuste',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<int> importeFinalEsperado = GeneratedColumn<int>(
    'importe_final_esperado',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> estatus = GeneratedColumn<String>(
    'estatus',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pendiente'),
  );
  late final GeneratedColumn<String> motivoEstatus = GeneratedColumn<String>(
    'motivo_estatus',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> observaciones = GeneratedColumn<String>(
    'observaciones',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> folioDocumento = GeneratedColumn<String>(
    'folio_documento',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> serieFiscal = GeneratedColumn<String>(
    'serie_fiscal',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> folioFiscal = GeneratedColumn<String>(
    'folio_fiscal',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> uuid = GeneratedColumn<String>(
    'uuid',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<DateTime> fechaEmisionReal =
      GeneratedColumn<DateTime>(
        'fecha_emision_real',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  late final GeneratedColumn<int> importeEmitido = GeneratedColumn<int>(
    'importe_emitido',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> observacionesEmision =
      GeneratedColumn<String>(
        'observaciones_emision',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  late final GeneratedColumn<DateTime> fechaEnvio = GeneratedColumn<DateTime>(
    'fecha_envio',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> observacionesEnvio =
      GeneratedColumn<String>(
        'observaciones_envio',
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
    entidadFiscalId,
    tipoDocumento,
    agrupacion,
    metodo,
    requiereComplemento,
    periodoInicio,
    periodoFin,
    fechaEmisionProgramada,
    fechaProcesamientoProgramada,
    fechaPagoEsperadoProgramada,
    generationKey,
    importeBaseEsperado,
    ajusteManual,
    motivoAjuste,
    importeFinalEsperado,
    estatus,
    motivoEstatus,
    observaciones,
    folioDocumento,
    serieFiscal,
    folioFiscal,
    uuid,
    fechaEmisionReal,
    importeEmitido,
    observacionesEmision,
    fechaEnvio,
    observacionesEnvio,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'documento_por_emitir';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  DocumentoPorEmitir createAlias(String alias) {
    return DocumentoPorEmitir(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'CHECK (periodo_fin >= periodo_inicio)',
    'CHECK (importe_base_esperado >= 0)',
    'CHECK (importe_final_esperado >= 0)',
    'CHECK (importe_emitido IS NULL OR importe_emitido >= 0)',
  ];
}

class DocumentoPorEmitirServicio extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  DocumentoPorEmitirServicio(this.attachedDatabase, [this._alias]);
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
  late final GeneratedColumn<String> documentoPorEmitirId =
      GeneratedColumn<String>(
        'documento_por_emitir_id',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES documento_por_emitir (id) ON DELETE CASCADE',
        ),
      );
  late final GeneratedColumn<String> servicioId = GeneratedColumn<String>(
    'servicio_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES servicio (id) ON DELETE RESTRICT',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [id, documentoPorEmitirId, servicioId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'documento_por_emitir_servicio';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  DocumentoPorEmitirServicio createAlias(String alias) {
    return DocumentoPorEmitirServicio(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'UNIQUE (documento_por_emitir_id, servicio_id)',
  ];
}

class DocumentoPorEmitirConfiguracion extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  DocumentoPorEmitirConfiguracion(this.attachedDatabase, [this._alias]);
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
  late final GeneratedColumn<String> documentoPorEmitirId =
      GeneratedColumn<String>(
        'documento_por_emitir_id',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES documento_por_emitir (id) ON DELETE CASCADE',
        ),
      );
  late final GeneratedColumn<String> servicioId = GeneratedColumn<String>(
    'servicio_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES servicio (id) ON DELETE RESTRICT',
    ),
  );
  late final GeneratedColumn<String> configuracionCobroVigenciaId =
      GeneratedColumn<String>(
        'configuracion_cobro_vigencia_id',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES configuracion_cobro_vigencia (id) ON DELETE RESTRICT',
        ),
      );
  late final GeneratedColumn<DateTime> fechaEmisionProgramada =
      GeneratedColumn<DateTime>(
        'fecha_emision_programada',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  late final GeneratedColumn<DateTime> fechaProcesamientoProgramada =
      GeneratedColumn<DateTime>(
        'fecha_procesamiento_programada',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  late final GeneratedColumn<DateTime> fechaPagoEsperadoProgramada =
      GeneratedColumn<DateTime>(
        'fecha_pago_esperado_programada',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    documentoPorEmitirId,
    servicioId,
    configuracionCobroVigenciaId,
    fechaEmisionProgramada,
    fechaProcesamientoProgramada,
    fechaPagoEsperadoProgramada,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'documento_por_emitir_configuracion';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  DocumentoPorEmitirConfiguracion createAlias(String alias) {
    return DocumentoPorEmitirConfiguracion(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'UNIQUE (documento_por_emitir_id, servicio_id)',
  ];
}

class DocumentoPorEmitirLinea extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  DocumentoPorEmitirLinea(this.attachedDatabase, [this._alias]);
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
  late final GeneratedColumn<String> documentoPorEmitirId =
      GeneratedColumn<String>(
        'documento_por_emitir_id',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES documento_por_emitir (id) ON DELETE CASCADE',
        ),
      );
  late final GeneratedColumn<String> servicioId = GeneratedColumn<String>(
    'servicio_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES servicio (id) ON DELETE RESTRICT',
    ),
  );
  late final GeneratedColumn<String>
  lineaComercialVigenciaId = GeneratedColumn<String>(
    'linea_comercial_vigencia_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES servicio_linea_comercial_vigencia (id) ON DELETE RESTRICT',
    ),
  );
  late final GeneratedColumn<String> puestoNombre = GeneratedColumn<String>(
    'puesto_nombre',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> modalidadTurnoNombre =
      GeneratedColumn<String>(
        'modalidad_turno_nombre',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  late final GeneratedColumn<int> cantidadElementos = GeneratedColumn<int>(
    'cantidad_elementos',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<int> precioUnitario = GeneratedColumn<int>(
    'precio_unitario',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> tratamientoIva = GeneratedColumn<String>(
    'tratamiento_iva',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<int> diasAplicables = GeneratedColumn<int>(
    'dias_aplicables',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<int> subtotalProporcional = GeneratedColumn<int>(
    'subtotal_proporcional',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    documentoPorEmitirId,
    servicioId,
    lineaComercialVigenciaId,
    puestoNombre,
    modalidadTurnoNombre,
    cantidadElementos,
    precioUnitario,
    tratamientoIva,
    diasAplicables,
    subtotalProporcional,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'documento_por_emitir_linea';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  DocumentoPorEmitirLinea createAlias(String alias) {
    return DocumentoPorEmitirLinea(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'CHECK (cantidad_elementos > 0)',
    'CHECK (precio_unitario > 0)',
    'CHECK (dias_aplicables > 0)',
    'CHECK (subtotal_proporcional >= 0)',
  ];
}

class DocumentoPorEmitirCorreo extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  DocumentoPorEmitirCorreo(this.attachedDatabase, [this._alias]);
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
  late final GeneratedColumn<String> documentoPorEmitirId =
      GeneratedColumn<String>(
        'documento_por_emitir_id',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES documento_por_emitir (id) ON DELETE CASCADE',
        ),
      );
  late final GeneratedColumn<String> correo = GeneratedColumn<String>(
    'correo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, documentoPorEmitirId, correo];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'documento_por_emitir_correo';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  DocumentoPorEmitirCorreo createAlias(String alias) {
    return DocumentoPorEmitirCorreo(attachedDatabase, alias);
  }
}

class DocumentoPorEmitirCorreoEnvio extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  DocumentoPorEmitirCorreoEnvio(this.attachedDatabase, [this._alias]);
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
  late final GeneratedColumn<String> documentoPorEmitirId =
      GeneratedColumn<String>(
        'documento_por_emitir_id',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES documento_por_emitir (id) ON DELETE CASCADE',
        ),
      );
  late final GeneratedColumn<String> correo = GeneratedColumn<String>(
    'correo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, documentoPorEmitirId, correo];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'documento_por_emitir_correo_envio';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  DocumentoPorEmitirCorreoEnvio createAlias(String alias) {
    return DocumentoPorEmitirCorreoEnvio(attachedDatabase, alias);
  }
}

class DocumentoPorEmitirEvento extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  DocumentoPorEmitirEvento(this.attachedDatabase, [this._alias]);
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
  late final GeneratedColumn<String> documentoPorEmitirId =
      GeneratedColumn<String>(
        'documento_por_emitir_id',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES documento_por_emitir (id) ON DELETE CASCADE',
        ),
      );
  late final GeneratedColumn<DateTime> fechaHora = GeneratedColumn<DateTime>(
    'fecha_hora',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> tipoEvento = GeneratedColumn<String>(
    'tipo_evento',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> estadoAnterior = GeneratedColumn<String>(
    'estado_anterior',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> estadoNuevo = GeneratedColumn<String>(
    'estado_nuevo',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> observacion = GeneratedColumn<String>(
    'observacion',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> actor = GeneratedColumn<String>(
    'actor',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> datosRelevantes = GeneratedColumn<String>(
    'datos_relevantes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    documentoPorEmitirId,
    fechaHora,
    tipoEvento,
    estadoAnterior,
    estadoNuevo,
    observacion,
    actor,
    datosRelevantes,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'documento_por_emitir_evento';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  DocumentoPorEmitirEvento createAlias(String alias) {
    return DocumentoPorEmitirEvento(attachedDatabase, alias);
  }
}

class CuentaPorCobrar extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  CuentaPorCobrar(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<String> cicloVidaRegistro =
      GeneratedColumn<String>(
        'ciclo_vida_registro',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('activo'),
      );
  late final GeneratedColumn<String> documentoPorEmitirId =
      GeneratedColumn<String>(
        'documento_por_emitir_id',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'UNIQUE REFERENCES documento_por_emitir (id) ON DELETE RESTRICT',
        ),
      );
  late final GeneratedColumn<String> clienteId = GeneratedColumn<String>(
    'cliente_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> tipoDocumento = GeneratedColumn<String>(
    'tipo_documento',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> metodo = GeneratedColumn<String>(
    'metodo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<bool> requiereComplemento = GeneratedColumn<bool>(
    'requiere_complemento',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("requiere_complemento" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  late final GeneratedColumn<String> folioDocumento = GeneratedColumn<String>(
    'folio_documento',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> serieFiscal = GeneratedColumn<String>(
    'serie_fiscal',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> folioFiscal = GeneratedColumn<String>(
    'folio_fiscal',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> uuid = GeneratedColumn<String>(
    'uuid',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<DateTime> fechaEmisionReal =
      GeneratedColumn<DateTime>(
        'fecha_emision_real',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  late final GeneratedColumn<int> importeEmitido = GeneratedColumn<int>(
    'importe_emitido',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<int> saldoOriginal = GeneratedColumn<int>(
    'saldo_original',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<int> saldoPendiente = GeneratedColumn<int>(
    'saldo_pendiente',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> moneda = GeneratedColumn<String>(
    'moneda',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('MXN'),
  );
  late final GeneratedColumn<String> estatus = GeneratedColumn<String>(
    'estatus',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pendiente'),
  );
  late final GeneratedColumn<DateTime> fechaVencimiento =
      GeneratedColumn<DateTime>(
        'fecha_vencimiento',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
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
    documentoPorEmitirId,
    clienteId,
    tipoDocumento,
    metodo,
    requiereComplemento,
    folioDocumento,
    serieFiscal,
    folioFiscal,
    uuid,
    fechaEmisionReal,
    importeEmitido,
    saldoOriginal,
    saldoPendiente,
    moneda,
    estatus,
    fechaVencimiento,
    observaciones,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cuenta_por_cobrar';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  CuentaPorCobrar createAlias(String alias) {
    return CuentaPorCobrar(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'CHECK (saldo_original >= 0)',
    'CHECK (saldo_pendiente >= 0 AND saldo_pendiente <= saldo_original)',
    'CHECK (importe_emitido >= 0)',
  ];
}

class CuentaPorCobrarEvento extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  CuentaPorCobrarEvento(this.attachedDatabase, [this._alias]);
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
  late final GeneratedColumn<String> cuentaPorCobrarId =
      GeneratedColumn<String>(
        'cuenta_por_cobrar_id',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES cuenta_por_cobrar (id) ON DELETE CASCADE',
        ),
      );
  late final GeneratedColumn<DateTime> fechaHora = GeneratedColumn<DateTime>(
    'fecha_hora',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> tipoEvento = GeneratedColumn<String>(
    'tipo_evento',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> estadoAnterior = GeneratedColumn<String>(
    'estado_anterior',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> estadoNuevo = GeneratedColumn<String>(
    'estado_nuevo',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> observacion = GeneratedColumn<String>(
    'observacion',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> actor = GeneratedColumn<String>(
    'actor',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> datosRelevantes = GeneratedColumn<String>(
    'datos_relevantes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    cuentaPorCobrarId,
    fechaHora,
    tipoEvento,
    estadoAnterior,
    estadoNuevo,
    observacion,
    actor,
    datosRelevantes,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cuenta_por_cobrar_evento';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  CuentaPorCobrarEvento createAlias(String alias) {
    return CuentaPorCobrarEvento(attachedDatabase, alias);
  }
}

class Pago extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Pago(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<String> cicloVidaRegistro =
      GeneratedColumn<String>(
        'ciclo_vida_registro',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('activo'),
      );
  late final GeneratedColumn<String> folioPago = GeneratedColumn<String>(
    'folio_pago',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
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
  late final GeneratedColumn<int> montoTotal = GeneratedColumn<int>(
    'monto_total',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<int> montoAplicado = GeneratedColumn<int>(
    'monto_aplicado',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  late final GeneratedColumn<DateTime> fechaPago = GeneratedColumn<DateTime>(
    'fecha_pago',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> formaPago = GeneratedColumn<String>(
    'forma_pago',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> referencia = GeneratedColumn<String>(
    'referencia',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> bancoOrigen = GeneratedColumn<String>(
    'banco_origen',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> cuentaBancariaDestino =
      GeneratedColumn<String>(
        'cuenta_bancaria_destino',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  late final GeneratedColumn<String> observaciones = GeneratedColumn<String>(
    'observaciones',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> estatus = GeneratedColumn<String>(
    'estatus',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('registrado'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    createdAt,
    updatedAt,
    cicloVidaRegistro,
    folioPago,
    clienteId,
    montoTotal,
    montoAplicado,
    fechaPago,
    formaPago,
    referencia,
    bancoOrigen,
    cuentaBancariaDestino,
    observaciones,
    estatus,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pago';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  Pago createAlias(String alias) {
    return Pago(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'CHECK (monto_total > 0)',
    'CHECK (monto_aplicado >= 0 AND monto_aplicado <= monto_total)',
  ];
}

class AplicacionPago extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  AplicacionPago(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<String> cicloVidaRegistro =
      GeneratedColumn<String>(
        'ciclo_vida_registro',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('activo'),
      );
  late final GeneratedColumn<String> pagoId = GeneratedColumn<String>(
    'pago_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES pago (id) ON DELETE RESTRICT',
    ),
  );
  late final GeneratedColumn<String> cuentaPorCobrarId =
      GeneratedColumn<String>(
        'cuenta_por_cobrar_id',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES cuenta_por_cobrar (id) ON DELETE RESTRICT',
        ),
      );
  late final GeneratedColumn<int> monto = GeneratedColumn<int>(
    'monto',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<int> saldoAntes = GeneratedColumn<int>(
    'saldo_antes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<int> saldoDespues = GeneratedColumn<int>(
    'saldo_despues',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> estatus = GeneratedColumn<String>(
    'estatus',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('aplicada'),
  );
  late final GeneratedColumn<String> motivoCancelacion =
      GeneratedColumn<String>(
        'motivo_cancelacion',
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
    pagoId,
    cuentaPorCobrarId,
    monto,
    saldoAntes,
    saldoDespues,
    estatus,
    motivoCancelacion,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'aplicacion_pago';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  AplicacionPago createAlias(String alias) {
    return AplicacionPago(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'CHECK (monto > 0)',
    'CHECK (saldo_despues = saldo_antes - monto)',
    'CHECK (saldo_despues >= 0)',
  ];
}

class PagoEvento extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  PagoEvento(this.attachedDatabase, [this._alias]);
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
  late final GeneratedColumn<String> pagoId = GeneratedColumn<String>(
    'pago_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES pago (id) ON DELETE CASCADE',
    ),
  );
  late final GeneratedColumn<DateTime> fechaHora = GeneratedColumn<DateTime>(
    'fecha_hora',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> tipoEvento = GeneratedColumn<String>(
    'tipo_evento',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> estadoAnterior = GeneratedColumn<String>(
    'estado_anterior',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> estadoNuevo = GeneratedColumn<String>(
    'estado_nuevo',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> observacion = GeneratedColumn<String>(
    'observacion',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> actor = GeneratedColumn<String>(
    'actor',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> datosRelevantes = GeneratedColumn<String>(
    'datos_relevantes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    pagoId,
    fechaHora,
    tipoEvento,
    estadoAnterior,
    estadoNuevo,
    observacion,
    actor,
    datosRelevantes,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pago_evento';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  PagoEvento createAlias(String alias) {
    return PagoEvento(attachedDatabase, alias);
  }
}

class ComplementoPago extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  ComplementoPago(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<String> cicloVidaRegistro =
      GeneratedColumn<String>(
        'ciclo_vida_registro',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('activo'),
      );
  late final GeneratedColumn<String> pagoId = GeneratedColumn<String>(
    'pago_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'UNIQUE REFERENCES pago (id) ON DELETE RESTRICT',
    ),
  );
  late final GeneratedColumn<String> uuid = GeneratedColumn<String>(
    'uuid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  late final GeneratedColumn<String> serieFiscal = GeneratedColumn<String>(
    'serie_fiscal',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> folioFiscal = GeneratedColumn<String>(
    'folio_fiscal',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<DateTime> fechaTimbrado =
      GeneratedColumn<DateTime>(
        'fecha_timbrado',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  late final GeneratedColumn<int> montoTotal = GeneratedColumn<int>(
    'monto_total',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> estatus = GeneratedColumn<String>(
    'estatus',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('registrado'),
  );
  late final GeneratedColumn<String> motivoCancelacion =
      GeneratedColumn<String>(
        'motivo_cancelacion',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
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
    pagoId,
    uuid,
    serieFiscal,
    folioFiscal,
    fechaTimbrado,
    montoTotal,
    estatus,
    motivoCancelacion,
    observaciones,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'complemento_pago';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  ComplementoPago createAlias(String alias) {
    return ComplementoPago(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const ['CHECK (monto_total > 0)'];
}

class ComplementoPagoEvento extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  ComplementoPagoEvento(this.attachedDatabase, [this._alias]);
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
  late final GeneratedColumn<String> complementoPagoId =
      GeneratedColumn<String>(
        'complemento_pago_id',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES complemento_pago (id) ON DELETE CASCADE',
        ),
      );
  late final GeneratedColumn<DateTime> fechaHora = GeneratedColumn<DateTime>(
    'fecha_hora',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> tipoEvento = GeneratedColumn<String>(
    'tipo_evento',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> estadoAnterior = GeneratedColumn<String>(
    'estado_anterior',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> estadoNuevo = GeneratedColumn<String>(
    'estado_nuevo',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> observacion = GeneratedColumn<String>(
    'observacion',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> actor = GeneratedColumn<String>(
    'actor',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> datosRelevantes = GeneratedColumn<String>(
    'datos_relevantes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    complementoPagoId,
    fechaHora,
    tipoEvento,
    estadoAnterior,
    estadoNuevo,
    observacion,
    actor,
    datosRelevantes,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'complemento_pago_evento';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  ComplementoPagoEvento createAlias(String alias) {
    return ComplementoPagoEvento(attachedDatabase, alias);
  }
}

class CategoriaFinanciera extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  CategoriaFinanciera(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<String> cicloVidaRegistro =
      GeneratedColumn<String>(
        'ciclo_vida_registro',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('activo'),
      );
  late final GeneratedColumn<String> codigo = GeneratedColumn<String>(
    'codigo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  late final GeneratedColumn<String> nombre = GeneratedColumn<String>(
    'nombre',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> tipo = GeneratedColumn<String>(
    'tipo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> tipoMovimiento = GeneratedColumn<String>(
    'tipo_movimiento',
    aliasedName,
    false,
    type: DriftSqlType.string,
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
    tipo,
    tipoMovimiento,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'categoria_financiera';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  CategoriaFinanciera createAlias(String alias) {
    return CategoriaFinanciera(attachedDatabase, alias);
  }
}

class Ingreso extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Ingreso(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<String> cicloVidaRegistro =
      GeneratedColumn<String>(
        'ciclo_vida_registro',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('activo'),
      );
  late final GeneratedColumn<String> pagoId = GeneratedColumn<String>(
    'pago_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'UNIQUE REFERENCES pago (id) ON DELETE RESTRICT',
    ),
  );
  late final GeneratedColumn<String> folioIngreso = GeneratedColumn<String>(
    'folio_ingreso',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  late final GeneratedColumn<int> monto = GeneratedColumn<int>(
    'monto',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<DateTime> fecha = GeneratedColumn<DateTime>(
    'fecha',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> categoriaFinancieraId =
      GeneratedColumn<String>(
        'categoria_financiera_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES categoria_financiera (id) ON DELETE RESTRICT',
        ),
      );
  late final GeneratedColumn<String> servicioId = GeneratedColumn<String>(
    'servicio_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES servicio (id) ON DELETE RESTRICT',
    ),
  );
  late final GeneratedColumn<String> sucursalId = GeneratedColumn<String>(
    'sucursal_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES sucursal (id) ON DELETE RESTRICT',
    ),
  );
  late final GeneratedColumn<String> areaId = GeneratedColumn<String>(
    'area_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES area (id) ON DELETE RESTRICT',
    ),
  );
  late final GeneratedColumn<String> cuentaCaja = GeneratedColumn<String>(
    'cuenta_caja',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> formaPago = GeneratedColumn<String>(
    'forma_pago',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> concepto = GeneratedColumn<String>(
    'concepto',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> observaciones = GeneratedColumn<String>(
    'observaciones',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> estatus = GeneratedColumn<String>(
    'estatus',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('registrado'),
  );
  late final GeneratedColumn<String> motivoCancelacion =
      GeneratedColumn<String>(
        'motivo_cancelacion',
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
    pagoId,
    folioIngreso,
    monto,
    fecha,
    categoriaFinancieraId,
    servicioId,
    sucursalId,
    areaId,
    cuentaCaja,
    formaPago,
    concepto,
    observaciones,
    estatus,
    motivoCancelacion,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ingreso';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  Ingreso createAlias(String alias) {
    return Ingreso(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const ['CHECK (monto > 0)'];
}

class IngresoEvento extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  IngresoEvento(this.attachedDatabase, [this._alias]);
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
  late final GeneratedColumn<String> ingresoId = GeneratedColumn<String>(
    'ingreso_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES ingreso (id) ON DELETE CASCADE',
    ),
  );
  late final GeneratedColumn<DateTime> fechaHora = GeneratedColumn<DateTime>(
    'fecha_hora',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> tipoEvento = GeneratedColumn<String>(
    'tipo_evento',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> estadoAnterior = GeneratedColumn<String>(
    'estado_anterior',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> estadoNuevo = GeneratedColumn<String>(
    'estado_nuevo',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> observacion = GeneratedColumn<String>(
    'observacion',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> actor = GeneratedColumn<String>(
    'actor',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> datosRelevantes = GeneratedColumn<String>(
    'datos_relevantes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    ingresoId,
    fechaHora,
    tipoEvento,
    estadoAnterior,
    estadoNuevo,
    observacion,
    actor,
    datosRelevantes,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ingreso_evento';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  IngresoEvento createAlias(String alias) {
    return IngresoEvento(attachedDatabase, alias);
  }
}

class Egreso extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Egreso(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<String> cicloVidaRegistro =
      GeneratedColumn<String>(
        'ciclo_vida_registro',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('activo'),
      );
  late final GeneratedColumn<String> folioEgreso = GeneratedColumn<String>(
    'folio_egreso',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  late final GeneratedColumn<int> monto = GeneratedColumn<int>(
    'monto',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<DateTime> fecha = GeneratedColumn<DateTime>(
    'fecha',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> categoriaFinancieraId =
      GeneratedColumn<String>(
        'categoria_financiera_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES categoria_financiera (id) ON DELETE RESTRICT',
        ),
      );
  late final GeneratedColumn<String> servicioId = GeneratedColumn<String>(
    'servicio_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES servicio (id) ON DELETE RESTRICT',
    ),
  );
  late final GeneratedColumn<String> sucursalId = GeneratedColumn<String>(
    'sucursal_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES sucursal (id) ON DELETE RESTRICT',
    ),
  );
  late final GeneratedColumn<String> areaId = GeneratedColumn<String>(
    'area_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES area (id) ON DELETE RESTRICT',
    ),
  );
  late final GeneratedColumn<String> cuentaCaja = GeneratedColumn<String>(
    'cuenta_caja',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> formaPago = GeneratedColumn<String>(
    'forma_pago',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> beneficiario = GeneratedColumn<String>(
    'beneficiario',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> concepto = GeneratedColumn<String>(
    'concepto',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> observaciones = GeneratedColumn<String>(
    'observaciones',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> estatus = GeneratedColumn<String>(
    'estatus',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('registrado'),
  );
  late final GeneratedColumn<String> motivoCancelacion =
      GeneratedColumn<String>(
        'motivo_cancelacion',
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
    folioEgreso,
    monto,
    fecha,
    categoriaFinancieraId,
    servicioId,
    sucursalId,
    areaId,
    cuentaCaja,
    formaPago,
    beneficiario,
    concepto,
    observaciones,
    estatus,
    motivoCancelacion,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'egreso';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  Egreso createAlias(String alias) {
    return Egreso(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const ['CHECK (monto > 0)'];
}

class EgresoEvento extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  EgresoEvento(this.attachedDatabase, [this._alias]);
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
  late final GeneratedColumn<String> egresoId = GeneratedColumn<String>(
    'egreso_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES egreso (id) ON DELETE CASCADE',
    ),
  );
  late final GeneratedColumn<DateTime> fechaHora = GeneratedColumn<DateTime>(
    'fecha_hora',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> tipoEvento = GeneratedColumn<String>(
    'tipo_evento',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> estadoAnterior = GeneratedColumn<String>(
    'estado_anterior',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> estadoNuevo = GeneratedColumn<String>(
    'estado_nuevo',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> observacion = GeneratedColumn<String>(
    'observacion',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> actor = GeneratedColumn<String>(
    'actor',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> datosRelevantes = GeneratedColumn<String>(
    'datos_relevantes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    egresoId,
    fechaHora,
    tipoEvento,
    estadoAnterior,
    estadoNuevo,
    observacion,
    actor,
    datosRelevantes,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'egreso_evento';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  EgresoEvento createAlias(String alias) {
    return EgresoEvento(attachedDatabase, alias);
  }
}

class Empleado extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Empleado(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<String> cicloVidaRegistro =
      GeneratedColumn<String>(
        'ciclo_vida_registro',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('activo'),
      );
  late final GeneratedColumn<int> numeroEmpleado = GeneratedColumn<int>(
    'numero_empleado',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  late final GeneratedColumn<String> fotografiaAttachmentId =
      GeneratedColumn<String>(
        'fotografia_attachment_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES attachment (id) ON DELETE RESTRICT',
        ),
      );
  late final GeneratedColumn<String> nombres = GeneratedColumn<String>(
    'nombres',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> apellidoPaterno = GeneratedColumn<String>(
    'apellido_paterno',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> apellidoMaterno = GeneratedColumn<String>(
    'apellido_materno',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> sexo = GeneratedColumn<String>(
    'sexo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<DateTime> fechaNacimiento =
      GeneratedColumn<DateTime>(
        'fecha_nacimiento',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  late final GeneratedColumn<String> curp = GeneratedColumn<String>(
    'curp',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> rfc = GeneratedColumn<String>(
    'rfc',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> codigoPostalFiscal =
      GeneratedColumn<String>(
        'codigo_postal_fiscal',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  late final GeneratedColumn<String> nss = GeneratedColumn<String>(
    'nss',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> estadoCivil = GeneratedColumn<String>(
    'estado_civil',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> nacionalidad = GeneratedColumn<String>(
    'nacionalidad',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('Mexicana'),
  );
  late final GeneratedColumn<String> telefono = GeneratedColumn<String>(
    'telefono',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> correoElectronico =
      GeneratedColumn<String>(
        'correo_electronico',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  late final GeneratedColumn<String> contactoEmergenciaNombre =
      GeneratedColumn<String>(
        'contacto_emergencia_nombre',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  late final GeneratedColumn<String> telefonoEmergencia =
      GeneratedColumn<String>(
        'telefono_emergencia',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  late final GeneratedColumn<String> parentescoEmergencia =
      GeneratedColumn<String>(
        'parentesco_emergencia',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  late final GeneratedColumn<String> bancoId = GeneratedColumn<String>(
    'banco_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES banco (id) ON DELETE RESTRICT',
    ),
  );
  late final GeneratedColumn<String> numeroCuentaTarjeta =
      GeneratedColumn<String>(
        'numero_cuenta_tarjeta',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  late final GeneratedColumn<String> clabe = GeneratedColumn<String>(
    'clabe',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<DateTime> fechaIngreso = GeneratedColumn<DateTime>(
    'fecha_ingreso',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> estatus = GeneratedColumn<String>(
    'estatus',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('activo'),
  );
  late final GeneratedColumn<String> puestoId = GeneratedColumn<String>(
    'puesto_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES puesto (id) ON DELETE RESTRICT',
    ),
  );
  late final GeneratedColumn<String> empresaId = GeneratedColumn<String>(
    'empresa_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES empresa (id) ON DELETE RESTRICT',
    ),
  );
  late final GeneratedColumn<String> sucursalId = GeneratedColumn<String>(
    'sucursal_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES sucursal (id) ON DELETE RESTRICT',
    ),
  );
  late final GeneratedColumn<int> sueldoMensualAdministrativo =
      GeneratedColumn<int>(
        'sueldo_mensual_administrativo',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      );
  late final GeneratedColumn<int> bonoMensualAdministrativo =
      GeneratedColumn<int>(
        'bono_mensual_administrativo',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      );
  late final GeneratedColumn<String> observaciones = GeneratedColumn<String>(
    'observaciones',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<DateTime> fechaBaja = GeneratedColumn<DateTime>(
    'fecha_baja',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> motivoBaja = GeneratedColumn<String>(
    'motivo_baja',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> observacionesBaja =
      GeneratedColumn<String>(
        'observaciones_baja',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  late final GeneratedColumn<String> nivelEstudios = GeneratedColumn<String>(
    'nivel_estudios',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> observacionesEscolaridad =
      GeneratedColumn<String>(
        'observaciones_escolaridad',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  late final GeneratedColumn<int> aniosExperienciaSeguridad =
      GeneratedColumn<int>(
        'anios_experiencia_seguridad',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      );
  late final GeneratedColumn<int> mesesExperienciaAdicionales =
      GeneratedColumn<int>(
        'meses_experiencia_adicionales',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      );
  late final GeneratedColumn<String> ultimoPuestoDesempenado =
      GeneratedColumn<String>(
        'ultimo_puesto_desempenado',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  late final GeneratedColumn<String> resumenExperiencia =
      GeneratedColumn<String>(
        'resumen_experiencia',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  late final GeneratedColumn<String> observacionesExperiencia =
      GeneratedColumn<String>(
        'observaciones_experiencia',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  late final GeneratedColumn<DateTime> fechaEvaluacionPsicologica =
      GeneratedColumn<DateTime>(
        'fecha_evaluacion_psicologica',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  late final GeneratedColumn<String> resumenPsicologico =
      GeneratedColumn<String>(
        'resumen_psicologico',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  late final GeneratedColumn<String> observacionesPsicologico =
      GeneratedColumn<String>(
        'observaciones_psicologico',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  late final GeneratedColumn<DateTime> fechaEstudioSocioeconomico =
      GeneratedColumn<DateTime>(
        'fecha_estudio_socioeconomico',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  late final GeneratedColumn<String> resumenEstudioSocioeconomico =
      GeneratedColumn<String>(
        'resumen_estudio_socioeconomico',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  late final GeneratedColumn<String> observacionesEstudioSocioeconomico =
      GeneratedColumn<String>(
        'observaciones_estudio_socioeconomico',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  late final GeneratedColumn<DateTime> fechaAntidoping =
      GeneratedColumn<DateTime>(
        'fecha_antidoping',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  late final GeneratedColumn<String> resultadoAmp = GeneratedColumn<String>(
    'resultado_amp',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> resultadoBzd = GeneratedColumn<String>(
    'resultado_bzd',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> resultadoCoc = GeneratedColumn<String>(
    'resultado_coc',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> resultadoMet = GeneratedColumn<String>(
    'resultado_met',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> resultadoOpi = GeneratedColumn<String>(
    'resultado_opi',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> observacionesAntidoping =
      GeneratedColumn<String>(
        'observaciones_antidoping',
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
    numeroEmpleado,
    fotografiaAttachmentId,
    nombres,
    apellidoPaterno,
    apellidoMaterno,
    sexo,
    fechaNacimiento,
    curp,
    rfc,
    codigoPostalFiscal,
    nss,
    estadoCivil,
    nacionalidad,
    telefono,
    correoElectronico,
    contactoEmergenciaNombre,
    telefonoEmergencia,
    parentescoEmergencia,
    bancoId,
    numeroCuentaTarjeta,
    clabe,
    fechaIngreso,
    estatus,
    puestoId,
    empresaId,
    sucursalId,
    sueldoMensualAdministrativo,
    bonoMensualAdministrativo,
    observaciones,
    fechaBaja,
    motivoBaja,
    observacionesBaja,
    nivelEstudios,
    observacionesEscolaridad,
    aniosExperienciaSeguridad,
    mesesExperienciaAdicionales,
    ultimoPuestoDesempenado,
    resumenExperiencia,
    observacionesExperiencia,
    fechaEvaluacionPsicologica,
    resumenPsicologico,
    observacionesPsicologico,
    fechaEstudioSocioeconomico,
    resumenEstudioSocioeconomico,
    observacionesEstudioSocioeconomico,
    fechaAntidoping,
    resultadoAmp,
    resultadoBzd,
    resultadoCoc,
    resultadoMet,
    resultadoOpi,
    observacionesAntidoping,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'empleado';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  Empleado createAlias(String alias) {
    return Empleado(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'CHECK (anios_experiencia_seguridad >= 0)',
    'CHECK (meses_experiencia_adicionales IS NULL OR (meses_experiencia_adicionales >= 0 AND meses_experiencia_adicionales <= 11))',
    'CHECK (sueldo_mensual_administrativo IS NULL OR sueldo_mensual_administrativo > 0)',
    'CHECK (bono_mensual_administrativo IS NULL OR bono_mensual_administrativo >= 0)',
  ];
}

class EmpleadoEvento extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  EmpleadoEvento(this.attachedDatabase, [this._alias]);
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
  late final GeneratedColumn<String> empleadoId = GeneratedColumn<String>(
    'empleado_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES empleado (id) ON DELETE CASCADE',
    ),
  );
  late final GeneratedColumn<DateTime> fechaHora = GeneratedColumn<DateTime>(
    'fecha_hora',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> tipoEvento = GeneratedColumn<String>(
    'tipo_evento',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> estadoAnterior = GeneratedColumn<String>(
    'estado_anterior',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> estadoNuevo = GeneratedColumn<String>(
    'estado_nuevo',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> observacion = GeneratedColumn<String>(
    'observacion',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> actor = GeneratedColumn<String>(
    'actor',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> datosRelevantes = GeneratedColumn<String>(
    'datos_relevantes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    empleadoId,
    fechaHora,
    tipoEvento,
    estadoAnterior,
    estadoNuevo,
    observacion,
    actor,
    datosRelevantes,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'empleado_evento';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  EmpleadoEvento createAlias(String alias) {
    return EmpleadoEvento(attachedDatabase, alias);
  }
}

class EmpleadoPeriodoLaboral extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  EmpleadoPeriodoLaboral(this.attachedDatabase, [this._alias]);
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
  late final GeneratedColumn<String> empleadoId = GeneratedColumn<String>(
    'empleado_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES empleado (id) ON DELETE CASCADE',
    ),
  );
  late final GeneratedColumn<DateTime> fechaIngreso = GeneratedColumn<DateTime>(
    'fecha_ingreso',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<DateTime> fechaBaja = GeneratedColumn<DateTime>(
    'fecha_baja',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> motivoBaja = GeneratedColumn<String>(
    'motivo_baja',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> observacionesBaja =
      GeneratedColumn<String>(
        'observaciones_baja',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    empleadoId,
    fechaIngreso,
    fechaBaja,
    motivoBaja,
    observacionesBaja,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'empleado_periodo_laboral';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  EmpleadoPeriodoLaboral createAlias(String alias) {
    return EmpleadoPeriodoLaboral(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'CHECK (fecha_baja >= fecha_ingreso)',
  ];
}

class AsignacionServicio extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  AsignacionServicio(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<String> cicloVidaRegistro =
      GeneratedColumn<String>(
        'ciclo_vida_registro',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('activo'),
      );
  late final GeneratedColumn<String> empleadoId = GeneratedColumn<String>(
    'empleado_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES empleado (id) ON DELETE RESTRICT',
    ),
  );
  late final GeneratedColumn<String> servicioId = GeneratedColumn<String>(
    'servicio_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES servicio (id) ON DELETE RESTRICT',
    ),
  );
  late final GeneratedColumn<String> turnoId = GeneratedColumn<String>(
    'turno_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES tipo_modalidad_turno (id) ON DELETE RESTRICT',
    ),
  );
  late final GeneratedColumn<DateTime> fechaInicio = GeneratedColumn<DateTime>(
    'fecha_inicio',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<DateTime> fechaTermino = GeneratedColumn<DateTime>(
    'fecha_termino',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> motivoTermino = GeneratedColumn<String>(
    'motivo_termino',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> observaciones = GeneratedColumn<String>(
    'observaciones',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> observacionesTermino =
      GeneratedColumn<String>(
        'observaciones_termino',
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
    empleadoId,
    servicioId,
    turnoId,
    fechaInicio,
    fechaTermino,
    motivoTermino,
    observaciones,
    observacionesTermino,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'asignacion_servicio';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  AsignacionServicio createAlias(String alias) {
    return AsignacionServicio(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'CHECK (fecha_termino IS NULL OR fecha_termino >= fecha_inicio)',
  ];
}

class AsignacionServicioSueldoVigencia extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  AsignacionServicioSueldoVigencia(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<String> cicloVidaRegistro =
      GeneratedColumn<String>(
        'ciclo_vida_registro',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('activo'),
      );
  late final GeneratedColumn<String> asignacionServicioId =
      GeneratedColumn<String>(
        'asignacion_servicio_id',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES asignacion_servicio (id) ON DELETE RESTRICT',
        ),
      );
  late final GeneratedColumn<int> sueldoMensual = GeneratedColumn<int>(
    'sueldo_mensual',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<int> bonoMensual = GeneratedColumn<int>(
    'bono_mensual',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<DateTime> fechaInicioVigencia =
      GeneratedColumn<DateTime>(
        'fecha_inicio_vigencia',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  late final GeneratedColumn<DateTime> fechaFinVigencia =
      GeneratedColumn<DateTime>(
        'fecha_fin_vigencia',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
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
    asignacionServicioId,
    sueldoMensual,
    bonoMensual,
    fechaInicioVigencia,
    fechaFinVigencia,
    observaciones,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'asignacion_servicio_sueldo_vigencia';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  AsignacionServicioSueldoVigencia createAlias(String alias) {
    return AsignacionServicioSueldoVigencia(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'CHECK (sueldo_mensual > 0)',
    'CHECK (bono_mensual >= 0)',
    'CHECK (fecha_fin_vigencia IS NULL OR fecha_fin_vigencia >= fecha_inicio_vigencia)',
  ];
}

class FichaTecnicaEmpleado extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  FichaTecnicaEmpleado(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<String> cicloVidaRegistro =
      GeneratedColumn<String>(
        'ciclo_vida_registro',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('activo'),
      );
  late final GeneratedColumn<String> folio = GeneratedColumn<String>(
    'folio',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  late final GeneratedColumn<String> empleadoId = GeneratedColumn<String>(
    'empleado_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES empleado (id) ON DELETE RESTRICT',
    ),
  );
  late final GeneratedColumn<String> servicioId = GeneratedColumn<String>(
    'servicio_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES servicio (id) ON DELETE RESTRICT',
    ),
  );
  late final GeneratedColumn<String> attachmentId = GeneratedColumn<String>(
    'attachment_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES attachment (id) ON DELETE RESTRICT',
    ),
  );
  late final GeneratedColumn<String> camposExcluidos = GeneratedColumn<String>(
    'campos_excluidos',
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
    folio,
    empleadoId,
    servicioId,
    attachmentId,
    camposExcluidos,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ficha_tecnica_empleado';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  FichaTecnicaEmpleado createAlias(String alias) {
    return FichaTecnicaEmpleado(attachedDatabase, alias);
  }
}

class EmpresaAttachment extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  EmpresaAttachment(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> attachmentId = GeneratedColumn<String>(
    'attachment_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES attachment (id) ON DELETE CASCADE',
    ),
  );
  late final GeneratedColumn<String> empresaId = GeneratedColumn<String>(
    'empresa_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES empresa (id) ON DELETE RESTRICT',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [attachmentId, empresaId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'empresa_attachment';
  @override
  Set<GeneratedColumn> get $primaryKey => {attachmentId};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  EmpresaAttachment createAlias(String alias) {
    return EmpresaAttachment(attachedDatabase, alias);
  }
}

class ClienteAttachment extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  ClienteAttachment(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> attachmentId = GeneratedColumn<String>(
    'attachment_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES attachment (id) ON DELETE CASCADE',
    ),
  );
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
  @override
  List<GeneratedColumn> get $columns => [attachmentId, clienteId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cliente_attachment';
  @override
  Set<GeneratedColumn> get $primaryKey => {attachmentId};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  ClienteAttachment createAlias(String alias) {
    return ClienteAttachment(attachedDatabase, alias);
  }
}

class DocumentoPorEmitirAttachment extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  DocumentoPorEmitirAttachment(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> attachmentId = GeneratedColumn<String>(
    'attachment_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES attachment (id) ON DELETE CASCADE',
    ),
  );
  late final GeneratedColumn<String> documentoPorEmitirId =
      GeneratedColumn<String>(
        'documento_por_emitir_id',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES documento_por_emitir (id) ON DELETE CASCADE',
        ),
      );
  @override
  List<GeneratedColumn> get $columns => [attachmentId, documentoPorEmitirId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'documento_por_emitir_attachment';
  @override
  Set<GeneratedColumn> get $primaryKey => {attachmentId};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  DocumentoPorEmitirAttachment createAlias(String alias) {
    return DocumentoPorEmitirAttachment(attachedDatabase, alias);
  }
}

class PagoAttachment extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  PagoAttachment(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> attachmentId = GeneratedColumn<String>(
    'attachment_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES attachment (id) ON DELETE CASCADE',
    ),
  );
  late final GeneratedColumn<String> pagoId = GeneratedColumn<String>(
    'pago_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES pago (id) ON DELETE CASCADE',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [attachmentId, pagoId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pago_attachment';
  @override
  Set<GeneratedColumn> get $primaryKey => {attachmentId};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  PagoAttachment createAlias(String alias) {
    return PagoAttachment(attachedDatabase, alias);
  }
}

class ComplementoPagoAttachment extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  ComplementoPagoAttachment(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> attachmentId = GeneratedColumn<String>(
    'attachment_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES attachment (id) ON DELETE CASCADE',
    ),
  );
  late final GeneratedColumn<String> complementoPagoId =
      GeneratedColumn<String>(
        'complemento_pago_id',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES complemento_pago (id) ON DELETE CASCADE',
        ),
      );
  @override
  List<GeneratedColumn> get $columns => [attachmentId, complementoPagoId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'complemento_pago_attachment';
  @override
  Set<GeneratedColumn> get $primaryKey => {attachmentId};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  ComplementoPagoAttachment createAlias(String alias) {
    return ComplementoPagoAttachment(attachedDatabase, alias);
  }
}

class IngresoAttachment extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  IngresoAttachment(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> attachmentId = GeneratedColumn<String>(
    'attachment_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES attachment (id) ON DELETE CASCADE',
    ),
  );
  late final GeneratedColumn<String> ingresoId = GeneratedColumn<String>(
    'ingreso_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES ingreso (id) ON DELETE CASCADE',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [attachmentId, ingresoId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ingreso_attachment';
  @override
  Set<GeneratedColumn> get $primaryKey => {attachmentId};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  IngresoAttachment createAlias(String alias) {
    return IngresoAttachment(attachedDatabase, alias);
  }
}

class EgresoAttachment extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  EgresoAttachment(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> attachmentId = GeneratedColumn<String>(
    'attachment_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES attachment (id) ON DELETE CASCADE',
    ),
  );
  late final GeneratedColumn<String> egresoId = GeneratedColumn<String>(
    'egreso_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES egreso (id) ON DELETE CASCADE',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [attachmentId, egresoId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'egreso_attachment';
  @override
  Set<GeneratedColumn> get $primaryKey => {attachmentId};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  EgresoAttachment createAlias(String alias) {
    return EgresoAttachment(attachedDatabase, alias);
  }
}

class EmpleadoAttachment extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  EmpleadoAttachment(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> attachmentId = GeneratedColumn<String>(
    'attachment_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES attachment (id) ON DELETE CASCADE',
    ),
  );
  late final GeneratedColumn<String> empleadoId = GeneratedColumn<String>(
    'empleado_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES empleado (id) ON DELETE CASCADE',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [attachmentId, empleadoId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'empleado_attachment';
  @override
  Set<GeneratedColumn> get $primaryKey => {attachmentId};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  EmpleadoAttachment createAlias(String alias) {
    return EmpleadoAttachment(attachedDatabase, alias);
  }
}

class Nomina extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Nomina(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<String> cicloVidaRegistro =
      GeneratedColumn<String>(
        'ciclo_vida_registro',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('activo'),
      );
  late final GeneratedColumn<String> folio = GeneratedColumn<String>(
    'folio',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  late final GeneratedColumn<int> anio = GeneratedColumn<int>(
    'anio',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<int> mes = GeneratedColumn<int>(
    'mes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> tipoPeriodo = GeneratedColumn<String>(
    'tipo_periodo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<DateTime> fechaInicioPeriodo =
      GeneratedColumn<DateTime>(
        'fecha_inicio_periodo',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  late final GeneratedColumn<DateTime> fechaFinPeriodo =
      GeneratedColumn<DateTime>(
        'fecha_fin_periodo',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  late final GeneratedColumn<DateTime> fechaPagoOrdinaria =
      GeneratedColumn<DateTime>(
        'fecha_pago_ordinaria',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  late final GeneratedColumn<String> estatus = GeneratedColumn<String>(
    'estatus',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('borrador'),
  );
  late final GeneratedColumn<DateTime> fechaCierre = GeneratedColumn<DateTime>(
    'fecha_cierre',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
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
    folio,
    anio,
    mes,
    tipoPeriodo,
    fechaInicioPeriodo,
    fechaFinPeriodo,
    fechaPagoOrdinaria,
    estatus,
    fechaCierre,
    observaciones,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'nomina';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  Nomina createAlias(String alias) {
    return Nomina(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'UNIQUE (anio, mes, tipo_periodo)',
    'CHECK (mes >= 1 AND mes <= 12)',
    'CHECK (fecha_fin_periodo >= fecha_inicio_periodo)',
  ];
}

class NominaEmpleado extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  NominaEmpleado(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<String> cicloVidaRegistro =
      GeneratedColumn<String>(
        'ciclo_vida_registro',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('activo'),
      );
  late final GeneratedColumn<String> nominaId = GeneratedColumn<String>(
    'nomina_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES nomina (id) ON DELETE CASCADE',
    ),
  );
  late final GeneratedColumn<String> empleadoId = GeneratedColumn<String>(
    'empleado_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES empleado (id) ON DELETE RESTRICT',
    ),
  );
  late final GeneratedColumn<int> numeroEmpleado = GeneratedColumn<int>(
    'numero_empleado',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> nombreCompleto = GeneratedColumn<String>(
    'nombre_completo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> puestoNombre = GeneratedColumn<String>(
    'puesto_nombre',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> servicioId = GeneratedColumn<String>(
    'servicio_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES servicio (id) ON DELETE RESTRICT',
    ),
  );
  late final GeneratedColumn<String> servicioNombre = GeneratedColumn<String>(
    'servicio_nombre',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> turnoNombre = GeneratedColumn<String>(
    'turno_nombre',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> bancoNombre = GeneratedColumn<String>(
    'banco_nombre',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> numeroCuentaTarjeta =
      GeneratedColumn<String>(
        'numero_cuenta_tarjeta',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  late final GeneratedColumn<String> clabe = GeneratedColumn<String>(
    'clabe',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> fuenteSueldoUtilizada =
      GeneratedColumn<String>(
        'fuente_sueldo_utilizada',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  late final GeneratedColumn<int> diasPagables = GeneratedColumn<int>(
    'dias_pagables',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<int> sueldoMensualUtilizado = GeneratedColumn<int>(
    'sueldo_mensual_utilizado',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<int> sueldoQuincenalReferencia =
      GeneratedColumn<int>(
        'sueldo_quincenal_referencia',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      );
  late final GeneratedColumn<int> pagoPorDia = GeneratedColumn<int>(
    'pago_por_dia',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<int> importeBase = GeneratedColumn<int>(
    'importe_base',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<int> prestamo = GeneratedColumn<int>(
    'prestamo',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  late final GeneratedColumn<int> tiempoExtra = GeneratedColumn<int>(
    'tiempo_extra',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  late final GeneratedColumn<int> bono = GeneratedColumn<int>(
    'bono',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  late final GeneratedColumn<bool> bonoModificadoManualmente =
      GeneratedColumn<bool>(
        'bono_modificado_manualmente',
        aliasedName,
        false,
        type: DriftSqlType.bool,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("bono_modificado_manualmente" IN (0, 1))',
        ),
        defaultValue: const Constant(false),
      );
  late final GeneratedColumn<int> faltas = GeneratedColumn<int>(
    'faltas',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  late final GeneratedColumn<int> descuentoPorFaltas = GeneratedColumn<int>(
    'descuento_por_faltas',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  late final GeneratedColumn<int> otrosDescuentos = GeneratedColumn<int>(
    'otros_descuentos',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  late final GeneratedColumn<String> observaciones = GeneratedColumn<String>(
    'observaciones',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<int> montoFiscal = GeneratedColumn<int>(
    'monto_fiscal',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  late final GeneratedColumn<int> montoNoFiscal = GeneratedColumn<int>(
    'monto_no_fiscal',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  late final GeneratedColumn<bool> distribucionModificadaManualmente =
      GeneratedColumn<bool>(
        'distribucion_modificada_manualmente',
        aliasedName,
        false,
        type: DriftSqlType.bool,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("distribucion_modificada_manualmente" IN (0, 1))',
        ),
        defaultValue: const Constant(false),
      );
  late final GeneratedColumn<bool> distribucionPendienteRevision =
      GeneratedColumn<bool>(
        'distribucion_pendiente_revision',
        aliasedName,
        false,
        type: DriftSqlType.bool,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("distribucion_pendiente_revision" IN (0, 1))',
        ),
        defaultValue: const Constant(false),
      );
  late final GeneratedColumn<int> totalAPagar = GeneratedColumn<int>(
    'total_a_pagar',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> estatusPago = GeneratedColumn<String>(
    'estatus_pago',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pendiente'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    createdAt,
    updatedAt,
    cicloVidaRegistro,
    nominaId,
    empleadoId,
    numeroEmpleado,
    nombreCompleto,
    puestoNombre,
    servicioId,
    servicioNombre,
    turnoNombre,
    bancoNombre,
    numeroCuentaTarjeta,
    clabe,
    fuenteSueldoUtilizada,
    diasPagables,
    sueldoMensualUtilizado,
    sueldoQuincenalReferencia,
    pagoPorDia,
    importeBase,
    prestamo,
    tiempoExtra,
    bono,
    bonoModificadoManualmente,
    faltas,
    descuentoPorFaltas,
    otrosDescuentos,
    observaciones,
    montoFiscal,
    montoNoFiscal,
    distribucionModificadaManualmente,
    distribucionPendienteRevision,
    totalAPagar,
    estatusPago,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'nomina_empleado';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  NominaEmpleado createAlias(String alias) {
    return NominaEmpleado(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'UNIQUE (nomina_id, empleado_id)',
    'CHECK (dias_pagables >= 0)',
    'CHECK (sueldo_mensual_utilizado > 0)',
    'CHECK (importe_base >= 0)',
    'CHECK (prestamo >= 0)',
    'CHECK (tiempo_extra >= 0)',
    'CHECK (bono >= 0)',
    'CHECK (faltas >= 0)',
    'CHECK (descuento_por_faltas >= 0)',
    'CHECK (otros_descuentos >= 0)',
    'CHECK (monto_fiscal >= 0)',
    'CHECK (monto_no_fiscal >= 0)',
  ];
}

class NominaEmpleadoTramo extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  NominaEmpleadoTramo(this.attachedDatabase, [this._alias]);
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
  late final GeneratedColumn<String> nominaEmpleadoId = GeneratedColumn<String>(
    'nomina_empleado_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES nomina_empleado (id) ON DELETE CASCADE',
    ),
  );
  late final GeneratedColumn<DateTime> fechaInicio = GeneratedColumn<DateTime>(
    'fecha_inicio',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<DateTime> fechaFin = GeneratedColumn<DateTime>(
    'fecha_fin',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> servicioId = GeneratedColumn<String>(
    'servicio_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES servicio (id) ON DELETE RESTRICT',
    ),
  );
  late final GeneratedColumn<String> servicioNombre = GeneratedColumn<String>(
    'servicio_nombre',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> turnoNombre = GeneratedColumn<String>(
    'turno_nombre',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> fuenteSueldo = GeneratedColumn<String>(
    'fuente_sueldo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<int> sueldoMensual = GeneratedColumn<int>(
    'sueldo_mensual',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<int> bonoMensual = GeneratedColumn<int>(
    'bono_mensual',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<int> diasReales = GeneratedColumn<int>(
    'dias_reales',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<int> importeTramo = GeneratedColumn<int>(
    'importe_tramo',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    nominaEmpleadoId,
    fechaInicio,
    fechaFin,
    servicioId,
    servicioNombre,
    turnoNombre,
    fuenteSueldo,
    sueldoMensual,
    bonoMensual,
    diasReales,
    importeTramo,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'nomina_empleado_tramo';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  NominaEmpleadoTramo createAlias(String alias) {
    return NominaEmpleadoTramo(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'CHECK (fecha_fin >= fecha_inicio)',
    'CHECK (dias_reales > 0)',
    'CHECK (sueldo_mensual > 0)',
    'CHECK (bono_mensual >= 0)',
    'CHECK (importe_tramo >= 0)',
  ];
}

class NominaEvento extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  NominaEvento(this.attachedDatabase, [this._alias]);
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
  late final GeneratedColumn<String> nominaId = GeneratedColumn<String>(
    'nomina_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES nomina (id) ON DELETE CASCADE',
    ),
  );
  late final GeneratedColumn<String> nominaEmpleadoId = GeneratedColumn<String>(
    'nomina_empleado_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES nomina_empleado (id) ON DELETE CASCADE',
    ),
  );
  late final GeneratedColumn<DateTime> fechaHora = GeneratedColumn<DateTime>(
    'fecha_hora',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> tipoEvento = GeneratedColumn<String>(
    'tipo_evento',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> observacion = GeneratedColumn<String>(
    'observacion',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> actor = GeneratedColumn<String>(
    'actor',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> datosRelevantes = GeneratedColumn<String>(
    'datos_relevantes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    nominaId,
    nominaEmpleadoId,
    fechaHora,
    tipoEvento,
    observacion,
    actor,
    datosRelevantes,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'nomina_evento';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  NominaEvento createAlias(String alias) {
    return NominaEvento(attachedDatabase, alias);
  }
}

class PagoNomina extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  PagoNomina(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<String> cicloVidaRegistro =
      GeneratedColumn<String>(
        'ciclo_vida_registro',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('activo'),
      );
  late final GeneratedColumn<String> folioPagoNomina = GeneratedColumn<String>(
    'folio_pago_nomina',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  late final GeneratedColumn<String> nominaId = GeneratedColumn<String>(
    'nomina_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES nomina (id) ON DELETE RESTRICT',
    ),
  );
  late final GeneratedColumn<String> egresoId = GeneratedColumn<String>(
    'egreso_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'UNIQUE REFERENCES egreso (id) ON DELETE RESTRICT',
    ),
  );
  late final GeneratedColumn<int> montoTotal = GeneratedColumn<int>(
    'monto_total',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<DateTime> fechaPago = GeneratedColumn<DateTime>(
    'fecha_pago',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> formaPago = GeneratedColumn<String>(
    'forma_pago',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> referencia = GeneratedColumn<String>(
    'referencia',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> cuentaBancariaOrigen =
      GeneratedColumn<String>(
        'cuenta_bancaria_origen',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  late final GeneratedColumn<String> observaciones = GeneratedColumn<String>(
    'observaciones',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> estatus = GeneratedColumn<String>(
    'estatus',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('registrado'),
  );
  late final GeneratedColumn<String> motivoCancelacion =
      GeneratedColumn<String>(
        'motivo_cancelacion',
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
    folioPagoNomina,
    nominaId,
    egresoId,
    montoTotal,
    fechaPago,
    formaPago,
    referencia,
    cuentaBancariaOrigen,
    observaciones,
    estatus,
    motivoCancelacion,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pago_nomina';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  PagoNomina createAlias(String alias) {
    return PagoNomina(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const ['CHECK (monto_total > 0)'];
}

class AplicacionPagoNomina extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  AplicacionPagoNomina(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<String> cicloVidaRegistro =
      GeneratedColumn<String>(
        'ciclo_vida_registro',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('activo'),
      );
  late final GeneratedColumn<String> pagoNominaId = GeneratedColumn<String>(
    'pago_nomina_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES pago_nomina (id) ON DELETE RESTRICT',
    ),
  );
  late final GeneratedColumn<String> nominaEmpleadoId = GeneratedColumn<String>(
    'nomina_empleado_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES nomina_empleado (id) ON DELETE RESTRICT',
    ),
  );
  late final GeneratedColumn<int> monto = GeneratedColumn<int>(
    'monto',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<int> saldoAntes = GeneratedColumn<int>(
    'saldo_antes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<int> saldoDespues = GeneratedColumn<int>(
    'saldo_despues',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> estatus = GeneratedColumn<String>(
    'estatus',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('aplicada'),
  );
  late final GeneratedColumn<String> motivoCancelacion =
      GeneratedColumn<String>(
        'motivo_cancelacion',
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
    pagoNominaId,
    nominaEmpleadoId,
    monto,
    saldoAntes,
    saldoDespues,
    estatus,
    motivoCancelacion,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'aplicacion_pago_nomina';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  AplicacionPagoNomina createAlias(String alias) {
    return AplicacionPagoNomina(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'CHECK (monto > 0)',
    'CHECK (saldo_despues = saldo_antes - monto)',
    'CHECK (saldo_despues >= 0)',
  ];
}

class PagoNominaEvento extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  PagoNominaEvento(this.attachedDatabase, [this._alias]);
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
  late final GeneratedColumn<String> pagoNominaId = GeneratedColumn<String>(
    'pago_nomina_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES pago_nomina (id) ON DELETE CASCADE',
    ),
  );
  late final GeneratedColumn<DateTime> fechaHora = GeneratedColumn<DateTime>(
    'fecha_hora',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> tipoEvento = GeneratedColumn<String>(
    'tipo_evento',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> estadoAnterior = GeneratedColumn<String>(
    'estado_anterior',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> estadoNuevo = GeneratedColumn<String>(
    'estado_nuevo',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> observacion = GeneratedColumn<String>(
    'observacion',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> actor = GeneratedColumn<String>(
    'actor',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> datosRelevantes = GeneratedColumn<String>(
    'datos_relevantes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    pagoNominaId,
    fechaHora,
    tipoEvento,
    estadoAnterior,
    estadoNuevo,
    observacion,
    actor,
    datosRelevantes,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pago_nomina_evento';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  PagoNominaEvento createAlias(String alias) {
    return PagoNominaEvento(attachedDatabase, alias);
  }
}

class PagoNominaAttachment extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  PagoNominaAttachment(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> attachmentId = GeneratedColumn<String>(
    'attachment_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES attachment (id) ON DELETE CASCADE',
    ),
  );
  late final GeneratedColumn<String> pagoNominaId = GeneratedColumn<String>(
    'pago_nomina_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES pago_nomina (id) ON DELETE CASCADE',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [attachmentId, pagoNominaId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pago_nomina_attachment';
  @override
  Set<GeneratedColumn> get $primaryKey => {attachmentId};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  PagoNominaAttachment createAlias(String alias) {
    return PagoNominaAttachment(attachedDatabase, alias);
  }
}

class CategoriaArticulo extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  CategoriaArticulo(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<String> cicloVidaRegistro =
      GeneratedColumn<String>(
        'ciclo_vida_registro',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('activo'),
      );
  late final GeneratedColumn<String> nombre = GeneratedColumn<String>(
    'nombre',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    createdAt,
    updatedAt,
    cicloVidaRegistro,
    nombre,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'categoria_articulo';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  CategoriaArticulo createAlias(String alias) {
    return CategoriaArticulo(attachedDatabase, alias);
  }
}

class Articulo extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Articulo(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<String> cicloVidaRegistro =
      GeneratedColumn<String>(
        'ciclo_vida_registro',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('activo'),
      );
  late final GeneratedColumn<String> folio = GeneratedColumn<String>(
    'folio',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  late final GeneratedColumn<String> categoriaId = GeneratedColumn<String>(
    'categoria_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES categoria_articulo (id) ON DELETE RESTRICT',
    ),
  );
  late final GeneratedColumn<String> nombre = GeneratedColumn<String>(
    'nombre',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> descripcion = GeneratedColumn<String>(
    'descripcion',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> unidadMedida = GeneratedColumn<String>(
    'unidad_medida',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<bool> manejaVariante = GeneratedColumn<bool>(
    'maneja_variante',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("maneja_variante" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  late final GeneratedColumn<bool> manejaSerie = GeneratedColumn<bool>(
    'maneja_serie',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("maneja_serie" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  late final GeneratedColumn<int> costoReferencia = GeneratedColumn<int>(
    'costo_referencia',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    createdAt,
    updatedAt,
    cicloVidaRegistro,
    folio,
    categoriaId,
    nombre,
    descripcion,
    unidadMedida,
    manejaVariante,
    manejaSerie,
    costoReferencia,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'articulo';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  Articulo createAlias(String alias) {
    return Articulo(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'CHECK (costo_referencia IS NULL OR costo_referencia >= 0)',
  ];
}

class ArticuloVariante extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  ArticuloVariante(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<String> cicloVidaRegistro =
      GeneratedColumn<String>(
        'ciclo_vida_registro',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('activo'),
      );
  late final GeneratedColumn<String> articuloId = GeneratedColumn<String>(
    'articulo_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES articulo (id) ON DELETE RESTRICT',
    ),
  );
  late final GeneratedColumn<String> valor = GeneratedColumn<String>(
    'valor',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    createdAt,
    updatedAt,
    cicloVidaRegistro,
    articuloId,
    valor,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'articulo_variante';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  ArticuloVariante createAlias(String alias) {
    return ArticuloVariante(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const ['UNIQUE (articulo_id, valor)'];
}

class ArticuloUnidad extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  ArticuloUnidad(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<String> cicloVidaRegistro =
      GeneratedColumn<String>(
        'ciclo_vida_registro',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('activo'),
      );
  late final GeneratedColumn<String> codigo = GeneratedColumn<String>(
    'codigo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  late final GeneratedColumn<String> articuloId = GeneratedColumn<String>(
    'articulo_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES articulo (id) ON DELETE RESTRICT',
    ),
  );
  late final GeneratedColumn<String> numeroSerie = GeneratedColumn<String>(
    'numero_serie',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  late final GeneratedColumn<String> marca = GeneratedColumn<String>(
    'marca',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> modelo = GeneratedColumn<String>(
    'modelo',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> estatus = GeneratedColumn<String>(
    'estatus',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('disponible'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    createdAt,
    updatedAt,
    cicloVidaRegistro,
    codigo,
    articuloId,
    numeroSerie,
    marca,
    modelo,
    estatus,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'articulo_unidad';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  ArticuloUnidad createAlias(String alias) {
    return ArticuloUnidad(attachedDatabase, alias);
  }
}

class ArticuloUnidadTelefono extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  ArticuloUnidadTelefono(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> unidadId = GeneratedColumn<String>(
    'unidad_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES articulo_unidad (id) ON DELETE CASCADE',
    ),
  );
  late final GeneratedColumn<String> imei = GeneratedColumn<String>(
    'imei',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> numeroTelefonico = GeneratedColumn<String>(
    'numero_telefonico',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [unidadId, imei, numeroTelefonico];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'articulo_unidad_telefono';
  @override
  Set<GeneratedColumn> get $primaryKey => {unidadId};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  ArticuloUnidadTelefono createAlias(String alias) {
    return ArticuloUnidadTelefono(attachedDatabase, alias);
  }
}

class MovimientoInventario extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  MovimientoInventario(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<String> cicloVidaRegistro =
      GeneratedColumn<String>(
        'ciclo_vida_registro',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('activo'),
      );
  late final GeneratedColumn<String> articuloId = GeneratedColumn<String>(
    'articulo_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES articulo (id) ON DELETE RESTRICT',
    ),
  );
  late final GeneratedColumn<String> varianteId = GeneratedColumn<String>(
    'variante_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES articulo_variante (id) ON DELETE RESTRICT',
    ),
  );
  late final GeneratedColumn<String> unidadId = GeneratedColumn<String>(
    'unidad_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES articulo_unidad (id) ON DELETE RESTRICT',
    ),
  );
  late final GeneratedColumn<int> cantidad = GeneratedColumn<int>(
    'cantidad',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> tipoMovimiento = GeneratedColumn<String>(
    'tipo_movimiento',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<DateTime> fecha = GeneratedColumn<DateTime>(
    'fecha',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<int> costoUnitario = GeneratedColumn<int>(
    'costo_unitario',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> observaciones = GeneratedColumn<String>(
    'observaciones',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> actor = GeneratedColumn<String>(
    'actor',
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
    articuloId,
    varianteId,
    unidadId,
    cantidad,
    tipoMovimiento,
    fecha,
    costoUnitario,
    observaciones,
    actor,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'movimiento_inventario';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  MovimientoInventario createAlias(String alias) {
    return MovimientoInventario(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'CHECK (variante_id IS NULL OR unidad_id IS NULL)',
    'CHECK (cantidad > 0)',
    'CHECK (unidad_id IS NULL OR cantidad = 1)',
    'CHECK (costo_unitario IS NULL OR costo_unitario >= 0)',
  ];
}

class MovimientoInventarioAttachment extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  MovimientoInventarioAttachment(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> attachmentId = GeneratedColumn<String>(
    'attachment_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES attachment (id) ON DELETE CASCADE',
    ),
  );
  late final GeneratedColumn<String> movimientoInventarioId =
      GeneratedColumn<String>(
        'movimiento_inventario_id',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES movimiento_inventario (id) ON DELETE CASCADE',
        ),
      );
  @override
  List<GeneratedColumn> get $columns => [attachmentId, movimientoInventarioId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'movimiento_inventario_attachment';
  @override
  Set<GeneratedColumn> get $primaryKey => {attachmentId};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  MovimientoInventarioAttachment createAlias(String alias) {
    return MovimientoInventarioAttachment(attachedDatabase, alias);
  }
}

class Asignacion extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Asignacion(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<String> cicloVidaRegistro =
      GeneratedColumn<String>(
        'ciclo_vida_registro',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('activo'),
      );
  late final GeneratedColumn<String> articuloId = GeneratedColumn<String>(
    'articulo_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES articulo (id) ON DELETE RESTRICT',
    ),
  );
  late final GeneratedColumn<String> varianteId = GeneratedColumn<String>(
    'variante_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES articulo_variante (id) ON DELETE RESTRICT',
    ),
  );
  late final GeneratedColumn<String> unidadId = GeneratedColumn<String>(
    'unidad_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES articulo_unidad (id) ON DELETE RESTRICT',
    ),
  );
  late final GeneratedColumn<int> cantidad = GeneratedColumn<int>(
    'cantidad',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> empleadoId = GeneratedColumn<String>(
    'empleado_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES empleado (id) ON DELETE RESTRICT',
    ),
  );
  late final GeneratedColumn<String> servicioId = GeneratedColumn<String>(
    'servicio_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES servicio (id) ON DELETE RESTRICT',
    ),
  );
  late final GeneratedColumn<DateTime> fechaEntrega = GeneratedColumn<DateTime>(
    'fecha_entrega',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> condicionEntrega = GeneratedColumn<String>(
    'condicion_entrega',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> observaciones = GeneratedColumn<String>(
    'observaciones',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> estatus = GeneratedColumn<String>(
    'estatus',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('activa'),
  );
  late final GeneratedColumn<DateTime> fechaCierre = GeneratedColumn<DateTime>(
    'fecha_cierre',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> motivoCierre = GeneratedColumn<String>(
    'motivo_cierre',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> observacionesCierre =
      GeneratedColumn<String>(
        'observaciones_cierre',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  late final GeneratedColumn<bool> atribuibleAlEmpleado = GeneratedColumn<bool>(
    'atribuible_al_empleado',
    aliasedName,
    true,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("atribuible_al_empleado" IN (0, 1))',
    ),
  );
  late final GeneratedColumn<String> asignacionReemplazoId =
      GeneratedColumn<String>(
        'asignacion_reemplazo_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES asignacion (id) ON DELETE RESTRICT',
        ),
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    createdAt,
    updatedAt,
    cicloVidaRegistro,
    articuloId,
    varianteId,
    unidadId,
    cantidad,
    empleadoId,
    servicioId,
    fechaEntrega,
    condicionEntrega,
    observaciones,
    estatus,
    fechaCierre,
    motivoCierre,
    observacionesCierre,
    atribuibleAlEmpleado,
    asignacionReemplazoId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'asignacion';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  Asignacion createAlias(String alias) {
    return Asignacion(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'CHECK ((empleado_id IS NOT NULL AND servicio_id IS NULL) OR (empleado_id IS NULL AND servicio_id IS NOT NULL))',
    'CHECK (variante_id IS NULL OR unidad_id IS NULL)',
    'CHECK (cantidad > 0)',
    'CHECK (unidad_id IS NULL OR cantidad = 1)',
    'CHECK ((estatus = \'activa\' AND fecha_cierre IS NULL) OR (estatus != \'activa\' AND fecha_cierre IS NOT NULL))',
    'CHECK (fecha_cierre IS NULL OR fecha_cierre >= fecha_entrega)',
    'CHECK (atribuible_al_empleado IS NULL OR estatus = \'danada\' OR estatus = \'perdida\')',
  ];
}

class DescuentoInventario extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  DescuentoInventario(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<String> cicloVidaRegistro =
      GeneratedColumn<String>(
        'ciclo_vida_registro',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('activo'),
      );
  late final GeneratedColumn<String> asignacionId = GeneratedColumn<String>(
    'asignacion_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES asignacion (id) ON DELETE RESTRICT',
    ),
  );
  late final GeneratedColumn<String> empleadoId = GeneratedColumn<String>(
    'empleado_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES empleado (id) ON DELETE RESTRICT',
    ),
  );
  late final GeneratedColumn<String> motivo = GeneratedColumn<String>(
    'motivo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<int> importe = GeneratedColumn<int>(
    'importe',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> estatus = GeneratedColumn<String>(
    'estatus',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pendiente'),
  );
  late final GeneratedColumn<DateTime> fechaAplicacion =
      GeneratedColumn<DateTime>(
        'fecha_aplicacion',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
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
    asignacionId,
    empleadoId,
    motivo,
    importe,
    estatus,
    fechaAplicacion,
    observaciones,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'descuento_inventario';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  DescuentoInventario createAlias(String alias) {
    return DescuentoInventario(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const ['CHECK (importe > 0)'];
}

class AsignacionAttachment extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  AsignacionAttachment(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> attachmentId = GeneratedColumn<String>(
    'attachment_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES attachment (id) ON DELETE CASCADE',
    ),
  );
  late final GeneratedColumn<String> asignacionId = GeneratedColumn<String>(
    'asignacion_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES asignacion (id) ON DELETE CASCADE',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [attachmentId, asignacionId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'asignacion_attachment';
  @override
  Set<GeneratedColumn> get $primaryKey => {attachmentId, asignacionId};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  AsignacionAttachment createAlias(String alias) {
    return AsignacionAttachment(attachedDatabase, alias);
  }
}

class Vehiculo extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Vehiculo(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<String> cicloVidaRegistro =
      GeneratedColumn<String>(
        'ciclo_vida_registro',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('activo'),
      );
  late final GeneratedColumn<String> codigo = GeneratedColumn<String>(
    'codigo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  late final GeneratedColumn<String> marca = GeneratedColumn<String>(
    'marca',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> modelo = GeneratedColumn<String>(
    'modelo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<int> anio = GeneratedColumn<int>(
    'anio',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> color = GeneratedColumn<String>(
    'color',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> placas = GeneratedColumn<String>(
    'placas',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> vin = GeneratedColumn<String>(
    'vin',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> numeroMotor = GeneratedColumn<String>(
    'numero_motor',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> tipoVehiculo = GeneratedColumn<String>(
    'tipo_vehiculo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> estatus = GeneratedColumn<String>(
    'estatus',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('disponible'),
  );
  late final GeneratedColumn<DateTime> fechaAdquisicion =
      GeneratedColumn<DateTime>(
        'fecha_adquisicion',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  late final GeneratedColumn<int> costoAdquisicion = GeneratedColumn<int>(
    'costo_adquisicion',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> observaciones = GeneratedColumn<String>(
    'observaciones',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> fotografiaAttachmentId =
      GeneratedColumn<String>(
        'fotografia_attachment_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES attachment (id) ON DELETE RESTRICT',
        ),
      );
  late final GeneratedColumn<DateTime> fechaBaja = GeneratedColumn<DateTime>(
    'fecha_baja',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> motivoBaja = GeneratedColumn<String>(
    'motivo_baja',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> observacionesBaja =
      GeneratedColumn<String>(
        'observaciones_baja',
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
    marca,
    modelo,
    anio,
    color,
    placas,
    vin,
    numeroMotor,
    tipoVehiculo,
    estatus,
    fechaAdquisicion,
    costoAdquisicion,
    observaciones,
    fotografiaAttachmentId,
    fechaBaja,
    motivoBaja,
    observacionesBaja,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'vehiculo';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  Vehiculo createAlias(String alias) {
    return Vehiculo(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'CHECK (costo_adquisicion IS NULL OR costo_adquisicion >= 0)',
    'CHECK ((estatus = \'baja\' AND fecha_baja IS NOT NULL) OR (estatus != \'baja\' AND fecha_baja IS NULL))',
  ];
}

class VehiculoAttachment extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  VehiculoAttachment(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> attachmentId = GeneratedColumn<String>(
    'attachment_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES attachment (id) ON DELETE CASCADE',
    ),
  );
  late final GeneratedColumn<String> vehiculoId = GeneratedColumn<String>(
    'vehiculo_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES vehiculo (id) ON DELETE CASCADE',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [attachmentId, vehiculoId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'vehiculo_attachment';
  @override
  Set<GeneratedColumn> get $primaryKey => {attachmentId};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  VehiculoAttachment createAlias(String alias) {
    return VehiculoAttachment(attachedDatabase, alias);
  }
}

class AsignacionVehiculo extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  AsignacionVehiculo(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<String> cicloVidaRegistro =
      GeneratedColumn<String>(
        'ciclo_vida_registro',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('activo'),
      );
  late final GeneratedColumn<String> vehiculoId = GeneratedColumn<String>(
    'vehiculo_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES vehiculo (id) ON DELETE RESTRICT',
    ),
  );
  late final GeneratedColumn<String> empleadoId = GeneratedColumn<String>(
    'empleado_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES empleado (id) ON DELETE RESTRICT',
    ),
  );
  late final GeneratedColumn<String> servicioId = GeneratedColumn<String>(
    'servicio_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES servicio (id) ON DELETE RESTRICT',
    ),
  );
  late final GeneratedColumn<DateTime> fechaInicio = GeneratedColumn<DateTime>(
    'fecha_inicio',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<DateTime> fechaTermino = GeneratedColumn<DateTime>(
    'fecha_termino',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> motivoTermino = GeneratedColumn<String>(
    'motivo_termino',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> observaciones = GeneratedColumn<String>(
    'observaciones',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> observacionesTermino =
      GeneratedColumn<String>(
        'observaciones_termino',
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
    vehiculoId,
    empleadoId,
    servicioId,
    fechaInicio,
    fechaTermino,
    motivoTermino,
    observaciones,
    observacionesTermino,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'asignacion_vehiculo';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  AsignacionVehiculo createAlias(String alias) {
    return AsignacionVehiculo(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'CHECK ((empleado_id IS NOT NULL AND servicio_id IS NULL) OR (empleado_id IS NULL AND servicio_id IS NOT NULL))',
    'CHECK (fecha_termino IS NULL OR fecha_termino >= fecha_inicio)',
  ];
}

class VehiculoKilometraje extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  VehiculoKilometraje(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<String> cicloVidaRegistro =
      GeneratedColumn<String>(
        'ciclo_vida_registro',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('activo'),
      );
  late final GeneratedColumn<String> vehiculoId = GeneratedColumn<String>(
    'vehiculo_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES vehiculo (id) ON DELETE RESTRICT',
    ),
  );
  late final GeneratedColumn<DateTime> fecha = GeneratedColumn<DateTime>(
    'fecha',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<int> kilometraje = GeneratedColumn<int>(
    'kilometraje',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> origen = GeneratedColumn<String>(
    'origen',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> observaciones = GeneratedColumn<String>(
    'observaciones',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> actor = GeneratedColumn<String>(
    'actor',
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
    vehiculoId,
    fecha,
    kilometraje,
    origen,
    observaciones,
    actor,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'vehiculo_kilometraje';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  VehiculoKilometraje createAlias(String alias) {
    return VehiculoKilometraje(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const ['CHECK (kilometraje >= 0)'];
}

class VehiculoDocumento extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  VehiculoDocumento(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<String> cicloVidaRegistro =
      GeneratedColumn<String>(
        'ciclo_vida_registro',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('activo'),
      );
  late final GeneratedColumn<String> vehiculoId = GeneratedColumn<String>(
    'vehiculo_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES vehiculo (id) ON DELETE RESTRICT',
    ),
  );
  late final GeneratedColumn<String> tipo = GeneratedColumn<String>(
    'tipo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> tipoOtroDescripcion =
      GeneratedColumn<String>(
        'tipo_otro_descripcion',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  late final GeneratedColumn<String> numeroFolio = GeneratedColumn<String>(
    'numero_folio',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<DateTime> fechaEmision = GeneratedColumn<DateTime>(
    'fecha_emision',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<DateTime> fechaVencimiento =
      GeneratedColumn<DateTime>(
        'fecha_vencimiento',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
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
    vehiculoId,
    tipo,
    tipoOtroDescripcion,
    numeroFolio,
    fechaEmision,
    fechaVencimiento,
    observaciones,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'vehiculo_documento';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  VehiculoDocumento createAlias(String alias) {
    return VehiculoDocumento(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'CHECK (fecha_vencimiento IS NULL OR fecha_emision IS NULL OR fecha_vencimiento >= fecha_emision)',
  ];
}

class VehiculoDocumentoAttachment extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  VehiculoDocumentoAttachment(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> attachmentId = GeneratedColumn<String>(
    'attachment_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES attachment (id) ON DELETE CASCADE',
    ),
  );
  late final GeneratedColumn<String> vehiculoDocumentoId =
      GeneratedColumn<String>(
        'vehiculo_documento_id',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES vehiculo_documento (id) ON DELETE CASCADE',
        ),
      );
  @override
  List<GeneratedColumn> get $columns => [attachmentId, vehiculoDocumentoId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'vehiculo_documento_attachment';
  @override
  Set<GeneratedColumn> get $primaryKey => {attachmentId};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  VehiculoDocumentoAttachment createAlias(String alias) {
    return VehiculoDocumentoAttachment(attachedDatabase, alias);
  }
}

class VehiculoMantenimiento extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  VehiculoMantenimiento(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  late final GeneratedColumn<String> cicloVidaRegistro =
      GeneratedColumn<String>(
        'ciclo_vida_registro',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('activo'),
      );
  late final GeneratedColumn<String> vehiculoId = GeneratedColumn<String>(
    'vehiculo_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES vehiculo (id) ON DELETE RESTRICT',
    ),
  );
  late final GeneratedColumn<DateTime> fecha = GeneratedColumn<DateTime>(
    'fecha',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<int> kilometraje = GeneratedColumn<int>(
    'kilometraje',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> tipo = GeneratedColumn<String>(
    'tipo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> descripcion = GeneratedColumn<String>(
    'descripcion',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> tallerProveedor = GeneratedColumn<String>(
    'taller_proveedor',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<int> costo = GeneratedColumn<int>(
    'costo',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<DateTime> proximoMantenimientoFecha =
      GeneratedColumn<DateTime>(
        'proximo_mantenimiento_fecha',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  late final GeneratedColumn<int> proximoMantenimientoKilometraje =
      GeneratedColumn<int>(
        'proximo_mantenimiento_kilometraje',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      );
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
    vehiculoId,
    fecha,
    kilometraje,
    tipo,
    descripcion,
    tallerProveedor,
    costo,
    proximoMantenimientoFecha,
    proximoMantenimientoKilometraje,
    observaciones,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'vehiculo_mantenimiento';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  VehiculoMantenimiento createAlias(String alias) {
    return VehiculoMantenimiento(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'CHECK (kilometraje IS NULL OR kilometraje >= 0)',
    'CHECK (costo IS NULL OR costo >= 0)',
    'CHECK (proximo_mantenimiento_kilometraje IS NULL OR proximo_mantenimiento_kilometraje >= 0)',
    'CHECK (proximo_mantenimiento_fecha IS NULL OR proximo_mantenimiento_fecha >= fecha)',
  ];
}

class VehiculoMantenimientoAttachment extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  VehiculoMantenimientoAttachment(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> attachmentId = GeneratedColumn<String>(
    'attachment_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES attachment (id) ON DELETE CASCADE',
    ),
  );
  late final GeneratedColumn<String> vehiculoMantenimientoId =
      GeneratedColumn<String>(
        'vehiculo_mantenimiento_id',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES vehiculo_mantenimiento (id) ON DELETE CASCADE',
        ),
      );
  @override
  List<GeneratedColumn> get $columns => [attachmentId, vehiculoMantenimientoId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'vehiculo_mantenimiento_attachment';
  @override
  Set<GeneratedColumn> get $primaryKey => {attachmentId};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  VehiculoMantenimientoAttachment createAlias(String alias) {
    return VehiculoMantenimientoAttachment(attachedDatabase, alias);
  }
}

class DatabaseAtV33 extends GeneratedDatabase {
  DatabaseAtV33(QueryExecutor e) : super(e);
  late final AppMetadata appMetadata = AppMetadata(this);
  late final CodigoSecuencia codigoSecuencia = CodigoSecuencia(this);
  late final TipoSucursal tipoSucursal = TipoSucursal(this);
  late final Industria industria = Industria(this);
  late final TipoServicio tipoServicio = TipoServicio(this);
  late final Area area = Area(this);
  late final TipoModalidadTurno tipoModalidadTurno = TipoModalidadTurno(this);
  late final TipoFrecuenciaCobro tipoFrecuenciaCobro = TipoFrecuenciaCobro(
    this,
  );
  late final Banco banco = Banco(this);
  late final Direccion direccion = Direccion(this);
  late final MedioContacto medioContacto = MedioContacto(this);
  late final Attachment attachment = Attachment(this);
  late final Horario horario = Horario(this);
  late final HorarioDetalle horarioDetalle = HorarioDetalle(this);
  late final Empresa empresa = Empresa(this);
  late final Sucursal sucursal = Sucursal(this);
  late final Cliente cliente = Cliente(this);
  late final Contacto contacto = Contacto(this);
  late final EntidadFiscal entidadFiscal = EntidadFiscal(this);
  late final Servicio servicio = Servicio(this);
  late final Ubicacion ubicacion = Ubicacion(this);
  late final Puesto puesto = Puesto(this);
  late final ServicioLineaComercial servicioLineaComercial =
      ServicioLineaComercial(this);
  late final ServicioLineaComercialVigencia servicioLineaComercialVigencia =
      ServicioLineaComercialVigencia(this);
  late final ConfiguracionCobro configuracionCobro = ConfiguracionCobro(this);
  late final ConfiguracionCobroVigencia configuracionCobroVigencia =
      ConfiguracionCobroVigencia(this);
  late final ConfiguracionCobroCorreo configuracionCobroCorreo =
      ConfiguracionCobroCorreo(this);
  late final ConfiguracionCobroReglaEvento configuracionCobroReglaEvento =
      ConfiguracionCobroReglaEvento(this);
  late final DocumentoPorEmitir documentoPorEmitir = DocumentoPorEmitir(this);
  late final DocumentoPorEmitirServicio documentoPorEmitirServicio =
      DocumentoPorEmitirServicio(this);
  late final DocumentoPorEmitirConfiguracion documentoPorEmitirConfiguracion =
      DocumentoPorEmitirConfiguracion(this);
  late final DocumentoPorEmitirLinea documentoPorEmitirLinea =
      DocumentoPorEmitirLinea(this);
  late final DocumentoPorEmitirCorreo documentoPorEmitirCorreo =
      DocumentoPorEmitirCorreo(this);
  late final DocumentoPorEmitirCorreoEnvio documentoPorEmitirCorreoEnvio =
      DocumentoPorEmitirCorreoEnvio(this);
  late final DocumentoPorEmitirEvento documentoPorEmitirEvento =
      DocumentoPorEmitirEvento(this);
  late final CuentaPorCobrar cuentaPorCobrar = CuentaPorCobrar(this);
  late final CuentaPorCobrarEvento cuentaPorCobrarEvento =
      CuentaPorCobrarEvento(this);
  late final Pago pago = Pago(this);
  late final AplicacionPago aplicacionPago = AplicacionPago(this);
  late final PagoEvento pagoEvento = PagoEvento(this);
  late final ComplementoPago complementoPago = ComplementoPago(this);
  late final ComplementoPagoEvento complementoPagoEvento =
      ComplementoPagoEvento(this);
  late final CategoriaFinanciera categoriaFinanciera = CategoriaFinanciera(
    this,
  );
  late final Ingreso ingreso = Ingreso(this);
  late final IngresoEvento ingresoEvento = IngresoEvento(this);
  late final Egreso egreso = Egreso(this);
  late final EgresoEvento egresoEvento = EgresoEvento(this);
  late final Empleado empleado = Empleado(this);
  late final EmpleadoEvento empleadoEvento = EmpleadoEvento(this);
  late final EmpleadoPeriodoLaboral empleadoPeriodoLaboral =
      EmpleadoPeriodoLaboral(this);
  late final AsignacionServicio asignacionServicio = AsignacionServicio(this);
  late final AsignacionServicioSueldoVigencia asignacionServicioSueldoVigencia =
      AsignacionServicioSueldoVigencia(this);
  late final FichaTecnicaEmpleado fichaTecnicaEmpleado = FichaTecnicaEmpleado(
    this,
  );
  late final EmpresaAttachment empresaAttachment = EmpresaAttachment(this);
  late final ClienteAttachment clienteAttachment = ClienteAttachment(this);
  late final DocumentoPorEmitirAttachment documentoPorEmitirAttachment =
      DocumentoPorEmitirAttachment(this);
  late final PagoAttachment pagoAttachment = PagoAttachment(this);
  late final ComplementoPagoAttachment complementoPagoAttachment =
      ComplementoPagoAttachment(this);
  late final IngresoAttachment ingresoAttachment = IngresoAttachment(this);
  late final EgresoAttachment egresoAttachment = EgresoAttachment(this);
  late final EmpleadoAttachment empleadoAttachment = EmpleadoAttachment(this);
  late final Nomina nomina = Nomina(this);
  late final NominaEmpleado nominaEmpleado = NominaEmpleado(this);
  late final NominaEmpleadoTramo nominaEmpleadoTramo = NominaEmpleadoTramo(
    this,
  );
  late final NominaEvento nominaEvento = NominaEvento(this);
  late final PagoNomina pagoNomina = PagoNomina(this);
  late final AplicacionPagoNomina aplicacionPagoNomina = AplicacionPagoNomina(
    this,
  );
  late final PagoNominaEvento pagoNominaEvento = PagoNominaEvento(this);
  late final PagoNominaAttachment pagoNominaAttachment = PagoNominaAttachment(
    this,
  );
  late final CategoriaArticulo categoriaArticulo = CategoriaArticulo(this);
  late final Articulo articulo = Articulo(this);
  late final ArticuloVariante articuloVariante = ArticuloVariante(this);
  late final ArticuloUnidad articuloUnidad = ArticuloUnidad(this);
  late final ArticuloUnidadTelefono articuloUnidadTelefono =
      ArticuloUnidadTelefono(this);
  late final MovimientoInventario movimientoInventario = MovimientoInventario(
    this,
  );
  late final MovimientoInventarioAttachment movimientoInventarioAttachment =
      MovimientoInventarioAttachment(this);
  late final Asignacion asignacion = Asignacion(this);
  late final DescuentoInventario descuentoInventario = DescuentoInventario(
    this,
  );
  late final AsignacionAttachment asignacionAttachment = AsignacionAttachment(
    this,
  );
  late final Vehiculo vehiculo = Vehiculo(this);
  late final VehiculoAttachment vehiculoAttachment = VehiculoAttachment(this);
  late final AsignacionVehiculo asignacionVehiculo = AsignacionVehiculo(this);
  late final VehiculoKilometraje vehiculoKilometraje = VehiculoKilometraje(
    this,
  );
  late final VehiculoDocumento vehiculoDocumento = VehiculoDocumento(this);
  late final VehiculoDocumentoAttachment vehiculoDocumentoAttachment =
      VehiculoDocumentoAttachment(this);
  late final VehiculoMantenimiento vehiculoMantenimiento =
      VehiculoMantenimiento(this);
  late final VehiculoMantenimientoAttachment vehiculoMantenimientoAttachment =
      VehiculoMantenimientoAttachment(this);
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
  late final Index idxContactoClienteTipoPrincipalActivo = Index(
    'idx_contacto_cliente_tipo_principal_activo',
    'CREATE UNIQUE INDEX idx_contacto_cliente_tipo_principal_activo ON contacto (cliente_id, tipo) WHERE es_principal = 1 AND ciclo_vida_registro = \'activo\'',
  );
  late final Index idxAsignacionServicioEmpleadoActiva = Index(
    'idx_asignacion_servicio_empleado_activa',
    'CREATE UNIQUE INDEX idx_asignacion_servicio_empleado_activa ON asignacion_servicio (empleado_id) WHERE fecha_termino IS NULL',
  );
  late final Index idxAsignacionUnidadActiva = Index(
    'idx_asignacion_unidad_activa',
    'CREATE UNIQUE INDEX idx_asignacion_unidad_activa ON asignacion (unidad_id) WHERE unidad_id IS NOT NULL AND estatus = \'activa\'',
  );
  late final Index idxVehiculoPlacasUnica = Index(
    'idx_vehiculo_placas_unica',
    'CREATE UNIQUE INDEX idx_vehiculo_placas_unica ON vehiculo (placas) WHERE placas IS NOT NULL',
  );
  late final Index idxVehiculoVinUnico = Index(
    'idx_vehiculo_vin_unico',
    'CREATE UNIQUE INDEX idx_vehiculo_vin_unico ON vehiculo (vin) WHERE vin IS NOT NULL',
  );
  late final Index idxAsignacionVehiculoVigente = Index(
    'idx_asignacion_vehiculo_vigente',
    'CREATE UNIQUE INDEX idx_asignacion_vehiculo_vigente ON asignacion_vehiculo (vehiculo_id) WHERE fecha_termino IS NULL',
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
    tipoModalidadTurno,
    tipoFrecuenciaCobro,
    banco,
    direccion,
    medioContacto,
    attachment,
    horario,
    horarioDetalle,
    empresa,
    sucursal,
    cliente,
    contacto,
    entidadFiscal,
    servicio,
    ubicacion,
    puesto,
    servicioLineaComercial,
    servicioLineaComercialVigencia,
    configuracionCobro,
    configuracionCobroVigencia,
    configuracionCobroCorreo,
    configuracionCobroReglaEvento,
    documentoPorEmitir,
    documentoPorEmitirServicio,
    documentoPorEmitirConfiguracion,
    documentoPorEmitirLinea,
    documentoPorEmitirCorreo,
    documentoPorEmitirCorreoEnvio,
    documentoPorEmitirEvento,
    cuentaPorCobrar,
    cuentaPorCobrarEvento,
    pago,
    aplicacionPago,
    pagoEvento,
    complementoPago,
    complementoPagoEvento,
    categoriaFinanciera,
    ingreso,
    ingresoEvento,
    egreso,
    egresoEvento,
    empleado,
    empleadoEvento,
    empleadoPeriodoLaboral,
    asignacionServicio,
    asignacionServicioSueldoVigencia,
    fichaTecnicaEmpleado,
    empresaAttachment,
    clienteAttachment,
    documentoPorEmitirAttachment,
    pagoAttachment,
    complementoPagoAttachment,
    ingresoAttachment,
    egresoAttachment,
    empleadoAttachment,
    nomina,
    nominaEmpleado,
    nominaEmpleadoTramo,
    nominaEvento,
    pagoNomina,
    aplicacionPagoNomina,
    pagoNominaEvento,
    pagoNominaAttachment,
    categoriaArticulo,
    articulo,
    articuloVariante,
    articuloUnidad,
    articuloUnidadTelefono,
    movimientoInventario,
    movimientoInventarioAttachment,
    asignacion,
    descuentoInventario,
    asignacionAttachment,
    vehiculo,
    vehiculoAttachment,
    asignacionVehiculo,
    vehiculoKilometraje,
    vehiculoDocumento,
    vehiculoDocumentoAttachment,
    vehiculoMantenimiento,
    vehiculoMantenimientoAttachment,
    idxDireccionClienteTipoPrincipal,
    idxDireccionCliente,
    idxEmpresaActivaUnica,
    idxContactoClienteTipoPrincipalActivo,
    idxAsignacionServicioEmpleadoActiva,
    idxAsignacionUnidadActiva,
    idxVehiculoPlacasUnica,
    idxVehiculoVinUnico,
    idxAsignacionVehiculoVigente,
  ];
  @override
  int get schemaVersion => 33;
}
