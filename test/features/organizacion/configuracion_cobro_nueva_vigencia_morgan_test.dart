// Caso MORGAN ATLACOMULCO — Comercial → Servicio → Configuración de
// cobro → Nueva vigencia.
//
// BUG REAL reportado por Marlon: al guardar, el diálogo se cerraba y
// aparecía "No se pudo registrar la nueva vigencia. Intenta de nuevo.";
// la configuración anterior seguía vigente y la nueva no se creaba.
//
// CAUSA RAÍZ: `EtapaCobroBorrador.id` es una clave de correlación
// DENTRO del lote (para que `etapaReferenciaId` apunte a una etapa
// hermana antes de que existan filas), pero el repositorio la insertaba
// como clave primaria de la fila. El formulario de Nueva vigencia se
// precarga con las etapas de la vigencia vigente conservando su `id`
// real, así que al guardar chocaba contra esas mismas filas —que siguen
// existiendo, porque el histórico no se toca—:
//
//   SqliteException(1555): UNIQUE constraint failed:
//   configuracion_cobro_etapa.id
//
// La transacción revertía todo: por eso la vigencia anterior quedaba
// intacta y la nueva no aparecía.

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';
import 'package:riseg_one/core/utils/clock.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_portal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/configuracion_cobro_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/entidad_fiscal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_comercial_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_etapa_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/calcular_fechas_cobro_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_vigencia_configuracion_cobro_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_errors.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_etapa_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_configuracion_cobro_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_servicio_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';

class _RelojFijo implements Clock {
  _RelojFijo(this._fecha);
  final DateTime _fecha;

  @override
  DateTime now() => _fecha;
}

void main() {
  late AppDatabase db;
  late ConfiguracionCobroRepositoryImpl repo;
  late CrearConfiguracionCobroUseCase crearConfiguracionCobro;
  late CambiarVigenciaConfiguracionCobroUseCase cambiarVigencia;
  late String servicioId;

  final hoy = DateTime(2026, 8, 15);

  /// Construye el mismo grafo de repositorios/casos de uso sobre una
  /// base de datos dada — se reutiliza al "reiniciar la app" sobre el
  /// mismo archivo para comprobar persistencia.
  void montarSobre(AppDatabase base) {
    final servicioRepo = ServicioRepositoryImpl(base, AsignacionServicioRepositoryImpl(base));
    final catalogoRepo = CatalogoRepositoryImpl(base);
    repo = ConfiguracionCobroRepositoryImpl(base, clock: _RelojFijo(hoy));
    final validator = ConfiguracionCobroValidator(
      servicioRepo,
      EntidadFiscalRepositoryImpl(base),
      catalogoRepo,
      ServicioComercialRepositoryImpl(base),
      ClientePortalRepositoryImpl(base),
    );
    const etapaValidator = ConfiguracionCobroEtapaValidator();
    crearConfiguracionCobro = CrearConfiguracionCobroUseCase(repo, servicioRepo, validator, etapaValidator);
    cambiarVigencia = CambiarVigenciaConfiguracionCobroUseCase(repo, servicioRepo, validator, etapaValidator);
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    montarSobre(db);

    final clienteRepo = ClienteRepositoryImpl(db);
    final servicioRepo = ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db));
    final cliente = await clienteRepo.crear(
      ClienteCompanion.insert(codigo: 'CLI-000010', nombreComercial: 'MORGAN'),
    );
    final servicio = await CrearServicioUseCase(
      servicioRepo,
      GenerarCodigoUseCase(CodigoSecuenciaService(db)),
      ServicioValidator(clienteRepo, CatalogoRepositoryImpl(db)),
    ).ejecutar(
      clienteId: cliente.id,
      borrador: ServicioBorrador(
        nombre: 'MORGAN ATLACOMULCO',
        tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
        fechaInicio: DateTime(2026, 1, 1),
      ),
    );
    servicioId = (servicio as GuardarServicioExitoso).servicio.id;
  });

  tearDown(() => db.close());

  ConfiguracionCobroBorrador borradorMorgan(DateTime desde) => ConfiguracionCobroBorrador(
        tipoDocumento: TipoDocumentoCobro.reciboDePago,
        frecuenciaId: SeedIds.frecuenciaCobroMensual,
        diaInicioPeriodo: 1,
        agrupacion: AgrupacionCobro.porServicio,
        metodo: MetodoPagoCobro.noAplica,
        requiereComplemento: false,
        fechaInicioVigencia: desde,
      );

  /// La configuración original de MORGAN: vigente desde el 24/04/2026.
  Future<String> configuracionOriginal() async {
    final creada = await crearConfiguracionCobro.ejecutar(
      servicioId: servicioId,
      borrador: borradorMorgan(DateTime(2026, 4, 24)),
      etapas: const [
        EtapaCobroBorrador(
          id: 'etapa-emision',
          tipoSistema: TipoEventoCobro.emision,
          orden: 0,
          tipoRegla: TipoReglaEvento.diaFijoDelMes,
          mesRelativo: MesRelativoCobro.actual,
          diaDelMes: 5,
        ),
        EtapaCobroBorrador(
          id: 'etapa-pago',
          tipoSistema: TipoEventoCobro.pagoEsperado,
          orden: 1,
          tipoRegla: TipoReglaEvento.diaFijoDelMes,
          mesRelativo: MesRelativoCobro.siguiente,
          diaDelMes: 10,
        ),
      ],
    );
    return (creada as CrearConfiguracionCobroExitoso).configuracion.id;
  }

  /// Lo que arma la pantalla al abrir "Nueva vigencia": precarga las
  /// etapas de la vigencia actual CONSERVANDO su `id` real
  /// (`EtapaEditState.desdeExistente`) y solo cambia las reglas.
  Future<List<EtapaCobroBorrador>> etapasCorregidasDeMorgan() async {
    final detalle = await repo.obtenerConfiguracion(servicioId);
    final precargadas = detalle!.etapas;
    return [
      EtapaCobroBorrador(
        id: precargadas.firstWhere((e) => e.tipoSistema == TipoEventoCobro.emision.name).id,
        tipoSistema: TipoEventoCobro.emision,
        orden: 0,
        tipoRegla: TipoReglaEvento.diaFijoDelMes,
        mesRelativo: MesRelativoCobro.actual, // MISMO MES DEL INICIO DEL PERIODO
        diaDelMes: 3,
      ),
      EtapaCobroBorrador(
        id: precargadas.firstWhere((e) => e.tipoSistema == TipoEventoCobro.pagoEsperado.name).id,
        tipoSistema: TipoEventoCobro.pagoEsperado,
        orden: 1,
        tipoRegla: TipoReglaEvento.nEsimoDiaSemanaDelMes,
        mesRelativo: MesRelativoCobro.siguiente, // MES SIGUIENTE AL INICIO DEL PERIODO
        ordinalSemana: OrdinalSemanaCobro.segundo,
        diaSemana: DiaSemanaCobro.viernes,
      ),
    ];
  }

  group('Alta y relevo de vigencias', () {
    test('crear la primera configuración deja una sola vigencia abierta', () async {
      final configuracionId = await configuracionOriginal();

      final historial = await repo.listarHistorial(configuracionId);
      expect(historial, hasLength(1));
      expect(historial.single.fechaInicioVigencia, DateTime(2026, 4, 24));
      expect(historial.single.fechaFinVigencia, isNull, reason: 'una vigencia sin sucesora nunca nace cerrada');
      expect(await repo.listarEtapas(historial.single.id), hasLength(2));
    });

    test('CASO MORGAN: Nueva vigencia sobre una vigente ya no falla (era el bug)', () async {
      final configuracionId = await configuracionOriginal();

      final resultado = await cambiarVigencia.ejecutar(
        configuracionCobroId: configuracionId,
        borrador: borradorMorgan(DateTime(2026, 9, 1)),
        etapas: await etapasCorregidasDeMorgan(),
      );

      expect(
        resultado,
        isA<CambiarVigenciaConfiguracionCobroExitoso>(),
        reason: resultado is CambiarVigenciaConfiguracionCobroErrorInesperado
            ? 'falló con: ${resultado.mensaje}'
            : 'falló con ${resultado.runtimeType}',
      );
    });

    test('el relevo es automático: la anterior se cierra en X-1, sin hueco ni traslape', () async {
      final configuracionId = await configuracionOriginal();
      await cambiarVigencia.ejecutar(
        configuracionCobroId: configuracionId,
        borrador: borradorMorgan(DateTime(2026, 9, 1)),
        etapas: await etapasCorregidasDeMorgan(),
      );

      final historial = await repo.listarHistorial(configuracionId);
      expect(historial, hasLength(2));
      final anterior = historial.first;
      final nueva = historial.last;

      expect(anterior.fechaInicioVigencia, DateTime(2026, 4, 24));
      expect(anterior.fechaFinVigencia, DateTime(2026, 8, 31), reason: 'un día antes de que empiece la nueva');
      expect(nueva.fechaInicioVigencia, DateTime(2026, 9, 1));
      expect(nueva.fechaFinVigencia, isNull);

      // Sin hueco: el día siguiente al fin de la anterior ES el inicio
      // de la nueva. Sin traslape: la anterior termina antes.
      expect(anterior.fechaFinVigencia!.add(const Duration(days: 1)), nueva.fechaInicioVigencia);
      expect(anterior.fechaFinVigencia!.isBefore(nueva.fechaInicioVigencia), isTrue);

      // NO hace falta cerrar a mano antes: "Nueva vigencia" hace el
      // relevo por sí sola.
      expect(anterior.cicloVidaRegistro, CicloVidaRegistro.activo.name);
    });

    test('el histórico anterior queda INTACTO: sus etapas siguen con sus reglas viejas', () async {
      final configuracionId = await configuracionOriginal();
      final historialAntes = await repo.listarHistorial(configuracionId);
      final etapasAntes = await repo.listarEtapas(historialAntes.single.id);

      await cambiarVigencia.ejecutar(
        configuracionCobroId: configuracionId,
        borrador: borradorMorgan(DateTime(2026, 9, 1)),
        etapas: await etapasCorregidasDeMorgan(),
      );

      final etapasDespues = await repo.listarEtapas(historialAntes.single.id);
      expect(etapasDespues, hasLength(2));

      final emisionVieja = etapasDespues.firstWhere((e) => e.tipoSistema == TipoEventoCobro.emision.name);
      expect(emisionVieja.diaDelMes, 5, reason: 'la regla vieja no se reescribe: era día 5');
      final pagoViejo = etapasDespues.firstWhere((e) => e.tipoSistema == TipoEventoCobro.pagoEsperado.name);
      expect(pagoViejo.tipoRegla, TipoReglaEvento.diaFijoDelMes.name);
      expect(pagoViejo.diaDelMes, 10);

      // Los id de las filas históricas tampoco cambian.
      expect(etapasDespues.map((e) => e.id).toSet(), etapasAntes.map((e) => e.id).toSet());
    });

    test('la vigencia nueva persiste sus propias etapas, con id distintos a los del histórico', () async {
      final configuracionId = await configuracionOriginal();
      final historialAntes = await repo.listarHistorial(configuracionId);
      final idsViejos = (await repo.listarEtapas(historialAntes.single.id)).map((e) => e.id).toSet();

      final resultado = await cambiarVigencia.ejecutar(
        configuracionCobroId: configuracionId,
        borrador: borradorMorgan(DateTime(2026, 9, 1)),
        etapas: await etapasCorregidasDeMorgan(),
      );
      final nueva = (resultado as CambiarVigenciaConfiguracionCobroExitoso).vigencia;

      final etapasNuevas = await repo.listarEtapas(nueva.id);
      expect(etapasNuevas, hasLength(2));
      expect(
        etapasNuevas.map((e) => e.id).toSet().intersection(idsViejos),
        isEmpty,
        reason: 'la identidad de la fila la asigna la persistencia, no el formulario',
      );

      final emision = etapasNuevas.firstWhere((e) => e.tipoSistema == TipoEventoCobro.emision.name);
      expect(emision.tipoRegla, TipoReglaEvento.diaFijoDelMes.name);
      expect(emision.mesRelativo, MesRelativoCobro.actual.name, reason: 'MISMO MES DEL INICIO DEL PERIODO');
      expect(emision.diaDelMes, 3);

      final pago = etapasNuevas.firstWhere((e) => e.tipoSistema == TipoEventoCobro.pagoEsperado.name);
      expect(pago.tipoRegla, TipoReglaEvento.nEsimoDiaSemanaDelMes.name);
      expect(pago.mesRelativo, MesRelativoCobro.siguiente.name, reason: 'MES SIGUIENTE AL INICIO DEL PERIODO');
      expect(pago.ordinalSemana, OrdinalSemanaCobro.segundo.name);
      expect(pago.diaSemana, DiaSemanaCobro.viernes.name);
    });

    test('las referencias entre etapas se remapean: el grafo del lote se conserva', () async {
      // Una etapa personalizada que depende de Emisión — el `id` que
      // usa `etapaReferenciaId` es el del lote, y al persistir debe
      // apuntar a la fila nueva de Emisión, nunca a la del histórico.
      final configuracionId = await configuracionOriginal();

      final resultado = await cambiarVigencia.ejecutar(
        configuracionCobroId: configuracionId,
        borrador: borradorMorgan(DateTime(2026, 9, 1)),
        etapas: const [
          EtapaCobroBorrador(
            id: 'lote-emision',
            tipoSistema: TipoEventoCobro.emision,
            orden: 0,
            tipoRegla: TipoReglaEvento.diaFijoDelMes,
            mesRelativo: MesRelativoCobro.actual,
            diaDelMes: 3,
          ),
          EtapaCobroBorrador(
            id: 'lote-validacion',
            nombre: 'Envío a validación',
            orden: 1,
            tipoRegla: TipoReglaEvento.diasCalendarioDespuesDe,
            offsetDias: 0,
            etapaReferenciaId: 'lote-emision',
          ),
        ],
      );

      final nueva = (resultado as CambiarVigenciaConfiguracionCobroExitoso).vigencia;
      final etapas = await repo.listarEtapas(nueva.id);
      final emision = etapas.firstWhere((e) => e.tipoSistema == TipoEventoCobro.emision.name);
      final validacion = etapas.firstWhere((e) => e.nombre == 'Envío a validación');

      expect(validacion.etapaReferenciaId, emision.id);
      expect(validacion.etapaReferenciaId, isNot('lote-emision'), reason: 'la referencia se remapea al id persistido');
    });
  });

  group('Rechazos y atomicidad', () {
    test('rechaza una vigencia con la MISMA fecha de inicio que otra existente', () async {
      final configuracionId = await configuracionOriginal();

      final resultado = await cambiarVigencia.ejecutar(
        configuracionCobroId: configuracionId,
        borrador: borradorMorgan(DateTime(2026, 4, 24)),
        etapas: await etapasCorregidasDeMorgan(),
      );

      expect(resultado, isA<CambiarVigenciaConfiguracionCobroErroresValidacion>());
      final errores = (resultado as CambiarVigenciaConfiguracionCobroErroresValidacion).errores;
      expect(errores.map((e) => e.codigo), contains(CodigoErrorConfiguracionCobro.fechaDuplicada));
      expect(await repo.listarHistorial(configuracionId), hasLength(1), reason: 'nada se creó');
    });

    test('rechaza una vigencia anterior al inicio del Servicio', () async {
      final configuracionId = await configuracionOriginal();

      final resultado = await cambiarVigencia.ejecutar(
        configuracionCobroId: configuracionId,
        borrador: borradorMorgan(DateTime(2025, 12, 31)),
        etapas: await etapasCorregidasDeMorgan(),
      );

      expect(resultado, isA<CambiarVigenciaConfiguracionCobroErroresValidacion>());
      expect(await repo.listarHistorial(configuracionId), hasLength(1));
    });

    test('ROLLBACK: si la nueva vigencia falla, la anterior NO queda cerrada', () async {
      final configuracionId = await configuracionOriginal();
      final historialAntes = await repo.listarHistorial(configuracionId);
      expect(historialAntes.single.fechaFinVigencia, isNull);

      // Dos etapas con el MISMO `tipoSistema` violan el UNIQUE
      // (configuracion_cobro_vigencia_id, tipo_sistema) en la base —
      // fuerza el fallo DENTRO de la transacción, después de que el
      // código ya cerró la predecesora.
      final resultado = await cambiarVigencia.ejecutar(
        configuracionCobroId: configuracionId,
        borrador: borradorMorgan(DateTime(2026, 9, 1)),
        etapas: const [
          EtapaCobroBorrador(
            id: 'a',
            tipoSistema: TipoEventoCobro.emision,
            orden: 0,
            tipoRegla: TipoReglaEvento.diaFijoDelMes,
            mesRelativo: MesRelativoCobro.actual,
            diaDelMes: 3,
          ),
          EtapaCobroBorrador(
            id: 'b',
            tipoSistema: TipoEventoCobro.emision,
            orden: 1,
            tipoRegla: TipoReglaEvento.diaFijoDelMes,
            mesRelativo: MesRelativoCobro.actual,
            diaDelMes: 4,
          ),
        ],
      );

      expect(resultado, isA<CambiarVigenciaConfiguracionCobroResultado>());
      expect(resultado, isNot(isA<CambiarVigenciaConfiguracionCobroExitoso>()));

      final historialDespues = await repo.listarHistorial(configuracionId);
      expect(historialDespues, hasLength(1), reason: 'no quedó una vigencia nueva a medias');
      expect(
        historialDespues.single.fechaFinVigencia,
        isNull,
        reason: 'la anterior NO puede quedar cerrada si la nueva no se creó',
      );
      expect(await repo.listarEtapas(historialDespues.single.id), hasLength(2), reason: 'sus etapas siguen intactas');
    });
  });

  group('Cálculo de fechas — reglas de MORGAN', () {
    const calcular = CalcularFechasCobroUseCase();

    Future<List<ConfiguracionCobroEtapaData>> etapasVigentesDeMorgan() async {
      final configuracionId = await configuracionOriginal();
      final resultado = await cambiarVigencia.ejecutar(
        configuracionCobroId: configuracionId,
        borrador: borradorMorgan(DateTime(2026, 9, 1)),
        etapas: await etapasCorregidasDeMorgan(),
      );
      final nueva = (resultado as CambiarVigenciaConfiguracionCobroExitoso).vigencia;
      return repo.listarEtapas(nueva.id);
    }

    test('periodo mensual septiembre 2026 → Emisión 03/09/2026, Pago esperado 09/10/2026', () async {
      final etapas = await etapasVigentesDeMorgan();
      final limites = calcularLimitesPeriodo(diaInicioPeriodo: 1, mesInicioPeriodo: DateTime(2026, 9, 1));

      final fechas = calcular.ejecutar(
        etapas: etapas,
        mesInicioPeriodo: DateTime(2026, 9, 1),
        periodoFin: limites.periodoFin,
      );

      expect(fechaDeEtapaSistema(fechas, TipoEventoCobro.emision), DateTime(2026, 9, 3));
      expect(
        fechaDeEtapaSistema(fechas, TipoEventoCobro.pagoEsperado),
        DateTime(2026, 10, 9),
        reason: 'el segundo viernes de octubre de 2026 es el día 9',
      );
    });

    test('periodo mensual octubre 2026 → Emisión 03/10/2026, Pago esperado 13/11/2026', () async {
      final etapas = await etapasVigentesDeMorgan();
      final limites = calcularLimitesPeriodo(diaInicioPeriodo: 1, mesInicioPeriodo: DateTime(2026, 10, 1));

      final fechas = calcular.ejecutar(
        etapas: etapas,
        mesInicioPeriodo: DateTime(2026, 10, 1),
        periodoFin: limites.periodoFin,
      );

      expect(fechaDeEtapaSistema(fechas, TipoEventoCobro.emision), DateTime(2026, 10, 3));
      expect(
        fechaDeEtapaSistema(fechas, TipoEventoCobro.pagoEsperado),
        DateTime(2026, 11, 13),
        reason: 'el segundo viernes de noviembre de 2026 es el día 13',
      );
    });

    test('"mismo mes" y "mes siguiente" no se confunden entre sí', () async {
      // Blindaje de la serialización de `MesRelativoCobro`: si `actual`
      // y `siguiente` se intercambiaran al persistir, las dos fechas
      // saldrían corridas un mes y las pruebas de arriba lo dirían —
      // esta lo dice explícitamente sobre la fila guardada.
      final etapas = await etapasVigentesDeMorgan();
      expect(
        etapas.firstWhere((e) => e.tipoSistema == TipoEventoCobro.emision.name).mesRelativo,
        MesRelativoCobro.actual.name,
      );
      expect(
        etapas.firstWhere((e) => e.tipoSistema == TipoEventoCobro.pagoEsperado.name).mesRelativo,
        MesRelativoCobro.siguiente.name,
      );
    });
  });

  test('persistencia: al volver a abrir la base, la vigencia nueva y el histórico siguen ahí', () async {
    // "Reiniciar la app" sobre el mismo archivo: se cierra la conexión,
    // se abre otra nueva y se rearma el grafo de repositorios.
    // La base en memoria de `setUp` no se usa aquí: cerrarla antes evita
    // la advertencia de drift por dos bases abiertas a la vez.
    await db.close();

    final archivo = await _archivoTemporal();
    final primera = AppDatabase(NativeDatabase(archivo));
    addTearDown(() {
      if (archivo.existsSync()) archivo.deleteSync();
    });

    montarSobre(primera);
    final clienteRepo = ClienteRepositoryImpl(primera);
    final servicioRepo = ServicioRepositoryImpl(primera, AsignacionServicioRepositoryImpl(primera));
    final cliente = await clienteRepo.crear(
      ClienteCompanion.insert(codigo: 'CLI-000010', nombreComercial: 'MORGAN'),
    );
    final servicio = await CrearServicioUseCase(
      servicioRepo,
      GenerarCodigoUseCase(CodigoSecuenciaService(primera)),
      ServicioValidator(clienteRepo, CatalogoRepositoryImpl(primera)),
    ).ejecutar(
      clienteId: cliente.id,
      borrador: ServicioBorrador(
        nombre: 'MORGAN ATLACOMULCO',
        tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
        fechaInicio: DateTime(2026, 1, 1),
      ),
    );
    servicioId = (servicio as GuardarServicioExitoso).servicio.id;

    final configuracionId = await configuracionOriginal();
    await cambiarVigencia.ejecutar(
      configuracionCobroId: configuracionId,
      borrador: borradorMorgan(DateTime(2026, 9, 1)),
      etapas: await etapasCorregidasDeMorgan(),
    );
    await primera.close();

    // Segunda "sesión" de la app.
    final segunda = AppDatabase(NativeDatabase(archivo));
    addTearDown(segunda.close);
    montarSobre(segunda);

    final historial = await repo.listarHistorial(configuracionId);
    expect(historial, hasLength(2));
    expect(historial.first.fechaFinVigencia, DateTime(2026, 8, 31));
    expect(historial.last.fechaInicioVigencia, DateTime(2026, 9, 1));

    // Las etapas de la vigencia NUEVA (la del 01/09). Ojo: al reloj de
    // prueba (15/08/2026) la vigente sigue siendo la anterior, así que
    // `obtenerConfiguracion` devolvería las etapas viejas — correcto,
    // pero no es lo que se está comprobando aquí.
    final etapasNuevas = await repo.listarEtapas(historial.last.id);
    final pago = etapasNuevas.firstWhere((e) => e.tipoSistema == TipoEventoCobro.pagoEsperado.name);
    expect(pago.tipoRegla, TipoReglaEvento.nEsimoDiaSemanaDelMes.name);
    expect(pago.ordinalSemana, OrdinalSemanaCobro.segundo.name);
    expect(pago.diaSemana, DiaSemanaCobro.viernes.name);
    expect(pago.mesRelativo, MesRelativoCobro.siguiente.name);
  });
}

Future<File> _archivoTemporal() async {
  final dir = Directory.systemTemp.createTempSync('riseg_cobro_persistencia_');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return File('${dir.path}/riseg_test.sqlite');
}
