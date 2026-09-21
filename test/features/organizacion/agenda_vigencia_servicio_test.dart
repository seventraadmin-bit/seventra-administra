// La Agenda sólo pide documentos por periodos que el Servicio
// realmente prestó.
//
// Caso real (SPORTIUM DESIERTO / SER-000011): el servicio terminó el
// 30/07/2026, su último periodo se facturó con DOC-000029 (21–30/07),
// y aun así la generación automática del 03/09 produjo DOC-000036 por
// el periodo 21/08–20/09 — un mes entero posterior al cierre.
//
// La regla NO es "estatus == terminado no genera": un Servicio
// terminado el 31/07 sigue teniendo un documento legítimo que se emite
// el 21/08 por lo prestado hasta el 31/07. La decisión se toma contra
// el PERIODO FACTURABLE y la vigencia temporal del Servicio, nunca
// contra su estatus del día.

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
import 'package:riseg_one/features/organizacion/data/tables/documento_por_emitir_table.dart' show EstatusDocumentoPorEmitir;
import 'package:riseg_one/features/organizacion/data/tables/servicio_linea_comercial_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_table.dart' show EstatusServicio;
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_estatus_servicio_usecase.dart';
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
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_estatus_documento_por_emitir_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';

void main() {
  late AppDatabase db;
  late DocumentoPorEmitirRepositoryImpl documentoRepo;
  late ConfiguracionCobroRepositoryImpl configuracionRepo;
  late GenerarAgendaUseCase generarAgenda;
  late CrearConfiguracionCobroUseCase crearConfiguracion;
  late CambiarVigenciaConfiguracionCobroUseCase cambiarVigencia;
  late CambiarEstatusServicioUseCase cambiarEstatusServicio;
  late CrearServicioUseCase crearServicio;
  late CrearLineaComercialUseCase crearLinea;
  late CrearDocumentoManualUseCase crearManual;
  late RegistrarEmisionDocumentoPorEmitirUseCase registrarEmision;
  late CambiarEstatusDocumentoPorEmitirUseCase cambiarEstatusDocumento;
  late String clienteId;
  late String entidadFiscalId;
  late String puestoId;

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
    cambiarEstatusServicio = CambiarEstatusServicioUseCase(servicioRepo, clienteRepo);
    final ensamblar = EnsamblarDocumentoPorEmitirUseCase(comercialRepo, configuracionRepo);
    generarAgenda = GenerarAgendaUseCase(documentoRepo, configuracionRepo, servicioRepo, ensamblar, generarCodigo);
    crearManual = CrearDocumentoManualUseCase(documentoRepo, configuracionRepo, servicioRepo, ensamblar, generarCodigo);
    registrarEmision = RegistrarEmisionDocumentoPorEmitirUseCase(documentoRepo);
    cambiarEstatusDocumento = CambiarEstatusDocumentoPorEmitirUseCase(documentoRepo);

    final puesto = await puestoRepo.crear(
      PuestoCompanion.insert(
        codigo: 'PUE-0001',
        nombre: 'Elemento Operativo',
        areaId: SeedIds.areaOperaciones,
        tipo: 'operativo',
        nivelJerarquico: 5,
      ),
    );
    puestoId = puesto.id;
    final cliente = await clienteRepo.crear(
      ClienteCompanion.insert(codigo: 'CLI-000005', nombreComercial: 'SPORTIUM'),
    );
    clienteId = cliente.id;
    // Un CFDI siempre se emite contra una Entidad fiscal.
    final entidad = await EntidadFiscalRepositoryImpl(db).crear(
      EntidadFiscalCompanion.insert(
        codigo: 'ENF-000005',
        clienteId: cliente.id,
        razonSocial: 'Sportium SA de CV',
        rfc: 'SPO010101AAA',
      ),
    );
    entidadFiscalId = entidad.id;
  });

  tearDown(() => db.close());

  var contador = 0;

  /// Un Servicio con su línea comercial y su Configuración de cobro a
  /// mes vencido: el periodo corre del día 21 al 20, y se emite el 21
  /// del mes siguiente — exactamente la forma de SPORTIUM DESIERTO.
  Future<String> crearServicioMesVencido({
    required DateTime fechaInicio,
    DateTime? fechaInicioVigenciaCobro,
  }) async {
    contador++;
    final creado = await crearServicio.ejecutar(
      clienteId: clienteId,
      borrador: ServicioBorrador(
        nombre: 'SPORTIUM DESIERTO $contador',
        tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
        fechaInicio: fechaInicio,
      ),
    );
    final id = (creado as GuardarServicioExitoso).servicio.id;

    final linea = await crearLinea.ejecutar(
      servicioId: id,
      borrador: LineaComercialBorrador(
        puestoId: puestoId,
        modalidadTurnoId: SeedIds.modalidadTurno24x24,
        cantidadElementos: 2,
        precioUnitario: 1567500,
        tratamientoIva: TratamientoIva.masIva,
        fechaInicioVigencia: fechaInicio,
      ),
    );
    expect(linea, isA<CrearLineaComercialExitoso>());

    final config = await crearConfiguracion.ejecutar(
      servicioId: id,
      borrador: ConfiguracionCobroBorrador(
        tipoDocumento: TipoDocumentoCobro.cfdi,
        frecuenciaId: SeedIds.frecuenciaCobroMensual,
        diaInicioPeriodo: 21,
        agrupacion: AgrupacionCobro.porServicio,
        metodo: MetodoPagoCobro.ppd,
        requiereComplemento: true,
        fechaInicioVigencia: fechaInicioVigenciaCobro ?? fechaInicio,
        entidadFiscalId: entidadFiscalId,
      ),
      etapas: [
        EtapaCobroBorrador(
          id: const Uuid().v4(),
          tipoSistema: TipoEventoCobro.emision,
          orden: 0,
          tipoRegla: TipoReglaEvento.diaFijoDelMes,
          mesRelativo: MesRelativoCobro.siguiente,
          diaDelMes: 21,
        ),
      ],
    );
    expect(config, isA<CrearConfiguracionCobroExitoso>());
    return id;
  }

  Future<void> terminar(String servicioId, DateTime fecha) async {
    final resultado = await cambiarEstatusServicio.ejecutar(
      servicioId: servicioId,
      nuevo: EstatusServicio.terminado,
      fechaTerminoEfectiva: fecha,
      motivo: 'El cliente cerró la sucursal.',
    );
    expect(resultado, isA<CambiarEstatusServicioExitoso>());
  }

  Future<List<({DateTime inicio, DateTime fin})>> periodosGenerados() async {
    final todos = await db.select(db.documentoPorEmitir).get();
    return [
      for (final d in todos) (inicio: d.periodoInicio, fin: d.periodoFin),
    ]..sort((a, b) => a.inicio.compareTo(b.inicio));
  }

  group('Vigencia temporal del Servicio', () {
    test('1. Servicio activo durante todo el periodo: genera', () async {
      await crearServicioMesVencido(fechaInicio: DateTime(2026, 5, 1));

      final resultado = await generarAgenda.ejecutar(
        rangoInicio: DateTime(2026, 9, 1),
        rangoFin: DateTime(2026, 9, 30),
      );

      expect(resultado.creados, hasLength(1));
      expect(resultado.creados.single.periodoInicio, DateTime(2026, 8, 21));
      expect(resultado.creados.single.periodoFin, DateTime(2026, 9, 20));
    });

    test('2. Servicio terminado ANTES de que el periodo empiece: no genera (DOC-000036)', () async {
      // SPORTIUM DESIERTO, literal: inicia 01/05, termina 30/07. El
      // periodo 21/08-20/09 es entero posterior al cierre.
      final servicio = await crearServicioMesVencido(fechaInicio: DateTime(2026, 5, 1));
      await terminar(servicio, DateTime(2026, 7, 30));

      final resultado = await generarAgenda.ejecutar(
        rangoInicio: DateTime(2026, 9, 1),
        rangoFin: DateTime(2026, 9, 30),
      );

      expect(resultado.creados, isEmpty, reason: 'ningún periodo posterior al cierre');
      expect(await periodosGenerados(), isEmpty);
    });

    test('3. Servicio terminado, pero el documento del periodo YA PRESTADO sí se genera', () async {
      // Lo que Marlon subrayó: terminar el 30/07 no borra el derecho a
      // emitir el 21/08 lo prestado hasta el 30/07.
      final servicio = await crearServicioMesVencido(fechaInicio: DateTime(2026, 5, 1));
      await terminar(servicio, DateTime(2026, 7, 30));

      final resultado = await generarAgenda.ejecutar(
        rangoInicio: DateTime(2026, 7, 1),
        rangoFin: DateTime(2026, 7, 31),
      );

      expect(resultado.creados, hasLength(1), reason: 'el periodo 21/06-20/07 es prestación real');
      final documento = resultado.creados.single;
      expect(documento.periodoInicio, DateTime(2026, 6, 21));
      expect(documento.periodoFin, DateTime(2026, 7, 20));
      expect(documento.fechaEmisionProgramada, DateTime(2026, 7, 21));

      // Y lo mismo emitiéndolo DESPUÉS del cierre: el periodo
      // 21/07-20/08 contiene el 30/07, así que sigue siendo prestación
      // real y se emite el 21/08, con el Servicio ya terminado.
      final posterior = await generarAgenda.ejecutar(
        rangoInicio: DateTime(2026, 8, 1),
        rangoFin: DateTime(2026, 8, 31),
      );
      expect(posterior.creados, hasLength(1));
      expect(posterior.creados.single.fechaEmisionProgramada, DateTime(2026, 8, 21),
          reason: 'terminar el Servicio no cancela el derecho a emitir lo ya prestado');
    });

    test('5. Servicio que inicia DESPUÉS de que el periodo termina: no genera', () async {
      await crearServicioMesVencido(fechaInicio: DateTime(2026, 11, 1));

      final resultado = await generarAgenda.ejecutar(
        rangoInicio: DateTime(2026, 9, 1),
        rangoFin: DateTime(2026, 9, 30),
      );

      expect(resultado.creados, isEmpty);
    });

    test('7. una vigencia de cobro retroactiva no revive periodos posteriores al cierre', () async {
      final servicio = await crearServicioMesVencido(fechaInicio: DateTime(2026, 5, 1));

      // La vigencia nueva, retroactiva, cambia la `generationKey` de
      // periodos ya pasados. (Se registra antes de terminar porque el
      // dominio ya impide agregar vigencias a un Servicio terminado:
      // `CambiarVigenciaConfiguracionCobroServicioNoDisponible`.)
      final nueva = await cambiarVigencia.ejecutar(
        configuracionCobroId: (await configuracionRepo.listarConfiguraciones(servicioId: servicio)).single.id,
        borrador: ConfiguracionCobroBorrador(
          tipoDocumento: TipoDocumentoCobro.cfdi,
          frecuenciaId: SeedIds.frecuenciaCobroMensual,
          diaInicioPeriodo: 21,
          agrupacion: AgrupacionCobro.porServicio,
          metodo: MetodoPagoCobro.ppd,
          requiereComplemento: true,
          fechaInicioVigencia: DateTime(2026, 6, 1),
          entidadFiscalId: entidadFiscalId,
        ),
        etapas: [
          EtapaCobroBorrador(
            id: const Uuid().v4(),
            tipoSistema: TipoEventoCobro.emision,
            orden: 0,
            tipoRegla: TipoReglaEvento.diaFijoDelMes,
            mesRelativo: MesRelativoCobro.siguiente,
            diaDelMes: 21,
          ),
        ],
      );
      expect(nueva, isA<CambiarVigenciaConfiguracionCobroExitoso>());
      await terminar(servicio, DateTime(2026, 7, 30));

      final resultado = await generarAgenda.ejecutar(
        rangoInicio: DateTime(2026, 9, 1),
        rangoFin: DateTime(2026, 9, 30),
      );

      expect(resultado.creados, isEmpty, reason: 'la vigencia nueva no resucita al Servicio');
      expect(await periodosGenerados(), isEmpty);
    });

    test('8. regenerar varias veces sigue siendo idempotente, y el blindaje comercial sigue vivo', () async {
      final servicio = await crearServicioMesVencido(fechaInicio: DateTime(2026, 5, 1));
      await terminar(servicio, DateTime(2026, 7, 30));

      // El periodo legítimo se genera una sola vez...
      final primera = await generarAgenda.ejecutar(rangoInicio: DateTime(2026, 8, 1), rangoFin: DateTime(2026, 8, 31));
      expect(primera.creados, hasLength(1));
      final segunda = await generarAgenda.ejecutar(rangoInicio: DateTime(2026, 8, 1), rangoFin: DateTime(2026, 8, 31));
      expect(segunda.creados, isEmpty);
      expect(segunda.yaExistian, 1);

      // ...y la clave comercial sigue siendo la que decide, no la técnica.
      final documento = primera.creados.single;
      expect(
        claveComercialDeGenerationKey(documento.generationKey),
        isNot(documento.generationKey),
        reason: 'la clave comercial sí deja fuera el segmento de vigencia',
      );

      // Y los periodos posteriores al cierre siguen sin aparecer por
      // más veces que se pulse Generar.
      for (var i = 0; i < 3; i++) {
        await generarAgenda.ejecutar(rangoInicio: DateTime(2026, 9, 1), rangoFin: DateTime(2026, 9, 30));
      }
      expect(await periodosGenerados(), [
        (inicio: DateTime(2026, 7, 21), fin: DateTime(2026, 7, 30)),
      ], reason: 'el tramo realmente prestado, recortado al cierre, y una sola vez');
    });
  });

  // ---------------------------------------------------------------
  // Intersección parcial: el documento existe por el tramo realmente
  // prestado y se prorratea sobre él. El calendario de cobro (emisión,
  // pago esperado) sigue siendo el nominal.
  // ---------------------------------------------------------------
  group('Periodos que cruzan el inicio o el cierre', () {
    test('4. termina a mitad de periodo: genera el tramo hasta fechaTermino y lo prorratea', () async {
      // El caso de DOC-000029, ahora automático: cierre el 30/07 dentro
      // del periodo 21/07-20/08.
      final servicio = await crearServicioMesVencido(fechaInicio: DateTime(2026, 5, 1));
      await terminar(servicio, DateTime(2026, 7, 30));

      final resultado = await generarAgenda.ejecutar(
        rangoInicio: DateTime(2026, 8, 1),
        rangoFin: DateTime(2026, 8, 31),
      );

      expect(resultado.creados, hasLength(1));
      final documento = resultado.creados.single;
      expect(documento.periodoInicio, DateTime(2026, 7, 21));
      expect(documento.periodoFin, DateTime(2026, 7, 30), reason: 'recortado al cierre del Servicio');
      expect(documento.fechaEmisionProgramada, DateTime(2026, 8, 21),
          reason: 'el calendario de cobro es nominal: recortar el tramo no adelanta la emisión');

      final detalle = await documentoRepo.obtenerDetalle(documento.id);
      expect(detalle!.lineas.single.diasAplicables, 10, reason: '21 a 30 de julio, inclusive');
      // 15,675.00 x 10 dias x 2 elementos / 30 = 10,450.00 — el importe
      // exacto de DOC-000029 en la base real.
      expect(detalle.lineas.single.subtotalProporcional, 1045000);
      expect(documento.importeBaseEsperado, 1045000);
    });

    test('5. inicia a mitad de periodo: genera desde fechaInicio y prorratea', () async {
      await crearServicioMesVencido(fechaInicio: DateTime(2026, 9, 5));

      final resultado = await generarAgenda.ejecutar(
        rangoInicio: DateTime(2026, 9, 1),
        rangoFin: DateTime(2026, 9, 30),
      );

      expect(resultado.creados, hasLength(1));
      final documento = resultado.creados.single;
      expect(documento.periodoInicio, DateTime(2026, 9, 5));
      expect(documento.periodoFin, DateTime(2026, 9, 20));

      final detalle = await documentoRepo.obtenerDetalle(documento.id);
      expect(detalle!.lineas.single.diasAplicables, 16, reason: '5 a 20 de septiembre, inclusive');
      expect(detalle.lineas.single.subtotalProporcional, 1672000);
    });

    test('6. ciclo 21-20: tras el tramo parcial de alta, el siguiente periodo sale completo', () async {
      await crearServicioMesVencido(fechaInicio: DateTime(2026, 9, 5));

      final parcial = await generarAgenda.ejecutar(rangoInicio: DateTime(2026, 9, 1), rangoFin: DateTime(2026, 9, 30));
      expect(parcial.creados.single.periodoInicio, DateTime(2026, 9, 5));

      // Éste es el mes que ANTES se perdía por resolver la vigencia con
      // el día 1 del mes candidato.
      final completo = await generarAgenda.ejecutar(rangoInicio: DateTime(2026, 10, 1), rangoFin: DateTime(2026, 10, 31));
      expect(completo.creados, hasLength(1), reason: 'el primer periodo completo ya no se pierde');
      expect(completo.creados.single.periodoInicio, DateTime(2026, 9, 21));
      expect(completo.creados.single.periodoFin, DateTime(2026, 10, 20));

      final detalle = await documentoRepo.obtenerDetalle(completo.creados.single.id);
      expect(detalle!.lineas.single.diasAplicables, 30, reason: 'mes comercial completo');
    });

    test('9. inicia y termina DENTRO del mismo periodo: sólo la intersección', () async {
      final servicio = await crearServicioMesVencido(fechaInicio: DateTime(2026, 9, 5));
      await terminar(servicio, DateTime(2026, 9, 12));

      final resultado = await generarAgenda.ejecutar(
        rangoInicio: DateTime(2026, 9, 1),
        rangoFin: DateTime(2026, 9, 30),
      );

      expect(resultado.creados, hasLength(1));
      expect(resultado.creados.single.periodoInicio, DateTime(2026, 9, 5));
      expect(resultado.creados.single.periodoFin, DateTime(2026, 9, 12));
      final detalle = await documentoRepo.obtenerDetalle(resultado.creados.single.id);
      expect(detalle!.lineas.single.diasAplicables, 8);
    });

    test('10. un documento manual por el MISMO tramo efectivo impide el automático', () async {
      // El caso DOC-000029 al pie de la letra: ya existe capturado a
      // mano 21/07-30/07, y la lógica nueva calcula exactamente ese
      // mismo tramo. No puede nacer un segundo documento.
      final servicio = await crearServicioMesVencido(fechaInicio: DateTime(2026, 5, 1));
      await terminar(servicio, DateTime(2026, 7, 30));

      final manual = await crearManual.ejecutar(
        clienteId: clienteId,
        servicioIds: [servicio],
        periodoInicio: DateTime(2026, 7, 21),
        periodoFin: DateTime(2026, 7, 30),
        entidadFiscalId: entidadFiscalId,
      );
      expect(manual, isA<CrearDocumentoManualExitoso>());

      final resultado = await generarAgenda.ejecutar(
        rangoInicio: DateTime(2026, 8, 1),
        rangoFin: DateTime(2026, 8, 31),
      );

      expect(resultado.creados, isEmpty, reason: 'la equivalencia comercial lo reconoce por periodo efectivo');
      expect(resultado.yaExistian, 1);
      expect(await periodosGenerados(), hasLength(1));
    });

    test('11. un documento histórico ya PROCESADO no se reescribe al cambiar el Servicio', () async {
      final servicio = await crearServicioMesVencido(fechaInicio: DateTime(2026, 5, 1));
      final documento = (await generarAgenda.ejecutar(
        rangoInicio: DateTime(2026, 8, 1),
        rangoFin: DateTime(2026, 8, 31),
      ))
          .creados
          .single;
      await registrarEmision.ejecutar(
        documentoPorEmitirId: documento.id,
        folioDocumento: 'A-001',
        uuid: '11111111-1111-1111-1111-111111111111',
        fechaEmisionReal: DateTime(2026, 8, 21),
        importeEmitido: 3654000,
      );
      await cambiarEstatusDocumento.ejecutar(
        documentoPorEmitirId: documento.id,
        nuevo: EstatusDocumentoPorEmitir.procesadoAceptado,
      );
      final antes = await documentoRepo.obtenerPorId(documento.id);

      // Ahora se cierra el Servicio ANTES de ese periodo ya facturado.
      await terminar(servicio, DateTime(2026, 5, 31));
      await generarAgenda.ejecutar(rangoInicio: DateTime(2026, 8, 1), rangoFin: DateTime(2026, 8, 31));

      final despues = await documentoRepo.obtenerPorId(documento.id);
      expect(despues!.periodoInicio, antes!.periodoInicio);
      expect(despues.periodoFin, antes.periodoFin);
      expect(despues.estatus, 'procesadoAceptado');
      expect(despues.importeEmitido, 3654000);
      expect(despues.importeBaseEsperado, antes.importeBaseEsperado);
      expect(await periodosGenerados(), hasLength(1), reason: 'tampoco nace un documento nuevo');
    });

    test('12. una vigencia de cobro que termina a mitad recorta el tramo', () async {
      // La vigencia vieja se cierra el 09/09 porque arranca otra el 10.
      final servicio = await crearServicioMesVencido(fechaInicio: DateTime(2026, 5, 1));
      final configuracionId = (await configuracionRepo.listarConfiguraciones(servicioId: servicio)).single.id;
      final nueva = await cambiarVigencia.ejecutar(
        configuracionCobroId: configuracionId,
        borrador: ConfiguracionCobroBorrador(
          tipoDocumento: TipoDocumentoCobro.cfdi,
          frecuenciaId: SeedIds.frecuenciaCobroMensual,
          diaInicioPeriodo: 21,
          agrupacion: AgrupacionCobro.porServicio,
          metodo: MetodoPagoCobro.ppd,
          requiereComplemento: true,
          fechaInicioVigencia: DateTime(2026, 9, 10),
          entidadFiscalId: entidadFiscalId,
        ),
        etapas: [
          EtapaCobroBorrador(
            id: const Uuid().v4(),
            tipoSistema: TipoEventoCobro.emision,
            orden: 0,
            tipoRegla: TipoReglaEvento.diaFijoDelMes,
            mesRelativo: MesRelativoCobro.siguiente,
            diaDelMes: 21,
          ),
        ],
      );
      expect(nueva, isA<CambiarVigenciaConfiguracionCobroExitoso>());

      final resultado = await generarAgenda.ejecutar(
        rangoInicio: DateTime(2026, 9, 1),
        rangoFin: DateTime(2026, 9, 30),
      );

      // El periodo 21/08-20/09 queda gobernado por la vigencia vieja
      // (la que cubre el 21/08) y se recorta donde ésta termina.
      expect(resultado.creados, hasLength(1));
      expect(resultado.creados.single.periodoInicio, DateTime(2026, 8, 21));
      expect(resultado.creados.single.periodoFin, DateTime(2026, 9, 9));
    });
  });
}
