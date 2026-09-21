// Etapa 15 — segunda pasada visual de Personal/Bajas. Verifica que
// "Plantilla activa" y "Bajas" no producen overflow en los breakpoints
// soportados por RISEG ONE (1536×864, 1366×768, 1024×768 y un ancho
// angosto ~700px), incluyendo el caso real "una sola baja" que
// originalmente producía "BOTTOM OVERFLOWED BY 12 PIXELS" en la
// gráfica "Bajas por mes".

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/asignacion_vehiculo_repository_impl.dart';
import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/codigos/generar_numero_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/database/tables/direccion_table.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/puesto_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_comercial_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_linea_comercial_vigencia_table.dart' show TratamientoIva;
import 'package:riseg_one/features/organizacion/data/tables/servicio_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_estatus_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_servicio_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/linea_comercial_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart';
import 'package:riseg_one/features/personal/domain/usecases/asignacion_servicio_validator.dart';
import 'package:riseg_one/features/personal/domain/usecases/asignar_empleado_servicio_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/crear_empleado_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/empleado_validator.dart';
import 'package:riseg_one/features/personal/domain/usecases/registrar_baja_laboral_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/registrar_reingreso_usecase.dart';
import 'package:riseg_one/features/personal/presentation/empleados/bajas_controller.dart';
import 'package:riseg_one/features/personal/presentation/empleados/bajas_list_screen.dart';
import 'package:riseg_one/features/personal/presentation/empleados/widgets/graficas_bajas.dart';
import 'package:riseg_one/features/personal/presentation/empleados/personal_activo_list_screen.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import 'package:riseg_one/core/attachments/attachment_repository.dart';
import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/features/personal/domain/usecases/actualizar_fotografia_empleado_usecase.dart';
import 'dart:convert' show base64Decode;
import 'dart:io';

// PNG 1×1 transparente real — un archivo válido para que `FileImage`
// decodifique sin error (bytes arbitrarios harían fallar la
// decodificación repetidamente y `pumpAndSettle()` nunca se estabiliza).
const _pngValidoBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

class _SesionMaestroDePrueba extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-maestro',
      nombre: 'Maestro de prueba',
      nombreUsuario: 'maestro',
      esMaestro: true,
      permisos: {},
    );
  }
}

class _Semillas {
  _Semillas(this.db);

  final AppDatabase db;
  late final AsignacionServicioRepositoryImpl asignacionRepo = AsignacionServicioRepositoryImpl(db);
  late final EmpleadoRepositoryImpl empleadoRepo = EmpleadoRepositoryImpl(db, asignacionRepo);
  late final ServicioRepositoryImpl servicioRepo = ServicioRepositoryImpl(db, asignacionRepo);
  late final ClienteRepositoryImpl clienteRepo = ClienteRepositoryImpl(db);
  late final ServicioComercialRepositoryImpl comercialRepo = ServicioComercialRepositoryImpl(db);
  late final PuestoRepositoryImpl puestoRepo = PuestoRepositoryImpl(db);
  late final CatalogoRepositoryImpl catalogoRepo = CatalogoRepositoryImpl(db);
  late final CodigoSecuenciaService codigoSecuencia = CodigoSecuenciaService(db);
  late final CrearEmpleadoUseCase crearEmpleado = CrearEmpleadoUseCase(
    empleadoRepo,
    GenerarNumeroUseCase(codigoSecuencia),
    const EmpleadoValidator(),
    servicioRepo,
    comercialRepo,
  );
  late final CrearServicioUseCase crearServicio = CrearServicioUseCase(
    servicioRepo,
    GenerarCodigoUseCase(codigoSecuencia),
    ServicioValidator(clienteRepo, catalogoRepo),
  );
  late final CambiarEstatusServicioUseCase cambiarEstatusServicio = CambiarEstatusServicioUseCase(servicioRepo, clienteRepo);
  late final RegistrarBajaLaboralUseCase registrarBajaLaboral = RegistrarBajaLaboralUseCase(empleadoRepo, const EmpleadoValidator(), AsignacionRepositoryImpl(db), AsignacionVehiculoRepositoryImpl(db));
  late final RegistrarReingresoUseCase registrarReingreso = RegistrarReingresoUseCase(empleadoRepo, const EmpleadoValidator());
  late final AsignarEmpleadoServicioUseCase asignarEmpleadoServicio =
      AsignarEmpleadoServicioUseCase(empleadoRepo, asignacionRepo, servicioRepo, comercialRepo, const AsignacionServicioValidator());
  late final AttachmentRepository attachmentRepo = AttachmentRepository(db);

  var _empleadoContador = 0;
  var _clienteContador = 0;
  var _puestoContador = 0;

  final Map<String, String> lineaComercialIdPorServicioId = {};

  Future<EmpleadoData> crearEmpleadoDePrueba({DateTime? fechaIngreso}) async {
    _empleadoContador++;
    final n = _empleadoContador.toString().padLeft(2, '0');
    final resultado = await crearEmpleado.ejecutar(
      nombres: 'Empleado$n',
      apellidoPaterno: 'Apellido$n',
      sexo: SexoEmpleado.masculino,
      fechaNacimiento: DateTime(1990, 1, 1),
      curp: 'PEXJ900101HDFXXX$n',
      rfc: 'PEXJ900101$n',
      nss: '100000000$n',
      estadoCivil: EstadoCivilEmpleado.soltero,
      fechaIngreso: fechaIngreso ?? DateTime(2026, 1, 1),
      aniosExperienciaSeguridad: 3,
    );
    return (resultado as CrearEmpleadoExitoso).empleado;
  }

  Future<ServicioData> crearServicioActivoDePrueba(String nombre) async {
    _clienteContador++;
    final cliente = await clienteRepo.crear(
      ClienteCompanion.insert(codigo: 'CLI-${_clienteContador.toString().padLeft(6, '0')}', nombreComercial: nombre),
    );
    final resultado = await crearServicio.ejecutar(
      clienteId: cliente.id,
      borrador: ServicioBorrador(nombre: nombre, tipoServicioId: SeedIds.tipoServicioVigilanciaFija, fechaInicio: DateTime(2026, 1, 1)),
    );
    final servicio = (resultado as GuardarServicioExitoso).servicio;

    _puestoContador++;
    final puesto = await puestoRepo.crear(
      PuestoCompanion.insert(
        codigo: 'PUE-${_puestoContador.toString().padLeft(6, '0')}',
        nombre: 'Elemento Operativo $_puestoContador',
        areaId: SeedIds.areaOperaciones,
        tipo: 'operativo',
        nivelJerarquico: 5,
      ),
    );
    final linea = await comercialRepo.crearLinea(
      servicioId: servicio.id,
      datos: LineaComercialValidada(
        puestoId: puesto.id,
        modalidadTurnoId: SeedIds.modalidadTurno24x24,
        cantidadElementos: 10,
        precioUnitario: 100000,
        tratamientoIva: TratamientoIva.noAplica,
        fechaInicioVigencia: DateTime(2026, 1, 1),
        sueldoMensualReferenciaPersonal: 1500000,
        bonoMensualReferenciaPersonal: 0,
      ),
    );

    await db.into(db.direccion).insert(
          DireccionCompanion.insert(
            servicioId: Value(servicio.id),
            tipoDireccion: TipoDireccion.operativa.name,
            calle: 'Av. Toluca',
            numeroExterior: '50',
            colonia: 'Centro',
            municipioAlcaldia: 'Toluca',
            estado: 'Estado de México',
            codigoPostal: '50000',
          ),
        );
    final activado = await cambiarEstatusServicio.ejecutar(servicioId: servicio.id, nuevo: EstatusServicio.activo, motivo: 'Motivo de prueba');
    final servicioActivo = (activado as CambiarEstatusServicioExitoso).servicio;
    lineaComercialIdPorServicioId[servicioActivo.id] = linea.linea.id;

    await asignarEmpleadoServicio.ejecutar(
      empleadoId: (await crearEmpleadoDePrueba()).id,
      servicioId: servicioActivo.id,
      fechaInicio: DateTime(2026, 1, 1),
      turnoId: SeedIds.modalidadTurno24x24,
      lineaComercialId: linea.linea.id,
    );

    return servicioActivo;
  }
}

Future<void> _pumpScreen(
  WidgetTester tester,
  AppDatabase db, {
  required Widget child,
  required Size tamano,
  ThemeData? tema,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: '/pantalla',
    routes: [
      GoRoute(path: '/pantalla', builder: (context, state) => Scaffold(body: child)),
      GoRoute(path: '/personal/empleados/:id', builder: (context, state) => const Scaffold(body: SizedBox.shrink())),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionMaestroDePrueba.new),
      ],
      child: MaterialApp.router(
        theme: tema ?? AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _anchos = [
  Size(1536, 864),
  Size(1366, 768),
  Size(1024, 768),
  Size(700, 900),
  Size(500, 900),
];

void main() {
  late AppDatabase db;
  late _Semillas semillas;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    semillas = _Semillas(db);
  });

  tearDown(() => db.close());

  group('Plantilla activa — responsive sin overflow', () {
    setUp(() async {
      // Un empleado CON asignación (Servicio/Turno reales) y uno SIN
      // asignación ("Sin asignar") — ejercita badges de Puesto/Turno,
      // el badge ámbar y la columna "Días activo".
      await semillas.crearServicioActivoDePrueba('Morgan Atlacomulco');
      await semillas.crearEmpleadoDePrueba();
    });

    for (final tamano in _anchos) {
      testWidgets('${tamano.width.toInt()}×${tamano.height.toInt()}: cero overflow', (tester) async {
        await _pumpScreen(tester, db, child: const PersonalActivoListScreen(), tamano: tamano);

        expect(tester.takeException(), isNull, reason: 'nunca debe aparecer RenderFlex overflow en Plantilla activa');
        expect(find.textContaining('días'), findsWidgets, reason: 'columna "Días activo" en días reales');
        expect(find.byIcon(Icons.chevron_right), findsWidgets, reason: 'acción discreta de fila navegable');
      });
    }

    testWidgets('modo oscuro, ancho angosto (700×900): cero overflow', (tester) async {
      await _pumpScreen(tester, db, child: const PersonalActivoListScreen(), tamano: const Size(700, 900), tema: AppTheme.dark());
      expect(tester.takeException(), isNull);
    });

    testWidgets('modo oscuro, ancho amplio (1536×864): cero overflow', (tester) async {
      await _pumpScreen(tester, db, child: const PersonalActivoListScreen(), tamano: const Size(1536, 864), tema: AppTheme.dark());
      expect(tester.takeException(), isNull);
    });
  });

  group('Bajas — responsive sin overflow, incluida una sola baja', () {
    setUp(() async {
      // Escenario real reportado: una sola baja en el periodo por
      // defecto ("Este mes") — antes producía "BOTTOM OVERFLOWED BY 12
      // PIXELS" en la gráfica "Bajas por mes".
      final empleado = await semillas.crearEmpleadoDePrueba(fechaIngreso: DateTime(2020, 1, 1));
      await semillas.registrarBajaLaboral.ejecutar(
        empleadoId: empleado.id,
        fechaBaja: DateTime.now(),
        motivo: MotivoBajaEmpleado.renuncia,
      );
    });

    for (final tamano in _anchos) {
      testWidgets('${tamano.width.toInt()}×${tamano.height.toInt()}: cero overflow con una sola baja', (tester) async {
        await _pumpScreen(tester, db, child: const BajasListScreen(), tamano: tamano);

        expect(tester.takeException(), isNull, reason: 'nunca debe aparecer RenderFlex overflow en Bajas, ni siquiera con 1 sola baja');
        // Etapa 17: se retiran las etiquetas de "zona" en mayúsculas
        // (RESUMEN/TENDENCIA/ANÁLISIS/DETALLE) — cada tarjeta lleva su
        // propio título en Title Case, mismo criterio de densidad que
        // el nuevo Resumen de Finanzas.
        expect(find.text('Bajas por mes'), findsOneWidget);
        // Etapa 16, tendencia adaptativa: con un solo mes con datos en el
        // periodo, se usa el compacto mes/cantidad, nunca el chart
        // completo (gráfica casi vacía).
        expect(find.byType(GraficaBarrasVerticales), findsNothing);
        expect(find.textContaining('1 baja'), findsOneWidget);
      });
    }

    testWidgets('modo oscuro, ancho angosto (700×900): cero overflow', (tester) async {
      await _pumpScreen(tester, db, child: const BajasListScreen(), tamano: const Size(700, 900), tema: AppTheme.dark());
      expect(tester.takeException(), isNull);
    });

    testWidgets('modo oscuro, ancho amplio (1536×864): cero overflow', (tester) async {
      await _pumpScreen(tester, db, child: const BajasListScreen(), tamano: const Size(1536, 864), tema: AppTheme.dark());
      expect(tester.takeException(), isNull);
    });
  });

  group('Bajas — tendencia adaptativa con 2+ meses con datos', () {
    testWidgets('con bajas en 2 meses distintos dentro del periodo, se usa el chart completo (no el compacto)', (tester) async {
      // Fechas relativas a "ahora" (nunca literales de un año fijo,
      // mismo criterio ya documentado en el grupo "snapshot histórico"
      // de este archivo) — `ultimos3Meses` resuelve a
      // `DateTime(ahora.year, ahora.month - 2, 1)..fin de este mes`
      // (`resolverRangoPeriodoBajas`), así que el mes anterior y el mes
      // actual SIEMPRE están dentro de ese rango, sin importar en qué
      // día del mes corra la prueba (a diferencia de un offset fijo en
      // días, que puede salirse del rango según dónde caiga "hoy"
      // dentro de su mes). Una fecha fija (encontrada por esta
      // auditoría: 2026-06-15/2026-08-10) se salía del rango en cuanto
      // "hoy" avanzaba más allá de cierto punto.
      final hoy = DateTime.now();
      final fechaBaja1 = DateTime(hoy.year, hoy.month - 1, 15);
      final fechaBaja2 = hoy;
      final e1 = await semillas.crearEmpleadoDePrueba(fechaIngreso: DateTime(2020, 1, 1));
      await semillas.registrarBajaLaboral.ejecutar(empleadoId: e1.id, fechaBaja: fechaBaja1, motivo: MotivoBajaEmpleado.renuncia);
      final e2 = await semillas.crearEmpleadoDePrueba(fechaIngreso: DateTime(2020, 1, 1));
      await semillas.registrarBajaLaboral.ejecutar(empleadoId: e2.id, fechaBaja: fechaBaja2, motivo: MotivoBajaEmpleado.renuncia);

      await _pumpScreen(tester, db, child: const BajasListScreen(), tamano: const Size(1366, 768));
      // Periodo por defecto es "Este mes" — cambiar a "Últimos 3 meses"
      // para que ambas bajas entren al rango.
      await tester.tap(find.text('Últimos 3 meses'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(GraficaBarrasVerticales), findsOneWidget, reason: 'con 2+ meses con datos se mantiene el chart, sin cambios');
    });
  });

  group('Bajas — sin registros', () {
    testWidgets('sin ninguna baja: estado vacío, sin overflow, sin secciones de tendencia/análisis', (tester) async {
      await _pumpScreen(tester, db, child: const BajasListScreen(), tamano: const Size(1366, 768));

      expect(tester.takeException(), isNull);
      expect(find.text('TENDENCIA'), findsNothing);
      expect(find.text('ANÁLISIS'), findsNothing);
    });
  });

  group('Bajas — snapshot histórico de un empleado reingresado', () {
    testWidgets('la fila archivada muestra el Servicio/Puesto DE ESE periodo, nunca el Servicio actual tras el reingreso', (tester) async {
      final servicioAnterior = await semillas.crearServicioActivoDePrueba('Servicio Anterior');
      final servicioActual = await semillas.crearServicioActivoDePrueba('Servicio Actual');

      // Fechas relativas a "ahora" (nunca literales de un año fijo) para
      // que el escenario quede dentro de "Últimos 3 meses" sin importar
      // en qué fecha real corra la prueba.
      // `crearServicioActivoDePrueba` fija el `fechaInicio` del Servicio
      // en 2026-01-01 (apertura de su vacante operativa) — la asignación
      // real no puede empezar antes de eso.
      final hoy = DateTime.now();
      final fechaIngresoInicial = hoy.subtract(const Duration(days: 90));
      final fechaBaja1 = hoy.subtract(const Duration(days: 60));
      final fechaReingreso = hoy.subtract(const Duration(days: 50));
      final fechaBaja2 = hoy.subtract(const Duration(days: 5));

      final empleado = await semillas.crearEmpleadoDePrueba(fechaIngreso: fechaIngresoInicial);
      final asignacion1 = await semillas.asignarEmpleadoServicio.ejecutar(
        empleadoId: empleado.id,
        servicioId: servicioAnterior.id,
        fechaInicio: fechaIngresoInicial,
        turnoId: SeedIds.modalidadTurno24x24,
        lineaComercialId: semillas.lineaComercialIdPorServicioId[servicioAnterior.id]!,
      );
      expect(asignacion1, isA<AsignarEmpleadoServicioExitoso>(), reason: asignacion1.runtimeType.toString());

      // Primera baja — snapshot debe quedar fijo en "Servicio Anterior".
      final baja1 = await semillas.registrarBajaLaboral.ejecutar(empleadoId: empleado.id, fechaBaja: fechaBaja1, motivo: MotivoBajaEmpleado.renuncia);
      expect(baja1, isA<RegistrarBajaLaboralExitoso>(), reason: baja1.runtimeType.toString());

      // Reingreso + reasignación a un Servicio DISTINTO — el snapshot de
      // la baja anterior NUNCA debe cambiar a reflejar esto.
      final reingreso = await semillas.registrarReingreso.ejecutar(empleadoId: empleado.id, fechaIngreso: fechaReingreso);
      expect(reingreso, isA<RegistrarReingresoExitoso>(), reason: reingreso.runtimeType.toString());

      final asignacion2 = await semillas.asignarEmpleadoServicio.ejecutar(
        empleadoId: empleado.id,
        servicioId: servicioActual.id,
        fechaInicio: fechaReingreso,
        turnoId: SeedIds.modalidadTurno24x24,
        lineaComercialId: semillas.lineaComercialIdPorServicioId[servicioActual.id]!,
      );
      expect(asignacion2, isA<AsignarEmpleadoServicioExitoso>(), reason: asignacion2.runtimeType.toString());

      // Segunda baja (vigente) — su snapshot corresponde a "Servicio Actual".
      final baja2 =
          await semillas.registrarBajaLaboral.ejecutar(empleadoId: empleado.id, fechaBaja: fechaBaja2, motivo: MotivoBajaEmpleado.inasistencias);
      expect(baja2, isA<RegistrarBajaLaboralExitoso>(), reason: baja2.runtimeType.toString());

      await _pumpScreen(tester, db, child: const BajasListScreen(), tamano: const Size(1366, 768));
      await tester.tap(find.text('Últimos 3 meses'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Ambas líneas compuestas Puesto/Servicio/Turno deben aparecer:
      // una con "Servicio Anterior" (periodo archivado) y otra con
      // "Servicio Actual" (baja vigente) — nunca las dos apuntando al
      // mismo Servicio por leer el vigente del Empleado en vez del
      // snapshot histórico de cada evento.
      expect(find.textContaining('Servicio Anterior'), findsWidgets);
      expect(find.textContaining('Servicio Actual'), findsWidgets);
    });
  });

  group('Bajas — fotografía vigente del Empleado, resolución en lote', () {
    // Prueba a nivel de controlador (sin pumpear un `FileImage` real):
    // el fallback foto→iniciales en sí ya está cubierto de forma
    // genérica en `riseg_entity_identity_test.dart`; aquí se protege
    // específicamente el NUEVO cableado de esta Etapa 16
    // (`BajasController` resolviendo `fotografiaPathPorEmpleadoId` en
    // una sola consulta en lote) — con foto real, sin foto, y que
    // nunca se cuelan ids sin fotografía en el mapa.
    test('el mapa fotografiaPathPorEmpleadoId solo contiene al empleado CON fotografía, con su ruta real', () async {
      final tempDir = Directory.systemTemp.createTempSync('riseg_bajas_foto_test_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final storage = AttachmentStorage(tempDir.path);
      final actualizarFotografia = ActualizarFotografiaEmpleadoUseCase(semillas.empleadoRepo, semillas.attachmentRepo, storage);

      final conFoto = await semillas.crearEmpleadoDePrueba(fechaIngreso: DateTime(2020, 1, 1));
      final archivoFoto = '${tempDir.path}/foto.png';
      File(archivoFoto).writeAsBytesSync(base64Decode(_pngValidoBase64));
      final resultado = await actualizarFotografia.ejecutar(
        empleadoId: conFoto.id,
        sourceFilePath: archivoFoto,
        originalFileName: 'foto.png',
        mimeType: 'image/png',
      );
      expect(resultado, isA<ActualizarFotografiaEmpleadoExitoso>());
      await semillas.registrarBajaLaboral.ejecutar(empleadoId: conFoto.id, fechaBaja: DateTime.now(), motivo: MotivoBajaEmpleado.renuncia);

      final sinFoto = await semillas.crearEmpleadoDePrueba(fechaIngreso: DateTime(2020, 1, 1));
      await semillas.registrarBajaLaboral.ejecutar(empleadoId: sinFoto.id, fechaBaja: DateTime.now(), motivo: MotivoBajaEmpleado.renuncia);

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          sesionControllerProvider.overrideWith(_SesionMaestroDePrueba.new),
        ],
      );
      addTearDown(container.dispose);
      await container.read(bajasControllerProvider.notifier).recargar();
      final state = container.read(bajasControllerProvider);

      expect(state.fotografiaPathPorEmpleadoId[conFoto.id], isNotNull, reason: 'el empleado con fotografía SÍ debe resolver su ruta real');
      expect(File(state.fotografiaPathPorEmpleadoId[conFoto.id]!).existsSync(), isTrue);
      expect(state.fotografiaPathPorEmpleadoId.containsKey(sinFoto.id), isFalse, reason: 'sin fotografía, nunca una entrada en el mapa');
    });
  });
}
