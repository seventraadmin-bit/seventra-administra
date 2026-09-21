// Blindaje del generador de Agenda: una vigencia retroactiva no vuelve
// a pedir un periodo ya materializado.
//
// El caso real (MORGAN ATLACOMULCO): agosto 2026 se emitió como
// DOC-000035 bajo la configuración vigente desde el 24/04. Al registrar
// después una vigencia nueva, retroactiva, la `generationKey` de agosto
// cambió —el segmento de vigencias es parte de ella—, la idempotencia
// técnica dejó de reconocer el periodo y la Agenda volvió a pedirlo:
// nació DOC-000040, un agosto duplicado y pendiente junto al ya
// procesado.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

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
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_etapa_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/documento_por_emitir_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_linea_comercial_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_estatus_documento_por_emitir_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_vigencia_configuracion_cobro_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_etapa_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_configuracion_cobro_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_documento_manual_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_linea_comercial_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/documento_por_emitir_generation_key.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/ensamblar_documento_por_emitir_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/generar_agenda_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_servicio_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/linea_comercial_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/registrar_emision_documento_por_emitir_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';

void main() {
  group('claveComercialDeGenerationKey', () {
    test('es la clave técnica sin el segmento de vigencias', () {
      const tecnica = 'porServicio|cli|ef|srv|vigencia-vieja|2026-08-01|2026-08-31|cfdi';
      const conOtraVigencia = 'porServicio|cli|ef|srv|vigencia-nueva|2026-08-01|2026-08-31|cfdi';

      expect(
        claveComercialDeGenerationKey(tecnica),
        'porServicio|cli|ef|srv|2026-08-01|2026-08-31|cfdi',
      );
      expect(
        claveComercialDeGenerationKey(tecnica),
        claveComercialDeGenerationKey(conOtraVigencia),
        reason: 'el mismo hecho comercial bajo dos configuraciones distintas',
      );
    });

    test('cambiar cualquier OTRA dimensión sí cambia la identidad comercial', () {
      const base = 'porServicio|cli|ef|srv|vig|2026-08-01|2026-08-31|cfdi';
      const distintas = {
        'agrupación': 'porCliente|cli|ef|srv|vig|2026-08-01|2026-08-31|cfdi',
        'cliente': 'porServicio|otro|ef|srv|vig|2026-08-01|2026-08-31|cfdi',
        'entidad fiscal': 'porServicio|cli|otra|srv|vig|2026-08-01|2026-08-31|cfdi',
        'servicios': 'porServicio|cli|ef|otro|vig|2026-08-01|2026-08-31|cfdi',
        'periodo': 'porServicio|cli|ef|srv|vig|2026-09-01|2026-09-30|cfdi',
        'tipo de documento': 'porServicio|cli|ef|srv|vig|2026-08-01|2026-08-31|reciboDePago',
      };
      distintas.forEach((dimension, clave) {
        expect(
          claveComercialDeGenerationKey(clave),
          isNot(claveComercialDeGenerationKey(base)),
          reason: dimension,
        );
      });
    });
  });

  group('GenerarAgendaUseCase — idempotencia comercial', () {
    late AppDatabase db;
    late DocumentoPorEmitirRepositoryImpl documentoRepo;
    late ConfiguracionCobroRepositoryImpl configuracionRepo;
    late GenerarAgendaUseCase generarAgenda;
    late CrearConfiguracionCobroUseCase crearConfiguracion;
    late CambiarVigenciaConfiguracionCobroUseCase cambiarVigencia;
    late RegistrarEmisionDocumentoPorEmitirUseCase registrarEmision;
    late CambiarEstatusDocumentoPorEmitirUseCase cambiarEstatus;
    late CrearDocumentoManualUseCase crearManual;
    late CrearServicioUseCase crearServicio;
    late CrearLineaComercialUseCase crearLinea;
    late String clienteId;
    late String servicioId;
    late String configuracionId;
    late String puestoId;

    ConfiguracionCobroBorrador borrador(DateTime desde) => ConfiguracionCobroBorrador(
          tipoDocumento: TipoDocumentoCobro.reciboDePago,
          frecuenciaId: SeedIds.frecuenciaCobroMensual,
          diaInicioPeriodo: 1,
          agrupacion: AgrupacionCobro.porServicio,
          metodo: MetodoPagoCobro.noAplica,
          requiereComplemento: false,
          fechaInicioVigencia: desde,
        );

    /// Emisión el día [diaDelMes] del mes indicado. Ids frescos en cada
    /// llamada: el `id` de `EtapaCobroBorrador` es de lote, no llave
    /// primaria, y reutilizarlo revienta la nueva vigencia.
    List<EtapaCobroBorrador> etapasEmision({
      required MesRelativoCobro mes,
      required int diaDelMes,
    }) =>
        [
          EtapaCobroBorrador(
            id: const Uuid().v4(),
            tipoSistema: TipoEventoCobro.emision,
            orden: 0,
            tipoRegla: TipoReglaEvento.diaFijoDelMes,
            mesRelativo: mes,
            diaDelMes: diaDelMes,
          ),
        ];

    Future<String> crearServicioDePrueba(String nombre) async {
      final creado = await crearServicio.ejecutar(
        clienteId: clienteId,
        borrador: ServicioBorrador(
          nombre: nombre,
          tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
          fechaInicio: DateTime(2026, 1, 1),
        ),
      );
      final id = (creado as GuardarServicioExitoso).servicio.id;
      final linea = await crearLinea.ejecutar(
        servicioId: id,
        borrador: LineaComercialBorrador(
          puestoId: puestoId,
          modalidadTurnoId: SeedIds.modalidadTurno24x24,
          cantidadElementos: 1,
          precioUnitario: 1800000,
          tratamientoIva: TratamientoIva.noAplica,
          fechaInicioVigencia: DateTime(2026, 1, 1),
        ),
      );
      expect(linea, isA<CrearLineaComercialExitoso>());
      return id;
    }

    /// La configuración original: mes VENCIDO — se emite el día 2 del
    /// mes siguiente al periodo.
    Future<String> configuracionOriginal(String servicio) async {
      final creada = await crearConfiguracion.ejecutar(
        servicioId: servicio,
        borrador: borrador(DateTime(2026, 4, 24)),
        etapas: etapasEmision(mes: MesRelativoCobro.siguiente, diaDelMes: 2),
      );
      expect(creada, isA<CrearConfiguracionCobroExitoso>());
      return (creada as CrearConfiguracionCobroExitoso).configuracion.id;
    }

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
      final clienteRepo = ClienteRepositoryImpl(db);
      final servicioRepo = ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db));
      final catalogoRepo = CatalogoRepositoryImpl(db);
      final comercialRepo = ServicioComercialRepositoryImpl(db);
      final puestoRepo = PuestoRepositoryImpl(db);
      configuracionRepo = ConfiguracionCobroRepositoryImpl(db);
      documentoRepo = DocumentoPorEmitirRepositoryImpl(db, AttachmentRepository(db), CuentaPorCobrarRepositoryImpl(db));

      final validator = ConfiguracionCobroValidator(
        servicioRepo,
        EntidadFiscalRepositoryImpl(db),
        catalogoRepo,
        comercialRepo,
        ClientePortalRepositoryImpl(db),
      );
      const etapaValidator = ConfiguracionCobroEtapaValidator();

      crearServicio = CrearServicioUseCase(servicioRepo, generarCodigo, ServicioValidator(clienteRepo, catalogoRepo));
      crearLinea = CrearLineaComercialUseCase(
        comercialRepo,
        servicioRepo,
        LineaComercialValidator(puestoRepo, catalogoRepo, servicioRepo, configuracionRepo),
      );
      crearConfiguracion = CrearConfiguracionCobroUseCase(configuracionRepo, servicioRepo, validator, etapaValidator);
      cambiarVigencia =
          CambiarVigenciaConfiguracionCobroUseCase(configuracionRepo, servicioRepo, validator, etapaValidator);
      generarAgenda = GenerarAgendaUseCase(
        documentoRepo,
        configuracionRepo,
        servicioRepo,
        EnsamblarDocumentoPorEmitirUseCase(comercialRepo, configuracionRepo),
        generarCodigo,
      );
      registrarEmision = RegistrarEmisionDocumentoPorEmitirUseCase(documentoRepo);
      cambiarEstatus = CambiarEstatusDocumentoPorEmitirUseCase(documentoRepo);
      crearManual = CrearDocumentoManualUseCase(
        documentoRepo,
        configuracionRepo,
        servicioRepo,
        EnsamblarDocumentoPorEmitirUseCase(comercialRepo, configuracionRepo),
        generarCodigo,
      );

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

      final cliente = await clienteRepo.crear(
        ClienteCompanion.insert(codigo: 'CLI-000010', nombreComercial: 'MORGAN'),
      );
      clienteId = cliente.id;
      servicioId = await crearServicioDePrueba('MORGAN ATLACOMULCO');
      configuracionId = await configuracionOriginal(servicioId);
    });

    tearDown(() => db.close());

    /// La vigencia retroactiva del caso real: se registra después, pero
    /// con efecto desde mayo, así que alcanza a periodos ya facturados.
    Future<void> vigenciaRetroactiva() async {
      final resultado = await cambiarVigencia.ejecutar(
        configuracionCobroId: configuracionId,
        borrador: borrador(DateTime(2026, 5, 1)),
        etapas: etapasEmision(mes: MesRelativoCobro.actual, diaDelMes: 3),
      );
      expect(resultado, isA<CambiarVigenciaConfiguracionCobroExitoso>());
    }

    Future<List<DocumentoPorEmitirData>> documentosDe(DateTime periodoInicio) async {
      final todos = await db.select(db.documentoPorEmitir).get();
      return todos.where((d) => d.periodoInicio == periodoInicio).toList();
    }

    /// Lleva un documento hasta `procesadoAceptado` por el flujo normal
    /// —emisión y después cambio de estatus—, que es lo que le da su
    /// Cuenta por cobrar.
    Future<void> procesar(DocumentoPorEmitirData documento, {int importe = 1800000}) async {
      final emitido = await registrarEmision.ejecutar(
        documentoPorEmitirId: documento.id,
        folioDocumento: 'REC-${documento.codigo}',
        fechaEmisionReal: documento.fechaEmisionProgramada ?? DateTime(2026, 9, 2),
        importeEmitido: importe,
      );
      expect(emitido, isA<RegistrarEmisionDocumentoPorEmitirExitoso>());
      final procesado = await cambiarEstatus.ejecutar(
        documentoPorEmitirId: documento.id,
        nuevo: EstatusDocumentoPorEmitir.procesadoAceptado,
      );
      expect(procesado, isA<CambiarEstatusDocumentoPorEmitirExitoso>());
    }

    /// Agosto, tal como lo agenda la configuración original: el periodo
    /// 01-31/ago se emite el 02/sep.
    Future<DocumentoPorEmitirData> agendarAgosto() async {
      final resultado = await generarAgenda.ejecutar(
        rangoInicio: DateTime(2026, 9, 1),
        rangoFin: DateTime(2026, 9, 30),
      );
      expect(resultado.creados, hasLength(1));
      final documento = resultado.creados.single;
      expect(documento.periodoInicio, DateTime(2026, 8, 1));
      return documento;
    }

    test('1. misma vigencia, generar dos veces: un solo documento', () async {
      await agendarAgosto();

      final segunda = await generarAgenda.ejecutar(
        rangoInicio: DateTime(2026, 9, 1),
        rangoFin: DateTime(2026, 9, 30),
      );

      expect(segunda.creados, isEmpty);
      expect(segunda.yaExistian, 1);
      expect(await documentosDe(DateTime(2026, 8, 1)), hasLength(1));
    });

    test('2. vigencia retroactiva sobre un periodo YA PROCESADO: no duplica (DOC-000040)', () async {
      final agosto = await agendarAgosto();
      await procesar(agosto);
      final claveAntes = agosto.generationKey;

      await vigenciaRetroactiva();
      final resultado = await generarAgenda.ejecutar(
        rangoInicio: DateTime(2026, 8, 1),
        rangoFin: DateTime(2026, 8, 31),
      );

      expect(resultado.creados, isEmpty, reason: 'agosto ya está materializado');
      expect(resultado.yaExistian, 1);
      final agostos = await documentosDe(DateTime(2026, 8, 1));
      expect(agostos, hasLength(1), reason: 'no nace un segundo agosto');
      expect(agostos.single.estatus, 'procesadoAceptado');
      expect(agostos.single.generationKey, claveAntes);
    });

    test('3. vigencia nueva + periodo posterior no generado todavía: SÍ lo genera', () async {
      await procesar(await agendarAgosto());
      await vigenciaRetroactiva();

      // Bajo la regla nueva —mes corriente, día 3— septiembre se emite
      // el 03/sep: un documento legítimo que nunca existió.
      final resultado = await generarAgenda.ejecutar(
        rangoInicio: DateTime(2026, 9, 1),
        rangoFin: DateTime(2026, 9, 30),
      );

      expect(resultado.creados, hasLength(1));
      expect(resultado.creados.single.periodoInicio, DateTime(2026, 9, 1));
      expect(await documentosDe(DateTime(2026, 8, 1)), hasLength(1));
    });

    test('4. un documento PENDIENTE equivalente tampoco se duplica', () async {
      final agosto = await agendarAgosto();
      expect(agosto.estatus, EstatusDocumentoPorEmitir.pendiente.name);

      await vigenciaRetroactiva();
      final resultado = await generarAgenda.ejecutar(
        rangoInicio: DateTime(2026, 8, 1),
        rangoFin: DateTime(2026, 8, 31),
      );

      expect(resultado.creados, isEmpty, reason: 'ya está agendado: pedirlo otra vez es pedir lo mismo');
      expect(await documentosDe(DateTime(2026, 8, 1)), hasLength(1));
    });

    test('5. un documento CANCELADO libera el periodo para reprogramarlo', () async {
      final agosto = await agendarAgosto();
      final cancelado = await cambiarEstatus.ejecutar(
        documentoPorEmitirId: agosto.id,
        nuevo: EstatusDocumentoPorEmitir.cancelado,
        motivo: 'Programado con la configuración equivocada.',
      );
      expect(cancelado, isA<CambiarEstatusDocumentoPorEmitirExitoso>());

      await vigenciaRetroactiva();
      final resultado = await generarAgenda.ejecutar(
        rangoInicio: DateTime(2026, 8, 1),
        rangoFin: DateTime(2026, 8, 31),
      );

      expect(resultado.creados, hasLength(1), reason: 'cancelar no puede bloquear el periodo para siempre');
      final agostos = await documentosDe(DateTime(2026, 8, 1));
      expect(agostos, hasLength(2));
      expect(
        agostos.where((d) => d.estatus == 'cancelado'),
        hasLength(1),
        reason: 'el cancelado se conserva como historia, no se borra',
      );
    });

    test('6. dos periodos distintos conviven', () async {
      await generarAgenda.ejecutar(rangoInicio: DateTime(2026, 9, 1), rangoFin: DateTime(2026, 9, 30));
      await generarAgenda.ejecutar(rangoInicio: DateTime(2026, 10, 1), rangoFin: DateTime(2026, 10, 31));

      final periodos = (await db.select(db.documentoPorEmitir).get()).map((d) => d.periodoInicio).toSet();
      expect(periodos, {DateTime(2026, 8, 1), DateTime(2026, 9, 1)});
    });

    test('7. otro servicio del mismo cliente no queda bloqueado por el primero', () async {
      final segundo = await crearServicioDePrueba('MORGAN TOLUCA');
      await configuracionOriginal(segundo);

      final resultado = await generarAgenda.ejecutar(
        rangoInicio: DateTime(2026, 9, 1),
        rangoFin: DateTime(2026, 9, 30),
      );

      expect(resultado.creados, hasLength(2), reason: 'agrupación porServicio: un documento por servicio');
      expect(
        resultado.creados.map((d) => claveComercialDeGenerationKey(d.generationKey)).toSet(),
        hasLength(2),
        reason: 'son hechos comerciales distintos, no equivalentes',
      );
    });

    /// Captura manual del MISMO agosto, tal como ocurrió el 10/09.
    Future<CrearDocumentoManualResultado> crearAgostoAMano() => crearManual.ejecutar(
          clienteId: clienteId,
          servicioIds: [servicioId],
          periodoInicio: DateTime(2026, 8, 1),
          periodoFin: DateTime(2026, 8, 31),
        );

    test('7b. capturar A MANO un agosto ya procesado tras la vigencia retroactiva: no duplica', () async {
      // Ésta es la reproducción exacta del caso real: DOC-000040 nació
      // `creadoManual`, no del generador.
      final agosto = await agendarAgosto();
      await procesar(agosto);
      await vigenciaRetroactiva();

      final resultado = await crearAgostoAMano();

      expect(resultado, isA<CrearDocumentoManualYaExiste>());
      expect((resultado as CrearDocumentoManualYaExiste).documento.id, agosto.id,
          reason: 'debe señalar el agosto que YA existe, no crear otro');
      expect(await documentosDe(DateTime(2026, 8, 1)), hasLength(1));
    });

    test('7c. capturar a mano sigue permitido cuando el periodo está cancelado', () async {
      final agosto = await agendarAgosto();
      await cambiarEstatus.ejecutar(
        documentoPorEmitirId: agosto.id,
        nuevo: EstatusDocumentoPorEmitir.cancelado,
        motivo: 'Programado con la configuración equivocada.',
      );
      await vigenciaRetroactiva();

      final resultado = await crearAgostoAMano();

      expect(resultado, isA<CrearDocumentoManualExitoso>(),
          reason: 'capturar a mano lo que se canceló es justo para lo que sirve');
      expect(await documentosDe(DateTime(2026, 8, 1)), hasLength(2));
    });

    test('7d. capturar a mano un periodo que el generador nunca agendó sigue funcionando', () async {
      final resultado = await crearManual.ejecutar(
        clienteId: clienteId,
        servicioIds: [servicioId],
        periodoInicio: DateTime(2026, 6, 1),
        periodoFin: DateTime(2026, 6, 30),
      );

      expect(resultado, isA<CrearDocumentoManualExitoso>());
      expect(await documentosDe(DateTime(2026, 6, 1)), hasLength(1));
    });

    test('8. procesar un DocumentoPorEmitir deja Documento y Cuenta por cobrar coherentes', () async {
      final agosto = await agendarAgosto();
      await procesar(agosto, importe: 1800000);

      final cxc = await db.select(db.cuentaPorCobrar).get();
      expect(cxc, hasLength(1), reason: 'un documento procesado siempre tiene su CxC');
      expect(cxc.single.documentoPorEmitirId, agosto.id, reason: 'ligada por FK, no por folio ni importe');
      expect(cxc.single.importeEmitido, 1800000);
      expect(cxc.single.saldoPendiente, 1800000);
      expect(cxc.single.clienteId, clienteId);
    });

    test('8b. si la Cuenta por cobrar falla, el documento NO queda procesado', () async {
      final agosto = await agendarAgosto();
      await registrarEmision.ejecutar(
        documentoPorEmitirId: agosto.id,
        folioDocumento: 'REC-${agosto.codigo}',
        fechaEmisionReal: DateTime(2026, 9, 2),
        importeEmitido: 1800000,
      );

      // Se rompe la inserción de la CxC desde la base misma —sin tocar
      // el código de producción—, que es la única forma honesta de
      // comprobar que las dos escrituras viven en la misma transacción.
      await db.customStatement(
        'CREATE TRIGGER romper_cxc BEFORE INSERT ON cuenta_por_cobrar '
        "BEGIN SELECT RAISE(ABORT, 'falla simulada'); END;",
      );
      addTearDown(() => db.customStatement('DROP TRIGGER IF EXISTS romper_cxc;'));

      final resultado = await cambiarEstatus.ejecutar(
        documentoPorEmitirId: agosto.id,
        nuevo: EstatusDocumentoPorEmitir.procesadoAceptado,
      );

      expect(resultado, isA<CambiarEstatusDocumentoPorEmitirErrorInesperado>());
      final documento = await documentoRepo.obtenerPorId(agosto.id);
      expect(documento!.estatus, 'emitido', reason: 'la transacción revirtió el cambio de estatus');
      expect(await db.select(db.cuentaPorCobrar).get(), isEmpty);
      expect(
        (await documentoRepo.listarEventos(agosto.id)).where((e) => e.estadoNuevo == 'procesadoAceptado'),
        isEmpty,
        reason: 'tampoco queda el evento de un cambio que no ocurrió',
      );
    });
  });
}
