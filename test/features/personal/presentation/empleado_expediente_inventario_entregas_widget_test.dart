// Etapa "Entrega múltiple de Inventario a Personal" — pruebas de
// widget del expediente del Empleado:
//   1. La sección "Equipo asignado" agrupa por Entrega (folio propio)
//      y conserva el bucket legacy "Asignaciones individuales"
//      (`entregaId == null`), sin excepción ni overflow.
//   2. Responsive/tema del bug visual real corregido en "Asignación a
//      Servicio" (antes: `Row([Expanded(Text), Wrap(botones)])` — con
//      5 botones visibles el título se envolvía letra por letra). Se
//      prueba con el Empleado en el peor caso real (Maestro, perfil
//      comercial sin regularizar, todos los botones del Wrap visibles)
//      en los 4 anchos reportados × claro/oscuro.

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/categoria_articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/inventario_repository_impl.dart';
import 'package:riseg_one/features/inventario/domain/repositories/asignacion_repository.dart' show AsignacionLineaInput;
import 'package:riseg_one/features/inventario/domain/usecases/crear_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_categoria_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_entrada_usecase.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart' show attachmentStorageProvider;
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/presentation/empleados/empleado_expediente_screen.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

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

Future<void> pump(
  WidgetTester tester,
  AppDatabase db,
  Directory tempDir,
  String empleadoId, {
  required Size tamano,
  required ThemeData tema,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: '/personal/empleados/$empleadoId',
    routes: [
      GoRoute(path: '/personal/empleados/:id', builder: (context, state) => EmpleadoExpedienteScreen(empleadoId: state.pathParameters['id']!)),
      GoRoute(path: '/comercial/servicios/:id', builder: (context, state) => const Scaffold(body: SizedBox.shrink())),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionMaestroDePrueba.new),
        attachmentStorageProvider.overrideWithValue(AttachmentStorage(tempDir.path)),
      ],
      child: MaterialApp.router(
        theme: tema,
        themeMode: ThemeMode.light,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late AppDatabase db;
  late Directory tempDir;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    tempDir = Directory.systemTemp.createTempSync('riseg_empleado_entregas_test_');
  });

  tearDown(() {
    db.close();
    tempDir.deleteSync(recursive: true);
  });

  Future<String> crearEmpleadoDePrueba() async {
    final empleado = await db.into(db.empleado).insertReturning(
          EmpleadoCompanion.insert(
            numeroEmpleado: 1,
            nombres: 'Juan',
            apellidoPaterno: 'Pérez',
            sexo: 'masculino',
            fechaNacimiento: DateTime(1990, 1, 1),
            curp: 'PEXJ900101HDFXXX01',
            rfc: 'PEXJ900101AB1',
            nss: '12345678901',
            estadoCivil: 'soltero',
            fechaIngreso: DateTime(2025, 1, 1),
            aniosExperienciaSeguridad: 3,
          ),
        );
    return empleado.id;
  }

  testWidgets(
    '"Equipo asignado" agrupa por Entrega (folio propio) y conserva el bucket legacy "Asignaciones individuales", sin overflow',
    (tester) async {
      final empleadoId = await crearEmpleadoDePrueba();

      final articuloRepo = ArticuloRepositoryImpl(db);
      final categoriaRepo = CategoriaArticuloRepositoryImpl(db);
      final inventarioRepo = InventarioRepositoryImpl(db);
      final asignacionRepo = AsignacionRepositoryImpl(db);

      final categoria = (await CrearCategoriaArticuloUseCase(categoriaRepo).ejecutar(nombre: 'Uniformes') as CrearCategoriaArticuloExitoso).categoria;
      final camisola = (await CrearArticuloUseCase(articuloRepo, categoriaRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db))).ejecutar(
        categoriaId: categoria.id,
        nombre: 'CAMISOLA',
        manejaVariante: false,
        manejaSerie: false,
      ) as CrearArticuloExitoso)
          .articulo;
      final gorra = (await CrearArticuloUseCase(articuloRepo, categoriaRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db))).ejecutar(
        categoriaId: categoria.id,
        nombre: 'GORRA',
        manejaVariante: false,
        manejaSerie: false,
      ) as CrearArticuloExitoso)
          .articulo;

      await RegistrarEntradaUseCase(inventarioRepo, articuloRepo).ejecutar(articuloId: camisola.id, cantidad: 5, fecha: DateTime(2026, 1, 1));
      await RegistrarEntradaUseCase(inventarioRepo, articuloRepo).ejecutar(articuloId: gorra.id, cantidad: 5, fecha: DateTime(2026, 1, 1));

      // Una Entrega (2 líneas) — mismo mecanismo que "Entregar equipo".
      await asignacionRepo.crearEntrega(
        folio: 'ENT-000001',
        lineas: [
          AsignacionLineaInput(articuloId: camisola.id, cantidad: 2, condicionEntrega: 'Nuevo'),
          AsignacionLineaInput(articuloId: gorra.id, cantidad: 1, condicionEntrega: 'Nuevo'),
        ],
        empleadoId: empleadoId,
        fechaEntrega: DateTime(2026, 8, 20),
      );

      // Una Asignacion legacy suelta (diálogo individual, entregaId
      // NULL) — debe seguir apareciendo en su propio bucket.
      await asignacionRepo.crear(
        articuloId: camisola.id,
        cantidad: 1,
        empleadoId: empleadoId,
        fechaEntrega: DateTime(2026, 8, 21),
        condicionEntrega: 'Nuevo',
      );

      await pump(tester, db, tempDir, empleadoId, tamano: const Size(1366, 900), tema: AppTheme.light());

      expect(tester.takeException(), isNull);
      expect(find.text('ENT-000001'), findsOneWidget);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));
      expect(find.text(l10n.empleadoInventarioAsignacionesIndividuales), findsOneWidget);
      expect(find.textContaining('2 × CAMISOLA'), findsOneWidget);
      expect(find.textContaining('1 × GORRA'), findsOneWidget);
      expect(find.textContaining('1 × CAMISOLA'), findsOneWidget);
    },
  );

  const anchos = [Size(1366, 768), Size(1024, 768), Size(700, 900), Size(500, 900)];
  final temas = {'claro': AppTheme.light(), 'oscuro': AppTheme.dark()};

  for (final entradaTema in temas.entries) {
    for (final tamano in anchos) {
      final etiqueta = '${tamano.width.toInt()}×${tamano.height.toInt()}, ${entradaTema.key}';

      testWidgets('"Asignación a Servicio" con los 5 botones visibles ($etiqueta): cero overflow', (tester) async {
        final empleadoId = await crearEmpleadoDePrueba();

        final tipoServicio = await db
            .into(db.tipoServicio)
            .insertReturning(TipoServicioCompanion.insert(id: 'tipo-1', codigo: 'VIGILANCIA_FIJA', nombre: 'Vigilancia fija'));
        final cliente =
            await db.into(db.cliente).insertReturning(ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Sportium'));
        final servicio = await db.into(db.servicio).insertReturning(
              ServicioCompanion.insert(
                codigo: 'SER-000001',
                clienteId: cliente.id,
                nombre: 'Vigilancia Sportium',
                tipoServicioId: tipoServicio.id,
                fechaInicio: DateTime(2026, 1, 1),
              ),
            );

        // `lineaComercialId` deliberadamente NULL — con Maestro, activa
        // el 5º botón ("Regularizar perfil"), el peor caso real del
        // Wrap que reproducía el bug original.
        await AsignacionServicioRepositoryImpl(db).asignar(
          empleadoId: empleadoId,
          servicioId: servicio.id,
          fechaInicio: DateTime(2026, 1, 1),
          sueldoMensual: 1500000,
          bonoMensual: 0,
        );

        await pump(tester, db, tempDir, empleadoId, tamano: tamano, tema: entradaTema.value);

        expect(tester.takeException(), isNull);
      });
    }
  }
}
