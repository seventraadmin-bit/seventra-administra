// Verifica el rediseño de "Condiciones de Personal" (Etapa 15) contra
// el caso real de personal heterogéneo reportado por Marlon: MORGAN
// ATLACOMULCO necesita 2 perfiles comerciales vigentes SIMULTÁNEAMENTE
// — 2 × Elemento Operativo (24×24) y 1 × Jefe de Turno (12×12), cada
// uno con su propio sueldo/bono de referencia — no una sola línea
// mixta. El modelo (`ServicioLineaComercial`/`ServicioLineaComercialVigencia`)
// ya soporta N líneas por Servicio sin ningún cambio de esquema (ver
// investigación: no existe ninguna restricción única por `servicioId`
// en ninguna capa); esta prueba confirma esa afirmación contra el árbol
// real, de extremo a extremo:
//  - `ObtenerExpedienteServicioUseCase` agrega correctamente el
//    subtotal comercial y los elementos comerciales vigentes SUMANDO
//    ambas líneas (no asumiendo una sola);
//  - la tabla de Configuración comercial muestra ambas líneas como
//    filas independientes, cada una con su propio sueldo/bono de
//    referencia visible;
//  - al asignar un Empleado, elegir un perfil distinto precarga el
//    sueldo/bono de ESE perfil, nunca el del otro.

import 'package:drift/drift.dart' hide isNull, isNotNull;
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
import 'package:riseg_one/features/organizacion/data/repositories/configuracion_cobro_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/entidad_fiscal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/puesto_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_comercial_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/sucursal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_linea_comercial_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_estatus_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/ensamblar_documento_por_emitir_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_servicio_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/linea_comercial_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/obtener_expediente_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';
import 'package:riseg_one/features/organizacion/presentation/servicios/servicio_expediente_screen.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart';
import 'package:riseg_one/features/personal/domain/usecases/crear_empleado_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/empleado_validator.dart';
import 'package:riseg_one/features/personal/presentation/empleados/widgets/asignar_servicio_empleado_dialog.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

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

Finder _campoTexto(String label) => find.descendant(
      of: find.byWidgetPredicate((w) => w is RisegTextField && w.label == label),
      matching: find.byType(TextFormField),
    );

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

void main() {
  late AppDatabase db;
  late String servicioId;
  late String clienteId;
  late String puestoElementoOperativoId;
  late String puestoJefeTurnoId;
  late ServicioComercialRepositoryImpl comercialRepo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(
            id: const Value('usuario-prueba'),
            nombre: 'Usuario de prueba',
            nombreUsuario: 'usuario-prueba',
            passwordHash: 'x',
          ),
        );

    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    final clienteRepo = ClienteRepositoryImpl(db);
    final servicioRepo = ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db));
    final catalogoRepo = CatalogoRepositoryImpl(db);
    comercialRepo = ServicioComercialRepositoryImpl(db);
    final puestoRepo = PuestoRepositoryImpl(db);

    final crearCliente = await clienteRepo.crear(
      ClienteCompanion.insert(codigo: 'CLI-000099', nombreComercial: 'Morgan Atlacomulco'),
    );
    clienteId = crearCliente.id;

    final crearServicio = CrearServicioUseCase(servicioRepo, generarCodigo, ServicioValidator(clienteRepo, catalogoRepo));
    final creado = await crearServicio.ejecutar(
      clienteId: clienteId,
      borrador: ServicioBorrador(
        nombre: 'Vigilancia Morgan Atlacomulco',
        tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
        fechaInicio: DateTime(2026, 1, 1),
      ),
    );
    servicioId = (creado as GuardarServicioExitoso).servicio.id;

    puestoElementoOperativoId = (await puestoRepo.crear(
      PuestoCompanion.insert(
        codigo: 'PUE-EO',
        nombre: 'Elemento Operativo',
        areaId: SeedIds.areaOperaciones,
        tipo: 'operativo',
        nivelJerarquico: 5,
      ),
    )).id;
    puestoJefeTurnoId = (await puestoRepo.crear(
      PuestoCompanion.insert(
        codigo: 'PUE-JT',
        nombre: 'Jefe de Turno',
        areaId: SeedIds.areaOperaciones,
        tipo: 'operativo',
        nivelJerarquico: 8,
      ),
    )).id;

    // Activar el Servicio — requiere Dirección operativa (mismo atajo
    // que el resto de las pruebas de este dominio).
    await db.into(db.direccion).insert(
          DireccionCompanion.insert(
            servicioId: Value(servicioId),
            tipoDireccion: TipoDireccion.operativa.name,
            calle: 'Av. Atlacomulco',
            numeroExterior: '1',
            colonia: 'Centro',
            municipioAlcaldia: 'Atlacomulco',
            estado: 'Estado de México',
            codigoPostal: '50450',
          ),
        );
    await CambiarEstatusServicioUseCase(servicioRepo, clienteRepo).ejecutar(servicioId: servicioId, nuevo: EstatusServicio.activo, motivo: 'Motivo de prueba');
  });

  tearDown(() => db.close());

  Future<({String lineaId, ServicioLineaComercialVigenciaData vigencia})> crearLinea({
    required String puestoId,
    required String modalidadTurnoId,
    required int cantidad,
    required int precioUnitario,
    required int sueldo,
    required int bono,
  }) async {
    final resultado = await comercialRepo.crearLinea(
      servicioId: servicioId,
      datos: LineaComercialValidada(
        puestoId: puestoId,
        modalidadTurnoId: modalidadTurnoId,
        cantidadElementos: cantidad,
        precioUnitario: precioUnitario,
        tratamientoIva: TratamientoIva.masIva,
        fechaInicioVigencia: DateTime(2026, 1, 1),
        sueldoMensualReferenciaPersonal: sueldo,
        bonoMensualReferenciaPersonal: bono,
      ),
    );
    return (lineaId: resultado.linea.id, vigencia: resultado.vigencia);
  }

  test(
    'MORGAN: 2 líneas vigentes simultáneas (2×Elemento Operativo 24×24 + 1×Jefe de Turno 12×12) — '
    'el subtotal comercial y los elementos comerciales vigentes SUMAN ambas líneas',
    () async {
      // 2 × Elemento Operativo, 24×24, $15,000.00/elemento, sueldo
      // $17,000.00, bono $2,500.00.
      await crearLinea(
        puestoId: puestoElementoOperativoId,
        modalidadTurnoId: SeedIds.modalidadTurno24x24,
        cantidad: 2,
        precioUnitario: 1500000,
        sueldo: 1700000,
        bono: 250000,
      );
      // 1 × Jefe de Turno, 12×12, $22,000.00, sueldo $26,000.00, bono
      // $4,000.00 — deliberadamente distinto en todos los campos, para
      // que cualquier mezcla accidental entre líneas sea detectable.
      await crearLinea(
        puestoId: puestoJefeTurnoId,
        modalidadTurnoId: SeedIds.modalidadTurno12x12,
        cantidad: 1,
        precioUnitario: 2200000,
        sueldo: 2600000,
        bono: 400000,
      );

      final obtenerExpediente = ObtenerExpedienteServicioUseCase(
        ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db)),
        ClienteRepositoryImpl(db),
        EntidadFiscalRepositoryImpl(db),
        SucursalRepositoryImpl(db),
        comercialRepo,
        ConfiguracionCobroRepositoryImpl(db),
        AsignacionServicioRepositoryImpl(db),
        EmpleadoRepositoryImpl(db, AsignacionServicioRepositoryImpl(db)),
      );
      final resultado = await obtenerExpediente.ejecutar(servicioId);
      final datos = resultado.when(ok: (d) => d, failure: (_) => throw StateError('no debería fallar'));

      expect(datos.lineasComerciales, hasLength(2));
      // Subtotal comercial: (2 × $15,000.00) + (1 × $22,000.00) = $52,000.00.
      expect(datos.subtotalComercial, 5200000);
      // Elementos comerciales vigentes: 2 + 1 = 3 — nunca se colapsan a
      // una sola línea ni se sobreescriben entre sí.
      expect(datos.elementosComercialesVigentes, 3);

      final elementoOperativo = datos.lineasComerciales.firstWhere((l) => l.puestoNombre == 'Elemento Operativo');
      final jefeTurno = datos.lineasComerciales.firstWhere((l) => l.puestoNombre == 'Jefe de Turno');
      expect(elementoOperativo.vigenciaActual!.sueldoMensualReferenciaPersonal, 1700000);
      expect(jefeTurno.vigenciaActual!.sueldoMensualReferenciaPersonal, 2600000, reason: 'cada línea conserva su propio sueldo, nunca el de la otra');
    },
  );

  testWidgets(
    'MORGAN: la tabla de Configuración comercial muestra ambas líneas como filas independientes, '
    'cada una con su propio sueldo/bono de referencia',
    (tester) async {
      await crearLinea(
        puestoId: puestoElementoOperativoId,
        modalidadTurnoId: SeedIds.modalidadTurno24x24,
        cantidad: 2,
        precioUnitario: 1500000,
        sueldo: 1700000,
        bono: 250000,
      );
      await crearLinea(
        puestoId: puestoJefeTurnoId,
        modalidadTurnoId: SeedIds.modalidadTurno12x12,
        cantidad: 1,
        precioUnitario: 2200000,
        sueldo: 2600000,
        bono: 400000,
      );

      tester.view.physicalSize = const Size(1400, 2400);
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
            home: ServicioExpedienteScreen(servicioId: servicioId),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Elemento Operativo'), findsOneWidget);
      expect(find.text('Jefe de Turno'), findsOneWidget);
      expect(find.textContaining('17,000.00'), findsWidgets, reason: 'sueldo de referencia de Elemento Operativo visible en su fila');
      expect(find.textContaining('26,000.00'), findsWidgets, reason: 'sueldo de referencia de Jefe de Turno visible en su fila, distinto del anterior');
      expect(find.textContaining('52,000.00'), findsWidgets, reason: 'Subtotal comercial = suma de ambas líneas');
      expect(find.text('3'), findsWidgets, reason: 'Elementos comerciales vigentes = 2 + 1');
    },
  );

  testWidgets(
    'MORGAN: al asignar un Empleado, elegir un perfil distinto precarga el sueldo/bono de ESE perfil',
    (tester) async {
      await crearLinea(
        puestoId: puestoElementoOperativoId,
        modalidadTurnoId: SeedIds.modalidadTurno24x24,
        cantidad: 2,
        precioUnitario: 1500000,
        sueldo: 1700000,
        bono: 250000,
      );
      await crearLinea(
        puestoId: puestoJefeTurnoId,
        modalidadTurnoId: SeedIds.modalidadTurno12x12,
        cantidad: 1,
        precioUnitario: 2200000,
        sueldo: 2600000,
        bono: 400000,
      );

      final asignacionRepo = AsignacionServicioRepositoryImpl(db);
      final empleadoRepo = EmpleadoRepositoryImpl(db, asignacionRepo);
      final crearEmpleado = CrearEmpleadoUseCase(
        empleadoRepo,
        GenerarNumeroUseCase(CodigoSecuenciaService(db)),
        const EmpleadoValidator(),
        ServicioRepositoryImpl(db, asignacionRepo),
        comercialRepo,
      );

      Future<EmpleadoData> crearEmpleadoDePrueba(String curp, String rfc, String nss, String nombres) async {
        final resultado = await crearEmpleado.ejecutar(
          nombres: nombres,
          apellidoPaterno: 'Pérez',
          sexo: SexoEmpleado.masculino,
          fechaNacimiento: DateTime(1990, 1, 1),
          curp: curp,
          rfc: rfc,
          nss: nss,
          estadoCivil: EstadoCivilEmpleado.soltero,
          fechaIngreso: DateTime(2026, 1, 1),
          aniosExperienciaSeguridad: 3,
        );
        return (resultado as CrearEmpleadoExitoso).empleado;
      }

      final empleadoOperativo = await crearEmpleadoDePrueba('PEXJ900101HDFXXX01', 'PEXJ900101AB1', '12345678901', 'Juan');
      final empleadoJefe = await crearEmpleadoDePrueba('GAAA900101MDFXXX02', 'GAAA900101AB2', '12345678902', 'Ana');
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      Future<void> pumpHost(WidgetTester tester, Widget Function(BuildContext, WidgetRef) contenido) async {
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

      // Elemento Operativo → precarga $17,000.00 / $2,500.00.
      await pumpHost(
        tester,
        (context, ref) => ElevatedButton(
          key: const Key('abrir'),
          onPressed: () => mostrarDialogoAsignarServicioEmpleado(context, ref, empleadoOperativo),
          child: const Text('abrir'),
        ),
      );
      await tester.tap(find.byKey(const Key('abrir')));
      await tester.pumpAndSettle();
      await _elegirEnSelector(tester, l10n.empleadoCampoServicio, 'Vigilancia Morgan Atlacomulco');
      await _elegirEnSelector(tester, l10n.empleadoCampoLineaComercial, 'Elemento Operativo · 24×24 · 2 posiciones');
      expect(find.text(l10n.empleadoLineaComercialCapacidad(0, 2)), findsOneWidget, reason: 'capacidad 0 de 2 antes de asignar a nadie');
      expect(_textoDe(tester, _campoTexto(l10n.empleadoCampoSueldoAcordado)), '17000.00');
      expect(_textoDe(tester, _campoTexto(l10n.empleadoCampoBonoAcordado)), '2500.00');
      await tester.tap(find.text(l10n.asignarServicioEmpleadoBotonConfirmar));
      await tester.pumpAndSettle();
      expect(find.text(l10n.asignarServicioEmpleadoExito), findsOneWidget);

      // Jefe de Turno → precarga $26,000.00 / $4,000.00, distinto del
      // perfil anterior — nunca se arrastra el sueldo del otro perfil.
      await pumpHost(
        tester,
        (context, ref) => ElevatedButton(
          key: const Key('abrir'),
          onPressed: () => mostrarDialogoAsignarServicioEmpleado(context, ref, empleadoJefe),
          child: const Text('abrir'),
        ),
      );
      await tester.tap(find.byKey(const Key('abrir')));
      await tester.pumpAndSettle();
      await _elegirEnSelector(tester, l10n.empleadoCampoServicio, 'Vigilancia Morgan Atlacomulco');
      await _elegirEnSelector(tester, l10n.empleadoCampoLineaComercial, 'Jefe de Turno · 12×12 · 1 posición');
      expect(find.text(l10n.empleadoLineaComercialCapacidad(0, 1)), findsOneWidget);
      expect(_textoDe(tester, _campoTexto(l10n.empleadoCampoSueldoAcordado)), '26000.00');
      expect(_textoDe(tester, _campoTexto(l10n.empleadoCampoBonoAcordado)), '4000.00');
      await tester.tap(find.text(l10n.asignarServicioEmpleadoBotonConfirmar));
      await tester.pumpAndSettle();
      expect(find.text(l10n.asignarServicioEmpleadoExito), findsOneWidget);

      // Verificación final: cada Empleado terminó en la línea que eligió,
      // no en la del otro.
      final asignacionOperativo = await asignacionRepo.obtenerActivaPorEmpleado(empleadoOperativo.id);
      final asignacionJefe = await asignacionRepo.obtenerActivaPorEmpleado(empleadoJefe.id);
      final lineas = await comercialRepo.listarLineas(servicioId);
      final lineaOperativo = lineas.firstWhere((l) => l.puestoNombre == 'Elemento Operativo');
      final lineaJefe = lineas.firstWhere((l) => l.puestoNombre == 'Jefe de Turno');
      expect(asignacionOperativo!.lineaComercialId, lineaOperativo.linea.id);
      expect(asignacionJefe!.lineaComercialId, lineaJefe.linea.id);
    },
  );

  testWidgets(
    'MORGAN — escenario completo (Etapa 15, UX "Condiciones de este perfil"): 2 líneas simultáneas, '
    'elementos comerciales vigentes = 3, sueldo/bono independiente por línea, precarga correcta al '
    'asignar a cada perfil, y la facturación suma ambos conceptos sin mezclarlos',
    (tester) async {
      // Línea 1: Elemento Operativo, 24×24, cantidad 2, precio X,
      // sueldo/bono de guardia.
      await crearLinea(
        puestoId: puestoElementoOperativoId,
        modalidadTurnoId: SeedIds.modalidadTurno24x24,
        cantidad: 2,
        precioUnitario: 1500000,
        sueldo: 1700000,
        bono: 250000,
      );
      // Línea 2: Jefe de Turno, 12×12, cantidad 1, precio Y, sueldo/bono
      // de jefe — deliberadamente distinto en todo, para que cualquier
      // mezcla accidental entre líneas sea detectable.
      await crearLinea(
        puestoId: puestoJefeTurnoId,
        modalidadTurnoId: SeedIds.modalidadTurno12x12,
        cantidad: 1,
        precioUnitario: 2200000,
        sueldo: 2600000,
        bono: 400000,
      );

      // 1. Elementos comerciales vigentes = 2 + 1 = 3, nunca colapsados
      // a una sola línea "repartida".
      final obtenerExpediente = ObtenerExpedienteServicioUseCase(
        ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db)),
        ClienteRepositoryImpl(db),
        EntidadFiscalRepositoryImpl(db),
        SucursalRepositoryImpl(db),
        comercialRepo,
        ConfiguracionCobroRepositoryImpl(db),
        AsignacionServicioRepositoryImpl(db),
        EmpleadoRepositoryImpl(db, AsignacionServicioRepositoryImpl(db)),
      );
      final expedienteResultado = await obtenerExpediente.ejecutar(servicioId);
      final datos = expedienteResultado.when(ok: (d) => d, failure: (_) => throw StateError('no debería fallar'));
      expect(datos.elementosComercialesVigentes, 3);

      // 2. Cada línea conserva su propio sueldo/bono — independiente,
      // nunca el de la otra.
      final lineaGuardia = datos.lineasComerciales.firstWhere((l) => l.puestoNombre == 'Elemento Operativo');
      final lineaJefeTurno = datos.lineasComerciales.firstWhere((l) => l.puestoNombre == 'Jefe de Turno');
      expect(lineaGuardia.vigenciaActual!.sueldoMensualReferenciaPersonal, 1700000);
      expect(lineaGuardia.vigenciaActual!.bonoMensualReferenciaPersonal, 250000);
      expect(lineaJefeTurno.vigenciaActual!.sueldoMensualReferenciaPersonal, 2600000);
      expect(lineaJefeTurno.vigenciaActual!.bonoMensualReferenciaPersonal, 400000);

      // 3 y 4. Asignar un Empleado a cada perfil precarga el sueldo/bono
      // de ESE perfil — nunca el del otro (vía el diálogo real).
      final asignacionRepo = AsignacionServicioRepositoryImpl(db);
      final empleadoRepo = EmpleadoRepositoryImpl(db, asignacionRepo);
      final crearEmpleado = CrearEmpleadoUseCase(
        empleadoRepo,
        GenerarNumeroUseCase(CodigoSecuenciaService(db)),
        const EmpleadoValidator(),
        ServicioRepositoryImpl(db, asignacionRepo),
        comercialRepo,
      );
      Future<EmpleadoData> crearEmpleadoDePrueba(String curp, String rfc, String nss, String nombres) async {
        final resultado = await crearEmpleado.ejecutar(
          nombres: nombres,
          apellidoPaterno: 'Pérez',
          sexo: SexoEmpleado.masculino,
          fechaNacimiento: DateTime(1990, 1, 1),
          curp: curp,
          rfc: rfc,
          nss: nss,
          estadoCivil: EstadoCivilEmpleado.soltero,
          fechaIngreso: DateTime(2026, 1, 1),
          aniosExperienciaSeguridad: 3,
        );
        return (resultado as CrearEmpleadoExitoso).empleado;
      }

      final guardia = await crearEmpleadoDePrueba('PEXJ900101HDFXXX03', 'PEXJ900101AB3', '12345678903', 'Carlos');
      final jefe = await crearEmpleadoDePrueba('GAAA900101MDFXXX04', 'GAAA900101AB4', '12345678904', 'Laura');
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      Future<void> pumpHost(WidgetTester tester, Widget Function(BuildContext, WidgetRef) contenido) async {
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

      await pumpHost(
        tester,
        (context, ref) => ElevatedButton(
          key: const Key('abrir'),
          onPressed: () => mostrarDialogoAsignarServicioEmpleado(context, ref, guardia),
          child: const Text('abrir'),
        ),
      );
      await tester.tap(find.byKey(const Key('abrir')));
      await tester.pumpAndSettle();
      await _elegirEnSelector(tester, l10n.empleadoCampoServicio, 'Vigilancia Morgan Atlacomulco');
      await _elegirEnSelector(tester, l10n.empleadoCampoLineaComercial, 'Elemento Operativo · 24×24 · 2 posiciones');
      expect(_textoDe(tester, _campoTexto(l10n.empleadoCampoSueldoAcordado)), '17000.00', reason: 'precarga el sueldo de guardia');
      expect(_textoDe(tester, _campoTexto(l10n.empleadoCampoBonoAcordado)), '2500.00');
      await tester.tap(find.text(l10n.asignarServicioEmpleadoBotonConfirmar));
      await tester.pumpAndSettle();
      expect(find.text(l10n.asignarServicioEmpleadoExito), findsOneWidget);

      await pumpHost(
        tester,
        (context, ref) => ElevatedButton(
          key: const Key('abrir'),
          onPressed: () => mostrarDialogoAsignarServicioEmpleado(context, ref, jefe),
          child: const Text('abrir'),
        ),
      );
      await tester.tap(find.byKey(const Key('abrir')));
      await tester.pumpAndSettle();
      await _elegirEnSelector(tester, l10n.empleadoCampoServicio, 'Vigilancia Morgan Atlacomulco');
      await _elegirEnSelector(tester, l10n.empleadoCampoLineaComercial, 'Jefe de Turno · 12×12 · 1 posición');
      expect(_textoDe(tester, _campoTexto(l10n.empleadoCampoSueldoAcordado)), '26000.00', reason: 'precarga el sueldo de jefe, no el de guardia');
      expect(_textoDe(tester, _campoTexto(l10n.empleadoCampoBonoAcordado)), '4000.00');
      await tester.tap(find.text(l10n.asignarServicioEmpleadoBotonConfirmar));
      await tester.pumpAndSettle();
      expect(find.text(l10n.asignarServicioEmpleadoExito), findsOneWidget);

      // 5. La facturación (armado de Documento por Emitir) suma el
      // importe comercial de ambas líneas sin mezclar el sueldo/bono en
      // ningún momento — `LineaArmada` ni siquiera tiene un campo de
      // sueldo/bono: es arquitectónicamente imposible que se filtre.
      final ensamblar = EnsamblarDocumentoPorEmitirUseCase(comercialRepo, ConfiguracionCobroRepositoryImpl(db));
      final armado = await ensamblar.ejecutar(
        clienteId: clienteId,
        tipoDocumento: 'reciboDePago',
        agrupacion: 'porServicio',
        metodo: 'noAplica',
        requiereComplemento: false,
        periodoInicio: DateTime(2026, 2, 1),
        periodoFin: DateTime(2026, 2, 28),
        servicios: [
          ServicioResueltoParaDocumento(servicioId: servicioId, configuracionCobroVigenciaId: 'sin-configuracion-cobro'),
        ],
      );

      expect(armado.lineas, hasLength(2), reason: 'ambas líneas se facturan por separado, nunca combinadas en una sola');
      // Subtotal proporcional de un mes calendario completo (28 días de
      // febrero — no es un mes comercial de 30 días exacto porque el
      // periodo no tiene la forma de mes calendario que arranca en el
      // día de inicio de la vigencia): se calcula con
      // `calcularImporteProporcional`, aquí solo se verifica que la
      // suma total sea la suma de ambas líneas, sin mezclar.
      final subtotalGuardia = armado.lineas.firstWhere((l) => l.puestoNombre == 'Elemento Operativo').subtotalProporcional;
      final subtotalJefe = armado.lineas.firstWhere((l) => l.puestoNombre == 'Jefe de Turno').subtotalProporcional;
      expect(armado.importeBaseEsperado, subtotalGuardia + subtotalJefe, reason: 'la facturación total es la suma exacta de ambos conceptos, sin mezclarlos');
      expect(subtotalGuardia, isNot(subtotalJefe), reason: 'precios distintos (15,000 vs 22,000) deben producir subtotales distintos');
    },
  );
}
