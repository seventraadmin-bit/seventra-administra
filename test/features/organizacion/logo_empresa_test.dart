// Etapa 5B.2 — el logotipo pertenece a la Empresa, no al producto.
//
// Hasta aquí, los documentos de la Empresa llevaban `assets/images/logo.png`
// —el escudo de RISEG— porque el producto lo traía dentro. Eso funcionaba
// mientras hubiera una sola Empresa; con varias, cada documento habría
// llevado el logotipo de otra.
//
// `Empresa.logoAttachmentId` y la tabla puente `EmpresaAttachment` ya
// existían en el esquema desde hacía etapas, sin usarse: 5B.2 no necesita
// migración, sólo conectarlas.

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:riseg_one/core/attachments/attachment_repository.dart';
import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/data/repositories/empresa_repository_impl.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/empresa_repository.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/adoptar_logo_heredado_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/eliminar_logo_empresa_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/logo_empresa_validacion.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/registrar_logo_empresa_usecase.dart';

/// Un PNG mínimo pero real: firma + un IHDR creíble.
Uint8List pngDePrueba({int relleno = 64}) {
  return Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
    ...List<int>.filled(relleno, 0x00),
  ]);
}

Uint8List jpegDePrueba() {
  return Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, ...List<int>.filled(32, 0x00), 0xFF, 0xD9]);
}

void main() {
  late AppDatabase db;
  late Directory raiz;
  late EmpresaRepository repo;
  late AttachmentRepository adjuntos;
  late AttachmentStorage almacen;
  late String empresaId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    raiz = Directory.systemTemp.createTempSync('logo_empresa_');
    repo = EmpresaRepositoryImpl(db);
    adjuntos = AttachmentRepository(db);
    almacen = AttachmentStorage(p.join(raiz.path, 'attachments'));

    // La siembra crea la Empresa activa.
    final empresa = await repo.obtenerActiva();
    empresaId = empresa.id;
  });

  tearDown(() async {
    await db.close();
    try {
      raiz.deleteSync(recursive: true);
    } on FileSystemException {
      // En Windows el archivo puede quedar tomado un instante más.
    }
  });

  /// Deja un archivo candidato en disco y devuelve su ruta.
  String archivoCon(Uint8List bytes, {String nombre = 'logo.png'}) {
    final f = File(p.join(raiz.path, nombre))..writeAsBytesSync(bytes, flush: true);
    return f.path;
  }

  RegistrarLogoEmpresaUseCase registrar() => RegistrarLogoEmpresaUseCase(repo, adjuntos, almacen);
  EliminarLogoEmpresaUseCase eliminar() => EliminarLogoEmpresaUseCase(repo, adjuntos);

  group('Validación del archivo', () {
    test('acepta PNG real', () async {
      final r = await revisarLogo(archivoCon(pngDePrueba()));
      expect(r, isA<LogoAceptado>());
      expect((r as LogoAceptado).mimeType, 'image/png');
    });

    test('acepta JPEG real', () async {
      final r = await revisarLogo(archivoCon(jpegDePrueba(), nombre: 'logo.jpg'));
      expect((r as LogoAceptado).mimeType, 'image/jpeg');
    });

    test('RECHAZA un archivo que sólo se LLAMA .png', () async {
      // El selector del sistema se puede sortear escribiendo el nombre a
      // mano. Lo que manda es el contenido.
      final ruta = archivoCon(Uint8List.fromList('%PDF-1.7 no soy una imagen'.codeUnits), nombre: 'trampa.png');
      expect(await revisarLogo(ruta), isA<LogoFormatoNoAceptado>());
    });

    test('el tipo sale de la firma, no de la extensión', () async {
      // Un JPEG guardado como .png sigue siendo JPEG.
      final r = await revisarLogo(archivoCon(jpegDePrueba(), nombre: 'confuso.png'));
      expect((r as LogoAceptado).mimeType, 'image/jpeg');
    });

    test('rechaza lo que excede el límite', () async {
      final grande = Uint8List.fromList([
        ...pngDePrueba(relleno: 0),
        ...List<int>.filled(LogoEmpresaValidacion.tamanoMaximoBytes + 1, 0x00),
      ]);
      final r = await revisarLogo(archivoCon(grande, nombre: 'enorme.png'));
      expect(r, isA<LogoDemasiadoGrande>());
    });

    test('rechaza un archivo vacío', () async {
      expect(await revisarLogo(archivoCon(Uint8List(0))), isA<LogoFormatoNoAceptado>());
    });

    test('un archivo inexistente no revienta', () async {
      expect(await revisarLogo(p.join(raiz.path, 'no-existe.png')), isA<LogoNoExiste>());
    });
  });

  group('Cargar, reemplazar y quitar', () {
    test('cargar deja la Empresa con su logotipo y el archivo en el almacén', () async {
      final r = await registrar().ejecutar(
        empresaId: empresaId,
        sourceFilePath: archivoCon(pngDePrueba()),
        originalFileName: 'mi-logo.png',
      );

      expect(r, isA<RegistrarLogoEmpresaExitoso>());
      final empresa = (r as RegistrarLogoEmpresaExitoso).empresa;
      expect(empresa.logoAttachmentId, isNotNull);

      final adjunto = await adjuntos.obtenerPorId(empresa.logoAttachmentId!);
      expect(adjunto!.categoria, categoriaLogo);
      expect(adjunto.mimeType, 'image/png');
      expect(File(adjunto.path).existsSync(), isTrue);

      // La fila puente es lo que ata el adjunto a ESTA Empresa.
      final puente = await db.select(db.empresaAttachment).get();
      expect(puente.single.empresaId, empresaId);
    });

    test('un archivo inválido NO toca el almacén ni la Empresa', () async {
      final ruta = archivoCon(Uint8List.fromList('no soy imagen'.codeUnits), nombre: 'malo.png');
      final r = await registrar().ejecutar(empresaId: empresaId, sourceFilePath: ruta, originalFileName: 'malo.png');

      expect(r, isA<RegistrarLogoEmpresaArchivoInvalido>());
      expect((await repo.obtenerPorId(empresaId))!.logoAttachmentId, isNull);
      expect(await db.select(db.attachment).get(), isEmpty, reason: 'no puede quedar un adjunto huérfano');
    });

    test('reemplazar mueve el puntero y ARCHIVA el anterior, no lo borra', () async {
      final primero = await registrar().ejecutar(
        empresaId: empresaId,
        sourceFilePath: archivoCon(pngDePrueba(), nombre: 'a.png'),
        originalFileName: 'a.png',
      );
      final idPrimero = (primero as RegistrarLogoEmpresaExitoso).empresa.logoAttachmentId!;

      final segundo = await registrar().ejecutar(
        empresaId: empresaId,
        sourceFilePath: archivoCon(jpegDePrueba(), nombre: 'b.jpg'),
        originalFileName: 'b.jpg',
      );
      final idSegundo = (segundo as RegistrarLogoEmpresaExitoso).empresa.logoAttachmentId!;

      expect(idSegundo, isNot(idPrimero));
      final anterior = await adjuntos.obtenerPorId(idPrimero);
      expect(anterior, isNotNull, reason: 'el anterior se archiva, jamás se borra');
      expect(anterior!.estado, 'archivado');
      expect((await adjuntos.obtenerPorId(idSegundo))!.estado, 'activo');
    });

    test('quitar deja la Empresa sin logotipo y archiva el adjunto', () async {
      await registrar().ejecutar(
        empresaId: empresaId,
        sourceFilePath: archivoCon(pngDePrueba()),
        originalFileName: 'logo.png',
      );

      final r = await eliminar().ejecutar(empresaId);
      expect(r, isA<EliminarLogoEmpresaExitoso>());
      expect((r as EliminarLogoEmpresaExitoso).empresa.logoAttachmentId, isNull);

      final historial = await repo.historialLogos(empresaId);
      expect(historial.single.estado, 'archivado');
    });

    test('quitar dos veces es inofensivo', () async {
      await registrar().ejecutar(
        empresaId: empresaId,
        sourceFilePath: archivoCon(pngDePrueba()),
        originalFileName: 'logo.png',
      );
      await eliminar().ejecutar(empresaId);
      expect(await eliminar().ejecutar(empresaId), isA<EliminarLogoEmpresaSinLogo>());
    });
  });

  group('Adopción del logotipo heredado', () {
    AdoptarLogoHeredadoUseCase adoptar(Uint8List? asset) =>
        AdoptarLogoHeredadoUseCase(repo, almacen, () async => asset);

    test('una instalación que viene de antes conserva su logotipo sin intervención', () async {
      final r = await adoptar(pngDePrueba()).ejecutar(empresaId);

      expect(r, isA<LogoHeredadoAdoptado>());
      final empresa = (r as LogoHeredadoAdoptado).empresa;
      expect(empresa.logoAttachmentId, isNotNull);
      final adjunto = await adjuntos.obtenerPorId(empresa.logoAttachmentId!);
      expect(adjunto!.originalFileName, AdoptarLogoHeredadoUseCase.nombreArchivoHeredado);
    });

    test('ES IDEMPOTENTE: correrla dos veces no duplica nada', () async {
      await adoptar(pngDePrueba()).ejecutar(empresaId);
      final segunda = await adoptar(pngDePrueba()).ejecutar(empresaId);

      expect(segunda, isA<LogoHeredadoNoAplica>());
      expect(await repo.historialLogos(empresaId), hasLength(1));
    });

    test('QUITAR EL LOGOTIPO A PROPÓSITO NO SE DESHACE EN EL SIGUIENTE ARRANQUE', () async {
      // Éste es el caso que decide el diseño: la marca de "ya se adoptó" no
      // es una bandera nueva, es el historial de adjuntos archivados.
      await adoptar(pngDePrueba()).ejecutar(empresaId);
      await eliminar().ejecutar(empresaId);

      final tercera = await adoptar(pngDePrueba()).ejecutar(empresaId);

      expect(tercera, isA<LogoHeredadoNoAplica>());
      expect((await repo.obtenerPorId(empresaId))!.logoAttachmentId, isNull, reason: 'la decisión se respeta');
    });

    test('no pisa un logotipo que la Empresa ya cargó', () async {
      await registrar().ejecutar(
        empresaId: empresaId,
        sourceFilePath: archivoCon(jpegDePrueba(), nombre: 'propio.jpg'),
        originalFileName: 'propio.jpg',
      );
      final antes = (await repo.obtenerPorId(empresaId))!.logoAttachmentId;

      expect(await adoptar(pngDePrueba()).ejecutar(empresaId), isA<LogoHeredadoNoAplica>());
      expect((await repo.obtenerPorId(empresaId))!.logoAttachmentId, antes);
    });

    test('en una instalación SIN logotipo heredado simplemente no hace nada', () async {
      final r = await adoptar(null).ejecutar(empresaId);

      expect(r, isA<LogoHeredadoNoAplica>());
      expect((await repo.obtenerPorId(empresaId))!.logoAttachmentId, isNull);
    });

    test('no mira el nombre ni el código de la Empresa', () async {
      // No hay ninguna regla del tipo `if empresa == RISEG`: se adopta lo que
      // haya, o no se adopta nada. La prueba lo fija cambiando el nombre.
      await (db.update(db.empresa)..where((t) => t.id.equals(empresaId))).write(
        const EmpresaCompanion(nombreComercial: Value('Extintores XYZ')),
      );

      expect(await adoptar(pngDePrueba()).ejecutar(empresaId), isA<LogoHeredadoAdoptado>());
    });
  });

  group('El logotipo viaja en el respaldo', () {
    test('el archivo vive bajo attachmentsDir, que es lo que empaqueta 4B', () async {
      final r = await registrar().ejecutar(
        empresaId: empresaId,
        sourceFilePath: archivoCon(pngDePrueba()),
        originalFileName: 'logo.png',
      );
      final adjunto = await adjuntos.obtenerPorId((r as RegistrarLogoEmpresaExitoso).empresa.logoAttachmentId!);

      // `CrearRespaldoUseCase` empaqueta `attachmentsDir` entero, así que un
      // logotipo guardado aquí entra en el .zip v2 y, con él, en el
      // .risegbkp portable. No hizo falta tocar 4B ni 4D.
      expect(p.isWithin(p.join(raiz.path, 'attachments'), adjunto!.path), isTrue);
      expect(adjunto.path, contains(empresaId), reason: 'la ruta cuelga del dueño');
    });
  });
}
