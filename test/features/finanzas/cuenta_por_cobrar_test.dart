import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/attachments/attachment_repository.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_por_cobrar_repository_impl.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/actualizar_fecha_vencimiento_cuenta_por_cobrar_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cuenta_por_cobrar_antiguedad.dart';
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
  late DocumentoPorEmitirRepositoryImpl documentoRepo;
  late ClienteRepositoryImpl clienteRepo;
  late ServicioRepositoryImpl servicioRepo;
  late CrearServicioUseCase crearServicio;
  late CrearLineaComercialUseCase crearLineaComercial;
  late CrearConfiguracionCobroUseCase crearConfiguracionCobro;
  late CrearDocumentoManualUseCase crearManual;
  late RegistrarEmisionDocumentoPorEmitirUseCase registrarEmision;
  late CambiarEstatusDocumentoPorEmitirUseCase cambiarEstatus;
  late ActualizarFechaVencimientoCuentaPorCobrarUseCase actualizarVencimiento;
  late String puestoId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    clienteRepo = ClienteRepositoryImpl(db);
    servicioRepo = ServicioRepositoryImpl(db);
    final puestoRepo = PuestoRepositoryImpl(db);
    final catalogoRepo = CatalogoRepositoryImpl(db);
    final entidadFiscalRepo = EntidadFiscalRepositoryImpl(db);
    final comercialRepo = ServicioComercialRepositoryImpl(db);
    final configuracionCobroRepo = ConfiguracionCobroRepositoryImpl(db);
    cuentaRepo = CuentaPorCobrarRepositoryImpl(db);
    documentoRepo = DocumentoPorEmitirRepositoryImpl(db, AttachmentRepository(db), cuentaRepo);

    final servicioValidator = ServicioValidator(clienteRepo, catalogoRepo);
    final lineaComercialValidator = LineaComercialValidator(puestoRepo, catalogoRepo, servicioRepo, configuracionCobroRepo);
    final configuracionCobroValidator =
        ConfiguracionCobroValidator(servicioRepo, entidadFiscalRepo, catalogoRepo, comercialRepo);
    const reglaValidator = ConfiguracionCobroReglaEventoValidator();

    crearServicio = CrearServicioUseCase(servicioRepo, generarCodigo, servicioValidator);
    crearLineaComercial = CrearLineaComercialUseCase(comercialRepo, servicioRepo, lineaComercialValidator);
    crearConfiguracionCobro =
        CrearConfiguracionCobroUseCase(configuracionCobroRepo, servicioRepo, configuracionCobroValidator, reglaValidator);

    final ensamblar = EnsamblarDocumentoPorEmitirUseCase(comercialRepo, configuracionCobroRepo);
    crearManual = CrearDocumentoManualUseCase(documentoRepo, configuracionCobroRepo, ensamblar, generarCodigo);
    registrarEmision = RegistrarEmisionDocumentoPorEmitirUseCase(documentoRepo);
    cambiarEstatus = CambiarEstatusDocumentoPorEmitirUseCase(documentoRepo);
    actualizarVencimiento = ActualizarFechaVencimientoCuentaPorCobrarUseCase(cuentaRepo);

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

  /// Arma un `DocumentoPorEmitir` real (Cliente + Servicio + Línea +
  /// Configuración de cobro) y lo lleva hasta `Emitido`, listo para
  /// transicionar a `procesadoAceptado`. Con `reglaPago: false` (caso
  /// Mirabilia) el documento nace sin `fechaPagoEsperadoProgramada`.
  Future<String> crearDocumentoEmitido({
    required String nombreCliente,
    TipoDocumentoCobro tipoDocumento = TipoDocumentoCobro.reciboDePago,
    bool reglaPago = true,
    int importeEmitido = 500000,
  }) async {
    final cliente = await clienteRepo.crear(
      ClienteCompanion.insert(codigo: 'CLI-${nombreCliente.hashCode.toUnsigned(20)}', nombreComercial: nombreCliente),
    );

    String? entidadFiscalId;
    if (tipoDocumento == TipoDocumentoCobro.cfdi) {
      final entidadFiscalRepo = EntidadFiscalRepositoryImpl(db);
      final entidad = await entidadFiscalRepo.crear(
        EntidadFiscalCompanion.insert(
          codigo: 'ENF-${nombreCliente.hashCode.toUnsigned(20)}',
          clienteId: cliente.id,
          razonSocial: '$nombreCliente SA de CV',
          rfc: 'MOR010101AAA',
        ),
      );
      entidadFiscalId = entidad.id;
    }

    final servicioCreado = await crearServicio.ejecutar(
      clienteId: cliente.id,
      borrador: ServicioBorrador(
        nombre: 'Vigilancia $nombreCliente',
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
        tratamientoIva: tipoDocumento == TipoDocumentoCobro.cfdi ? TratamientoIva.masIva : TratamientoIva.noAplica,
        fechaInicioVigencia: DateTime(2026, 1, 1),
      ),
    );

    final configuracionResultado = await crearConfiguracionCobro.ejecutar(
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
      reglas: reglaPago
          ? [
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
            ]
          : const [],
    );
    expect(configuracionResultado, isA<CrearConfiguracionCobroExitoso>());

    final resultado = await crearManual.ejecutar(
      clienteId: cliente.id,
      servicioIds: [servicioId],
      periodoInicio: DateTime(2026, 1, 1),
      periodoFin: DateTime(2026, 1, 31),
      entidadFiscalId: entidadFiscalId,
    );
    expect(resultado, isA<CrearDocumentoManualExitoso>());
    final documento = (resultado as CrearDocumentoManualExitoso).documento;

    final emisionResultado = await registrarEmision.ejecutar(
      documentoPorEmitirId: documento.id,
      folioDocumento: 'FOL-001',
      serieFiscal: tipoDocumento == TipoDocumentoCobro.cfdi ? 'A' : null,
      folioFiscal: tipoDocumento == TipoDocumentoCobro.cfdi ? '001' : null,
      uuid: tipoDocumento == TipoDocumentoCobro.cfdi ? '11111111-1111-1111-1111-111111111111' : null,
      fechaEmisionReal: DateTime(2026, 1, 5),
      importeEmitido: importeEmitido,
    );
    expect(emisionResultado, isA<RegistrarEmisionDocumentoPorEmitirExitoso>());

    return documento.id;
  }

  group('Creación atómica de la Cuenta por cobrar (Resolución A de Marlon)', () {
    test('procesadoAceptado genera un snapshot administrativo completo', () async {
      final documentoId = await crearDocumentoEmitido(nombreCliente: 'Morgan');
      final documentoAntes = await documentoRepo.obtenerPorId(documentoId);

      final resultado =
          await cambiarEstatus.ejecutar(documentoPorEmitirId: documentoId, nuevo: EstatusDocumentoPorEmitir.procesadoAceptado);
      expect(resultado, isA<CambiarEstatusDocumentoPorEmitirExitoso>());

      final cuenta = await cuentaRepo.obtenerPorDocumentoPorEmitirId(documentoId);
      expect(cuenta, isNotNull);
      expect(cuenta!.clienteId, documentoAntes!.clienteId);
      expect(cuenta.tipoDocumento, documentoAntes.tipoDocumento);
      expect(cuenta.metodo, documentoAntes.metodo);
      expect(cuenta.requiereComplemento, documentoAntes.requiereComplemento);
      expect(cuenta.folioDocumento, 'FOL-001');
      expect(cuenta.fechaEmisionReal, DateTime(2026, 1, 5));
      expect(cuenta.importeEmitido, 500000);
      expect(cuenta.saldoOriginal, 500000);
      expect(cuenta.saldoPendiente, 500000);
      expect(cuenta.moneda, 'MXN');
      expect(cuenta.estatus, 'pendiente');
      expect(cuenta.fechaVencimiento, isNotNull);
    });

    test('CFDI conserva serie fiscal, folio fiscal y UUID en el snapshot', () async {
      final documentoId = await crearDocumentoEmitido(nombreCliente: 'Sportium', tipoDocumento: TipoDocumentoCobro.cfdi);
      await cambiarEstatus.ejecutar(documentoPorEmitirId: documentoId, nuevo: EstatusDocumentoPorEmitir.procesadoAceptado);

      final cuenta = await cuentaRepo.obtenerPorDocumentoPorEmitirId(documentoId);
      expect(cuenta!.serieFiscal, 'A');
      expect(cuenta.folioFiscal, '001');
      expect(cuenta.uuid, '11111111-1111-1111-1111-111111111111');
    });

    test('Mirabilia: documento sin regla de Pago genera una Cuenta por cobrar sin fecha de vencimiento', () async {
      final documentoId = await crearDocumentoEmitido(nombreCliente: 'Mirabilia', reglaPago: false);
      await cambiarEstatus.ejecutar(documentoPorEmitirId: documentoId, nuevo: EstatusDocumentoPorEmitir.procesadoAceptado);

      final cuenta = await cuentaRepo.obtenerPorDocumentoPorEmitirId(documentoId);
      expect(cuenta, isNotNull);
      expect(cuenta!.fechaVencimiento, isNull);
      expect(estaVencida(cuenta, DateTime(2030, 1, 1)), isFalse, reason: 'sin fecha de vencimiento nunca puede estar vencida');
    });

    test('un DocumentoPorEmitir nunca puede tener más de una Cuenta por cobrar (UNIQUE en base de datos)', () async {
      final documentoId = await crearDocumentoEmitido(nombreCliente: 'Miluyole');
      await cambiarEstatus.ejecutar(documentoPorEmitirId: documentoId, nuevo: EstatusDocumentoPorEmitir.procesadoAceptado);

      final documento = await documentoRepo.obtenerPorId(documentoId);
      expect(
        () => cuentaRepo.crear(
          documentoPorEmitirId: documentoId,
          clienteId: documento!.clienteId,
          tipoDocumento: documento.tipoDocumento,
          metodo: documento.metodo,
          requiereComplemento: documento.requiereComplemento,
          fechaEmisionReal: documento.fechaEmisionReal!,
          importeEmitido: documento.importeEmitido!,
        ),
        throwsA(anything),
      );
    });

    test('una Cuenta por cobrar nunca puede existir sin su DocumentoPorEmitir (FK)', () async {
      expect(
        () => cuentaRepo.crear(
          documentoPorEmitirId: 'documento-inexistente',
          clienteId: 'cliente-inexistente',
          tipoDocumento: TipoDocumentoCobro.reciboDePago.name,
          metodo: MetodoPagoCobro.noAplica.name,
          requiereComplemento: false,
          fechaEmisionReal: DateTime(2026, 1, 5),
          importeEmitido: 100000,
        ),
        throwsA(anything),
      );
    });

    test('Procesado/Aceptado es terminal: la máquina de estados impide una segunda transición y una segunda Cuenta por cobrar',
        () async {
      final documentoId = await crearDocumentoEmitido(nombreCliente: 'Toluca 32');
      await cambiarEstatus.ejecutar(documentoPorEmitirId: documentoId, nuevo: EstatusDocumentoPorEmitir.procesadoAceptado);

      final segundoIntento =
          await cambiarEstatus.ejecutar(documentoPorEmitirId: documentoId, nuevo: EstatusDocumentoPorEmitir.procesadoAceptado);
      expect(segundoIntento, isA<CambiarEstatusDocumentoPorEmitirTransicionInvalida>());

      final cuentas = await cuentaRepo.listar(documentoPorEmitirId: documentoId);
      expect(cuentas, hasLength(1));
    });
  });

  group('Historial administrativo append-only', () {
    test('la creación automática registra un evento "creada"', () async {
      final documentoId = await crearDocumentoEmitido(nombreCliente: 'Tikal');
      await cambiarEstatus.ejecutar(documentoPorEmitirId: documentoId, nuevo: EstatusDocumentoPorEmitir.procesadoAceptado);

      final cuenta = await cuentaRepo.obtenerPorDocumentoPorEmitirId(documentoId);
      final eventos = await cuentaRepo.listarEventos(cuenta!.id);
      expect(eventos, hasLength(1));
      expect(eventos.single.tipoEvento, 'creada');
      expect(eventos.single.estadoAnterior, isNull);
      expect(eventos.single.estadoNuevo, 'pendiente');
    });
  });

  group('Definir/corregir fecha de vencimiento (Resolución E de Marlon)', () {
    test('completa la fecha de vencimiento de una cuenta que nació sin ella (caso Mirabilia)', () async {
      final documentoId = await crearDocumentoEmitido(nombreCliente: 'Mirabilia', reglaPago: false);
      await cambiarEstatus.ejecutar(documentoPorEmitirId: documentoId, nuevo: EstatusDocumentoPorEmitir.procesadoAceptado);
      final cuenta = await cuentaRepo.obtenerPorDocumentoPorEmitirId(documentoId);

      final resultado = await actualizarVencimiento.ejecutar(
        cuentaPorCobrarId: cuenta!.id,
        fechaVencimiento: DateTime(2026, 2, 15),
        motivo: 'Fecha acordada telefónicamente con el cliente',
      );

      expect(resultado, isA<ActualizarFechaVencimientoCuentaPorCobrarExitoso>());
      final actualizada = (resultado as ActualizarFechaVencimientoCuentaPorCobrarExitoso).cuenta;
      expect(actualizada.fechaVencimiento, DateTime(2026, 2, 15));

      final eventos = await cuentaRepo.listarEventos(cuenta.id);
      expect(eventos, hasLength(2));
      expect(eventos.last.tipoEvento, 'fechaVencimientoDefinida');
      expect(eventos.last.observacion, 'Fecha acordada telefónicamente con el cliente');
    });

    test('también corrige una fecha ya definida, sin restricción de estatus', () async {
      final documentoId = await crearDocumentoEmitido(nombreCliente: 'Sportium');
      await cambiarEstatus.ejecutar(documentoPorEmitirId: documentoId, nuevo: EstatusDocumentoPorEmitir.procesadoAceptado);
      final cuenta = await cuentaRepo.obtenerPorDocumentoPorEmitirId(documentoId);
      expect(cuenta!.fechaVencimiento, isNotNull);

      final resultado = await actualizarVencimiento.ejecutar(
        cuentaPorCobrarId: cuenta.id,
        fechaVencimiento: DateTime(2026, 3, 1),
      );
      expect(resultado, isA<ActualizarFechaVencimientoCuentaPorCobrarExitoso>());
      expect((resultado as ActualizarFechaVencimientoCuentaPorCobrarExitoso).cuenta.fechaVencimiento, DateTime(2026, 3, 1));
    });

    test('una Cuenta por cobrar inexistente retorna NoExiste', () async {
      final resultado = await actualizarVencimiento.ejecutar(
        cuentaPorCobrarId: 'no-existe',
        fechaVencimiento: DateTime(2026, 3, 1),
      );
      expect(resultado, isA<ActualizarFechaVencimientoCuentaPorCobrarNoExiste>());
    });
  });

  group('Antigüedad derivada (nunca almacenada — Resolución D de Marlon)', () {
    CuentaPorCobrarData cuenta({DateTime? fechaVencimiento, String estatus = 'pendiente'}) {
      return CuentaPorCobrarData(
        id: 'cxc-1',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        cicloVidaRegistro: 'activo',
        documentoPorEmitirId: 'doc-1',
        clienteId: 'cliente-1',
        tipoDocumento: TipoDocumentoCobro.reciboDePago.name,
        metodo: MetodoPagoCobro.noAplica.name,
        requiereComplemento: false,
        fechaEmisionReal: DateTime(2026, 1, 1),
        importeEmitido: 100000,
        saldoOriginal: 100000,
        saldoPendiente: 100000,
        moneda: 'MXN',
        estatus: estatus,
        fechaVencimiento: fechaVencimiento,
      );
    }

    test('sin fechaVencimiento nunca está vencida ni tiene antigüedad', () {
      final c = cuenta(fechaVencimiento: null);
      expect(estaVencida(c, DateTime(2030, 1, 1)), isFalse);
      expect(calcularRangoAntiguedad(c, DateTime(2030, 1, 1)), RangoAntiguedadCuentaPorCobrar.alCorriente);
    });

    test('una cuenta Pagada nunca está vencida aunque la fecha ya haya pasado', () {
      final c = cuenta(fechaVencimiento: DateTime(2026, 1, 1), estatus: 'pagada');
      expect(estaVencida(c, DateTime(2026, 6, 1)), isFalse);
    });

    test('con vencimiento futuro está al corriente', () {
      final c = cuenta(fechaVencimiento: DateTime(2026, 6, 1));
      expect(estaVencida(c, DateTime(2026, 1, 1)), isFalse);
      expect(calcularRangoAntiguedad(c, DateTime(2026, 1, 1)), RangoAntiguedadCuentaPorCobrar.alCorriente);
    });

    test('rangos de antigüedad: 0-30, 31-60, 61-90 y 90+', () {
      final c = cuenta(fechaVencimiento: DateTime(2026, 1, 1));
      expect(calcularRangoAntiguedad(c, DateTime(2026, 1, 15)), RangoAntiguedadCuentaPorCobrar.dias0a30);
      expect(calcularRangoAntiguedad(c, DateTime(2026, 2, 15)), RangoAntiguedadCuentaPorCobrar.dias31a60);
      expect(calcularRangoAntiguedad(c, DateTime(2026, 3, 15)), RangoAntiguedadCuentaPorCobrar.dias61a90);
      expect(calcularRangoAntiguedad(c, DateTime(2026, 6, 1)), RangoAntiguedadCuentaPorCobrar.dias90Mas);
    });
  });

  group('Consultas previstas (§13 del plan — filtros por Cliente/Servicio/Entidad fiscal/Documento/Estatus)', () {
    test('listar filtra por clienteId, tipoDocumento, estatus y documentoPorEmitirId', () async {
      final documentoId = await crearDocumentoEmitido(nombreCliente: 'Morgan');
      await cambiarEstatus.ejecutar(documentoPorEmitirId: documentoId, nuevo: EstatusDocumentoPorEmitir.procesadoAceptado);
      final documento = await documentoRepo.obtenerPorId(documentoId);

      expect(await cuentaRepo.listar(clienteId: documento!.clienteId), hasLength(1));
      expect(await cuentaRepo.listar(clienteId: 'otro-cliente'), isEmpty);
      expect(await cuentaRepo.listar(tipoDocumento: TipoDocumentoCobro.reciboDePago.name), hasLength(1));
      expect(await cuentaRepo.listar(estatus: 'pendiente'), hasLength(1));
      expect(await cuentaRepo.listar(estatus: 'pagada'), isEmpty);
      expect(await cuentaRepo.listar(documentoPorEmitirId: documentoId), hasLength(1));
    });

    test('listar filtra por servicioId vía join con DocumentoPorEmitirServicio', () async {
      final documentoId = await crearDocumentoEmitido(nombreCliente: 'Miluyole');
      await cambiarEstatus.ejecutar(documentoPorEmitirId: documentoId, nuevo: EstatusDocumentoPorEmitir.procesadoAceptado);
      final detalle = await documentoRepo.obtenerDetalle(documentoId);

      final cuentas = await cuentaRepo.listar(servicioId: detalle!.servicioIds.single);
      expect(cuentas, hasLength(1));
      expect(await cuentaRepo.listar(servicioId: 'servicio-inexistente'), isEmpty);
    });

    test('listar filtra por entidadFiscalId vía join con DocumentoPorEmitir', () async {
      final documentoId = await crearDocumentoEmitido(nombreCliente: 'Sportium', tipoDocumento: TipoDocumentoCobro.cfdi);
      await cambiarEstatus.ejecutar(documentoPorEmitirId: documentoId, nuevo: EstatusDocumentoPorEmitir.procesadoAceptado);
      final documento = await documentoRepo.obtenerPorId(documentoId);

      final cuentas = await cuentaRepo.listar(entidadFiscalId: documento!.entidadFiscalId);
      expect(cuentas, hasLength(1));
      expect(await cuentaRepo.listar(entidadFiscalId: 'entidad-inexistente'), isEmpty);
    });
  });
}
