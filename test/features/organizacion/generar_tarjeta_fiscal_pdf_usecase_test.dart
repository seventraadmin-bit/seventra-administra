// Etapa 16 — Generar PDF de la Tarjeta fiscal de Empresa. Mismo
// criterio que `generar_recibo_pago_pdf_test.dart`: datos de entrada
// desde una base de datos real, contenido binario del PDF no se
// verifica byte a byte (sin infraestructura de parseo de PDF en el
// proyecto) — solo `%PDF`/tamaño, y que el tamaño crece con el logo
// embebido.

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/attachments/attachment_repository.dart';
import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/data/pdf/tarjeta_fiscal_pdf_renderer.dart';
import 'package:riseg_one/features/organizacion/data/repositories/empresa_repository_impl.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/generar_tarjeta_fiscal_pdf_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/obtener_empresa_activa_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/obtener_expediente_empresa_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/tarjeta_fiscal_data.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/validar_datos_fiscales_tarjeta.dart';
import 'package:riseg_one/features/organizacion/domain/shared/direccion_input.dart';
import 'package:riseg_one/features/organizacion/domain/shared/medio_contacto_input.dart';

/// `AttachmentStorage.abrir` invocaría `cmd /c start` real — se
/// sobreescribe para solo registrar la llamada, mismo patrón que
/// `generar_recibo_pago_pdf_test.dart`.
class _AttachmentStorageDePrueba extends AttachmentStorage {
  _AttachmentStorageDePrueba(super.attachmentsDir);
  final rutasAbiertas = <String>[];

  @override
  Future<void> abrir(String path) async {
    rutasAbiertas.add(path);
  }
}

void main() {
  late AppDatabase db;
  late Directory tempDir;
  late _AttachmentStorageDePrueba storage;
  late String datosFiscalesDir;
  late EmpresaRepositoryImpl empresaRepo;
  late GenerarTarjetaFiscalPdfUseCase generar;
  late String empresaId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    tempDir = Directory.systemTemp.createTempSync('riseg_tarjeta_fiscal_test_');
    storage = _AttachmentStorageDePrueba(tempDir.path);
    datosFiscalesDir = '${tempDir.path}/datos_fiscales';

    empresaRepo = EmpresaRepositoryImpl(db);
    final obtenerExpediente = ObtenerExpedienteEmpresaUseCase(ObtenerEmpresaActivaUseCase(empresaRepo), empresaRepo);
    generar = GenerarTarjetaFiscalPdfUseCase(
      obtenerExpediente,
      AttachmentRepository(db),
      storage,
      datosFiscalesDir,
      TarjetaFiscalPdfRenderer(),
    );

    // La Empresa sembrada por defecto nunca tiene razonSocial/rfc
    // capturados (Etapa 4B) — confirmado directamente aquí para no
    // depender de un supuesto no verificado.
    final empresaSemilla = await empresaRepo.obtenerActiva();
    empresaId = empresaSemilla.id;
    expect(empresaSemilla.razonSocial, isNull);
    expect(empresaSemilla.rfc, isNull);
  });

  tearDown(() async {
    await db.close();
    tempDir.deleteSync(recursive: true);
  });

  Future<void> completarDatosFiscales({bool conContacto = true}) async {
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
      medioContacto: conContacto ? const MedioContactoInput(correo: 'facturacion@riseg.mx', telefono: '5555555555') : null,
    );
  }

  group('validación de datos incompletos', () {
    test('Empresa recién sembrada (sin razón social/RFC/domicilio): bloquea con los 3 faltantes', () async {
      final resultado = await generar.ejecutar();

      expect(resultado, isA<GenerarTarjetaFiscalPdfDatosIncompletos>());
      final faltantes = (resultado as GenerarTarjetaFiscalPdfDatosIncompletos).faltantes;
      expect(faltantes, [CampoFiscalFaltante.razonSocial, CampoFiscalFaltante.rfc, CampoFiscalFaltante.domicilioFiscal]);
      expect(storage.rutasAbiertas, isEmpty, reason: 'nunca se genera ni se abre nada si faltan datos');
    });
  });

  group('Empresa completa — genera el PDF', () {
    test('genera el PDF, lo guarda en datosFiscalesDir, lo abre, y no persiste ningún Attachment', () async {
      await completarDatosFiscales();

      final resultado = await generar.ejecutar();

      expect(resultado, isA<GenerarTarjetaFiscalPdfExitoso>());
      final ruta = (resultado as GenerarTarjetaFiscalPdfExitoso).rutaArchivo;
      final bytes = await File(ruta).readAsBytes();
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
      expect(storage.rutasAbiertas, [ruta]);
      expect(ruta, contains('datos_fiscales'));

      final adjuntos = await (db.select(db.attachment)..limit(1)).get();
      expect(adjuntos, isEmpty, reason: 'la tarjeta fiscal es 100% regenerable, nunca un Attachment');
    });

    test('dirección SIN número interior también genera el PDF sin problema', () async {
      await empresaRepo.guardarExpediente(
        empresaId: empresaId,
        datosGenerales: const EmpresaCompanion(razonSocial: Value('Razón Social S.A. de C.V.'), rfc: Value('RSC123456AB1')),
        direccionFiscal: const DireccionInput(
          calle: 'Reforma',
          numeroExterior: '100',
          colonia: 'Centro',
          municipioAlcaldia: 'Toluca',
          estado: 'Estado de México',
          codigoPostal: '50000',
        ),
        medioContacto: null,
      );

      final resultado = await generar.ejecutar();
      expect(resultado, isA<GenerarTarjetaFiscalPdfExitoso>());
    });

    test('cambio posterior en Empresa aparece en una nueva generación (nunca reutiliza datos ya cargados)', () async {
      await completarDatosFiscales();
      final primero = await generar.ejecutar();
      expect(primero, isA<GenerarTarjetaFiscalPdfExitoso>());
      // Se lee de inmediato: `sanitizarNombreArchivo` solo tiene
      // granularidad de segundo (mismo hallazgo ya documentado en
      // `generar_recibo_pago_pdf_test.dart`) — dos generaciones en el
      // mismo segundo podrían compartir nombre de archivo, y la
      // segunda escritura sobrescribiría a la primera antes de leerla.
      final bytesPrimero = await File((primero as GenerarTarjetaFiscalPdfExitoso).rutaArchivo).readAsBytes();

      await empresaRepo.actualizarDatosGenerales(
        const EmpresaCompanion(razonSocial: Value('RAZÓN SOCIAL ACTUALIZADA SA DE CV')),
      );
      final actualizado = await empresaRepo.obtenerActiva();
      expect(actualizado.razonSocial, 'RAZÓN SOCIAL ACTUALIZADA SA DE CV');

      final segundo = await generar.ejecutar();
      expect(segundo, isA<GenerarTarjetaFiscalPdfExitoso>());
      final bytesSegundo = await File((segundo as GenerarTarjetaFiscalPdfExitoso).rutaArchivo).readAsBytes();

      // El PDF con la razón social actualizada tiene texto distinto —
      // si el use case reutilizara datos ya cargados (obsoletos), ambos
      // PDFs serían byte-idénticos.
      expect(bytesSegundo, isNot(equals(bytesPrimero)));
    });

    test('sin medio de contacto capturado — igual genera el PDF (correo/teléfono nunca son requeridos)', () async {
      await completarDatosFiscales(conContacto: false);

      final resultado = await generar.ejecutar();
      expect(resultado, isA<GenerarTarjetaFiscalPdfExitoso>());
    });
  });

  group('logotipo', () {
    test('usa el logotipo de Empresa (Attachment real) cuando existe — nunca el de respaldo', () async {
      await completarDatosFiscales();

      final logoDir = Directory('${tempDir.path}/logo_empresa')..createSync(recursive: true);
      final logoFile = File('${logoDir.path}/logo.png');
      await logoFile.writeAsBytes(await File('assets/images/logo.png').readAsBytes());
      final attachment = await AttachmentRepository(db).crear(
        AttachmentCompanion.insert(
          id: 'attachment-logo-empresa',
          originalFileName: 'logo.png',
          storedFileName: 'logo.png',
          path: logoFile.path,
          mimeType: 'image/png',
          sizeBytes: await logoFile.length(),
        ),
      );
      await empresaRepo.actualizarDatosGenerales(EmpresaCompanion(logoAttachmentId: Value(attachment.id)));

      final resultado = await generar.ejecutar();
      expect(resultado, isA<GenerarTarjetaFiscalPdfExitoso>());

      final obtenerExpediente = ObtenerExpedienteEmpresaUseCase(ObtenerEmpresaActivaUseCase(empresaRepo), empresaRepo);
      final expedienteResult = await obtenerExpediente.ejecutar();
      final expediente = expedienteResult.when(ok: (v) => v, failure: (_) => throw StateError('no debería fallar'));
      final sinLogoBytes = await TarjetaFiscalPdfRenderer().renderizar(data: construirTarjetaFiscalData(expediente));

      final ruta = (resultado as GenerarTarjetaFiscalPdfExitoso).rutaArchivo;
      final generado = await File(ruta).readAsBytes();
      expect(generado.length, greaterThan(sinLogoBytes.length), reason: 'el PDF real incluyó el logo de Empresa');
    });

    test('SIN logotipo de Empresa la tarjeta se emite sin logotipo — ya no hay asset de respaldo', () async {
      // Etapa 5B.2, mismo criterio que el recibo de pago.
      await completarDatosFiscales();

      final empresaSinLogo = await empresaRepo.obtenerActiva();
      expect(empresaSinLogo.logoAttachmentId, isNull);

      final resultado = await generar.ejecutar();
      expect(resultado, isA<GenerarTarjetaFiscalPdfExitoso>());

      final bytes = await File((resultado as GenerarTarjetaFiscalPdfExitoso).rutaArchivo).readAsBytes();
      expect(bytes, isNotEmpty);

      final escudo = await File('assets/images/logo.png').readAsBytes();
      expect(bytes.length, lessThan(escudo.length), reason: 'no puede llevar el escudo heredado embebido');
    });
  });
}
