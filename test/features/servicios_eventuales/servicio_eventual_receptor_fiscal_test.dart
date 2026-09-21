// §1 — el receptor fiscal, separado del solicitante comercial.
//
// El hallazgo de la prueba manual fue concreto: vender con factura a un
// solicitante externo sólo pedía nombre, contacto, teléfono y correo.
// Nada de eso identifica a quién se le factura. "Juan del comité" no es
// "Administradora Bosques S.A. de C.V.", y el sistema lo estaba
// tratando como si sí.
//
// Lo que estas pruebas fijan:
//   * con factura, el receptor fiscal es obligatorio y se valida;
//   * sin factura, no se pide nada (un recibo no es un trámite);
//   * el Cliente NO recaptura: apunta a su Entidad fiscal;
//   * el CFDI congela razón social, RFC **y CP**.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_por_cobrar_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/pago_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/entidad_fiscal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart'
    show MetodoPagoCobro;
import 'package:riseg_one/features/organizacion/domain/shared/direccion_input.dart';
import 'package:riseg_one/features/servicios_eventuales/data/repositories/servicio_eventual_documento_fiscal_repository_impl.dart';
import 'package:riseg_one/features/servicios_eventuales/data/repositories/servicio_eventual_repository_impl.dart';
import 'package:riseg_one/features/servicios_eventuales/data/tables/servicio_eventual_table.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/receptor_fiscal_eventual.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/crear_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/registrar_documento_fiscal_eventual_usecase.dart';

void main() {
  late AppDatabase db;
  late ServicioEventualRepositoryImpl repo;
  late EntidadFiscalRepositoryImpl entidadFiscalRepo;
  late ServicioEventualDocumentoFiscalRepositoryImpl documentoRepo;
  late CrearServicioEventualUseCase crear;
  late RegistrarDocumentoFiscalEventualUseCase facturar;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    final codigoSecuencia = CodigoSecuenciaService(db);
    final egresoRepo = EgresoRepositoryImpl(db);
    final cuentaRepo = CuentaPorCobrarRepositoryImpl(db);
    repo = ServicioEventualRepositoryImpl(
      db,
      egresoRepo,
      DeudaRepositoryImpl(db, egresoRepo),
      codigoSecuencia,
      cuentaRepo,
      PagoRepositoryImpl(db),
    );
    entidadFiscalRepo = EntidadFiscalRepositoryImpl(db);
    documentoRepo = ServicioEventualDocumentoFiscalRepositoryImpl(db, cuentaRepo, repo);
    crear = CrearServicioEventualUseCase(repo, ClienteRepositoryImpl(db), entidadFiscalRepo);
    facturar = RegistrarDocumentoFiscalEventualUseCase(documentoRepo, repo, cuentaRepo, entidadFiscalRepo);
  });

  tearDown(() => db.close());

  Future<CrearServicioEventualResultado> venderExterno({
    bool conFactura = true,
    String? razonSocial = 'Administradora Bosques S.A. de C.V.',
    String? rfc = 'ABO010101AA1',
    String? cp = '06700',
  }) {
    return crear.ejecutar(
      nombre: 'Posada',
      fechaHoraInicio: DateTime(2026, 5, 1, 18),
      fechaHoraFin: DateTime(2026, 5, 2, 2),
      importeAcordado: 800000,
      tipoSolicitante: TipoSolicitanteServicioEventual.eventual,
      // El solicitante: quien pide, quien contesta el teléfono.
      solicitanteNombre: 'Juan del comité',
      solicitanteContacto: 'Juan',
      solicitanteTelefono: '8112345678',
      requiereFactura: conFactura,
      metodoCobro: conFactura ? MetodoPagoCobro.pue : MetodoPagoCobro.noAplica,
      // El receptor fiscal: a nombre de quién se emite.
      solicitanteRazonSocial: razonSocial,
      solicitanteRfc: rfc,
      solicitanteCodigoPostalFiscal: cp,
    );
  }

  group('Solicitante ocasional con factura', () {
    test('el solicitante y el receptor fiscal se guardan por separado', () async {
      final venta = await venderExterno() as CrearServicioEventualExitoso;
      final eventual = venta.servicioEventual;

      expect(eventual.solicitanteNombre, 'Juan del comité');
      expect(eventual.solicitanteRazonSocial, 'Administradora Bosques S.A. de C.V.');
      expect(
        eventual.solicitanteRazonSocial,
        isNot(eventual.solicitanteNombre),
        reason: 'el nombre del solicitante nunca es la razón social',
      );
      expect(eventual.solicitanteRfc, 'ABO010101AA1');
      expect(eventual.solicitanteCodigoPostalFiscal, '06700');
      // No se creó cartera por facturarle una vez a alguien.
      expect(await db.select(db.cliente).get(), isEmpty);
      expect(await db.select(db.entidadFiscal).get(), isEmpty);
    });

    test('sin razón social no se vende', () async {
      expect(
        await venderExterno(razonSocial: null),
        isA<CrearServicioEventualReceptorFiscalInvalido>().having(
          (r) => r.motivo,
          'motivo',
          ErrorReceptorFiscalEventual.razonSocialRequerida,
        ),
      );
      expect(await db.select(db.servicioEventual).get(), isEmpty);
    });

    test('sin RFC no se vende', () async {
      expect(
        await venderExterno(rfc: ''),
        isA<CrearServicioEventualReceptorFiscalInvalido>().having(
          (r) => r.motivo,
          'motivo',
          ErrorReceptorFiscalEventual.rfcRequerido,
        ),
      );
    });

    test('un RFC con formato imposible se rechaza', () async {
      expect(
        await venderExterno(rfc: 'ABC'),
        isA<CrearServicioEventualReceptorFiscalInvalido>().having(
          (r) => r.motivo,
          'motivo',
          ErrorReceptorFiscalEventual.rfcInvalido,
        ),
      );
    });

    test('el RFC se normaliza: minúsculas y espacios no cambian la identidad fiscal', () async {
      final venta = await venderExterno(rfc: ' abo010101aa1 ') as CrearServicioEventualExitoso;
      expect(venta.servicioEventual.solicitanteRfc, 'ABO010101AA1');
    });

    test('sin código postal fiscal no se vende', () async {
      expect(
        await venderExterno(cp: null),
        isA<CrearServicioEventualReceptorFiscalInvalido>().having(
          (r) => r.motivo,
          'motivo',
          ErrorReceptorFiscalEventual.codigoPostalRequerido,
        ),
      );
    });

    test('un CP que no son cinco dígitos se rechaza', () async {
      for (final malo in ['6700', '067001', 'CP700']) {
        expect(
          await venderExterno(cp: malo),
          isA<CrearServicioEventualReceptorFiscalInvalido>().having(
            (r) => r.motivo,
            'motivo',
            ErrorReceptorFiscalEventual.codigoPostalInvalido,
          ),
          reason: malo,
        );
      }
    });

    test('el CFDI congela los TRES datos, CP incluido', () async {
      final venta = await venderExterno() as CrearServicioEventualExitoso;
      final resultado = await facturar.ejecutar(
        servicioEventualId: venta.servicioEventual.id,
        folio: 'A-100',
        fechaEmision: DateTime(2026, 5, 3),
        metodo: MetodoPagoCobro.pue,
      );
      final documento = (resultado as RegistrarDocumentoFiscalEventualExitoso).documento;

      expect(documento.snapshotRazonSocial, 'Administradora Bosques S.A. de C.V.');
      expect(documento.snapshotRfc, 'ABO010101AA1');
      expect(documento.snapshotCodigoPostalFiscal, '06700');
      expect(documento.entidadFiscalId, isNull, reason: 'un ocasional no crea Entidad fiscal');
    });
  });

  group('Sin factura', () {
    test('no se piden datos fiscales, y no se inventan', () async {
      final venta = await venderExterno(
        conFactura: false,
        razonSocial: null,
        rfc: null,
        cp: null,
      ) as CrearServicioEventualExitoso;

      expect(venta.servicioEventual.requiereFactura, isFalse);
      expect(venta.servicioEventual.solicitanteRazonSocial, isNull);
      expect(venta.servicioEventual.solicitanteRfc, isNull);
      expect(venta.servicioEventual.solicitanteCodigoPostalFiscal, isNull);
      expect(venta.servicioEventual.solicitanteNombre, 'Juan del comité');
    });
  });

  group('Cliente existente con factura', () {
    late ClienteData cliente;

    Future<EntidadFiscalData> crearEntidad({required bool conDomicilio}) async {
      final entidad = await entidadFiscalRepo.crear(
        EntidadFiscalCompanion.insert(
          codigo: 'EF-000001',
          clienteId: cliente.id,
          razonSocial: 'Sportium SA de CV',
          rfc: 'SPO123456AB1',
        ),
      );
      if (conDomicilio) {
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
      }
      return entidad;
    }

    Future<CrearServicioEventualResultado> vender({String? entidadFiscalId}) {
      return crear.ejecutar(
        nombre: 'Evento corporativo',
        fechaHoraInicio: DateTime(2026, 5, 1),
        fechaHoraFin: DateTime(2026, 5, 2),
        importeAcordado: 1200000,
        tipoSolicitante: TipoSolicitanteServicioEventual.cliente,
        clienteId: cliente.id,
        requiereFactura: true,
        metodoCobro: MetodoPagoCobro.pue,
        entidadFiscalId: entidadFiscalId,
      );
    }

    setUp(() async {
      cliente = await db.into(db.cliente).insertReturning(
            ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Sportium'),
          );
    });

    test('se apunta a su Entidad fiscal y NO se recaptura nada', () async {
      final entidad = await crearEntidad(conDomicilio: true);
      final venta = await vender(entidadFiscalId: entidad.id) as CrearServicioEventualExitoso;

      expect(venta.servicioEventual.entidadFiscalId, entidad.id);
      expect(venta.servicioEventual.solicitanteRazonSocial, isNull);
      expect(venta.servicioEventual.solicitanteRfc, isNull);
      expect(venta.servicioEventual.solicitanteCodigoPostalFiscal, isNull,
          reason: 'el CP vive en el domicilio fiscal de la Entidad, no duplicado aquí');
    });

    test('sin elegir Entidad fiscal no se vende con factura', () async {
      await crearEntidad(conDomicilio: true);
      expect(await vender(), isA<CrearServicioEventualEntidadFiscalRequerida>());
      expect(await db.select(db.servicioEventual).get(), isEmpty);
    });

    test('una Entidad fiscal sin domicilio bloquea la venta, no la factura', () async {
      final entidad = await crearEntidad(conDomicilio: false);
      expect(
        await vender(entidadFiscalId: entidad.id),
        isA<CrearServicioEventualEntidadFiscalSinDomicilio>()
            .having((r) => r.razonSocial, 'razonSocial', 'Sportium SA de CV'),
        reason: 'sin domicilio no hay CP que llevar al CFDI; se avisa al vender, no al facturar',
      );
    });

    test('el CFDI toma razón social, RFC y CP de la Entidad elegida al vender', () async {
      final entidad = await crearEntidad(conDomicilio: true);
      final venta = await vender(entidadFiscalId: entidad.id) as CrearServicioEventualExitoso;

      final resultado = await facturar.ejecutar(
        servicioEventualId: venta.servicioEventual.id,
        folio: 'A-777',
        fechaEmision: DateTime(2026, 5, 4),
        metodo: MetodoPagoCobro.pue,
      );
      final documento = (resultado as RegistrarDocumentoFiscalEventualExitoso).documento;

      expect(documento.snapshotRazonSocial, 'Sportium SA de CV');
      expect(documento.snapshotRfc, 'SPO123456AB1');
      expect(documento.snapshotCodigoPostalFiscal, '64000');
      expect(documento.entidadFiscalId, entidad.id, reason: 'procedencia, para navegar');
    });

    test('cambiar la razón social del Cliente NO cambia el CFDI ya emitido', () async {
      final entidad = await crearEntidad(conDomicilio: true);
      final venta = await vender(entidadFiscalId: entidad.id) as CrearServicioEventualExitoso;
      final documento = ((await facturar.ejecutar(
        servicioEventualId: venta.servicioEventual.id,
        folio: 'A-778',
        fechaEmision: DateTime(2026, 5, 4),
        metodo: MetodoPagoCobro.pue,
      )) as RegistrarDocumentoFiscalEventualExitoso)
          .documento;

      await entidadFiscalRepo.actualizar(
        id: entidad.id,
        cambios: const EntidadFiscalCompanion(razonSocial: Value('Sportium Norte SA de CV')),
        motivo: 'Cambio de denominación',
      );

      final releido = (await db.select(db.servicioEventualDocumentoFiscal).get()).single;
      expect(releido.id, documento.id);
      expect(releido.snapshotRazonSocial, 'Sportium SA de CV',
          reason: 'el documento de ayer tiene que seguir diciendo lo que decía');
    });
  });
}
