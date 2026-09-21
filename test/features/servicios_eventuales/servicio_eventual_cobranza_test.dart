// Servicios Eventuales — Rebanada 2: la cadena completa de cobranza.
//
//   ServicioEventual → CxC → Pago → AplicacionPago → Ingreso
//   y, con factura PPD, → ComplementoPago
//
// Los ocho casos de §29, contra BD real (Drift `NativeDatabase.memory()`,
// sin mocks). El invariante de fondo: **todo eventual vendido tiene
// exactamente una Cuenta por cobrar**, y ninguna ruta inventa un
// `DocumentoPorEmitir` para sostenerla.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/features/organizacion/domain/shared/direccion_input.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/repositories/complemento_pago_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_por_cobrar_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/pago_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/tables/complemento_pago_table.dart';
import 'package:riseg_one/features/finanzas/data/tables/cuenta_por_cobrar_table.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show EstatusAplicacionPago, FormaPago;
import 'package:riseg_one/features/finanzas/domain/contraparte_cobro.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cancelar_complemento_pago_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/obtener_complementos_pendientes_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_complemento_pago_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_pago_aplicado_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/resolver_nombres_contraparte_usecase.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/entidad_fiscal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart'
    show MetodoPagoCobro;
import 'package:riseg_one/features/servicios_eventuales/data/repositories/servicio_eventual_documento_fiscal_repository_impl.dart';
import 'package:riseg_one/features/servicios_eventuales/data/repositories/servicio_eventual_repository_impl.dart';
import 'package:riseg_one/features/servicios_eventuales/data/tables/servicio_eventual_documento_fiscal_table.dart';
import 'package:riseg_one/features/servicios_eventuales/data/tables/servicio_eventual_table.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/repositories/servicio_eventual_repository.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/cancelar_documento_fiscal_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/corregir_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/crear_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/registrar_cobro_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/registrar_documento_fiscal_eventual_usecase.dart';

void main() {
  late AppDatabase db;
  late CuentaPorCobrarRepositoryImpl cuentaRepo;
  late PagoRepositoryImpl pagoRepo;
  late ComplementoPagoRepositoryImpl complementoRepo;
  late ServicioEventualRepositoryImpl repo;
  late ServicioEventualDocumentoFiscalRepositoryImpl documentoRepo;
  late EntidadFiscalRepositoryImpl entidadFiscalRepo;

  late CrearServicioEventualUseCase crear;
  late CorregirServicioEventualUseCase corregir;
  late RegistrarCobroServicioEventualUseCase cobrar;
  late RegistrarDocumentoFiscalEventualUseCase facturar;
  late CancelarDocumentoFiscalEventualUseCase cancelarFactura;
  late RegistrarComplementoPagoUseCase registrarComplemento;
  late CancelarComplementoPagoUseCase cancelarComplemento;
  late ObtenerComplementosPendientesUseCase complementosPendientes;
  late ResolverNombresContraparteUseCase resolverNombres;

  late CuentaFinancieraData cuentaBanco;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final codigoSecuencia = CodigoSecuenciaService(db);
    final egresoRepo = EgresoRepositoryImpl(db);
    final deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
    cuentaRepo = CuentaPorCobrarRepositoryImpl(db);
    pagoRepo = PagoRepositoryImpl(db);
    complementoRepo = ComplementoPagoRepositoryImpl(db);
    final clienteRepo = ClienteRepositoryImpl(db);
    entidadFiscalRepo = EntidadFiscalRepositoryImpl(db);

    repo = ServicioEventualRepositoryImpl(db, egresoRepo, deudaRepo, codigoSecuencia, cuentaRepo, pagoRepo);
    documentoRepo = ServicioEventualDocumentoFiscalRepositoryImpl(db, cuentaRepo, repo);

    crear = CrearServicioEventualUseCase(repo, clienteRepo, EntidadFiscalRepositoryImpl(db));
    corregir = CorregirServicioEventualUseCase(repo, cuentaRepo, pagoRepo);
    cobrar = RegistrarCobroServicioEventualUseCase(
      repo,
      RegistrarPagoAplicadoUseCase(pagoRepo, cuentaRepo, GenerarCodigoUseCase(codigoSecuencia)),
    );
    facturar = RegistrarDocumentoFiscalEventualUseCase(documentoRepo, repo, cuentaRepo, entidadFiscalRepo);
    cancelarFactura = CancelarDocumentoFiscalEventualUseCase(documentoRepo);
    registrarComplemento = RegistrarComplementoPagoUseCase(complementoRepo, pagoRepo);
    cancelarComplemento = CancelarComplementoPagoUseCase(complementoRepo);
    complementosPendientes = ObtenerComplementosPendientesUseCase(pagoRepo, cuentaRepo, complementoRepo);
    resolverNombres = ResolverNombresContraparteUseCase(clienteRepo, repo);

    cuentaBanco = await db.into(db.cuentaFinanciera).insertReturning(
          CuentaFinancieraCompanion.insert(
            codigo: 'CF-BBVA',
            nombre: 'BBVA',
            tipo: 'cuenta',
            saldoInicial: 0,
            fechaSaldoInicial: DateTime(2026, 1, 1),
          ),
        );
  });

  tearDown(() => db.close());

  Future<ClienteData> crearCliente({String nombre = 'Sportium'}) {
    return db.into(db.cliente).insertReturning(
          ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: nombre),
        );
  }

  Future<CrearServicioEventualExitoso> vender({
    int importe = 500000,
    bool conFactura = false,
    MetodoPagoCobro metodo = MetodoPagoCobro.noAplica,
    String? clienteId,
    String? entidadFiscalId,
    CobroInmediatoServicioEventual? cobroInmediato,
  }) async {
    final resultado = await crear.ejecutar(
      nombre: 'Evento de prueba',
      fechaHoraInicio: DateTime(2026, 5, 1, 18),
      fechaHoraFin: DateTime(2026, 5, 2, 2),
      importeAcordado: importe,
      tipoSolicitante:
          clienteId == null ? TipoSolicitanteServicioEventual.eventual : TipoSolicitanteServicioEventual.cliente,
      clienteId: clienteId,
      solicitanteNombre: clienteId == null ? 'Promotora Norte' : null,
      requiereFactura: conFactura,
      // Receptor fiscal (v90): por Entidad fiscal cuando hay Cliente, y
      // por snapshot capturado cuando el solicitante es ocasional.
      entidadFiscalId: conFactura ? entidadFiscalId : null,
      solicitanteRazonSocial:
          conFactura && clienteId == null ? 'Promotora Norte S.A. de C.V.' : null,
      solicitanteRfc: conFactura && clienteId == null ? 'PNO010101AB1' : null,
      solicitanteCodigoPostalFiscal: conFactura && clienteId == null ? '64000' : null,
      metodoCobro: metodo,
      fechaVencimiento: DateTime(2026, 5, 15),
      cobroInmediato: cobroInmediato,
    );
    return resultado as CrearServicioEventualExitoso;
  }

  group('Caso A — solicitante eventual, sin factura, cobro inmediato', () {
    test('la cadena completa queda registrada y la cuenta queda pagada', () async {
      final venta = await vender(
        importe: 500000,
        cobroInmediato: CobroInmediatoServicioEventual(
          monto: 500000,
          fechaPago: DateTime(2026, 5, 1),
          formaPago: FormaPago.transferencia.name,
          cuentaFinancieraId: cuentaBanco.id,
        ),
      );

      // Eventual + CxC + Pago + Aplicación + Ingreso.
      expect(await db.select(db.servicioEventual).get(), hasLength(1));
      final cuentas = await db.select(db.cuentaPorCobrar).get();
      expect(cuentas, hasLength(1));
      expect(cuentas.single.estatus, EstatusCuentaPorCobrar.pagada.name);
      expect(cuentas.single.saldoPendiente, 0);
      expect(cuentas.single.metodo, MetodoPagoCobro.noAplica.name);

      final pagos = await db.select(db.pago).get();
      expect(pagos, hasLength(1));
      expect(pagos.single.montoTotal, 500000);
      expect(venta.pago!.id, pagos.single.id);

      expect(await db.select(db.aplicacionPago).get(), hasLength(1));

      // El Ingreso lo genera el repositorio de Pagos; este dominio
      // nunca lo crea a mano.
      final ingresos = await db.select(db.ingreso).get();
      expect(ingresos, hasLength(1));
      expect(ingresos.single.monto, 500000);
      expect(ingresos.single.cuentaFinancieraId, cuentaBanco.id);

      // Y cero documentos por emitir: la cobranza eventual no pasa por
      // la agenda comercial.
      expect(await db.select(db.documentoPorEmitir).get(), isEmpty);
    });

    test('la contraparte es el eventual, no un Cliente inventado', () async {
      final venta = await vender(
        cobroInmediato: CobroInmediatoServicioEventual(
          monto: 500000,
          fechaPago: DateTime(2026, 5, 1),
          formaPago: FormaPago.transferencia.name,
          cuentaFinancieraId: cuentaBanco.id,
        ),
      );

      expect(contraparteDeCuenta(venta.cuenta), ContraparteCobro.servicioEventual(venta.servicioEventual.id));
      expect(contraparteDePago(venta.pago!), ContraparteCobro.servicioEventual(venta.servicioEventual.id));
      expect(venta.cuenta.clienteId, isNull);
      expect(venta.pago!.clienteId, isNull);
      expect(await db.select(db.cliente).get(), isEmpty);

      // Y su nombre se resuelve: nunca un UUID.
      final nombres = await resolverNombres.paraCuentas([venta.cuenta]);
      expect(nombres.de(contraparteDeCuenta(venta.cuenta)), 'Promotora Norte');
    });

    test('un cobro que falla no deja eventual ni cuenta a medias', () async {
      // Monto mayor que la venta: el caso de uso corta ANTES de abrir
      // la transacción, así que no se crea nada.
      final resultado = await crear.ejecutar(
        nombre: 'Evento de prueba',
        fechaHoraInicio: DateTime(2026, 5, 1, 18),
        fechaHoraFin: DateTime(2026, 5, 2, 2),
        importeAcordado: 500000,
        tipoSolicitante: TipoSolicitanteServicioEventual.eventual,
        solicitanteNombre: 'Promotora Norte',
        cobroInmediato: CobroInmediatoServicioEventual(
          monto: 900000,
          fechaPago: DateTime(2026, 5, 1),
          formaPago: FormaPago.transferencia.name,
          cuentaFinancieraId: cuentaBanco.id,
        ),
      );
      expect(resultado, isA<CrearServicioEventualCobroInvalido>());
      expect(await db.select(db.servicioEventual).get(), isEmpty);
      expect(await db.select(db.cuentaPorCobrar).get(), isEmpty);
      expect(await db.select(db.pago).get(), isEmpty);
    });
  });

  group('Caso B — sin factura, pendiente, cobro parcial', () {
    test('la cuenta queda abierta y el pago parcial la deja en parcial', () async {
      final venta = await vender(importe: 900000);
      expect(venta.pago, isNull);
      expect(venta.cuenta.saldoPendiente, 900000);
      expect(venta.cuenta.estatus, EstatusCuentaPorCobrar.pendiente.name);

      final cobro = await cobrar.ejecutar(
        servicioEventualId: venta.servicioEventual.id,
        monto: 400000,
        fechaPago: DateTime(2026, 5, 10),
        formaPago: FormaPago.transferencia.name,
        cuentaFinancieraId: cuentaBanco.id,
      );
      expect(cobro, isA<RegistrarCobroServicioEventualExitoso>());

      final cuenta = (await cuentaRepo.obtenerPorId(venta.cuenta.id))!;
      expect(cuenta.saldoPendiente, 500000);
      expect(cuenta.estatus, EstatusCuentaPorCobrar.parcial.name);
      expect(await db.select(db.ingreso).get(), hasLength(1));
    });

    test('cobrar de más se rechaza con el saldo real', () async {
      final venta = await vender(importe: 900000);
      final resultado = await cobrar.ejecutar(
        servicioEventualId: venta.servicioEventual.id,
        monto: 1000000,
        fechaPago: DateTime(2026, 5, 10),
        formaPago: FormaPago.transferencia.name,
      );
      expect(resultado, isA<RegistrarCobroServicioEventualRechazado>());
      expect(
        (resultado as RegistrarCobroServicioEventualRechazado).motivo,
        isA<RegistrarPagoAplicadoSobrepago>(),
      );
      expect(await db.select(db.pago).get(), isEmpty);
    });
  });

  group('Caso C — Cliente existente, factura PPD, complemento con sustituto', () {
    late ClienteData cliente;
    late EntidadFiscalData entidad;

    setUp(() async {
      cliente = await crearCliente();
      entidad = await entidadFiscalRepo.crear(
        EntidadFiscalCompanion.insert(
          codigo: 'EF-000001',
          clienteId: cliente.id,
          razonSocial: 'Sportium SA de CV',
          rfc: 'SPO123456AB1',
        ),
      );
      // Sin domicilio no hay CP que congelar en el CFDI, y vender con
      // factura se bloquea — así que el fixture lo registra.
      await entidadFiscalRepo.guardarDomicilioFiscal(
        entidad.id,
        const DireccionInput(
          calle: 'Av. Constitución',
          numeroExterior: '100',
          colonia: 'Centro',
          municipioAlcaldia: 'Monterrey',
          estado: 'Nuevo León',
          codigoPostal: '64000',
        ),
      );
    });

    test('la cadena completa hasta el complemento sustituto', () async {
      final venta = await vender(
        importe: 1200000,
        conFactura: true,
        metodo: MetodoPagoCobro.ppd,
        clienteId: cliente.id,
        entidadFiscalId: entidad.id,
      );
      expect(venta.cuenta.metodo, MetodoPagoCobro.ppd.name);
      expect(venta.cuenta.requiereComplemento, isTrue);
      expect(contraparteDeCuenta(venta.cuenta), ContraparteCobro.cliente(cliente.id));

      // 1. Se registra el CFDI emitido por fuera y la CxC lo adopta.
      final factura = await facturar.ejecutar(
        servicioEventualId: venta.servicioEventual.id,
        folio: 'A-1234',
        uuid: '123e4567-e89b-12d3-a456-426614174000',
        fechaEmision: DateTime(2026, 5, 4),
        metodo: MetodoPagoCobro.ppd,
        entidadFiscalId: entidad.id,
      );
      expect(factura, isA<RegistrarDocumentoFiscalEventualExitoso>());
      final documento = (factura as RegistrarDocumentoFiscalEventualExitoso).documento;

      // El snapshot fiscal quedó congelado.
      expect(documento.snapshotRazonSocial, 'Sportium SA de CV');
      expect(documento.snapshotRfc, 'SPO123456AB1');
      expect(documento.importe, 1200000);

      final cuentaConFactura = (await cuentaRepo.obtenerPorId(venta.cuenta.id))!;
      expect(cuentaConFactura.folioDocumento, 'A-1234');
      expect(cuentaConFactura.uuid, '123e4567-e89b-12d3-a456-426614174000');
      expect(cuentaConFactura.fechaEmisionReal, DateTime(2026, 5, 4));
      // Facturar no cobra.
      expect(cuentaConFactura.saldoPendiente, 1200000);

      // 2. Cobro posterior.
      final cobro = await cobrar.ejecutar(
        servicioEventualId: venta.servicioEventual.id,
        monto: 1200000,
        fechaPago: DateTime(2026, 5, 20),
        formaPago: FormaPago.transferencia.name,
        cuentaFinancieraId: cuentaBanco.id,
      );
      final pago = (cobro as RegistrarCobroServicioEventualExitoso).pago.pago;
      expect(await db.select(db.ingreso).get(), hasLength(1));

      // 3. El Complemento aparece como PENDIENTE, sin ConfigCobro ni
      //    DocumentoPorEmitir de por medio.
      final pendientes = await complementosPendientes.ejecutar();
      expect(pendientes.pendientes.map((p) => p.pago.id), contains(pago.id));

      // 4. Se registra A, se cancela A, se registra B.
      final a = await registrarComplemento.ejecutar(
        pagoId: pago.id,
        uuid: '223e4567-e89b-12d3-a456-426614174000',
        fechaTimbrado: DateTime(2026, 5, 21),
        montoTotal: 1200000,
      );
      expect(a, isA<RegistrarComplementoPagoExitoso>());
      expect((await complementosPendientes.ejecutar()).pendientes, isEmpty);

      await cancelarComplemento.ejecutar(
        complementoPagoId: (a as RegistrarComplementoPagoExitoso).complemento.id,
        motivo: 'Timbrado con datos incorrectos',
      );
      // Cancelado el único vigente, la obligación vuelve a estar viva.
      expect((await complementosPendientes.ejecutar()).pendientes.map((p) => p.pago.id), contains(pago.id));

      final b = await registrarComplemento.ejecutar(
        pagoId: pago.id,
        uuid: '323e4567-e89b-12d3-a456-426614174000',
        fechaTimbrado: DateTime(2026, 5, 22),
        montoTotal: 1200000,
      );
      expect(b, isA<RegistrarComplementoPagoExitoso>());

      // 5. Exactamente uno vigente, y el histórico completo conservado.
      final complementos = await complementoRepo.listarPorPagoId(pago.id);
      expect(complementos, hasLength(2));
      expect(
        complementos.where((c) => c.estatus == EstatusComplementoPago.registrado.name),
        hasLength(1),
      );

      // Un tercero, con B vigente, se rechaza.
      final c = await registrarComplemento.ejecutar(
        pagoId: pago.id,
        uuid: '423e4567-e89b-12d3-a456-426614174000',
        fechaTimbrado: DateTime(2026, 5, 23),
        montoTotal: 1200000,
      );
      expect(c, isNot(isA<RegistrarComplementoPagoExitoso>()));
    });

    test('el documento fiscal vigente es uno solo, con historial de cancelados', () async {
      final venta = await vender(
        importe: 1200000,
        conFactura: true,
        metodo: MetodoPagoCobro.ppd,
        clienteId: cliente.id,
        entidadFiscalId: entidad.id,
      );

      final primera = (await facturar.ejecutar(
        servicioEventualId: venta.servicioEventual.id,
        folio: 'A-1',
        fechaEmision: DateTime(2026, 5, 4),
        metodo: MetodoPagoCobro.ppd,
        entidadFiscalId: entidad.id,
      ) as RegistrarDocumentoFiscalEventualExitoso)
          .documento;

      // Con una vigente, la segunda se rechaza.
      expect(
        await facturar.ejecutar(
          servicioEventualId: venta.servicioEventual.id,
          folio: 'A-2',
          fechaEmision: DateTime(2026, 5, 5),
          metodo: MetodoPagoCobro.ppd,
          entidadFiscalId: entidad.id,
        ),
        isA<RegistrarDocumentoFiscalEventualYaTieneVigente>(),
      );

      await cancelarFactura.ejecutar(documentoId: primera.id, motivo: 'Datos equivocados');

      // Cancelar NO toca la deuda ni el acuerdo comercial; sólo deja de
      // citar un folio muerto.
      final cuentaTrasCancelar = (await cuentaRepo.obtenerPorId(venta.cuenta.id))!;
      expect(cuentaTrasCancelar.folioDocumento, isNull);
      expect(cuentaTrasCancelar.metodo, MetodoPagoCobro.ppd.name);
      expect(cuentaTrasCancelar.requiereComplemento, isTrue);
      expect(cuentaTrasCancelar.saldoPendiente, 1200000);
      expect(cuentaTrasCancelar.estatus, EstatusCuentaPorCobrar.pendiente.name);

      // Y ahora sí se puede registrar el sustituto.
      final segunda = await facturar.ejecutar(
        servicioEventualId: venta.servicioEventual.id,
        folio: 'A-2',
        fechaEmision: DateTime(2026, 5, 5),
        metodo: MetodoPagoCobro.ppd,
        entidadFiscalId: entidad.id,
      );
      expect(segunda, isA<RegistrarDocumentoFiscalEventualExitoso>());

      final documentos = await documentoRepo.listarPorEventual(venta.servicioEventual.id);
      expect(documentos, hasLength(2), reason: 'el cancelado se conserva como historia fiscal');
      expect(
        documentos.where((d) => d.estatus == EstatusDocumentoFiscalEventual.registrado.name),
        hasLength(1),
      );
    });

    test('una entidad fiscal de otro Cliente se rechaza al VENDER', () async {
      final otroCliente = await db.into(db.cliente).insertReturning(
            ClienteCompanion.insert(codigo: 'CLI-000002', nombreComercial: 'Otro'),
          );
      final ajena = await entidadFiscalRepo.crear(
        EntidadFiscalCompanion.insert(
          codigo: 'EF-000002',
          clienteId: otroCliente.id,
          razonSocial: 'Otro SA',
          rfc: 'OTR123456AB1',
        ),
      );

      // schemaVersion 90: el receptor fiscal se decide en el alta, así
      // que ahí es donde se cierra la puerta.
      expect(
        await crear.ejecutar(
          nombre: 'Evento de prueba',
          fechaHoraInicio: DateTime(2026, 5, 1, 18),
          fechaHoraFin: DateTime(2026, 5, 2, 2),
          importeAcordado: 500000,
          tipoSolicitante: TipoSolicitanteServicioEventual.cliente,
          clienteId: cliente.id,
          requiereFactura: true,
          metodoCobro: MetodoPagoCobro.pue,
          entidadFiscalId: ajena.id,
        ),
        isA<CrearServicioEventualEntidadFiscalInvalida>(),
      );
      expect(await db.select(db.servicioEventual).get(), isEmpty,
          reason: 'un receptor invalido no deja media venta escrita');
    });

    test('al facturar ya no se puede cambiar de receptor', () async {
      final otroCliente = await db.into(db.cliente).insertReturning(
            ClienteCompanion.insert(codigo: 'CLI-000002', nombreComercial: 'Otro'),
          );
      final ajena = await entidadFiscalRepo.crear(
        EntidadFiscalCompanion.insert(
          codigo: 'EF-000002',
          clienteId: otroCliente.id,
          razonSocial: 'Otro SA',
          rfc: 'OTR123456AB1',
        ),
      );
      final venta = await vender(
        conFactura: true,
        metodo: MetodoPagoCobro.pue,
        clienteId: cliente.id,
        entidadFiscalId: entidad.id,
      );

      // Se manda una Entidad ajena a propósito: el caso de uso la
      // IGNORA y congela la del eventual. Facturarle a un tercero deja
      // de ser posible incluso pidiéndolo.
      final resultado = await facturar.ejecutar(
        servicioEventualId: venta.servicioEventual.id,
        folio: 'A-9',
        fechaEmision: DateTime(2026, 5, 4),
        metodo: MetodoPagoCobro.pue,
        entidadFiscalId: ajena.id,
      );
      final documento = (resultado as RegistrarDocumentoFiscalEventualExitoso).documento;
      expect(documento.entidadFiscalId, entidad.id);
      expect(documento.snapshotRazonSocial, 'Sportium SA de CV');
      expect(documento.snapshotRfc, 'SPO123456AB1');
      expect(documento.snapshotCodigoPostalFiscal, '64000',
          reason: 'el CP viaja al snapshot desde el domicilio fiscal de la Entidad');
    });

    test('un UUID mal formado se rechaza sin escribir nada', () async {
      final venta = await vender(
        conFactura: true,
        metodo: MetodoPagoCobro.pue,
        clienteId: cliente.id,
        entidadFiscalId: entidad.id,
      );
      expect(
        await facturar.ejecutar(
          servicioEventualId: venta.servicioEventual.id,
          folio: 'A-9',
          uuid: 'no-es-un-uuid',
          fechaEmision: DateTime(2026, 5, 4),
          metodo: MetodoPagoCobro.pue,
          entidadFiscalId: entidad.id,
        ),
        isA<RegistrarDocumentoFiscalEventualUuidInvalido>(),
      );
      expect(await db.select(db.servicioEventualDocumentoFiscal).get(), isEmpty);
    });

    test('el UUID puede llegar después, por corrección', () async {
      final venta = await vender(
        conFactura: true,
        metodo: MetodoPagoCobro.pue,
        clienteId: cliente.id,
        entidadFiscalId: entidad.id,
      );
      final documento = (await facturar.ejecutar(
        servicioEventualId: venta.servicioEventual.id,
        folio: 'A-1',
        fechaEmision: DateTime(2026, 5, 4),
        metodo: MetodoPagoCobro.pue,
        entidadFiscalId: entidad.id,
      ) as RegistrarDocumentoFiscalEventualExitoso)
          .documento;
      expect(documento.uuid, isNull, reason: 'el folio es obligatorio, el UUID no');

      await documentoRepo.corregir(
        documentoId: documento.id,
        uuid: '523e4567-e89b-12d3-a456-426614174000',
        motivo: 'Llegó el folio fiscal',
      );
      expect((await cuentaRepo.obtenerPorId(venta.cuenta.id))!.uuid, '523e4567-e89b-12d3-a456-426614174000');
    });
  });

  group('Caso D — factura PUE', () {
    test('un Pago de CxC PUE jamás produce complemento pendiente', () async {
      final cliente = await crearCliente();
      final entidad = await entidadFiscalRepo.crear(
        EntidadFiscalCompanion.insert(
          codigo: 'EF-000001',
          clienteId: cliente.id,
          razonSocial: 'Sportium SA de CV',
          rfc: 'SPO123456AB1',
        ),
      );
      await entidadFiscalRepo.guardarDomicilioFiscal(
        entidad.id,
        const DireccionInput(
          calle: 'Av. Constitución',
          numeroExterior: '100',
          colonia: 'Centro',
          municipioAlcaldia: 'Monterrey',
          estado: 'Nuevo León',
          codigoPostal: '64000',
        ),
      );
      final venta = await vender(
        importe: 600000,
        conFactura: true,
        metodo: MetodoPagoCobro.pue,
        clienteId: cliente.id,
        entidadFiscalId: entidad.id,
      );
      expect(venta.cuenta.requiereComplemento, isFalse);

      await facturar.ejecutar(
        servicioEventualId: venta.servicioEventual.id,
        folio: 'A-500',
        fechaEmision: DateTime(2026, 5, 4),
        metodo: MetodoPagoCobro.pue,
        entidadFiscalId: entidad.id,
      );
      await cobrar.ejecutar(
        servicioEventualId: venta.servicioEventual.id,
        monto: 600000,
        fechaPago: DateTime(2026, 5, 20),
        formaPago: FormaPago.transferencia.name,
        cuentaFinancieraId: cuentaBanco.id,
      );

      expect((await complementosPendientes.ejecutar()).pendientes, isEmpty);
      expect((await cuentaRepo.obtenerPorId(venta.cuenta.id))!.requiereComplemento, isFalse);
    });
  });

  group('Caso E — sin factura', () {
    test('metodo noAplica y jamás complemento, ni siquiera tras cobrar', () async {
      final venta = await vender(importe: 300000);
      expect(venta.cuenta.metodo, MetodoPagoCobro.noAplica.name);
      expect(venta.cuenta.requiereComplemento, isFalse);

      await cobrar.ejecutar(
        servicioEventualId: venta.servicioEventual.id,
        monto: 300000,
        fechaPago: DateTime(2026, 5, 10),
        formaPago: FormaPago.efectivo.name,
        cuentaFinancieraId: cuentaBanco.id,
      );
      expect((await complementosPendientes.ejecutar()).pendientes, isEmpty);

      // Y no admite documento fiscal alguno.
      expect(
        await facturar.ejecutar(
          servicioEventualId: venta.servicioEventual.id,
          folio: 'A-1',
          fechaEmision: DateTime(2026, 5, 4),
          metodo: MetodoPagoCobro.pue,
          razonSocialManual: 'Quien sea',
          rfcManual: 'XAXX010101000',
        ),
        isA<RegistrarDocumentoFiscalEventualNoRequiereFactura>(),
      );
    });

    test('vender sin factura pero con método fiscal se rechaza, y al revés', () async {
      final conMetodo = await crear.ejecutar(
        nombre: 'Evento',
        fechaHoraInicio: DateTime(2026, 5, 1),
        fechaHoraFin: DateTime(2026, 5, 2),
        importeAcordado: 100000,
        tipoSolicitante: TipoSolicitanteServicioEventual.eventual,
        solicitanteNombre: 'X',
        metodoCobro: MetodoPagoCobro.pue,
      );
      expect(conMetodo, isA<CrearServicioEventualMetodoIncoherente>());

      final sinMetodo = await crear.ejecutar(
        nombre: 'Evento',
        fechaHoraInicio: DateTime(2026, 5, 1),
        fechaHoraFin: DateTime(2026, 5, 2),
        importeAcordado: 100000,
        tipoSolicitante: TipoSolicitanteServicioEventual.eventual,
        solicitanteNombre: 'X',
        requiereFactura: true,
      );
      expect(sinMetodo, isA<CrearServicioEventualMetodoIncoherente>());
      expect(await db.select(db.servicioEventual).get(), isEmpty);
    });
  });

  group('Caso F — corrección del importe', () {
    test('sin aplicaciones activas se corrige y la cuenta lo sigue', () async {
      final venta = await vender(importe: 500000);
      final resultado = await corregir.ejecutar(
        servicioEventualId: venta.servicioEventual.id,
        importeAcordado: 750000,
        motivo: 'Se renegoció el precio',
      );
      expect(resultado, isA<CorregirServicioEventualExitoso>());

      final cuenta = (await cuentaRepo.obtenerPorId(venta.cuenta.id))!;
      expect(cuenta.importeEmitido, 750000);
      expect(cuenta.saldoOriginal, 750000);
      expect(cuenta.saldoPendiente, 750000);
    });

    test('con un pago aplicado se rechaza y NO cancela nada', () async {
      final venta = await vender(
        importe: 500000,
        cobroInmediato: CobroInmediatoServicioEventual(
          monto: 500000,
          fechaPago: DateTime(2026, 5, 1),
          formaPago: FormaPago.transferencia.name,
          cuentaFinancieraId: cuentaBanco.id,
        ),
      );

      final resultado = await corregir.ejecutar(
        servicioEventualId: venta.servicioEventual.id,
        importeAcordado: 750000,
        motivo: 'Intento',
      );
      expect(resultado, isA<CorregirServicioEventualImporteBloqueadoPorPago>());

      // Ni el eventual ni la cobranza se movieron.
      expect((await repo.obtenerPorId(venta.servicioEventual.id))!.importeAcordado, 500000);
      expect((await cuentaRepo.obtenerPorId(venta.cuenta.id))!.saldoOriginal, 500000);
      final aplicaciones = await pagoRepo.listarAplicacionesPorCuenta(venta.cuenta.id);
      expect(aplicaciones.single.estatus, EstatusAplicacionPago.aplicada.name);
    });

    test('corregir el nombre sigue permitido aunque haya pago', () async {
      final venta = await vender(
        importe: 500000,
        cobroInmediato: CobroInmediatoServicioEventual(
          monto: 500000,
          fechaPago: DateTime(2026, 5, 1),
          formaPago: FormaPago.transferencia.name,
          cuentaFinancieraId: cuentaBanco.id,
        ),
      );
      expect(
        await corregir.ejecutar(
          servicioEventualId: venta.servicioEventual.id,
          nombre: 'Nombre corregido',
          motivo: 'Error de captura',
        ),
        isA<CorregirServicioEventualExitoso>(),
      );
    });
  });

  group('Caso G — contraparte por tipo + id', () {
    test('un Cliente y un Eventual con el mismo id NO son la misma contraparte', () async {
      // Se fuerza el id compartido a propósito: es exactamente el caso
      // que una comparación por id suelto confundiría.
      const idCompartido = 'id-compartido';
      await db.into(db.cliente).insert(
            ClienteCompanion.insert(
              id: const Value(idCompartido),
              codigo: 'CLI-000009',
              nombreComercial: 'Cliente homónimo',
            ),
          );

      expect(
        const ContraparteCobro.cliente(idCompartido),
        isNot(const ContraparteCobro.servicioEventual(idCompartido)),
      );

      final venta = await vender(importe: 100000);
      const delCliente = ContraparteCobro.cliente(idCompartido);
      expect(contraparteDeCuenta(venta.cuenta), isNot(delCliente));

      // Y sus nombres se resuelven cada uno con su fuente.
      final nombres = await resolverNombres.paraContrapartes([
        delCliente,
        contraparteDeCuenta(venta.cuenta),
      ]);
      expect(nombres.de(delCliente), 'Cliente homónimo');
      expect(nombres.de(contraparteDeCuenta(venta.cuenta)), 'Promotora Norte');
    });

    test('un Pago de un eventual no se aplica a la cuenta de otro eventual', () async {
      final a = await vender(importe: 300000);
      final b = await vender(importe: 300000);

      final pagoDeA = await pagoRepo.crearAplicado(
        folioPago: 'PAG-000099',
        servicioEventualId: a.servicioEventual.id,
        montoTotal: 100000,
        fechaPago: DateTime(2026, 5, 10),
        formaPago: FormaPago.transferencia.name,
        cuentaPorCobrarId: a.cuenta.id,
      );

      // La contraparte del Pago de A y la de la Cuenta de B difieren:
      // eso es lo que `AplicarPagoACuentaUseCase` compara.
      expect(contraparteDePago(pagoDeA.pago), isNot(contraparteDeCuenta(b.cuenta)));
    });
  });

  group('Caso H — la cobranza recurrente no cambió', () {
    test('una CxC de DocumentoPorEmitir se crea y se cobra igual que siempre', () async {
      final cliente = await crearCliente(nombre: 'Corporativo recurrente');
      final documento = await db.into(db.documentoPorEmitir).insertReturning(
            DocumentoPorEmitirCompanion.insert(
              codigo: 'DPE-000001',
              clienteId: cliente.id,
              tipoDocumento: 'cfdi',
              agrupacion: 'porServicio',
              metodo: MetodoPagoCobro.pue.name,
              periodoInicio: DateTime(2026, 1, 1),
              periodoFin: DateTime(2026, 1, 31),
              generationKey: 'key-1',
              importeBaseEsperado: 800000,
              importeFinalEsperado: 800000,
            ),
          );

      final cuenta = await cuentaRepo.crear(
        documentoPorEmitirId: documento.id,
        clienteId: cliente.id,
        tipoDocumento: 'cfdi',
        metodo: MetodoPagoCobro.pue.name,
        requiereComplemento: false,
        folioDocumento: 'F-100',
        fechaEmisionReal: DateTime(2026, 2, 1),
        importeEmitido: 800000,
        fechaVencimiento: DateTime(2026, 2, 28),
      );

      expect(cuenta.servicioEventualId, isNull);
      expect(contraparteDeCuenta(cuenta), ContraparteCobro.cliente(cliente.id));
      expect(origenDeCuenta(cuenta), OrigenCuentaPorCobrar.documentoPorEmitir);

      final pago = await pagoRepo.crearAplicado(
        folioPago: 'PAG-000001',
        clienteId: cliente.id,
        montoTotal: 800000,
        fechaPago: DateTime(2026, 2, 20),
        formaPago: FormaPago.transferencia.name,
        cuentaPorCobrarId: cuenta.id,
        cuentaFinancieraId: cuentaBanco.id,
      );

      final cuentaFinal = (await cuentaRepo.obtenerPorId(cuenta.id))!;
      expect(cuentaFinal.estatus, EstatusCuentaPorCobrar.pagada.name);
      expect(pago.pago.servicioEventualId, isNull);
      expect(await db.select(db.ingreso).get(), hasLength(1));
    });
  });

  test('el filtro por eventual devuelve sólo su cuenta', () async {
    final a = await vender(importe: 100000);
    await vender(importe: 200000);

    final suyas = await cuentaRepo.listar(servicioEventualId: a.servicioEventual.id);
    expect(suyas, hasLength(1));
    expect(suyas.single.id, a.cuenta.id);

    // Y el filtro por Servicio (que va por join contra
    // DocumentoPorEmitir) sigue excluyendo eventuales, a propósito.
    expect(await cuentaRepo.listar(servicioId: 'cualquiera'), isEmpty);
  });
}
