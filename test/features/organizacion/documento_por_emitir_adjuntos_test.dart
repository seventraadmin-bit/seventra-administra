import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/attachments/attachment_repository.dart';
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_por_cobrar_repository_impl.dart';
import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/database/tables/attachment_table.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/configuracion_cobro_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/documento_por_emitir_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_portal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/entidad_fiscal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_comercial_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/adjuntar_archivo_documento_por_emitir_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_etapa_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_configuracion_cobro_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_documento_manual_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/ensamblar_documento_por_emitir_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_servicio_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/reemplazar_archivo_documento_por_emitir_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';

void main() {
  late AppDatabase db;
  late DocumentoPorEmitirRepositoryImpl documentoRepo;
  late AttachmentRepository attachmentRepo;
  late CrearDocumentoManualUseCase crearManual;
  late AdjuntarArchivoDocumentoPorEmitirUseCase adjuntar;
  late ReemplazarArchivoDocumentoPorEmitirUseCase reemplazar;
  late Directory tempDir;
  late String sourceFilePath;

  Future<String> crearDocumentoDePrueba({TipoDocumentoCobro tipoDocumento = TipoDocumentoCobro.reciboDePago}) async {
    final clienteRepo = ClienteRepositoryImpl(db);
    final servicioRepo = ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db));
    final catalogoRepo = CatalogoRepositoryImpl(db);
    final entidadFiscalRepo = EntidadFiscalRepositoryImpl(db);
    final clientePortalRepo = ClientePortalRepositoryImpl(db);
    final comercialRepo = ServicioComercialRepositoryImpl(db);
    final configuracionCobroRepo = ConfiguracionCobroRepositoryImpl(db);
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    final servicioValidator = ServicioValidator(clienteRepo, catalogoRepo);
    final configuracionCobroValidator =
        ConfiguracionCobroValidator(servicioRepo, entidadFiscalRepo, catalogoRepo, comercialRepo, clientePortalRepo);
    final crearServicio = CrearServicioUseCase(servicioRepo, generarCodigo, servicioValidator);
    final crearConfiguracionCobro = CrearConfiguracionCobroUseCase(
      configuracionCobroRepo,
      servicioRepo,
      configuracionCobroValidator,
      const ConfiguracionCobroEtapaValidator(),
    );

    final cliente = await clienteRepo.crear(ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Morgan'));

    String? entidadFiscalId;
    if (tipoDocumento == TipoDocumentoCobro.cfdi) {
      final entidad = await entidadFiscalRepo.crear(
        EntidadFiscalCompanion.insert(
          codigo: 'ENF-000001',
          clienteId: cliente.id,
          razonSocial: 'Morgan SA de CV',
          rfc: 'MOR010101AAA',
        ),
      );
      entidadFiscalId = entidad.id;
    }

    final servicioCreado = await crearServicio.ejecutar(
      clienteId: cliente.id,
      borrador: ServicioBorrador(
        nombre: 'Vigilancia Morgan',
        tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
        fechaInicio: DateTime(2026, 1, 1),
      ),
    );
    final servicioId = (servicioCreado as GuardarServicioExitoso).servicio.id;

    await crearConfiguracionCobro.ejecutar(
      servicioId: servicioId,
      borrador: ConfiguracionCobroBorrador(
        tipoDocumento: tipoDocumento,
        frecuenciaId: SeedIds.frecuenciaCobroMensual,
        diaInicioPeriodo: 1,
        agrupacion: AgrupacionCobro.porServicio,
        metodo: tipoDocumento == TipoDocumentoCobro.cfdi ? MetodoPagoCobro.pue : MetodoPagoCobro.noAplica,
        requiereComplemento: false,
        fechaInicioVigencia: DateTime(2026, 1, 1),
        entidadFiscalId: entidadFiscalId,
      ),
    );

    final resultado = await crearManual.ejecutar(
      clienteId: cliente.id,
      servicioIds: [servicioId],
      periodoInicio: DateTime(2026, 1, 1),
      periodoFin: DateTime(2026, 1, 31),
      entidadFiscalId: entidadFiscalId,
    );
    return (resultado as CrearDocumentoManualExitoso).documento.id;
  }

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    attachmentRepo = AttachmentRepository(db);
    documentoRepo = DocumentoPorEmitirRepositoryImpl(db, attachmentRepo, CuentaPorCobrarRepositoryImpl(db));
    final comercialRepo = ServicioComercialRepositoryImpl(db);
    final configuracionCobroRepo = ConfiguracionCobroRepositoryImpl(db);
    final servicioRepo = ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db));
    final ensamblar = EnsamblarDocumentoPorEmitirUseCase(comercialRepo, configuracionCobroRepo);
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    crearManual = CrearDocumentoManualUseCase(documentoRepo, configuracionCobroRepo, servicioRepo, ensamblar, generarCodigo);

    tempDir = Directory.systemTemp.createTempSync('riseg_adjuntos_test_');
    final storage = AttachmentStorage(tempDir.path);
    adjuntar = AdjuntarArchivoDocumentoPorEmitirUseCase(documentoRepo, storage);
    reemplazar = ReemplazarArchivoDocumentoPorEmitirUseCase(documentoRepo, attachmentRepo, storage);

    sourceFilePath = '${tempDir.path}/origen.tmp';
    File(sourceFilePath).writeAsStringSync('contenido de prueba');
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('AdjuntarArchivoDocumentoPorEmitirUseCase — casos reales obligatorios', () {
    test('adjunta CFDI PDF y XML a un documento CFDI', () async {
      final documentoId = await crearDocumentoDePrueba(tipoDocumento: TipoDocumentoCobro.cfdi);

      final pdf = await adjuntar.ejecutar(
        documentoPorEmitirId: documentoId,
        categoria: CategoriaAdjuntoDocumentoPorEmitir.cfdiPdf,
        sourceFilePath: sourceFilePath,
        originalFileName: 'factura enero.pdf',
        mimeType: 'application/pdf',
      );
      expect(pdf, isA<AdjuntarArchivoDocumentoPorEmitirExitoso>());

      final xml = await adjuntar.ejecutar(
        documentoPorEmitirId: documentoId,
        categoria: CategoriaAdjuntoDocumentoPorEmitir.cfdiXml,
        sourceFilePath: sourceFilePath,
        originalFileName: 'factura enero.xml',
        mimeType: 'text/xml',
      );
      expect(xml, isA<AdjuntarArchivoDocumentoPorEmitirExitoso>());

      final activos = await attachmentRepo.listarActivosPorDocumentoPorEmitir(documentoId);
      expect(activos, hasLength(2));
    });

    test('adjunta recibo PDF a un documento de recibo', () async {
      final documentoId = await crearDocumentoDePrueba();

      final resultado = await adjuntar.ejecutar(
        documentoPorEmitirId: documentoId,
        categoria: CategoriaAdjuntoDocumentoPorEmitir.reciboPdf,
        sourceFilePath: sourceFilePath,
        originalFileName: 'recibo enero.pdf',
        mimeType: 'application/pdf',
      );
      expect(resultado, isA<AdjuntarArchivoDocumentoPorEmitirExitoso>());
    });

    test('rechaza CFDI PDF/XML en un documento de recibo (categoría incompatible)', () async {
      final documentoId = await crearDocumentoDePrueba();

      final resultado = await adjuntar.ejecutar(
        documentoPorEmitirId: documentoId,
        categoria: CategoriaAdjuntoDocumentoPorEmitir.cfdiPdf,
        sourceFilePath: sourceFilePath,
        originalFileName: 'factura.pdf',
        mimeType: 'application/pdf',
      );
      expect(resultado, isA<AdjuntarArchivoDocumentoPorEmitirCategoriaIncompatible>());
    });

    test('rechaza recibo PDF en un documento CFDI (categoría incompatible)', () async {
      final documentoId = await crearDocumentoDePrueba(tipoDocumento: TipoDocumentoCobro.cfdi);

      final resultado = await adjuntar.ejecutar(
        documentoPorEmitirId: documentoId,
        categoria: CategoriaAdjuntoDocumentoPorEmitir.reciboPdf,
        sourceFilePath: sourceFilePath,
        originalFileName: 'recibo.pdf',
        mimeType: 'application/pdf',
      );
      expect(resultado, isA<AdjuntarArchivoDocumentoPorEmitirCategoriaIncompatible>());
    });

    test('rechaza un tipo de archivo que no corresponde a la categoría', () async {
      final documentoId = await crearDocumentoDePrueba();

      final resultado = await adjuntar.ejecutar(
        documentoPorEmitirId: documentoId,
        categoria: CategoriaAdjuntoDocumentoPorEmitir.reciboPdf,
        sourceFilePath: sourceFilePath,
        originalFileName: 'recibo.xml',
        mimeType: 'text/xml',
      );
      expect(resultado, isA<AdjuntarArchivoDocumentoPorEmitirTipoArchivoInvalido>());
    });

    test('otroSoporte acepta cualquier tipo de archivo, sin restricción', () async {
      final documentoId = await crearDocumentoDePrueba();

      final resultado = await adjuntar.ejecutar(
        documentoPorEmitirId: documentoId,
        categoria: CategoriaAdjuntoDocumentoPorEmitir.otroSoporte,
        sourceFilePath: sourceFilePath,
        originalFileName: 'evidencia.jpg',
        mimeType: 'image/jpeg',
      );
      expect(resultado, isA<AdjuntarArchivoDocumentoPorEmitirExitoso>());
    });

    test('varios archivos en la misma categoría coexisten', () async {
      final documentoId = await crearDocumentoDePrueba();

      await adjuntar.ejecutar(
        documentoPorEmitirId: documentoId,
        categoria: CategoriaAdjuntoDocumentoPorEmitir.otroSoporte,
        sourceFilePath: sourceFilePath,
        originalFileName: 'anexo1.jpg',
        mimeType: 'image/jpeg',
      );
      await adjuntar.ejecutar(
        documentoPorEmitirId: documentoId,
        categoria: CategoriaAdjuntoDocumentoPorEmitir.otroSoporte,
        sourceFilePath: sourceFilePath,
        originalFileName: 'anexo2.jpg',
        mimeType: 'image/jpeg',
      );

      final activos = await attachmentRepo.listarActivosPorDocumentoPorEmitir(
        documentoId,
        categoria: CategoriaAdjuntoDocumentoPorEmitir.otroSoporte.name,
      );
      expect(activos, hasLength(2));
    });

    test('storedFileName nunca es igual a originalFileName (regla de negocio permanente)', () async {
      final documentoId = await crearDocumentoDePrueba();

      final resultado = await adjuntar.ejecutar(
        documentoPorEmitirId: documentoId,
        categoria: CategoriaAdjuntoDocumentoPorEmitir.reciboPdf,
        sourceFilePath: sourceFilePath,
        originalFileName: 'recibo con espacios y ñ.pdf',
        mimeType: 'application/pdf',
      );
      final adjunto = (resultado as AdjuntarArchivoDocumentoPorEmitirExitoso).adjunto;
      expect(adjunto.storedFileName, isNot('recibo con espacios y ñ.pdf'));
      expect(adjunto.originalFileName, 'recibo con espacios y ñ.pdf');
      expect(adjunto.storedFileName, endsWith('.pdf'));
      expect(File(adjunto.path).existsSync(), isTrue);
    });

    test('registra el evento archivoAdjuntado', () async {
      final documentoId = await crearDocumentoDePrueba();

      await adjuntar.ejecutar(
        documentoPorEmitirId: documentoId,
        categoria: CategoriaAdjuntoDocumentoPorEmitir.reciboPdf,
        sourceFilePath: sourceFilePath,
        originalFileName: 'recibo.pdf',
        mimeType: 'application/pdf',
      );

      final eventos = await documentoRepo.listarEventos(documentoId);
      final evento = eventos.firstWhere((e) => e.tipoEvento == 'archivoAdjuntado');
      expect(evento.datosRelevantes, contains('reciboPdf'));
      expect(evento.datosRelevantes, contains('recibo.pdf'));
    });
  });

  group('ReemplazarArchivoDocumentoPorEmitirUseCase', () {
    test('el archivo anterior queda archivado, nunca se borra físicamente, y se registra el evento con ambos archivos',
        () async {
      final documentoId = await crearDocumentoDePrueba();
      final primero = await adjuntar.ejecutar(
        documentoPorEmitirId: documentoId,
        categoria: CategoriaAdjuntoDocumentoPorEmitir.reciboPdf,
        sourceFilePath: sourceFilePath,
        originalFileName: 'recibo-v1.pdf',
        mimeType: 'application/pdf',
      );
      final anterior = (primero as AdjuntarArchivoDocumentoPorEmitirExitoso).adjunto;

      final resultado = await reemplazar.ejecutar(
        documentoPorEmitirId: documentoId,
        attachmentAnteriorId: anterior.id,
        categoria: CategoriaAdjuntoDocumentoPorEmitir.reciboPdf,
        sourceFilePath: sourceFilePath,
        originalFileName: 'recibo-v2.pdf',
        mimeType: 'application/pdf',
        motivo: 'Corrección de folio',
      );
      expect(resultado, isA<ReemplazarArchivoDocumentoPorEmitirExitoso>());

      // Nunca se borra físicamente.
      expect(File(anterior.path).existsSync(), isTrue);

      final anteriorActualizado = await attachmentRepo.obtenerPorId(anterior.id);
      expect(anteriorActualizado!.estado, 'archivado');

      final activos = await attachmentRepo.listarActivosPorDocumentoPorEmitir(documentoId);
      expect(activos, hasLength(1));
      expect(activos.single.originalFileName, 'recibo-v2.pdf');

      final archivados = await attachmentRepo.listarArchivadosPorDocumentoPorEmitir(documentoId);
      expect(archivados, hasLength(1));
      expect(archivados.single.originalFileName, 'recibo-v1.pdf');

      final eventos = await documentoRepo.listarEventos(documentoId);
      final evento = eventos.firstWhere((e) => e.tipoEvento == 'archivoReemplazado');
      expect(evento.observacion, 'Corrección de folio');
      expect(evento.datosRelevantes, contains('recibo-v1.pdf'));
      expect(evento.datosRelevantes, contains('recibo-v2.pdf'));
    });

    test('rechaza reemplazar un archivo que ya está archivado', () async {
      final documentoId = await crearDocumentoDePrueba();
      final primero = await adjuntar.ejecutar(
        documentoPorEmitirId: documentoId,
        categoria: CategoriaAdjuntoDocumentoPorEmitir.reciboPdf,
        sourceFilePath: sourceFilePath,
        originalFileName: 'recibo-v1.pdf',
        mimeType: 'application/pdf',
      );
      final anterior = (primero as AdjuntarArchivoDocumentoPorEmitirExitoso).adjunto;

      await reemplazar.ejecutar(
        documentoPorEmitirId: documentoId,
        attachmentAnteriorId: anterior.id,
        categoria: CategoriaAdjuntoDocumentoPorEmitir.reciboPdf,
        sourceFilePath: sourceFilePath,
        originalFileName: 'recibo-v2.pdf',
        mimeType: 'application/pdf',
      );

      // Intentar reemplazar la v1 (ya archivada) otra vez.
      final resultado = await reemplazar.ejecutar(
        documentoPorEmitirId: documentoId,
        attachmentAnteriorId: anterior.id,
        categoria: CategoriaAdjuntoDocumentoPorEmitir.reciboPdf,
        sourceFilePath: sourceFilePath,
        originalFileName: 'recibo-v3.pdf',
        mimeType: 'application/pdf',
      );
      expect(resultado, isA<ReemplazarArchivoDocumentoPorEmitirArchivoYaArchivado>());
    });

    test('rechaza reemplazar con una categoría incompatible con el tipo de documento', () async {
      final documentoId = await crearDocumentoDePrueba();
      final primero = await adjuntar.ejecutar(
        documentoPorEmitirId: documentoId,
        categoria: CategoriaAdjuntoDocumentoPorEmitir.reciboPdf,
        sourceFilePath: sourceFilePath,
        originalFileName: 'recibo-v1.pdf',
        mimeType: 'application/pdf',
      );
      final anterior = (primero as AdjuntarArchivoDocumentoPorEmitirExitoso).adjunto;

      final resultado = await reemplazar.ejecutar(
        documentoPorEmitirId: documentoId,
        attachmentAnteriorId: anterior.id,
        categoria: CategoriaAdjuntoDocumentoPorEmitir.cfdiPdf,
        sourceFilePath: sourceFilePath,
        originalFileName: 'factura.pdf',
        mimeType: 'application/pdf',
      );
      expect(resultado, isA<ReemplazarArchivoDocumentoPorEmitirCategoriaIncompatible>());
    });
  });
}
