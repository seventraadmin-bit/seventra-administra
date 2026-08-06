import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
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
import 'package:riseg_one/features/organizacion/domain/usecases/actualizar_ajuste_manual_documento_por_emitir_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_estatus_documento_por_emitir_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_regla_evento_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_configuracion_cobro_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_documento_manual_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_vigencia_linea_comercial_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_linea_comercial_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/ensamblar_documento_por_emitir_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/generar_agenda_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_servicio_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/linea_comercial_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';

void main() {
  late AppDatabase db;
  late ClienteRepositoryImpl clienteRepo;
  late ServicioRepositoryImpl servicioRepo;
  late PuestoRepositoryImpl puestoRepo;
  late ServicioComercialRepositoryImpl comercialRepo;
  late ConfiguracionCobroRepositoryImpl configuracionCobroRepo;
  late DocumentoPorEmitirRepositoryImpl documentoRepo;
  late CrearServicioUseCase crearServicio;
  late CrearLineaComercialUseCase crearLineaComercial;
  late CambiarVigenciaLineaComercialUseCase cambiarVigenciaLineaComercial;
  late CrearConfiguracionCobroUseCase crearConfiguracionCobro;
  late GenerarAgendaUseCase generarAgenda;
  late CrearDocumentoManualUseCase crearManual;
  late CambiarEstatusDocumentoPorEmitirUseCase cambiarEstatus;
  late ActualizarAjusteManualDocumentoPorEmitirUseCase actualizarAjuste;
  late String puestoId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    clienteRepo = ClienteRepositoryImpl(db);
    servicioRepo = ServicioRepositoryImpl(db);
    puestoRepo = PuestoRepositoryImpl(db);
    final catalogoRepo = CatalogoRepositoryImpl(db);
    final entidadFiscalRepo = EntidadFiscalRepositoryImpl(db);
    comercialRepo = ServicioComercialRepositoryImpl(db);
    configuracionCobroRepo = ConfiguracionCobroRepositoryImpl(db);
    documentoRepo = DocumentoPorEmitirRepositoryImpl(db);

    final servicioValidator = ServicioValidator(clienteRepo, catalogoRepo);
    final lineaComercialValidator = LineaComercialValidator(puestoRepo, catalogoRepo, servicioRepo, configuracionCobroRepo);
    final configuracionCobroValidator =
        ConfiguracionCobroValidator(servicioRepo, entidadFiscalRepo, catalogoRepo, comercialRepo);
    const reglaValidator = ConfiguracionCobroReglaEventoValidator();

    crearServicio = CrearServicioUseCase(servicioRepo, generarCodigo, servicioValidator);
    crearLineaComercial = CrearLineaComercialUseCase(comercialRepo, servicioRepo, lineaComercialValidator);
    cambiarVigenciaLineaComercial =
        CambiarVigenciaLineaComercialUseCase(comercialRepo, servicioRepo, lineaComercialValidator);
    crearConfiguracionCobro =
        CrearConfiguracionCobroUseCase(configuracionCobroRepo, servicioRepo, configuracionCobroValidator, reglaValidator);

    final ensamblar = EnsamblarDocumentoPorEmitirUseCase(comercialRepo, configuracionCobroRepo);
    generarAgenda = GenerarAgendaUseCase(documentoRepo, configuracionCobroRepo, servicioRepo, ensamblar, generarCodigo);
    crearManual = CrearDocumentoManualUseCase(documentoRepo, configuracionCobroRepo, ensamblar, generarCodigo);
    cambiarEstatus = CambiarEstatusDocumentoPorEmitirUseCase(documentoRepo);
    actualizarAjuste = ActualizarAjusteManualDocumentoPorEmitirUseCase(documentoRepo);

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

  var _clienteContador = 0;

  Future<ClienteData> crearClienteDePrueba(String nombre) {
    _clienteContador++;
    return clienteRepo.crear(
      ClienteCompanion.insert(codigo: 'CLI-${_clienteContador.toString().padLeft(6, '0')}', nombreComercial: nombre),
    );
  }

  var _servicioContador = 0;

  Future<ServicioData> crearServicioDePrueba(String clienteId, String nombre, {DateTime? fechaInicio}) async {
    _servicioContador++;
    final creado = await crearServicio.ejecutar(
      clienteId: clienteId,
      borrador: ServicioBorrador(
        nombre: '$nombre-$_servicioContador',
        tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
        fechaInicio: fechaInicio ?? DateTime(2026, 1, 1),
      ),
    );
    return (creado as GuardarServicioExitoso).servicio;
  }

  Future<ServicioLineaComercialData> crearLineaDePrueba(
    String servicioId, {
    int cantidadElementos = 1,
    int precioUnitario = 1800000,
    TratamientoIva tratamientoIva = TratamientoIva.noAplica,
    DateTime? fechaInicioVigencia,
  }) async {
    final resultado = await crearLineaComercial.ejecutar(
      servicioId: servicioId,
      borrador: LineaComercialBorrador(
        puestoId: puestoId,
        modalidadTurnoId: SeedIds.modalidadTurno24x24,
        cantidadElementos: cantidadElementos,
        precioUnitario: precioUnitario,
        tratamientoIva: tratamientoIva,
        fechaInicioVigencia: fechaInicioVigencia ?? DateTime(2026, 1, 1),
      ),
    );
    expect(resultado, isA<CrearLineaComercialExitoso>());
    return (resultado as CrearLineaComercialExitoso).linea;
  }

  Future<String> crearConfiguracionCobroDePrueba(
    String servicioId, {
    int diaInicioPeriodo = 1,
    AgrupacionCobro agrupacion = AgrupacionCobro.porServicio,
    bool requiereComplemento = false,
    List<ReglaEventoBorrador> reglas = const [],
    DateTime? fechaInicioVigencia,
  }) async {
    final resultado = await crearConfiguracionCobro.ejecutar(
      servicioId: servicioId,
      borrador: ConfiguracionCobroBorrador(
        tipoDocumento: TipoDocumentoCobro.reciboDePago,
        frecuenciaId: SeedIds.frecuenciaCobroMensual,
        diaInicioPeriodo: diaInicioPeriodo,
        agrupacion: agrupacion,
        metodo: MetodoPagoCobro.noAplica,
        requiereComplemento: requiereComplemento,
        fechaInicioVigencia: fechaInicioVigencia ?? DateTime(2026, 1, 1),
      ),
      reglas: reglas,
    );
    expect(resultado, isA<CrearConfiguracionCobroExitoso>());
    return (resultado as CrearConfiguracionCobroExitoso).configuracion.id;
  }

  group('Casos reales obligatorios (Etapa 4I.1)', () {
    test('Sportium: 4 clubes con agrupación porServicio generan 4 documentos independientes en agosto', () async {
      final cliente = await crearClienteDePrueba('Sportium');
      for (var i = 0; i < 4; i++) {
        final servicio = await crearServicioDePrueba(cliente.id, 'Club Sportium');
        await crearLineaDePrueba(servicio.id, precioUnitario: 1800000);
        await crearConfiguracionCobroDePrueba(
          servicio.id,
          diaInicioPeriodo: 21,
          reglas: [
            ReglaEventoBorrador(
              tipoEvento: TipoEventoCobro.emision,
              tipoRegla: TipoReglaEvento.diaFijoDelMes,
              mesRelativo: MesRelativoCobro.siguiente,
              diaDelMes: 21,
            ),
            ReglaEventoBorrador(
              tipoEvento: TipoEventoCobro.pagoEsperado,
              tipoRegla: TipoReglaEvento.diasHabilesDespuesDe,
              offsetDiasHabiles: 10,
              eventoReferencia: TipoEventoCobro.emision,
            ),
          ],
        );
      }

      final resultado = await generarAgenda.ejecutar(rangoInicio: DateTime(2026, 8, 1), rangoFin: DateTime(2026, 8, 31));

      expect(resultado.creados, hasLength(4));
      expect(resultado.yaExistian, 0);
      for (final documento in resultado.creados) {
        expect(documento.periodoInicio, DateTime(2026, 7, 21));
        expect(documento.periodoFin, DateTime(2026, 8, 20));
        expect(documento.fechaEmisionProgramada, DateTime(2026, 8, 21));
        expect(documento.fechaPagoEsperadoProgramada, DateTime(2026, 9, 4));
        // Periodo de 31 días (Sportium) cobra más que un precio unitario
        // exacto de 30 días — 1,800,000 * 31 / 30 = 1,860,000.
        expect(documento.importeBaseEsperado, 1860000);
        final detalle = await documentoRepo.obtenerDetalle(documento.id);
        expect(detalle!.servicioIds, hasLength(1));
        expect(detalle.lineas.single.subtotalProporcional, 1860000);
      }
    });

    test('Miluyole: emisión día 1, procesamiento primer miércoles, pago miércoles siguiente al procesamiento', () async {
      final cliente = await crearClienteDePrueba('Miluyole');
      final servicio = await crearServicioDePrueba(cliente.id, 'Vigilancia Miluyole');
      await crearLineaDePrueba(servicio.id);
      await crearConfiguracionCobroDePrueba(
        servicio.id,
        reglas: [
          ReglaEventoBorrador(
            tipoEvento: TipoEventoCobro.emision,
            tipoRegla: TipoReglaEvento.diaFijoDelMes,
            mesRelativo: MesRelativoCobro.actual,
            diaDelMes: 1,
          ),
          ReglaEventoBorrador(
            tipoEvento: TipoEventoCobro.procesamiento,
            tipoRegla: TipoReglaEvento.nEsimoDiaSemanaDelMes,
            mesRelativo: MesRelativoCobro.actual,
            diaSemana: DiaSemanaCobro.miercoles,
            ordinalSemana: OrdinalSemanaCobro.primero,
          ),
          ReglaEventoBorrador(
            tipoEvento: TipoEventoCobro.pagoEsperado,
            tipoRegla: TipoReglaEvento.mismoDiaSemanaSiguienteA,
            diaSemana: DiaSemanaCobro.miercoles,
            eventoReferencia: TipoEventoCobro.procesamiento,
          ),
        ],
      );

      final resultado = await generarAgenda.ejecutar(rangoInicio: DateTime(2026, 1, 1), rangoFin: DateTime(2026, 1, 31));

      expect(resultado.creados, hasLength(1));
      final documento = resultado.creados.single;
      expect(documento.fechaEmisionProgramada, DateTime(2026, 1, 1));
      expect(documento.fechaProcesamientoProgramada, DateTime(2026, 1, 7));
      expect(documento.fechaPagoEsperadoProgramada, DateTime(2026, 1, 14));
    });

    test('Morgan: emisión inicio de mes, pago segundo viernes del mes siguiente', () async {
      final cliente = await crearClienteDePrueba('Morgan');
      final servicio = await crearServicioDePrueba(cliente.id, 'Vigilancia Morgan');
      await crearLineaDePrueba(servicio.id);
      await crearConfiguracionCobroDePrueba(
        servicio.id,
        reglas: [
          ReglaEventoBorrador(
            tipoEvento: TipoEventoCobro.emision,
            tipoRegla: TipoReglaEvento.diaFijoDelMes,
            mesRelativo: MesRelativoCobro.actual,
            diaDelMes: 1,
          ),
          ReglaEventoBorrador(
            tipoEvento: TipoEventoCobro.pagoEsperado,
            tipoRegla: TipoReglaEvento.nEsimoDiaSemanaDelMes,
            mesRelativo: MesRelativoCobro.siguiente,
            diaSemana: DiaSemanaCobro.viernes,
            ordinalSemana: OrdinalSemanaCobro.segundo,
          ),
        ],
      );

      final resultado = await generarAgenda.ejecutar(rangoInicio: DateTime(2026, 1, 1), rangoFin: DateTime(2026, 1, 31));

      expect(resultado.creados, hasLength(1));
      final documento = resultado.creados.single;
      expect(documento.fechaEmisionProgramada, DateTime(2026, 1, 1));
      expect(documento.fechaProcesamientoProgramada, isNull);
      expect(documento.fechaPagoEsperadoProgramada, DateTime(2026, 2, 13));
    });

    test('Toluca 32: solo regla de pago (sin emisión) — la generación automática no lo encuentra, requiere creación manual', () async {
      final cliente = await crearClienteDePrueba('Toluca 32');
      final servicio = await crearServicioDePrueba(cliente.id, 'Vigilancia Toluca 32');
      await crearLineaDePrueba(servicio.id, cantidadElementos: 2, precioUnitario: 1500000);
      await crearConfiguracionCobroDePrueba(
        servicio.id,
        reglas: [
          ReglaEventoBorrador(
            tipoEvento: TipoEventoCobro.pagoEsperado,
            tipoRegla: TipoReglaEvento.diaFijoDelMes,
            mesRelativo: MesRelativoCobro.actual,
            diaDelMes: 10,
          ),
        ],
      );

      final automatico = await generarAgenda.ejecutar(rangoInicio: DateTime(2026, 1, 1), rangoFin: DateTime(2026, 12, 31));
      expect(automatico.creados, isEmpty, reason: 'sin regla de Emisión, ningún periodo puede caer en el rango buscado');

      final manual = await crearManual.ejecutar(
        clienteId: cliente.id,
        servicioIds: [servicio.id],
        periodoInicio: DateTime(2026, 1, 1),
        periodoFin: DateTime(2026, 1, 31),
      );
      expect(manual, isA<CrearDocumentoManualExitoso>());
      final documento = (manual as CrearDocumentoManualExitoso).documento;
      expect(documento.fechaEmisionProgramada, isNull);
      expect(documento.fechaPagoEsperadoProgramada, DateTime(2026, 1, 10));
      // Enero tiene 31 días: 1,500,000 * 2 * 31 / 30 = 3,100,000.
      expect(documento.importeBaseEsperado, 3100000);
    });

    test('Tikal: solo regla de pago (sin emisión) — la generación automática no lo encuentra, requiere creación manual', () async {
      final cliente = await crearClienteDePrueba('Tikal');
      final servicio = await crearServicioDePrueba(cliente.id, 'Vigilancia Tikal');
      await crearLineaDePrueba(servicio.id, cantidadElementos: 2, precioUnitario: 1600000);
      await crearConfiguracionCobroDePrueba(
        servicio.id,
        reglas: [
          ReglaEventoBorrador(
            tipoEvento: TipoEventoCobro.pagoEsperado,
            tipoRegla: TipoReglaEvento.diaFijoDelMes,
            mesRelativo: MesRelativoCobro.actual,
            diaDelMes: 20,
          ),
        ],
      );

      final automatico = await generarAgenda.ejecutar(rangoInicio: DateTime(2026, 1, 1), rangoFin: DateTime(2026, 12, 31));
      expect(automatico.creados, isEmpty);

      final manual = await crearManual.ejecutar(
        clienteId: cliente.id,
        servicioIds: [servicio.id],
        periodoInicio: DateTime(2026, 1, 1),
        periodoFin: DateTime(2026, 1, 31),
      );
      expect(manual, isA<CrearDocumentoManualExitoso>());
      expect((manual as CrearDocumentoManualExitoso).documento.fechaPagoEsperadoProgramada, DateTime(2026, 1, 20));
    });

    test('Mirabilia: sin ninguna regla capturada — la creación manual produce un documento incompleto, sin datos inventados', () async {
      final cliente = await crearClienteDePrueba('Mirabilia');
      final servicio = await crearServicioDePrueba(cliente.id, 'Vigilancia Mirabilia');
      await crearConfiguracionCobroDePrueba(servicio.id);

      final automatico = await generarAgenda.ejecutar(rangoInicio: DateTime(2026, 1, 1), rangoFin: DateTime(2026, 12, 31));
      expect(automatico.creados, isEmpty);

      final manual = await crearManual.ejecutar(
        clienteId: cliente.id,
        servicioIds: [servicio.id],
        periodoInicio: DateTime(2026, 1, 1),
        periodoFin: DateTime(2026, 1, 31),
      );
      expect(manual, isA<CrearDocumentoManualExitoso>());
      final documento = (manual as CrearDocumentoManualExitoso).documento;
      expect(documento.fechaEmisionProgramada, isNull);
      expect(documento.fechaProcesamientoProgramada, isNull);
      expect(documento.fechaPagoEsperadoProgramada, isNull);
      expect(documento.importeBaseEsperado, 0, reason: 'sin línea comercial vigente, no se inventa un importe');
    });
  });

  group('Idempotencia', () {
    test('regenerar el mismo rango no duplica documentos', () async {
      final cliente = await crearClienteDePrueba('Morgan');
      final servicio = await crearServicioDePrueba(cliente.id, 'Vigilancia Morgan');
      await crearLineaDePrueba(servicio.id);
      await crearConfiguracionCobroDePrueba(
        servicio.id,
        reglas: [
          ReglaEventoBorrador(
            tipoEvento: TipoEventoCobro.emision,
            tipoRegla: TipoReglaEvento.diaFijoDelMes,
            mesRelativo: MesRelativoCobro.actual,
            diaDelMes: 1,
          ),
        ],
      );

      final primera = await generarAgenda.ejecutar(rangoInicio: DateTime(2026, 1, 1), rangoFin: DateTime(2026, 1, 31));
      expect(primera.creados, hasLength(1));
      expect(primera.yaExistian, 0);

      final segunda = await generarAgenda.ejecutar(rangoInicio: DateTime(2026, 1, 1), rangoFin: DateTime(2026, 1, 31));
      expect(segunda.creados, isEmpty);
      expect(segunda.yaExistian, 1);

      final todos = await documentoRepo.listar();
      expect(todos, hasLength(1));
    });
  });

  group('Agrupaciones compatibles (Etapa 4I.1)', () {
    test('agrupación porCliente combina Servicios compatibles y separa el que no lo es', () async {
      final cliente = await crearClienteDePrueba('Grupo X');
      final reglaEmisionDia1 = [
        ReglaEventoBorrador(
          tipoEvento: TipoEventoCobro.emision,
          tipoRegla: TipoReglaEvento.diaFijoDelMes,
          mesRelativo: MesRelativoCobro.actual,
          diaDelMes: 1,
        ),
      ];

      final servicioA = await crearServicioDePrueba(cliente.id, 'Servicio A');
      await crearLineaDePrueba(servicioA.id, precioUnitario: 1000000);
      await crearConfiguracionCobroDePrueba(servicioA.id, agrupacion: AgrupacionCobro.porCliente, reglas: reglaEmisionDia1);

      final servicioB = await crearServicioDePrueba(cliente.id, 'Servicio B');
      await crearLineaDePrueba(servicioB.id, precioUnitario: 2000000);
      await crearConfiguracionCobroDePrueba(servicioB.id, agrupacion: AgrupacionCobro.porCliente, reglas: reglaEmisionDia1);

      // Mismo Cliente y misma agrupación, pero requiereComplemento
      // distinto — nunca se agrupa solo por compartir Cliente.
      final servicioC = await crearServicioDePrueba(cliente.id, 'Servicio C');
      await crearLineaDePrueba(servicioC.id, precioUnitario: 500000);
      await crearConfiguracionCobroDePrueba(
        servicioC.id,
        agrupacion: AgrupacionCobro.porCliente,
        requiereComplemento: true,
        reglas: reglaEmisionDia1,
      );

      final resultado = await generarAgenda.ejecutar(rangoInicio: DateTime(2026, 1, 1), rangoFin: DateTime(2026, 1, 31));

      expect(resultado.creados, hasLength(2));
      final combinado = resultado.creados.firstWhere((d) => d.importeBaseEsperado > 2000000);
      final separado = resultado.creados.firstWhere((d) => d.importeBaseEsperado < 2000000);

      final detalleCombinado = await documentoRepo.obtenerDetalle(combinado.id);
      expect(detalleCombinado!.servicioIds, containsAll([servicioA.id, servicioB.id]));
      expect(detalleCombinado.servicioIds, hasLength(2));
      // 31 días de enero: (1,000,000 + 2,000,000) * 31 / 30 = 3,100,000.
      expect(combinado.importeBaseEsperado, 3100000);

      final detalleSeparado = await documentoRepo.obtenerDetalle(separado.id);
      expect(detalleSeparado!.servicioIds, [servicioC.id]);
      expect(separado.importeBaseEsperado, 516667);
    });
  });

  group('Cambio de precio anual', () {
    test('enero usa la vigencia nueva del precio y diciembre conserva la vigencia anterior', () async {
      final cliente = await crearClienteDePrueba('Morgan');
      final servicio = await crearServicioDePrueba(cliente.id, 'Vigilancia Morgan', fechaInicio: DateTime(2025, 1, 1));
      final linea = await crearLineaDePrueba(servicio.id, precioUnitario: 1000000, fechaInicioVigencia: DateTime(2025, 1, 1));

      final configuracionId = await crearConfiguracionCobroDePrueba(
        servicio.id,
        fechaInicioVigencia: DateTime(2025, 1, 1),
        reglas: [
          ReglaEventoBorrador(
            tipoEvento: TipoEventoCobro.emision,
            tipoRegla: TipoReglaEvento.diaFijoDelMes,
            mesRelativo: MesRelativoCobro.actual,
            diaDelMes: 1,
          ),
        ],
      );
      // Nueva vigencia de precio de la MISMA línea comercial a partir
      // del 1 de enero de 2026 (no una línea nueva y separada — eso
      // dejaría la vigencia anterior "abierta" para siempre y ambas se
      // sumarían en enero). `CambiarVigenciaLineaComercialUseCase` trunca
      // la vigencia anterior en la fecha efectiva, igual que el ciclo de
      // vigencias de la Configuración de cobro.
      final cambio = await cambiarVigenciaLineaComercial.ejecutar(
        lineaComercialId: linea.id,
        borrador: LineaComercialBorrador(
          puestoId: puestoId,
          modalidadTurnoId: SeedIds.modalidadTurno24x24,
          cantidadElementos: 1,
          precioUnitario: 1200000,
          tratamientoIva: TratamientoIva.noAplica,
          fechaInicioVigencia: DateTime(2026, 1, 1),
        ),
      );
      expect(cambio, isA<CambiarVigenciaLineaComercialExitoso>());

      final resultado = await generarAgenda.ejecutar(rangoInicio: DateTime(2025, 12, 1), rangoFin: DateTime(2026, 1, 31));
      expect(resultado.creados, hasLength(2));

      final diciembre = resultado.creados.firstWhere((d) => d.periodoInicio == DateTime(2025, 12, 1));
      final enero = resultado.creados.firstWhere((d) => d.periodoInicio == DateTime(2026, 1, 1));

      // Ambos periodos tienen 31 días (diciembre y enero): el importe es
      // proporcional al precio vigente en cada uno, nunca el mismo valor
      // fijo — 1,000,000 * 31 / 30 = 1,033,333 (diciembre, precio
      // anterior); 1,200,000 * 31 / 30 = 1,240,000 (enero, precio nuevo).
      expect(diciembre.importeBaseEsperado, 1033333, reason: 'diciembre usa el precio vigente antes del cambio');
      expect(enero.importeBaseEsperado, 1240000, reason: 'enero usa el precio de la nueva vigencia');
      expect(configuracionId, isNotEmpty);
    });
  });

  group('Máquina de estados (Etapa 4I.1)', () {
    late String documentoId;

    setUp(() async {
      final cliente = await crearClienteDePrueba('Mirabilia');
      final servicio = await crearServicioDePrueba(cliente.id, 'Vigilancia Mirabilia');
      await crearConfiguracionCobroDePrueba(servicio.id);
      final resultado = await crearManual.ejecutar(
        clienteId: cliente.id,
        servicioIds: [servicio.id],
        periodoInicio: DateTime(2026, 1, 1),
        periodoFin: DateTime(2026, 1, 31),
      );
      documentoId = (resultado as CrearDocumentoManualExitoso).documento.id;
    });

    test('Pendiente → EnPreparacion es válida y no exige motivo', () async {
      final resultado = await cambiarEstatus.ejecutar(
        documentoPorEmitirId: documentoId,
        nuevo: EstatusDocumentoPorEmitir.enPreparacion,
      );
      expect(resultado, isA<CambiarEstatusDocumentoPorEmitirExitoso>());
    });

    test('Pendiente → Cancelado exige motivo', () async {
      final sinMotivo = await cambiarEstatus.ejecutar(
        documentoPorEmitirId: documentoId,
        nuevo: EstatusDocumentoPorEmitir.cancelado,
      );
      expect(sinMotivo, isA<CambiarEstatusDocumentoPorEmitirMotivoRequerido>());

      final conMotivo = await cambiarEstatus.ejecutar(
        documentoPorEmitirId: documentoId,
        nuevo: EstatusDocumentoPorEmitir.cancelado,
        motivo: 'Cliente canceló el contrato',
      );
      expect(conMotivo, isA<CambiarEstatusDocumentoPorEmitirExitoso>());
    });

    test('Pendiente → NoRequerido exige motivo, distinto semánticamente de Cancelado', () async {
      final resultado = await cambiarEstatus.ejecutar(
        documentoPorEmitirId: documentoId,
        nuevo: EstatusDocumentoPorEmitir.noRequerido,
        motivo: 'Periodo confirmado sin documento a preparar',
      );
      expect(resultado, isA<CambiarEstatusDocumentoPorEmitirExitoso>());
      final exitoso = resultado as CambiarEstatusDocumentoPorEmitirExitoso;
      expect(exitoso.documento.estatus, 'noRequerido');
    });

    test('EnPreparacion → Pendiente es inválida (sin retroceso)', () async {
      await cambiarEstatus.ejecutar(documentoPorEmitirId: documentoId, nuevo: EstatusDocumentoPorEmitir.enPreparacion);
      final resultado = await cambiarEstatus.ejecutar(
        documentoPorEmitirId: documentoId,
        nuevo: EstatusDocumentoPorEmitir.pendiente,
      );
      expect(resultado, isA<CambiarEstatusDocumentoPorEmitirTransicionInvalida>());
    });

    test('Cancelado es terminal: ninguna transición posterior es válida', () async {
      await cambiarEstatus.ejecutar(
        documentoPorEmitirId: documentoId,
        nuevo: EstatusDocumentoPorEmitir.cancelado,
        motivo: 'Prueba',
      );
      final resultado = await cambiarEstatus.ejecutar(
        documentoPorEmitirId: documentoId,
        nuevo: EstatusDocumentoPorEmitir.enPreparacion,
      );
      expect(resultado, isA<CambiarEstatusDocumentoPorEmitirTransicionInvalida>());
    });
  });

  group('Ajuste manual (modelo desde 4I.1, interfaz diferida a 4I.2)', () {
    late String documentoId;

    setUp(() async {
      final cliente = await crearClienteDePrueba('Morgan');
      final servicio = await crearServicioDePrueba(cliente.id, 'Vigilancia Morgan');
      await crearLineaDePrueba(servicio.id, precioUnitario: 1000000);
      await crearConfiguracionCobroDePrueba(servicio.id);
      // Periodo de exactamente 30 días (2 al 31 de enero) para que el
      // importe base sea el precio unitario exacto, sin fracción — el
      // redondeo del cálculo proporcional ya se prueba por separado en
      // `calcular_importe_proporcional_test.dart` y en los casos reales
      // de este archivo (Sportium, Toluca 32).
      final resultado = await crearManual.ejecutar(
        clienteId: cliente.id,
        servicioIds: [servicio.id],
        periodoInicio: DateTime(2026, 1, 2),
        periodoFin: DateTime(2026, 1, 31),
      );
      documentoId = (resultado as CrearDocumentoManualExitoso).documento.id;
    });

    test('un ajuste distinto de cero sin motivo se rechaza', () async {
      final resultado = await actualizarAjuste.ejecutar(documentoPorEmitirId: documentoId, ajusteManual: -50000);
      expect(resultado, isA<ActualizarAjusteManualDocumentoPorEmitirMotivoRequerido>());
    });

    test('un ajuste que deja el importe final negativo se rechaza', () async {
      final resultado = await actualizarAjuste.ejecutar(
        documentoPorEmitirId: documentoId,
        ajusteManual: -2000000,
        motivoAjuste: 'Descuento excesivo de prueba',
      );
      expect(resultado, isA<ActualizarAjusteManualDocumentoPorEmitirImporteNegativo>());
    });

    test('un ajuste válido con motivo actualiza el importe final esperado', () async {
      final resultado = await actualizarAjuste.ejecutar(
        documentoPorEmitirId: documentoId,
        ajusteManual: -100000,
        motivoAjuste: 'Descuento por falta parcial',
      );
      expect(resultado, isA<ActualizarAjusteManualDocumentoPorEmitirExitoso>());
      final exitoso = resultado as ActualizarAjusteManualDocumentoPorEmitirExitoso;
      expect(exitoso.documento.importeBaseEsperado, 1000000);
      expect(exitoso.documento.ajusteManual, -100000);
      expect(exitoso.documento.importeFinalEsperado, 900000);
    });

    test('ajuste vuelto a cero limpia el motivo — el snapshot de líneas nunca se toca', () async {
      await actualizarAjuste.ejecutar(documentoPorEmitirId: documentoId, ajusteManual: -100000, motivoAjuste: 'Prueba');
      final resultado = await actualizarAjuste.ejecutar(documentoPorEmitirId: documentoId, ajusteManual: 0);
      final exitoso = resultado as ActualizarAjusteManualDocumentoPorEmitirExitoso;
      expect(exitoso.documento.ajusteManual, isNull);
      expect(exitoso.documento.motivoAjuste, isNull);
      expect(exitoso.documento.importeFinalEsperado, exitoso.documento.importeBaseEsperado);
    });
  });
}
