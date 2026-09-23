// Etapa 1B (cierre de seguridad): `generarTarjetaFiscalPdfAutorizadoProvider`
// antes llamaba al use case crudo sin ningún `autorizarUseCase` en la
// cadena — hueco real encontrado en la auditoría. Ahora gatea con
// `organizacion.ver` (nunca `crear`/`modificar`): es una operación de
// solo lectura/generación de documento sobre datos de Empresa que el
// usuario ya puede ver en la propia ficha, nunca escribe en BD.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/attachments/attachment_repository.dart';
import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/organizacion/data/pdf/tarjeta_fiscal_pdf_renderer.dart';
import 'package:riseg_one/features/organizacion/data/repositories/empresa_repository_impl.dart';
import 'package:riseg_one/features/organizacion/domain/shared/direccion_input.dart';
import 'package:riseg_one/features/organizacion/domain/shared/medio_contacto_input.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/generar_tarjeta_fiscal_pdf_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/obtener_empresa_activa_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/obtener_expediente_empresa_usecase.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import '../../support/sesion_en_base.dart';

/// `AttachmentStorage.abrir` invocaría `cmd /c start` real — se
/// sobreescribe para solo registrar la llamada, mismo patrón que
/// `generar_tarjeta_fiscal_pdf_usecase_test.dart`.
class _AttachmentStorageDePrueba extends AttachmentStorage {
  _AttachmentStorageDePrueba(super.attachmentsDir);
  final rutasAbiertas = <String>[];

  @override
  Future<void> abrir(String path) async {
    rutasAbiertas.add(path);
  }
}

class _SesionSinPermiso extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-normal',
      nombre: 'Usuario normal',
      nombreUsuario: 'normal',
      esMaestro: false,
      // Ningún permiso de Organización, en particular NO organizacion.ver.
      permisos: {'personal.ver'},
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
      permisos: {'organizacion.ver'},
    );
  }
}

class _SesionMaestro extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-maestro',
      nombre: 'Maestro de prueba',
      nombreUsuario: 'maestro',
      esMaestro: true,
      // El Maestro nunca tiene filas de PermisoUsuario — pasa igual.
      permisos: {},
    );
  }
}

void main() {
  late AppDatabase db;
  late Directory tempDir;
  late EmpresaRepositoryImpl empresaRepo;
  late String empresaId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    tempDir = Directory.systemTemp.createTempSync('riseg_tarjeta_fiscal_autorizacion_test_');

    empresaRepo = EmpresaRepositoryImpl(db);
    final empresaSemilla = await empresaRepo.obtenerActiva();
    empresaId = empresaSemilla.id;

    // Completa los 3 campos indispensables (razón social, RFC, domicilio
    // fiscal) para que el caso positivo genere el PDF de verdad, en vez
    // de quedar bloqueado por `GenerarTarjetaFiscalPdfDatosIncompletos`
    // (que no es lo que esta prueba de autorización quiere ejercitar).
    await empresaRepo.guardarExpediente(
      empresaId: empresaId,
      datosGenerales: const EmpresaCompanion(
        razonSocial: Value('CORPORATIVO DE SEGURIDAD PRIVADA RIZEG SAS DE CV'),
        rfc: Value('CSP123456AB1'),
      ),
      direccionFiscal: const DireccionInput(
        calle: 'Valle de los Reyes',
        numeroExterior: '2',
        numeroInterior: '9',
        colonia: 'Valle del Nevado',
        municipioAlcaldia: 'Calimaya',
        estado: 'Estado de México',
        codigoPostal: '52224',
      ),
      medioContacto: const MedioContactoInput(correo: 'facturacion@riseg.mx', telefono: '5555555555'),
    );
  });

  tearDown(() {
    db.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  // `generarTarjetaFiscalPdfUseCaseProvider` lee `appPathsProvider`
  // directo (`datosFiscalesDir`), y `appPathsProvider` solo se resuelve
  // en bootstrap real (`path_provider`, no disponible en pruebas
  // unitarias) — así que se sobreescribe el UseCase completo con una
  // instancia manual apuntando al directorio temporal, mismo criterio
  // que `attachmentStorageProvider` en los demás archivos de prueba de
  // autorización. La autorización en sí (`autorizarUseCase` +
  // `organizacion.ver`) sigue viniendo 100% del contenedor real.
  Future<ProviderContainer> containerCon(SesionController Function() sesion) async {
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      sesionControllerProvider.overrideWith(sesion),
      generarTarjetaFiscalPdfUseCaseProvider.overrideWithValue(
        GenerarTarjetaFiscalPdfUseCase(
          ObtenerExpedienteEmpresaUseCase(ObtenerEmpresaActivaUseCase(empresaRepo), empresaRepo),
          AttachmentRepository(db),
          _AttachmentStorageDePrueba(tempDir.path),
          '${tempDir.path}/datos_fiscales',
          TarjetaFiscalPdfRenderer(),
        ),
      ),
    ]);
    // Etapa 3B: la autorización se revalida contra la base. Se
    // persiste la sesión que ESTA prueba va a usar, leída del
    // propio contenedor: el escenario sembrado y el inyectado no
    // pueden divergir, y una prueba negativa sigue sin permisos.
    final sesionDeLaPrueba = container.read(sesionControllerProvider);
    if (sesionDeLaPrueba != null) await sembrarSesionEnBase(db, sesionDeLaPrueba);
    return container;
  }

  test('un usuario sin organizacion.ver no puede generar la tarjeta fiscal', () async {
    final container = await containerCon(_SesionSinPermiso.new);
    addTearDown(container.dispose);

    final resultado = await container.read(generarTarjetaFiscalPdfAutorizadoProvider)();

    expect(resultado, isA<GenerarTarjetaFiscalPdfErrorInesperado>());
    expect(
      (resultado as GenerarTarjetaFiscalPdfErrorInesperado).mensaje,
      'No tiene permiso para realizar esta acción.',
    );
  });

  test('un usuario con organizacion.ver sí puede generar la tarjeta fiscal', () async {
    final container = await containerCon(_SesionConPermiso.new);
    addTearDown(container.dispose);

    final resultado = await container.read(generarTarjetaFiscalPdfAutorizadoProvider)();

    expect(resultado, isA<GenerarTarjetaFiscalPdfExitoso>());
    final ruta = (resultado as GenerarTarjetaFiscalPdfExitoso).rutaArchivo;
    expect(File(ruta).existsSync(), isTrue);
  });

  test('el Usuario Maestro (sin filas de PermisoUsuario) sí puede generar la tarjeta fiscal', () async {
    final container = await containerCon(_SesionMaestro.new);
    addTearDown(container.dispose);

    final resultado = await container.read(generarTarjetaFiscalPdfAutorizadoProvider)();

    expect(resultado, isA<GenerarTarjetaFiscalPdfExitoso>());
  });

  test('generar la tarjeta fiscal nunca muta Empresa ni crea ningún Attachment', () async {
    final container = await containerCon(_SesionConPermiso.new);
    addTearDown(container.dispose);

    final empresaAntes = await container.read(empresaRepositoryProvider).obtenerActiva();
    final attachmentsAntes = await (db.select(db.attachment)).get();

    final resultado = await container.read(generarTarjetaFiscalPdfAutorizadoProvider)();
    expect(resultado, isA<GenerarTarjetaFiscalPdfExitoso>());

    final empresaDespues = await container.read(empresaRepositoryProvider).obtenerActiva();
    final attachmentsDespues = await (db.select(db.attachment)).get();

    expect(empresaDespues, empresaAntes, reason: 'la fila de Empresa nunca cambia al generar el PDF');
    expect(
      attachmentsDespues.length,
      attachmentsAntes.length,
      reason: 'la tarjeta fiscal es 100% regenerable, nunca persiste un Attachment nuevo',
    );
  });
}
