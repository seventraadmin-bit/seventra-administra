// Etapa 3 (Compras — corrección financiera completa Cuenta↔TDC),
// Sección 7/14: smoke de responsividad + tema para la pantalla de
// corrección rediseñada — el selector de Origen financiero
// (`RisegFormSection(grid: true)`, mismo componente que ya usa
// `RegistrarCompraScreen`) debe seguir sin overflow en los 5 anchos
// explícitos del pedido: 1536/1366/1024/700/500 × claro/oscuro.
// Mismo criterio de evidencia que el resto de RISEG ONE: "cero
// overflow / cero excepción", sin herramienta de captura de pantalla.

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
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_financiera_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/tables/cuenta_financiera_table.dart';
import 'package:riseg_one/features/finanzas/data/tables/deuda_table.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_deuda_usecase.dart';
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
  final cuentaFinancieraRepo = CuentaFinancieraRepositoryImpl(db);
  final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
  final registrarCompra = RegistrarCompraUseCase(compraRepo, articuloRepo, inventarioRepo, deudaRepo, generarCodigo);

  // Una tarjeta y una cuenta activas — para que ambos selectores
  // condicionales del origen financiero tengan al menos una opción
  // real que renderizar en cada ancho.
  await cuentaFinancieraRepo.crear(
    codigo: 'CTA-000001',
    nombre: 'BBVA',
    tipo: TipoCuentaFinanciera.banco.name,
    saldoInicial: 5000000,
    fechaSaldoInicial: DateTime(2026, 1, 1),
  );
  await RegistrarDeudaUseCase(deudaRepo, generarCodigo).ejecutar(
    nombre: 'Konfío',
    tipo: TipoDeuda.tarjetaCredito.name,
    saldoInicial: 0,
    tarjetaLimiteCredito: 4000000,
  );

  final categoria =
      (await CrearCategoriaArticuloUseCase(categoriaRepo).ejecutar(nombre: 'Uniformes') as CrearCategoriaArticuloExitoso).categoria;
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

const _anchos = [Size(1536, 864), Size(1366, 768), Size(1024, 768), Size(700, 900), Size(500, 900)];

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

      testWidgets('Compras — Corregir compra ($etiqueta): selector de Origen financiero sin overflow', (tester) async {
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
              sesionControllerProvider.overrideWith(_SesionMaestroDePrueba.new),
              themeModeControllerProvider.overrideWith(() => _TemaFijo(modo)),
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

        final l10n = await AppLocalizations.delegate.load(const Locale('es'));
        await tester.ensureVisible(find.text(l10n.compraExpedienteBotonCorregir));
        await tester.tap(find.text(l10n.compraExpedienteBotonCorregir));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text(l10n.compraCorregirSeccionOrigen), findsOneWidget);
      });
    }
  }
}
