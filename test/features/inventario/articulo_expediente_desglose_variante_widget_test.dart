// Etapa 15 — desglose de existencia por talla/variante, verificado en
// la pantalla real (no solo en el cálculo del repositorio). Cubre: la
// sección "Existencia por talla" reemplaza los chips CH/EXG/G/M/XXG
// (que antes solo informaban qué tallas existen, sin su inventario)
// por un resumen rápido + la tabla completa Total/Disponible/Dañado/
// Perdido; y que un artículo sin variantes conserva únicamente el
// resumen general, sin tabla ni sección vacía/absurda.

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:riseg_one/app/app.dart';
import 'package:riseg_one/app/router/app_router.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/categoria_articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/inventario_repository_impl.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_categoria_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_entrada_usecase.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

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

Future<String> _sembrarCamisolaConVariantes(AppDatabase db) async {
  final articuloRepo = ArticuloRepositoryImpl(db);
  final categoriaRepo = CategoriaArticuloRepositoryImpl(db);
  final inventarioRepo = InventarioRepositoryImpl(db);
  final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));

  final categoria =
      (await CrearCategoriaArticuloUseCase(categoriaRepo).ejecutar(nombre: 'Uniformes') as CrearCategoriaArticuloExitoso)
          .categoria;
  final articulo = (await CrearArticuloUseCase(articuloRepo, categoriaRepo, generarCodigo).ejecutar(
    categoriaId: categoria.id,
    nombre: 'CAMISOLA',
    manejaVariante: true,
    manejaSerie: false,
  ) as CrearArticuloExitoso)
      .articulo;

  final ch = await articuloRepo.crearVariante(articuloId: articulo.id, valor: 'CH');
  final g = await articuloRepo.crearVariante(articuloId: articulo.id, valor: 'G');
  await articuloRepo.crearVariante(articuloId: articulo.id, valor: 'M');

  await RegistrarEntradaUseCase(inventarioRepo, articuloRepo).ejecutar(
    articuloId: articulo.id,
    varianteId: ch.id,
    cantidad: 1,
    costoUnitario: 33000,
    fecha: DateTime(2026, 8, 12),
  );
  await RegistrarEntradaUseCase(inventarioRepo, articuloRepo).ejecutar(
    articuloId: articulo.id,
    varianteId: g.id,
    cantidad: 5,
    costoUnitario: 33000,
    fecha: DateTime(2026, 8, 12),
  );

  return articulo.id;
}

Future<String> _sembrarArticuloSinVariantes(AppDatabase db) async {
  final articuloRepo = ArticuloRepositoryImpl(db);
  final categoriaRepo = CategoriaArticuloRepositoryImpl(db);
  final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));

  final categoria =
      (await CrearCategoriaArticuloUseCase(categoriaRepo).ejecutar(nombre: 'Papelería') as CrearCategoriaArticuloExitoso)
          .categoria;
  final articulo = (await CrearArticuloUseCase(articuloRepo, categoriaRepo, generarCodigo).ejecutar(
    categoriaId: categoria.id,
    nombre: 'GUANTES',
    manejaVariante: false,
    manejaSerie: false,
  ) as CrearArticuloExitoso)
      .articulo;

  return articulo.id;
}

Future<void> _pumpEnExpediente(
  WidgetTester tester,
  AppDatabase db, {
  required String nombreArticulo,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        contarUsuariosProvider.overrideWith((ref) async => 1),
        sesionControllerProvider.overrideWith(_SesionMaestroDePrueba.new),
      ],
      child: RisegOneApp(router: createAppRouter()),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const Key('nav_item_inventario')));
  await tester.pumpAndSettle();
  // Etapa 18: el listado de Artículos ganó un resumen KPI + fila de
  // filtros arriba de la tabla — en la ventana de prueba por defecto
  // (800×600) la fila del artículo queda fuera de la vista inicial
  // (la pantalla es un `SingleChildScrollView`, así que existe pero
  // no es visible sin desplazar). `ensureVisible` reemplaza el tap a
  // ciegas que antes acertaba por casualidad.
  await tester.ensureVisible(find.text(nombreArticulo).first);
  await tester.tap(find.text(nombreArticulo).first);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'artículo con variantes: la sección "Existencia por talla" muestra el resumen rápido y la tabla '
    'completa por variante, y el resumen general coincide con la suma',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await _sembrarCamisolaConVariantes(db);

      await _pumpEnExpediente(tester, db, nombreArticulo: 'CAMISOLA');
      expect(tester.takeException(), isNull);

      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      expect(find.text(l10n.articuloExpedienteSeccionVariantes), findsOneWidget, reason: 'título de la sección renombrada');

      // Resumen rápido — una sola línea con "talla cantidad disponible"
      // por cada variante, reemplazando los chips que antes no decían
      // nada del inventario.
      expect(find.textContaining(l10n.articuloExpedienteExistenciaVarianteResumen('CH', 1)), findsOneWidget);
      expect(find.textContaining(l10n.articuloExpedienteExistenciaVarianteResumen('G', 5)), findsOneWidget);
      expect(find.textContaining(l10n.articuloExpedienteExistenciaVarianteResumen('M', 0)), findsOneWidget);

      // Tabla completa Total/Disponible/Dañado/Perdido por variante —
      // "CH"/"G" también aparecen en la tabla de Movimientos (columna
      // Talla/Unidad de su propia entrada), así que solo se confirma
      // que la celda de la tabla de variantes SÍ está presente, no su
      // unicidad en toda la pantalla.
      expect(find.text(l10n.articuloExpedienteColumnaTalla), findsOneWidget);
      expect(find.text('CH'), findsWidgets);
      expect(find.text('G'), findsWidgets);
      expect(find.text('M'), findsWidgets);

      // Resumen general = suma de variantes (CH 1 + G 5 + M 0 = 6).
      final camposGenerales = find.text('6');
      expect(camposGenerales, findsNWidgets(2), reason: 'Total y Disponible generales, ambos en 6 (sin daño/pérdida)');
    },
  );

  testWidgets(
    'artículo sin variantes: nunca aparece la sección de tallas ni una tabla vacía/absurda',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await _sembrarArticuloSinVariantes(db);

      await _pumpEnExpediente(tester, db, nombreArticulo: 'GUANTES');
      expect(tester.takeException(), isNull);

      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      expect(find.text(l10n.articuloExpedienteSeccionVariantes), findsNothing, reason: 'sin variantes, la sección no debe existir');
      expect(find.text(l10n.articuloExpedienteColumnaTalla), findsNothing);
    },
  );
}
