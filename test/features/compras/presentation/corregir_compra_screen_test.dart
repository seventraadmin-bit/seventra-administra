// Etapa 15 — pruebas de widget del formulario real de "Corregir datos"
// de Compra (`CorregirCompraScreen`), navegado desde el expediente real
// (no la pantalla aislada): confirma que carga precargada con los
// valores reales, que marcar/deshacer "Quitar esta partida" funciona
// visualmente, que el motivo es obligatorio, y que guardar una
// corrección exitosa regresa al expediente con los datos actualizados
// — mismo arnés (`RisegOneApp` + `createAppRouter()` + sesión Maestro
// fija) que usa `smoke_test.dart`.

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:riseg_one/app/app.dart';
import 'package:riseg_one/app/router/app_router.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/compras/data/repositories/compra_repository_impl.dart';
import 'package:riseg_one/features/compras/data/tables/compra_partida_table.dart' show DestinoCompraPartida;
import 'package:riseg_one/features/compras/domain/repositories/compra_repository.dart';
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

/// El campo de texto (`TextFormField`) que vive dentro del `RisegTextField`
/// cuya propiedad `label` es exactamente [label] — mismo criterio ya
/// establecido en `empleado_servicio_dialogs_test.dart`: se busca por
/// la propiedad del widget, no por su `Text` visible, para no depender
/// de ambigüedades de `find.ancestor` cuando esa misma etiqueta
/// aparece más de una vez en el árbol.
Finder _campoTexto(String label) => find.descendant(
      of: find.byWidgetPredicate((w) => w is RisegTextField && w.label == label),
      matching: find.byType(TextFormField),
    );

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

Future<CompraData> _sembrarCompraDePrueba(AppDatabase db) async {
  await db.into(db.usuario).insert(
        UsuarioCompanion.insert(
          id: const drift.Value('usuario-maestro'),
          nombre: 'Maestro de prueba',
          nombreUsuario: 'maestro',
          passwordHash: 'x',
          esMaestro: const drift.Value(true),
        ),
      );

  final articuloRepo = ArticuloRepositoryImpl(db);
  final inventarioRepo = InventarioRepositoryImpl(db);
  final egresoRepo = EgresoRepositoryImpl(db);
  final deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
  final compraRepo = CompraRepositoryImpl(db, inventarioRepo, articuloRepo, egresoRepo, deudaRepo);
  final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));

  final categoria = (await CrearCategoriaArticuloUseCase(CategoriaArticuloRepositoryImpl(db)).ejecutar(nombre: 'Uniformes')
          as CrearCategoriaArticuloExitoso)
      .categoria;
  final articulo = (await CrearArticuloUseCase(articuloRepo, CategoriaArticuloRepositoryImpl(db), generarCodigo).ejecutar(
    categoriaId: categoria.id,
    nombre: 'Camisola CH',
    manejaVariante: false,
    manejaSerie: false,
  ) as CrearArticuloExitoso)
      .articulo;

  final registrar = RegistrarCompraUseCase(compraRepo, articuloRepo, inventarioRepo, deudaRepo, generarCodigo);
  final resultado = await registrar.ejecutar(
    fecha: DateTime(2026, 8, 10),
    proveedor: 'Uniformes del Centro',
    formaPago: FormaPago.efectivo.name,
    partidas: [
      PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: articulo.id, cantidad: 5, costoUnitario: 33000),
      PartidaCompraInput(destino: DestinoCompraPartida.gastoDirecto.name, concepto: 'Bolsa/empaque', cantidad: 1, costoUnitario: 5000),
    ],
  );
  return (resultado as RegistrarCompraExitosa).compra;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'Corregir datos de una Compra: precarga valores reales, permite marcar/deshacer "Quitar esta partida", '
    'exige motivo, y una corrección exitosa regresa al expediente actualizado',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final compra = await _sembrarCompraDePrueba(db);

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
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      await tester.tap(find.byKey(const Key('nav_item_compras')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(compra.folioCompra));
      await tester.pumpAndSettle();

      expect(find.text(l10n.compraExpedienteBotonCorregir), findsOneWidget);
      await tester.tap(find.text(l10n.compraExpedienteBotonCorregir));
      await tester.pumpAndSettle();

      // Precarga: título con folio real, proveedor y partidas reales.
      expect(find.text(l10n.compraCorregirScreenTitulo(compra.folioCompra)), findsOneWidget);
      expect(find.text('Uniformes del Centro'), findsOneWidget, reason: 'el proveedor real viene precargado');
      expect(
        find.text('Camisola CH'),
        findsWidgets,
        reason: 'el artículo real de la partida fungible viene precargado (aparece en el encabezado de la tarjeta y en el selector)',
      );
      expect(find.text('Bolsa/empaque'), findsOneWidget, reason: 'el concepto real de la partida de gasto directo viene precargado');

      // Marcar "Quitar esta partida" sobre la partida de gasto directo
      // y deshacerlo — confirma el toggle visual real, no solo el
      // estado interno.
      final botonesQuitar = find.text(l10n.compraCorregirBotonQuitarPartidaCompleta);
      expect(botonesQuitar, findsWidgets);
      await tester.ensureVisible(botonesQuitar.last);
      await tester.tap(botonesQuitar.last);
      await tester.pumpAndSettle();
      expect(find.text(l10n.compraCorregirBotonDeshacerQuitar), findsOneWidget);
      expect(find.text('Bolsa/empaque'), findsNothing, reason: 'la partida marcada para quitar deja de mostrar su formulario editable');

      await tester.ensureVisible(find.text(l10n.compraCorregirBotonDeshacerQuitar));
      await tester.tap(find.text(l10n.compraCorregirBotonDeshacerQuitar));
      await tester.pumpAndSettle();
      expect(find.text('Bolsa/empaque'), findsOneWidget, reason: 'deshacer restaura la partida a su estado editable normal');

      // Motivo vacío bloquea el guardado con un mensaje específico.
      await tester.ensureVisible(find.text(l10n.compraCorregirBotonGuardar));
      await tester.tap(find.text(l10n.compraCorregirBotonGuardar));
      await tester.pumpAndSettle();
      expect(find.text(l10n.compraCorregirErrorMotivoRequerido), findsOneWidget);

      // Corrección administrativa válida: cambia proveedor, captura
      // motivo, guarda.
      await tester.enterText(_campoTexto(l10n.compraCampoProveedor), 'Uniformes del Norte');
      await tester.enterText(_campoTexto(l10n.compraCorregirCampoMotivo), 'Proveedor mal capturado en el alta');
      await tester.ensureVisible(find.text(l10n.compraCorregirBotonGuardar));
      await tester.tap(find.text(l10n.compraCorregirBotonGuardar));
      await tester.pumpAndSettle();

      expect(find.text(l10n.compraCorregirExito), findsOneWidget);
      // De vuelta en el expediente, con el proveedor ya corregido
      // visible de inmediato, sin recargar manualmente.
      expect(find.text(l10n.compraExpedienteBotonCorregir), findsOneWidget);
      expect(find.text('Uniformes del Norte'), findsOneWidget);
    },
  );
}
