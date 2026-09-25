// Etapa 4D — la puerta que decide si se puede restaurar sin sesión.
//
// Es el punto más delicado de todo 4D: si esta comprobación se equivoca
// por exceso de confianza, cualquiera con un USB y su frase sobrescribe
// la instalación de otra empresa desde la pantalla de inicio. Por eso la
// pregunta no es "¿es una instalación nueva?" —que no tiene respuesta
// fiable— sino "¿hay aquí algo que una restauración pueda destruir?".
//
// `contarUsuarios() == 0` NO basta, y estas pruebas lo demuestran con
// los casos exactos que el pliego señaló: base con datos pero sin
// usuarios, restauración a medio aplicar, adjuntos sin filas.

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/respaldo/domain/portable/evaluador_instalacion.dart';

void main() {
  late Directory raiz;
  late AppDatabase db;
  late String attachmentsDir;
  late String restorePendingDir;
  late String restorePendingMarkerFile;
  late String restoreOldDir;

  setUp(() async {
    raiz = Directory.systemTemp.createTempSync('riseg_eval_');
    attachmentsDir = p.join(raiz.path, 'attachments');
    restorePendingDir = p.join(raiz.path, 'restore_pending');
    restorePendingMarkerFile = p.join(raiz.path, 'restore_pending.json');
    restoreOldDir = p.join(raiz.path, 'restore_old');
    db = AppDatabase(NativeDatabase.memory());
    // Abrir crea el esquema y siembra los catálogos: es exactamente el
    // estado de una instalación recién instalada.
    await db.customSelect('SELECT 1').get();
    await db.ensureMetadata(appVersion: '1.0.0');
  });

  tearDown(() async {
    await db.close();
    try {
      raiz.deleteSync(recursive: true);
    } on FileSystemException {
      // Irrelevante para lo que se mide.
    }
  });

  EvaluadorInstalacion evaluador() => EvaluadorInstalacion(
    db: db,
    attachmentsDir: attachmentsDir,
    restorePendingDir: restorePendingDir,
    restorePendingMarkerFile: restorePendingMarkerFile,
    restoreOldDir: restoreOldDir,
  );

  group('Instalación realmente vacía', () {
    test('una instalación recién creada, con sus catálogos y metadata, es VACIA_SEGURA', () async {
      expect(await evaluador().evaluar(), EstadoInstalacion.vaciaSegura);
    });

    test('tener configuración de recuperación portable ya la vuelve EXISTENTE, y está bien', () async {
      await db.customStatement(
        'INSERT INTO configuracion_recuperacion_portable '
        '(id, backup_set_id, formato_version, envoltura_frase, envoltura_clave_recuperacion, '
        'clave_recuperacion_generada_en, ciclo_vida_registro, created_at, updated_at) '
        "VALUES ('c1', 'abc', 1, '{}', '{}', 1700000000, 'activo', 1700000000, 1700000000)",
      );

      // El criterio es estricto: cualquier fila de más respecto a una
      // instalación de fábrica cuenta. No es una limitación real, porque
      // configurar la recuperación exige entrar como Maestro, y para eso
      // hace falta un usuario — que ya la habría vuelto EXISTENTE. Se
      // prefiere el criterio estricto antes que una excepción que haya
      // que razonar cada vez que alguien lea este código.
      expect(await evaluador().evaluar(), EstadoInstalacion.existente);
    });

    test('una carpeta de adjuntos que existe pero está vacía tampoco la descalifica', () async {
      Directory(attachmentsDir).createSync(recursive: true);

      expect(await evaluador().evaluar(), EstadoInstalacion.vaciaSegura);
    });
  });

  group('Lo que SÍ la convierte en existente', () {
    test('un usuario', () async {
      await db.customStatement(
        'INSERT INTO usuario (id, nombre, nombre_usuario, password_hash, es_maestro, debe_cambiar_password, '
        'ciclo_vida_registro, created_at, updated_at) '
        "VALUES ('u1', 'MARLON', 'M', 'pbkdf2\$1\$s\$h', 1, 0, 'activo', 1700000000, 1700000000)",
      );

      expect(await evaluador().evaluar(), EstadoInstalacion.existente);
    });

    test('EL CASO PELIGROSO: datos de negocio con CERO usuarios', () async {
      // Una base dañada o a medio restaurar puede quedar así. Con la
      // comprobación ingenua de `contarUsuarios() == 0` se habría
      // considerado vacía, y se habría sobrescrito el trabajo de años
      // sin pedirle nada a nadie.
      await db.customStatement(
        'INSERT INTO cliente (id, codigo, nombre_comercial, ciclo_vida_registro, created_at, updated_at) '
        "VALUES ('cli-1', 'CLI-001', 'MORGAN', 'activo', 1700000000, 1700000000)",
      );
      final usuarios = await db.customSelect('SELECT COUNT(*) AS n FROM usuario').getSingle();

      expect(usuarios.data['n'], 0, reason: 'cero usuarios, y aun así hay datos');
      expect(await evaluador().evaluar(), EstadoInstalacion.existente);
    });

    test('un solo adjunto, sin ninguna fila en la base', () async {
      Directory(attachmentsDir).createSync(recursive: true);
      File(p.join(attachmentsDir, 'acta.pdf')).writeAsStringSync('irremplazable');

      expect(await evaluador().evaluar(), EstadoInstalacion.existente);
    });

    test('un adjunto en una subcarpeta', () async {
      final sub = Directory(p.join(attachmentsDir, 'personal', 'emp-1'))..createSync(recursive: true);
      File(p.join(sub.path, 'foto.jpg')).writeAsStringSync('x');

      expect(await evaluador().evaluar(), EstadoInstalacion.existente);
    });

    test('un marcador de restauración pendiente', () async {
      File(restorePendingMarkerFile).writeAsStringSync('{"fase":"preparado"}');

      expect(
        await evaluador().evaluar(),
        EstadoInstalacion.existente,
        reason: 'los datos de verdad pueden estar apartados',
      );
    });

    test('una carpeta restore_pending', () async {
      Directory(restorePendingDir).createSync(recursive: true);

      expect(await evaluador().evaluar(), EstadoInstalacion.existente);
    });

    test('una carpeta restore_old: ahí está el estado anterior', () async {
      Directory(restoreOldDir).createSync(recursive: true);

      expect(await evaluador().evaluar(), EstadoInstalacion.existente);
    });
  });

  group('Cuando no se puede saber', () {
    test('una base que no se deja consultar es INDETERMINADA, nunca vacía', () async {
      await db.close();

      expect(
        await evaluador().evaluar(),
        EstadoInstalacion.indeterminada,
        reason: 'ante la duda se protegen los datos; es la única respuesta que no sale cara',
      );
    });

    test('INDETERMINADA no es vaciaSegura', () async {
      await db.close();

      expect(await evaluador().evaluar(), isNot(EstadoInstalacion.vaciaSegura));
    });
  });

  group('Guardrail: la referencia de fábrica cubre todas las tablas', () {
    test('los conteos de fábrica incluyen TODAS las tablas del esquema', () async {
      final fabrica = await EvaluadorInstalacion.conteosDeInstalacionDeFabrica();
      final todas = db.allTables.map((t) => t.actualTableName).toSet();

      // Una tabla nueva entra sola en la comparación: no hay ninguna
      // lista que alguien pueda olvidar actualizar.
      expect(fabrica.keys.toSet(), equals(todas));
    });

    test('las tablas que el sembrado rellena están documentadas', () async {
      final fabrica = await EvaluadorInstalacion.conteosDeInstalacionDeFabrica();
      final sembradas = fabrica.entries.where((e) => e.value > 0).map((e) => e.key).toSet();

      // Si el sembrado cambia, esta prueba falla y obliga a revisarlo.
      // No afecta a la seguridad —la comparación es automática— pero
      // deja constancia de cuál es el estado de fábrica.
      expect(sembradas, {
        'app_metadata',
        'codigo_secuencia',
        'tipo_sucursal',
        'industria',
        'tipo_servicio',
        'area',
        'tipo_modalidad_turno',
        'tipo_frecuencia_cobro',
        'banco',
        'empresa',
      });
    });

    test('las tablas con datos del usuario nacen vacías', () async {
      final fabrica = await EvaluadorInstalacion.conteosDeInstalacionDeFabrica();

      for (final tabla in [
        'usuario',
        'permiso_usuario',
        'cliente',
        'empleado',
        'boveda_credencial',
        'equipo_telefonico_credencial',
        'cliente_portal',
        'nomina',
        'egreso',
        'articulo_unidad',
        'vehiculo',
        'linea_telefonica',
        'configuracion_recuperacion_portable',
      ]) {
        expect(fabrica[tabla], 0, reason: '$tabla no puede venir con filas de fábrica');
      }
    });

    test('una tabla de más en la base viva da INDETERMINADA, nunca vacía', () async {
      await db.customStatement('CREATE TABLE tabla_intrusa (id INTEGER PRIMARY KEY)');

      // `allTables` refleja el esquema de Dart, así que una tabla creada
      // a mano no aparece ahí; lo que sí se comprueba es el camino
      // inverso: una referencia incompleta nunca puede concluir 'vacía'.
      final evaluadorConReferenciaIncompleta = EvaluadorInstalacion(
        db: db,
        attachmentsDir: attachmentsDir,
        restorePendingDir: restorePendingDir,
        restorePendingMarkerFile: restorePendingMarkerFile,
        restoreOldDir: restoreOldDir,
        conteosDeFabrica: () async => {'app_metadata': 1},
      );

      expect(await evaluadorConReferenciaIncompleta.evaluar(), EstadoInstalacion.indeterminada);
    });
  });
}
