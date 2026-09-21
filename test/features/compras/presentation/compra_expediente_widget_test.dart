// Etapa 19 — pasada UX/UI de Compras, Expediente: cubre la cabecera
// (folio + proveedor/fecha + badge), el resumen (Total/Artículos/
// Unidades/Forma de pago), el menú ⋯ Maestro-only, la sección
// Inventario/Finanzas con datos reales (incluido el folio real del
// Egreso vía la FK `Compra.egresoId`) y la navegación Detalle→Artículo
// — nada de esto tenía una prueba de pantalla dedicada antes (solo se
// llegaba de paso desde `corregir_compra_screen_test.dart`).

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

class _SesionNormalDePrueba extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-normal',
      nombre: 'Usuario normal',
      nombreUsuario: 'normal',
      esMaestro: false,
      permisos: {'compras.ver', 'compras.crear', 'compras.cancelar'},
    );
  }
}

Future<CompraData> _sembrarCompra(AppDatabase db) async {
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

  final resultado = await registrarCompra.ejecutar(
    fecha: DateTime(2026, 8, 19),
    proveedor: 'ML',
    formaPago: FormaPago.efectivo.name,
    partidas: [
      PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: camisola.id, cantidad: 3, costoUnitario: 20000),
    ],
  ) as RegistrarCompraExitosa;
  return resultado.compra;
}

Future<void> _pumpEnExpediente(WidgetTester tester, AppDatabase db, {bool maestro = true}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        contarUsuariosProvider.overrideWith((ref) async => 1),
        sesionControllerProvider.overrideWith(maestro ? _SesionMaestroDePrueba.new : _SesionNormalDePrueba.new),
      ],
      child: RisegOneApp(router: createAppRouter()),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const Key('nav_item_compras')));
  await tester.pumpAndSettle();

  await tester.ensureVisible(find.text('CAMISOLA ×3'));
  await tester.tap(find.text('CAMISOLA ×3'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('cabecera muestra folio + proveedor/fecha + badge, y el resumen es Total/Artículos/Unidades/Forma de pago', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final compra = await _sembrarCompra(db);

    await _pumpEnExpediente(tester, db);
    expect(tester.takeException(), isNull);

    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    expect(find.text(compra.folioCompra), findsWidgets);
    expect(find.textContaining('ML'), findsWidgets);
    expect(find.text(l10n.compraEstatusRegistrada), findsOneWidget);

    expect(find.text(l10n.compraExpedienteResumenTotal), findsOneWidget);
    expect(find.text(l10n.compraExpedienteResumenArticulos), findsOneWidget);
    // 3 unidades de un solo renglón — Artículos=1, Unidades=3, nunca
    // confundidos entre sí.
    expect(find.text('1'), findsWidgets);
    expect(find.text('3'), findsWidgets);
    expect(find.text(l10n.compraExpedienteResumenUnidades), findsOneWidget);
    // "Forma de pago" también es la etiqueta del campo en "Datos de la
    // compra" — mismo texto, dos apariciones legítimas.
    expect(find.text(l10n.compraExpedienteResumenFormaPago), findsWidgets);
  });

  testWidgets('Maestro ve el menú ⋯ con Eliminar físicamente; un usuario normal no lo ve', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _sembrarCompra(db);

    await _pumpEnExpediente(tester, db);

    final l10n = await AppLocalizations.delegate.load(const Locale('es'));
    expect(find.byKey(const Key('compra_expediente_menu_acciones')), findsOneWidget);

    await tester.tap(find.byKey(const Key('compra_expediente_menu_acciones')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.eliminacionFisicaAccionMenu), findsOneWidget);

    // Cierra el menú antes de terminar el test (evita advertencias de
    // overlay abierto al desmontar).
    await tester.tapAt(tester.getTopLeft(find.byType(ModalBarrier).last));
    await tester.pumpAndSettle();
  });

  testWidgets('un usuario normal no ve el menú ⋯ (Eliminar físicamente es Maestro-only)', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _sembrarCompra(db);

    await _pumpEnExpediente(tester, db, maestro: false);

    expect(find.byKey(const Key('compra_expediente_menu_acciones')), findsNothing);
  });

  testWidgets('la sección Finanzas muestra el folio y monto reales del Egreso vinculado (FK Compra.egresoId)', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _sembrarCompra(db);
    final egreso = await db.select(db.egreso).getSingle();

    await _pumpEnExpediente(tester, db);

    final l10n = await AppLocalizations.delegate.load(const Locale('es'));
    expect(find.text(l10n.compraIntegracionesEgresoRegistrado), findsOneWidget);
    expect(find.textContaining(egreso.folioEgreso), findsOneWidget);
  });

  testWidgets('tocar el renglón de Artículo en el Detalle navega al expediente del Artículo', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _sembrarCompra(db);

    await _pumpEnExpediente(tester, db);

    await tester.ensureVisible(find.text('CAMISOLA').first);
    await tester.tap(find.text('CAMISOLA').first);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('compra_expediente_menu_acciones')), findsNothing, reason: 'ya no es el expediente de la Compra');
  });
}
