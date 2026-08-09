import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/attachments/attachment_repository.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/configuracion_cobro_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/documento_por_emitir_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/entidad_fiscal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_comercial_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/documento_por_emitir_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/actualizar_ajuste_manual_documento_por_emitir_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_estatus_documento_por_emitir_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_regla_evento_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/corregir_datos_emision_documento_por_emitir_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_configuracion_cobro_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_documento_manual_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/ensamblar_documento_por_emitir_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_servicio_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/registrar_emision_documento_por_emitir_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/registrar_envio_documento_por_emitir_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';

void main() {
  late AppDatabase db;
  late DocumentoPorEmitirRepositoryImpl documentoRepo;
  late CrearDocumentoManualUseCase crearManual;
  late RegistrarEmisionDocumentoPorEmitirUseCase registrarEmision;
  late CorregirDatosEmisionDocumentoPorEmitirUseCase corregirDatosEmision;
  late RegistrarEnvioDocumentoPorEmitirUseCase registrarEnvio;
  late CambiarEstatusDocumentoPorEmitirUseCase cambiarEstatus;
  late ActualizarAjusteManualDocumentoPorEmitirUseCase actualizarAjuste;

  Future<String> crearDocumentoDePrueba({TipoDocumentoCobro tipoDocumento = TipoDocumentoCobro.reciboDePago}) async {
    final clienteRepo = ClienteRepositoryImpl(db);
    final servicioRepo = ServicioRepositoryImpl(db);
    final catalogoRepo = CatalogoRepositoryImpl(db);
    final entidadFiscalRepo = EntidadFiscalRepositoryImpl(db);
    final comercialRepo = ServicioComercialRepositoryImpl(db);
    final configuracionCobroRepo = ConfiguracionCobroRepositoryImpl(db);
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    final servicioValidator = ServicioValidator(clienteRepo, catalogoRepo);
    final configuracionCobroValidator =
        ConfiguracionCobroValidator(servicioRepo, entidadFiscalRepo, catalogoRepo, comercialRepo);
    final crearServicio = CrearServicioUseCase(servicioRepo, generarCodigo, servicioValidator);
    final crearConfiguracionCobro = CrearConfiguracionCobroUseCase(
      configuracionCobroRepo,
      servicioRepo,
      configuracionCobroValidator,
      const ConfiguracionCobroReglaEventoValidator(),
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
    documentoRepo = DocumentoPorEmitirRepositoryImpl(db, AttachmentRepository(db));
    final comercialRepo = ServicioComercialRepositoryImpl(db);
    final configuracionCobroRepo = ConfiguracionCobroRepositoryImpl(db);
    final ensamblar = EnsamblarDocumentoPorEmitirUseCase(comercialRepo, configuracionCobroRepo);
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    crearManual = CrearDocumentoManualUseCase(documentoRepo, configuracionCobroRepo, ensamblar, generarCodigo);
    registrarEmision = RegistrarEmisionDocumentoPorEmitirUseCase(documentoRepo);
    corregirDatosEmision = CorregirDatosEmisionDocumentoPorEmitirUseCase(documentoRepo);
    registrarEnvio = RegistrarEnvioDocumentoPorEmitirUseCase(documentoRepo);
    cambiarEstatus = CambiarEstatusDocumentoPorEmitirUseCase(documentoRepo);
    actualizarAjuste = ActualizarAjusteManualDocumentoPorEmitirUseCase(documentoRepo);
  });

  tearDown(() => db.close());

  group('RegistrarEmisionDocumentoPorEmitirUseCase — casos reales obligatorios', () {
    test('CFDI emitido con serie, folio fiscal y UUID', () async {
      final documentoId = await crearDocumentoDePrueba(tipoDocumento: TipoDocumentoCobro.cfdi);

      final resultado = await registrarEmision.ejecutar(
        documentoPorEmitirId: documentoId,
        folioDocumento: 'A-001',
        serieFiscal: 'A',
        folioFiscal: '001',
        uuid: '11111111-1111-1111-1111-111111111111',
        fechaEmisionReal: DateTime(2026, 1, 5),
        importeEmitido: 500000,
        observacionesEmision: 'Emitido vía sistema externo',
      );

      expect(resultado, isA<RegistrarEmisionDocumentoPorEmitirExitoso>());
      final documento = (resultado as RegistrarEmisionDocumentoPorEmitirExitoso).documento;
      expect(documento.estatus, 'emitido');
      expect(documento.folioDocumento, 'A-001');
      expect(documento.serieFiscal, 'A');
      expect(documento.folioFiscal, '001');
      expect(documento.uuid, '11111111-1111-1111-1111-111111111111');
      expect(documento.importeEmitido, 500000);
    });

    test('Recibo emitido solo con folio — UUID/XML nunca se piden', () async {
      final documentoId = await crearDocumentoDePrueba();

      final resultado = await registrarEmision.ejecutar(
        documentoPorEmitirId: documentoId,
        folioDocumento: 'REC-001',
        fechaEmisionReal: DateTime(2026, 1, 5),
        importeEmitido: 0,
      );

      expect(resultado, isA<RegistrarEmisionDocumentoPorEmitirExitoso>());
      final documento = (resultado as RegistrarEmisionDocumentoPorEmitirExitoso).documento;
      expect(documento.folioDocumento, 'REC-001');
      expect(documento.serieFiscal, isNull);
      expect(documento.uuid, isNull);
    });

    test('un recibo rechaza serie/folio fiscal/UUID si se intentan capturar', () async {
      final documentoId = await crearDocumentoDePrueba();

      final resultado = await registrarEmision.ejecutar(
        documentoPorEmitirId: documentoId,
        folioDocumento: 'REC-001',
        uuid: '11111111-1111-1111-1111-111111111111',
        fechaEmisionReal: DateTime(2026, 1, 5),
        importeEmitido: 0,
      );

      expect(resultado, isA<RegistrarEmisionDocumentoPorEmitirCamposNoPermitidosParaRecibo>());
    });

    test('folio vacío se rechaza', () async {
      final documentoId = await crearDocumentoDePrueba();
      final resultado = await registrarEmision.ejecutar(
        documentoPorEmitirId: documentoId,
        folioDocumento: '   ',
        fechaEmisionReal: DateTime(2026, 1, 5),
        importeEmitido: 0,
      );
      expect(resultado, isA<RegistrarEmisionDocumentoPorEmitirFolioRequerido>());
    });

    test('importe emitido negativo se rechaza', () async {
      final documentoId = await crearDocumentoDePrueba();
      final resultado = await registrarEmision.ejecutar(
        documentoPorEmitirId: documentoId,
        folioDocumento: 'REC-001',
        fechaEmisionReal: DateTime(2026, 1, 5),
        importeEmitido: -100,
      );
      expect(resultado, isA<RegistrarEmisionDocumentoPorEmitirImporteInvalido>());
    });

    test('un documento ya Emitido no puede volver a emitirse por esta vía', () async {
      final documentoId = await crearDocumentoDePrueba();
      await registrarEmision.ejecutar(
        documentoPorEmitirId: documentoId,
        folioDocumento: 'REC-001',
        fechaEmisionReal: DateTime(2026, 1, 5),
        importeEmitido: 0,
      );

      final resultado = await registrarEmision.ejecutar(
        documentoPorEmitirId: documentoId,
        folioDocumento: 'REC-002',
        fechaEmisionReal: DateTime(2026, 1, 6),
        importeEmitido: 0,
      );
      expect(resultado, isA<RegistrarEmisionDocumentoPorEmitirTransicionInvalida>());
    });
  });

  group('RegistrarEnvioDocumentoPorEmitirUseCase', () {
    test('envío posterior a la emisión transiciona a Enviado con los correos utilizados', () async {
      final documentoId = await crearDocumentoDePrueba();
      await registrarEmision.ejecutar(
        documentoPorEmitirId: documentoId,
        folioDocumento: 'REC-001',
        fechaEmisionReal: DateTime(2026, 1, 5),
        importeEmitido: 0,
      );

      final resultado = await registrarEnvio.ejecutar(
        documentoPorEmitirId: documentoId,
        fechaEnvio: DateTime(2026, 1, 6),
        correos: ['facturacion@morgan.mx', 'contabilidad@morgan.mx'],
        observacionesEnvio: 'Enviado por correo',
      );

      expect(resultado, isA<RegistrarEnvioDocumentoPorEmitirExitoso>());
      final documento = (resultado as RegistrarEnvioDocumentoPorEmitirExitoso).documento;
      expect(documento.estatus, 'enviado');
      final correos = await documentoRepo.listarCorreosEnvio(documentoId);
      expect(correos, ['facturacion@morgan.mx', 'contabilidad@morgan.mx']);
    });

    test('no se puede registrar envío antes de emitir', () async {
      final documentoId = await crearDocumentoDePrueba();
      final resultado = await registrarEnvio.ejecutar(documentoPorEmitirId: documentoId, fechaEnvio: DateTime(2026, 1, 6));
      expect(resultado, isA<RegistrarEnvioDocumentoPorEmitirTransicionInvalida>());
    });

    test('un envío sin correos es válido (entrega sin correo formal)', () async {
      final documentoId = await crearDocumentoDePrueba();
      await registrarEmision.ejecutar(
        documentoPorEmitirId: documentoId,
        folioDocumento: 'REC-001',
        fechaEmisionReal: DateTime(2026, 1, 5),
        importeEmitido: 0,
      );
      final resultado = await registrarEnvio.ejecutar(documentoPorEmitirId: documentoId, fechaEnvio: DateTime(2026, 1, 6));
      expect(resultado, isA<RegistrarEnvioDocumentoPorEmitirExitoso>());
    });
  });

  group('Procesado/Aceptado y transiciones inválidas', () {
    test('Emitido → Procesado/Aceptado directo (sin envío formal)', () async {
      final documentoId = await crearDocumentoDePrueba();
      await registrarEmision.ejecutar(
        documentoPorEmitirId: documentoId,
        folioDocumento: 'REC-001',
        fechaEmisionReal: DateTime(2026, 1, 5),
        importeEmitido: 0,
      );

      final resultado =
          await cambiarEstatus.ejecutar(documentoPorEmitirId: documentoId, nuevo: EstatusDocumentoPorEmitir.procesadoAceptado);
      expect(resultado, isA<CambiarEstatusDocumentoPorEmitirExitoso>());
      expect((resultado as CambiarEstatusDocumentoPorEmitirExitoso).documento.estatus, 'procesadoAceptado');
    });

    test('Enviado → Procesado/Aceptado', () async {
      final documentoId = await crearDocumentoDePrueba();
      await registrarEmision.ejecutar(
        documentoPorEmitirId: documentoId,
        folioDocumento: 'REC-001',
        fechaEmisionReal: DateTime(2026, 1, 5),
        importeEmitido: 0,
      );
      await registrarEnvio.ejecutar(documentoPorEmitirId: documentoId, fechaEnvio: DateTime(2026, 1, 6));

      final resultado =
          await cambiarEstatus.ejecutar(documentoPorEmitirId: documentoId, nuevo: EstatusDocumentoPorEmitir.procesadoAceptado);
      expect(resultado, isA<CambiarEstatusDocumentoPorEmitirExitoso>());
    });

    test('Pendiente → Enviado directo se rechaza (Emitido nunca se salta)', () async {
      final documentoId = await crearDocumentoDePrueba();
      final resultado = await cambiarEstatus.ejecutar(documentoPorEmitirId: documentoId, nuevo: EstatusDocumentoPorEmitir.enviado);
      expect(resultado, isA<CambiarEstatusDocumentoPorEmitirTransicionInvalida>());
    });

    test('Emitido no puede pasar a Cancelado en esta etapa', () async {
      final documentoId = await crearDocumentoDePrueba();
      await registrarEmision.ejecutar(
        documentoPorEmitirId: documentoId,
        folioDocumento: 'REC-001',
        fechaEmisionReal: DateTime(2026, 1, 5),
        importeEmitido: 0,
      );
      final resultado = await cambiarEstatus.ejecutar(
        documentoPorEmitirId: documentoId,
        nuevo: EstatusDocumentoPorEmitir.cancelado,
        motivo: 'Prueba',
      );
      expect(resultado, isA<CambiarEstatusDocumentoPorEmitirTransicionInvalida>());
    });

    test('Procesado/Aceptado es terminal: ninguna transición posterior es válida', () async {
      final documentoId = await crearDocumentoDePrueba();
      await registrarEmision.ejecutar(
        documentoPorEmitirId: documentoId,
        folioDocumento: 'REC-001',
        fechaEmisionReal: DateTime(2026, 1, 5),
        importeEmitido: 0,
      );
      await cambiarEstatus.ejecutar(documentoPorEmitirId: documentoId, nuevo: EstatusDocumentoPorEmitir.procesadoAceptado);

      final resultado = await cambiarEstatus.ejecutar(documentoPorEmitirId: documentoId, nuevo: EstatusDocumentoPorEmitir.emitido);
      expect(resultado, isA<CambiarEstatusDocumentoPorEmitirTransicionInvalida>());
    });

    test('Enviado → Emitido exige motivo (corrección administrativa)', () async {
      final documentoId = await crearDocumentoDePrueba();
      await registrarEmision.ejecutar(
        documentoPorEmitirId: documentoId,
        folioDocumento: 'REC-001',
        fechaEmisionReal: DateTime(2026, 1, 5),
        importeEmitido: 0,
      );
      await registrarEnvio.ejecutar(documentoPorEmitirId: documentoId, fechaEnvio: DateTime(2026, 1, 6));

      final sinMotivo = await cambiarEstatus.ejecutar(documentoPorEmitirId: documentoId, nuevo: EstatusDocumentoPorEmitir.emitido);
      expect(sinMotivo, isA<CambiarEstatusDocumentoPorEmitirMotivoRequerido>());

      final conMotivo = await cambiarEstatus.ejecutar(
        documentoPorEmitirId: documentoId,
        nuevo: EstatusDocumentoPorEmitir.emitido,
        motivo: 'Corrección de folio',
      );
      expect(conMotivo, isA<CambiarEstatusDocumentoPorEmitirExitoso>());
      expect((conMotivo as CambiarEstatusDocumentoPorEmitirExitoso).documento.estatus, 'emitido');
    });
  });

  group('Importe emitido distinto al esperado', () {
    test('la diferencia se calcula (nunca se almacena) cuando el importe emitido difiere del esperado', () async {
      final documentoId = await crearDocumentoDePrueba();
      await registrarEmision.ejecutar(
        documentoPorEmitirId: documentoId,
        folioDocumento: 'REC-001',
        fechaEmisionReal: DateTime(2026, 1, 5),
        importeEmitido: 150000,
      );

      final detalle = await documentoRepo.obtenerDetalle(documentoId);
      expect(detalle!.documento.importeFinalEsperado, 0, reason: 'sin línea comercial, el esperado es 0');
      expect(detalle.documento.importeEmitido, 150000);
      expect(detalle.diferenciaEmision, 150000);
    });
  });

  group('Corrección de datos de emisión', () {
    test('conserva los valores anteriores en el evento y exige motivo', () async {
      final documentoId = await crearDocumentoDePrueba();
      await registrarEmision.ejecutar(
        documentoPorEmitirId: documentoId,
        folioDocumento: 'REC-001',
        fechaEmisionReal: DateTime(2026, 1, 5),
        importeEmitido: 100000,
      );

      final sinMotivo = await corregirDatosEmision.ejecutar(documentoPorEmitirId: documentoId, motivo: '', folioDocumento: 'REC-002');
      expect(sinMotivo, isA<CorregirDatosEmisionDocumentoPorEmitirMotivoRequerido>());

      final resultado = await corregirDatosEmision.ejecutar(
        documentoPorEmitirId: documentoId,
        motivo: 'Folio capturado con error de dedo',
        folioDocumento: 'REC-002',
      );
      expect(resultado, isA<CorregirDatosEmisionDocumentoPorEmitirExitoso>());
      expect((resultado as CorregirDatosEmisionDocumentoPorEmitirExitoso).documento.folioDocumento, 'REC-002');

      final eventos = await documentoRepo.listarEventos(documentoId);
      final correccion = eventos.firstWhere((e) => e.tipoEvento == 'correccionDatosEmision');
      expect(correccion.observacion, 'Folio capturado con error de dedo');
      expect(correccion.datosRelevantes, contains('REC-001'), reason: 'el folio anterior debe quedar en el evento');
    });

    test('no se puede corregir un documento Procesado/Aceptado', () async {
      final documentoId = await crearDocumentoDePrueba();
      await registrarEmision.ejecutar(
        documentoPorEmitirId: documentoId,
        folioDocumento: 'REC-001',
        fechaEmisionReal: DateTime(2026, 1, 5),
        importeEmitido: 0,
      );
      await cambiarEstatus.ejecutar(documentoPorEmitirId: documentoId, nuevo: EstatusDocumentoPorEmitir.procesadoAceptado);

      final resultado = await corregirDatosEmision.ejecutar(
        documentoPorEmitirId: documentoId,
        motivo: 'Intento de corrección',
        folioDocumento: 'REC-002',
      );
      expect(resultado, isA<CorregirDatosEmisionDocumentoPorEmitirNoPermitido>());
    });

    test('no se puede corregir antes de emitir (Pendiente/EnPreparacion)', () async {
      final documentoId = await crearDocumentoDePrueba();
      final resultado = await corregirDatosEmision.ejecutar(
        documentoPorEmitirId: documentoId,
        motivo: 'Intento de corrección',
        folioDocumento: 'REC-002',
      );
      expect(resultado, isA<CorregirDatosEmisionDocumentoPorEmitirNoPermitido>());
    });
  });

  group('Ajuste manual — historial (Etapa 4I.2.1)', () {
    test('cada cambio de ajuste genera un evento con los valores anterior y nuevo', () async {
      final documentoId = await crearDocumentoDePrueba();

      // El documento de prueba no tiene línea comercial (importeBaseEsperado
      // = 0) — se usan ajustes positivos (incremento) para que el importe
      // final nunca quede negativo.
      final primero =
          await actualizarAjuste.ejecutar(documentoPorEmitirId: documentoId, ajusteManual: 50000, motivoAjuste: 'Cargo inicial');
      expect(primero, isA<ActualizarAjusteManualDocumentoPorEmitirExitoso>());
      final segundo =
          await actualizarAjuste.ejecutar(documentoPorEmitirId: documentoId, ajusteManual: 80000, motivoAjuste: 'Cargo ampliado');
      expect(segundo, isA<ActualizarAjusteManualDocumentoPorEmitirExitoso>());

      final eventos = await documentoRepo.listarEventos(documentoId);
      final ajustes = eventos.where((e) => e.tipoEvento == 'ajusteRegistrado').toList();
      expect(ajustes, hasLength(2));
      expect(ajustes.first.datosRelevantes, contains('"ajusteAnterior":null'));
      expect(ajustes.last.datosRelevantes, contains('"ajusteAnterior":50000'));
      expect(ajustes.last.datosRelevantes, contains('"ajusteNuevo":80000'));
    });
  });

  group('Historial cronológico', () {
    test('el historial refleja, en orden, creación manual, emisión, envío y procesado/aceptado', () async {
      final documentoId = await crearDocumentoDePrueba();
      await registrarEmision.ejecutar(
        documentoPorEmitirId: documentoId,
        folioDocumento: 'REC-001',
        fechaEmisionReal: DateTime(2026, 1, 5),
        importeEmitido: 0,
      );
      await registrarEnvio.ejecutar(documentoPorEmitirId: documentoId, fechaEnvio: DateTime(2026, 1, 6));
      await cambiarEstatus.ejecutar(documentoPorEmitirId: documentoId, nuevo: EstatusDocumentoPorEmitir.procesadoAceptado);

      final eventos = await documentoRepo.listarEventos(documentoId);
      expect(eventos.map((e) => e.tipoEvento), [
        'creadoManual',
        'emisionRegistrada',
        'envioRegistrado',
        'procesadoAceptado',
      ]);
    });
  });
}
