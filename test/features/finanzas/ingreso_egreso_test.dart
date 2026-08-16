import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import 'package:riseg_one/core/attachments/attachment_repository.dart';
import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/features/finanzas/data/repositories/categoria_financiera_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_por_cobrar_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/ingreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/pago_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/adjuntar_comprobante_egreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/adjuntar_comprobante_ingreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/archivar_categoria_financiera_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cancelar_egreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cancelar_ingreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cancelar_pago_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/corregir_egreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/corregir_ingreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/crear_categoria_financiera_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/obtener_resumen_financiero_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_egreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_ingreso_manual_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_pago_aplicado_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_pago_usecase.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/configuracion_cobro_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/documento_por_emitir_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_portal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/entidad_fiscal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/puesto_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_comercial_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_etapa_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/documento_por_emitir_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_linea_comercial_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_estatus_documento_por_emitir_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_etapa_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_configuracion_cobro_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_documento_manual_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_linea_comercial_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/ensamblar_documento_por_emitir_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_servicio_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/linea_comercial_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/registrar_emision_documento_por_emitir_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';

void main() {
  late AppDatabase db;
  late CuentaPorCobrarRepositoryImpl cuentaRepo;
  late PagoRepositoryImpl pagoRepo;
  late IngresoRepositoryImpl ingresoRepo;
  late EgresoRepositoryImpl egresoRepo;
  late CategoriaFinancieraRepositoryImpl categoriaRepo;
  late ClienteRepositoryImpl clienteRepo;
  late CrearServicioUseCase crearServicio;
  late CrearLineaComercialUseCase crearLineaComercial;
  late CrearConfiguracionCobroUseCase crearConfiguracionCobro;
  late CrearDocumentoManualUseCase crearManual;
  late RegistrarEmisionDocumentoPorEmitirUseCase registrarEmision;
  late CambiarEstatusDocumentoPorEmitirUseCase cambiarEstatus;
  late RegistrarPagoUseCase registrarPago;
  late RegistrarPagoAplicadoUseCase registrarPagoAplicado;
  late CancelarPagoUseCase cancelarPago;
  late CrearCategoriaFinancieraUseCase crearCategoria;
  late ArchivarCategoriaFinancieraUseCase archivarCategoria;
  late RegistrarIngresoManualUseCase registrarIngresoManual;
  late CorregirIngresoUseCase corregirIngreso;
  late CancelarIngresoUseCase cancelarIngreso;
  late AdjuntarComprobanteIngresoUseCase adjuntarComprobanteIngreso;
  late RegistrarEgresoUseCase registrarEgreso;
  late CorregirEgresoUseCase corregirEgreso;
  late CancelarEgresoUseCase cancelarEgreso;
  late AdjuntarComprobanteEgresoUseCase adjuntarComprobanteEgreso;
  late ObtenerResumenFinancieroUseCase obtenerResumenFinanciero;
  late String puestoId;
  late Directory tempDir;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final generarCodigoInterno = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    clienteRepo = ClienteRepositoryImpl(db);
    final servicioRepo = ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db));
    final puestoRepo = PuestoRepositoryImpl(db);
    final catalogoRepo = CatalogoRepositoryImpl(db);
    final entidadFiscalRepo = EntidadFiscalRepositoryImpl(db);
    final clientePortalRepo = ClientePortalRepositoryImpl(db);
    final comercialRepo = ServicioComercialRepositoryImpl(db);
    final configuracionCobroRepo = ConfiguracionCobroRepositoryImpl(db);
    cuentaRepo = CuentaPorCobrarRepositoryImpl(db);
    pagoRepo = PagoRepositoryImpl(db);
    ingresoRepo = IngresoRepositoryImpl(db);
    egresoRepo = EgresoRepositoryImpl(db);
    categoriaRepo = CategoriaFinancieraRepositoryImpl(db);

    final servicioValidator = ServicioValidator(clienteRepo, catalogoRepo);
    final lineaComercialValidator = LineaComercialValidator(puestoRepo, catalogoRepo, servicioRepo, configuracionCobroRepo);
    final configuracionCobroValidator =
        ConfiguracionCobroValidator(servicioRepo, entidadFiscalRepo, catalogoRepo, comercialRepo, clientePortalRepo);
    const reglaValidator = ConfiguracionCobroEtapaValidator();

    crearServicio = CrearServicioUseCase(servicioRepo, generarCodigoInterno, servicioValidator);
    crearLineaComercial = CrearLineaComercialUseCase(comercialRepo, servicioRepo, lineaComercialValidator);
    crearConfiguracionCobro =
        CrearConfiguracionCobroUseCase(configuracionCobroRepo, servicioRepo, configuracionCobroValidator, reglaValidator);

    final ensamblar = EnsamblarDocumentoPorEmitirUseCase(comercialRepo, configuracionCobroRepo);
    final documentoRepo = DocumentoPorEmitirRepositoryImpl(db, AttachmentRepository(db), cuentaRepo);
    crearManual = CrearDocumentoManualUseCase(documentoRepo, configuracionCobroRepo, ensamblar, generarCodigoInterno);
    registrarEmision = RegistrarEmisionDocumentoPorEmitirUseCase(documentoRepo);
    cambiarEstatus = CambiarEstatusDocumentoPorEmitirUseCase(documentoRepo);

    registrarPago = RegistrarPagoUseCase(pagoRepo, clienteRepo, generarCodigoInterno);
    registrarPagoAplicado = RegistrarPagoAplicadoUseCase(pagoRepo, cuentaRepo, generarCodigoInterno);
    cancelarPago = CancelarPagoUseCase(pagoRepo);

    crearCategoria = CrearCategoriaFinancieraUseCase(categoriaRepo);
    archivarCategoria = ArchivarCategoriaFinancieraUseCase(categoriaRepo);
    registrarIngresoManual = RegistrarIngresoManualUseCase(ingresoRepo, generarCodigoInterno);
    corregirIngreso = CorregirIngresoUseCase(ingresoRepo);
    cancelarIngreso = CancelarIngresoUseCase(ingresoRepo);
    registrarEgreso = RegistrarEgresoUseCase(egresoRepo, generarCodigoInterno);
    corregirEgreso = CorregirEgresoUseCase(egresoRepo);
    cancelarEgreso = CancelarEgresoUseCase(egresoRepo);
    obtenerResumenFinanciero = ObtenerResumenFinancieroUseCase(ingresoRepo, egresoRepo);

    tempDir = Directory.systemTemp.createTempSync('riseg_ingreso_egreso_test_');
    adjuntarComprobanteIngreso = AdjuntarComprobanteIngresoUseCase(ingresoRepo, AttachmentStorage(tempDir.path));
    adjuntarComprobanteEgreso = AdjuntarComprobanteEgresoUseCase(egresoRepo, AttachmentStorage(tempDir.path));

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

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// Arma un `DocumentoPorEmitir` real y lo lleva hasta
  /// `procesadoAceptado`, devolviendo su Cuenta por cobrar ya generada
  /// — mismo helper que `pago_test.dart`, reproducido aquí porque cada
  /// archivo de prueba arma su propio `setUp`.
  Future<CuentaPorCobrarData> crearCuentaDePrueba({
    required String nombreCliente,
    int importeEmitido = 500000,
    String? clienteIdExistente,
  }) async {
    String cliente;
    if (clienteIdExistente != null) {
      cliente = clienteIdExistente;
    } else {
      final clienteCreado = await clienteRepo.crear(
        ClienteCompanion.insert(codigo: 'CLI-${nombreCliente.hashCode.toUnsigned(20)}', nombreComercial: nombreCliente),
      );
      cliente = clienteCreado.id;
    }

    final servicioCreado = await crearServicio.ejecutar(
      clienteId: cliente,
      borrador: ServicioBorrador(
        nombre: 'Vigilancia $nombreCliente ${DateTime.now().microsecondsSinceEpoch}',
        tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
        fechaInicio: DateTime(2026, 1, 1),
      ),
    );
    final servicioId = (servicioCreado as GuardarServicioExitoso).servicio.id;

    await crearLineaComercial.ejecutar(
      servicioId: servicioId,
      borrador: LineaComercialBorrador(
        puestoId: puestoId,
        modalidadTurnoId: SeedIds.modalidadTurno24x24,
        cantidadElementos: 1,
        precioUnitario: 1800000,
        tratamientoIva: TratamientoIva.noAplica,
        fechaInicioVigencia: DateTime(2026, 1, 1),
      ),
    );

    final emisionEtapaId = const Uuid().v4();
    await crearConfiguracionCobro.ejecutar(
      servicioId: servicioId,
      borrador: ConfiguracionCobroBorrador(
        tipoDocumento: TipoDocumentoCobro.reciboDePago,
        frecuenciaId: SeedIds.frecuenciaCobroMensual,
        diaInicioPeriodo: 1,
        agrupacion: AgrupacionCobro.porServicio,
        metodo: MetodoPagoCobro.noAplica,
        requiereComplemento: false,
        fechaInicioVigencia: DateTime(2026, 1, 1),
      ),
      etapas: [
        EtapaCobroBorrador(
          id: emisionEtapaId,
          tipoSistema: TipoEventoCobro.emision,
          orden: 0,
          tipoRegla: TipoReglaEvento.diaFijoDelMes,
          mesRelativo: MesRelativoCobro.actual,
          diaDelMes: 1,
        ),
        EtapaCobroBorrador(
          id: const Uuid().v4(),
          tipoSistema: TipoEventoCobro.pagoEsperado,
          orden: 1,
          tipoRegla: TipoReglaEvento.diasHabilesDespuesDe,
          offsetDias: 10,
          etapaReferenciaId: emisionEtapaId,
        ),
      ],
    );

    final resultado = await crearManual.ejecutar(
      clienteId: cliente,
      servicioIds: [servicioId],
      periodoInicio: DateTime(2026, 1, 1),
      periodoFin: DateTime(2026, 1, 31),
    );
    final documento = (resultado as CrearDocumentoManualExitoso).documento;

    await registrarEmision.ejecutar(
      documentoPorEmitirId: documento.id,
      folioDocumento: 'FOL-${documento.id.hashCode.toUnsigned(16)}',
      fechaEmisionReal: DateTime(2026, 1, 5),
      importeEmitido: importeEmitido,
    );
    await cambiarEstatus.ejecutar(documentoPorEmitirId: documento.id, nuevo: EstatusDocumentoPorEmitir.procesadoAceptado);

    return (await cuentaRepo.obtenerPorDocumentoPorEmitirId(documento.id))!;
  }

  group('Ingreso automático desde Pago (Etapa 4K.1, composición en PagoRepositoryImpl)', () {
    test('registrar un Pago aplicado genera su Ingreso automático con el mismo monto', () async {
      final cuenta = await crearCuentaDePrueba(nombreCliente: 'Sportium Ingreso', importeEmitido: 500000);
      final registrado = await registrarPagoAplicado.ejecutar(
        cuentaPorCobrarId: cuenta.id,
        monto: 500000,
        fechaPago: DateTime(2026, 1, 20),
        formaPago: FormaPago.transferencia.name,
      );
      final pago = (registrado as RegistrarPagoAplicadoExitoso).pago;

      final ingreso = await ingresoRepo.obtenerPorPagoId(pago.id);
      expect(ingreso, isNotNull);
      expect(ingreso!.monto, 500000);
      expect(ingreso.estatus, 'registrado');
      expect(ingreso.folioIngreso, matches(RegExp(r'^ING-\d{6}$')));
    });

    test('un Pago con montoAplicado 0 (sin aplicar todavía) también genera su Ingreso — reconocimiento en base a efectivo',
        () async {
      final cuenta = await crearCuentaDePrueba(nombreCliente: 'Miluyole Ingreso', importeEmitido: 500000);
      final registrado = await registrarPago.ejecutar(
        clienteId: cuenta.clienteId,
        montoTotal: 500000,
        fechaPago: DateTime(2026, 1, 20),
        formaPago: FormaPago.transferencia.name,
      );
      final pago = (registrado as RegistrarPagoExitoso).pago;

      final ingreso = await ingresoRepo.obtenerPorPagoId(pago.id);
      expect(ingreso, isNotNull);
      expect(ingreso!.monto, 500000, reason: 'el Ingreso se reconoce al recibir el dinero, no al aplicarlo a una Cuenta');
    });

    test('cancelar el Pago cascada la cancelación de su Ingreso automático', () async {
      final cuenta = await crearCuentaDePrueba(nombreCliente: 'Morgan Ingreso Cancel', importeEmitido: 200000);
      final registrado = await registrarPagoAplicado.ejecutar(
        cuentaPorCobrarId: cuenta.id,
        monto: 200000,
        fechaPago: DateTime(2026, 1, 20),
        formaPago: FormaPago.efectivo.name,
      );
      final pago = (registrado as RegistrarPagoAplicadoExitoso).pago;

      await cancelarPago.ejecutar(pagoId: pago.id, motivo: 'Depósito rechazado');

      final ingreso = await ingresoRepo.obtenerPorPagoId(pago.id);
      expect(ingreso!.estatus, 'cancelado');
      expect(ingreso.motivoCancelacion, isNotNull);
    });

    test('no se puede cancelar directamente un Ingreso automático — debe cancelarse vía su Pago', () async {
      final cuenta = await crearCuentaDePrueba(nombreCliente: 'Tikal Ingreso Guard', importeEmitido: 100000);
      final registrado = await registrarPagoAplicado.ejecutar(
        cuentaPorCobrarId: cuenta.id,
        monto: 100000,
        fechaPago: DateTime(2026, 1, 20),
        formaPago: FormaPago.efectivo.name,
      );
      final pago = (registrado as RegistrarPagoAplicadoExitoso).pago;
      final ingreso = await ingresoRepo.obtenerPorPagoId(pago.id);

      final resultado = await cancelarIngreso.ejecutar(ingresoId: ingreso!.id, motivo: 'Intento inválido');
      expect(resultado, isA<CancelarIngresoPagoAutomatico>());

      final ingresoTrasIntento = await ingresoRepo.obtenerPorId(ingreso.id);
      expect(ingresoTrasIntento!.estatus, 'registrado', reason: 'el intento rechazado no debe cambiar el estatus');
    });
  });

  group('Ingreso manual (sin Pago, Etapa 4K.1)', () {
    test('registra un Ingreso manual con folio ING-######', () async {
      final resultado = await registrarIngresoManual.ejecutar(
        monto: 150000,
        fecha: DateTime(2026, 2, 1),
        formaPago: FormaPago.efectivo.name,
        concepto: 'Venta de activo dado de baja',
      );

      expect(resultado, isA<RegistrarIngresoManualExitoso>());
      final ingreso = (resultado as RegistrarIngresoManualExitoso).ingreso;
      expect(ingreso.pagoId, isNull);
      expect(ingreso.folioIngreso, matches(RegExp(r'^ING-\d{6}$')));
      expect(ingreso.monto, 150000);
    });

    test('rechaza monto inválido', () async {
      final resultado = await registrarIngresoManual.ejecutar(
        monto: 0,
        fecha: DateTime(2026, 2, 1),
        formaPago: FormaPago.efectivo.name,
        concepto: 'Concepto',
      );
      expect(resultado, isA<RegistrarIngresoManualMontoInvalido>());
    });

    test('rechaza concepto vacío', () async {
      final resultado = await registrarIngresoManual.ejecutar(
        monto: 1000,
        fecha: DateTime(2026, 2, 1),
        formaPago: FormaPago.efectivo.name,
        concepto: '   ',
      );
      expect(resultado, isA<RegistrarIngresoManualConceptoRequerido>());
    });

    test('corrige metadatos administrativos pero nunca el monto', () async {
      final registrado = await registrarIngresoManual.ejecutar(
        monto: 150000,
        fecha: DateTime(2026, 2, 1),
        formaPago: FormaPago.efectivo.name,
        concepto: 'Concepto original',
      );
      final ingreso = (registrado as RegistrarIngresoManualExitoso).ingreso;

      final corregido = await corregirIngreso.ejecutar(
        ingresoId: ingreso.id,
        concepto: 'Concepto corregido',
        motivo: 'Error de captura',
      );

      expect(corregido, isA<CorregirIngresoExitoso>());
      final actualizado = (corregido as CorregirIngresoExitoso).ingreso;
      expect(actualizado.concepto, 'Concepto corregido');
      expect(actualizado.monto, 150000);
    });

    test('cancela un Ingreso manual directamente (sin Pago que lo bloquee)', () async {
      final registrado = await registrarIngresoManual.ejecutar(
        monto: 150000,
        fecha: DateTime(2026, 2, 1),
        formaPago: FormaPago.efectivo.name,
        concepto: 'Concepto',
      );
      final ingreso = (registrado as RegistrarIngresoManualExitoso).ingreso;

      final resultado = await cancelarIngreso.ejecutar(ingresoId: ingreso.id, motivo: 'Duplicado');
      expect(resultado, isA<CancelarIngresoExitoso>());
      expect((resultado as CancelarIngresoExitoso).ingreso.estatus, 'cancelado');
    });

    test('adjunta un comprobante y registra el evento comprobanteAdjuntado', () async {
      final registrado = await registrarIngresoManual.ejecutar(
        monto: 150000,
        fecha: DateTime(2026, 2, 1),
        formaPago: FormaPago.efectivo.name,
        concepto: 'Concepto',
      );
      final ingreso = (registrado as RegistrarIngresoManualExitoso).ingreso;

      final sourceFilePath = '${tempDir.path}/comprobante.pdf';
      File(sourceFilePath).writeAsStringSync('contenido de prueba');

      final resultado = await adjuntarComprobanteIngreso.ejecutar(
        ingresoId: ingreso.id,
        sourceFilePath: sourceFilePath,
        originalFileName: 'comprobante.pdf',
        mimeType: 'application/pdf',
      );

      expect(resultado, isA<AdjuntarComprobanteIngresoExitoso>());
      final eventos = await ingresoRepo.listarEventos(ingreso.id);
      expect(eventos.last.tipoEvento, 'comprobanteAdjuntado');
    });
  });

  group('Egreso (100% manual, Etapa 4K.1)', () {
    test('registra un Egreso con folio EGR-######', () async {
      final resultado = await registrarEgreso.ejecutar(
        monto: 80000,
        fecha: DateTime(2026, 2, 3),
        formaPago: FormaPago.transferencia.name,
        beneficiario: 'Proveedor de uniformes',
        concepto: 'Compra de uniformes',
      );

      expect(resultado, isA<RegistrarEgresoExitoso>());
      final egreso = (resultado as RegistrarEgresoExitoso).egreso;
      expect(egreso.folioEgreso, matches(RegExp(r'^EGR-\d{6}$')));
      expect(egreso.beneficiario, 'Proveedor de uniformes');
    });

    test('rechaza monto inválido', () async {
      final resultado = await registrarEgreso.ejecutar(
        monto: -100,
        fecha: DateTime(2026, 2, 3),
        formaPago: FormaPago.efectivo.name,
        concepto: 'Concepto',
      );
      expect(resultado, isA<RegistrarEgresoMontoInvalido>());
    });

    test('corrige metadatos administrativos pero nunca el monto', () async {
      final registrado = await registrarEgreso.ejecutar(
        monto: 80000,
        fecha: DateTime(2026, 2, 3),
        formaPago: FormaPago.efectivo.name,
        concepto: 'Original',
      );
      final egreso = (registrado as RegistrarEgresoExitoso).egreso;

      final corregido = await corregirEgreso.ejecutar(
        egresoId: egreso.id,
        beneficiario: 'Beneficiario corregido',
        motivo: 'Ajuste',
      );

      expect(corregido, isA<CorregirEgresoExitoso>());
      final actualizado = (corregido as CorregirEgresoExitoso).egreso;
      expect(actualizado.beneficiario, 'Beneficiario corregido');
      expect(actualizado.monto, 80000);
    });

    test('cancela un Egreso directamente — sin cascada, no tiene entidades hijas', () async {
      final registrado = await registrarEgreso.ejecutar(
        monto: 80000,
        fecha: DateTime(2026, 2, 3),
        formaPago: FormaPago.efectivo.name,
        concepto: 'Concepto',
      );
      final egreso = (registrado as RegistrarEgresoExitoso).egreso;

      final resultado = await cancelarEgreso.ejecutar(egresoId: egreso.id, motivo: 'Cancelado por error');
      expect(resultado, isA<CancelarEgresoExitoso>());
      expect((resultado as CancelarEgresoExitoso).egreso.estatus, 'cancelado');
    });

    test('rechaza cancelar un Egreso ya cancelado', () async {
      final registrado = await registrarEgreso.ejecutar(
        monto: 80000,
        fecha: DateTime(2026, 2, 3),
        formaPago: FormaPago.efectivo.name,
        concepto: 'Concepto',
      );
      final egreso = (registrado as RegistrarEgresoExitoso).egreso;
      await cancelarEgreso.ejecutar(egresoId: egreso.id, motivo: 'Primera cancelación');

      final segunda = await cancelarEgreso.ejecutar(egresoId: egreso.id, motivo: 'Otra vez');
      expect(segunda, isA<CancelarEgresoYaCancelado>());
    });

    test('adjunta un comprobante y registra el evento comprobanteAdjuntado', () async {
      final registrado = await registrarEgreso.ejecutar(
        monto: 80000,
        fecha: DateTime(2026, 2, 3),
        formaPago: FormaPago.efectivo.name,
        concepto: 'Concepto',
      );
      final egreso = (registrado as RegistrarEgresoExitoso).egreso;

      final sourceFilePath = '${tempDir.path}/comprobante_egreso.pdf';
      File(sourceFilePath).writeAsStringSync('contenido de prueba');

      final resultado = await adjuntarComprobanteEgreso.ejecutar(
        egresoId: egreso.id,
        sourceFilePath: sourceFilePath,
        originalFileName: 'comprobante_egreso.pdf',
        mimeType: 'application/pdf',
      );

      expect(resultado, isA<AdjuntarComprobanteEgresoExitoso>());
      final eventos = await egresoRepo.listarEventos(egreso.id);
      expect(eventos.last.tipoEvento, 'comprobanteAdjuntado');
    });
  });

  group('CategoriaFinanciera (Etapa 4K.1)', () {
    test('crea una categoría y aparece en el listado filtrado por tipo', () async {
      final resultado = await crearCategoria.ejecutar(
        codigo: 'CAT-NOMINA',
        nombre: 'Nómina',
        tipo: 'egreso',
        tipoMovimiento: 'operativo',
      );
      expect(resultado, isA<CrearCategoriaFinancieraExitoso>());

      final soloEgreso = await categoriaRepo.listar(tipo: 'egreso');
      expect(soloEgreso.map((c) => c.codigo), contains('CAT-NOMINA'));

      final soloIngreso = await categoriaRepo.listar(tipo: 'ingreso');
      expect(soloIngreso.map((c) => c.codigo), isNot(contains('CAT-NOMINA')));
    });

    test('una categoría tipo ambos aparece en ambos filtros', () async {
      await crearCategoria.ejecutar(codigo: 'CAT-AJUSTES', nombre: 'Ajustes varios', tipo: 'ambos', tipoMovimiento: 'financiero');

      final soloIngreso = await categoriaRepo.listar(tipo: 'ingreso');
      final soloEgreso = await categoriaRepo.listar(tipo: 'egreso');
      expect(soloIngreso.map((c) => c.codigo), contains('CAT-AJUSTES'));
      expect(soloEgreso.map((c) => c.codigo), contains('CAT-AJUSTES'));
    });

    test('rechaza código vacío', () async {
      final resultado =
          await crearCategoria.ejecutar(codigo: '  ', nombre: 'Nombre', tipo: 'ingreso', tipoMovimiento: 'operativo');
      expect(resultado, isA<CrearCategoriaFinancieraCodigoRequerido>());
    });

    test('archivar quita la categoría del listado activo sin borrarla', () async {
      final creada = await crearCategoria.ejecutar(codigo: 'CAT-TEMP', nombre: 'Temporal', tipo: 'ambos', tipoMovimiento: 'operativo');
      final categoria = (creada as CrearCategoriaFinancieraExitoso).categoria;

      final resultado = await archivarCategoria.ejecutar(categoria.id);
      expect(resultado, isA<ArchivarCategoriaFinancieraExitoso>());

      final activas = await categoriaRepo.listar();
      expect(activas.map((c) => c.id), isNot(contains(categoria.id)));

      final directa = await categoriaRepo.obtenerPorId(categoria.id);
      expect(directa, isNotNull, reason: 'archivar nunca borra físicamente la fila');
      expect(directa!.cicloVidaRegistro, 'archivado');
    });
  });

  group('Resumen financiero base (Resolución 5 de Marlon: totalIngresos/totalEgresos/resultadoOperativo)', () {
    test('suma solo Ingresos/Egresos registrados, excluye cancelados', () async {
      final ingresoUno = await registrarIngresoManual.ejecutar(
        monto: 100000,
        fecha: DateTime(2026, 3, 1),
        formaPago: FormaPago.efectivo.name,
        concepto: 'Ingreso uno',
      );
      await registrarIngresoManual.ejecutar(
        monto: 200000,
        fecha: DateTime(2026, 3, 2),
        formaPago: FormaPago.efectivo.name,
        concepto: 'Ingreso dos',
      );
      final ingresoCancelado = (ingresoUno as RegistrarIngresoManualExitoso).ingreso;
      await cancelarIngreso.ejecutar(ingresoId: ingresoCancelado.id, motivo: 'No aplica');

      await registrarEgreso.ejecutar(
        monto: 50000,
        fecha: DateTime(2026, 3, 1),
        formaPago: FormaPago.efectivo.name,
        concepto: 'Egreso uno',
      );

      final resumen = await obtenerResumenFinanciero.ejecutar();
      expect(resumen.totalIngresos, 200000, reason: 'el Ingreso cancelado no debe sumar');
      expect(resumen.totalEgresos, 50000);
      expect(resumen.resultadoOperativo, 150000);
    });

    test('filtra por rango de fechas', () async {
      await registrarIngresoManual.ejecutar(
        monto: 100000,
        fecha: DateTime(2026, 1, 15),
        formaPago: FormaPago.efectivo.name,
        concepto: 'Fuera de rango',
      );
      await registrarIngresoManual.ejecutar(
        monto: 300000,
        fecha: DateTime(2026, 3, 15),
        formaPago: FormaPago.efectivo.name,
        concepto: 'Dentro de rango',
      );

      final resumen = await obtenerResumenFinanciero.ejecutar(
        rangoInicio: DateTime(2026, 3, 1),
        rangoFin: DateTime(2026, 3, 31),
      );
      expect(resumen.totalIngresos, 300000);
    });
  });
}
