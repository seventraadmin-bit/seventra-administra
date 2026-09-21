import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/configuracion_cobro_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_portal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/entidad_fiscal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/puesto_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_comercial_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_etapa_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_linea_comercial_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_estatus_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_vigencia_configuracion_cobro_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_errors.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_etapa_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/corregir_configuracion_cobro_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_configuracion_cobro_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_linea_comercial_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_servicio_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/linea_comercial_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';

void main() {
  late AppDatabase db;
  late ClienteRepositoryImpl clienteRepo;
  late ServicioRepositoryImpl servicioRepo;
  late EntidadFiscalRepositoryImpl entidadFiscalRepo;
  late ClientePortalRepositoryImpl clientePortalRepo;
  late ServicioComercialRepositoryImpl comercialRepo;
  late ConfiguracionCobroRepositoryImpl configuracionCobroRepo;
  late CrearServicioUseCase crearServicio;
  late CrearLineaComercialUseCase crearLineaComercial;
  late CambiarEstatusServicioUseCase cambiarEstatusServicio;
  late CrearConfiguracionCobroUseCase crearConfiguracionCobro;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    clienteRepo = ClienteRepositoryImpl(db);
    servicioRepo = ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db));
    entidadFiscalRepo = EntidadFiscalRepositoryImpl(db);
    clientePortalRepo = ClientePortalRepositoryImpl(db);
    final puestoRepo = PuestoRepositoryImpl(db);
    final catalogoRepo = CatalogoRepositoryImpl(db);
    comercialRepo = ServicioComercialRepositoryImpl(db);
    configuracionCobroRepo = ConfiguracionCobroRepositoryImpl(db);
    final servicioValidator = ServicioValidator(clienteRepo, catalogoRepo);
    final lineaComercialValidator =
        LineaComercialValidator(puestoRepo, catalogoRepo, servicioRepo, configuracionCobroRepo);
    final configuracionCobroValidator =
        ConfiguracionCobroValidator(servicioRepo, entidadFiscalRepo, catalogoRepo, comercialRepo, clientePortalRepo);

    crearServicio = CrearServicioUseCase(servicioRepo, generarCodigo, servicioValidator);
    crearLineaComercial = CrearLineaComercialUseCase(comercialRepo, servicioRepo, lineaComercialValidator);
    cambiarEstatusServicio = CambiarEstatusServicioUseCase(servicioRepo, clienteRepo);
    crearConfiguracionCobro = CrearConfiguracionCobroUseCase(
      configuracionCobroRepo,
      servicioRepo,
      configuracionCobroValidator,
      const ConfiguracionCobroEtapaValidator(),
    );
  });

  tearDown(() => db.close());

  Future<ClienteData> crearClienteDePrueba({String codigo = 'CLI-000001', String nombre = 'Sportium'}) {
    return clienteRepo.crear(ClienteCompanion.insert(codigo: codigo, nombreComercial: nombre));
  }

  Future<ServicioData> crearServicioDePrueba(
    String clienteId, {
    String nombre = 'Vigilancia Sportium Toluca',
    DateTime? fechaInicio,
  }) async {
    final creado = await crearServicio.ejecutar(
      clienteId: clienteId,
      borrador: ServicioBorrador(
        nombre: nombre,
        tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
        fechaInicio: fechaInicio ?? DateTime(2026, 1, 1),
      ),
    );
    return (creado as GuardarServicioExitoso).servicio;
  }

  Future<EntidadFiscalData> crearEntidadFiscalDePrueba(
    String clienteId, {
    String codigo = 'ENF-0001',
    String razonSocial = 'Sportium Club Uno SA de CV',
    String rfc = 'SPO010101AA1',
  }) {
    return entidadFiscalRepo.crear(
      EntidadFiscalCompanion.insert(codigo: codigo, clienteId: clienteId, razonSocial: razonSocial, rfc: rfc),
    );
  }

  Future<void> agregarLineaComercialDePrueba(
    String servicioId, {
    TratamientoIva tratamientoIva = TratamientoIva.noAplica,
  }) async {
    final puesto = await PuestoRepositoryImpl(db).crear(
      PuestoCompanion.insert(
        codigo: 'PUE-${servicioId.hashCode.abs()}',
        nombre: 'Guardia',
        areaId: SeedIds.areaOperaciones,
        tipo: 'operativo',
        nivelJerarquico: 5,
      ),
    );
    final resultado = await crearLineaComercial.ejecutar(
      servicioId: servicioId,
      borrador: LineaComercialBorrador(
        puestoId: puesto.id,
        modalidadTurnoId: SeedIds.modalidadTurno24x24,
        cantidadElementos: 2,
        precioUnitario: 1500000,
        tratamientoIva: tratamientoIva,
        fechaInicioVigencia: DateTime(2026, 1, 1),
      ),
    );
    if (resultado is! CrearLineaComercialExitoso) {
      throw StateError('no se pudo crear la línea comercial de prueba: $resultado');
    }
  }

  group('CrearConfiguracionCobroUseCase — casos reales obligatorios', () {
    test('Sportium: factura por club (CFDI), PPD con complemento requerido', () async {
      final cliente = await crearClienteDePrueba();
      final servicio = await crearServicioDePrueba(cliente.id);
      final entidad = await crearEntidadFiscalDePrueba(cliente.id);
      await agregarLineaComercialDePrueba(servicio.id, tratamientoIva: TratamientoIva.masIva);

      final resultado = await crearConfiguracionCobro.ejecutar(
        servicioId: servicio.id,
        borrador: ConfiguracionCobroBorrador(
          tipoDocumento: TipoDocumentoCobro.cfdi,
          frecuenciaId: SeedIds.frecuenciaCobroMensual,
          diaInicioPeriodo: 21,
          agrupacion: AgrupacionCobro.porEntidadFiscal,
          metodo: MetodoPagoCobro.ppd,
          requiereComplemento: true,
          fechaInicioVigencia: DateTime(2026, 1, 21),
          entidadFiscalId: entidad.id,
        ),
      );

      expect(resultado, isA<CrearConfiguracionCobroExitoso>());
      final exito = resultado as CrearConfiguracionCobroExitoso;
      expect(exito.vigencia.diaInicioPeriodo, 21);
      expect(exito.vigencia.metodo, 'ppd');
      expect(exito.vigencia.requiereComplemento, isTrue);
    });

    test('Toluca 32: recibo, mes corriente, pago día 10, IVA no aplica', () async {
      final cliente = await crearClienteDePrueba(codigo: 'CLI-000002', nombre: 'Toluca 32');
      final servicio = await crearServicioDePrueba(cliente.id, nombre: 'Vigilancia Toluca 32');
      await agregarLineaComercialDePrueba(servicio.id, tratamientoIva: TratamientoIva.noAplica);

      final resultado = await crearConfiguracionCobro.ejecutar(
        servicioId: servicio.id,
        borrador: ConfiguracionCobroBorrador(
          tipoDocumento: TipoDocumentoCobro.reciboDePago,
          frecuenciaId: SeedIds.frecuenciaCobroMensual,
          diaInicioPeriodo: 1,
          agrupacion: AgrupacionCobro.porServicio,
          metodo: MetodoPagoCobro.noAplica,
          requiereComplemento: false,
          fechaInicioVigencia: DateTime(2026, 1, 1),
        ),
      );

      expect(resultado, isA<CrearConfiguracionCobroExitoso>());
    });

    test('Mirabilia: recibo, sin Entidad fiscal ni correos', () async {
      final cliente = await crearClienteDePrueba(codigo: 'CLI-000004', nombre: 'Construcciones Habitacionales');
      final servicio = await crearServicioDePrueba(cliente.id, nombre: 'Mirabilia');
      await agregarLineaComercialDePrueba(servicio.id, tratamientoIva: TratamientoIva.noAplica);

      final resultado = await crearConfiguracionCobro.ejecutar(
        servicioId: servicio.id,
        borrador: ConfiguracionCobroBorrador(
          tipoDocumento: TipoDocumentoCobro.reciboDePago,
          frecuenciaId: SeedIds.frecuenciaCobroMensual,
          diaInicioPeriodo: 1,
          agrupacion: AgrupacionCobro.porServicio,
          metodo: MetodoPagoCobro.noAplica,
          requiereComplemento: false,
          fechaInicioVigencia: DateTime(2026, 1, 1),
        ),
      );

      expect(resultado, isA<CrearConfiguracionCobroExitoso>());
      final exito = resultado as CrearConfiguracionCobroExitoso;
      expect(exito.vigencia.entidadFiscalId, isNull);
    });

    test('Morgan: CFDI, emisión inicio de mes, correos de envío capturados', () async {
      final cliente = await crearClienteDePrueba(codigo: 'CLI-000005', nombre: 'Morgan');
      final servicio = await crearServicioDePrueba(cliente.id, nombre: 'Vigilancia Morgan');
      final entidad = await crearEntidadFiscalDePrueba(cliente.id, codigo: 'ENF-0002', razonSocial: 'Morgan SA de CV', rfc: 'MOR010101AA1');
      await agregarLineaComercialDePrueba(servicio.id, tratamientoIva: TratamientoIva.masIva);

      final resultado = await crearConfiguracionCobro.ejecutar(
        servicioId: servicio.id,
        borrador: ConfiguracionCobroBorrador(
          tipoDocumento: TipoDocumentoCobro.cfdi,
          frecuenciaId: SeedIds.frecuenciaCobroMensual,
          diaInicioPeriodo: 1,
          agrupacion: AgrupacionCobro.porServicio,
          metodo: MetodoPagoCobro.pue,
          requiereComplemento: false,
          fechaInicioVigencia: DateTime(2026, 1, 1),
          entidadFiscalId: entidad.id,
          correos: const ['facturacion@morgan.mx', 'contabilidad@morgan.mx'],
        ),
      );

      expect(resultado, isA<CrearConfiguracionCobroExitoso>());
      final configuracion = await configuracionCobroRepo.obtenerConfiguracion(servicio.id);
      expect(configuracion!.correos, {'facturacion@morgan.mx', 'contabilidad@morgan.mx'});
    });
  });

  group('ConfiguracionCobroValidator — validaciones', () {
    test('rechaza campos requeridos ausentes', () async {
      final cliente = await crearClienteDePrueba();
      final servicio = await crearServicioDePrueba(cliente.id);

      final resultado = await crearConfiguracionCobro.ejecutar(
        servicioId: servicio.id,
        borrador: const ConfiguracionCobroBorrador(
          tipoDocumento: null,
          frecuenciaId: '',
          diaInicioPeriodo: null,
          agrupacion: null,
          metodo: null,
          requiereComplemento: false,
          fechaInicioVigencia: null,
        ),
      );

      expect(resultado, isA<CrearConfiguracionCobroErroresValidacion>());
      final errores = (resultado as CrearConfiguracionCobroErroresValidacion).errores;
      expect(errores.any((e) => e.campo == CampoConfiguracionCobro.tipoDocumento), isTrue);
      expect(errores.any((e) => e.campo == CampoConfiguracionCobro.frecuencia), isTrue);
      expect(errores.any((e) => e.campo == CampoConfiguracionCobro.diaInicioPeriodo), isTrue);
      expect(errores.any((e) => e.campo == CampoConfiguracionCobro.agrupacion), isTrue);
      expect(errores.any((e) => e.campo == CampoConfiguracionCobro.metodo), isTrue);
      expect(errores.any((e) => e.campo == CampoConfiguracionCobro.fechaInicioVigencia), isTrue);
    });

    test('recibo con método distinto de noAplica es rechazado', () async {
      final cliente = await crearClienteDePrueba();
      final servicio = await crearServicioDePrueba(cliente.id);

      final resultado = await crearConfiguracionCobro.ejecutar(
        servicioId: servicio.id,
        borrador: ConfiguracionCobroBorrador(
          tipoDocumento: TipoDocumentoCobro.reciboDePago,
          frecuenciaId: SeedIds.frecuenciaCobroMensual,
          diaInicioPeriodo: 1,
          agrupacion: AgrupacionCobro.porServicio,
          metodo: MetodoPagoCobro.pue,
          requiereComplemento: false,
          fechaInicioVigencia: DateTime(2026, 1, 1),
        ),
      );

      expect(resultado, isA<CrearConfiguracionCobroErroresValidacion>());
      final errores = (resultado as CrearConfiguracionCobroErroresValidacion).errores;
      expect(errores.any((e) => e.codigo == CodigoErrorConfiguracionCobro.metodoInvalidoParaRecibo), isTrue);
    });

    test('PPD sin requerirComplemento es rechazado', () async {
      final cliente = await crearClienteDePrueba();
      final servicio = await crearServicioDePrueba(cliente.id);
      final entidad = await crearEntidadFiscalDePrueba(cliente.id);

      final resultado = await crearConfiguracionCobro.ejecutar(
        servicioId: servicio.id,
        borrador: ConfiguracionCobroBorrador(
          tipoDocumento: TipoDocumentoCobro.cfdi,
          frecuenciaId: SeedIds.frecuenciaCobroMensual,
          diaInicioPeriodo: 1,
          agrupacion: AgrupacionCobro.porServicio,
          metodo: MetodoPagoCobro.ppd,
          requiereComplemento: false,
          fechaInicioVigencia: DateTime(2026, 1, 1),
          entidadFiscalId: entidad.id,
        ),
      );

      expect(resultado, isA<CrearConfiguracionCobroErroresValidacion>());
      final errores = (resultado as CrearConfiguracionCobroErroresValidacion).errores;
      expect(errores.any((e) => e.codigo == CodigoErrorConfiguracionCobro.complementoRequeridoParaPpd), isTrue);
    });

    test('CFDI sin Entidad fiscal es rechazado', () async {
      final cliente = await crearClienteDePrueba();
      final servicio = await crearServicioDePrueba(cliente.id);

      final resultado = await crearConfiguracionCobro.ejecutar(
        servicioId: servicio.id,
        borrador: ConfiguracionCobroBorrador(
          tipoDocumento: TipoDocumentoCobro.cfdi,
          frecuenciaId: SeedIds.frecuenciaCobroMensual,
          diaInicioPeriodo: 1,
          agrupacion: AgrupacionCobro.porServicio,
          metodo: MetodoPagoCobro.pue,
          requiereComplemento: false,
          fechaInicioVigencia: DateTime(2026, 1, 1),
        ),
      );

      expect(resultado, isA<CrearConfiguracionCobroErroresValidacion>());
      final errores = (resultado as CrearConfiguracionCobroErroresValidacion).errores;
      expect(errores.any((e) => e.codigo == CodigoErrorConfiguracionCobro.entidadFiscalRequeridaParaCfdi), isTrue);
    });

    test('CFDI con Entidad fiscal de otro Cliente es rechazado', () async {
      final cliente = await crearClienteDePrueba();
      final otroCliente = await crearClienteDePrueba(codigo: 'CLI-000099', nombre: 'Otro Cliente');
      final servicio = await crearServicioDePrueba(cliente.id);
      final entidadDeOtroCliente = await crearEntidadFiscalDePrueba(otroCliente.id);

      final resultado = await crearConfiguracionCobro.ejecutar(
        servicioId: servicio.id,
        borrador: ConfiguracionCobroBorrador(
          tipoDocumento: TipoDocumentoCobro.cfdi,
          frecuenciaId: SeedIds.frecuenciaCobroMensual,
          diaInicioPeriodo: 1,
          agrupacion: AgrupacionCobro.porServicio,
          metodo: MetodoPagoCobro.pue,
          requiereComplemento: false,
          fechaInicioVigencia: DateTime(2026, 1, 1),
          entidadFiscalId: entidadDeOtroCliente.id,
        ),
      );

      expect(resultado, isA<CrearConfiguracionCobroErroresValidacion>());
      final errores = (resultado as CrearConfiguracionCobroErroresValidacion).errores;
      expect(errores.any((e) => e.codigo == CodigoErrorConfiguracionCobro.noExiste), isTrue);
    });

    test('rechaza una fecha de vigencia anterior al inicio del Servicio', () async {
      final cliente = await crearClienteDePrueba();
      final servicio = await crearServicioDePrueba(cliente.id);

      final resultado = await crearConfiguracionCobro.ejecutar(
        servicioId: servicio.id,
        borrador: ConfiguracionCobroBorrador(
          tipoDocumento: TipoDocumentoCobro.reciboDePago,
          frecuenciaId: SeedIds.frecuenciaCobroMensual,
          diaInicioPeriodo: 1,
          agrupacion: AgrupacionCobro.porServicio,
          metodo: MetodoPagoCobro.noAplica,
          requiereComplemento: false,
          fechaInicioVigencia: DateTime(2025, 1, 1),
        ),
      );

      expect(resultado, isA<CrearConfiguracionCobroErroresValidacion>());
      final errores = (resultado as CrearConfiguracionCobroErroresValidacion).errores;
      expect(errores.any((e) => e.codigo == CodigoErrorConfiguracionCobro.fechaAnteriorInicioServicio), isTrue);
    });

    test('rechaza un correo con formato inválido', () async {
      final cliente = await crearClienteDePrueba();
      final servicio = await crearServicioDePrueba(cliente.id);

      final resultado = await crearConfiguracionCobro.ejecutar(
        servicioId: servicio.id,
        borrador: ConfiguracionCobroBorrador(
          tipoDocumento: TipoDocumentoCobro.reciboDePago,
          frecuenciaId: SeedIds.frecuenciaCobroMensual,
          diaInicioPeriodo: 1,
          agrupacion: AgrupacionCobro.porServicio,
          metodo: MetodoPagoCobro.noAplica,
          requiereComplemento: false,
          fechaInicioVigencia: DateTime(2026, 1, 1),
          correos: const ['correo invalido sin arroba'],
        ),
      );

      expect(resultado, isA<CrearConfiguracionCobroErroresValidacion>());
      final errores = (resultado as CrearConfiguracionCobroErroresValidacion).errores;
      expect(errores.any((e) => e.codigo == CodigoErrorConfiguracionCobro.correoInvalido), isTrue);
    });

    test('rechaza agregar una Configuración de cobro a un Servicio terminado', () async {
      final cliente = await crearClienteDePrueba();
      final servicio = await crearServicioDePrueba(cliente.id);
      await cambiarEstatusServicio.ejecutar(
        servicioId: servicio.id,
        nuevo: EstatusServicio.terminado,
        fechaTerminoEfectiva: DateTime(2026, 6, 1),
        motivo: 'Motivo de prueba',
      );

      final resultado = await crearConfiguracionCobro.ejecutar(
        servicioId: servicio.id,
        borrador: ConfiguracionCobroBorrador(
          tipoDocumento: TipoDocumentoCobro.reciboDePago,
          frecuenciaId: SeedIds.frecuenciaCobroMensual,
          diaInicioPeriodo: 1,
          agrupacion: AgrupacionCobro.porServicio,
          metodo: MetodoPagoCobro.noAplica,
          requiereComplemento: false,
          fechaInicioVigencia: DateTime(2026, 6, 1),
        ),
      );

      expect(resultado, isA<CrearConfiguracionCobroServicioNoDisponible>());
    });

    test('rechaza una segunda Configuración de cobro para el mismo Servicio (1:1)', () async {
      final cliente = await crearClienteDePrueba();
      final servicio = await crearServicioDePrueba(cliente.id);
      final borrador = ConfiguracionCobroBorrador(
        tipoDocumento: TipoDocumentoCobro.reciboDePago,
        frecuenciaId: SeedIds.frecuenciaCobroMensual,
        diaInicioPeriodo: 1,
        agrupacion: AgrupacionCobro.porServicio,
        metodo: MetodoPagoCobro.noAplica,
        requiereComplemento: false,
        fechaInicioVigencia: DateTime(2026, 1, 1),
      );

      final primero = await crearConfiguracionCobro.ejecutar(servicioId: servicio.id, borrador: borrador);
      expect(primero, isA<CrearConfiguracionCobroExitoso>());

      final segundo = await crearConfiguracionCobro.ejecutar(servicioId: servicio.id, borrador: borrador);
      expect(segundo, isA<CrearConfiguracionCobroYaExiste>());
    });
  });

  group('Validación cruzada IVA/documento (Resoluciones D y G)', () {
    test('CFDI es rechazado si alguna línea comercial vigente usa IVA "No aplica"', () async {
      final cliente = await crearClienteDePrueba();
      final servicio = await crearServicioDePrueba(cliente.id);
      final entidad = await crearEntidadFiscalDePrueba(cliente.id);
      await agregarLineaComercialDePrueba(servicio.id, tratamientoIva: TratamientoIva.noAplica);

      final resultado = await crearConfiguracionCobro.ejecutar(
        servicioId: servicio.id,
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
      );

      expect(resultado, isA<CrearConfiguracionCobroErroresValidacion>());
      final errores = (resultado as CrearConfiguracionCobroErroresValidacion).errores;
      expect(errores.any((e) => e.codigo == CodigoErrorConfiguracionCobro.cfdiIncompatibleConIvaNoAplica), isTrue);
    });

    test('recibo es rechazado si alguna línea comercial vigente no usa IVA "No aplica"', () async {
      final cliente = await crearClienteDePrueba();
      final servicio = await crearServicioDePrueba(cliente.id);
      await agregarLineaComercialDePrueba(servicio.id, tratamientoIva: TratamientoIva.masIva);

      final resultado = await crearConfiguracionCobro.ejecutar(
        servicioId: servicio.id,
        borrador: ConfiguracionCobroBorrador(
          tipoDocumento: TipoDocumentoCobro.reciboDePago,
          frecuenciaId: SeedIds.frecuenciaCobroMensual,
          diaInicioPeriodo: 1,
          agrupacion: AgrupacionCobro.porServicio,
          metodo: MetodoPagoCobro.noAplica,
          requiereComplemento: false,
          fechaInicioVigencia: DateTime(2026, 1, 1),
        ),
      );

      expect(resultado, isA<CrearConfiguracionCobroErroresValidacion>());
      final errores = (resultado as CrearConfiguracionCobroErroresValidacion).errores;
      expect(errores.any((e) => e.codigo == CodigoErrorConfiguracionCobro.reciboRequiereIvaNoAplica), isTrue);
    });

    test('una línea comercial CFDI-incompatible (noAplica) es rechazada si ya existe Configuración de cobro CFDI', () async {
      final cliente = await crearClienteDePrueba();
      final servicio = await crearServicioDePrueba(cliente.id);
      final entidad = await crearEntidadFiscalDePrueba(cliente.id);
      await agregarLineaComercialDePrueba(servicio.id, tratamientoIva: TratamientoIva.masIva);

      final configuracion = await crearConfiguracionCobro.ejecutar(
        servicioId: servicio.id,
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
      );
      expect(configuracion, isA<CrearConfiguracionCobroExitoso>());

      final puesto = await PuestoRepositoryImpl(db).crear(
        PuestoCompanion.insert(
          codigo: 'PUE-9999',
          nombre: 'Jefe de turno',
          areaId: SeedIds.areaOperaciones,
          tipo: 'operativo',
          nivelJerarquico: 6,
        ),
      );
      final resultadoLinea = await crearLineaComercial.ejecutar(
        servicioId: servicio.id,
        borrador: LineaComercialBorrador(
          puestoId: puesto.id,
          modalidadTurnoId: SeedIds.modalidadTurno24x24,
          cantidadElementos: 1,
          precioUnitario: 1000000,
          tratamientoIva: TratamientoIva.noAplica,
          fechaInicioVigencia: DateTime(2026, 1, 1),
        ),
      );

      expect(resultadoLinea, isA<CrearLineaComercialErroresValidacion>());
    });
  });

  group('Escenario real — Residencial Tikal (Etapa 15, diagnóstico y corrección)', () {
    // Datos exactamente como los capturó Marlon: Documento=Recibo de pago,
    // Frecuencia=Mensual, Día inicio=1, Agrupación=Por Cliente,
    // Método=PUE, Complemento=No, Entidad fiscal=seleccionada,
    // Vigente desde=01/06/2026, Emisión=día fijo/mismo mes/día 19,
    // Procesamiento=día fijo/mismo mes/día 19, Pago esperado=día
    // fijo/mismo mes/día 20, Portal/Cuenta/Observaciones/Correos vacíos.
    ConfiguracionCobroBorrador borradorTikal(String entidadFiscalId, {required MetodoPagoCobro metodo}) {
      return ConfiguracionCobroBorrador(
        tipoDocumento: TipoDocumentoCobro.reciboDePago,
        frecuenciaId: SeedIds.frecuenciaCobroMensual,
        diaInicioPeriodo: 1,
        agrupacion: AgrupacionCobro.porCliente,
        metodo: metodo,
        requiereComplemento: false,
        fechaInicioVigencia: DateTime(2026, 6, 1),
        entidadFiscalId: entidadFiscalId,
      );
    }

    List<EtapaCobroBorrador> reglasTikal() => const [
          EtapaCobroBorrador(
            id: 'tikal-emision',
            tipoSistema: TipoEventoCobro.emision,
            orden: 0,
            tipoRegla: TipoReglaEvento.diaFijoDelMes,
            mesRelativo: MesRelativoCobro.actual,
            diaDelMes: 19,
          ),
          EtapaCobroBorrador(
            id: 'tikal-procesamiento',
            tipoSistema: TipoEventoCobro.procesamiento,
            orden: 1,
            tipoRegla: TipoReglaEvento.diaFijoDelMes,
            mesRelativo: MesRelativoCobro.actual,
            diaDelMes: 19,
          ),
          EtapaCobroBorrador(
            id: 'tikal-pago',
            tipoSistema: TipoEventoCobro.pagoEsperado,
            orden: 2,
            tipoRegla: TipoReglaEvento.diaFijoDelMes,
            mesRelativo: MesRelativoCobro.actual,
            diaDelMes: 20,
          ),
        ];

    test('reproduce el bug: Recibo de pago + PUE es rechazado por una regla real, no un mensaje genérico', () async {
      final cliente = await crearClienteDePrueba(codigo: 'CLI-TIKAL', nombre: 'Residencial Tikal');
      final servicio = await crearServicioDePrueba(cliente.id, nombre: 'Vigilancia Tikal', fechaInicio: DateTime(2026, 1, 1));
      final entidad = await crearEntidadFiscalDePrueba(cliente.id, codigo: 'ENF-TIKAL', razonSocial: 'Tikal SA de CV', rfc: 'TIK010101AA1');
      await agregarLineaComercialDePrueba(servicio.id, tratamientoIva: TratamientoIva.noAplica);

      final resultado = await crearConfiguracionCobro.ejecutar(
        servicioId: servicio.id,
        borrador: borradorTikal(entidad.id, metodo: MetodoPagoCobro.pue),
        etapas: reglasTikal(),
      );

      expect(resultado, isA<CrearConfiguracionCobroErroresValidacion>());
      final fallo = resultado as CrearConfiguracionCobroErroresValidacion;
      // La causa real y única: Recibo de pago no admite PUE/PPD — regla de
      // negocio correcta (Etapa 4H.1), no un bug del validador. La
      // Entidad fiscal seleccionada nunca fue evaluada para Recibo, y las
      // 3 reglas de evento (día 19/19/20) son válidas por sí mismas.
      expect(fallo.errores, hasLength(1));
      expect(fallo.errores.single.codigo, CodigoErrorConfiguracionCobro.metodoInvalidoParaRecibo);
      expect(fallo.errores.single.campo, CampoConfiguracionCobro.metodo);
      expect(fallo.erroresEtapas, isEmpty, reason: 'emisión/procesamiento el mismo día no está prohibido');
    });

    test('corregido: Recibo de pago + método "No aplica" se acepta con las mismas reglas y datos', () async {
      final cliente = await crearClienteDePrueba(codigo: 'CLI-TIKAL', nombre: 'Residencial Tikal');
      final servicio = await crearServicioDePrueba(cliente.id, nombre: 'Vigilancia Tikal', fechaInicio: DateTime(2026, 1, 1));
      final entidad = await crearEntidadFiscalDePrueba(cliente.id, codigo: 'ENF-TIKAL', razonSocial: 'Tikal SA de CV', rfc: 'TIK010101AA1');
      await agregarLineaComercialDePrueba(servicio.id, tratamientoIva: TratamientoIva.noAplica);

      final resultado = await crearConfiguracionCobro.ejecutar(
        servicioId: servicio.id,
        borrador: borradorTikal(entidad.id, metodo: MetodoPagoCobro.noAplica),
        etapas: reglasTikal(),
      );

      expect(resultado, isA<CrearConfiguracionCobroExitoso>());
      final exito = resultado as CrearConfiguracionCobroExitoso;
      expect(exito.vigencia.metodo, 'noAplica');
      expect(exito.vigencia.agrupacion, 'porCliente');

      final configuracion = await configuracionCobroRepo.obtenerConfiguracion(servicio.id);
      expect(configuracion!.etapas, hasLength(3));
      expect(configuracion.correos, isEmpty);
      expect(configuracion.vigenciaActual?.cuentaBancaria, isNull);
      expect(configuracion.vigenciaActual?.portalNombre, isNull);
      expect(configuracion.vigenciaActual?.observaciones, isNull);
    });
  });

  group('Corregir Configuración de cobro (Etapa 15 — sin historia)', () {
    late CorregirConfiguracionCobroUseCase corregirConfiguracionCobro;
    late CambiarVigenciaConfiguracionCobroUseCase cambiarVigenciaConfiguracionCobro;

    setUp(() {
      final configuracionCobroValidator =
          ConfiguracionCobroValidator(
              servicioRepo, entidadFiscalRepo, CatalogoRepositoryImpl(db), comercialRepo, clientePortalRepo);
      corregirConfiguracionCobro = CorregirConfiguracionCobroUseCase(
        configuracionCobroRepo,
        configuracionCobroValidator,
        const ConfiguracionCobroEtapaValidator(),
      );
      cambiarVigenciaConfiguracionCobro = CambiarVigenciaConfiguracionCobroUseCase(
        configuracionCobroRepo,
        servicioRepo,
        configuracionCobroValidator,
        const ConfiguracionCobroEtapaValidator(),
      );
    });

    Future<String> crearConfiguracionDePrueba(String servicioId) async {
      final resultado = await crearConfiguracionCobro.ejecutar(
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
      );
      return ((resultado as CrearConfiguracionCobroExitoso).configuracion).id;
    }

    test('corrige in-place una configuración recién creada, sin generar una nueva vigencia', () async {
      final cliente = await crearClienteDePrueba();
      final servicio = await crearServicioDePrueba(cliente.id);
      await agregarLineaComercialDePrueba(servicio.id);
      final configuracionId = await crearConfiguracionDePrueba(servicio.id);
      final vigenciaOriginalId = (await configuracionCobroRepo.listarHistorial(configuracionId)).single.id;

      final resultado = await corregirConfiguracionCobro.ejecutar(
        configuracionCobroId: configuracionId,
        borrador: ConfiguracionCobroBorrador(
          tipoDocumento: TipoDocumentoCobro.reciboDePago,
          frecuenciaId: SeedIds.frecuenciaCobroMensual,
          diaInicioPeriodo: 5, // corrige un error de captura (se quería día 5, no día 1)
          agrupacion: AgrupacionCobro.porServicio,
          metodo: MetodoPagoCobro.noAplica,
          requiereComplemento: false,
          fechaInicioVigencia: DateTime(2026, 1, 1),
        ),
        motivo: 'Motivo de prueba',
      );

      expect(resultado, isA<CorregirConfiguracionCobroExitoso>());
      final vigenciaCorregida = (resultado as CorregirConfiguracionCobroExitoso).vigencia;
      expect(vigenciaCorregida.id, vigenciaOriginalId, reason: 'muta el mismo registro, no crea uno nuevo');
      expect(vigenciaCorregida.diaInicioPeriodo, 5);

      final historial = await configuracionCobroRepo.listarHistorial(configuracionId);
      expect(historial, hasLength(1), reason: 'corregir nunca cierra+inserta, solo muta la única vigencia');

      final configuracion = await configuracionCobroRepo.obtenerConfiguracion(servicio.id);
      expect(configuracion!.esCorregible, isTrue);
    });

    test('no reescribe una configuración que ya pasó por "Nueva vigencia"', () async {
      final cliente = await crearClienteDePrueba();
      final servicio = await crearServicioDePrueba(cliente.id);
      await agregarLineaComercialDePrueba(servicio.id);
      final configuracionId = await crearConfiguracionDePrueba(servicio.id);

      await cambiarVigenciaConfiguracionCobro.ejecutar(
        configuracionCobroId: configuracionId,
        borrador: ConfiguracionCobroBorrador(
          tipoDocumento: TipoDocumentoCobro.reciboDePago,
          frecuenciaId: SeedIds.frecuenciaCobroMensual,
          diaInicioPeriodo: 1,
          agrupacion: AgrupacionCobro.porServicio,
          metodo: MetodoPagoCobro.noAplica,
          requiereComplemento: false,
          fechaInicioVigencia: DateTime(2027, 1, 1),
        ),
      );

      final resultado = await corregirConfiguracionCobro.ejecutar(
        configuracionCobroId: configuracionId,
        borrador: ConfiguracionCobroBorrador(
          tipoDocumento: TipoDocumentoCobro.reciboDePago,
          frecuenciaId: SeedIds.frecuenciaCobroMensual,
          diaInicioPeriodo: 9,
          agrupacion: AgrupacionCobro.porServicio,
          metodo: MetodoPagoCobro.noAplica,
          requiereComplemento: false,
          fechaInicioVigencia: DateTime(2026, 1, 1),
        ),
        motivo: 'Motivo de prueba',
      );

      expect(resultado, isA<CorregirConfiguracionCobroTieneHistoria>());
      final configuracion = await configuracionCobroRepo.obtenerConfiguracion(servicio.id);
      expect(configuracion!.esCorregible, isFalse);
    });

    test('no reescribe una vigencia que ya generó un DocumentoPorEmitirConfiguracion', () async {
      final cliente = await crearClienteDePrueba();
      final servicio = await crearServicioDePrueba(cliente.id);
      await agregarLineaComercialDePrueba(servicio.id);
      final configuracionId = await crearConfiguracionDePrueba(servicio.id);
      final vigenciaId = (await configuracionCobroRepo.listarHistorial(configuracionId)).single.id;

      final documento = await db.into(db.documentoPorEmitir).insertReturning(
            DocumentoPorEmitirCompanion.insert(
              codigo: 'DOC-0001',
              clienteId: cliente.id,
              tipoDocumento: 'reciboDePago',
              agrupacion: 'porServicio',
              metodo: 'noAplica',
              periodoInicio: DateTime(2026, 1, 1),
              periodoFin: DateTime(2026, 1, 31),
              generationKey: 'GK-0001',
              importeBaseEsperado: 3000000,
              importeFinalEsperado: 3000000,
            ),
          );
      await db.into(db.documentoPorEmitirConfiguracion).insert(
            DocumentoPorEmitirConfiguracionCompanion.insert(
              documentoPorEmitirId: documento.id,
              servicioId: servicio.id,
              configuracionCobroVigenciaId: vigenciaId,
            ),
          );

      final resultado = await corregirConfiguracionCobro.ejecutar(
        configuracionCobroId: configuracionId,
        borrador: ConfiguracionCobroBorrador(
          tipoDocumento: TipoDocumentoCobro.reciboDePago,
          frecuenciaId: SeedIds.frecuenciaCobroMensual,
          diaInicioPeriodo: 9,
          agrupacion: AgrupacionCobro.porServicio,
          metodo: MetodoPagoCobro.noAplica,
          requiereComplemento: false,
          fechaInicioVigencia: DateTime(2026, 1, 1),
        ),
        motivo: 'Motivo de prueba',
      );

      expect(resultado, isA<CorregirConfiguracionCobroTieneHistoria>());
    });

    test('configuración inexistente', () async {
      final resultado = await corregirConfiguracionCobro.ejecutar(
        configuracionCobroId: 'no-existe',
        borrador: ConfiguracionCobroBorrador(
          tipoDocumento: TipoDocumentoCobro.reciboDePago,
          frecuenciaId: SeedIds.frecuenciaCobroMensual,
          diaInicioPeriodo: 1,
          agrupacion: AgrupacionCobro.porServicio,
          metodo: MetodoPagoCobro.noAplica,
          requiereComplemento: false,
          fechaInicioVigencia: DateTime(2026, 1, 1),
        ),
        motivo: 'Motivo de prueba',
      );
      expect(resultado, isA<CorregirConfiguracionCobroNoExiste>());
    });
  });
}
