// Etapa 0 (auditoría de consistencia transversal — corrección de un
// hueco real de autorización): el logo de Cliente se registraba/quitaba
// desde `logo_cliente_dialog.dart` directo sobre el use case crudo, sin
// ningún `autorizarUseCase` en la cadena. Mismo permiso que el resto de
// mutaciones de Cliente (`clientes.corregir`). Cubre
// `registrarLogoClienteAutorizadoProvider`/
// `eliminarLogoClienteAutorizadoProvider` de punta a punta: negativo
// (rechazo + `logoAttachmentId` intacto + cero `Attachment` nuevo) y
// positivo (éxito real, verificado en BD).

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/eliminar_logo_cliente_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/registrar_logo_cliente_usecase.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import '../../support/sesion_en_base.dart';

class _SesionSinPermiso extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-normal',
      nombre: 'Usuario normal',
      nombreUsuario: 'normal',
      esMaestro: false,
      // Tiene permisos de otros módulos, pero NUNCA clientes.corregir.
      permisos: {'comercial.ver', 'clientes.crear'},
    );
  }
}

class _SesionConPermiso extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-normal',
      nombre: 'Usuario normal',
      nombreUsuario: 'normal',
      esMaestro: false,
      permisos: {'comercial.ver', 'clientes.crear', 'clientes.corregir'},
    );
  }
}

void main() {
  late AppDatabase db;
  late Directory tempDir;
  late String clienteId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    tempDir = Directory.systemTemp.createTempSync('riseg_logo_cliente_p0_test_');

    final cliente = await ClienteRepositoryImpl(db).crear(
      ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Sportium'),
    );
    clienteId = cliente.id;
  });

  tearDown(() {
    db.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<ProviderContainer> containerCon(SesionController Function() sesion) async {
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      sesionControllerProvider.overrideWith(sesion),
      attachmentStorageProvider.overrideWithValue(AttachmentStorage(tempDir.path)),
    ]);
    // Etapa 3B: la autorización se revalida contra la base. Se
    // persiste la sesión que ESTA prueba va a usar, leída del
    // propio contenedor: el escenario sembrado y el inyectado no
    // pueden divergir, y una prueba negativa sigue sin permisos.
    final sesionDeLaPrueba = container.read(sesionControllerProvider);
    if (sesionDeLaPrueba != null) await sembrarSesionEnBase(db, sesionDeLaPrueba);
    return container;
  }

  test('un usuario sin clientes.corregir no puede registrar el logo', () async {
    final container = await containerCon(_SesionSinPermiso.new);
    addTearDown(container.dispose);

    final totalAntes = (await db.select(db.attachment).get()).length;

    final archivo = '${tempDir.path}/logo.png';
    File(archivo).writeAsStringSync('contenido logo');

    final resultado = await container.read(registrarLogoClienteAutorizadoProvider)(
      clienteId: clienteId,
      sourceFilePath: archivo,
      originalFileName: 'logo.png',
      mimeType: 'image/png',
    );

    expect(resultado, isA<RegistrarLogoClienteErrorInesperado>());
    final cliente = await container.read(clienteRepositoryProvider).obtenerPorId(clienteId);
    expect(cliente!.logoAttachmentId, isNull, reason: 'nunca se registra el logo sin el permiso');
    expect(
      (await db.select(db.attachment).get()).length,
      totalAntes,
      reason: 'ningún Attachment nuevo sin el permiso',
    );
  });

  test('un usuario con clientes.corregir sí puede registrar el logo', () async {
    final container = await containerCon(_SesionConPermiso.new);
    addTearDown(container.dispose);

    final archivo = '${tempDir.path}/logo.png';
    File(archivo).writeAsStringSync('contenido logo');

    final resultado = await container.read(registrarLogoClienteAutorizadoProvider)(
      clienteId: clienteId,
      sourceFilePath: archivo,
      originalFileName: 'logo.png',
      mimeType: 'image/png',
    );

    expect(resultado, isA<RegistrarLogoClienteExitoso>());
    final cliente = (resultado as RegistrarLogoClienteExitoso).cliente;
    expect(cliente.logoAttachmentId, isNotNull);
    final adjunto = await container.read(attachmentRepositoryProvider).obtenerPorId(cliente.logoAttachmentId!);
    expect(adjunto!.categoria, 'logo');
    expect(adjunto.estado, 'activo');
  });

  test('un usuario sin clientes.corregir no puede eliminar el logo ya registrado', () async {
    final registrador = await containerCon(_SesionConPermiso.new);
    final archivo = '${tempDir.path}/logo.png';
    File(archivo).writeAsStringSync('contenido logo');
    final registrado = await registrador.read(registrarLogoClienteAutorizadoProvider)(
      clienteId: clienteId,
      sourceFilePath: archivo,
      originalFileName: 'logo.png',
      mimeType: 'image/png',
    ) as RegistrarLogoClienteExitoso;
    final attachmentId = registrado.cliente.logoAttachmentId!;
    registrador.dispose();

    final container = await containerCon(_SesionSinPermiso.new);
    addTearDown(container.dispose);

    final resultado = await container.read(eliminarLogoClienteAutorizadoProvider)(clienteId);

    expect(resultado, isA<EliminarLogoClienteErrorInesperado>());
    final cliente = await container.read(clienteRepositoryProvider).obtenerPorId(clienteId);
    expect(cliente!.logoAttachmentId, attachmentId, reason: 'nunca se quita el logo sin el permiso');
    final adjunto = await container.read(attachmentRepositoryProvider).obtenerPorId(attachmentId);
    expect(adjunto!.estado, 'activo', reason: 'nunca se archiva el Attachment sin el permiso');
  });

  test('un usuario con clientes.corregir sí puede eliminar el logo', () async {
    final registrador = await containerCon(_SesionConPermiso.new);
    final archivo = '${tempDir.path}/logo.png';
    File(archivo).writeAsStringSync('contenido logo');
    final registrado = await registrador.read(registrarLogoClienteAutorizadoProvider)(
      clienteId: clienteId,
      sourceFilePath: archivo,
      originalFileName: 'logo.png',
      mimeType: 'image/png',
    ) as RegistrarLogoClienteExitoso;
    final attachmentId = registrado.cliente.logoAttachmentId!;
    registrador.dispose();

    final container = await containerCon(_SesionConPermiso.new);
    addTearDown(container.dispose);

    final resultado = await container.read(eliminarLogoClienteAutorizadoProvider)(clienteId);

    expect(resultado, isA<EliminarLogoClienteExitoso>());
    final cliente = (resultado as EliminarLogoClienteExitoso).cliente;
    expect(cliente.logoAttachmentId, isNull);
    final adjunto = await container.read(attachmentRepositoryProvider).obtenerPorId(attachmentId);
    expect(adjunto!.estado, 'archivado');
  });
}
