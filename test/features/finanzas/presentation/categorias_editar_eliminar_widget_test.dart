// Etapa 18 — el menú ⋯ de Categorías financieras gana Editar y
// Eliminar (además de Archivar). La eliminación respeta integridad
// referencial: si un Ingreso/Egreso real referencia la categoría
// (`categoriaFinancieraId`, `onDelete: restrict`), se rechaza siempre
// con un mensaje explicativo, y Archivar sigue disponible como
// alternativa no destructiva — nunca se fuerza ni se rompe la
// referencia.

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
import 'package:riseg_one/features/finanzas/data/repositories/categoria_financiera_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_egreso_usecase.dart';
import 'package:riseg_one/features/finanzas/presentation/categorias/categorias_list_screen.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

const _usuarioMaestroId = 'usuario-maestro';

class _SesionMaestroDePrueba extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: _usuarioMaestroId,
      nombre: 'Maestro de prueba',
      nombreUsuario: 'maestro',
      esMaestro: true,
      permisos: {},
    );
  }
}

class _SesionNormalDePrueba extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-normal',
      nombre: 'Usuario normal',
      nombreUsuario: 'normal',
      esMaestro: false,
      permisos: {'finanzas.ver', 'categoriasFinancieras.crear', 'categoriasFinancieras.corregir', 'categoriasFinancieras.archivar'},
    );
  }
}

Future<void> _pumpScreen(WidgetTester tester, AppDatabase db, SesionController Function() sesion) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(sesion),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: CategoriasListScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _abrirMenu(WidgetTester tester, String categoriaId) async {
  await tester.tap(find.byKey(Key('categoria_menu_acciones_$categoriaId')));
  await tester.pumpAndSettle();
}

void main() {
  late AppDatabase db;
  late CategoriaFinancieraRepositoryImpl categoriaRepo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    categoriaRepo = CategoriaFinancieraRepositoryImpl(db);
    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(
            id: const Value(_usuarioMaestroId),
            nombre: 'Maestro de prueba',
            nombreUsuario: 'maestro',
            passwordHash: 'x',
            esMaestro: const Value(true),
          ),
        );
  });

  tearDown(() => db.close());

  testWidgets('Maestro edita una categoría desde el menú ⋯ y el listado refleja el cambio', (tester) async {
    final categoria = await categoriaRepo.crear(
      codigo: 'GAS-001',
      nombre: 'Gastos varios',
      tipo: 'egreso',
      tipoMovimiento: 'operativo',
    );

    await _pumpScreen(tester, db, _SesionMaestroDePrueba.new);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await _abrirMenu(tester, categoria.id);
    await tester.tap(find.text(l10n.categoriaAccionEditar));
    await tester.pumpAndSettle();

    expect(find.text(l10n.categoriaDialogoTituloEditar), findsOneWidget);
    final campoNombre = find.byType(TextFormField).at(1);
    await tester.enterText(campoNombre, 'Gastos operativos diversos');
    await tester.tap(find.widgetWithText(RisegButton, l10n.categoriaDialogoBotonGuardar));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Gastos operativos diversos'), findsOneWidget);
    expect(find.text('Gastos varios'), findsNothing);

    final actualizada = await categoriaRepo.obtenerPorId(categoria.id);
    expect(actualizada!.nombre, 'Gastos operativos diversos');
  });

  testWidgets('Maestro elimina físicamente una categoría sin uso desde el menú ⋯', (tester) async {
    final categoria = await categoriaRepo.crear(
      codigo: 'GAS-002',
      nombre: 'Categoría sin uso',
      tipo: 'egreso',
      tipoMovimiento: 'operativo',
    );

    await _pumpScreen(tester, db, _SesionMaestroDePrueba.new);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await _abrirMenu(tester, categoria.id);
    await tester.tap(find.text(l10n.eliminacionFisicaAccionMenu));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(RisegButton, l10n.eliminacionFisicaBotonConfirmar), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'Captura de prueba, categoría nunca se usó');
    await tester.tap(find.widgetWithText(RisegButton, l10n.eliminacionFisicaBotonConfirmar));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Categoría sin uso'), findsNothing);
    expect(await categoriaRepo.obtenerPorId(categoria.id), isNull);
  });

  testWidgets(
    'una categoría utilizada por un Egreso real rechaza la eliminación física y conserva Archivar como alternativa',
    (tester) async {
      final categoria = await categoriaRepo.crear(
        codigo: 'GAS-003',
        nombre: 'Categoría en uso',
        tipo: 'egreso',
        tipoMovimiento: 'operativo',
      );
      final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
      await RegistrarEgresoUseCase(EgresoRepositoryImpl(db), generarCodigo, DeudaRepositoryImpl(db, EgresoRepositoryImpl(db))).ejecutar(
        monto: 50000,
        fecha: DateTime(2026, 1, 10),
        formaPago: 'efectivo',
        concepto: 'Gasto real de prueba',
        categoriaFinancieraId: categoria.id,
      );

      await _pumpScreen(tester, db, _SesionMaestroDePrueba.new);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      await _abrirMenu(tester, categoria.id);
      await tester.tap(find.text(l10n.eliminacionFisicaAccionMenu));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, 'Intento de limpieza, no debería proceder');
      await tester.tap(find.widgetWithText(RisegButton, l10n.eliminacionFisicaBotonConfirmar));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('1 egreso(s)'), findsOneWidget);
      expect(find.text('Categoría en uso'), findsOneWidget, reason: 'la categoría bloqueada nunca se elimina');

      final sigueExistiendo = await categoriaRepo.obtenerPorId(categoria.id);
      expect(sigueExistiendo, isNotNull);

      await _abrirMenu(tester, categoria.id);
      expect(find.text(l10n.categoriaAccionArchivar), findsOneWidget, reason: 'Archivar sigue disponible como alternativa');
    },
  );

  testWidgets('un usuario normal ve Editar y Archivar pero nunca Eliminar físicamente', (tester) async {
    final categoria = await categoriaRepo.crear(
      codigo: 'GAS-004',
      nombre: 'Categoría cualquiera',
      tipo: 'egreso',
      tipoMovimiento: 'operativo',
    );

    await _pumpScreen(tester, db, _SesionNormalDePrueba.new);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await _abrirMenu(tester, categoria.id);

    expect(find.text(l10n.categoriaAccionEditar), findsOneWidget);
    expect(find.text(l10n.categoriaAccionArchivar), findsOneWidget);
    expect(find.text(l10n.eliminacionFisicaAccionMenu), findsNothing);
  });
}
