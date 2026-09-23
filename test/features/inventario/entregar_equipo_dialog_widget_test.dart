// Prueba de widget del diálogo "Entregar equipo" (Etapa "Entrega
// múltiple de Inventario a Personal") — ejerce el diálogo real (no una
// llamada directa al caso de uso) para probar exactamente lo que un
// operador hace: elegir un artículo fungible, agregarlo con cantidad,
// elegir un artículo serializado marcando su unidad, capturar la
// condición y confirmar — y que el resultado sea UNA Entrega con AMBAS
// Asignaciones vinculadas.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/categoria_articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/inventario_repository_impl.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_categoria_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_entrada_usecase.dart';
import 'package:riseg_one/features/inventario/presentation/asignaciones/widgets/entregar_equipo_dialog.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import '../../support/sesion_en_base.dart';

class _SesionMaestroDePrueba extends SesionController {
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

void main() {
  late AppDatabase db;
  late String pantalonId;
  late String telefonoId;
  late String empleadoId;

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

    final articuloRepo = ArticuloRepositoryImpl(db);
    final categoriaRepo = CategoriaArticuloRepositoryImpl(db);
    final inventarioRepo = InventarioRepositoryImpl(db);
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));

    final categoria =
        (await CrearCategoriaArticuloUseCase(categoriaRepo).ejecutar(nombre: 'Uniformes') as CrearCategoriaArticuloExitoso)
            .categoria;

    final pantalon = (await CrearArticuloUseCase(articuloRepo, categoriaRepo, generarCodigo).ejecutar(
      categoriaId: categoria.id,
      nombre: 'PANTALON NEGRO COMANDO',
      manejaVariante: false,
      manejaSerie: false,
    ) as CrearArticuloExitoso)
        .articulo;
    pantalonId = pantalon.id;
    await RegistrarEntradaUseCase(inventarioRepo, articuloRepo).ejecutar(articuloId: pantalonId, cantidad: 5, fecha: DateTime(2026, 8, 20));

    final telefono = (await CrearArticuloUseCase(articuloRepo, categoriaRepo, generarCodigo).ejecutar(
      categoriaId: categoria.id,
      nombre: 'TELEFONO CORPORATIVO',
      manejaVariante: false,
      manejaSerie: true,
    ) as CrearArticuloExitoso)
        .articulo;
    telefonoId = telefono.id;
    await inventarioRepo.registrarEntradaUnidad(
      articuloId: telefonoId,
      codigo: 'UNI-000001',
      numeroSerie: 'SN-0001',
      fecha: DateTime(2026, 8, 20),
    );

    empleadoId = (await db.into(db.empleado).insertReturning(
          EmpleadoCompanion.insert(
            numeroEmpleado: 1,
            nombres: 'Juan Manuel',
            apellidoPaterno: 'Zintzun',
            apellidoMaterno: const Value('Lopez'),
            sexo: 'masculino',
            fechaNacimiento: DateTime(1990, 1, 1),
            curp: 'ZILJ900101HDFXXX01',
            rfc: 'ZILJ900101AB1',
            nss: '12345678901',
            estadoCivil: 'soltero',
            fechaIngreso: DateTime(2026, 1, 1),
            aniosExperienciaSeguridad: 3,
          ),
        ))
        .id;
    // Etapa 3B: autorizar revalida contra la base, así que la
    // sesión de esta prueba tiene que corresponder a una cuenta real.
    await sembrarSesionEnBase(db, SesionUsuario( usuarioId: 'usuario-prueba', nombre: 'Usuario de prueba', nombreUsuario: 'prueba', esMaestro: true, permisos: {}, ));
  });

  tearDown(() => db.close());

  Future<void> montar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          sesionControllerProvider.overrideWith(_SesionMaestroDePrueba.new),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => ElevatedButton(
                key: const Key('abrir'),
                onPressed: () => mostrarDialogoEntregarEquipo(
                  context,
                  ref,
                  empleadoId: empleadoId,
                  empleadoNombre: 'Juan Manuel Zintzun Lopez',
                ),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('abrir')));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'camino feliz: agregar 1 línea fungible + 1 serializada y confirmar crea UNA Entrega con ambas Asignaciones vinculadas',
    (tester) async {
      await montar(tester);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      // Línea fungible: PANTALON NEGRO COMANDO × 2.
      await tester.tap(_selector(l10n.asignarArticuloCampoArticulo));
      await tester.pumpAndSettle();
      await tester.tap(find.text('PANTALON NEGRO COMANDO').last);
      await tester.pumpAndSettle();
      await tester.enterText(_campoTexto(l10n.asignarArticuloCampoCantidad), '2');
      await tester.tap(find.text(l10n.entregarEquipoBotonAgregar));
      await tester.pumpAndSettle();

      expect(find.textContaining('2 × PANTALON NEGRO COMANDO'), findsOneWidget);

      // Línea serializada: TELEFONO CORPORATIVO, marcar su única unidad.
      await tester.tap(_selector(l10n.asignarArticuloCampoArticulo));
      await tester.pumpAndSettle();
      await tester.tap(find.text('TELEFONO CORPORATIVO').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();

      expect(find.textContaining('TELEFONO CORPORATIVO · UNI-000001'), findsOneWidget);

      // Resumen en vivo: 3 unidades (2 + 1) en 2 conceptos.
      expect(find.text(l10n.entregarEquipoResumen(3, 2, 'Juan Manuel Zintzun Lopez')), findsOneWidget);

      await tester.enterText(_campoTexto(l10n.asignarArticuloCampoCondicion), 'Nuevo');
      await tester.tap(find.text(l10n.entregarEquipoBotonConfirmar));
      await tester.pumpAndSettle();

      expect(find.text(l10n.asignarArticuloExito), findsOneWidget);

      final asignacionRepo = AsignacionRepositoryImpl(db);
      final asignaciones = await asignacionRepo.listarActivasPorEmpleado(empleadoId);
      expect(asignaciones, hasLength(2));
      expect(asignaciones.every((a) => a.entregaId != null), isTrue);
      expect(asignaciones.map((a) => a.entregaId).toSet(), hasLength(1));
    },
  );

  testWidgets(
    'cantidad mayor al disponible bloquea "Agregar" con un mensaje inline, sin agregar la línea',
    (tester) async {
      await montar(tester);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      await tester.tap(_selector(l10n.asignarArticuloCampoArticulo));
      await tester.pumpAndSettle();
      await tester.tap(find.text('PANTALON NEGRO COMANDO').last);
      await tester.pumpAndSettle();
      await tester.enterText(_campoTexto(l10n.asignarArticuloCampoCantidad), '99');
      await tester.tap(find.text(l10n.entregarEquipoBotonAgregar));
      await tester.pumpAndSettle();

      expect(find.text(l10n.asignarArticuloErrorSobrepasaDisponible), findsOneWidget);
      expect(find.textContaining('× PANTALON NEGRO COMANDO'), findsNothing);
    },
  );

  testWidgets(
    'confirmar sin capturar la condición al entregar muestra el error y no cierra el diálogo',
    (tester) async {
      await montar(tester);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      await tester.tap(_selector(l10n.asignarArticuloCampoArticulo));
      await tester.pumpAndSettle();
      await tester.tap(find.text('PANTALON NEGRO COMANDO').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.entregarEquipoBotonAgregar));
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.entregarEquipoBotonConfirmar));
      await tester.pumpAndSettle();

      expect(find.text(l10n.entregarEquipoErrorCondicionRequerida), findsOneWidget);
      expect(find.text(l10n.entregarEquipoDialogoTitulo), findsOneWidget);
    },
  );
}
