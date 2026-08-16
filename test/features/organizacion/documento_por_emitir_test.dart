import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import 'package:riseg_one/core/attachments/attachment_repository.dart';
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_por_cobrar_repository_impl.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
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
import 'package:riseg_one/features/organizacion/domain/usecases/actualizar_ajuste_manual_documento_por_emitir_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_estatus_documento_por_emitir_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_etapa_validator.dart';
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

/// Adaptador de prueba (Etapa 15) — misma forma que el viejo
/// `ReglaEventoBorrador` (Etapa 4H.2), para no tener que reescribir los
/// ~15 escenarios reales ya cubiertos en este archivo (Sportium,
/// Miluyole, Morgan, Toluca 32, Tikal, Mirabilia, ...) solo por el
/// cambio de modelo. `_etapasDesdeReglas` resuelve `id`/`orden`/
/// `etapaReferenciaId` automáticamente: cada llamada genera ids frescos
/// (uuid), así que reutilizar la misma lista de `_ReglaLegacy` en
/// varias iteraciones (ej. los 4 clubes de Sportium) nunca choca contra
/// la restricción de llave primaria de `ConfiguracionCobroEtapa`.
class _ReglaLegacy {
  const _ReglaLegacy({
    required this.tipoEvento,
    this.tipoRegla,
    this.mesRelativo,
    this.diaDelMes,
    this.ordinalSemana,
    this.diaSemana,
    this.offsetDiasHabiles,
    this.eventoReferencia,
  });

  final TipoEventoCobro tipoEvento;
  final TipoReglaEvento? tipoRegla;
  final MesRelativoCobro? mesRelativo;
  final int? diaDelMes;
  final OrdinalSemanaCobro? ordinalSemana;
  final DiaSemanaCobro? diaSemana;
  final int? offsetDiasHabiles;
  final TipoEventoCobro? eventoReferencia;
}

List<EtapaCobroBorrador> _etapasDesdeReglas(List<_ReglaLegacy> reglas) {
  final idPorTipo = {for (final r in reglas) r.tipoEvento: const Uuid().v4()};
  var orden = 0;
  return [
    for (final r in reglas)
      EtapaCobroBorrador(
        id: idPorTipo[r.tipoEvento]!,
        tipoSistema: r.tipoEvento,
        orden: orden++,
        tipoRegla: r.tipoRegla,
        mesRelativo: r.mesRelativo,
        diaDelMes: r.diaDelMes,
        ordinalSemana: r.ordinalSemana,
        diaSemana: r.diaSemana,
        offsetDias: r.offsetDiasHabiles,
        etapaReferenciaId: r.eventoReferencia == null ? null : idPorTipo[r.eventoReferencia],
      ),
  ];
}

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
    servicioRepo = ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db));
    puestoRepo = PuestoRepositoryImpl(db);
    final catalogoRepo = CatalogoRepositoryImpl(db);
    final entidadFiscalRepo = EntidadFiscalRepositoryImpl(db);
    final clientePortalRepo = ClientePortalRepositoryImpl(db);
    comercialRepo = ServicioComercialRepositoryImpl(db);
    configuracionCobroRepo = ConfiguracionCobroRepositoryImpl(db);
    documentoRepo = DocumentoPorEmitirRepositoryImpl(db, AttachmentRepository(db), CuentaPorCobrarRepositoryImpl(db));

    final servicioValidator = ServicioValidator(clienteRepo, catalogoRepo);
    final lineaComercialValidator = LineaComercialValidator(puestoRepo, catalogoRepo, servicioRepo, configuracionCobroRepo);
    final configuracionCobroValidator =
        ConfiguracionCobroValidator(servicioRepo, entidadFiscalRepo, catalogoRepo, comercialRepo, clientePortalRepo);
    const reglaValidator = ConfiguracionCobroEtapaValidator();

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
    List<_ReglaLegacy> reglas = const [],
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
      etapas: _etapasDesdeReglas(reglas),
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
            _ReglaLegacy(
              tipoEvento: TipoEventoCobro.emision,
              tipoRegla: TipoReglaEvento.diaFijoDelMes,
              mesRelativo: MesRelativoCobro.siguiente,
              diaDelMes: 21,
            ),
            _ReglaLegacy(
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
        // Periodo mensual completo (Sportium, 21 jul-20 ago, 31 días de
        // calendario) siempre vale 30 días comerciales — no cobra más
        // que un precio unitario exacto: 1,800,000 * 30 / 30 = 1,800,000.
        expect(documento.importeBaseEsperado, 1800000);
        final detalle = await documentoRepo.obtenerDetalle(documento.id);
        expect(detalle!.servicioIds, hasLength(1));
        expect(detalle.lineas.single.diasAplicables, 30);
        expect(detalle.lineas.single.subtotalProporcional, 1800000);
      }
    });

    test('Miluyole: emisión día 1, procesamiento primer miércoles, pago miércoles siguiente al procesamiento', () async {
      final cliente = await crearClienteDePrueba('Miluyole');
      final servicio = await crearServicioDePrueba(cliente.id, 'Vigilancia Miluyole');
      await crearLineaDePrueba(servicio.id);
      await crearConfiguracionCobroDePrueba(
        servicio.id,
        reglas: [
          _ReglaLegacy(
            tipoEvento: TipoEventoCobro.emision,
            tipoRegla: TipoReglaEvento.diaFijoDelMes,
            mesRelativo: MesRelativoCobro.actual,
            diaDelMes: 1,
          ),
          _ReglaLegacy(
            tipoEvento: TipoEventoCobro.procesamiento,
            tipoRegla: TipoReglaEvento.nEsimoDiaSemanaDelMes,
            mesRelativo: MesRelativoCobro.actual,
            diaSemana: DiaSemanaCobro.miercoles,
            ordinalSemana: OrdinalSemanaCobro.primero,
          ),
          _ReglaLegacy(
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
          _ReglaLegacy(
            tipoEvento: TipoEventoCobro.emision,
            tipoRegla: TipoReglaEvento.diaFijoDelMes,
            mesRelativo: MesRelativoCobro.actual,
            diaDelMes: 1,
          ),
          _ReglaLegacy(
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
          _ReglaLegacy(
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
      // Enero completo (31 días de calendario) vale 30 días comerciales:
      // 1,500,000 * 2 * 30 / 30 = 3,000,000.
      expect(documento.importeBaseEsperado, 3000000);
    });

    test('Tikal: solo regla de pago (sin emisión) — la generación automática no lo encuentra, requiere creación manual', () async {
      final cliente = await crearClienteDePrueba('Tikal');
      final servicio = await crearServicioDePrueba(cliente.id, 'Vigilancia Tikal');
      await crearLineaDePrueba(servicio.id, cantidadElementos: 2, precioUnitario: 1600000);
      await crearConfiguracionCobroDePrueba(
        servicio.id,
        reglas: [
          _ReglaLegacy(
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

  group('Regla comercial de 30 días (Etapa 15, corrección real de Marlon)', () {
    test('Tikal: 19 agosto - 18 septiembre (mes comercial completo) → 30 días, \$34,000.00', () async {
      final cliente = await crearClienteDePrueba('Residencial Tikal');
      final servicio = await crearServicioDePrueba(cliente.id, 'Vigilancia Tikal', fechaInicio: DateTime(2026, 1, 1));
      await crearLineaDePrueba(servicio.id, cantidadElementos: 2, precioUnitario: 1700000);
      await crearConfiguracionCobroDePrueba(servicio.id, diaInicioPeriodo: 19);

      final manual = await crearManual.ejecutar(
        clienteId: cliente.id,
        servicioIds: [servicio.id],
        periodoInicio: DateTime(2026, 8, 19),
        periodoFin: DateTime(2026, 9, 18),
      );

      expect(manual, isA<CrearDocumentoManualExitoso>());
      final documento = (manual as CrearDocumentoManualExitoso).documento;
      final detalle = await documentoRepo.obtenerDetalle(documento.id);
      expect(detalle!.lineas.single.diasAplicables, 30);
      expect(documento.importeBaseEsperado, 3400000, reason: '2 × \$17,000.00 = \$34,000.00, nunca prorrateado por 31 días');
    });

    test('Febrero completo (28 días de calendario) → 30 días comerciales', () async {
      final cliente = await crearClienteDePrueba('Prueba Febrero');
      final servicio = await crearServicioDePrueba(cliente.id, 'Vigilancia Febrero', fechaInicio: DateTime(2026, 1, 1));
      await crearLineaDePrueba(servicio.id, cantidadElementos: 1, precioUnitario: 1500000);
      await crearConfiguracionCobroDePrueba(servicio.id);

      final manual = await crearManual.ejecutar(
        clienteId: cliente.id,
        servicioIds: [servicio.id],
        periodoInicio: DateTime(2026, 2, 1),
        periodoFin: DateTime(2026, 2, 28),
      );

      final documento = (manual as CrearDocumentoManualExitoso).documento;
      final detalle = await documentoRepo.obtenerDetalle(documento.id);
      expect(detalle!.lineas.single.diasAplicables, 30);
      expect(documento.importeBaseEsperado, 1500000);
    });

    test('Enero completo (31 días de calendario) → 30 días comerciales', () async {
      final cliente = await crearClienteDePrueba('Prueba Enero');
      final servicio = await crearServicioDePrueba(cliente.id, 'Vigilancia Enero', fechaInicio: DateTime(2026, 1, 1));
      await crearLineaDePrueba(servicio.id, cantidadElementos: 1, precioUnitario: 1500000);
      await crearConfiguracionCobroDePrueba(servicio.id);

      final manual = await crearManual.ejecutar(
        clienteId: cliente.id,
        servicioIds: [servicio.id],
        periodoInicio: DateTime(2026, 1, 1),
        periodoFin: DateTime(2026, 1, 31),
      );

      final documento = (manual as CrearDocumentoManualExitoso).documento;
      final detalle = await documentoRepo.obtenerDetalle(documento.id);
      expect(detalle!.lineas.single.diasAplicables, 30);
      expect(documento.importeBaseEsperado, 1500000);
    });

    test('periodo parcial de 15 días nunca se vuelve 30 — sigue prorrateado', () async {
      final cliente = await crearClienteDePrueba('Prueba Parcial');
      final servicio = await crearServicioDePrueba(cliente.id, 'Vigilancia Parcial', fechaInicio: DateTime(2026, 1, 1));
      await crearLineaDePrueba(servicio.id, cantidadElementos: 1, precioUnitario: 1500000);
      await crearConfiguracionCobroDePrueba(servicio.id);

      // 15 días reales (1 al 15 de enero) — no tiene la forma de un mes
      // calendario completo, así que debe prorratearse con días reales.
      final manual = await crearManual.ejecutar(
        clienteId: cliente.id,
        servicioIds: [servicio.id],
        periodoInicio: DateTime(2026, 1, 1),
        periodoFin: DateTime(2026, 1, 15),
      );

      final documento = (manual as CrearDocumentoManualExitoso).documento;
      final detalle = await documentoRepo.obtenerDetalle(documento.id);
      expect(detalle!.lineas.single.diasAplicables, 15);
      expect(documento.importeBaseEsperado, 750000, reason: '1,500,000 * 15 / 30 = 750,000');
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
          _ReglaLegacy(
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
        _ReglaLegacy(
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
      // Enero completo vale 30 días comerciales: (1,000,000 + 2,000,000)
      // * 30 / 30 = 3,000,000.
      expect(combinado.importeBaseEsperado, 3000000);

      final detalleSeparado = await documentoRepo.obtenerDetalle(separado.id);
      expect(detalleSeparado!.servicioIds, [servicioC.id]);
      expect(separado.importeBaseEsperado, 500000);
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
          _ReglaLegacy(
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

      // Ambos periodos son meses comerciales completos (30 días): la
      // vigencia de diciembre queda truncada exactamente en el último
      // día de diciembre — coincide con el fin del periodo, no lo corta
      // a mitad de mes — así que sigue siendo un periodo completo, con
      // el precio vigente en cada uno: 1,000,000 (diciembre, precio
      // anterior); 1,200,000 (enero, precio nuevo).
      expect(diciembre.importeBaseEsperado, 1000000, reason: 'diciembre usa el precio vigente antes del cambio');
      expect(enero.importeBaseEsperado, 1200000, reason: 'enero usa el precio de la nueva vigencia');
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

  group('Flujo dinámico de etapas — Agenda y snapshot de hitos (Etapa 15)', () {
    test(
      'Sportium con cadena completa (Emisión → Validación → Carga a portal → Pago esperado) genera '
      'exactamente 4 hitos con las fechas exactas del escenario acordado',
      () async {
        final cliente = await crearClienteDePrueba('Sportium');
        final servicio = await crearServicioDePrueba(cliente.id, 'Club Sportium Toluca');
        await crearLineaDePrueba(servicio.id, precioUnitario: 1800000);

        final emisionId = const Uuid().v4();
        final validacionId = const Uuid().v4();
        final portalId = const Uuid().v4();
        final pagoId = const Uuid().v4();

        final resultadoConfiguracion = await crearConfiguracionCobro.ejecutar(
          servicioId: servicio.id,
          borrador: ConfiguracionCobroBorrador(
            tipoDocumento: TipoDocumentoCobro.reciboDePago,
            frecuenciaId: SeedIds.frecuenciaCobroMensual,
            diaInicioPeriodo: 21,
            agrupacion: AgrupacionCobro.porServicio,
            metodo: MetodoPagoCobro.noAplica,
            requiereComplemento: false,
            fechaInicioVigencia: DateTime(2026, 1, 1),
          ),
          etapas: [
            EtapaCobroBorrador(
              id: emisionId,
              tipoSistema: TipoEventoCobro.emision,
              orden: 0,
              tipoRegla: TipoReglaEvento.diaFijoDelMes,
              mesRelativo: MesRelativoCobro.siguiente,
              diaDelMes: 21,
            ),
            EtapaCobroBorrador(
              id: validacionId,
              nombre: 'Validación por correo',
              orden: 1,
              tipoRegla: TipoReglaEvento.diasCalendarioDespuesDe,
              offsetDias: 0,
              etapaReferenciaId: emisionId,
            ),
            EtapaCobroBorrador(
              id: portalId,
              nombre: 'Carga a portal',
              orden: 2,
              tipoRegla: TipoReglaEvento.diasCalendarioDespuesDe,
              offsetDias: 4,
              etapaReferenciaId: validacionId,
            ),
            EtapaCobroBorrador(
              id: pagoId,
              tipoSistema: TipoEventoCobro.pagoEsperado,
              orden: 3,
              tipoRegla: TipoReglaEvento.diasCalendarioDespuesDe,
              offsetDias: 7,
              etapaReferenciaId: portalId,
            ),
          ],
        );
        expect(resultadoConfiguracion, isA<CrearConfiguracionCobroExitoso>());

        final resultado = await generarAgenda.ejecutar(rangoInicio: DateTime(2026, 8, 1), rangoFin: DateTime(2026, 8, 31));
        expect(resultado.creados, hasLength(1));
        final documento = resultado.creados.single;

        // Compatibilidad legacy: CxC/Agenda siguen leyendo estas 2
        // columnas sin saber nada de Validación/Carga a portal.
        expect(documento.fechaEmisionProgramada, DateTime(2026, 8, 21));
        expect(documento.fechaPagoEsperadoProgramada, DateTime(2026, 9, 1));

        final hitos = await documentoRepo.listarHitos(documento.id);
        expect(hitos, hasLength(4), reason: 'las 4 etapas activas, ni una fija de más ni de menos');

        final porOrden = [...hitos]..sort((a, b) => a.orden.compareTo(b.orden));
        expect(porOrden[0].tipoSistema, 'emision');
        expect(porOrden[0].nombre, isNull);
        expect(porOrden[0].fechaProgramada, DateTime(2026, 8, 21));

        expect(porOrden[1].tipoSistema, isNull);
        expect(porOrden[1].nombre, 'Validación por correo');
        expect(porOrden[1].fechaProgramada, DateTime(2026, 8, 21), reason: 'mismo día de Emisión');

        expect(porOrden[2].tipoSistema, isNull);
        expect(porOrden[2].nombre, 'Carga a portal');
        expect(porOrden[2].fechaProgramada, DateTime(2026, 8, 25), reason: '4 días después de Validación');

        expect(porOrden[3].tipoSistema, 'pagoEsperado');
        expect(porOrden[3].nombre, isNull);
        expect(porOrden[3].fechaProgramada, DateTime(2026, 9, 1), reason: '7 días después de Carga a portal');
      },
    );

    test(
      'cliente simple con Cierre → Emisión → Pago esperado solo genera los 2 hitos realmente '
      'configurados — Agenda nunca muestra una etapa intermedia inexistente',
      () async {
        final cliente = await crearClienteDePrueba('Cliente simple');
        final servicio = await crearServicioDePrueba(cliente.id, 'Vigilancia simple');
        await crearLineaDePrueba(servicio.id, precioUnitario: 1200000);

        final emisionId = const Uuid().v4();

        final resultadoConfiguracion = await crearConfiguracionCobro.ejecutar(
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
          etapas: [
            EtapaCobroBorrador(
              id: emisionId,
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
              tipoRegla: TipoReglaEvento.diasCalendarioDespuesDe,
              offsetDias: 15,
              etapaReferenciaId: emisionId,
            ),
          ],
        );
        expect(resultadoConfiguracion, isA<CrearConfiguracionCobroExitoso>());

        final resultado = await generarAgenda.ejecutar(rangoInicio: DateTime(2026, 9, 1), rangoFin: DateTime(2026, 9, 30));
        expect(resultado.creados, hasLength(1));
        final documento = resultado.creados.single;

        final hitos = await documentoRepo.listarHitos(documento.id);
        expect(hitos, hasLength(2), reason: 'nunca se inventa Validación/Procesamiento/Carga a portal');
        expect(hitos.map((h) => h.tipoSistema).toSet(), {'emision', 'pagoEsperado'});
        expect(hitos.every((h) => h.nombre == null), isTrue, reason: 'ambas son etapas de sistema, ninguna personalizada');
      },
    );
  });
}
