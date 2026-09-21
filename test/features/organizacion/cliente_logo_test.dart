// Etapa 16 — evolución visual del Design System. Cubre el logotipo de
// Cliente de punta a punta (BD + archivo reales): registrar, reemplazar
// (archiva el Attachment anterior, nunca lo borra) y eliminar (deja
// `logoAttachmentId` en NULL explícitamente, a diferencia de la
// fotografía de Empleado que no tiene "quitar").

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/attachments/attachment_repository.dart';
import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/eliminar_logo_cliente_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/registrar_logo_cliente_usecase.dart';

void main() {
  late AppDatabase db;
  late ClienteRepositoryImpl clienteRepo;
  late AttachmentRepository attachmentRepo;
  late RegistrarLogoClienteUseCase registrarLogo;
  late EliminarLogoClienteUseCase eliminarLogo;
  late Directory tempDir;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    clienteRepo = ClienteRepositoryImpl(db);
    attachmentRepo = AttachmentRepository(db);
    tempDir = Directory.systemTemp.createTempSync('riseg_cliente_logo_test_');
    final storage = AttachmentStorage(tempDir.path);
    registrarLogo = RegistrarLogoClienteUseCase(clienteRepo, attachmentRepo, storage);
    eliminarLogo = EliminarLogoClienteUseCase(clienteRepo, attachmentRepo);
  });

  tearDown(() {
    db.close();
    tempDir.deleteSync(recursive: true);
  });

  test('registra el logo — crea el Attachment (categoría logo) y mueve el puntero de Cliente', () async {
    final cliente = await clienteRepo.crear(
      ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Sportium'),
    );
    expect(cliente.logoAttachmentId, isNull, reason: 'ningún Cliente nace con logo');

    final archivo = '${tempDir.path}/logo1.png';
    File(archivo).writeAsStringSync('contenido logo 1');

    final resultado = await registrarLogo.ejecutar(
      clienteId: cliente.id,
      sourceFilePath: archivo,
      originalFileName: 'logo1.png',
      mimeType: 'image/png',
    );

    expect(resultado, isA<RegistrarLogoClienteExitoso>());
    final actualizado = (resultado as RegistrarLogoClienteExitoso).cliente;
    expect(actualizado.logoAttachmentId, isNotNull);

    final adjunto = await attachmentRepo.obtenerPorId(actualizado.logoAttachmentId!);
    expect(adjunto!.categoria, 'logo');
    expect(adjunto.estado, 'activo');
  });

  test('reemplazar el logo archiva el anterior — nunca lo borra', () async {
    final cliente = await clienteRepo.crear(
      ClienteCompanion.insert(codigo: 'CLI-000002', nombreComercial: 'Miluyole'),
    );

    final archivo1 = '${tempDir.path}/logo1.png';
    File(archivo1).writeAsStringSync('contenido 1');
    final primero = await registrarLogo.ejecutar(
      clienteId: cliente.id,
      sourceFilePath: archivo1,
      originalFileName: 'logo1.png',
      mimeType: 'image/png',
    ) as RegistrarLogoClienteExitoso;
    final primerId = primero.cliente.logoAttachmentId!;

    final archivo2 = '${tempDir.path}/logo2.png';
    File(archivo2).writeAsStringSync('contenido 2');
    final segundo = await registrarLogo.ejecutar(
      clienteId: cliente.id,
      sourceFilePath: archivo2,
      originalFileName: 'logo2.png',
      mimeType: 'image/png',
    ) as RegistrarLogoClienteExitoso;
    final segundoId = segundo.cliente.logoAttachmentId!;

    expect(segundoId, isNot(primerId));
    final anterior = await attachmentRepo.obtenerPorId(primerId);
    expect(anterior!.estado, 'archivado', reason: 'el logo reemplazado se archiva, nunca se borra físicamente');
  });

  test('eliminar el logo deja logoAttachmentId en NULL y archiva el Attachment', () async {
    final cliente = await clienteRepo.crear(
      ClienteCompanion.insert(codigo: 'CLI-000003', nombreComercial: 'Atlacomulco Corp'),
    );
    final archivo = '${tempDir.path}/logo.png';
    File(archivo).writeAsStringSync('contenido');
    final registrado = await registrarLogo.ejecutar(
      clienteId: cliente.id,
      sourceFilePath: archivo,
      originalFileName: 'logo.png',
      mimeType: 'image/png',
    ) as RegistrarLogoClienteExitoso;
    final attachmentId = registrado.cliente.logoAttachmentId!;

    final resultado = await eliminarLogo.ejecutar(cliente.id);

    expect(resultado, isA<EliminarLogoClienteExitoso>());
    final actualizado = (resultado as EliminarLogoClienteExitoso).cliente;
    expect(actualizado.logoAttachmentId, isNull, reason: 'a diferencia de la fotografía de Empleado, el logo sí puede quedar vacío');

    final adjunto = await attachmentRepo.obtenerPorId(attachmentId);
    expect(adjunto!.estado, 'archivado');
  });

  test('eliminar el logo cuando no hay ninguno reporta SinLogo, sin tocar nada', () async {
    final cliente = await clienteRepo.crear(
      ClienteCompanion.insert(codigo: 'CLI-000004', nombreComercial: 'Sin Logo S.A.'),
    );

    final resultado = await eliminarLogo.ejecutar(cliente.id);
    expect(resultado, isA<EliminarLogoClienteSinLogo>());
  });

  test('registrar el logo de un Cliente inexistente reporta NoExiste', () async {
    final resultado = await registrarLogo.ejecutar(
      clienteId: 'no-existe',
      sourceFilePath: '${tempDir.path}/x.png',
      originalFileName: 'x.png',
      mimeType: 'image/png',
    );
    expect(resultado, isA<RegistrarLogoClienteNoExiste>());
  });
}
