// Ajuste comercial de facturación — decisión de producto "opción C":
// UN ajuste neto con signo y su motivo libre, que nace y muere dentro de
// Facturación. Nada aquí sabe ni pregunta por ausencias, coberturas,
// empleados ni vacantes: "2 días no facturados" es sólo texto.
//
// Cubre las tres reglas nuevas: el ajuste no toca el contractual, se
// congela al emitir, y la única forma de corregirlo después es la vía
// Maestro de corrección histórica, que jamás toca el CFDI ni la cobranza.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/attachments/attachment_repository.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_por_cobrar_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_portal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/configuracion_cobro_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/documento_por_emitir_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/entidad_fiscal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/puesto_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_comercial_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/documento_por_emitir_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_linea_comercial_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/actualizar_ajuste_manual_documento_por_emitir_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_estatus_documento_por_emitir_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_etapa_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/corregir_ajuste_historico_documento_por_emitir_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_configuracion_cobro_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_documento_manual_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_linea_comercial_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/ensamblar_documento_por_emitir_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_servicio_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/linea_comercial_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/registrar_emision_documento_por_emitir_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/resumen_iva_documento_por_emitir.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';
import 'package:riseg_one/features/organizacion/presentation/agenda/total_esperado_documento.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';

void main() {
  late AppDatabase db;
  late DocumentoPorEmitirRepositoryImpl documentoRepo;
  late CrearServicioUseCase crearServicio;
  late CrearLineaComercialUseCase crearLineaComercial;
  late CrearConfiguracionCobroUseCase crearConfiguracionCobro;
  late CrearDocumentoManualUseCase crearManual;
  late RegistrarEmisionDocumentoPorEmitirUseCase registrarEmision;
  late ActualizarAjusteManualDocumentoPorEmitirUseCase actualizarAjuste;
  late CorregirAjusteHistoricoDocumentoPorEmitirUseCase corregirHistorico;
  late CambiarEstatusDocumentoPorEmitirUseCase cambiarEstatus;
  late ClienteRepositoryImpl clienteRepo;
  late String puestoId;
  var contador = 0;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    clienteRepo = ClienteRepositoryImpl(db);
    final servicioRepo = ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db));
    final puestoRepo = PuestoRepositoryImpl(db);
    final catalogoRepo = CatalogoRepositoryImpl(db);
    final entidadFiscalRepo = EntidadFiscalRepositoryImpl(db);
    final clientePortalRepo = ClientePortalRepositoryImpl(db);
    final comercialRepo = ServicioComercialRepositoryImpl(db);
    final configuracionCobroRepo = ConfiguracionCobroRepositoryImpl(db);
    documentoRepo = DocumentoPorEmitirRepositoryImpl(db, AttachmentRepository(db), CuentaPorCobrarRepositoryImpl(db));

    final servicioValidator = ServicioValidator(clienteRepo, catalogoRepo);
    final lineaComercialValidator =
        LineaComercialValidator(puestoRepo, catalogoRepo, servicioRepo, configuracionCobroRepo);
    final configuracionCobroValidator =
        ConfiguracionCobroValidator(servicioRepo, entidadFiscalRepo, catalogoRepo, comercialRepo, clientePortalRepo);

    crearServicio = CrearServicioUseCase(servicioRepo, generarCodigo, servicioValidator);
    crearLineaComercial = CrearLineaComercialUseCase(comercialRepo, servicioRepo, lineaComercialValidator);
    crearConfiguracionCobro = CrearConfiguracionCobroUseCase(
      configuracionCobroRepo,
      servicioRepo,
      configuracionCobroValidator,
      const ConfiguracionCobroEtapaValidator(),
    );
    final ensamblar = EnsamblarDocumentoPorEmitirUseCase(comercialRepo, configuracionCobroRepo);
    crearManual =
        CrearDocumentoManualUseCase(documentoRepo, configuracionCobroRepo, servicioRepo, ensamblar, generarCodigo);
    registrarEmision = RegistrarEmisionDocumentoPorEmitirUseCase(documentoRepo);
    actualizarAjuste = ActualizarAjusteManualDocumentoPorEmitirUseCase(documentoRepo);
    corregirHistorico = CorregirAjusteHistoricoDocumentoPorEmitirUseCase(documentoRepo);
    cambiarEstatus = CambiarEstatusDocumentoPorEmitirUseCase(documentoRepo);

    final puesto = await puestoRepo.crear(
      PuestoCompanion.insert(
        codigo: 'PUE-0001',
        nombre: 'Guardia',
        areaId: SeedIds.areaOperaciones,
        tipo: 'operativo',
        nivelJerarquico: 5,
      ),
    );
    puestoId = puesto.id;
  });

  tearDown(() => db.close());

  /// Documento con una línea de 30 días y 1 elemento, cuyo subtotal
  /// proporcional reproduce exactamente `precioUnitarioCentavos`.
  Future<String> crearDocumento({int precioUnitarioCentavos = 1850000}) async {
    final n = ++contador;
    final cliente = await clienteRepo.crear(
      ClienteCompanion.insert(codigo: 'CLI-$n', nombreComercial: 'Cliente $n'),
    );
    final servicioCreado = await crearServicio.ejecutar(
      clienteId: cliente.id,
      borrador: ServicioBorrador(
        nombre: 'Vigilancia $n',
        tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
        fechaInicio: DateTime(2026, 1, 1),
      ),
    );
    final servicioId = (servicioCreado as GuardarServicioExitoso).servicio.id;

    final linea = await crearLineaComercial.ejecutar(
      servicioId: servicioId,
      borrador: LineaComercialBorrador(
        puestoId: puestoId,
        modalidadTurnoId: SeedIds.modalidadTurno24x24,
        cantidadElementos: 1,
        precioUnitario: precioUnitarioCentavos,
        tratamientoIva: TratamientoIva.masIva,
        fechaInicioVigencia: DateTime(2026, 1, 1),
      ),
    );
    if (linea is! CrearLineaComercialExitoso) throw StateError('línea: $linea');

    final entidad = await EntidadFiscalRepositoryImpl(db).crear(
      EntidadFiscalCompanion.insert(
        codigo: 'ENF-$n',
        clienteId: cliente.id,
        razonSocial: 'Cliente $n',
        // RFC único por entidad: la columna es UNIQUE y varias pruebas
        // crean más de una entidad fiscal.
        rfc: 'XXX0101${n.toString().padLeft(2, '0')}AA',
      ),
    );

    final config = await crearConfiguracionCobro.ejecutar(
      servicioId: servicioId,
      borrador: ConfiguracionCobroBorrador(
        tipoDocumento: TipoDocumentoCobro.cfdi,
        frecuenciaId: SeedIds.frecuenciaCobroMensual,
        diaInicioPeriodo: 1,
        agrupacion: AgrupacionCobro.porServicio,
        metodo: MetodoPagoCobro.pue,
        requiereComplemento: false,
        fechaInicioVigencia: DateTime(2026, 1, 1),
        entidadFiscalId: entidad.id,
      ),
      etapas: const [],
    );
    if (config is! CrearConfiguracionCobroExitoso) throw StateError('config: $config');

    final documento = await crearManual.ejecutar(
      clienteId: cliente.id,
      servicioIds: [servicioId],
      periodoInicio: DateTime(2026, 1, 1),
      periodoFin: DateTime(2026, 1, 30),
    );
    if (documento is! CrearDocumentoManualExitoso) throw StateError('documento: $documento');
    return documento.documento.id;
  }

  Future<void> emitir(String documentoId, {int importeEmitido = 2002934}) async {
    final r = await registrarEmision.ejecutar(
      documentoPorEmitirId: documentoId,
      folioDocumento: 'A-001',
      fechaEmisionReal: DateTime(2026, 2, 5),
      importeEmitido: importeEmitido,
    );
    expect(r, isA<RegistrarEmisionDocumentoPorEmitirExitoso>());
  }

  group('El ajuste, antes de emitir', () {
    test('1. negativo: descuenta del facturable y deja intacto el contractual', () async {
      final id = await crearDocumento();

      final r = await actualizarAjuste.ejecutar(
        documentoPorEmitirId: id,
        ajusteManual: -123333,
        motivoAjuste: '2 días no facturados',
      );

      final documento = (r as ActualizarAjusteManualDocumentoPorEmitirExitoso).documento;
      expect(documento.importeBaseEsperado, 1850000, reason: 'el contractual nunca se toca');
      expect(documento.ajusteManual, -123333);
      expect(documento.motivoAjuste, '2 días no facturados');
      expect(documento.importeFinalEsperado, 1850000 - 123333);
    });

    test('2. positivo: un cargo adicional suma, con el mismo campo', () async {
      final id = await crearDocumento();

      final r = await actualizarAjuste.ejecutar(
        documentoPorEmitirId: id,
        ajusteManual: 50000,
        motivoAjuste: 'Servicio extraordinario acordado',
      );

      final documento = (r as ActualizarAjusteManualDocumentoPorEmitirExitoso).documento;
      expect(documento.importeBaseEsperado, 1850000);
      expect(documento.importeFinalEsperado, 1900000);
    });

    test('3. cero: limpia ajuste y motivo, y el facturable vuelve al contractual', () async {
      final id = await crearDocumento();
      await actualizarAjuste.ejecutar(documentoPorEmitirId: id, ajusteManual: -123333, motivoAjuste: 'algo');

      final r = await actualizarAjuste.ejecutar(documentoPorEmitirId: id, ajusteManual: 0);

      final documento = (r as ActualizarAjusteManualDocumentoPorEmitirExitoso).documento;
      expect(documento.ajusteManual, isNull);
      expect(documento.motivoAjuste, isNull);
      expect(documento.importeFinalEsperado, documento.importeBaseEsperado);
    });

    test('4. un ajuste distinto de cero sin motivo se rechaza', () async {
      final id = await crearDocumento();

      final r = await actualizarAjuste.ejecutar(documentoPorEmitirId: id, ajusteManual: -1, motivoAjuste: '   ');

      expect(r, isA<ActualizarAjusteManualDocumentoPorEmitirMotivoRequerido>());
      final documento = await documentoRepo.obtenerPorId(id);
      expect(documento!.ajusteManual, isNull, reason: 'el rechazo no escribe nada');
    });

    test('5. un ajuste que dejaría el facturable en negativo se rechaza', () async {
      final id = await crearDocumento();

      final r = await actualizarAjuste.ejecutar(
        documentoPorEmitirId: id,
        ajusteManual: -1850001,
        motivoAjuste: 'imposible',
      );

      expect(r, isA<ActualizarAjusteManualDocumentoPorEmitirImporteNegativo>());
    });
  });

  group('Congelamiento al emitir', () {
    test('6. registrar la emisión congela el ajuste: editarlo queda bloqueado', () async {
      final id = await crearDocumento();
      await actualizarAjuste.ejecutar(documentoPorEmitirId: id, ajusteManual: -123333, motivoAjuste: '2 días');
      await emitir(id);

      final r = await actualizarAjuste.ejecutar(
        documentoPorEmitirId: id,
        ajusteManual: -999999,
        motivoAjuste: 'otro criterio',
      );

      expect(r, isA<ActualizarAjusteManualDocumentoPorEmitirCongelado>());
      final documento = await documentoRepo.obtenerPorId(id);
      expect(documento!.ajusteManual, -123333, reason: 'el ajuste emitido no se movió');
      expect(documento.importeFinalEsperado, 1850000 - 123333);
    });

    test('7. ni siquiera se puede "dejarlo igual" después de emitir', () async {
      final id = await crearDocumento();
      await emitir(id);

      final r = await actualizarAjuste.ejecutar(documentoPorEmitirId: id, ajusteManual: 0);

      expect(r, isA<ActualizarAjusteManualDocumentoPorEmitirCongelado>());
    });

    test('8. el predicado mira los datos de emisión, no sólo el estatus', () async {
      final id = await crearDocumento();
      final antes = await documentoRepo.obtenerPorId(id);
      expect(ajusteComercialCongelado(antes!), isFalse);

      await emitir(id);

      final despues = await documentoRepo.obtenerPorId(id);
      expect(ajusteComercialCongelado(despues!), isTrue);
    });
  });

  group('Corrección histórica (Maestro)', () {
    test('9. corrige el ajuste de un documento ya emitido', () async {
      final id = await crearDocumento();
      await emitir(id);

      final r = await corregirHistorico.ejecutar(
        documentoPorEmitirId: id,
        motivoCorreccion: 'Capturado antes de que existiera la regla',
        ajusteManual: -123333,
        motivoAjuste: '2 días no facturados',
        actorUsuarioId: null,
      );

      final documento = (r as CorregirAjusteHistoricoDocumentoPorEmitirExitoso).documento;
      expect(documento.importeBaseEsperado, 1850000, reason: 'el contractual sigue intacto');
      expect(documento.ajusteManual, -123333);
      expect(documento.importeFinalEsperado, 1726667);
    });

    test('10. sin motivo administrativo, se rechaza', () async {
      final id = await crearDocumento();
      await emitir(id);

      final r = await corregirHistorico.ejecutar(
        documentoPorEmitirId: id,
        motivoCorreccion: '  ',
        ajusteManual: -123333,
        motivoAjuste: '2 días',
      );

      expect(r, isA<CorregirAjusteHistoricoDocumentoPorEmitirMotivoCorreccionRequerido>());
    });

    test('11. sobre un documento NO emitido se rechaza: para eso está el ajuste normal', () async {
      final id = await crearDocumento();

      final r = await corregirHistorico.ejecutar(
        documentoPorEmitirId: id,
        motivoCorreccion: 'no aplica todavía',
        ajusteManual: -1,
        motivoAjuste: 'x',
      );

      expect(r, isA<CorregirAjusteHistoricoDocumentoPorEmitirNoEmitido>());
    });

    test('12. no toca el importe emitido, el folio ni la fecha de emisión', () async {
      final id = await crearDocumento();
      await emitir(id);
      final antes = await documentoRepo.obtenerPorId(id);

      await corregirHistorico.ejecutar(
        documentoPorEmitirId: id,
        motivoCorreccion: 'corrección',
        ajusteManual: -123333,
        motivoAjuste: '2 días',
      );

      final despues = await documentoRepo.obtenerPorId(id);
      expect(despues!.importeEmitido, antes!.importeEmitido);
      expect(despues.folioDocumento, antes.folioDocumento);
      expect(despues.fechaEmisionReal, antes.fechaEmisionReal);
      expect(despues.uuid, antes.uuid);
      expect(despues.estatus, antes.estatus);
    });

    test('13. no toca cobranza: la Cuenta por cobrar conserva su importe y su saldo', () async {
      final id = await crearDocumento();
      await emitir(id);
      // La CxC nace al pasar a procesadoAceptado, no al emitir.
      final aceptado = await cambiarEstatus.ejecutar(
        documentoPorEmitirId: id,
        nuevo: EstatusDocumentoPorEmitir.procesadoAceptado,
      );
      expect(aceptado, isA<CambiarEstatusDocumentoPorEmitirExitoso>());
      final cxcAntes = await db.select(db.cuentaPorCobrar).get();
      expect(cxcAntes, isNotEmpty, reason: 'emitir genera la CxC; si no, esta prueba no prueba nada');

      await corregirHistorico.ejecutar(
        documentoPorEmitirId: id,
        motivoCorreccion: 'corrección',
        ajusteManual: -123333,
        motivoAjuste: '2 días',
      );

      final cxcDespues = await db.select(db.cuentaPorCobrar).get();
      expect(cxcDespues.length, cxcAntes.length);
      expect(cxcDespues.single.importeEmitido, cxcAntes.single.importeEmitido);
      expect(cxcDespues.single.saldoPendiente, cxcAntes.single.saldoPendiente);
    });

    test('14. no crea Pagos, Ingresos ni Complementos', () async {
      final id = await crearDocumento();
      await emitir(id);

      await corregirHistorico.ejecutar(
        documentoPorEmitirId: id,
        motivoCorreccion: 'corrección',
        ajusteManual: -123333,
        motivoAjuste: '2 días',
      );

      expect(await db.select(db.pago).get(), isEmpty);
      expect(await db.select(db.ingreso).get(), isEmpty);
      expect(await db.select(db.complementoPago).get(), isEmpty);
    });

    test('15. deja un evento propio con el antes, el después y ambos motivos', () async {
      final id = await crearDocumento();
      await actualizarAjuste.ejecutar(documentoPorEmitirId: id, ajusteManual: -100, motivoAjuste: 'inicial');
      await emitir(id);

      await corregirHistorico.ejecutar(
        documentoPorEmitirId: id,
        motivoCorreccion: 'Capturado antes de la regla',
        ajusteManual: -123333,
        motivoAjuste: '2 días no facturados',
      );

      final eventos = await documentoRepo.listarEventos(id);
      final correccion = eventos.firstWhere(
        (e) => e.tipoEvento == TipoEventoDocumentoPorEmitir.correccionAjusteHistorico.name,
      );
      expect(correccion.observacion, 'Capturado antes de la regla');
      final datos = correccion.datosRelevantes!;
      expect(datos, contains('"ajusteAnterior":-100'));
      expect(datos, contains('"ajusteNuevo":-123333'));
      expect(datos, contains('"motivoNuevo":"2 días no facturados"'));
      expect(datos, contains('"motivoCorreccion":"Capturado antes de la regla"'));
      expect(datos, contains('"importeEmitidoSinCambio":2002934'));
    });

    test('16. el evento normal y el de corrección son distinguibles entre sí', () async {
      final id = await crearDocumento();
      await actualizarAjuste.ejecutar(documentoPorEmitirId: id, ajusteManual: -100, motivoAjuste: 'inicial');
      await emitir(id);
      await corregirHistorico.ejecutar(
        documentoPorEmitirId: id,
        motivoCorreccion: 'corrección',
        ajusteManual: -200,
        motivoAjuste: 'nuevo',
      );

      final tipos = (await documentoRepo.listarEventos(id)).map((e) => e.tipoEvento).toList();
      expect(tipos, contains(TipoEventoDocumentoPorEmitir.ajusteRegistrado.name));
      expect(tipos, contains(TipoEventoDocumentoPorEmitir.correccionAjusteHistorico.name));
    });

    test('17. el ajuste lo captura la persona: el sistema nunca lo deriva del emitido', () async {
      final id = await crearDocumento();
      await emitir(id, importeEmitido: 2002934);

      // Se captura un ajuste que NO cuadra a propósito.
      await corregirHistorico.ejecutar(
        documentoPorEmitirId: id,
        motivoCorreccion: 'corrección parcial',
        ajusteManual: -1,
        motivoAjuste: 'un peso',
      );

      final documento = await documentoRepo.obtenerPorId(id);
      expect(
        documento!.ajusteManual,
        -1,
        reason: 'se guarda lo capturado, no el ajuste que habría hecho coincidir las cifras',
      );
    });
  });

  group('Regresión', () {
    test('18. un documento sin ajuste se comporta exactamente como antes', () async {
      final id = await crearDocumento();

      final documento = await documentoRepo.obtenerPorId(id);
      expect(documento!.ajusteManual, isNull);
      expect(documento.motivoAjuste, isNull);
      expect(documento.importeFinalEsperado, documento.importeBaseEsperado);

      final detalle = await documentoRepo.obtenerDetalle(id);
      expect(detalle!.totalesEsperados!.base, 1850000);
      expect(detalle.totalesEsperados!.ivaEsperado, 296000);
      expect(detalle.totalesEsperados!.totalEsperado, 2146000);
    });
  });

  /// Documento con DOS líneas de tratamientos distintos (masIva +
  /// ivaIncluido) sobre el mismo Servicio: un CFDI mixto real.
  Future<String> crearDocumentoMixto() async {
    final n = ++contador;
    final cliente = await clienteRepo.crear(
      ClienteCompanion.insert(codigo: 'CLI-$n', nombreComercial: 'Mixto $n'),
    );
    final servicioCreado = await crearServicio.ejecutar(
      clienteId: cliente.id,
      borrador: ServicioBorrador(
        nombre: 'Vigilancia mixta $n',
        tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
        fechaInicio: DateTime(2026, 1, 1),
      ),
    );
    final servicioId = (servicioCreado as GuardarServicioExitoso).servicio.id;

    for (final (puesto, precio, tratamiento) in [
      ('Guardia masIva', 1000000, TratamientoIva.masIva),
      ('Guardia ivaIncluido', 500000, TratamientoIva.ivaIncluido),
    ]) {
      final p = await PuestoRepositoryImpl(db).crear(
        PuestoCompanion.insert(
          codigo: 'PUE-$n-$precio',
          nombre: puesto,
          areaId: SeedIds.areaOperaciones,
          tipo: 'operativo',
          nivelJerarquico: 5,
        ),
      );
      final linea = await crearLineaComercial.ejecutar(
        servicioId: servicioId,
        borrador: LineaComercialBorrador(
          puestoId: p.id,
          modalidadTurnoId: SeedIds.modalidadTurno24x24,
          cantidadElementos: 1,
          precioUnitario: precio,
          tratamientoIva: tratamiento,
          fechaInicioVigencia: DateTime(2026, 1, 1),
        ),
      );
      if (linea is! CrearLineaComercialExitoso) throw StateError('línea mixta: $linea');
    }

    final entidad = await EntidadFiscalRepositoryImpl(db).crear(
      EntidadFiscalCompanion.insert(
        codigo: 'ENF-MIX-$n',
        clienteId: cliente.id,
        razonSocial: 'Mixto $n',
        // RFC único por entidad: la columna es UNIQUE y varias pruebas
        // crean más de una entidad fiscal.
        rfc: 'XXX0101${n.toString().padLeft(2, '0')}AA',
      ),
    );
    final config = await crearConfiguracionCobro.ejecutar(
      servicioId: servicioId,
      borrador: ConfiguracionCobroBorrador(
        tipoDocumento: TipoDocumentoCobro.cfdi,
        frecuenciaId: SeedIds.frecuenciaCobroMensual,
        diaInicioPeriodo: 1,
        agrupacion: AgrupacionCobro.porServicio,
        metodo: MetodoPagoCobro.pue,
        requiereComplemento: false,
        fechaInicioVigencia: DateTime(2026, 1, 1),
        entidadFiscalId: entidad.id,
      ),
      etapas: const [],
    );
    if (config is! CrearConfiguracionCobroExitoso) throw StateError('config mixta: $config');

    final documento = await crearManual.ejecutar(
      clienteId: cliente.id,
      servicioIds: [servicioId],
      periodoInicio: DateTime(2026, 1, 1),
      periodoFin: DateTime(2026, 1, 30),
    );
    if (documento is! CrearDocumentoManualExitoso) throw StateError('documento mixto: $documento');
    return documento.documento.id;
  }

  group('Documentos mixtos', () {
    test('19. sin ajuste: el total se calcula línea por línea, nunca con una tasa global', () async {
      final id = await crearDocumentoMixto();
      final detalle = await documentoRepo.obtenerDetalle(id);

      expect(detalle!.resumenIva, ResumenIvaDocumento.mixto, reason: 'si no es mixto, la prueba no prueba nada');
      expect(detalle.documento.importeBaseEsperado, 1500000);

      // Sólo la línea masIva causa IVA: 10,000.00 x 16% = 1,600.00.
      // La línea ivaIncluido aporta su subtotal y cero IVA desglosado,
      // igual que en el camino homogéneo.
      expect(detalle.totalesEsperados, isNotNull);
      expect(detalle.totalesEsperados!.base, 1500000);
      expect(detalle.totalesEsperados!.ivaEsperado, 160000);
      expect(detalle.totalesEsperados!.totalEsperado, 1660000);
    });

    test('20. sin ajuste: la diferencia compara magnitudes equivalentes', () async {
      final id = await crearDocumentoMixto();
      await emitir(id, importeEmitido: 1660000);

      final detalle = await documentoRepo.obtenerDetalle(id);
      expect(
        detalle!.diferenciaEmision,
        0,
        reason: 'antes se comparaba el emitido CON IVA contra la base SIN IVA y salía 160000',
      );
    });

    test('21. CON ajuste: no hay total comparable, y no se inventa uno', () async {
      final id = await crearDocumentoMixto();
      await actualizarAjuste.ejecutar(
        documentoPorEmitirId: id,
        ajusteManual: -100000,
        motivoAjuste: '2 días no facturados',
      );
      await emitir(id, importeEmitido: 1660000);

      final detalle = await documentoRepo.obtenerDetalle(id);
      expect(detalle!.totalesNoDisponiblesPorAjusteEnMixto, isTrue);
      expect(
        detalle.totalesEsperados,
        isNull,
        reason: 'el ajuste escalar no pertenece a ningún tratamiento fiscal',
      );
      expect(
        detalle.diferenciaEmision,
        isNull,
        reason: 'mejor no disponible que una diferencia matemáticamente falsa',
      );

      // Lo que sí sigue siendo cierto y visible: el contractual y el
      // facturable esperado, que no dependen de ningún tratamiento.
      expect(detalle.documento.importeBaseEsperado, 1500000);
      expect(detalle.documento.importeFinalEsperado, 1400000);
    });
  });

  /// Documento de una línea con el tratamiento que se pida — para probar
  /// la columna de la Agenda en los tres casos homogéneos.
  Future<String> crearDocumentoConTratamiento(TratamientoIva tratamiento, {int precio = 1850000}) async {
    final n = ++contador;
    final esRecibo = tratamiento == TratamientoIva.noAplica;
    final cliente = await clienteRepo.crear(
      ClienteCompanion.insert(codigo: 'CLI-T$n', nombreComercial: 'Cliente T$n'),
    );
    final servicioCreado = await crearServicio.ejecutar(
      clienteId: cliente.id,
      borrador: ServicioBorrador(
        nombre: 'Vigilancia T$n',
        tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
        fechaInicio: DateTime(2026, 1, 1),
      ),
    );
    final servicioId = (servicioCreado as GuardarServicioExitoso).servicio.id;

    final linea = await crearLineaComercial.ejecutar(
      servicioId: servicioId,
      borrador: LineaComercialBorrador(
        puestoId: puestoId,
        modalidadTurnoId: SeedIds.modalidadTurno24x24,
        cantidadElementos: 1,
        precioUnitario: precio,
        tratamientoIva: tratamiento,
        fechaInicioVigencia: DateTime(2026, 1, 1),
      ),
    );
    if (linea is! CrearLineaComercialExitoso) throw StateError('línea: $linea');

    String? entidadFiscalId;
    if (!esRecibo) {
      final entidad = await EntidadFiscalRepositoryImpl(db).crear(
        EntidadFiscalCompanion.insert(
          codigo: 'ENF-T$n',
          clienteId: cliente.id,
          razonSocial: 'Cliente T$n',
          // RFC único por entidad: la columna es UNIQUE y varias pruebas
        // crean más de una entidad fiscal.
        rfc: 'XXX0101${n.toString().padLeft(2, '0')}AA',
        ),
      );
      entidadFiscalId = entidad.id;
    }

    final config = await crearConfiguracionCobro.ejecutar(
      servicioId: servicioId,
      borrador: ConfiguracionCobroBorrador(
        tipoDocumento: esRecibo ? TipoDocumentoCobro.reciboDePago : TipoDocumentoCobro.cfdi,
        frecuenciaId: SeedIds.frecuenciaCobroMensual,
        diaInicioPeriodo: 1,
        agrupacion: AgrupacionCobro.porServicio,
        metodo: esRecibo ? MetodoPagoCobro.noAplica : MetodoPagoCobro.pue,
        requiereComplemento: false,
        fechaInicioVigencia: DateTime(2026, 1, 1),
        entidadFiscalId: entidadFiscalId,
      ),
      etapas: const [],
    );
    if (config is! CrearConfiguracionCobroExitoso) throw StateError('config: $config');

    final documento = await crearManual.ejecutar(
      clienteId: cliente.id,
      servicioIds: [servicioId],
      periodoInicio: DateTime(2026, 1, 1),
      periodoFin: DateTime(2026, 1, 30),
    );
    if (documento is! CrearDocumentoManualExitoso) throw StateError('documento: $documento');
    return documento.documento.id;
  }

  /// El MISMO camino que recorre la Agenda: lote de líneas + la función
  /// compartida. No reproduce la lógica de la pantalla, la usa.
  Future<int?> totalDeAgenda(String documentoId) async {
    final documento = await documentoRepo.obtenerPorId(documentoId);
    final lineas = await documentoRepo.lineasPorDocumentos([documentoId]);
    return totalEsperadoDeDocumento(documento!, lineas[documentoId] ?? const []);
  }

  group('Total esperado de la Agenda', () {
    test('22. Más IVA: la columna muestra el total CON IVA, no la base', () async {
      final id = await crearDocumentoConTratamiento(TratamientoIva.masIva);

      expect(await totalDeAgenda(id), 2146000, reason: r'18,500 + 16% = 21,460');
    });

    test('23. IVA incluido: el precio ya lo trae dentro, el total es ese mismo', () async {
      final id = await crearDocumentoConTratamiento(TratamientoIva.ivaIncluido, precio: 2146000);

      expect(await totalDeAgenda(id), 2146000);
    });

    test('24. No aplica: no se inventa IVA', () async {
      final id = await crearDocumentoConTratamiento(TratamientoIva.noAplica);

      expect(await totalDeAgenda(id), 1850000);
    });

    test('25. los tres son comparables entre sí: misma magnitud en la columna', () async {
      final masIva = await crearDocumentoConTratamiento(TratamientoIva.masIva);
      final incluido = await crearDocumentoConTratamiento(TratamientoIva.ivaIncluido, precio: 2146000);

      expect(
        await totalDeAgenda(masIva),
        await totalDeAgenda(incluido),
        reason: 'dos formas de cobrar lo mismo deben verse igual en la Agenda',
      );
    });

    test('26. Más IVA con ajuste: el IVA se causa sobre la base YA ajustada', () async {
      final id = await crearDocumentoConTratamiento(TratamientoIva.masIva);
      await actualizarAjuste.ejecutar(
        documentoPorEmitirId: id,
        ajusteManual: -123333,
        motivoAjuste: '2 días no facturados',
      );

      // 18,500 - 1,233.33 = 17,266.67 → IVA 2,762.67 → total 20,029.34
      expect(await totalDeAgenda(id), 2002934);
    });

    test('27. mixto calculable: total por línea, nunca una tasa global', () async {
      final id = await crearDocumentoMixto();

      expect(await totalDeAgenda(id), 1660000);
    });

    test('28. mixto con ajuste ambiguo: la Agenda no inventa un total', () async {
      final id = await crearDocumentoMixto();
      await actualizarAjuste.ejecutar(
        documentoPorEmitirId: id,
        ajusteManual: -100000,
        motivoAjuste: '2 días no facturados',
      );

      expect(await totalDeAgenda(id), isNull);
    });

    test('29. una sola consulta de líneas para muchos documentos, nunca N+1', () async {
      final ids = [
        await crearDocumentoConTratamiento(TratamientoIva.masIva),
        await crearDocumentoConTratamiento(TratamientoIva.ivaIncluido),
        await crearDocumentoMixto(),
      ];

      final lineas = await documentoRepo.lineasPorDocumentos(ids);

      expect(lineas.keys.toSet(), ids.toSet());
      expect(lineas[ids[2]], hasLength(2), reason: 'el mixto trae sus dos líneas');
    });

    test('30. el detalle y la Agenda nunca discrepan: misma decisión fiscal', () async {
      final id = await crearDocumentoConTratamiento(TratamientoIva.masIva);
      await actualizarAjuste.ejecutar(
        documentoPorEmitirId: id,
        ajusteManual: -123333,
        motivoAjuste: '2 días',
      );

      final detalle = await documentoRepo.obtenerDetalle(id);
      expect(await totalDeAgenda(id), detalle!.totalesEsperados!.totalEsperado);
    });

    test('31. el total es derivado: no se persiste ni reescribe el documento', () async {
      final id = await crearDocumentoConTratamiento(TratamientoIva.masIva);
      final antes = await documentoRepo.obtenerPorId(id);

      await totalDeAgenda(id);

      final despues = await documentoRepo.obtenerPorId(id);
      expect(despues!.importeBaseEsperado, antes!.importeBaseEsperado);
      expect(despues.importeFinalEsperado, antes.importeFinalEsperado);
      expect(despues.updatedAt, antes.updatedAt);
    });
  });
}
