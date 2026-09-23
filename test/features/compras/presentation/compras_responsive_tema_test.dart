// Etapa 19 — pasada UX/UI de Compras. Smoke de tema oscuro +
// breakpoints (1366×768 y 500×900) para las 3 pantallas que ganaron
// resumen KPI/filtros/RisegFieldGrid en esta etapa: listado, expediente
// y el formulario "Registrar compra". Mismo criterio que el resto de
// RISEG ONE: sin herramienta de captura de pantalla, la evidencia es
// "cero overflow / cero excepción", nunca una comparación de píxeles.
//
// 900×560 se excluye deliberadamente — ver el doc comment de
// `inventario_responsive_tema_test.dart` (Etapa 18): es la esquina
// exacta donde coinciden los dos pisos de colapso del sidebar, un
// problema preexistente del Shell, fuera de alcance de Compras.

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:riseg_one/app/app.dart';
import 'package:riseg_one/app/router/app_router.dart';
import 'package:riseg_one/app/theme/theme_mode_controller.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/compras/data/repositories/compra_repository_impl.dart';
import 'package:riseg_one/features/compras/data/tables/compra_partida_table.dart' show DestinoCompraPartida;
import 'package:riseg_one/features/compras/domain/repositories/compra_repository.dart' show PartidaCompraInput;
import 'package:riseg_one/features/compras/domain/usecases/registrar_compra_usecase.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/categoria_articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/inventario_repository_impl.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_categoria_articulo_usecase.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';
import '../../../support/sesion_en_base.dart';

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

class _TemaFijo extends ThemeModeController {
  _TemaFijo(this.modo);
  final ThemeMode modo;

  @override
  ThemeMode build() => modo;
}

Future<void> _sembrar(AppDatabase db) async {
  final articuloRepo = ArticuloRepositoryImpl(db);
  final categoriaRepo = CategoriaArticuloRepositoryImpl(db);
  final inventarioRepo = InventarioRepositoryImpl(db);
  final egresoRepo = EgresoRepositoryImpl(db);
  final deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
  final compraRepo = CompraRepositoryImpl(db, inventarioRepo, articuloRepo, egresoRepo, deudaRepo);
  final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
  final registrarCompra = RegistrarCompraUseCase(compraRepo, articuloRepo, inventarioRepo, deudaRepo, generarCodigo);

  final categoria =
      (await CrearCategoriaArticuloUseCase(categoriaRepo).ejecutar(nombre: 'Uniformes') as CrearCategoriaArticuloExitoso)
          .categoria;
  final camisola = (await CrearArticuloUseCase(articuloRepo, categoriaRepo, generarCodigo).ejecutar(
    categoriaId: categoria.id,
    nombre: 'CAMISOLA',
  ) as CrearArticuloExitoso)
      .articulo;

  await registrarCompra.ejecutar(
    fecha: DateTime(2026, 8, 19),
    proveedor: 'ML',
    formaPago: FormaPago.efectivo.name,
    partidas: [
      PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: camisola.id, cantidad: 3, costoUnitario: 20000),
    ],
  );
}

const _anchos = [Size(1366, 768), Size(500, 900)];

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  final temas = {'claro': ThemeMode.light, 'oscuro': ThemeMode.dark};

  for (final entradaTema in temas.entries) {
    final etiquetaTema = entradaTema.key;
    final modo = entradaTema.value;

    for (final tamano in _anchos) {
      final etiqueta = '${tamano.width.toInt()}×${tamano.height.toInt()}, $etiquetaTema';

      Future<AppDatabase> pump(WidgetTester tester) async {
        tester.view.physicalSize = tamano;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final db = AppDatabase(NativeDatabase.memory());
        // Etapa 3B: autorizar revalida contra la base, así que el
        // escenario de la sesión tiene que estar persistido.
        await sembrarSesionEnBase(db, SesionUsuario( usuarioId: 'usuario-prueba', nombre: 'Usuario de prueba', nombreUsuario: 'prueba', esMaestro: true, permisos: {}, ));
        addTearDown(db.close);
        await _sembrar(db);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appDatabaseProvider.overrideWithValue(db),
              contarUsuariosProvider.overrideWith((ref) async => 1),
              sesionControllerProvider.overrideWith(_SesionMaestroDePrueba.new),
              themeModeControllerProvider.overrideWith(() => _TemaFijo(modo)),
            ],
            child: RisegOneApp(router: createAppRouter()),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('nav_item_compras')));
        await tester.pumpAndSettle();
        return db;
      }

      testWidgets('Compras — listado ($etiqueta): cero overflow', (tester) async {
        await pump(tester);
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('compras_boton_registrar')), findsOneWidget);
      });

      testWidgets('Compras — expediente ($etiqueta): cero overflow', (tester) async {
        await pump(tester);
        await tester.ensureVisible(find.text('CAMISOLA ×3'));
        await tester.tap(find.text('CAMISOLA ×3'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('compra_expediente_menu_acciones')), findsOneWidget);
      });

      testWidgets('Compras — Registrar compra ($etiqueta): cero overflow', (tester) async {
        await pump(tester);
        await tester.ensureVisible(find.byKey(const Key('compras_boton_registrar')));
        await tester.tap(find.byKey(const Key('compras_boton_registrar')));
        await tester.pumpAndSettle();

        final l10n = await AppLocalizations.delegate.load(const Locale('es'));
        expect(tester.takeException(), isNull);
        expect(find.text(l10n.compraInformacionSeccionTitulo), findsOneWidget);
        expect(find.text(l10n.compraPartidasSeccionTitulo), findsOneWidget);
      });
    }
  }
}
