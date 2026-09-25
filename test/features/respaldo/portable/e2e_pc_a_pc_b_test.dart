// Etapa 4D — el criterio real de éxito.
//
// PC A muere. Sólo queda un archivo `.risegbkp`. En PC B se instala RISEG
// ONE desde cero y se recupera todo: la base, los adjuntos, los usuarios
// y —esto es lo que no existía antes de 4D— la capacidad de **descifrar**
// Bóveda, Telefonía y Portal del Cliente.
//
// Estas pruebas no comparten nada entre A y B: carpetas distintas, base
// distinta y Almacén de Credenciales distinto. Si algo de PC A hiciera
// falta para abrir el paquete, aquí no estaría.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/security/almacen_ranuras_clave.dart';
import 'package:riseg_one/core/security/credential_cipher.dart';
import 'package:riseg_one/features/respaldo/data/repositories/configuracion_recuperacion_repository_impl.dart';
import 'package:riseg_one/features/respaldo/domain/portable/configurar_recuperacion_usecase.dart';
import 'package:riseg_one/features/respaldo/domain/portable/contenedor_portable.dart';
import 'package:riseg_one/features/respaldo/domain/portable/coordinador_restauracion_portable.dart';
import 'package:riseg_one/features/respaldo/domain/portable/crear_respaldo_portable_usecase.dart';
import 'package:riseg_one/features/respaldo/domain/portable/evaluador_instalacion.dart';
import 'package:riseg_one/features/respaldo/domain/portable/kdf_portable.dart';
import 'package:riseg_one/features/respaldo/domain/portable/sobre_portable.dart';
import 'package:riseg_one/features/respaldo/domain/portable/validador_base_restaurada.dart';
import 'package:riseg_one/features/respaldo/domain/portable/verificar_respaldo_portable_usecase.dart';
import 'package:riseg_one/features/respaldo/domain/usecases/aplicar_restauracion_pendiente_usecase.dart';
import 'package:riseg_one/features/respaldo/domain/usecases/crear_respaldo_usecase.dart';
import 'package:riseg_one/features/respaldo/domain/usecases/preparar_restauracion_usecase.dart';
import 'package:riseg_one/features/respaldo/domain/usecases/validar_paquete_respaldo_usecase.dart';

/// Argon2 de mentira, compartido por creación y restauración: estas
/// pruebas miden el recorrido, no el coste del KDF.
class _Argon2Rapido implements GeneradorArgon2 {
  @override
  Uint8List derivar({required Uint8List secreto, required ParametrosArgon2id parametros}) {
    final salida = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      salida[i] = (secreto.isEmpty ? 7 : secreto[i % secreto.length]) ^ parametros.salt[i % parametros.salt.length] ^ i;
    }
    return salida;
  }
}

class _AlmacenClave implements AlmacenClaveCifrado {
  _AlmacenClave();
  String? valor;
  @override
  Future<String?> leer() async => valor;
  @override
  Future<void> escribir(String v) async => valor = v;
}

/// Ranuras en memoria: el Almacén de Credenciales de un equipo concreto.
class _Ranuras implements AlmacenRanurasClave {
  final Map<RanuraClave, Uint8List> valores = {};
  @override
  Future<Uint8List?> leer(RanuraClave r) async => valores[r];
  @override
  Future<void> escribir(RanuraClave r, Uint8List c) async => valores[r] = Uint8List.fromList(c);
  @override
  Future<void> borrar(RanuraClave r) async => valores.remove(r);
}

const _frase = 'frase de recuperación de la empresa';
const _secretoBoveda = 'contrasena-del-portal-SAT';
const _secretoTelefonia = 'contrasena-del-telefono';
const _secretoPortal = 'contrasena-del-portal-MORGAN';

/// Un equipo: sus carpetas, su base y su Almacén de Credenciales.
class _Equipo {
  _Equipo(this.raiz)
    : databaseFile = p.join(raiz.path, 'riseg_one.sqlite'),
      attachmentsDir = p.join(raiz.path, 'attachments'),
      backupsDir = p.join(raiz.path, 'backups'),
      stagingDir = p.join(raiz.path, 'staging'),
      restorePendingDir = p.join(raiz.path, 'restore_pending'),
      restorePendingMarkerFile = p.join(raiz.path, 'restore_pending.json'),
      restoreOldDir = p.join(raiz.path, 'restore_old');

  final Directory raiz;
  final String databaseFile;
  final String attachmentsDir;
  final String backupsDir;
  final String stagingDir;
  final String restorePendingDir;
  final String restorePendingMarkerFile;
  final String restoreOldDir;

  final _AlmacenClave almacenClave = _AlmacenClave();
  final _Ranuras ranuras = _Ranuras();

  AppDatabase abrirBase() => AppDatabase(openAppDatabaseConnection(databaseFile), almacenClaveCifrado: almacenClave);

  /// Mantiene el Almacén de Credenciales y las ranuras en el mismo
  /// estado, como hacen en producción (la ranura principal *es* la clave
  /// de la aplicación).
  void sincronizarClavePrincipal() {
    final principal = ranuras.valores[RanuraClave.principal];
    almacenClave.valor = principal == null ? null : base64.encode(principal);
  }

  void crearCarpetas() {
    Directory(attachmentsDir).createSync(recursive: true);
    Directory(backupsDir).createSync(recursive: true);
    Directory(stagingDir).createSync(recursive: true);
  }
}

void main() {
  SobrePortable sobre() => SobrePortable(derivador: DerivadorKek(argon2: _Argon2Rapido()));

  ParametrosArgon2id parametrosRapidos() => ParametrosArgon2id(
    memoriaKiB: LimitesArgon2id.memoriaMinimaKiB,
    iteraciones: 1,
    paralelismo: 1,
    salt: Uint8List.fromList(List<int>.generate(16, (i) => i + 3)),
  );

  /// Monta PC A con datos reales y devuelve el paquete portable creado.
  Future<({_Equipo equipo, RecuperacionConfigurada recuperacion, String paquete})> montarPcAyCrearPortable(
    Directory raizA,
  ) async {
    final a = _Equipo(raizA)..crearCarpetas();

    // La clave AES de A, creada al cifrar el primer secreto.
    final cipherA = CredentialCipher(almacen: a.almacenClave);
    final boveda = await cipherA.cifrar(_secretoBoveda);
    final telefonia = await cipherA.cifrar(_secretoTelefonia);
    final portal = await cipherA.cifrar(_secretoPortal);

    final db = a.abrirBase();
    await db.customSelect('SELECT 1').get();
    await db.customStatement(
      'INSERT INTO usuario (id, nombre, nombre_usuario, password_hash, es_maestro, debe_cambiar_password, '
      'ciclo_vida_registro, created_at, updated_at) '
      "VALUES ('u-maestro', 'MARLON', 'MARLONRH', 'pbkdf2\$1000\$s\$h', 1, 0, 'activo', 1700000000, 1700000000)",
    );
    await db.customStatement(
      'INSERT INTO boveda_credencial (id, nombre, tipo, secreto_cifrado, ciclo_vida_registro, created_at, updated_at) '
      "VALUES ('bc-1', 'RISEG - SAT', 'portal', '$boveda', 'activo', 1700000000, 1700000000)",
    );
    await db.customStatement(
      'INSERT INTO categoria_articulo (id, nombre, ciclo_vida_registro, created_at, updated_at) '
      "VALUES ('cat-1', 'Telefonía', 'activo', 1700000000, 1700000000)",
    );
    await db.customStatement(
      'INSERT INTO articulo (id, folio, categoria_id, nombre, ciclo_vida_registro, created_at, updated_at) '
      "VALUES ('art-1', 'ART-001', 'cat-1', 'Teléfono', 'activo', 1700000000, 1700000000)",
    );
    await db.customStatement(
      'INSERT INTO articulo_unidad (id, codigo, articulo_id, numero_serie, estatus, ciclo_vida_registro, '
      'created_at, updated_at) '
      "VALUES ('u-1', 'U-001', 'art-1', 'SN-1', 'disponible', 'activo', 1700000000, 1700000000)",
    );
    await db.customStatement(
      'INSERT INTO equipo_telefonico_credencial (unidad_id, contrasena_cifrada) '
      "VALUES ('u-1', '$telefonia')",
    );
    await db.customStatement(
      'INSERT INTO cliente (id, codigo, nombre_comercial, ciclo_vida_registro, created_at, updated_at) '
      "VALUES ('cli-1', 'CLI-001', 'MORGAN', 'activo', 1700000000, 1700000000)",
    );
    await db.customStatement(
      'INSERT INTO cliente_portal (id, cliente_id, nombre, tipo, contrasena_cifrada, ciclo_vida_registro, '
      'created_at, updated_at) '
      "VALUES ('cp-1', 'cli-1', 'Portal MORGAN', 'facturacion', '$portal', 'activo', 1700000000, 1700000000)",
    );
    // La recuperación se configura **antes** de cerrar la base porque su
    // bloque local vive dentro de la base de A: es parte del estado que el
    // respaldo se lleva, igual que los clientes o la Bóveda.
    final recuperacion = ConfigurarRecuperacionUseCase(
      sobre: sobre(),
    ).ejecutar(frase: _frase, parametros: parametrosRapidos());
    await ConfiguracionRecuperacionRepositoryImpl(db).guardar(recuperacion.configuracion);

    await db.close();

    File(p.join(a.attachmentsDir, 'contrato.pdf')).writeAsStringSync('contrato irremplazable de A');

    final paquete = p.join(raizA.path, 'respaldo_de_A${ContenedorPortable.extension}');
    final creado = await CrearRespaldoPortableUseCase(
      databaseFile: a.databaseFile,
      attachmentsDir: a.attachmentsDir,
      stagingDir: a.stagingDir,
      appVersion: '1.0.0',
      cipher: CredentialCipher(almacen: a.almacenClave),
      sobre: sobre(),
      verificador: VerificarRespaldoPortableUseCase(stagingDir: a.stagingDir, sobre: sobre()),
    ).ejecutar(destino: paquete, frase: _frase, configuracion: recuperacion.configuracion, appSchemaVersion: 93);

    expect(creado, isA<PortableCreado>(), reason: 'PC A tiene que poder crear su respaldo');
    return (equipo: a, recuperacion: recuperacion, paquete: paquete);
  }

  /// Restaura [paquete] en [b] con la credencial indicada, simulando el
  /// reinicio entre preparar y aplicar.
  Future<ResultadoAplicarPortable> restaurarEn(
    _Equipo b,
    String paquete, {
    String? frase,
    String? claveRecuperacionTexto,
  }) async {
    final validador = ValidadorBaseRestaurada(abrirBase: b.abrirBase);

    CoordinadorRestauracionPortable nuevoCoordinador() => CoordinadorRestauracionPortable(
      verificador: VerificarRespaldoPortableUseCase(stagingDir: b.stagingDir, sobre: sobre()),
      preparar: PrepararRestauracionUseCase(
        backupsDir: b.backupsDir,
        restorePendingDir: b.restorePendingDir,
        restorePendingMarkerFile: b.restorePendingMarkerFile,
        validar: ValidarPaqueteRespaldoUseCase(),
        crearRespaldo: CrearRespaldoUseCase(databaseFile: b.databaseFile, attachmentsDir: b.attachmentsDir),
      ),
      aplicar: AplicarRestauracionPendienteUseCase(
        databaseFile: b.databaseFile,
        attachmentsDir: b.attachmentsDir,
        restorePendingDir: b.restorePendingDir,
        restorePendingMarkerFile: b.restorePendingMarkerFile,
        restoreOldDir: b.restoreOldDir,
      ),
      ranuras: b.ranuras,
      stagingDir: b.stagingDir,
      validarBaseRestaurada: validador.validar,
      claveAbreLoRestaurado: validador.claveAbreLoRestaurado,
    );

    final preparado = await nuevoCoordinador().preparar(
      rutaPaquete: paquete,
      appSchemaVersionActual: 93,
      frase: frase,
      claveRecuperacionTexto: claveRecuperacionTexto,
    );
    expect(preparado, isA<RestauracionPortablePreparada>());

    // -- reinicio: coordinador nuevo, como haría el arranque --
    final resultado = await nuevoCoordinador().aplicarYConfirmar();
    b.sincronizarClavePrincipal();
    return resultado;
  }

  /// Todo lo que PC B tiene que poder hacer después.
  Future<void> exigirRecuperacionTotal(_Equipo b, String backupSetIdEsperado) async {
    final db = b.abrirBase();
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();

    // Esquema y datos.
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data.values.first, 93, reason: 'la base restaurada quedó en el esquema de esta build');

    final usuario = await db.customSelect("SELECT nombre FROM usuario WHERE id = 'u-maestro'").getSingle();
    expect(usuario.data['nombre'], 'MARLON', reason: 'el Maestro de A puede iniciar sesión en B');

    // Adjuntos.
    final contrato = File(p.join(b.attachmentsDir, 'contrato.pdf'));
    expect(contrato.existsSync(), isTrue);
    expect(contrato.readAsStringSync(), 'contrato irremplazable de A');

    // **La parte que no existía antes de 4D**: los tres dominios
    // descifran de verdad, con la clave que llegó dentro del paquete.
    final cipher = CredentialCipher(almacen: b.almacenClave);
    final boveda = await db.customSelect('SELECT secreto_cifrado AS c FROM boveda_credencial').getSingle();
    expect(await cipher.descifrar(boveda.data['c'] as String), _secretoBoveda);

    final telefonia =
        await db.customSelect('SELECT contrasena_cifrada AS c FROM equipo_telefonico_credencial').getSingle();
    expect(await cipher.descifrar(telefonia.data['c'] as String), _secretoTelefonia);

    final portal = await db.customSelect('SELECT contrasena_cifrada AS c FROM cliente_portal').getSingle();
    expect(await cipher.descifrar(portal.data['c'] as String), _secretoPortal);

    // La configuración de recuperación viajó con los datos: B continúa el
    // conjunto de A y puede crear respaldos nuevos.
    final config = await db.select(db.configuracionRecuperacionPortable).getSingleOrNull();
    expect(config, isNotNull, reason: 'la configuración de recuperación forma parte del estado restaurado');

    // Estado limpio.
    expect(File(b.restorePendingMarkerFile).existsSync(), isFalse, reason: 'sin marcador residual');
    expect(Directory(b.restorePendingDir).existsSync(), isFalse, reason: 'sin staging residual');
    expect(Directory(b.restoreOldDir).existsSync(), isFalse, reason: 'el estado anterior se soltó al confirmar');
    expect(Directory(b.stagingDir).listSync(), isEmpty, reason: 'ninguna copia en claro sobrevive');
    expect(b.ranuras.valores[RanuraClave.pendiente], isNull, reason: 'sin clave pendiente huérfana');
    expect(b.ranuras.valores[RanuraClave.principal], isNotNull);
    expect(backupSetIdEsperado, isNotEmpty);
  }

  group('PC A muere, PC B recupera', () {
    test(
      'con la FRASE: base, adjuntos, usuarios, y Bóveda/Telefonía/Portal descifran',
      timeout: const Timeout(Duration(minutes: 5)),
      () async {
        final raizA = Directory.systemTemp.createTempSync('riseg_pcA_');
        final raizB = Directory.systemTemp.createTempSync('riseg_pcB_');
        addTearDown(() => _borrar(raizA));
        addTearDown(() => _borrar(raizB));

        final a = await montarPcAyCrearPortable(raizA);

        // PC B: instalación nueva de verdad. Nada de A está aquí.
        final b = _Equipo(raizB)..crearCarpetas();
        final dbB = b.abrirBase();
        await dbB.customSelect('SELECT 1').get();
        await dbB.ensureMetadata(appVersion: '1.0.0');
        expect(
          await EvaluadorInstalacion(
            db: dbB,
            attachmentsDir: b.attachmentsDir,
            restorePendingDir: b.restorePendingDir,
            restorePendingMarkerFile: b.restorePendingMarkerFile,
            restoreOldDir: b.restoreOldDir,
          ).evaluar(),
          EstadoInstalacion.vaciaSegura,
          reason: 'B es una instalación vacía: la posesión del paquete y la frase bastan',
        );
        await dbB.close();
        expect(b.almacenClave.valor, isNull, reason: 'B no tiene ninguna clave propia');

        final resultado = await restaurarEn(b, a.paquete, frase: _frase);

        expect(resultado, isA<RestauracionPortableConfirmada>());
        await exigirRecuperacionTotal(b, a.recuperacion.configuracion.backupSetId);
      },
    );

    test(
      'con la CLAVE DE RECUPERACIÓN, en un equipo B distinto y nuevo',
      timeout: const Timeout(Duration(minutes: 5)),
      () async {
        final raizA = Directory.systemTemp.createTempSync('riseg_pcA2_');
        final raizB = Directory.systemTemp.createTempSync('riseg_pcB2_');
        addTearDown(() => _borrar(raizA));
        addTearDown(() => _borrar(raizB));

        final a = await montarPcAyCrearPortable(raizA);

        // Otro equipo, otro Almacén de Credenciales: no se reutiliza nada
        // de la prueba anterior.
        final b = _Equipo(raizB)..crearCarpetas();
        final dbB = b.abrirBase();
        await dbB.customSelect('SELECT 1').get();
        await dbB.close();

        final resultado = await restaurarEn(
          b,
          a.paquete,
          claveRecuperacionTexto: a.recuperacion.claveRecuperacionTexto,
        );

        expect(
          resultado,
          isA<RestauracionPortableConfirmada>(),
          reason: 'la clave de recuperación tiene que bastar sola: es para cuando nadie recuerda la frase',
        );
        await exigirRecuperacionTotal(b, a.recuperacion.configuracion.backupSetId);
      },
    );

    test(
      'sobre una instalación B que YA tenía datos y su propia clave',
      timeout: const Timeout(Duration(minutes: 5)),
      () async {
        final raizA = Directory.systemTemp.createTempSync('riseg_pcA3_');
        final raizB = Directory.systemTemp.createTempSync('riseg_pcB3_');
        addTearDown(() => _borrar(raizA));
        addTearDown(() => _borrar(raizB));

        final a = await montarPcAyCrearPortable(raizA);

        // B tiene su propia vida: su clave, su cliente, su adjunto.
        final b = _Equipo(raizB)..crearCarpetas();
        final cipherB = CredentialCipher(almacen: b.almacenClave);
        final secretoDeB = await cipherB.cifrar('secreto-que-solo-B-conoce');
        final dbB = b.abrirBase();
        await dbB.customSelect('SELECT 1').get();
        await dbB.customStatement(
          'INSERT INTO cliente (id, codigo, nombre_comercial, ciclo_vida_registro, created_at, updated_at) '
          "VALUES ('cli-B', 'CLI-B', 'EMPRESA DE B', 'activo', 1700000000, 1700000000)",
        );
        await dbB.customStatement(
          'INSERT INTO boveda_credencial (id, nombre, tipo, secreto_cifrado, ciclo_vida_registro, created_at, '
          'updated_at) '
          "VALUES ('bc-B', 'Portal de B', 'portal', '$secretoDeB', 'activo', 1700000000, 1700000000)",
        );
        await dbB.close();
        File(p.join(b.attachmentsDir, 'de_B.pdf')).writeAsStringSync('documento de B');
        b.ranuras.valores[RanuraClave.principal] = Uint8List.fromList(base64.decode(b.almacenClave.valor!));

        // B abre sus propios secretos ANTES de restaurar.
        final dbAntes = b.abrirBase();
        final antes = await dbAntes.customSelect('SELECT secreto_cifrado AS c FROM boveda_credencial').getSingle();
        expect(await cipherB.descifrar(antes.data['c'] as String), 'secreto-que-solo-B-conoce');
        await dbAntes.close();

        // La instalación NO es vacía: el flujo pre-auth no le aplica.
        final dbEstado = b.abrirBase();
        await dbEstado.customSelect('SELECT 1').get();
        expect(
          await EvaluadorInstalacion(
            db: dbEstado,
            attachmentsDir: b.attachmentsDir,
            restorePendingDir: b.restorePendingDir,
            restorePendingMarkerFile: b.restorePendingMarkerFile,
            restoreOldDir: b.restoreOldDir,
          ).evaluar(),
          EstadoInstalacion.existente,
          reason: 'aquí hace falta Maestro local ADEMÁS de la credencial del paquete',
        );
        await dbEstado.close();

        // Los conjuntos son distintos: hay que advertirlo, no bloquear.
        final info = await VerificarRespaldoPortableUseCase(
          stagingDir: b.stagingDir,
          sobre: sobre(),
        ).inspeccionar(rutaPaquete: a.paquete);
        expect(info.backupSetId, a.recuperacion.configuracion.backupSetId);

        final resultado = await restaurarEn(b, a.paquete, frase: _frase);

        expect(resultado, isA<RestauracionPortableConfirmada>());
        await exigirRecuperacionTotal(b, a.recuperacion.configuracion.backupSetId);

        // Nada de B sobrevive mezclado con A.
        final dbDespues = b.abrirBase();
        addTearDown(dbDespues.close);
        final clientes = await dbDespues.customSelect('SELECT codigo FROM cliente ORDER BY codigo').get();
        expect(clientes.map((f) => f.data['codigo']), ['CLI-001'], reason: 'los datos de B fueron reemplazados');
        expect(File(p.join(b.attachmentsDir, 'de_B.pdf')).existsSync(), isFalse);
        expect(
          b.ranuras.valores[RanuraClave.anterior],
          isNotNull,
          reason: 'la clave de B se conserva mientras exista su respaldo preventivo',
        );
      },
    );
  });
}

void _borrar(Directory dir) {
  try {
    dir.deleteSync(recursive: true);
  } on FileSystemException {
    // En Windows un handle recién cerrado puede tardar un instante.
  }
}
