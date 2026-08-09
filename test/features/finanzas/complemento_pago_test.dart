import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/attachments/attachment_repository.dart';
import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/features/finanzas/data/repositories/complemento_pago_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_por_cobrar_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/pago_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/tables/complemento_pago_table.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/adjuntar_archivo_complemento_pago_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cancelar_complemento_pago_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/complemento_pago_derivado.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/complemento_pago_validator.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/corregir_complemento_pago_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_complemento_pago_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_pago_aplicado_usecase.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/configuracion_cobro_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/documento_por_emitir_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/entidad_fiscal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/puesto_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_comercial_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_regla_evento_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/documento_por_emitir_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_linea_comercial_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_estatus_documento_por_emitir_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_regla_evento_validator.dart';
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
  late ComplementoPagoRepositoryImpl complementoRepo;
  late DocumentoPorEmitirRepositoryImpl documentoRepo;
  late ClienteRepositoryImpl clienteRepo;
  late EntidadFiscalRepositoryImpl entidadFiscalRepo;
  late CrearServicioUseCase crearServicio;
  late CrearLineaComercialUseCase crearLineaComercial;
  late CrearConfiguracionCobroUseCase crearConfiguracionCobro;
  late CrearDocumentoManualUseCase crearManual;
  late RegistrarEmisionDocumentoPorEmitirUseCase registrarEmision;
  late CambiarEstatusDocumentoPorEmitirUseCase cambiarEstatus;
  late RegistrarPagoAplicadoUseCase registrarPagoAplicado;
  late RegistrarComplementoPagoUseCase registrarComplemento;
  late CorregirComplementoPagoUseCase corregirComplemento;
  late CancelarComplementoPagoUseCase cancelarComplemento;
  late AdjuntarArchivoComplementoPagoUseCase adjuntarArchivoComplemento;
  late String puestoId;
  late Directory tempDir;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final generarCodigoInterno = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    clienteRepo = ClienteRepositoryImpl(db);
    final servicioRepo = ServicioRepositoryImpl(db);
    final puestoRepo = PuestoRepositoryImpl(db);
    final catalogoRepo = CatalogoRepositoryImpl(db);
    entidadFiscalRepo = EntidadFiscalRepositoryImpl(db);
    final comercialRepo = ServicioComercialRepositoryImpl(db);
    final configuracionCobroRepo = ConfiguracionCobroRepositoryImpl(db);
    cuentaRepo = CuentaPorCobrarRepositoryImpl(db);
    pagoRepo = PagoRepositoryImpl(db);
    complementoRepo = ComplementoPagoRepositoryImpl(db);
    documentoRepo = DocumentoPorEmitirRepositoryImpl(db, AttachmentRepository(db), cuentaRepo);

    final servicioValidator = ServicioValidator(clienteRepo, catalogoRepo);
    final lineaComercialValidator = LineaComercialValidator(puestoRepo, catalogoRepo, servicioRepo, configuracionCobroRepo);
    final configuracionCobroValidator =
        ConfiguracionCobroValidator(servicioRepo, entidadFiscalRepo, catalogoRepo, comercialRepo);
    const reglaValidator = ConfiguracionCobroReglaEventoValidator();

    crearServicio = CrearServicioUseCase(servicioRepo, generarCodigoInterno, servicioValidator);
    crearLineaComercial = CrearLineaComercialUseCase(comercialRepo, servicioRepo, lineaComercialValidator);
    crearConfiguracionCobro =
        CrearConfiguracionCobroUseCase(configuracionCobroRepo, servicioRepo, configuracionCobroValidator, reglaValidator);

    final ensamblar = EnsamblarDocumentoPorEmitirUseCase(comercialRepo, configuracionCobroRepo);
    crearManual = CrearDocumentoManualUseCase(documentoRepo, configuracionCobroRepo, ensamblar, generarCodigoInterno);
    registrarEmision = RegistrarEmisionDocumentoPorEmitirUseCase(documentoRepo);
    cambiarEstatus = CambiarEstatusDocumentoPorEmitirUseCase(documentoRepo);

    registrarPagoAplicado = RegistrarPagoAplicadoUseCase(pagoRepo, cuentaRepo, generarCodigoInterno);
    registrarComplemento = RegistrarComplementoPagoUseCase(complementoRepo, pagoRepo);
    corregirComplemento = CorregirComplementoPagoUseCase(complementoRepo);
    cancelarComplemento = CancelarComplementoPagoUseCase(complementoRepo);

    tempDir = Directory.systemTemp.createTempSync('riseg_complemento_test_');
    adjuntarArchivoComplemento = AdjuntarArchivoComplementoPagoUseCase(complementoRepo, AttachmentStorage(tempDir.path));

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

  /// Arma una Cuenta por cobrar CFDI/PPD con `requiereComplemento` en
  /// verdadero — el único escenario donde 4J.3 exige un Complemento.
  Future<CuentaPorCobrarData> crearCuentaPpdDePrueba({
    required String nombreCliente,
    int importeEmitido = 500000,
    DateTime? fechaPago,
  }) async {
    final cliente =
        await clienteRepo.crear(ClienteCompanion.insert(codigo: 'CLI-${nombreCliente.hashCode.toUnsigned(20)}', nombreComercial: nombreCliente));
    final entidad = await entidadFiscalRepo.crear(
      EntidadFiscalCompanion.insert(
        codigo: 'ENF-${nombreCliente.hashCode.toUnsigned(20)}',
        clienteId: cliente.id,
        razonSocial: '$nombreCliente SA de CV',
        rfc: 'RFC${nombreCliente.hashCode.toUnsigned(20)}',
      ),
    );

    final servicioCreado = await crearServicio.ejecutar(
      clienteId: cliente.id,
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
        tratamientoIva: TratamientoIva.masIva,
        fechaInicioVigencia: DateTime(2026, 1, 1),
      ),
    );

    final configuracionResultado = await crearConfiguracionCobro.ejecutar(
      servicioId: servicioId,
      borrador: ConfiguracionCobroBorrador(
        tipoDocumento: TipoDocumentoCobro.cfdi,
        frecuenciaId: SeedIds.frecuenciaCobroMensual,
        diaInicioPeriodo: 1,
        agrupacion: AgrupacionCobro.porServicio,
        metodo: MetodoPagoCobro.ppd,
        requiereComplemento: true,
        fechaInicioVigencia: DateTime(2026, 1, 1),
        entidadFiscalId: entidad.id,
      ),
      reglas: [
        ReglaEventoBorrador(
          tipoEvento: TipoEventoCobro.emision,
          tipoRegla: TipoReglaEvento.diaFijoDelMes,
          mesRelativo: MesRelativoCobro.actual,
          diaDelMes: 1,
        ),
        ReglaEventoBorrador(
          tipoEvento: TipoEventoCobro.pagoEsperado,
          tipoRegla: TipoReglaEvento.diasHabilesDespuesDe,
          offsetDiasHabiles: 10,
          eventoReferencia: TipoEventoCobro.emision,
        ),
      ],
    );
    expect(configuracionResultado, isA<CrearConfiguracionCobroExitoso>());

    final resultado = await crearManual.ejecutar(
      clienteId: cliente.id,
      servicioIds: [servicioId],
      periodoInicio: DateTime(2026, 1, 1),
      periodoFin: DateTime(2026, 1, 31),
      entidadFiscalId: entidad.id,
    );
    final documento = (resultado as CrearDocumentoManualExitoso).documento;

    await registrarEmision.ejecutar(
      documentoPorEmitirId: documento.id,
      folioDocumento: 'A-${documento.id.hashCode.toUnsigned(16)}',
      serieFiscal: 'A',
      folioFiscal: '${documento.id.hashCode.toUnsigned(8)}',
      uuid: '11111111-1111-1111-1111-111111111111',
      fechaEmisionReal: DateTime(2026, 1, 5),
      importeEmitido: importeEmitido,
    );
    await cambiarEstatus.ejecutar(documentoPorEmitirId: documento.id, nuevo: EstatusDocumentoPorEmitir.procesadoAceptado);

    return (await cuentaRepo.obtenerPorDocumentoPorEmitirId(documento.id))!;
  }

  /// Registra un Pago que liquida por completo [cuenta] — reutiliza el
  /// flujo simplificado ya probado en `pago_test.dart`.
  Future<PagoData> pagarCuentaCompleta(CuentaPorCobrarData cuenta, {DateTime? fechaPago}) async {
    final resultado = await registrarPagoAplicado.ejecutar(
      cuentaPorCobrarId: cuenta.id,
      monto: cuenta.saldoPendiente,
      fechaPago: fechaPago ?? DateTime(2026, 1, 20),
      formaPago: 'transferencia',
    );
    return (resultado as RegistrarPagoAplicadoExitoso).pago;
  }

  group('RegistrarComplementoPagoUseCase — casos reales obligatorios (Etapa 4J.3)', () {
    test('registra un Complemento válido para un Pago que liquidó una Cuenta PPD', () async {
      final cuenta = await crearCuentaPpdDePrueba(nombreCliente: 'Sportium PPD');
      final pago = await pagarCuentaCompleta(cuenta);

      final resultado = await registrarComplemento.ejecutar(
        pagoId: pago.id,
        uuid: '22222222-2222-2222-2222-222222222222',
        serieFiscal: 'REP',
        folioFiscal: '001',
        fechaTimbrado: DateTime(2026, 1, 21),
        montoTotal: cuenta.saldoOriginal,
      );

      expect(resultado, isA<RegistrarComplementoPagoExitoso>());
      final complemento = (resultado as RegistrarComplementoPagoExitoso).complemento;
      expect(complemento.pagoId, pago.id);
      expect(complemento.uuid, '22222222-2222-2222-2222-222222222222');
      expect(complemento.estatus, 'registrado');

      final eventos = await complementoRepo.listarEventos(complemento.id);
      expect(eventos, hasLength(1));
      expect(eventos.single.tipoEvento, 'registrado');
    });

    test('rechaza un Pago inexistente', () async {
      final resultado = await registrarComplemento.ejecutar(
        pagoId: 'no-existe',
        uuid: '22222222-2222-2222-2222-222222222222',
        fechaTimbrado: DateTime(2026, 1, 21),
        montoTotal: 100000,
      );
      expect(resultado, isA<RegistrarComplementoPagoPagoNoExiste>());
    });

    test('rechaza registrar sobre un Pago cancelado', () async {
      final cuenta = await crearCuentaPpdDePrueba(nombreCliente: 'Miluyole PPD');
      final pago = await pagarCuentaCompleta(cuenta);
      await pagoRepo.cancelar(pagoId: pago.id, motivo: 'Prueba');

      final resultado = await registrarComplemento.ejecutar(
        pagoId: pago.id,
        uuid: '22222222-2222-2222-2222-222222222222',
        fechaTimbrado: DateTime(2026, 1, 21),
        montoTotal: 100000,
      );
      expect(resultado, isA<RegistrarComplementoPagoPagoCancelado>());
    });

    test('rechaza un segundo Complemento sobre el mismo Pago (relación 1:1 definitiva)', () async {
      final cuenta = await crearCuentaPpdDePrueba(nombreCliente: 'Morgan PPD');
      final pago = await pagarCuentaCompleta(cuenta);
      await registrarComplemento.ejecutar(
        pagoId: pago.id,
        uuid: '22222222-2222-2222-2222-222222222222',
        fechaTimbrado: DateTime(2026, 1, 21),
        montoTotal: cuenta.saldoOriginal,
      );

      final segundo = await registrarComplemento.ejecutar(
        pagoId: pago.id,
        uuid: '33333333-3333-3333-3333-333333333333',
        fechaTimbrado: DateTime(2026, 1, 22),
        montoTotal: cuenta.saldoOriginal,
      );
      expect(segundo, isA<RegistrarComplementoPagoYaExiste>());
    });

    test('rechaza un UUID con formato inválido', () async {
      final cuenta = await crearCuentaPpdDePrueba(nombreCliente: 'Tikal PPD');
      final pago = await pagarCuentaCompleta(cuenta);

      final resultado = await registrarComplemento.ejecutar(
        pagoId: pago.id,
        uuid: 'no-es-un-uuid',
        fechaTimbrado: DateTime(2026, 1, 21),
        montoTotal: cuenta.saldoOriginal,
      );
      expect(resultado, isA<RegistrarComplementoPagoUuidFormatoInvalido>());
    });

    test('rechaza un UUID ya registrado en otro Complemento', () async {
      final cuentaA = await crearCuentaPpdDePrueba(nombreCliente: 'Toluca PPD A');
      final pagoA = await pagarCuentaCompleta(cuentaA);
      await registrarComplemento.ejecutar(
        pagoId: pagoA.id,
        uuid: '22222222-2222-2222-2222-222222222222',
        fechaTimbrado: DateTime(2026, 1, 21),
        montoTotal: cuentaA.saldoOriginal,
      );

      final cuentaB = await crearCuentaPpdDePrueba(nombreCliente: 'Toluca PPD B');
      final pagoB = await pagarCuentaCompleta(cuentaB);
      final resultado = await registrarComplemento.ejecutar(
        pagoId: pagoB.id,
        uuid: '22222222-2222-2222-2222-222222222222',
        fechaTimbrado: DateTime(2026, 1, 21),
        montoTotal: cuentaB.saldoOriginal,
      );
      expect(resultado, isA<RegistrarComplementoPagoUuidYaRegistrado>());
    });

    test('rechaza un monto inválido', () async {
      final cuenta = await crearCuentaPpdDePrueba(nombreCliente: 'Mirabilia PPD');
      final pago = await pagarCuentaCompleta(cuenta);

      final resultado = await registrarComplemento.ejecutar(
        pagoId: pago.id,
        uuid: '22222222-2222-2222-2222-222222222222',
        fechaTimbrado: DateTime(2026, 1, 21),
        montoTotal: 0,
      );
      expect(resultado, isA<RegistrarComplementoPagoMontoInvalido>());
    });

    test('rechaza fechaTimbrado anterior a fechaPago (Resolución de Marlon, confirmada)', () async {
      final cuenta = await crearCuentaPpdDePrueba(nombreCliente: 'Sportium Fecha');
      final pago = await pagarCuentaCompleta(cuenta, fechaPago: DateTime(2026, 1, 20));

      final resultado = await registrarComplemento.ejecutar(
        pagoId: pago.id,
        uuid: '22222222-2222-2222-2222-222222222222',
        fechaTimbrado: DateTime(2026, 1, 19),
        montoTotal: cuenta.saldoOriginal,
      );
      expect(resultado, isA<RegistrarComplementoPagoFechaTimbradoAnteriorAlPago>());
    });

    test('acepta fechaTimbrado igual a fechaPago (límite inclusivo)', () async {
      final cuenta = await crearCuentaPpdDePrueba(nombreCliente: 'Sportium Limite');
      final pago = await pagarCuentaCompleta(cuenta, fechaPago: DateTime(2026, 1, 20));

      final resultado = await registrarComplemento.ejecutar(
        pagoId: pago.id,
        uuid: '22222222-2222-2222-2222-222222222222',
        fechaTimbrado: DateTime(2026, 1, 20),
        montoTotal: cuenta.saldoOriginal,
      );
      expect(resultado, isA<RegistrarComplementoPagoExitoso>());
    });
  });

  group('Validación de formato de UUID (Resolución de Marlon: nunca exigir versión 4)', () {
    test('acepta un UUID con formato estándar sin importar la versión', () {
      expect(esUuidFormatoValido('11111111-1111-1111-1111-111111111111'), isTrue);
      // Nibble de versión "1" (no v4) — debe aceptarse igual.
      expect(esUuidFormatoValido('a1b2c3d4-e5f6-1789-8abc-def012345678'), isTrue);
    });

    test('rechaza formatos no estándar', () {
      expect(esUuidFormatoValido('no-es-un-uuid'), isFalse);
      expect(esUuidFormatoValido('11111111111111111111111111111111'), isFalse, reason: 'sin guiones');
      expect(esUuidFormatoValido('11111111-1111-1111-1111-11111111111'), isFalse, reason: 'longitud incorrecta');
      expect(esUuidFormatoValido(''), isFalse);
    });
  });

  group('Indicadores derivados (Etapa 4J.3 — corrige la simplificación de 4J.2)', () {
    test('cuentaRequiereComplemento es verdadero solo para PPD con requiereComplemento', () async {
      final cuentaPpd = await crearCuentaPpdDePrueba(nombreCliente: 'Sportium Derivado');
      expect(cuentaRequiereComplemento(cuentaPpd), isTrue);
    });

    test('pagoRequiereComplemento es verdadero si alguna Cuenta tocada lo requiere', () {
      expect(pagoRequiereComplemento([]), isFalse);
    });

    test('complementoPendiente es verdadero sin Complemento registrado', () {
      expect(complementoPendiente(requiereComplemento: true, complemento: null), isTrue);
      expect(complementoPendiente(requiereComplemento: false, complemento: null), isFalse);
    });

    test('complementoPendiente pasa a falso una vez registrado, y vuelve a verdadero si se cancela', () async {
      final cuenta = await crearCuentaPpdDePrueba(nombreCliente: 'Miluyole Derivado');
      final pago = await pagarCuentaCompleta(cuenta);
      final registrado = await registrarComplemento.ejecutar(
        pagoId: pago.id,
        uuid: '22222222-2222-2222-2222-222222222222',
        fechaTimbrado: DateTime(2026, 1, 21),
        montoTotal: cuenta.saldoOriginal,
      );
      final complemento = (registrado as RegistrarComplementoPagoExitoso).complemento;
      expect(complementoPendiente(requiereComplemento: true, complemento: complemento), isFalse);

      final cancelado = await cancelarComplemento.ejecutar(complementoPagoId: complemento.id, motivo: 'Prueba');
      final complementoCancelado = (cancelado as CancelarComplementoPagoExitoso).complemento;
      expect(complementoPendiente(requiereComplemento: true, complemento: complementoCancelado), isTrue);
    });

    test('cierreCobranzaCompleto es falso si la Cuenta no está pagada', () async {
      final cuenta = await crearCuentaPpdDePrueba(nombreCliente: 'Morgan Cierre');
      expect(cierreCobranzaCompleto(cuenta: cuenta, algunPagoConComplementoPendiente: false), isFalse);
    });

    test('cierreCobranzaCompleto es verdadero para una Cuenta pagada que no requiere Complemento', () async {
      final cuenta = await crearCuentaPpdDePrueba(nombreCliente: 'Tikal Cierre');
      await pagarCuentaCompleta(cuenta);
      final cuentaPagada = (await cuentaRepo.obtenerPorId(cuenta.id))!;
      // Simula una Cuenta que no requiere complemento (recibo, por
      // ejemplo) reutilizando la función pura directamente.
      expect(
        cierreCobranzaCompleto(
          cuenta: cuentaPagada.copyWith(metodo: 'noAplica', requiereComplemento: false),
          algunPagoConComplementoPendiente: true,
        ),
        isTrue,
      );
    });

    test('cierreCobranzaCompleto es falso mientras el Complemento de una Cuenta PPD pagada siga pendiente', () async {
      final cuenta = await crearCuentaPpdDePrueba(nombreCliente: 'Toluca Cierre');
      await pagarCuentaCompleta(cuenta);
      final cuentaPagada = (await cuentaRepo.obtenerPorId(cuenta.id))!;
      expect(cuentaPagada.estatus, 'pagada');

      expect(cierreCobranzaCompleto(cuenta: cuentaPagada, algunPagoConComplementoPendiente: true), isFalse);
      expect(cierreCobranzaCompleto(cuenta: cuentaPagada, algunPagoConComplementoPendiente: false), isTrue);
    });
  });

  group('Corrección administrativa de un Complemento', () {
    test('corrige metadatos no monetarios y registra el evento con datos anteriores', () async {
      final cuenta = await crearCuentaPpdDePrueba(nombreCliente: 'Sportium Correccion');
      final pago = await pagarCuentaCompleta(cuenta);
      final registrado = await registrarComplemento.ejecutar(
        pagoId: pago.id,
        uuid: '22222222-2222-2222-2222-222222222222',
        serieFiscal: 'REP-ORIGINAL',
        fechaTimbrado: DateTime(2026, 1, 21),
        montoTotal: cuenta.saldoOriginal,
      );
      final complemento = (registrado as RegistrarComplementoPagoExitoso).complemento;

      final resultado = await corregirComplemento.ejecutar(
        complementoPagoId: complemento.id,
        serieFiscal: 'REP-CORREGIDA',
        motivo: 'Se transcribió mal la serie',
      );

      expect(resultado, isA<CorregirComplementoPagoExitoso>());
      final actualizado = (resultado as CorregirComplementoPagoExitoso).complemento;
      expect(actualizado.serieFiscal, 'REP-CORREGIDA');
      expect(actualizado.uuid, complemento.uuid, reason: 'uuid nunca es editable');
      expect(actualizado.montoTotal, complemento.montoTotal, reason: 'montoTotal nunca es editable');

      final eventos = await complementoRepo.listarEventos(complemento.id);
      expect(eventos.last.tipoEvento, 'corregido');
      expect(eventos.last.observacion, 'Se transcribió mal la serie');
    });

    test('rechaza corregir un Complemento cancelado', () async {
      final cuenta = await crearCuentaPpdDePrueba(nombreCliente: 'Tikal Correccion');
      final pago = await pagarCuentaCompleta(cuenta);
      final registrado = await registrarComplemento.ejecutar(
        pagoId: pago.id,
        uuid: '22222222-2222-2222-2222-222222222222',
        fechaTimbrado: DateTime(2026, 1, 21),
        montoTotal: cuenta.saldoOriginal,
      );
      final complemento = (registrado as RegistrarComplementoPagoExitoso).complemento;
      await cancelarComplemento.ejecutar(complementoPagoId: complemento.id, motivo: 'Prueba');

      final resultado = await corregirComplemento.ejecutar(
        complementoPagoId: complemento.id,
        serieFiscal: 'X',
        motivo: 'Intento inválido',
      );
      expect(resultado, isA<CorregirComplementoPagoCancelado>());
    });
  });

  group('Cancelación (sin cascada — Etapa 4J.3)', () {
    test('cancela un Complemento sin afectar el Pago ni la Cuenta por cobrar', () async {
      final cuenta = await crearCuentaPpdDePrueba(nombreCliente: 'Morgan Cascada');
      final pago = await pagarCuentaCompleta(cuenta);
      final registrado = await registrarComplemento.ejecutar(
        pagoId: pago.id,
        uuid: '22222222-2222-2222-2222-222222222222',
        fechaTimbrado: DateTime(2026, 1, 21),
        montoTotal: cuenta.saldoOriginal,
      );
      final complemento = (registrado as RegistrarComplementoPagoExitoso).complemento;

      final resultado = await cancelarComplemento.ejecutar(complementoPagoId: complemento.id, motivo: 'Error del PAC');
      expect(resultado, isA<CancelarComplementoPagoExitoso>());
      expect((resultado as CancelarComplementoPagoExitoso).complemento.estatus, 'cancelado');

      final pagoTrasCancelar = await pagoRepo.obtenerPorId(pago.id);
      expect(pagoTrasCancelar!.estatus, 'registrado', reason: 'cancelar un Complemento no toca el Pago');
      final cuentaTrasCancelar = await cuentaRepo.obtenerPorId(cuenta.id);
      expect(cuentaTrasCancelar!.estatus, 'pagada', reason: 'cancelar un Complemento no toca la Cuenta por cobrar');
    });

    test('rechaza cancelar un Complemento ya cancelado', () async {
      final cuenta = await crearCuentaPpdDePrueba(nombreCliente: 'Tikal Cascada');
      final pago = await pagarCuentaCompleta(cuenta);
      final registrado = await registrarComplemento.ejecutar(
        pagoId: pago.id,
        uuid: '22222222-2222-2222-2222-222222222222',
        fechaTimbrado: DateTime(2026, 1, 21),
        montoTotal: cuenta.saldoOriginal,
      );
      final complemento = (registrado as RegistrarComplementoPagoExitoso).complemento;
      await cancelarComplemento.ejecutar(complementoPagoId: complemento.id, motivo: 'Primera cancelación');

      final segunda = await cancelarComplemento.ejecutar(complementoPagoId: complemento.id, motivo: 'Otra vez');
      expect(segunda, isA<CancelarComplementoPagoYaCancelado>());
    });
  });

  group('Archivos (PDF/XML mediante Attachment — arco de 5 vías)', () {
    test('adjunta un PDF y un XML, ambos quedan visibles', () async {
      final cuenta = await crearCuentaPpdDePrueba(nombreCliente: 'Sportium Archivos');
      final pago = await pagarCuentaCompleta(cuenta);
      final registrado = await registrarComplemento.ejecutar(
        pagoId: pago.id,
        uuid: '22222222-2222-2222-2222-222222222222',
        fechaTimbrado: DateTime(2026, 1, 21),
        montoTotal: cuenta.saldoOriginal,
      );
      final complemento = (registrado as RegistrarComplementoPagoExitoso).complemento;

      final pdfPath = '${tempDir.path}/complemento.pdf';
      File(pdfPath).writeAsStringSync('contenido pdf');
      final xmlPath = '${tempDir.path}/complemento.xml';
      File(xmlPath).writeAsStringSync('<xml/>');

      final resultadoPdf = await adjuntarArchivoComplemento.ejecutar(
        complementoPagoId: complemento.id,
        categoria: CategoriaAdjuntoComplementoPago.pdf,
        sourceFilePath: pdfPath,
        originalFileName: 'complemento.pdf',
        mimeType: 'application/pdf',
      );
      final resultadoXml = await adjuntarArchivoComplemento.ejecutar(
        complementoPagoId: complemento.id,
        categoria: CategoriaAdjuntoComplementoPago.xml,
        sourceFilePath: xmlPath,
        originalFileName: 'complemento.xml',
        mimeType: 'text/xml',
      );

      expect(resultadoPdf, isA<AdjuntarArchivoComplementoPagoExitoso>());
      expect(resultadoXml, isA<AdjuntarArchivoComplementoPagoExitoso>());

      final archivos = await AttachmentRepository(db).listarActivosPorComplementoPago(complemento.id);
      expect(archivos, hasLength(2), reason: 'ambos deben quedar unidos al Complemento vía ComplementoPagoAttachment');

      final eventos = await complementoRepo.listarEventos(complemento.id);
      expect(eventos.where((e) => e.tipoEvento == 'archivoAdjuntado'), hasLength(2));
    });

    test('rechaza un tipo de archivo incompatible con la categoría', () async {
      final cuenta = await crearCuentaPpdDePrueba(nombreCliente: 'Miluyole Archivos');
      final pago = await pagarCuentaCompleta(cuenta);
      final registrado = await registrarComplemento.ejecutar(
        pagoId: pago.id,
        uuid: '22222222-2222-2222-2222-222222222222',
        fechaTimbrado: DateTime(2026, 1, 21),
        montoTotal: cuenta.saldoOriginal,
      );
      final complemento = (registrado as RegistrarComplementoPagoExitoso).complemento;

      final resultado = await adjuntarArchivoComplemento.ejecutar(
        complementoPagoId: complemento.id,
        categoria: CategoriaAdjuntoComplementoPago.pdf,
        sourceFilePath: '${tempDir.path}/no-importa.txt',
        originalFileName: 'archivo.xml',
        mimeType: 'text/xml',
      );
      expect(resultado, isA<AdjuntarArchivoComplementoPagoTipoArchivoInvalido>());
    });
  });
}
