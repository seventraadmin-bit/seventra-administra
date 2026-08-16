// Etapa 15 (Agenda) — Generar recibo PDF. Todos los datos de entrada
// (`DocumentoPorEmitirDetalle`, `ClienteData`, `EmpresaData`) se
// obtienen de una base de datos real (misma convención que el resto
// del proyecto) en vez de construir a mano los objetos generados por
// Drift, que tienen muchos campos y son fáciles de armar mal. El
// contenido del PDF binario no se verifica byte a byte (no hay
// infraestructura de parseo de PDF en el proyecto — mismo criterio ya
// usado en `reportes_exportacion_test.dart`/`ficha_tecnica_empleado_test.dart`,
// que solo confirman `%PDF`/tamaño > 0); en su lugar,
// `construirReciboPagoPdfData` (función pura) se prueba directamente
// para verificar con precisión que el total impreso coincide con
// `importeFinalEsperado` y que IVA "No aplica" nunca agrega un monto
// de IVA inventado.

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/attachments/attachment_repository.dart';
import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/cuenta_por_cobrar_repository.dart';
import 'package:riseg_one/features/organizacion/data/pdf/recibo_pago_pdf_renderer.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/configuracion_cobro_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/documento_por_emitir_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/empresa_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/puesto_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_comercial_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_linea_comercial_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_linea_comercial_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/generar_recibo_pago_pdf_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_servicio_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/linea_comercial_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/recibo_pago_pdf_data.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';

/// `AttachmentStorage.abrir` invocaría `cmd /c start` real — se
/// sobreescribe para solo registrar la llamada, mismo patrón que
/// `_AttachmentStorageDePrueba` en `reportes_exportacion_test.dart`.
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
  late String recibosDir;

  late ClienteRepositoryImpl clienteRepo;
  late ServicioRepositoryImpl servicioRepo;
  late ServicioComercialRepositoryImpl comercialRepo;
  late DocumentoPorEmitirRepositoryImpl documentoRepo;
  late EmpresaRepositoryImpl empresaRepo;
  late GenerarReciboPagoPdfUseCase generar;

  late String clienteId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    tempDir = Directory.systemTemp.createTempSync('riseg_recibo_pdf_test_');
    storage = _AttachmentStorageDePrueba(tempDir.path);
    recibosDir = '${tempDir.path}/recibos';

    clienteRepo = ClienteRepositoryImpl(db);
    servicioRepo = ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db));
    comercialRepo = ServicioComercialRepositoryImpl(db);
    documentoRepo = DocumentoPorEmitirRepositoryImpl(db, AttachmentRepository(db), _CuentaPorCobrarRepoNoUsado());
    empresaRepo = EmpresaRepositoryImpl(db);

    generar = GenerarReciboPagoPdfUseCase(
      documentoRepo,
      clienteRepo,
      servicioRepo,
      empresaRepo,
      AttachmentRepository(db),
      storage,
      recibosDir,
      ReciboPagoPdfRenderer(),
    );

    final cliente =
        await clienteRepo.crear(ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Sportium'));
    clienteId = cliente.id;
  });

  tearDown(() async {
    await db.close();
    tempDir.deleteSync(recursive: true);
  });

  Future<({String servicioId, String vigenciaId})> crearServicioConLineaDePrueba({
    TratamientoIva tratamientoIva = TratamientoIva.noAplica,
  }) async {
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    final crearServicio = CrearServicioUseCase(
      servicioRepo,
      generarCodigo,
      ServicioValidator(clienteRepo, CatalogoRepositoryImpl(db)),
    );
    final creado = await crearServicio.ejecutar(
      clienteId: clienteId,
      borrador: ServicioBorrador(
        nombre: 'Vigilancia Sportium',
        tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
        fechaInicio: DateTime(2026, 1, 1),
      ),
    );
    final servicioId = (creado as GuardarServicioExitoso).servicio.id;

    final puesto = await PuestoRepositoryImpl(db).crear(
      PuestoCompanion.insert(
        codigo: 'PUE-0001',
        nombre: 'Guardia',
        areaId: SeedIds.areaOperaciones,
        tipo: 'operativo',
        nivelJerarquico: 5,
      ),
    );

    final crearLinea = CrearLineaComercialUseCase(
      comercialRepo,
      servicioRepo,
      LineaComercialValidator(PuestoRepositoryImpl(db), CatalogoRepositoryImpl(db), servicioRepo, ConfiguracionCobroRepositoryImpl(db)),
    );
    final lineaCreada = await crearLinea.ejecutar(
      servicioId: servicioId,
      borrador: LineaComercialBorrador(
        puestoId: puesto.id,
        modalidadTurnoId: SeedIds.modalidadTurno24x24,
        cantidadElementos: 2,
        precioUnitario: 1500000,
        tratamientoIva: tratamientoIva,
        fechaInicioVigencia: DateTime(2026, 1, 1),
      ),
    ) as CrearLineaComercialExitoso;

    return (servicioId: servicioId, vigenciaId: lineaCreada.vigencia.id);
  }

  Future<String> crearDocumentoDePrueba({
    required String servicioId,
    String? vigenciaId,
    String codigo = 'DOC-0001',
    String tipoDocumento = 'reciboDePago',
    String metodo = 'noAplica',
    int importeBaseEsperado = 2180000,
    int? ajusteManual,
    int importeFinalEsperado = 2180000,
    TratamientoIva tratamientoIva = TratamientoIva.noAplica,
  }) async {
    final documento = await db.into(db.documentoPorEmitir).insertReturning(
          DocumentoPorEmitirCompanion.insert(
            codigo: codigo,
            clienteId: clienteId,
            tipoDocumento: tipoDocumento,
            agrupacion: 'porServicio',
            metodo: metodo,
            periodoInicio: DateTime(2026, 6, 1),
            periodoFin: DateTime(2026, 6, 30),
            generationKey: 'GK-$codigo',
            importeBaseEsperado: importeBaseEsperado,
            ajusteManual: Value(ajusteManual),
            importeFinalEsperado: importeFinalEsperado,
          ),
        );
    await db.into(db.documentoPorEmitirServicio).insert(
          DocumentoPorEmitirServicioCompanion.insert(documentoPorEmitirId: documento.id, servicioId: servicioId),
        );
    if (vigenciaId != null) {
      await db.into(db.documentoPorEmitirLinea).insert(
            DocumentoPorEmitirLineaCompanion.insert(
              documentoPorEmitirId: documento.id,
              servicioId: servicioId,
              lineaComercialVigenciaId: vigenciaId,
              puestoNombre: 'Guardia',
              modalidadTurnoNombre: '24×24',
              cantidadElementos: 2,
              precioUnitario: 1500000,
              tratamientoIva: tratamientoIva.name,
              diasAplicables: 30,
              subtotalProporcional: 3000000,
            ),
          );
    }
    return documento.id;
  }

  group('construirReciboPagoPdfData (pura, contra datos reales ya cargados)', () {
    test('el total impreso coincide con importeFinalEsperado', () async {
      final ctx = await crearServicioConLineaDePrueba();
      final documentoId = await crearDocumentoDePrueba(
        servicioId: ctx.servicioId,
        vigenciaId: ctx.vigenciaId,
        importeBaseEsperado: 2500000,
        ajusteManual: -320000,
        importeFinalEsperado: 2180000,
      );

      final detalle = (await documentoRepo.obtenerDetalle(documentoId))!;
      final cliente = await clienteRepo.obtenerPorId(clienteId);
      final empresa = await empresaRepo.obtenerActiva();

      final data = construirReciboPagoPdfData(
        detalle: detalle,
        cliente: cliente,
        servicios: const ['SRV-0001 - Vigilancia Sportium'],
        empresa: empresa,
      );

      expect(data.importeFinalEsperado, 2180000);
      expect(data.importeBaseEsperado, 2500000);
      expect(data.ajusteManual, -320000);
    });

    test('una línea "No aplica" se imprime con esa etiqueta, sin monto de IVA inventado', () async {
      final ctx = await crearServicioConLineaDePrueba(tratamientoIva: TratamientoIva.noAplica);
      final documentoId = await crearDocumentoDePrueba(
        servicioId: ctx.servicioId,
        vigenciaId: ctx.vigenciaId,
        tratamientoIva: TratamientoIva.noAplica,
      );

      final detalle = (await documentoRepo.obtenerDetalle(documentoId))!;
      final data = construirReciboPagoPdfData(
        detalle: detalle,
        cliente: await clienteRepo.obtenerPorId(clienteId),
        servicios: const ['SRV-0001 - Vigilancia Sportium'],
        empresa: await empresaRepo.obtenerActiva(),
      );

      expect(data.lineas.single.tratamientoIvaLabel, 'No aplica');
      expect(data.lineas.single.subtotalProporcional, detalle.lineas.single.subtotalProporcional);
    });

    test('una línea "Más IVA" se traduce a esa etiqueta (clasificación, no un monto calculado)', () async {
      final ctx = await crearServicioConLineaDePrueba(tratamientoIva: TratamientoIva.masIva);
      final documentoId = await crearDocumentoDePrueba(
        servicioId: ctx.servicioId,
        vigenciaId: ctx.vigenciaId,
        codigo: 'DOC-0002',
        tipoDocumento: 'cfdi',
        metodo: 'pue',
        tratamientoIva: TratamientoIva.masIva,
      );

      final detalle = (await documentoRepo.obtenerDetalle(documentoId))!;
      final data = construirReciboPagoPdfData(
        detalle: detalle,
        cliente: await clienteRepo.obtenerPorId(clienteId),
        servicios: const ['SRV-0001 - Vigilancia Sportium'],
        empresa: await empresaRepo.obtenerActiva(),
      );

      expect(data.lineas.single.tratamientoIvaLabel, 'Más IVA');
    });

    test('método "No aplica" (caso normal de un recibo) no se imprime', () async {
      final ctx = await crearServicioConLineaDePrueba();
      final documentoId = await crearDocumentoDePrueba(servicioId: ctx.servicioId, metodo: 'noAplica');

      final detalle = (await documentoRepo.obtenerDetalle(documentoId))!;
      final data = construirReciboPagoPdfData(
        detalle: detalle,
        cliente: await clienteRepo.obtenerPorId(clienteId),
        servicios: const [],
        empresa: await empresaRepo.obtenerActiva(),
      );

      expect(data.metodoLabel, isNull);
    });

    test('un método real (PUE) sí se imprime, ya traducido', () async {
      final ctx = await crearServicioConLineaDePrueba();
      final documentoId = await crearDocumentoDePrueba(servicioId: ctx.servicioId, codigo: 'DOC-0003', metodo: 'pue');

      final detalle = (await documentoRepo.obtenerDetalle(documentoId))!;
      final data = construirReciboPagoPdfData(
        detalle: detalle,
        cliente: await clienteRepo.obtenerPorId(clienteId),
        servicios: const [],
        empresa: await empresaRepo.obtenerActiva(),
      );

      expect(data.metodoLabel, 'PUE');
    });

    test('RFC ausente en Empresa no se inventa — queda null, nunca un placeholder', () async {
      final ctx = await crearServicioConLineaDePrueba();
      final documentoId = await crearDocumentoDePrueba(servicioId: ctx.servicioId);

      final empresa = await empresaRepo.obtenerActiva();
      expect(empresa.rfc, isNull, reason: 'la Empresa sembrada por defecto nunca tiene RFC capturado');

      final detalle = (await documentoRepo.obtenerDetalle(documentoId))!;
      final data = construirReciboPagoPdfData(
        detalle: detalle,
        cliente: await clienteRepo.obtenerPorId(clienteId),
        servicios: const [],
        empresa: empresa,
      );

      expect(data.empresaRfc, isNull);
    });
  });

  group('ReciboPagoPdfRenderer', () {
    test('produce un PDF válido y no vacío', () async {
      final ctx = await crearServicioConLineaDePrueba();
      final documentoId = await crearDocumentoDePrueba(servicioId: ctx.servicioId, vigenciaId: ctx.vigenciaId);

      final detalle = (await documentoRepo.obtenerDetalle(documentoId))!;
      final data = construirReciboPagoPdfData(
        detalle: detalle,
        cliente: await clienteRepo.obtenerPorId(clienteId),
        servicios: const ['SRV-0001 - Vigilancia Sportium'],
        empresa: await empresaRepo.obtenerActiva(),
      );

      final bytes = await ReciboPagoPdfRenderer().renderizar(data: data);
      expect(bytes.length, greaterThan(0));
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });

    test('con logotipo, el renderer realmente incluye una imagen — el PDF resultante es más grande', () async {
      final ctx = await crearServicioConLineaDePrueba();
      final documentoId = await crearDocumentoDePrueba(servicioId: ctx.servicioId, vigenciaId: ctx.vigenciaId);

      final detalle = (await documentoRepo.obtenerDetalle(documentoId))!;
      final data = construirReciboPagoPdfData(
        detalle: detalle,
        cliente: await clienteRepo.obtenerPorId(clienteId),
        servicios: const ['SRV-0001 - Vigilancia Sportium'],
        empresa: await empresaRepo.obtenerActiva(),
      );

      final logoBytes = await File('assets/images/logo.png').readAsBytes();
      final sinLogo = await ReciboPagoPdfRenderer().renderizar(data: data);
      final conLogo = await ReciboPagoPdfRenderer().renderizar(data: data, logoBytes: logoBytes);

      expect(String.fromCharCodes(conLogo.take(4)), '%PDF');
      expect(
        conLogo.length,
        greaterThan(sinLogo.length),
        reason: 'un PDF con la imagen del logo embebida debe pesar más que uno sin ella',
      );
    });
  });

  group('GenerarReciboPagoPdfUseCase — integración', () {
    test('Recibo de pago: genera el PDF, lo guarda en recibosDir, lo abre, y no persiste ningún Attachment', () async {
      final ctx = await crearServicioConLineaDePrueba();
      final documentoId = await crearDocumentoDePrueba(servicioId: ctx.servicioId, vigenciaId: ctx.vigenciaId);

      final resultado = await generar.ejecutar(documentoPorEmitirId: documentoId);

      expect(resultado, isA<GenerarReciboPagoPdfExitoso>());
      final ruta = (resultado as GenerarReciboPagoPdfExitoso).rutaArchivo;
      final bytes = await File(ruta).readAsBytes();
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
      expect(storage.rutasAbiertas, [ruta]);
      expect(ruta, contains('recibos'));

      final adjuntos = await (db.select(db.attachment)..limit(1)).get();
      expect(adjuntos, isEmpty, reason: 'el recibo generado es 100% regenerable, nunca un Attachment');
    });

    test('CFDI: no genera el recibo — RISEG ONE nunca sustituye ni imprime un CFDI', () async {
      final ctx = await crearServicioConLineaDePrueba();
      final documentoId = await crearDocumentoDePrueba(
        servicioId: ctx.servicioId,
        codigo: 'DOC-0002',
        tipoDocumento: 'cfdi',
      );

      final resultado = await generar.ejecutar(documentoPorEmitirId: documentoId);

      expect(resultado, isA<GenerarReciboPagoPdfTipoDocumentoInvalido>());
      expect(storage.rutasAbiertas, isEmpty);
    });

    test('documento inexistente', () async {
      final resultado = await generar.ejecutar(documentoPorEmitirId: 'no-existe');
      expect(resultado, isA<GenerarReciboPagoPdfNoExiste>());
    });

    test('usa el logotipo de Empresa (Attachment real) cuando existe — nunca el de respaldo', () async {
      final ctx = await crearServicioConLineaDePrueba();
      final documentoId = await crearDocumentoDePrueba(servicioId: ctx.servicioId, vigenciaId: ctx.vigenciaId);

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

      // Sin fallback: si el use case usara el de respaldo por error, el
      // PDF igual tendría un logo — la prueba real está en que el
      // resultado no depende de `logoFallbackBytes` en absoluto.
      final resultado = await generar.ejecutar(documentoPorEmitirId: documentoId);
      expect(resultado, isA<GenerarReciboPagoPdfExitoso>());

      final sinLogoBytes = await ReciboPagoPdfRenderer().renderizar(
        data: construirReciboPagoPdfData(
          detalle: (await documentoRepo.obtenerDetalle(documentoId))!,
          cliente: await clienteRepo.obtenerPorId(clienteId),
          servicios: const ['SRV-0001 - Vigilancia Sportium'],
          empresa: await empresaRepo.obtenerActiva(),
        ),
      );
      final ruta = (resultado as GenerarReciboPagoPdfExitoso).rutaArchivo;
      final generado = await File(ruta).readAsBytes();
      expect(generado.length, greaterThan(sinLogoBytes.length), reason: 'el PDF real incluyó el logo de Empresa');
    });

    test('usa el logotipo de respaldo (asset oficial) cuando Empresa no tiene uno configurado', () async {
      final ctx = await crearServicioConLineaDePrueba();
      final documentoId = await crearDocumentoDePrueba(servicioId: ctx.servicioId, vigenciaId: ctx.vigenciaId);

      final empresaSinLogo = await empresaRepo.obtenerActiva();
      expect(empresaSinLogo.logoAttachmentId, isNull, reason: 'no existe todavía ninguna pantalla de carga de logo');

      final logoFallbackBytes = await File('assets/images/logo.png').readAsBytes();

      // `sanitizarNombreArchivo` solo tiene granularidad de segundo — si
      // ambas rutas se leyeran al final, dos llamadas seguidas para el
      // mismo documento podrían colisionar en el mismo nombre de
      // archivo y la segunda sobrescribiría a la primera antes de
      // leerla. Se lee cada archivo de inmediato, antes de la siguiente
      // generación.
      final sinFallback = await generar.ejecutar(documentoPorEmitirId: documentoId);
      expect(sinFallback, isA<GenerarReciboPagoPdfExitoso>());
      final bytesSinFallback =
          await File((sinFallback as GenerarReciboPagoPdfExitoso).rutaArchivo).readAsBytes();

      final conFallback = await generar.ejecutar(documentoPorEmitirId: documentoId, logoFallbackBytes: logoFallbackBytes);
      expect(conFallback, isA<GenerarReciboPagoPdfExitoso>());
      final bytesConFallback =
          await File((conFallback as GenerarReciboPagoPdfExitoso).rutaArchivo).readAsBytes();

      expect(
        bytesConFallback.length,
        greaterThan(bytesSinFallback.length),
        reason: 'con logoFallbackBytes el PDF real debe incluir el asset oficial embebido',
      );
    });
  });
}

/// Nunca se llega a `procesadoAceptado` en estos escenarios de prueba,
/// así que `CuentaPorCobrarRepository` nunca se invoca — implementación
/// vacía únicamente para satisfacer el constructor de
/// `DocumentoPorEmitirRepositoryImpl`.
class _CuentaPorCobrarRepoNoUsado implements CuentaPorCobrarRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
