// Etapa 4D — la prueba P0: nunca la base de A con la clave de B.
//
// El sistema de archivos y el Almacén de Credenciales no comparten
// transacción. Un estado mezclado no es un error recuperable: son datos
// que existen y que nadie puede leer, sin explicación visible. Por eso
// estas pruebas no comprueban "que no lance": comprueban, en cada punto
// de caída, que el conjunto observable sea **A completo** o **B
// completo**, archivos y clave a la vez.
//
// Cada reentrada construye el coordinador DE NUEVO, como haría un
// arranque real. Llamar a `revertir()` dentro del mismo stack y llamarlo
// recuperación tras caída no demostraría nada.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'package:riseg_one/core/security/almacen_ranuras_clave.dart';
import 'package:riseg_one/features/respaldo/domain/portable/coordinador_restauracion_portable.dart';
import 'package:riseg_one/features/respaldo/domain/portable/verificar_respaldo_portable_usecase.dart';
import 'package:riseg_one/features/respaldo/domain/usecases/aplicar_restauracion_pendiente_usecase.dart';
import 'package:riseg_one/features/respaldo/domain/usecases/crear_respaldo_usecase.dart';
import 'package:riseg_one/features/respaldo/domain/usecases/preparar_restauracion_usecase.dart';
import 'package:riseg_one/features/respaldo/domain/usecases/validar_paquete_respaldo_usecase.dart';

/// Ranuras en memoria, con fallos inyectables por ranura.
class _RanurasEnMemoria implements AlmacenRanurasClave {
  final Map<RanuraClave, Uint8List> valores = {};

  /// Ranuras cuya escritura debe fallar — así se simula que promover la
  /// clave no salga bien.
  final Set<RanuraClave> fallaAlEscribir = {};

  @override
  Future<Uint8List?> leer(RanuraClave ranura) async => valores[ranura];

  @override
  Future<void> escribir(RanuraClave ranura, Uint8List clave) async {
    if (fallaAlEscribir.contains(ranura)) {
      throw const FileSystemException('el Almacén de Credenciales rechazó la escritura');
    }
    valores[ranura] = Uint8List.fromList(clave);
  }

  @override
  Future<void> borrar(RanuraClave ranura) async => valores.remove(ranura);
}

final _claveB = Uint8List.fromList(List<int>.generate(32, (i) => 0xB0 + (i % 16)));
final _claveA = Uint8List.fromList(List<int>.generate(32, (i) => 0xA0 + (i % 16)));

const _operacion = 'op-1234567890abcdef';
const _keyIdA = 'a1a2a3a4a5a6a7a8a9aaabacadaeafb0';

void main() {
  late Directory raiz;
  late String databaseFile;
  late String attachmentsDir;
  late String restorePendingDir;
  late String restorePendingMarkerFile;
  late String restoreOldDir;
  late String stagingDir;
  late _RanurasEnMemoria ranuras;

  setUp(() {
    raiz = Directory.systemTemp.createTempSync('riseg_coord_');
    databaseFile = p.join(raiz.path, 'riseg_one.sqlite');
    attachmentsDir = p.join(raiz.path, 'attachments');
    restorePendingDir = p.join(raiz.path, 'restore_pending');
    restorePendingMarkerFile = p.join(raiz.path, 'restore_pending.json');
    restoreOldDir = p.join(raiz.path, 'restore_old');
    stagingDir = p.join(raiz.path, 'staging');
    Directory(stagingDir).createSync(recursive: true);
    ranuras = _RanurasEnMemoria();
  });

  tearDown(() {
    try {
      raiz.deleteSync(recursive: true);
    } on FileSystemException {
      // Irrelevante para lo que se mide.
    }
  });

  void crearSqlite(String ruta, {required int userVersion}) {
    Directory(p.dirname(ruta)).createSync(recursive: true);
    final db = sqlite3.open(ruta);
    db.execute('PRAGMA user_version = $userVersion');
    db.execute('CREATE TABLE IF NOT EXISTS t (id INTEGER PRIMARY KEY)');
    db.dispose();
  }

  int versionDe(String ruta) {
    final db = sqlite3.open(ruta, mode: OpenMode.readOnly);
    final v = db.userVersion;
    db.dispose();
    return v;
  }

  /// El estado que deja `preparar()`: instalación B viva, paquete de A en
  /// espera, clave de A en la ranura pendiente, marcador con la operación.
  void escenarioPreparado({bool conClavePendiente = true, bool conMarcador = true}) {
    crearSqlite(databaseFile, userVersion: 93); // base de B
    Directory(attachmentsDir).createSync(recursive: true);
    File(p.join(attachmentsDir, 'de_B.pdf')).writeAsStringSync('documento de B');

    crearSqlite(p.join(restorePendingDir, 'riseg_one.sqlite'), userVersion: 93); // base de A
    final staged = Directory(p.join(restorePendingDir, 'attachments'))..createSync(recursive: true);
    File(p.join(staged.path, 'de_A.pdf')).writeAsStringSync('documento de A');

    ranuras.valores[RanuraClave.principal] = _claveB;
    if (conClavePendiente) ranuras.valores[RanuraClave.pendiente] = _claveA;

    if (conMarcador) {
      File(restorePendingMarkerFile).writeAsStringSync(
        jsonEncode({
          'preparedAt': DateTime.now().toIso8601String(),
          'fase': FaseRestauracion.preparado.name,
          campoAdjuntosEsperados: 1,
          campoBytesAdjuntosEsperados: 'documento de A'.length,
          CamposRestauracionPortable.operacion: _operacion,
          CamposRestauracionPortable.keyIdEsperado: _keyIdA,
          CamposRestauracionPortable.clavePendiente: true,
        }),
      );
    }
  }

  /// Un coordinador **nuevo**, como lo construiría un arranque.
  CoordinadorRestauracionPortable coordinador({
    bool baseSana = true,
    bool claveAbre = true,
    Set<RanuraClave> fallaAlEscribir = const {},
    bool confirmacionFalla = false,
  }) {
    ranuras.fallaAlEscribir
      ..clear()
      ..addAll(fallaAlEscribir);

    final aplicar =
        confirmacionFalla
            ? _AplicarQueFallaAlConfirmar(
              databaseFile: databaseFile,
              attachmentsDir: attachmentsDir,
              restorePendingDir: restorePendingDir,
              restorePendingMarkerFile: restorePendingMarkerFile,
              restoreOldDir: restoreOldDir,
            )
            : AplicarRestauracionPendienteUseCase(
              databaseFile: databaseFile,
              attachmentsDir: attachmentsDir,
              restorePendingDir: restorePendingDir,
              restorePendingMarkerFile: restorePendingMarkerFile,
              restoreOldDir: restoreOldDir,
            );

    return CoordinadorRestauracionPortable(
      verificador: VerificarRespaldoPortableUseCase(stagingDir: stagingDir),
      preparar: PrepararRestauracionUseCase(
        backupsDir: p.join(raiz.path, 'backups'),
        restorePendingDir: restorePendingDir,
        restorePendingMarkerFile: restorePendingMarkerFile,
        validar: ValidarPaqueteRespaldoUseCase(),
        crearRespaldo: CrearRespaldoUseCase(databaseFile: databaseFile, attachmentsDir: attachmentsDir),
      ),
      aplicar: aplicar,
      ranuras: ranuras,
      stagingDir: stagingDir,
      validarBaseRestaurada: () async => ResultadoSaludBaseRestaurada(sana: baseSana),
      claveAbreLoRestaurado: (_) async => claveAbre,
    );
  }

  /// **La invariante P0.** El conjunto observable —base, adjuntos y clave
  /// principal— tiene que pertenecer todo a A o todo a B. Nunca a los dos.
  void exigirConjuntoCoherente({required String porque}) {
    final baseEsDeA = File(p.join(attachmentsDir, 'de_A.pdf')).existsSync();
    final baseEsDeB = File(p.join(attachmentsDir, 'de_B.pdf')).existsSync();
    final principal = ranuras.valores[RanuraClave.principal];

    expect(baseEsDeA != baseEsDeB, isTrue, reason: '$porque: los adjuntos son de A o de B, nunca de ambos');
    expect(principal, isNotNull, reason: '$porque: siempre tiene que haber una clave principal');

    if (baseEsDeA) {
      expect(principal, equals(_claveA), reason: '$porque: datos de A exigen la clave de A');
    } else {
      expect(principal, equals(_claveB), reason: '$porque: datos de B exigen la clave de B');
    }
  }

  group('Camino feliz', () {
    test('aplica, valida, promueve la clave y confirma — en ese orden', () async {
      escenarioPreparado();

      final resultado = await coordinador().aplicarYConfirmar();

      expect(resultado, isA<RestauracionPortableConfirmada>());
      expect((resultado as RestauracionPortableConfirmada).restoreOperationId, _operacion);
      expect(resultado.keyId, _keyIdA);

      expect(File(p.join(attachmentsDir, 'de_A.pdf')).existsSync(), isTrue);
      expect(ranuras.valores[RanuraClave.principal], equals(_claveA));
      expect(ranuras.valores[RanuraClave.pendiente], isNull, reason: 'la pendiente se consumió');
      expect(
        ranuras.valores[RanuraClave.anterior],
        equals(_claveB),
        reason: 'la de B se conserva hasta poder soltarla',
      );
      expect(File(restorePendingMarkerFile).existsSync(), isFalse);
      expect(Directory(restoreOldDir).existsSync(), isFalse);
      exigirConjuntoCoherente(porque: 'tras confirmar');
    });
  });

  group('Fallos antes de promover: queda B completo', () {
    test('la base restaurada no está sana', () async {
      escenarioPreparado();

      final resultado = await coordinador(baseSana: false).aplicarYConfirmar();

      expect(resultado, isA<RestauracionPortableRevertida>());
      expect((resultado as RestauracionPortableRevertida).motivo, MotivoRestauracionPortableAbortada.baseNoSana);
      expect(resultado.estadoAnteriorRepuesto, isTrue);
      expect(ranuras.valores[RanuraClave.principal], equals(_claveB), reason: 'la clave de B nunca se tocó');
      expect(ranuras.valores[RanuraClave.pendiente], isNull);
      exigirConjuntoCoherente(porque: 'base no sana');
    });

    test('LA CLAVE DEL PAQUETE NO ABRE lo que se acaba de restaurar', () async {
      escenarioPreparado();

      // Éste es el caso que convierte una "recuperación total" en una
      // promesa incumplida: los datos llegan y no se pueden leer.
      final resultado = await coordinador(claveAbre: false).aplicarYConfirmar();

      expect(
        (resultado as RestauracionPortableRevertida).motivo,
        MotivoRestauracionPortableAbortada.claveNoAbreLoRestaurado,
      );
      expect(resultado.estadoAnteriorRepuesto, isTrue);
      exigirConjuntoCoherente(porque: 'la clave no abría lo restaurado');
    });
  });

  group('La promoción de la clave falla', () {
    test('DB de A instalada y validada, pero la clave no se puede promover → vuelve B COMPLETO', () async {
      escenarioPreparado();

      final resultado = await coordinador(fallaAlEscribir: {RanuraClave.principal}).aplicarYConfirmar();

      expect(resultado, isA<RestauracionPortableRevertida>());
      expect(
        (resultado as RestauracionPortableRevertida).motivo,
        MotivoRestauracionPortableAbortada.promocionDeClaveFallida,
      );

      // Lo que importa: NO queda un estado mezclado. Los archivos de B
      // volvieron y la clave principal sigue siendo la de B — nunca se
      // sobrescribió, porque la escritura que la habría cambiado es
      // precisamente la que falló.
      expect(versionDe(databaseFile), 93);
      expect(File(p.join(attachmentsDir, 'de_B.pdf')).existsSync(), isTrue, reason: 'los adjuntos de B volvieron');
      expect(File(p.join(attachmentsDir, 'de_A.pdf')).existsSync(), isFalse);
      expect(ranuras.valores[RanuraClave.principal], equals(_claveB));
      expect(
        ranuras.valores[RanuraClave.pendiente],
        isNull,
        reason: 'la limpieza de la pendiente no puede depender de que la reposición de la clave saliera bien',
      );
      exigirConjuntoCoherente(porque: 'la promoción falló');
    });

    test('cuando el Almacén de Credenciales no responde, el rollback lo dice en vez de fingir', () async {
      escenarioPreparado();

      final resultado =
          await coordinador(fallaAlEscribir: {RanuraClave.principal}).aplicarYConfirmar()
              as RestauracionPortableRevertida;

      // `anterior` se había guardado antes de que fallara la escritura de
      // `principal`, así que reponerla también falla. El coordinador NO
      // declara éxito: informa de que la reposición quedó incompleta,
      // aunque el estado observable siga siendo coherente.
      expect(resultado.estadoAnteriorRepuesto, isFalse);
      exigirConjuntoCoherente(porque: 'el almacén de credenciales no respondía');
    });
  });

  group('La confirmación falla', () {
    test('clave ya promovida y la confirmación no sale: se revierte TODO junto', () async {
      escenarioPreparado();

      final resultado = await coordinador(confirmacionFalla: true).aplicarYConfirmar();

      expect(
        (resultado as RestauracionPortableRevertida).motivo,
        MotivoRestauracionPortableAbortada.confirmacionFallida,
      );
      // Lo esencial: la clave de A NO se queda con los datos de B.
      exigirConjuntoCoherente(porque: 'la confirmación falló después de promover');
      expect(ranuras.valores[RanuraClave.principal], equals(_claveB));
      expect(ranuras.valores[RanuraClave.anterior], isNull, reason: 'se consumió al reponerla');
    });
  });

  group('Siete puntos de caída, cada uno con un arranque nuevo', () {
    test('1. antes de guardar la clave pendiente: no hay nada que reanudar', () async {
      crearSqlite(databaseFile, userVersion: 93);
      ranuras.valores[RanuraClave.principal] = _claveB;

      final resultado = await coordinador().aplicarYConfirmar();

      expect(resultado, isA<SinRestauracionPortablePendiente>());
      expect(ranuras.valores[RanuraClave.principal], equals(_claveB));
    });

    test('2. clave pendiente SIN marcador: es un huérfano y se retira', () async {
      crearSqlite(databaseFile, userVersion: 93);
      ranuras.valores[RanuraClave.principal] = _claveB;
      ranuras.valores[RanuraClave.pendiente] = _claveA;

      final resultado = await coordinador().aplicarYConfirmar();

      expect(resultado, isA<SinRestauracionPortablePendiente>());
      expect(
        ranuras.valores[RanuraClave.pendiente],
        isNull,
        reason: 'una clave que no pertenece a ninguna operación no puede quedarse ahí',
      );
      expect(ranuras.valores[RanuraClave.principal], equals(_claveB));
    });

    test('3. archivos ya apartados: el arranque siguiente completa', () async {
      escenarioPreparado();
      // Se simula que la fase de archivos ya corrió.
      Directory(restoreOldDir).createSync(recursive: true);
      File(databaseFile).renameSync(p.join(restoreOldDir, 'riseg_one.sqlite'));
      File(p.join(restorePendingDir, 'riseg_one.sqlite')).renameSync(databaseFile);
      Directory(attachmentsDir).renameSync(p.join(restoreOldDir, 'attachments'));
      Directory(p.join(restorePendingDir, 'attachments')).renameSync(attachmentsDir);
      File(restorePendingMarkerFile).writeAsStringSync(
        jsonEncode({
          'fase': FaseRestauracion.aplicada.name,
          campoAdjuntosEsperados: 1,
          campoBytesAdjuntosEsperados: 'documento de A'.length,
          CamposRestauracionPortable.operacion: _operacion,
          CamposRestauracionPortable.keyIdEsperado: _keyIdA,
        }),
      );

      final resultado = await coordinador().aplicarYConfirmar();

      expect(resultado, isA<RestauracionPortableConfirmada>());
      exigirConjuntoCoherente(porque: 'reanudado desde archivos apartados');
    });

    test('4. base nueva instalada y migrada: se completa desde ahí', () async {
      escenarioPreparado();
      final primera = await coordinador().aplicarYConfirmar();
      expect(primera, isA<RestauracionPortableConfirmada>());

      // Un segundo arranque no debe volver a hacer nada.
      final segunda = await coordinador().aplicarYConfirmar();

      expect(segunda, isA<SinRestauracionPortablePendiente>());
      exigirConjuntoCoherente(porque: 'segundo arranque tras confirmar');
    });

    test('5. clave YA promovida al reiniciar: la promoción es idempotente', () async {
      escenarioPreparado();
      // Se simula el apagón justo después de promover: pendiente ya no
      // existe, anterior guarda la de B, y el marcador sigue ahí.
      ranuras.valores
        ..[RanuraClave.principal] = _claveA
        ..remove(RanuraClave.pendiente)
        ..[RanuraClave.anterior] = _claveB;

      final resultado = await coordinador().aplicarYConfirmar();

      expect(resultado, isA<RestauracionPortableConfirmada>());
      expect(
        ranuras.valores[RanuraClave.principal],
        equals(_claveA),
        reason: 'no se vuelve a promover ni se deshace lo ya hecho',
      );
      exigirConjuntoCoherente(porque: 'clave ya promovida al reiniciar');
    });

    test('6. antes de confirmar: el marcador sobrevive y el arranque termina el trabajo', () async {
      escenarioPreparado();
      final aplicar = AplicarRestauracionPendienteUseCase(
        databaseFile: databaseFile,
        attachmentsDir: attachmentsDir,
        restorePendingDir: restorePendingDir,
        restorePendingMarkerFile: restorePendingMarkerFile,
        restoreOldDir: restoreOldDir,
      );
      await aplicar.ejecutar(); // archivos movidos, sin confirmar
      expect(File(restorePendingMarkerFile).existsSync(), isTrue);

      final resultado = await coordinador().aplicarYConfirmar();

      expect(resultado, isA<RestauracionPortableConfirmada>());
      expect(File(restorePendingMarkerFile).existsSync(), isFalse);
      exigirConjuntoCoherente(porque: 'reanudado antes de confirmar');
    });

    test('7. confirmada antes de la limpieza: no se rehace nada', () async {
      escenarioPreparado();
      await coordinador().aplicarYConfirmar();
      // Queda la ranura `anterior` como huérfana legítima: es la pareja
      // del respaldo preventivo y se retira cuando éste se elimine.
      expect(ranuras.valores[RanuraClave.anterior], equals(_claveB));

      final resultado = await coordinador().aplicarYConfirmar();

      expect(resultado, isA<SinRestauracionPortablePendiente>());
      exigirConjuntoCoherente(porque: 'tras la limpieza pendiente');
    });
  });

  group('Estados ambiguos: no adivinar, no borrar evidencia', () {
    test('marcador portable sin ninguna clave: se aborta sin tocar nada', () async {
      escenarioPreparado(conClavePendiente: false);
      ranuras.valores.remove(RanuraClave.principal);

      final resultado = await coordinador().aplicarYConfirmar();

      expect(resultado, isA<RestauracionPortableEstadoAmbiguo>());
      // Nada se movió: la evidencia sigue completa para que una persona
      // pueda mirar.
      expect(File(restorePendingMarkerFile).existsSync(), isTrue);
      expect(File(p.join(restorePendingDir, 'riseg_one.sqlite')).existsSync(), isTrue);
      expect(File(p.join(attachmentsDir, 'de_B.pdf')).existsSync(), isTrue);
    });

    test('un marcador de 4B sin campos portables lo atiende el arranque normal', () async {
      escenarioPreparado(conMarcador: false);
      File(restorePendingMarkerFile).writeAsStringSync(jsonEncode({'fase': FaseRestauracion.preparado.name}));

      final resultado = await coordinador().aplicarYConfirmar();

      expect(resultado, isA<SinRestauracionPortablePendiente>());
      expect(File(restorePendingMarkerFile).existsSync(), isTrue, reason: 'no es suyo: no lo toca');
    });
  });
}

/// Aplica igual que el motor real, pero su confirmación falla — para
/// poder probar el punto exacto entre promover y confirmar.
class _AplicarQueFallaAlConfirmar extends AplicarRestauracionPendienteUseCase {
  _AplicarQueFallaAlConfirmar({
    required super.databaseFile,
    required super.attachmentsDir,
    required super.restorePendingDir,
    required super.restorePendingMarkerFile,
    required super.restoreOldDir,
  });

  @override
  Future<void> confirmar() async {
    throw const FileSystemException('no se pudo soltar el estado anterior');
  }
}
