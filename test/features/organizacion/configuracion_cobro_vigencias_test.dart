import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/utils/clock.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/configuracion_cobro_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_portal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/entidad_fiscal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_comercial_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_etapa_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/actualizar_observaciones_configuracion_cobro_vigencia_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_vigencia_configuracion_cobro_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cancelar_vigencia_programada_configuracion_cobro_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cerrar_configuracion_cobro_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_con_vigencia.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_etapa_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_configuracion_cobro_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_servicio_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/obtener_historial_configuracion_cobro_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';

class _RelojFijo implements Clock {
  _RelojFijo(this._fecha);
  final DateTime _fecha;

  @override
  DateTime now() => _fecha;
}

void main() {
  late AppDatabase db;
  late ClienteRepositoryImpl clienteRepo;
  late ServicioRepositoryImpl servicioRepo;
  late ConfiguracionCobroRepositoryImpl configuracionCobroRepo;
  late CrearServicioUseCase crearServicio;

  final hoy = DateTime(2026, 8, 15);
  late Clock clock;
  late CrearConfiguracionCobroUseCase crearConfiguracionCobro;
  late CambiarVigenciaConfiguracionCobroUseCase cambiarVigencia;
  late CerrarConfiguracionCobroUseCase cerrarConfiguracionCobro;
  late CancelarVigenciaProgramadaConfiguracionCobroUseCase cancelarProgramada;
  late ActualizarObservacionesConfiguracionCobroVigenciaUseCase actualizarObservaciones;
  late ObtenerHistorialConfiguracionCobroUseCase obtenerHistorial;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    clienteRepo = ClienteRepositoryImpl(db);
    servicioRepo = ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db));
    final catalogoRepo = CatalogoRepositoryImpl(db);
    final entidadFiscalRepo = EntidadFiscalRepositoryImpl(db);
    final clientePortalRepo = ClientePortalRepositoryImpl(db);
    final comercialRepo = ServicioComercialRepositoryImpl(db);
    clock = _RelojFijo(hoy);
    configuracionCobroRepo = ConfiguracionCobroRepositoryImpl(db, clock: clock);
    final servicioValidator = ServicioValidator(clienteRepo, catalogoRepo);
    final configuracionCobroValidator =
        ConfiguracionCobroValidator(servicioRepo, entidadFiscalRepo, catalogoRepo, comercialRepo, clientePortalRepo);
    const reglaValidator = ConfiguracionCobroEtapaValidator();

    crearServicio = CrearServicioUseCase(servicioRepo, generarCodigo, servicioValidator);
    crearConfiguracionCobro =
        CrearConfiguracionCobroUseCase(configuracionCobroRepo, servicioRepo, configuracionCobroValidator, reglaValidator);
    cambiarVigencia = CambiarVigenciaConfiguracionCobroUseCase(
      configuracionCobroRepo,
      servicioRepo,
      configuracionCobroValidator,
      reglaValidator,
    );
    cerrarConfiguracionCobro = CerrarConfiguracionCobroUseCase(configuracionCobroRepo, clock);
    cancelarProgramada = CancelarVigenciaProgramadaConfiguracionCobroUseCase(configuracionCobroRepo, clock);
    actualizarObservaciones = ActualizarObservacionesConfiguracionCobroVigenciaUseCase(configuracionCobroRepo, clock);
    obtenerHistorial =
        ObtenerHistorialConfiguracionCobroUseCase(configuracionCobroRepo, entidadFiscalRepo, catalogoRepo, clock);
  });

  tearDown(() => db.close());

  Future<ClienteData> crearClienteDePrueba({String codigo = 'CLI-000001', String nombre = 'Sportium'}) {
    return clienteRepo.crear(ClienteCompanion.insert(codigo: codigo, nombreComercial: nombre));
  }

  Future<ServicioData> crearServicioDePrueba(String clienteId) async {
    final creado = await crearServicio.ejecutar(
      clienteId: clienteId,
      borrador: ServicioBorrador(
        nombre: 'Vigilancia Sportium Toluca',
        tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
        fechaInicio: DateTime(2026, 1, 1),
      ),
    );
    return (creado as GuardarServicioExitoso).servicio;
  }

  Future<String> crearConfiguracionCobroDePrueba(String servicioId, {DateTime? fechaInicioVigencia}) async {
    final resultado = await crearConfiguracionCobro.ejecutar(
      servicioId: servicioId,
      borrador: ConfiguracionCobroBorrador(
        tipoDocumento: TipoDocumentoCobro.reciboDePago,
        frecuenciaId: SeedIds.frecuenciaCobroMensual,
        diaInicioPeriodo: 1,
        agrupacion: AgrupacionCobro.porServicio,
        metodo: MetodoPagoCobro.noAplica,
        requiereComplemento: false,
        fechaInicioVigencia: fechaInicioVigencia ?? DateTime(2026, 1, 1),
      ),
    );
    return (resultado as CrearConfiguracionCobroExitoso).configuracion.id;
  }

  group('Nueva vigencia (Resolución A, mismo algoritmo de 4G.2)', () {
    test('reemplaza la vigente actual cuando la fecha efectiva es hoy', () async {
      final cliente = await crearClienteDePrueba();
      final servicio = await crearServicioDePrueba(cliente.id);
      final configuracionCobroId = await crearConfiguracionCobroDePrueba(servicio.id);

      final resultado = await cambiarVigencia.ejecutar(
        configuracionCobroId: configuracionCobroId,
        borrador: ConfiguracionCobroBorrador(
          tipoDocumento: TipoDocumentoCobro.reciboDePago,
          frecuenciaId: SeedIds.frecuenciaCobroMensual,
          diaInicioPeriodo: 1,
          agrupacion: AgrupacionCobro.porServicio,
          metodo: MetodoPagoCobro.noAplica,
          requiereComplemento: false,
          fechaInicioVigencia: hoy,
        ),
      );

      expect(resultado, isA<CambiarVigenciaConfiguracionCobroExitoso>());
      final configuracion = await configuracionCobroRepo.obtenerConfiguracion(servicio.id);
      expect(configuracion!.vigenciaActual, isNotNull);
      expect(configuracion.vigenciaActual!.fechaInicioVigencia, hoy);

      final historial = await obtenerHistorial.ejecutar(configuracionCobroId);
      expect(historial, hasLength(2));
      expect(historial.where((h) => h.estado == EstadoVigenciaCobro.historica), hasLength(1));
      expect(historial.where((h) => h.estado == EstadoVigenciaCobro.vigente), hasLength(1));
    });

    test('queda programada cuando la fecha efectiva es futura, sin sustituir la vigente actual', () async {
      final cliente = await crearClienteDePrueba();
      final servicio = await crearServicioDePrueba(cliente.id);
      final configuracionCobroId = await crearConfiguracionCobroDePrueba(servicio.id);
      final enUnAnio = hoy.add(const Duration(days: 365));

      final resultado = await cambiarVigencia.ejecutar(
        configuracionCobroId: configuracionCobroId,
        borrador: ConfiguracionCobroBorrador(
          tipoDocumento: TipoDocumentoCobro.reciboDePago,
          frecuenciaId: SeedIds.frecuenciaCobroMensual,
          diaInicioPeriodo: 1,
          agrupacion: AgrupacionCobro.porServicio,
          metodo: MetodoPagoCobro.noAplica,
          requiereComplemento: false,
          fechaInicioVigencia: enUnAnio,
        ),
      );

      expect(resultado, isA<CambiarVigenciaConfiguracionCobroExitoso>());
      final configuracion = await configuracionCobroRepo.obtenerConfiguracion(servicio.id);
      expect(configuracion!.vigenciasProgramadas, hasLength(1));
      expect(configuracion.vigenciaActual, isNotNull, reason: 'la vigencia original sigue vigente hasta esa fecha');
    });

    test('rechaza dos vigencias con la misma fecha de inicio', () async {
      final cliente = await crearClienteDePrueba();
      final servicio = await crearServicioDePrueba(cliente.id);
      final configuracionCobroId = await crearConfiguracionCobroDePrueba(servicio.id, fechaInicioVigencia: DateTime(2026, 1, 1));

      final resultado = await cambiarVigencia.ejecutar(
        configuracionCobroId: configuracionCobroId,
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

      expect(resultado, isA<CambiarVigenciaConfiguracionCobroErroresValidacion>());
    });

    test('las reglas temporales de la vigencia anterior nunca se editan in place: cambiarlas exige una nueva vigencia', () async {
      final cliente = await crearClienteDePrueba();
      final servicio = await crearServicioDePrueba(cliente.id);
      final configuracionCobroId = await crearConfiguracionCobro.ejecutar(
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
        etapas: const [
          EtapaCobroBorrador(
            id: 'etapa-pago-anterior',
            tipoSistema: TipoEventoCobro.pagoEsperado,
            orden: 0,
            tipoRegla: TipoReglaEvento.diaFijoDelMes,
            mesRelativo: MesRelativoCobro.actual,
            diaDelMes: 10,
          ),
        ],
      ).then((r) => (r as CrearConfiguracionCobroExitoso).configuracion.id);

      final resultado = await cambiarVigencia.ejecutar(
        configuracionCobroId: configuracionCobroId,
        borrador: ConfiguracionCobroBorrador(
          tipoDocumento: TipoDocumentoCobro.reciboDePago,
          frecuenciaId: SeedIds.frecuenciaCobroMensual,
          diaInicioPeriodo: 1,
          agrupacion: AgrupacionCobro.porServicio,
          metodo: MetodoPagoCobro.noAplica,
          requiereComplemento: false,
          fechaInicioVigencia: hoy,
        ),
        etapas: const [
          EtapaCobroBorrador(
            id: 'etapa-pago-nueva',
            tipoSistema: TipoEventoCobro.pagoEsperado,
            orden: 0,
            tipoRegla: TipoReglaEvento.diaFijoDelMes,
            mesRelativo: MesRelativoCobro.actual,
            diaDelMes: 20,
          ),
        ],
      );
      expect(resultado, isA<CambiarVigenciaConfiguracionCobroExitoso>());

      final historial = await obtenerHistorial.ejecutar(configuracionCobroId);
      final historica = historial.firstWhere((h) => h.estado == EstadoVigenciaCobro.historica);
      final vigente = historial.firstWhere((h) => h.estado == EstadoVigenciaCobro.vigente);
      expect(historica.etapas.single.diaDelMes, 10, reason: 'la etapa histórica nunca cambia retroactivamente');
      expect(vigente.etapas.single.diaDelMes, 20);
    });
  });

  group('Cerrar sin reemplazo', () {
    test('cierra la vigente actual y la configuración queda sin condición vigente', () async {
      final cliente = await crearClienteDePrueba();
      final servicio = await crearServicioDePrueba(cliente.id);
      final configuracionCobroId = await crearConfiguracionCobroDePrueba(servicio.id);

      final resultado = await cerrarConfiguracionCobro.ejecutar(
        configuracionCobroId: configuracionCobroId,
        fechaEfectiva: hoy,
        motivo: 'Motivo de prueba',
      );

      expect(resultado, isA<CerrarConfiguracionCobroExitoso>());

      // `fechaFinVigencia` es inclusiva (mismo criterio que 4G.2): el
      // día efectivo de cierre todavía cuenta como vigente; solo al día
      // siguiente la configuración pasa a "sin condición vigente".
      final configuracionHoy = await configuracionCobroRepo.obtenerConfiguracion(servicio.id);
      expect(configuracionHoy!.vigenciaActual?.fechaFinVigencia, hoy);

      final repoManana = ConfiguracionCobroRepositoryImpl(db, clock: _RelojFijo(hoy.add(const Duration(days: 1))));
      final configuracionManana = await repoManana.obtenerConfiguracion(servicio.id);
      expect(configuracionManana!.vigenciaActual, isNull);
      expect(configuracionManana.vigenciasProgramadas, isEmpty);
    });

    test('rechaza cerrar si ya existe una vigencia programada', () async {
      final cliente = await crearClienteDePrueba();
      final servicio = await crearServicioDePrueba(cliente.id);
      final configuracionCobroId = await crearConfiguracionCobroDePrueba(servicio.id);
      await cambiarVigencia.ejecutar(
        configuracionCobroId: configuracionCobroId,
        borrador: ConfiguracionCobroBorrador(
          tipoDocumento: TipoDocumentoCobro.reciboDePago,
          frecuenciaId: SeedIds.frecuenciaCobroMensual,
          diaInicioPeriodo: 1,
          agrupacion: AgrupacionCobro.porServicio,
          metodo: MetodoPagoCobro.noAplica,
          requiereComplemento: false,
          fechaInicioVigencia: hoy.add(const Duration(days: 365)),
        ),
      );

      final resultado = await cerrarConfiguracionCobro.ejecutar(
        configuracionCobroId: configuracionCobroId,
        fechaEfectiva: hoy,
        motivo: 'Motivo de prueba',
      );

      expect(resultado, isA<CerrarConfiguracionCobroTieneVigenciaProgramada>());
    });

    test('rechaza cerrar si no hay condición vigente', () async {
      final cliente = await crearClienteDePrueba();
      final servicio = await crearServicioDePrueba(cliente.id);
      final configuracionCobroId = await crearConfiguracionCobroDePrueba(servicio.id);
      await cerrarConfiguracionCobro.ejecutar(configuracionCobroId: configuracionCobroId, fechaEfectiva: hoy, motivo: 'Motivo de prueba');

      // El cierre de arriba solo se refleja "sin condición vigente" a
      // partir del día siguiente (fechaFinVigencia es inclusiva).
      final manana = hoy.add(const Duration(days: 1));
      final cerrarManana = CerrarConfiguracionCobroUseCase(configuracionCobroRepo, _RelojFijo(manana));
      final resultado = await cerrarManana.ejecutar(
        configuracionCobroId: configuracionCobroId,
        fechaEfectiva: manana,
        motivo: 'Motivo de prueba',
      );

      expect(resultado, isA<CerrarConfiguracionCobroSinCondicionVigente>());
    });
  });

  group('Cancelar vigencia programada (Resolución F de 4G.2, aplicada igual aquí)', () {
    test('cancela y repara la predecesora, restaurando su fechaFinVigencia original', () async {
      final cliente = await crearClienteDePrueba();
      final servicio = await crearServicioDePrueba(cliente.id);
      final configuracionCobroId = await crearConfiguracionCobroDePrueba(servicio.id);
      final creada = await cambiarVigencia.ejecutar(
        configuracionCobroId: configuracionCobroId,
        borrador: ConfiguracionCobroBorrador(
          tipoDocumento: TipoDocumentoCobro.reciboDePago,
          frecuenciaId: SeedIds.frecuenciaCobroMensual,
          diaInicioPeriodo: 1,
          agrupacion: AgrupacionCobro.porServicio,
          metodo: MetodoPagoCobro.noAplica,
          requiereComplemento: false,
          fechaInicioVigencia: hoy.add(const Duration(days: 365)),
        ),
      );
      final programadaId = (creada as CambiarVigenciaConfiguracionCobroExitoso).vigencia.id;

      final resultado = await cancelarProgramada.ejecutar(vigenciaId: programadaId, motivo: 'Motivo de prueba');
      expect(resultado, isA<CancelarVigenciaProgramadaConfiguracionCobroExitoso>());

      final configuracion = await configuracionCobroRepo.obtenerConfiguracion(servicio.id);
      expect(configuracion!.vigenciasProgramadas, isEmpty);
      expect(configuracion.vigenciaActual, isNotNull);
      expect(configuracion.vigenciaActual!.fechaFinVigencia, isNull, reason: 'se restaura como si la programada nunca hubiera existido');
    });

    test('rechaza cancelar una vigencia que ya no está programada', () async {
      final cliente = await crearClienteDePrueba();
      final servicio = await crearServicioDePrueba(cliente.id);
      await crearConfiguracionCobroDePrueba(servicio.id);
      final configuracion = await configuracionCobroRepo.obtenerConfiguracion(servicio.id);

      final resultado = await cancelarProgramada.ejecutar(vigenciaId: configuracion!.vigenciaActual!.id, motivo: 'Motivo de prueba');

      expect(resultado, isA<CancelarVigenciaProgramadaConfiguracionCobroNoEsProgramada>());
    });
  });

  group('Actualizar observaciones sin crear nueva vigencia', () {
    test('edita observaciones sobre la vigente actual', () async {
      final cliente = await crearClienteDePrueba();
      final servicio = await crearServicioDePrueba(cliente.id);
      final configuracionCobroId = await crearConfiguracionCobroDePrueba(servicio.id);
      final configuracionAntes = await configuracionCobroRepo.obtenerConfiguracion(servicio.id);
      final vigenciaId = configuracionAntes!.vigenciaActual!.id;

      final resultado = await actualizarObservaciones.ejecutar(
        vigenciaId: vigenciaId,
        observaciones: 'Cliente confirmó condiciones por correo',
      );

      expect(resultado, isA<ActualizarObservacionesConfiguracionCobroVigenciaExitoso>());
      final configuracionDespues = await configuracionCobroRepo.obtenerConfiguracion(servicio.id);
      expect(configuracionDespues!.vigenciaActual!.observaciones, 'Cliente confirmó condiciones por correo');
      expect(configuracionDespues.vigenciaActual!.id, vigenciaId, reason: 'no debe crear una vigencia nueva');

      final historial = await obtenerHistorial.ejecutar(configuracionCobroId);
      expect(historial, hasLength(1));
    });

    test('rechaza editar observaciones de una vigencia histórica', () async {
      final cliente = await crearClienteDePrueba();
      final servicio = await crearServicioDePrueba(cliente.id);
      final configuracionCobroId = await crearConfiguracionCobroDePrueba(servicio.id);
      await cerrarConfiguracionCobro.ejecutar(configuracionCobroId: configuracionCobroId, fechaEfectiva: DateTime(2026, 2, 1), motivo: 'Motivo de prueba');

      final historial = await obtenerHistorial.ejecutar(configuracionCobroId);
      final historica = historial.single;

      final resultado =
          await actualizarObservaciones.ejecutar(vigenciaId: historica.vigencia.id, observaciones: 'no debería aplicar');

      expect(resultado, isA<ActualizarObservacionesConfiguracionCobroVigenciaNoEditable>());
    });
  });

  group('Historial cronológico', () {
    test('muestra los 4 estados posibles a lo largo del ciclo de vida', () async {
      final cliente = await crearClienteDePrueba();
      final servicio = await crearServicioDePrueba(cliente.id);
      final configuracionCobroId = await crearConfiguracionCobroDePrueba(servicio.id);

      // Reemplaza la vigente actual (pasa a histórica).
      await cambiarVigencia.ejecutar(
        configuracionCobroId: configuracionCobroId,
        borrador: ConfiguracionCobroBorrador(
          tipoDocumento: TipoDocumentoCobro.reciboDePago,
          frecuenciaId: SeedIds.frecuenciaCobroMensual,
          diaInicioPeriodo: 1,
          agrupacion: AgrupacionCobro.porServicio,
          metodo: MetodoPagoCobro.noAplica,
          requiereComplemento: false,
          fechaInicioVigencia: hoy,
        ),
      );
      // Programa una a futuro.
      await cambiarVigencia.ejecutar(
        configuracionCobroId: configuracionCobroId,
        borrador: ConfiguracionCobroBorrador(
          tipoDocumento: TipoDocumentoCobro.reciboDePago,
          frecuenciaId: SeedIds.frecuenciaCobroMensual,
          diaInicioPeriodo: 1,
          agrupacion: AgrupacionCobro.porServicio,
          metodo: MetodoPagoCobro.noAplica,
          requiereComplemento: false,
          fechaInicioVigencia: hoy.add(const Duration(days: 365)),
        ),
      );
      // Programa otra más para cancelarla.
      final creadaParaCancelar = await cambiarVigencia.ejecutar(
        configuracionCobroId: configuracionCobroId,
        borrador: ConfiguracionCobroBorrador(
          tipoDocumento: TipoDocumentoCobro.reciboDePago,
          frecuenciaId: SeedIds.frecuenciaCobroMensual,
          diaInicioPeriodo: 1,
          agrupacion: AgrupacionCobro.porServicio,
          metodo: MetodoPagoCobro.noAplica,
          requiereComplemento: false,
          fechaInicioVigencia: hoy.add(const Duration(days: 730)),
        ),
      );
      final aCancelarId = (creadaParaCancelar as CambiarVigenciaConfiguracionCobroExitoso).vigencia.id;
      await cancelarProgramada.ejecutar(vigenciaId: aCancelarId, motivo: 'Motivo de prueba');

      final historial = await obtenerHistorial.ejecutar(configuracionCobroId);
      final estados = historial.map((h) => h.estado).toSet();
      expect(estados, {
        EstadoVigenciaCobro.historica,
        EstadoVigenciaCobro.vigente,
        EstadoVigenciaCobro.programada,
        EstadoVigenciaCobro.cancelada,
      });
    });
  });
}
