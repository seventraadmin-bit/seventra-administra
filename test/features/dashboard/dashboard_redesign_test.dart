// Etapa 15 (rediseño visual del Dashboard) — pruebas específicas de la
// nueva presentación: Actividad reciente unificada y ordenada por
// fecha real (nunca una hora inventada), ausencia de tendencias
// ficticias (no existe fuente real de comparación contra el periodo
// anterior hoy), y responsive sin overflow con datos reales cargados
// (no solo con la base de datos vacía, que ya cubre
// `dashboard_screen_test.dart`).

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:riseg_one/app/app.dart';
import 'package:riseg_one/app/router/app_router.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

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

Future<AppDatabase> _sembrarActividadDePrueba() async {
  final db = AppDatabase(NativeDatabase.memory());
  final hoy = DateTime.now();

  final cliente = await db.into(db.cliente).insertReturning(
        ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'MIRABILIA'),
      );

  // Compra — la más antigua de las tres (hace 2 días).
  await db.into(db.compra).insert(
        CompraCompanion.insert(
          folioCompra: 'COM-000001',
          fecha: hoy.subtract(const Duration(days: 2)),
          proveedor: const Value('Ferretería ML'),
          formaPago: 'transferencia',
        ),
      );

  // Pago — la más reciente (hoy).
  await db.into(db.pago).insert(
        PagoCompanion.insert(
          folioPago: 'PAG-000001',
          clienteId: cliente.id,
          montoTotal: 1750000,
          fechaPago: hoy,
          formaPago: 'transferencia',
        ),
      );

  // Movimiento de inventario — hace 1 día (queda en medio).
  final categoria = await db.into(db.categoriaArticulo).insertReturning(
        CategoriaArticuloCompanion.insert(nombre: 'Uniformes'),
      );
  final articulo = await db.into(db.articulo).insertReturning(
        ArticuloCompanion.insert(folio: 'ART-000001', nombre: 'CAMISOLA', categoriaId: categoria.id),
      );
  await db.into(db.movimientoInventario).insert(
        MovimientoInventarioCompanion.insert(
          articuloId: articulo.id,
          tipoMovimiento: 'entrada',
          cantidad: 5,
          fecha: hoy.subtract(const Duration(days: 1)),
        ),
      );

  return db;
}

Future<void> _pumpApp(WidgetTester tester, AppDatabase db, {Size tamano = const Size(1440, 900)}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});

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
}

void main() {
  testWidgets('Actividad reciente unificada ordena Pago (hoy) → Movimiento (ayer) → Compra (hace 2 días)', (tester) async {
    final db = await _sembrarActividadDePrueba();
    addTearDown(db.close);
    await _pumpApp(tester, db);

    expect(tester.takeException(), isNull);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    expect(find.text(l10n.dashboardSeccionActividad), findsOneWidget);
    expect(find.text(l10n.dashboardActividadItemPago), findsOneWidget);
    expect(find.text(l10n.dashboardActividadItemCompra), findsOneWidget);
    // "entrada" → mismo texto que ya usa `movimientoTipoLabel` en el
    // resto del proyecto (Etapa 7A/7D), no un texto nuevo inventado.
    expect(find.text(l10n.movimientoTipoEntrada), findsOneWidget);

    // Orden real por fecha: el título de Pago (hoy) debe aparecer ANTES
    // que el de Compra (hace 2 días) en el árbol de widgets.
    final posicionPago = tester.getTopLeft(find.text(l10n.dashboardActividadItemPago)).dy;
    final posicionCompra = tester.getTopLeft(find.text(l10n.dashboardActividadItemCompra)).dy;
    expect(posicionPago, lessThan(posicionCompra), reason: 'Pago (hoy) debe listarse antes que Compra (hace 2 días)');
  });

  testWidgets('Sin ninguna actividad real, muestra el mensaje de vacío — nunca una tarjeta por tipo', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _pumpApp(tester, db);

    expect(tester.takeException(), isNull);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    expect(find.text(l10n.dashboardActividadVacia), findsOneWidget);
  });

  testWidgets('Ninguna tendencia/comparación ficticia contra periodo anterior — no existe fuente real hoy', (tester) async {
    final db = await _sembrarActividadDePrueba();
    addTearDown(db.close);
    await _pumpApp(tester, db);

    expect(tester.takeException(), isNull);

    // Nunca debe aparecer un símbolo de variación porcentual en el
    // Dashboard — no existe ninguna fuente real de comparación contra
    // el periodo anterior en este esquema todavía.
    final textosConPorcentaje = find
        .byWidgetPredicate((widget) => widget is Text && (widget.data?.contains('%') ?? false))
        .evaluate();
    expect(textosConPorcentaje, isEmpty, reason: 'no debe mostrarse ninguna tendencia inventada (ej. "↑ 8.4% vs. periodo anterior")');
  });

  testWidgets('Ventana angosta (700px) con datos reales cargados, sin overflow', (tester) async {
    final db = await _sembrarActividadDePrueba();
    addTearDown(db.close);
    await _pumpApp(tester, db, tamano: const Size(700, 900));

    expect(tester.takeException(), isNull);
  });

  testWidgets('Ventana muy amplia (1920px) con datos reales cargados, sin overflow', (tester) async {
    final db = await _sembrarActividadDePrueba();
    addTearDown(db.close);
    await _pumpApp(tester, db, tamano: const Size(1920, 1080));

    expect(tester.takeException(), isNull);
  });
}
