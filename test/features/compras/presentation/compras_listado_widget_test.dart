// Etapa 19 — pasada UX/UI de Compras: cubre el resumen KPI, el nuevo
// filtro de Forma de pago, la identidad de la tabla (Compra = folio +
// fecha) y los dos empty states (sin compras vs sin coincidencias) en
// el listado real — antes solo cubierto a nivel repositorio/smoke test
// parcial.
//
// Etapa 19.1 (ajuste puntual): "Artículos comprados" reemplaza la
// columna de conteo — nombre real + cantidad real por renglón, nunca
// un número agregado — y "Proveedor/establecimiento" se retira de la
// tabla (sigue en el filtro/formulario/expediente).

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
import 'package:riseg_one/core/design_system/design_system.dart' show RisegTextField;
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
  final guantes = (await CrearArticuloUseCase(articuloRepo, categoriaRepo, generarCodigo).ejecutar(
    categoriaId: categoria.id,
    nombre: 'GUANTES',
  ) as CrearArticuloExitoso)
      .articulo;

  // Compra 1: efectivo, 2 renglones de Inventario (3+2 = 5 unidades),
  // proveedor "ML".
  await registrarCompra.ejecutar(
    fecha: DateTime(2026, 8, 10),
    proveedor: 'ML',
    formaPago: FormaPago.efectivo.name,
    partidas: [
      PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: camisola.id, cantidad: 3, costoUnitario: 20000),
      PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: guantes.id, cantidad: 2, costoUnitario: 5000),
    ],
  );

  // Compra 2: transferencia, 1 renglón, proveedor "Grupo MJ&MSA".
  await registrarCompra.ejecutar(
    fecha: DateTime(2026, 8, 15),
    proveedor: 'Grupo MJ&MSA',
    formaPago: FormaPago.transferencia.name,
    partidas: [
      PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: camisola.id, cantidad: 1, costoUnitario: 20000),
    ],
  );
}

Future<void> _pumpEnCompras(WidgetTester tester, AppDatabase db) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionMaestroDePrueba.new),
      ],
      child: RisegOneApp(router: createAppRouter()),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const Key('nav_item_compras')));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('el resumen KPI distingue Compras/Total/Artículos adquiridos/Proveedores, y la tabla no confunde renglones con unidades', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    // Etapa 3B: autorizar revalida contra la base, así que el
    // escenario de la sesión tiene que estar persistido.
    await sembrarSesionEnBase(db, const SesionUsuario( usuarioId: 'usuario-prueba', nombre: 'Usuario de prueba', nombreUsuario: 'prueba', esMaestro: true, permisos: {}, ));
    addTearDown(db.close);
    await _sembrar(db);

    await _pumpEnCompras(tester, db);
    expect(tester.takeException(), isNull);

    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    // 2 Compras, total = (3×200 + 2×50 + 1×200) = $1,000.00,
    // artículos adquiridos (suma de cantidades) = 3+2+1 = 6,
    // proveedores distintos = 2 ("ML", "Grupo MJ&MSA").
    expect(find.text(l10n.comprasResumenComprasDelPeriodo), findsOneWidget);
    expect(find.text('2'), findsWidgets);
    expect(find.text(l10n.comprasResumenTotalComprado), findsOneWidget);
    expect(find.text(l10n.comprasResumenArticulosAdquiridos), findsOneWidget);
    expect(find.text('6'), findsWidgets);
    expect(find.text(l10n.comprasResumenProveedores), findsOneWidget);

    // "Artículos comprados" muestra nombre real + cantidad real por
    // renglón — nunca "2 artículos" (conteo) ni "5 artículos" (suma de
    // unidades confundida con renglones).
    expect(find.text('CAMISOLA ×3 · GUANTES ×2'), findsOneWidget);
    expect(find.text('CAMISOLA ×1'), findsOneWidget);

    // Proveedor/establecimiento ya no es columna del listado — sigue
    // existiendo como filtro (una sola aparición de su etiqueta, no
    // una segunda como encabezado de columna).
    expect(find.text(l10n.comprasFiltroProveedor), findsOneWidget);
  });

  testWidgets('el filtro de Forma de pago narrows la tabla y "Limpiar filtros" restaura todo', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    // Etapa 3B: autorizar revalida contra la base, así que el
    // escenario de la sesión tiene que estar persistido.
    await sembrarSesionEnBase(db, const SesionUsuario( usuarioId: 'usuario-prueba', nombre: 'Usuario de prueba', nombreUsuario: 'prueba', esMaestro: true, permisos: {}, ));
    addTearDown(db.close);
    await _sembrar(db);

    await _pumpEnCompras(tester, db);

    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    // Proveedor ya no es columna visible — se identifica cada Compra
    // por su columna "Artículos comprados" (Compra 1 = efectivo,
    // Compra 2 = transferencia).
    expect(find.text('CAMISOLA ×3 · GUANTES ×2'), findsOneWidget);
    expect(find.text('CAMISOLA ×1'), findsOneWidget);

    // Orden de los `RisegSelect<String?>` en la fila de filtros:
    // Artículo (0), Forma de pago (1), Estatus (2) — mismo tipo
    // genérico para los tres.
    await tester.ensureVisible(find.byType(DropdownButtonFormField<String?>).at(1));
    await tester.tap(find.byType(DropdownButtonFormField<String?>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.formaPagoTransferencia).last);
    await tester.pumpAndSettle();

    expect(find.text('CAMISOLA ×3 · GUANTES ×2'), findsNothing);
    expect(find.text('CAMISOLA ×1'), findsOneWidget);

    await tester.ensureVisible(find.text(l10n.comprasLimpiarFiltros));
    await tester.tap(find.text(l10n.comprasLimpiarFiltros));
    await tester.pumpAndSettle();

    expect(find.text('CAMISOLA ×3 · GUANTES ×2'), findsOneWidget);
    expect(find.text('CAMISOLA ×1'), findsOneWidget);
  });

  testWidgets('tocar una fila abre el expediente de la Compra correspondiente', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    // Etapa 3B: autorizar revalida contra la base, así que el
    // escenario de la sesión tiene que estar persistido.
    await sembrarSesionEnBase(db, const SesionUsuario( usuarioId: 'usuario-prueba', nombre: 'Usuario de prueba', nombreUsuario: 'prueba', esMaestro: true, permisos: {}, ));
    addTearDown(db.close);
    await _sembrar(db);

    await _pumpEnCompras(tester, db);

    // Se toca por el contenido de "Artículos comprados" (Proveedor ya
    // no es columna del listado).
    await tester.ensureVisible(find.text('CAMISOLA ×3 · GUANTES ×2'));
    await tester.tap(find.text('CAMISOLA ×3 · GUANTES ×2'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('compras_boton_registrar')), findsNothing, reason: 'ya no es el listado');
    expect(find.text('ML'), findsWidgets, reason: 'proveedor sigue visible en el expediente');
  });

  testWidgets('sin compras en absoluto muestra el empty state "Sin compras registradas"; filtrado sin coincidencias muestra el compacto', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    // Etapa 3B: autorizar revalida contra la base, así que el
    // escenario de la sesión tiene que estar persistido.
    await sembrarSesionEnBase(db, const SesionUsuario( usuarioId: 'usuario-prueba', nombre: 'Usuario de prueba', nombreUsuario: 'prueba', esMaestro: true, permisos: {}, ));
    addTearDown(db.close);
    // Sin sembrar ninguna Compra.

    await _pumpEnCompras(tester, db);
    expect(tester.takeException(), isNull);

    final l10n = await AppLocalizations.delegate.load(const Locale('es'));
    expect(find.text(l10n.comprasListadoVacioTitulo), findsOneWidget);
    expect(find.text(l10n.comprasListadoVacioMensaje), findsOneWidget);
  });

  testWidgets('un filtro sin coincidencias usa el empty state compacto "Sin compras"', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    // Etapa 3B: autorizar revalida contra la base, así que el
    // escenario de la sesión tiene que estar persistido.
    await sembrarSesionEnBase(db, const SesionUsuario( usuarioId: 'usuario-prueba', nombre: 'Usuario de prueba', nombreUsuario: 'prueba', esMaestro: true, permisos: {}, ));
    addTearDown(db.close);
    await _sembrar(db);

    await _pumpEnCompras(tester, db);

    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    final campoFolio = find.descendant(
      of: find.byWidgetPredicate((w) => w is RisegTextField && w.label == l10n.comprasFiltroFolio),
      matching: find.byType(TextFormField),
    );
    await tester.ensureVisible(campoFolio);
    await tester.enterText(campoFolio, 'NO-EXISTE');
    await tester.pumpAndSettle();

    expect(find.text(l10n.comprasListadoVacioFiltradoTitulo), findsOneWidget);
    expect(find.text(l10n.comprasListadoVacioFiltradoMensaje), findsOneWidget);
  });

  testWidgets('con más de 2 renglones, "Artículos comprados" trunca a "+N más" y el tooltip muestra la lista completa', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    // Etapa 3B: autorizar revalida contra la base, así que el
    // escenario de la sesión tiene que estar persistido.
    await sembrarSesionEnBase(db, const SesionUsuario( usuarioId: 'usuario-prueba', nombre: 'Usuario de prueba', nombreUsuario: 'prueba', esMaestro: true, permisos: {}, ));
    addTearDown(db.close);

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

    Future<ArticuloData> crear(String nombre) async => (await CrearArticuloUseCase(articuloRepo, categoriaRepo, generarCodigo).ejecutar(
          categoriaId: categoria.id,
          nombre: nombre,
        ) as CrearArticuloExitoso)
        .articulo;

    final camisola = await crear('CAMISOLA');
    final pantalon = await crear('PANTALÓN NEGRO COMANDO');
    final chaleco = await crear('CHALECO REFLEJANTE');
    final botas = await crear('BOTAS TACTICAS');

    await registrarCompra.ejecutar(
      fecha: DateTime(2026, 8, 20),
      proveedor: 'ML',
      formaPago: FormaPago.efectivo.name,
      partidas: [
        PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: camisola.id, cantidad: 3, costoUnitario: 20000),
        PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: pantalon.id, cantidad: 2, costoUnitario: 30000),
        PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: chaleco.id, cantidad: 1, costoUnitario: 15000),
        PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: botas.id, cantidad: 4, costoUnitario: 50000),
      ],
    );

    await _pumpEnCompras(tester, db);
    expect(tester.takeException(), isNull);

    // 4 renglones, se muestran los primeros 2 + "+2 más" — nunca la
    // fila crece para caber los 4.
    expect(find.text('CAMISOLA ×3 · PANTALÓN NEGRO COMANDO ×2 · +2 más'), findsOneWidget);
    expect(find.text('CAMISOLA ×3 · PANTALÓN NEGRO COMANDO ×2 · CHALECO REFLEJANTE ×1 · BOTAS TACTICAS ×4'), findsNothing);

    final tooltip = tester.widget<Tooltip>(
      find.ancestor(of: find.text('CAMISOLA ×3 · PANTALÓN NEGRO COMANDO ×2 · +2 más'), matching: find.byType(Tooltip)),
    );
    expect(tooltip.message, 'CAMISOLA ×3 · PANTALÓN NEGRO COMANDO ×2 · CHALECO REFLEJANTE ×1 · BOTAS TACTICAS ×4');
  });

  testWidgets('una Compra solo de gasto directo (sin renglones de Inventario) muestra "—" en Artículos comprados', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    // Etapa 3B: autorizar revalida contra la base, así que el
    // escenario de la sesión tiene que estar persistido.
    await sembrarSesionEnBase(db, const SesionUsuario( usuarioId: 'usuario-prueba', nombre: 'Usuario de prueba', nombreUsuario: 'prueba', esMaestro: true, permisos: {}, ));
    addTearDown(db.close);

    final articuloRepo = ArticuloRepositoryImpl(db);
    final inventarioRepo = InventarioRepositoryImpl(db);
    final egresoRepo = EgresoRepositoryImpl(db);
    final deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
    final compraRepo = CompraRepositoryImpl(db, inventarioRepo, articuloRepo, egresoRepo, deudaRepo);
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    final registrarCompra = RegistrarCompraUseCase(compraRepo, articuloRepo, inventarioRepo, deudaRepo, generarCodigo);

    await registrarCompra.ejecutar(
      fecha: DateTime(2026, 8, 20),
      proveedor: 'Gasolinera del Centro',
      formaPago: FormaPago.efectivo.name,
      partidas: [
        PartidaCompraInput(destino: DestinoCompraPartida.gastoDirecto.name, concepto: 'Combustible', cantidad: 1, costoUnitario: 80000),
      ],
    );

    await _pumpEnCompras(tester, db);
    expect(tester.takeException(), isNull);

    final l10n = await AppLocalizations.delegate.load(const Locale('es'));
    expect(find.text(l10n.comprasArticulosSinRenglones), findsOneWidget);
  });
}
