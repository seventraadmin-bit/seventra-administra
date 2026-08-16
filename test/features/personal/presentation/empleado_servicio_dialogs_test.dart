// Pruebas de pantalla de los diálogos de sueldo/bono acordado (Etapa
// 15, rediseño de "Condiciones de Personal") — Asignar/Cambiar
// Servicio, Alta de Personal con adscripción a Servicio, y Actualizar
// sueldo/bono de una asignación vigente. Cada diálogo se monta sobre
// un host mínimo (un botón que lo abre) — el mismo criterio que las
// pruebas de pantalla de Organización, sin necesitar la pantalla de
// listado/expediente completa para ejercer el diálogo en sí.

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/codigos/generar_numero_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/database/tables/direccion_table.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/puesto_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_comercial_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_linea_comercial_vigencia_table.dart';
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
import 'package:riseg_one/features/personal/presentation/empleados/widgets/actualizar_sueldo_asignacion_dialog.dart';
import 'package:riseg_one/features/personal/presentation/empleados/widgets/asignar_servicio_empleado_dialog.dart';
import 'package:riseg_one/features/personal/presentation/empleados/widgets/cambiar_servicio_empleado_dialog.dart';
import 'package:riseg_one/features/personal/presentation/empleados/widgets/crear_empleado_dialog.dart';
import 'package:riseg_one/features/personal/presentation/empleados/widgets/sueldo_acordado_fields.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

/// Sesión Maestro fija — Etapa 11C activó autorización real en las
/// acciones de estos diálogos; sin este override todas serían
/// rechazadas por `AuthorizationService` (mismo criterio que
/// `smoke_test.dart`).
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

/// El campo de texto (`TextFormField`) que vive dentro del `RisegTextField`
/// cuya propiedad `label` es exactamente [label] — se busca por la
/// propiedad del widget, no por su `Text` visible, para no depender de
/// ambigüedades de `find.ancestor` cuando esa misma etiqueta aparece más
/// de una vez en el árbol (ej. como parte de otro texto).
Finder _campoTexto(String label) => find.descendant(
      of: find.byWidgetPredicate((w) => w is RisegTextField && w.label == label),
      matching: find.byType(TextFormField),
    );

/// El `DropdownButtonFormField` dentro del `RisegSelect` cuya propiedad
/// `label` es exactamente [label] — mismo motivo que [_campoTexto].
Finder _selector(String label) => find.descendant(
      of: find.byWidgetPredicate((w) => w is RisegSelect && w.label == label),
      matching: find.byWidgetPredicate((w) => w is DropdownButtonFormField),
    );

String _textoDe(WidgetTester tester, Finder campoTexto) {
  return tester.widget<TextFormField>(campoTexto).controller!.text;
}

Future<void> _elegirEnSelector(WidgetTester tester, String label, String opcionTexto) async {
  await tester.ensureVisible(_selector(label));
  await tester.tap(_selector(label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(opcionTexto).last);
  await tester.pumpAndSettle();
}

/// Etiqueta real del selector de línea comercial para el (único) perfil
/// de un Servicio — se calcula en vez de fijarse a mano en cada prueba
/// para no depender de coincidir "24×24" (con el signo de multiplicar
/// real del catálogo) carácter por carácter.
Future<String> _etiquetaLineaUnica(AppDatabase db, AppLocalizations l10n, String servicioId) async {
  final lineas = await ServicioComercialRepositoryImpl(db).listarLineas(servicioId);
  return etiquetaLineaComercial(l10n, lineas.single);
}

Future<void> _pumpHost(WidgetTester tester, AppDatabase db, Widget Function(BuildContext, WidgetRef) contenido) async {
  tester.view.physicalSize = const Size(1440, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionControllerDePrueba.new),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Consumer(builder: (context, ref, _) => contenido(context, ref))),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late AppDatabase db;
  var clienteContador = 0;
  var puestoContador = 0;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    clienteContador = 0;
    puestoContador = 0;
    // Fila real de Usuario para el `usuarioId` de `_SesionControllerDePrueba`
    // (Etapa 11D): `actorUsuarioId` ahora es una FK real hacia `Usuario` en
    // las tablas de evento que estos diálogos escriben, así que un id
    // inventado que no exista en la base rompe la restricción — antes
    // pasaba inadvertido porque `actorUsuarioId` siempre llegaba `null`.
    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(
            id: const Value('usuario-prueba'),
            nombre: 'Usuario de prueba',
            nombreUsuario: 'usuario-prueba',
            passwordHash: 'x',
          ),
        );
  });

  tearDown(() => db.close());

  /// Por defecto ya deja una línea comercial con
  /// `sueldoMensualReferenciaPersonal`/`bonoMensualReferenciaPersonal`
  /// capturados (Etapa 15) — para que los diálogos que solo prueban otro
  /// comportamiento no tengan que resolver la precarga en cada caso.
  /// Pasar `sueldoMensualReferencia: null` explícitamente para probar el
  /// camino "sin referencia" (la línea existe igual, solo sin sueldo
  /// capturado); pasar `conLinea: false` para probar un Servicio sin
  /// ninguna línea comercial vigente.
  Future<ServicioData> crearServicio({
    String nombre = 'Vigilancia Sportium Toluca',
    int? sueldoMensualReferencia = 1500000,
    int? bonoMensualReferencia = 0,
    bool conLinea = true,
    bool activar = true,
  }) async {
    clienteContador++;
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    final clienteRepo = ClienteRepositoryImpl(db);
    final servicioRepo = ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db));
    final validator = ServicioValidator(clienteRepo, CatalogoRepositoryImpl(db));
    final crearServicio = CrearServicioUseCase(servicioRepo, generarCodigo, validator);
    final comercialRepo = ServicioComercialRepositoryImpl(db);

    final cliente = await clienteRepo.crear(
      ClienteCompanion.insert(codigo: 'CLI-${clienteContador.toString().padLeft(6, '0')}', nombreComercial: 'Sportium'),
    );
    final creado = await crearServicio.ejecutar(
      clienteId: cliente.id,
      borrador: ServicioBorrador(nombre: nombre, tipoServicioId: SeedIds.tipoServicioVigilanciaFija, fechaInicio: DateTime(2026, 1, 1)),
    );
    var servicio = (creado as GuardarServicioExitoso).servicio;

    if (conLinea) {
      puestoContador++;
      final puesto = await PuestoRepositoryImpl(db).crear(
        PuestoCompanion.insert(
          codigo: 'PUE-${puestoContador.toString().padLeft(6, '0')}',
          nombre: 'Elemento Operativo $puestoContador',
          areaId: SeedIds.areaOperaciones,
          tipo: 'operativo',
          nivelJerarquico: 5,
        ),
      );
      await comercialRepo.crearLinea(
        servicioId: servicio.id,
        datos: LineaComercialValidada(
          puestoId: puesto.id,
          modalidadTurnoId: SeedIds.modalidadTurno24x24,
          cantidadElementos: 2,
          precioUnitario: 100000,
          tratamientoIva: TratamientoIva.noAplica,
          fechaInicioVigencia: DateTime(2026, 1, 1),
          sueldoMensualReferenciaPersonal: sueldoMensualReferencia,
          bonoMensualReferenciaPersonal: bonoMensualReferencia,
        ),
      );
    }

    if (activar) {
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
      final cambiado = await CambiarEstatusServicioUseCase(servicioRepo, clienteRepo)
          .ejecutar(servicioId: servicio.id, nuevo: EstatusServicio.activo);
      servicio = (cambiado as CambiarEstatusServicioExitoso).servicio;
    }

    return servicio;
  }

  Future<EmpleadoData> crearEmpleado({DateTime? fechaIngreso}) async {
    final asignacionRepo = AsignacionServicioRepositoryImpl(db);
    final empleadoRepo = EmpleadoRepositoryImpl(db, asignacionRepo);
    final crearEmpleado = CrearEmpleadoUseCase(
      empleadoRepo,
      GenerarNumeroUseCase(CodigoSecuenciaService(db)),
      const EmpleadoValidator(),
      ServicioRepositoryImpl(db, asignacionRepo),
      ServicioComercialRepositoryImpl(db),
    );
    final resultado = await crearEmpleado.ejecutar(
      nombres: 'Juan',
      apellidoPaterno: 'Pérez',
      sexo: SexoEmpleado.masculino,
      fechaNacimiento: DateTime(1990, 1, 1),
      curp: 'PEXJ900101HDFXXX01',
      rfc: 'PEXJ900101AB1',
      nss: '12345678901',
      estadoCivil: EstadoCivilEmpleado.soltero,
      fechaIngreso: fechaIngreso ?? DateTime(2026, 1, 1),
      aniosExperienciaSeguridad: 3,
    );
    return (resultado as CrearEmpleadoExitoso).empleado;
  }

  group('AsignarServicioEmpleadoDialog', () {
    testWidgets('elegir el perfil/línea comercial precarga sueldo/bono y asigna con éxito', (tester) async {
      final empleado = await crearEmpleado();
      final servicio = await crearServicio(sueldoMensualReferencia: 1600000, bonoMensualReferencia: 300000);
      bool? resultado;
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      await _pumpHost(
        tester,
        db,
        (context, ref) => ElevatedButton(
          key: const Key('abrir'),
          onPressed: () async {
            resultado = await mostrarDialogoAsignarServicioEmpleado(context, ref, empleado);
          },
          child: const Text('abrir'),
        ),
      );
      await tester.tap(find.byKey(const Key('abrir')));
      await tester.pumpAndSettle();

      await _elegirEnSelector(tester, l10n.empleadoCampoServicio, servicio.nombre);
      expect(_selector(l10n.empleadoCampoLineaComercial), findsOneWidget, reason: 'una única línea vigente debe ofrecerse en el selector');
      await _elegirEnSelector(tester, l10n.empleadoCampoLineaComercial, await _etiquetaLineaUnica(db, l10n, servicio.id));

      // La precarga ya llenó "Sueldo acordado"/"Bono acordado" con la
      // referencia de la línea ($16,000.00 / $3,000.00) — se confirma
      // tal cual, sin editar nada.
      expect(_textoDe(tester, _campoTexto(l10n.empleadoCampoSueldoAcordado)), '16000.00');
      expect(_textoDe(tester, _campoTexto(l10n.empleadoCampoBonoAcordado)), '3000.00');
      expect(find.textContaining('16,000.00'), findsWidgets, reason: 'la referencia del perfil también se muestra en su propio texto');

      await tester.tap(find.text(l10n.asignarServicioEmpleadoBotonConfirmar));
      await tester.pumpAndSettle();

      expect(resultado, isTrue);
      expect(find.text(l10n.asignarServicioEmpleadoExito), findsOneWidget);
    });

    testWidgets('permite una excepción individual que sustituye la precarga de la línea', (tester) async {
      final empleado = await crearEmpleado();
      final servicio = await crearServicio(sueldoMensualReferencia: 1600000, bonoMensualReferencia: 300000);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      await _pumpHost(
        tester,
        db,
        (context, ref) => ElevatedButton(
          key: const Key('abrir'),
          onPressed: () => mostrarDialogoAsignarServicioEmpleado(context, ref, empleado),
          child: const Text('abrir'),
        ),
      );
      await tester.tap(find.byKey(const Key('abrir')));
      await tester.pumpAndSettle();

      await _elegirEnSelector(tester, l10n.empleadoCampoServicio, servicio.nombre);
      await _elegirEnSelector(tester, l10n.empleadoCampoLineaComercial, await _etiquetaLineaUnica(db, l10n, servicio.id));

      await tester.enterText(_campoTexto(l10n.empleadoCampoSueldoAcordado), '2000');
      await tester.enterText(_campoTexto(l10n.empleadoCampoBonoAcordado), '0');

      await tester.tap(find.text(l10n.asignarServicioEmpleadoBotonConfirmar));
      await tester.pumpAndSettle();

      expect(find.text(l10n.asignarServicioEmpleadoExito), findsOneWidget);

      final asignacionRepo = AsignacionServicioRepositoryImpl(db);
      final asignacion = await asignacionRepo.obtenerActivaPorEmpleado(empleado.id);
      final vigencias = await asignacionRepo.listarHistorialSueldo(asignacion!.id);
      expect(vigencias.single.sueldoMensual, 200000, reason: 'la excepción individual (2000 pesos) sustituye la referencia');
      expect(vigencias.single.bonoMensual, 0, reason: r'bono $0 explícito sí es válido');
    });

    testWidgets('rechaza confirmar sin elegir línea cuando el Servicio tiene una vigente', (tester) async {
      final empleado = await crearEmpleado();
      final servicio = await crearServicio();
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      await _pumpHost(
        tester,
        db,
        (context, ref) => ElevatedButton(
          key: const Key('abrir'),
          onPressed: () => mostrarDialogoAsignarServicioEmpleado(context, ref, empleado),
          child: const Text('abrir'),
        ),
      );
      await tester.tap(find.byKey(const Key('abrir')));
      await tester.pumpAndSettle();

      await _elegirEnSelector(tester, l10n.empleadoCampoServicio, servicio.nombre);

      await tester.tap(find.text(l10n.asignarServicioEmpleadoBotonConfirmar));
      await tester.pumpAndSettle();

      expect(find.text(l10n.empleadoErrorLineaComercialRequerida), findsOneWidget, reason: 'el diálogo debe seguir abierto mostrando el mensaje claro');
    });

    testWidgets('muestra un mensaje claro cuando la línea elegida no tiene sueldo de referencia y no hay excepción', (tester) async {
      final empleado = await crearEmpleado();
      final servicio = await crearServicio(sueldoMensualReferencia: null, bonoMensualReferencia: null);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      await _pumpHost(
        tester,
        db,
        (context, ref) => ElevatedButton(
          key: const Key('abrir'),
          onPressed: () => mostrarDialogoAsignarServicioEmpleado(context, ref, empleado),
          child: const Text('abrir'),
        ),
      );
      await tester.tap(find.byKey(const Key('abrir')));
      await tester.pumpAndSettle();

      await _elegirEnSelector(tester, l10n.empleadoCampoServicio, servicio.nombre);
      await _elegirEnSelector(tester, l10n.empleadoCampoLineaComercial, await _etiquetaLineaUnica(db, l10n, servicio.id));

      expect(find.textContaining(l10n.servicioCondicionesPersonalValorSinConfigurar), findsWidgets);
      expect(_textoDe(tester, _campoTexto(l10n.empleadoCampoSueldoAcordado)), isEmpty);

      await tester.tap(find.text(l10n.asignarServicioEmpleadoBotonConfirmar));
      await tester.pumpAndSettle();

      expect(find.text(l10n.empleadoErrorSueldoRequerido), findsOneWidget, reason: 'el diálogo debe seguir abierto mostrando el mensaje claro');
    });

    testWidgets('un Servicio sin ninguna línea comercial vigente no ofrece el selector de perfil, pero sí acepta sueldo manual', (tester) async {
      final empleado = await crearEmpleado();
      final servicio = await crearServicio(conLinea: false);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      await _pumpHost(
        tester,
        db,
        (context, ref) => ElevatedButton(
          key: const Key('abrir'),
          onPressed: () => mostrarDialogoAsignarServicioEmpleado(context, ref, empleado),
          child: const Text('abrir'),
        ),
      );
      await tester.tap(find.byKey(const Key('abrir')));
      await tester.pumpAndSettle();

      await _elegirEnSelector(tester, l10n.empleadoCampoServicio, servicio.nombre);
      expect(_selector(l10n.empleadoCampoLineaComercial), findsNothing, reason: 'sin líneas vigentes no hay nada que elegir');
      expect(_campoTexto(l10n.empleadoCampoSueldoAcordado), findsOneWidget, reason: 'el campo debe seguir visible para capturar la excepción manual');

      await tester.enterText(_campoTexto(l10n.empleadoCampoSueldoAcordado), '1500');

      await tester.tap(find.text(l10n.asignarServicioEmpleadoBotonConfirmar));
      await tester.pumpAndSettle();

      expect(find.text(l10n.asignarServicioEmpleadoExito), findsOneWidget);
    });
  });

  group('CambiarServicioEmpleadoDialog', () {
    testWidgets('elegir el perfil/línea comercial del nuevo Servicio precarga sueldo/bono', (tester) async {
      final empleado = await crearEmpleado();
      final servicioA = await crearServicio(nombre: 'Servicio A', sueldoMensualReferencia: 1500000, bonoMensualReferencia: 0);
      final servicioB = await crearServicio(nombre: 'Servicio B', sueldoMensualReferencia: 2200000, bonoMensualReferencia: 400000);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      final asignacionRepo = AsignacionServicioRepositoryImpl(db);
      final servicioRepo = ServicioRepositoryImpl(db, asignacionRepo);
      final comercialRepo = ServicioComercialRepositoryImpl(db);
      final asignarUseCase = AsignarEmpleadoServicioUseCase(
        EmpleadoRepositoryImpl(db, asignacionRepo),
        asignacionRepo,
        servicioRepo,
        comercialRepo,
        const AsignacionServicioValidator(),
      );
      final lineasA = await comercialRepo.listarLineas(servicioA.id);
      await asignarUseCase.ejecutar(
        empleadoId: empleado.id,
        servicioId: servicioA.id,
        fechaInicio: DateTime(2026, 1, 1),
        lineaComercialId: lineasA.single.linea.id,
      );

      await _pumpHost(
        tester,
        db,
        (context, ref) => ElevatedButton(
          key: const Key('abrir'),
          onPressed: () => mostrarDialogoCambiarServicioEmpleado(context, ref, empleado, servicioA.id),
          child: const Text('abrir'),
        ),
      );
      await tester.tap(find.byKey(const Key('abrir')));
      await tester.pumpAndSettle();

      await _elegirEnSelector(tester, l10n.empleadoCampoServicioNuevo, servicioB.nombre);
      await _elegirEnSelector(tester, l10n.empleadoCampoLineaComercial, await _etiquetaLineaUnica(db, l10n, servicioB.id));

      expect(_textoDe(tester, _campoTexto(l10n.empleadoCampoSueldoAcordado)), '22000.00');
      expect(_textoDe(tester, _campoTexto(l10n.empleadoCampoBonoAcordado)), '4000.00');

      await tester.tap(find.text(l10n.cambiarServicioEmpleadoBotonConfirmar));
      await tester.pumpAndSettle();

      expect(find.text(l10n.cambiarServicioEmpleadoExito), findsOneWidget);
    });
  });

  group('ActualizarSueldoAsignacionDialog', () {
    Future<AsignacionServicioData> crearAsignacionActiva() async {
      final empleado = await crearEmpleado();
      final servicio = await crearServicio(sueldoMensualReferencia: 1500000, bonoMensualReferencia: 0);
      final asignacionRepo = AsignacionServicioRepositoryImpl(db);
      final comercialRepo = ServicioComercialRepositoryImpl(db);
      final asignarUseCase = AsignarEmpleadoServicioUseCase(
        EmpleadoRepositoryImpl(db, asignacionRepo),
        asignacionRepo,
        ServicioRepositoryImpl(db, asignacionRepo),
        comercialRepo,
        const AsignacionServicioValidator(),
      );
      final lineas = await comercialRepo.listarLineas(servicio.id);
      final resultado = await asignarUseCase.ejecutar(
        empleadoId: empleado.id,
        servicioId: servicio.id,
        fechaInicio: DateTime(2026, 1, 1),
        lineaComercialId: lineas.single.linea.id,
      );
      return (resultado as AsignarEmpleadoServicioExitoso).asignacion;
    }

    testWidgets('registra una nueva vigencia efectiva hoy, precargada con el sueldo/bono vigente', (tester) async {
      final asignacion = await crearAsignacionActiva();
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      await _pumpHost(
        tester,
        db,
        (context, ref) => ElevatedButton(
          key: const Key('abrir'),
          onPressed: () => mostrarDialogoActualizarSueldoAsignacion(context, ref, asignacion),
          child: const Text('abrir'),
        ),
      );
      await tester.tap(find.byKey(const Key('abrir')));
      await tester.pumpAndSettle();

      // Precargado con el sueldo vigente ($15,000.00) — se confirma tal
      // cual, sin editar nada.
      expect(_textoDe(tester, _campoTexto(l10n.empleadoCampoSueldoAcordado)), '15000.00');

      await tester.tap(find.text(l10n.actualizarSueldoAsignacionBotonConfirmar));
      await tester.pumpAndSettle();

      expect(find.text(l10n.actualizarSueldoAsignacionExito), findsOneWidget);
    });

    testWidgets('programa una vigencia futura y lo indica en el mensaje de éxito', (tester) async {
      final asignacion = await crearAsignacionActiva();
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      await _pumpHost(
        tester,
        db,
        (context, ref) => ElevatedButton(
          key: const Key('abrir'),
          onPressed: () => mostrarDialogoActualizarSueldoAsignacion(context, ref, asignacion),
          child: const Text('abrir'),
        ),
      );
      await tester.tap(find.byKey(const Key('abrir')));
      await tester.pumpAndSettle();

      await tester.enterText(_campoTexto(l10n.empleadoCampoSueldoAcordado), '2000');

      // Fecha futura — se invoca directamente el callback del campo para
      // no depender de navegar el selector de calendario Material.
      final campoFecha = tester.widget<RisegDateField>(find.byType(RisegDateField));
      campoFecha.onChanged(DateTime.now().add(const Duration(days: 60)));
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.actualizarSueldoAsignacionBotonConfirmar));
      await tester.pumpAndSettle();

      expect(find.text(l10n.actualizarSueldoAsignacionExitoProgramada), findsOneWidget);
    });

    testWidgets('rechaza un sueldo en 0 con un mensaje claro', (tester) async {
      final asignacion = await crearAsignacionActiva();
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      await _pumpHost(
        tester,
        db,
        (context, ref) => ElevatedButton(
          key: const Key('abrir'),
          onPressed: () => mostrarDialogoActualizarSueldoAsignacion(context, ref, asignacion),
          child: const Text('abrir'),
        ),
      );
      await tester.tap(find.byKey(const Key('abrir')));
      await tester.pumpAndSettle();

      await tester.enterText(_campoTexto(l10n.empleadoCampoSueldoAcordado), '0');

      await tester.tap(find.text(l10n.actualizarSueldoAsignacionBotonConfirmar));
      await tester.pumpAndSettle();

      expect(find.text(l10n.empleadoErrorSueldoAcordadoInvalido), findsOneWidget);
    });
  });

  group('CrearEmpleadoDialog con adscripción a Servicio', () {
    testWidgets('elegir el perfil/línea comercial de un Servicio precarga los campos de sueldo/bono acordado', (tester) async {
      final servicio = await crearServicio(sueldoMensualReferencia: 1700000, bonoMensualReferencia: 250000);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      await _pumpHost(
        tester,
        db,
        (context, ref) => ElevatedButton(
          key: const Key('abrir'),
          onPressed: () => mostrarDialogoCrearEmpleado(context, ref),
          child: const Text('abrir'),
        ),
      );
      await tester.tap(find.byKey(const Key('abrir')));
      await tester.pumpAndSettle();

      await _elegirEnSelector(tester, l10n.empleadoCampoTipoAdscripcion, l10n.empleadoTipoAdscripcionServicio);
      await _elegirEnSelector(tester, l10n.empleadoCampoServicio, servicio.nombre);
      await _elegirEnSelector(tester, l10n.empleadoCampoLineaComercial, await _etiquetaLineaUnica(db, l10n, servicio.id));

      expect(_textoDe(tester, _campoTexto(l10n.empleadoCampoSueldoAcordado)), '17000.00');
      expect(_textoDe(tester, _campoTexto(l10n.empleadoCampoBonoAcordado)), '2500.00');
    });

    testWidgets('sin elegir línea cuando el Servicio tiene una vigente, confirmar muestra el mensaje claro', (tester) async {
      final servicio = await crearServicio();
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      await _pumpHost(
        tester,
        db,
        (context, ref) => ElevatedButton(
          key: const Key('abrir'),
          onPressed: () => mostrarDialogoCrearEmpleado(context, ref),
          child: const Text('abrir'),
        ),
      );
      await tester.tap(find.byKey(const Key('abrir')));
      await tester.pumpAndSettle();

      await tester.enterText(_campoTexto(l10n.empleadoCampoNombres), 'Juan');
      await tester.enterText(_campoTexto(l10n.empleadoCampoApellidoPaterno), 'Pérez');
      await tester.enterText(_campoTexto(l10n.empleadoCampoCurp), 'PEXJ900101HDFXXX01');
      await tester.enterText(_campoTexto(l10n.empleadoCampoRfc), 'PEXJ900101AB1');
      await tester.enterText(_campoTexto(l10n.empleadoCampoNss), '12345678901');

      final fechaNacimiento = tester.widget<RisegDateField>(
        find.byWidgetPredicate((w) => w is RisegDateField && w.label == l10n.empleadoCampoFechaNacimiento),
      );
      fechaNacimiento.onChanged(DateTime(1990, 1, 1));
      await tester.pumpAndSettle();
      final fechaIngreso = tester.widget<RisegDateField>(
        find.byWidgetPredicate((w) => w is RisegDateField && w.label == l10n.empleadoCampoFechaIngreso),
      );
      fechaIngreso.onChanged(DateTime(2026, 1, 1));
      await tester.pumpAndSettle();

      await _elegirEnSelector(tester, l10n.empleadoCampoTipoAdscripcion, l10n.empleadoTipoAdscripcionServicio);
      await _elegirEnSelector(tester, l10n.empleadoCampoServicio, servicio.nombre);

      await tester.ensureVisible(find.text(l10n.crearEmpleadoBotonConfirmar));
      await tester.tap(find.text(l10n.crearEmpleadoBotonConfirmar));
      await tester.pumpAndSettle();

      expect(find.text(l10n.empleadoErrorLineaComercialRequerida), findsOneWidget, reason: 'el diálogo debe seguir abierto mostrando el mensaje claro');
    });
  });
}
