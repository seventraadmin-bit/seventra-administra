import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_regla_evento_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/documento_por_emitir_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/actualizar_ajuste_manual_documento_por_emitir_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_estatus_documento_por_emitir_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_regla_evento_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_configuracion_cobro_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_documento_manual_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_servicio_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart';
import 'package:riseg_one/features/organizacion/presentation/agenda/agenda_controller.dart';

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

    container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
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
    List<ReglaEventoBorrador> reglas = const [],
    AgrupacionCobro agrupacion = AgrupacionCobro.porServicio,
  }) async {
    final entidadFiscalRepo = container.read(entidadFiscalRepositoryProvider);
    final comercialRepo = container.read(servicioComercialRepositoryProvider);
    final servicioRepo = container.read(servicioRepositoryProvider);
    final configuracionCobroRepo = container.read(configuracionCobroRepositoryProvider);
    final catalogoRepo = container.read(catalogoRepositoryProvider);
    final validator = ConfiguracionCobroValidator(servicioRepo, entidadFiscalRepo, catalogoRepo, comercialRepo);
    final crearConfiguracionCobro = CrearConfiguracionCobroUseCase(
      configuracionCobroRepo,
      servicioRepo,
      validator,
      const ConfiguracionCobroReglaEventoValidator(),
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
      reglas: reglas,
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
      reglas: [
        ReglaEventoBorrador(
          tipoEvento: TipoEventoCobro.emision,
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
