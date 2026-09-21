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
import 'package:riseg_one/features/finanzas/data/repositories/complemento_pago_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_por_cobrar_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/pago_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/adjuntar_comprobante_pago_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/aplicar_pago_a_cuenta_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cancelar_aplicacion_pago_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cancelar_pago_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/corregir_pago_usecase.dart';
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
  late DocumentoPorEmitirRepositoryImpl documentoRepo;
  late ClienteRepositoryImpl clienteRepo;
  late CrearServicioUseCase crearServicio;
  late CrearLineaComercialUseCase crearLineaComercial;
  late CrearConfiguracionCobroUseCase crearConfiguracionCobro;
  late CrearDocumentoManualUseCase crearManual;
  late RegistrarEmisionDocumentoPorEmitirUseCase registrarEmision;
  late CambiarEstatusDocumentoPorEmitirUseCase cambiarEstatus;
  late RegistrarPagoUseCase registrarPago;
  late AplicarPagoACuentaUseCase aplicarPagoACuenta;
  late RegistrarPagoAplicadoUseCase registrarPagoAplicado;
  late CorregirPagoUseCase corregirPago;
  late CancelarAplicacionPagoUseCase cancelarAplicacionPago;
  late CancelarPagoUseCase cancelarPago;
  late AdjuntarComprobantePagoUseCase adjuntarComprobante;
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
    final complementoPagoRepo = ComplementoPagoRepositoryImpl(db);
    documentoRepo = DocumentoPorEmitirRepositoryImpl(db, AttachmentRepository(db), cuentaRepo);

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
    crearManual = CrearDocumentoManualUseCase(documentoRepo, configuracionCobroRepo, servicioRepo, ensamblar, generarCodigoInterno);
    registrarEmision = RegistrarEmisionDocumentoPorEmitirUseCase(documentoRepo);
    cambiarEstatus = CambiarEstatusDocumentoPorEmitirUseCase(documentoRepo);

    registrarPago = RegistrarPagoUseCase(pagoRepo, clienteRepo, generarCodigoInterno);
    aplicarPagoACuenta = AplicarPagoACuentaUseCase(pagoRepo, cuentaRepo);
    registrarPagoAplicado = RegistrarPagoAplicadoUseCase(pagoRepo, cuentaRepo, generarCodigoInterno);
    corregirPago = CorregirPagoUseCase(pagoRepo, cuentaRepo, complementoPagoRepo);
    cancelarAplicacionPago = CancelarAplicacionPagoUseCase(pagoRepo);
    cancelarPago = CancelarPagoUseCase(pagoRepo, complementoPagoRepo);

    tempDir = Directory.systemTemp.createTempSync('riseg_pago_test_');
    adjuntarComprobante = AdjuntarComprobantePagoUseCase(pagoRepo, AttachmentStorage(tempDir.path));

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
  /// — mismo helper que `cuenta_por_cobrar_test.dart`, reproducido
  /// aquí porque cada archivo de prueba arma su propio `setUp`.
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

  group('RegistrarPagoAplicadoUseCase — flujo simplificado (Etapa 4J.2)', () {
    test('registra el Pago y su única AplicacionPago atómicamente, con folioPago con formato PAG-######', () async {
      final cuenta = await crearCuentaDePrueba(nombreCliente: 'Sportium', importeEmitido: 500000);

      final resultado = await registrarPagoAplicado.ejecutar(
        cuentaPorCobrarId: cuenta.id,
        monto: 500000,
        fechaPago: DateTime(2026, 1, 20),
        formaPago: FormaPago.transferencia.name,
        referencia: 'REF-001',
      );

      expect(resultado, isA<RegistrarPagoAplicadoExitoso>());
      final exitoso = resultado as RegistrarPagoAplicadoExitoso;
      expect(exitoso.pago.folioPago, matches(RegExp(r'^PAG-\d{6}$')));
      expect(exitoso.pago.montoTotal, 500000);
      expect(exitoso.pago.montoAplicado, 500000, reason: 'el flujo simplificado siempre aplica el monto completo');
      expect(exitoso.pago.clienteId, cuenta.clienteId);
      expect(exitoso.aplicacion.monto, 500000);
      expect(exitoso.aplicacion.saldoAntes, 500000);
      expect(exitoso.aplicacion.saldoDespues, 0);

      final cuentaActualizada = await cuentaRepo.obtenerPorId(cuenta.id);
      expect(cuentaActualizada!.saldoPendiente, 0);
      expect(cuentaActualizada.estatus, 'pagada');
    });

    test('un pago parcial deja la Cuenta en estatus parcial', () async {
      final cuenta = await crearCuentaDePrueba(nombreCliente: 'Miluyole', importeEmitido: 500000);

      final resultado = await registrarPagoAplicado.ejecutar(
        cuentaPorCobrarId: cuenta.id,
        monto: 200000,
        fechaPago: DateTime(2026, 1, 20),
        formaPago: FormaPago.efectivo.name,
      );

      expect(resultado, isA<RegistrarPagoAplicadoExitoso>());
      final cuentaActualizada = await cuentaRepo.obtenerPorId(cuenta.id);
      expect(cuentaActualizada!.saldoPendiente, 300000);
      expect(cuentaActualizada.estatus, 'parcial');
    });

    test('varios pagos parciales acumulan hasta saldar por completo', () async {
      final cuenta = await crearCuentaDePrueba(nombreCliente: 'Morgan', importeEmitido: 500000);

      await registrarPagoAplicado.ejecutar(
        cuentaPorCobrarId: cuenta.id,
        monto: 200000,
        fechaPago: DateTime(2026, 1, 20),
        formaPago: FormaPago.efectivo.name,
      );
      final segundo = await registrarPagoAplicado.ejecutar(
        cuentaPorCobrarId: cuenta.id,
        monto: 300000,
        fechaPago: DateTime(2026, 1, 25),
        formaPago: FormaPago.transferencia.name,
      );

      expect(segundo, isA<RegistrarPagoAplicadoExitoso>());
      expect((segundo as RegistrarPagoAplicadoExitoso).aplicacion.saldoAntes, 300000);
      final cuentaActualizada = await cuentaRepo.obtenerPorId(cuenta.id);
      expect(cuentaActualizada!.saldoPendiente, 0);
      expect(cuentaActualizada.estatus, 'pagada');
    });

    test('rechaza sobrepago', () async {
      final cuenta = await crearCuentaDePrueba(nombreCliente: 'Toluca 32', importeEmitido: 500000);

      final resultado = await registrarPagoAplicado.ejecutar(
        cuentaPorCobrarId: cuenta.id,
        monto: 600000,
        fechaPago: DateTime(2026, 1, 20),
        formaPago: FormaPago.transferencia.name,
      );

      expect(resultado, isA<RegistrarPagoAplicadoSobrepago>());
      expect((resultado as RegistrarPagoAplicadoSobrepago).saldoDisponible, 500000);
      final cuentaActualizada = await cuentaRepo.obtenerPorId(cuenta.id);
      expect(cuentaActualizada!.saldoPendiente, 500000, reason: 'un sobrepago rechazado no debe modificar la cuenta');
    });

    test('rechaza monto inválido', () async {
      final cuenta = await crearCuentaDePrueba(nombreCliente: 'Tikal', importeEmitido: 500000);
      final resultado = await registrarPagoAplicado.ejecutar(
        cuentaPorCobrarId: cuenta.id,
        monto: 0,
        fechaPago: DateTime(2026, 1, 20),
        formaPago: FormaPago.efectivo.name,
      );
      expect(resultado, isA<RegistrarPagoAplicadoMontoInvalido>());
    });

    test('rechaza una Cuenta ya pagada', () async {
      final cuenta = await crearCuentaDePrueba(nombreCliente: 'Mirabilia', importeEmitido: 500000);
      await registrarPagoAplicado.ejecutar(
        cuentaPorCobrarId: cuenta.id,
        monto: 500000,
        fechaPago: DateTime(2026, 1, 20),
        formaPago: FormaPago.transferencia.name,
      );

      final resultado = await registrarPagoAplicado.ejecutar(
        cuentaPorCobrarId: cuenta.id,
        monto: 100,
        fechaPago: DateTime(2026, 1, 21),
        formaPago: FormaPago.efectivo.name,
      );
      expect(resultado, isA<RegistrarPagoAplicadoCuentaYaPagada>());
    });

    test('rechaza una Cuenta por cobrar inexistente', () async {
      final resultado = await registrarPagoAplicado.ejecutar(
        cuentaPorCobrarId: 'no-existe',
        monto: 1000,
        fechaPago: DateTime(2026, 1, 20),
        formaPago: FormaPago.efectivo.name,
      );
      expect(resultado, isA<RegistrarPagoAplicadoCuentaNoExiste>());
    });

    // Caso real MILUYOLE (Etapa 15, corrección estructural CFDI real):
    // subtotal $21,800.00, IVA 16% $3,488.00, Total $25,288.00.
    // `importeEmitido` debe capturarse como el Total real ($25,288.00,
    // no el subtotal) — con esa corrección, la CxC nace por el monto
    // realmente cobrable y un pago por el Total exacto ya NO se
    // rechaza como sobrepago (antes de esta corrección, capturar el
    // subtotal como `importeEmitido` producía justo ese bloqueo real).
    test('CFDI con IVA (MILUYOLE): CxC nace por el Total real y un pago por ese Total no es sobrepago', () async {
      final cuenta = await crearCuentaDePrueba(nombreCliente: 'MILUYOLE', importeEmitido: 2528800);
      expect(cuenta.saldoOriginal, 2528800, reason: 'la CxC debe representar el Total real cobrable, no el subtotal');
      expect(cuenta.saldoPendiente, 2528800);

      final resultado = await registrarPagoAplicado.ejecutar(
        cuentaPorCobrarId: cuenta.id,
        monto: 2528800,
        fechaPago: DateTime(2026, 1, 20),
        formaPago: FormaPago.transferencia.name,
      );

      expect(resultado, isA<RegistrarPagoAplicadoExitoso>());
      final cuentaActualizada = await cuentaRepo.obtenerPorId(cuenta.id);
      expect(cuentaActualizada!.saldoPendiente, 0);
      expect(cuentaActualizada.estatus, 'pagada');
    });
  });

  group('Modelo N:M — un mismo Pago aplicado a varias Cuentas por cobrar', () {
    test('un Pago cubre dos Cuentas del mismo Cliente (transferencia que liquida varias facturas)', () async {
      final clienteCreado = await clienteRepo.crear(ClienteCompanion.insert(codigo: 'CLI-900001', nombreComercial: 'Sportium Multi'));
      final cuentaA = await crearCuentaDePrueba(
        nombreCliente: 'Sportium Multi',
        importeEmitido: 300000,
        clienteIdExistente: clienteCreado.id,
      );
      final cuentaB = await crearCuentaDePrueba(
        nombreCliente: 'Sportium Multi',
        importeEmitido: 200000,
        clienteIdExistente: clienteCreado.id,
      );

      final registrado = await registrarPago.ejecutar(
        clienteId: clienteCreado.id,
        montoTotal: 500000,
        fechaPago: DateTime(2026, 1, 20),
        formaPago: FormaPago.transferencia.name,
        referencia: 'TRANSFER-CONSOLIDADA',
      );
      expect(registrado, isA<RegistrarPagoExitoso>());
      final pago = (registrado as RegistrarPagoExitoso).pago;
      expect(pago.montoAplicado, 0, reason: 'un Pago recién registrado nace sin aplicaciones (Resolución 8 de Marlon)');

      final aplicacionA =
          await aplicarPagoACuenta.ejecutar(pagoId: pago.id, cuentaPorCobrarId: cuentaA.id, monto: 300000);
      final aplicacionB =
          await aplicarPagoACuenta.ejecutar(pagoId: pago.id, cuentaPorCobrarId: cuentaB.id, monto: 200000);

      expect(aplicacionA, isA<AplicarPagoACuentaExitoso>());
      expect(aplicacionB, isA<AplicarPagoACuentaExitoso>());

      final pagoActualizado = await pagoRepo.obtenerPorId(pago.id);
      expect(pagoActualizado!.montoAplicado, 500000);

      final cuentaAActualizada = await cuentaRepo.obtenerPorId(cuentaA.id);
      final cuentaBActualizada = await cuentaRepo.obtenerPorId(cuentaB.id);
      expect(cuentaAActualizada!.estatus, 'pagada');
      expect(cuentaBActualizada!.estatus, 'pagada');
    });

    test('rechaza aplicar un Pago a una Cuenta de un Cliente distinto', () async {
      final cuentaClienteA = await crearCuentaDePrueba(nombreCliente: 'Cliente A', importeEmitido: 100000);
      final cuentaClienteB = await crearCuentaDePrueba(nombreCliente: 'Cliente B', importeEmitido: 100000);

      final registrado = await registrarPago.ejecutar(
        clienteId: cuentaClienteA.clienteId!,
        montoTotal: 100000,
        fechaPago: DateTime(2026, 1, 20),
        formaPago: FormaPago.efectivo.name,
      );
      final pago = (registrado as RegistrarPagoExitoso).pago;

      final resultado =
          await aplicarPagoACuenta.ejecutar(pagoId: pago.id, cuentaPorCobrarId: cuentaClienteB.id, monto: 100000);
      expect(resultado, isA<AplicarPagoACuentaClienteNoCoincide>());
    });

    test('rechaza sobrepago del Pago cuando la suma de aplicaciones excede montoTotal', () async {
      final clienteCreado = await clienteRepo.crear(ClienteCompanion.insert(codigo: 'CLI-900002', nombreComercial: 'Sportium Sobrepago'));
      final cuentaA = await crearCuentaDePrueba(
        nombreCliente: 'Sportium Sobrepago',
        importeEmitido: 300000,
        clienteIdExistente: clienteCreado.id,
      );
      final cuentaB = await crearCuentaDePrueba(
        nombreCliente: 'Sportium Sobrepago',
        importeEmitido: 300000,
        clienteIdExistente: clienteCreado.id,
      );

      final registrado = await registrarPago.ejecutar(
        clienteId: clienteCreado.id,
        montoTotal: 400000,
        fechaPago: DateTime(2026, 1, 20),
        formaPago: FormaPago.transferencia.name,
      );
      final pago = (registrado as RegistrarPagoExitoso).pago;

      await aplicarPagoACuenta.ejecutar(pagoId: pago.id, cuentaPorCobrarId: cuentaA.id, monto: 300000);
      final resultado =
          await aplicarPagoACuenta.ejecutar(pagoId: pago.id, cuentaPorCobrarId: cuentaB.id, monto: 200000);

      expect(resultado, isA<AplicarPagoACuentaSobrepagoDelPago>());
      expect((resultado as AplicarPagoACuentaSobrepagoDelPago).montoDisponible, 100000);
    });

    test('rechaza sobrepago de la Cuenta aunque el Pago tenga saldo suficiente sin aplicar', () async {
      final cuenta = await crearCuentaDePrueba(nombreCliente: 'Sportium Solo', importeEmitido: 100000);
      final registrado = await registrarPago.ejecutar(
        clienteId: cuenta.clienteId!,
        montoTotal: 500000,
        fechaPago: DateTime(2026, 1, 20),
        formaPago: FormaPago.transferencia.name,
      );
      final pago = (registrado as RegistrarPagoExitoso).pago;

      final resultado =
          await aplicarPagoACuenta.ejecutar(pagoId: pago.id, cuentaPorCobrarId: cuenta.id, monto: 200000);
      expect(resultado, isA<AplicarPagoACuentaSobrepagoDeLaCuenta>());
      expect((resultado as AplicarPagoACuentaSobrepagoDeLaCuenta).saldoDisponible, 100000);
    });

    test('rechaza aplicar sobre un Pago cancelado', () async {
      final cuenta = await crearCuentaDePrueba(nombreCliente: 'Sportium Cancelado', importeEmitido: 100000);
      final registrado = await registrarPago.ejecutar(
        clienteId: cuenta.clienteId!,
        montoTotal: 100000,
        fechaPago: DateTime(2026, 1, 20),
        formaPago: FormaPago.efectivo.name,
      );
      final pago = (registrado as RegistrarPagoExitoso).pago;
      await cancelarPago.ejecutar(pagoId: pago.id, motivo: 'Prueba');

      final resultado = await aplicarPagoACuenta.ejecutar(pagoId: pago.id, cuentaPorCobrarId: cuenta.id, monto: 100000);
      expect(resultado, isA<AplicarPagoACuentaPagoCancelado>());
    });
  });

  group('Corrección administrativa de un Pago', () {
    test('corrige metadatos no monetarios y registra el evento con datos anteriores', () async {
      final cuenta = await crearCuentaDePrueba(nombreCliente: 'Morgan Correccion', importeEmitido: 100000);
      final registrado = await registrarPagoAplicado.ejecutar(
        cuentaPorCobrarId: cuenta.id,
        monto: 100000,
        fechaPago: DateTime(2026, 1, 20),
        formaPago: FormaPago.efectivo.name,
        referencia: 'REF-ORIGINAL',
      );
      final pago = (registrado as RegistrarPagoAplicadoExitoso).pago;

      final resultado = await corregirPago.ejecutar(
        pagoId: pago.id,
        formaPago: FormaPago.transferencia.name,
        referencia: 'REF-CORREGIDA',
        motivo: 'Se capturó mal la forma de pago',
      );

      expect(resultado, isA<CorregirPagoExitoso>());
      final actualizado = (resultado as CorregirPagoExitoso).pago;
      expect(actualizado.formaPago, FormaPago.transferencia.name);
      expect(actualizado.referencia, 'REF-CORREGIDA');
      expect(actualizado.montoTotal, 100000, reason: 'montoTotal nunca es editable');

      final eventos = await pagoRepo.listarEventos(pago.id);
      expect(eventos.last.tipoEvento, 'corregido');
      expect(eventos.last.observacion, 'Se capturó mal la forma de pago');
    });

    test('rechaza corregir un Pago cancelado', () async {
      final cuenta = await crearCuentaDePrueba(nombreCliente: 'Tikal Correccion', importeEmitido: 100000);
      final registrado = await registrarPagoAplicado.ejecutar(
        cuentaPorCobrarId: cuenta.id,
        monto: 100000,
        fechaPago: DateTime(2026, 1, 20),
        formaPago: FormaPago.efectivo.name,
      );
      final pago = (registrado as RegistrarPagoAplicadoExitoso).pago;
      await cancelarPago.ejecutar(pagoId: pago.id, motivo: 'Prueba');

      final resultado = await corregirPago.ejecutar(pagoId: pago.id, referencia: 'X', motivo: 'Intento inválido');
      expect(resultado, isA<CorregirPagoCancelado>());
    });
  });

  group('Cancelación (Etapa 4J.2, Resolución 7 de Marlon: cascada automática)', () {
    test('cancelar una aplicación individual revierte el saldo de la Cuenta y libera el monto en el Pago', () async {
      final cuenta = await crearCuentaDePrueba(nombreCliente: 'Morgan Cancelacion', importeEmitido: 500000);
      final registrado = await registrarPagoAplicado.ejecutar(
        cuentaPorCobrarId: cuenta.id,
        monto: 200000,
        fechaPago: DateTime(2026, 1, 20),
        formaPago: FormaPago.efectivo.name,
      );
      final resultadoExitoso = registrado as RegistrarPagoAplicadoExitoso;

      final cancelado = await cancelarAplicacionPago.ejecutar(
        aplicacionPagoId: resultadoExitoso.aplicacion.id,
        motivo: 'Aplicación duplicada por error',
      );

      expect(cancelado, isA<CancelarAplicacionPagoExitoso>());
      final cuentaActualizada = await cuentaRepo.obtenerPorId(cuenta.id);
      expect(cuentaActualizada!.saldoPendiente, 500000, reason: 'el saldo debe revertirse por completo');
      expect(cuentaActualizada.estatus, 'pendiente');

      final pagoActualizado = await pagoRepo.obtenerPorId(resultadoExitoso.pago.id);
      expect(pagoActualizado!.montoAplicado, 0, reason: 'el monto liberado queda disponible de nuevo en el Pago');
    });

    test('el monto liberado por una cancelación puede volver a aplicarse (a la misma Cuenta o a otra)', () async {
      final cuenta = await crearCuentaDePrueba(nombreCliente: 'Miluyole Reaplicacion', importeEmitido: 300000);
      final registrado = await registrarPagoAplicado.ejecutar(
        cuentaPorCobrarId: cuenta.id,
        monto: 300000,
        fechaPago: DateTime(2026, 1, 20),
        formaPago: FormaPago.efectivo.name,
      );
      final resultadoExitoso = registrado as RegistrarPagoAplicadoExitoso;
      await cancelarAplicacionPago.ejecutar(aplicacionPagoId: resultadoExitoso.aplicacion.id, motivo: 'Prueba');

      final reaplicado = await aplicarPagoACuenta.ejecutar(
        pagoId: resultadoExitoso.pago.id,
        cuentaPorCobrarId: cuenta.id,
        monto: 300000,
      );
      expect(reaplicado, isA<AplicarPagoACuentaExitoso>());

      final cuentaActualizada = await cuentaRepo.obtenerPorId(cuenta.id);
      expect(cuentaActualizada!.estatus, 'pagada');
    });

    test('cancelar un Pago completo cancela en cascada todas sus aplicaciones activas', () async {
      final clienteCreado = await clienteRepo.crear(ClienteCompanion.insert(codigo: 'CLI-900003', nombreComercial: 'Sportium Cascada'));
      final cuentaA = await crearCuentaDePrueba(
        nombreCliente: 'Sportium Cascada',
        importeEmitido: 200000,
        clienteIdExistente: clienteCreado.id,
      );
      final cuentaB = await crearCuentaDePrueba(
        nombreCliente: 'Sportium Cascada',
        importeEmitido: 300000,
        clienteIdExistente: clienteCreado.id,
      );

      final registrado = await registrarPago.ejecutar(
        clienteId: clienteCreado.id,
        montoTotal: 500000,
        fechaPago: DateTime(2026, 1, 20),
        formaPago: FormaPago.transferencia.name,
      );
      final pago = (registrado as RegistrarPagoExitoso).pago;
      await aplicarPagoACuenta.ejecutar(pagoId: pago.id, cuentaPorCobrarId: cuentaA.id, monto: 200000);
      await aplicarPagoACuenta.ejecutar(pagoId: pago.id, cuentaPorCobrarId: cuentaB.id, monto: 300000);

      final cancelado = await cancelarPago.ejecutar(pagoId: pago.id, motivo: 'Depósito rechazado por el banco');

      expect(cancelado, isA<CancelarPagoExitoso>());
      expect((cancelado as CancelarPagoExitoso).pago.estatus, 'cancelado');

      final cuentaAActualizada = await cuentaRepo.obtenerPorId(cuentaA.id);
      final cuentaBActualizada = await cuentaRepo.obtenerPorId(cuentaB.id);
      expect(cuentaAActualizada!.saldoPendiente, 200000, reason: 'la cascada debe revertir ambas Cuentas');
      expect(cuentaBActualizada!.saldoPendiente, 300000);

      final aplicaciones = await pagoRepo.listarAplicacionesPorPago(pago.id);
      expect(aplicaciones.every((a) => a.estatus == 'cancelada'), isTrue);
    });

    test('cancelar un Pago sin aplicaciones no falla (Resolución 8 de Marlon)', () async {
      final cuenta = await crearCuentaDePrueba(nombreCliente: 'Tikal Sin Aplicar', importeEmitido: 100000);
      final registrado = await registrarPago.ejecutar(
        clienteId: cuenta.clienteId!,
        montoTotal: 100000,
        fechaPago: DateTime(2026, 1, 20),
        formaPago: FormaPago.efectivo.name,
      );
      final pago = (registrado as RegistrarPagoExitoso).pago;

      final cancelado = await cancelarPago.ejecutar(pagoId: pago.id, motivo: 'Ya no se recibirá');
      expect(cancelado, isA<CancelarPagoExitoso>());
    });

    test('rechaza cancelar una aplicación ya cancelada', () async {
      final cuenta = await crearCuentaDePrueba(nombreCliente: 'Mirabilia Doble Cancel', importeEmitido: 100000);
      final registrado = await registrarPagoAplicado.ejecutar(
        cuentaPorCobrarId: cuenta.id,
        monto: 100000,
        fechaPago: DateTime(2026, 1, 20),
        formaPago: FormaPago.efectivo.name,
      );
      final resultadoExitoso = registrado as RegistrarPagoAplicadoExitoso;
      await cancelarAplicacionPago.ejecutar(aplicacionPagoId: resultadoExitoso.aplicacion.id, motivo: 'Primera cancelación');

      final segundaCancelacion =
          await cancelarAplicacionPago.ejecutar(aplicacionPagoId: resultadoExitoso.aplicacion.id, motivo: 'Otra vez');
      expect(segundaCancelacion, isA<CancelarAplicacionPagoYaCancelada>());
    });

    test('rechaza cancelar un Pago ya cancelado', () async {
      final cuenta = await crearCuentaDePrueba(nombreCliente: 'Toluca Doble Cancel', importeEmitido: 100000);
      final registrado = await registrarPago.ejecutar(
        clienteId: cuenta.clienteId!,
        montoTotal: 100000,
        fechaPago: DateTime(2026, 1, 20),
        formaPago: FormaPago.efectivo.name,
      );
      final pago = (registrado as RegistrarPagoExitoso).pago;
      await cancelarPago.ejecutar(pagoId: pago.id, motivo: 'Primera cancelación');

      final segundaCancelacion = await cancelarPago.ejecutar(pagoId: pago.id, motivo: 'Otra vez');
      expect(segundaCancelacion, isA<CancelarPagoYaCancelado>());
    });
  });

  group('Comprobantes de pago (mismo mecanismo que Attachment)', () {
    test('adjunta un comprobante y registra el evento comprobanteAdjuntado', () async {
      final cuenta = await crearCuentaDePrueba(nombreCliente: 'Sportium Comprobante', importeEmitido: 100000);
      final registrado = await registrarPago.ejecutar(
        clienteId: cuenta.clienteId!,
        montoTotal: 100000,
        fechaPago: DateTime(2026, 1, 20),
        formaPago: FormaPago.transferencia.name,
      );
      final pago = (registrado as RegistrarPagoExitoso).pago;

      final sourceFilePath = '${tempDir.path}/comprobante.pdf';
      File(sourceFilePath).writeAsStringSync('contenido de prueba');

      final resultado = await adjuntarComprobante.ejecutar(
        pagoId: pago.id,
        sourceFilePath: sourceFilePath,
        originalFileName: 'comprobante_transferencia.pdf',
        mimeType: 'application/pdf',
      );

      expect(resultado, isA<AdjuntarComprobantePagoExitoso>());
      final adjunto = (resultado as AdjuntarComprobantePagoExitoso).adjunto;
      expect(adjunto.categoria, 'comprobante');

      final comprobantes = await AttachmentRepository(db).listarActivosPorPago(pago.id);
      expect(comprobantes, hasLength(1));
      expect(comprobantes.single.id, adjunto.id, reason: 'el comprobante debe quedar unido al Pago vía PagoAttachment');

      final eventos = await pagoRepo.listarEventos(pago.id);
      expect(eventos.last.tipoEvento, 'comprobanteAdjuntado');
    });

    test('rechaza adjuntar un comprobante a un Pago inexistente', () async {
      final resultado = await adjuntarComprobante.ejecutar(
        pagoId: 'no-existe',
        sourceFilePath: '${tempDir.path}/x.pdf',
        originalFileName: 'x.pdf',
        mimeType: 'application/pdf',
      );
      expect(resultado, isA<AdjuntarComprobantePagoNoExiste>());
    });
  });

  group('folioPago', () {
    test('se genera secuencialmente con el formato PAG-000001, PAG-000002, ...', () async {
      final cuenta = await crearCuentaDePrueba(nombreCliente: 'Sportium Folios', importeEmitido: 1000000);

      final primero = await registrarPagoAplicado.ejecutar(
        cuentaPorCobrarId: cuenta.id,
        monto: 100000,
        fechaPago: DateTime(2026, 1, 20),
        formaPago: FormaPago.efectivo.name,
      );
      final segundo = await registrarPagoAplicado.ejecutar(
        cuentaPorCobrarId: cuenta.id,
        monto: 100000,
        fechaPago: DateTime(2026, 1, 21),
        formaPago: FormaPago.efectivo.name,
      );

      expect((primero as RegistrarPagoAplicadoExitoso).pago.folioPago, 'PAG-000001');
      expect((segundo as RegistrarPagoAplicadoExitoso).pago.folioPago, 'PAG-000002');
    });
  });
}
