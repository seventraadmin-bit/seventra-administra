import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_etapa_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/documento_por_emitir_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/actualizar_ajuste_manual_documento_por_emitir_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_estatus_documento_por_emitir_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_etapa_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_configuracion_cobro_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/corregir_ajuste_historico_documento_por_emitir_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_documento_manual_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_servicio_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart';
import 'package:riseg_one/features/organizacion/presentation/agenda/agenda_controller.dart';
import 'package:riseg_one/features/organizacion/presentation/agenda/agenda_resumen_periodo.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

/// Sesión Maestro fija — Etapa 11C activó autorización real en
/// `AgendaController`; sin este override todas las acciones serían
/// rechazadas por `AuthorizationService` (mismo criterio que
/// `areas_list_screen_test.dart`).
class _SesionControllerDePrueba extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-prueba',
      nombre: 'Usuario de prueba',
      nombreUsuario: 'prueba',
      esMaestro: true,
      permisos: {},
    );
  }
}

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late String clienteId;
  late String servicioId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());

    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    final clienteRepo = ClienteRepositoryImpl(db);
    final servicioRepo = ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db));
    final catalogoRepo = CatalogoRepositoryImpl(db);
    final servicioValidator = ServicioValidator(clienteRepo, catalogoRepo);
    final crearServicio = CrearServicioUseCase(servicioRepo, generarCodigo, servicioValidator);

    final cliente = await clienteRepo.crear(ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Morgan'));
    clienteId = cliente.id;
    final servicioCreado = await crearServicio.ejecutar(
      clienteId: clienteId,
      borrador: ServicioBorrador(
        nombre: 'Vigilancia Morgan',
        tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
        fechaInicio: DateTime(2026, 1, 1),
      ),
    );
    servicioId = (servicioCreado as GuardarServicioExitoso).servicio.id;

    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionControllerDePrueba.new),
        // `documentoPorEmitirRepositoryProvider` ahora depende de
        // `attachmentStorageProvider` (Etapa 15, eliminación física
        // ampliada) — se sobreescribe directo para no necesitar
        // `appPathsProvider` (requiere `path_provider`).
        attachmentStorageProvider.overrideWithValue(AttachmentStorage('.')),
      ],
    );
    addTearDown(container.dispose);
    container.listen(agendaControllerProvider, (_, _) {});
  });

  tearDown(() => db.close());

  Future<void> esperarCarga() async {
    while (container.read(agendaControllerProvider).cargando) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<String> crearConfiguracionCobroConReglas({
    List<EtapaCobroBorrador> etapas = const [],
    AgrupacionCobro agrupacion = AgrupacionCobro.porServicio,
  }) async {
    final entidadFiscalRepo = container.read(entidadFiscalRepositoryProvider);
    final clientePortalRepo = container.read(clientePortalRepositoryProvider);
    final comercialRepo = container.read(servicioComercialRepositoryProvider);
    final servicioRepo = container.read(servicioRepositoryProvider);
    final configuracionCobroRepo = container.read(configuracionCobroRepositoryProvider);
    final catalogoRepo = container.read(catalogoRepositoryProvider);
    final validator =
        ConfiguracionCobroValidator(servicioRepo, entidadFiscalRepo, catalogoRepo, comercialRepo, clientePortalRepo);
    final crearConfiguracionCobro = CrearConfiguracionCobroUseCase(
      configuracionCobroRepo,
      servicioRepo,
      validator,
      const ConfiguracionCobroEtapaValidator(),
    );

    final resultado = await crearConfiguracionCobro.ejecutar(
      servicioId: servicioId,
      borrador: ConfiguracionCobroBorrador(
        tipoDocumento: TipoDocumentoCobro.reciboDePago,
        frecuenciaId: SeedIds.frecuenciaCobroMensual,
        diaInicioPeriodo: 1,
        agrupacion: agrupacion,
        metodo: MetodoPagoCobro.noAplica,
        requiereComplemento: false,
        fechaInicioVigencia: DateTime(2026, 1, 1),
      ),
      etapas: etapas,
    );
    return (resultado as CrearConfiguracionCobroExitoso).configuracion.id;
  }

  test('carga inicial usa el mes calendario actual como rango por defecto', () async {
    await esperarCarga();
    final ahora = DateTime.now();
    final state = container.read(agendaControllerProvider);

    expect(state.errorCarga, isNull);
    expect(state.documentos, isEmpty);
    expect(state.rangoInicio, DateTime(ahora.year, ahora.month, 1));
  });

  test('generar crea documentos para el rango filtrado y recarga la lista', () async {
    await esperarCarga();
    await crearConfiguracionCobroConReglas(
      etapas: [
        EtapaCobroBorrador(
          id: 'etapa-emision',
          tipoSistema: TipoEventoCobro.emision,
          orden: 0,
          tipoRegla: TipoReglaEvento.diaFijoDelMes,
          mesRelativo: MesRelativoCobro.actual,
          diaDelMes: 1,
        ),
      ],
    );

    final notifier = container.read(agendaControllerProvider.notifier);
    await notifier.aplicarFiltros(rangoInicio: DateTime(2026, 1, 1), rangoFin: DateTime(2026, 1, 31));

    final resultado = await notifier.generar();
    expect(resultado!.creados, hasLength(1));

    final state = container.read(agendaControllerProvider);
    expect(state.documentos, hasLength(1));
    expect(state.documentos.single.clienteId, clienteId);
  });

  test('generar sin resultados no crea documentos ni falla', () async {
    await esperarCarga();
    await crearConfiguracionCobroConReglas(); // sin reglas: Mirabilia-like.

    final notifier = container.read(agendaControllerProvider.notifier);
    await notifier.aplicarFiltros(rangoInicio: DateTime(2026, 1, 1), rangoFin: DateTime(2026, 1, 31));
    final resultado = await notifier.generar();

    expect(resultado!.creados, isEmpty);
    expect(container.read(agendaControllerProvider).documentos, isEmpty);
  });

  test('crearManual crea un documento para un Servicio sin regla de emisión calculable', () async {
    await esperarCarga();
    await crearConfiguracionCobroConReglas(); // sin reglas.

    final notifier = container.read(agendaControllerProvider.notifier);
    await notifier.aplicarFiltros(rangoInicio: DateTime(2026, 1, 1), rangoFin: DateTime(2026, 1, 31));

    final resultado = await notifier.crearManual(
      clienteId: clienteId,
      servicioIds: [servicioId],
      periodoInicio: DateTime(2026, 1, 1),
      periodoFin: DateTime(2026, 1, 31),
    );

    expect(resultado, isA<CrearDocumentoManualExitoso>());
    expect(container.read(agendaControllerProvider).documentos, hasLength(1));
  });

  test('cambiarEstatus actualiza el documento y refleja el nuevo estatus tras recargar', () async {
    await esperarCarga();
    await crearConfiguracionCobroConReglas();
    final notifier = container.read(agendaControllerProvider.notifier);
    await notifier.aplicarFiltros(rangoInicio: DateTime(2026, 1, 1), rangoFin: DateTime(2026, 1, 31));
    final creado = await notifier.crearManual(
      clienteId: clienteId,
      servicioIds: [servicioId],
      periodoInicio: DateTime(2026, 1, 1),
      periodoFin: DateTime(2026, 1, 31),
    );
    final documentoId = (creado as CrearDocumentoManualExitoso).documento.id;

    final resultado = await notifier.cambiarEstatus(
      documentoPorEmitirId: documentoId,
      nuevo: EstatusDocumentoPorEmitir.enPreparacion,
    );

    expect(resultado, isA<CambiarEstatusDocumentoPorEmitirExitoso>());
    final state = container.read(agendaControllerProvider);
    expect(state.documentos.single.estatus, 'enPreparacion');
  });

  test('actualizarAjusteManual actualiza el importe final tras recargar', () async {
    await esperarCarga();
    await crearConfiguracionCobroConReglas();
    final notifier = container.read(agendaControllerProvider.notifier);
    await notifier.aplicarFiltros(rangoInicio: DateTime(2026, 1, 1), rangoFin: DateTime(2026, 1, 31));
    final creado = await notifier.crearManual(
      clienteId: clienteId,
      servicioIds: [servicioId],
      periodoInicio: DateTime(2026, 1, 1),
      periodoFin: DateTime(2026, 1, 31),
    );
    final documento = (creado as CrearDocumentoManualExitoso).documento;
    expect(documento.importeBaseEsperado, 0, reason: 'sin línea comercial, el importe base es cero');

    final resultado = await notifier.actualizarAjusteManual(
      documentoPorEmitirId: documento.id,
      ajusteManual: 50000,
      motivoAjuste: 'Cargo adicional acordado',
    );

    expect(resultado, isA<ActualizarAjusteManualDocumentoPorEmitirExitoso>());
    final state = container.read(agendaControllerProvider);
    expect(state.documentos.single.importeFinalEsperado, 50000);
  });

  test('corregir el ajuste histórico actualiza la Agenda en el mismo contenedor, sin navegar', () async {
    await esperarCarga();
    await crearConfiguracionCobroConReglas();
    // La corrección histórica SÍ registra al actor, así que el usuario de la
    // sesión tiene que existir de verdad (en producción siempre existe).
    await db.into(db.usuario).insert(
      UsuarioCompanion.insert(
        id: const Value("usuario-prueba"),
        nombre: "Usuario de prueba",
        nombreUsuario: "prueba",
        passwordHash: "x",
      ),
    );
    final notifier = container.read(agendaControllerProvider.notifier);
    await notifier.aplicarFiltros(rangoInicio: DateTime(2026, 1, 1), rangoFin: DateTime(2026, 1, 31));
    final creado = await notifier.crearManual(
      clienteId: clienteId,
      servicioIds: [servicioId],
      periodoInicio: DateTime(2026, 1, 1),
      periodoFin: DateTime(2026, 1, 31),
    );
    final documento = (creado as CrearDocumentoManualExitoso).documento;

    await notifier.registrarEmision(
      documentoPorEmitirId: documento.id,
      folioDocumento: 'A-001',
      fechaEmisionReal: DateTime(2026, 2, 5),
      importeEmitido: 2002934,
    );

    // Emitido: el camino normal ya está cerrado.
    final bloqueado = await notifier.actualizarAjusteManual(
      documentoPorEmitirId: documento.id,
      ajusteManual: 123333,
      motivoAjuste: 'Cargo adicional acordado',
    );
    expect(bloqueado, isA<ActualizarAjusteManualDocumentoPorEmitirCongelado>());

    final corregido = await notifier.corregirAjusteHistorico(
      documentoPorEmitirId: documento.id,
      motivoCorreccion: 'Capturado antes de que existiera la regla',
      ajusteManual: 123333,
      motivoAjuste: 'Cargo adicional acordado',
    );
    expect(corregido, isA<CorregirAjusteHistoricoDocumentoPorEmitirExitoso>());

    // Sin invalidar a mano y sin reconstruir el contenedor: el renglón de
    // la Agenda ya trae el importe facturable esperado nuevo.
    final state = container.read(agendaControllerProvider);
    expect(state.documentos.single.ajusteManual, 123333);
    expect(
      state.documentos.single.importeFinalEsperado,
      state.documentos.single.importeBaseEsperado + 123333,
    );
    expect(
      state.documentos.single.importeEmitido,
      2002934,
      reason: 'la corrección comercial no tocó lo que realmente se emitió',
    );

    // La columna de la Agenda: el total esperado del renglón, recalculado
    // en la misma carga. Sin líneas comerciales el documento es `noAplica`,
    // así que su total es el facturable, sin IVA inventado.
    expect(state.totalEsperadoPorDocumento[documento.id], 123333);

    // Y el KPI del periodo, que suma esos totales.
    final resumen = calcularResumenPeriodoAgenda(
      state.documentos,
      DateTime(2026, 1, 15),
      totalEsperadoPorDocumento: state.totalEsperadoPorDocumento,
    );
    expect(resumen.importeEsperado, 123333);
    expect(resumen.documentosSinTotalCalculable, 0);
  });

  test('el agregado sigue al filtro de periodo: fuera del rango no suma', () async {
    await esperarCarga();
    await crearConfiguracionCobroConReglas();
    final notifier = container.read(agendaControllerProvider.notifier);
    await notifier.aplicarFiltros(rangoInicio: DateTime(2026, 1, 1), rangoFin: DateTime(2026, 1, 31));
    final creado = await notifier.crearManual(
      clienteId: clienteId,
      servicioIds: [servicioId],
      periodoInicio: DateTime(2026, 1, 1),
      periodoFin: DateTime(2026, 1, 31),
    );
    final documento = (creado as CrearDocumentoManualExitoso).documento;
    await notifier.actualizarAjusteManual(
      documentoPorEmitirId: documento.id,
      ajusteManual: 50000,
      motivoAjuste: 'Cargo adicional acordado',
    );

    var state = container.read(agendaControllerProvider);
    expect(state.totalEsperadoPorDocumento[documento.id], 50000);
    expect(
      calcularResumenPeriodoAgenda(
        state.documentos,
        DateTime(2026, 1, 15),
        totalEsperadoPorDocumento: state.totalEsperadoPorDocumento,
      ).importeEsperado,
      50000,
    );

    // Mismo dato, otro periodo: el documento sale de la vista y el
    // agregado baja con él, sin quedarse con totales huérfanos.
    await notifier.aplicarFiltros(rangoInicio: DateTime(2026, 6, 1), rangoFin: DateTime(2026, 6, 30));

    state = container.read(agendaControllerProvider);
    expect(state.documentos, isEmpty);
    expect(state.totalEsperadoPorDocumento, isEmpty);
    expect(
      calcularResumenPeriodoAgenda(
        state.documentos,
        DateTime(2026, 6, 15),
        totalEsperadoPorDocumento: state.totalEsperadoPorDocumento,
      ).importeEsperado,
      0,
    );
  });

  test('obtenerDetalle regresa el expediente completo del documento', () async {
    await esperarCarga();
    await crearConfiguracionCobroConReglas();
    final notifier = container.read(agendaControllerProvider.notifier);
    final creado = await notifier.crearManual(
      clienteId: clienteId,
      servicioIds: [servicioId],
      periodoInicio: DateTime(2026, 1, 1),
      periodoFin: DateTime(2026, 1, 31),
    );
    final documentoId = (creado as CrearDocumentoManualExitoso).documento.id;

    final detalle = await notifier.obtenerDetalle(documentoId);

    expect(detalle, isNotNull);
    expect(detalle!.servicioIds, [servicioId]);
  });

  test('aplicarFiltros con limpiarClienteId quita el filtro de Cliente y recarga', () async {
    await esperarCarga();
    final notifier = container.read(agendaControllerProvider.notifier);

    await notifier.aplicarFiltros(clienteId: clienteId);
    expect(container.read(agendaControllerProvider).clienteId, clienteId);

    await notifier.aplicarFiltros(limpiarClienteId: true);
    expect(container.read(agendaControllerProvider).clienteId, isNull);
  });
}
