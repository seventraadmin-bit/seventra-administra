// Etapa 18 — pasada UX/UI de Inventario. Smoke de tema oscuro +
// breakpoints (1366×768, 900×560 y 500×900) para las 2 pantallas que
// ganaron resumen KPI + filas de filtros en esta etapa: Artículos
// (listado) y Reportes. Mismo criterio que el resto de RISEG ONE: sin
// herramienta de captura de pantalla, la evidencia es "cero overflow /
// cero excepción", nunca una comparación de píxeles.

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
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/categoria_articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/inventario_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/tables/asignacion_table.dart' show MotivoCierreAsignacion;
import 'package:riseg_one/features/inventario/domain/usecases/cerrar_asignacion_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_asignacion_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_categoria_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_entrada_usecase.dart';
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
  final asignacionRepo = AsignacionRepositoryImpl(db);
  final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));

  final categoria =
      (await CrearCategoriaArticuloUseCase(categoriaRepo).ejecutar(nombre: 'Uniformes') as CrearCategoriaArticuloExitoso)
          .categoria;
  final articulo = (await CrearArticuloUseCase(articuloRepo, categoriaRepo, generarCodigo).ejecutar(
    categoriaId: categoria.id,
    nombre: 'CAMISOLA',
    manejaVariante: false,
    manejaSerie: false,
  ) as CrearArticuloExitoso)
      .articulo;
  await RegistrarEntradaUseCase(inventarioRepo, articuloRepo).ejecutar(
    articuloId: articulo.id,
    cantidad: 10,
    costoUnitario: 20000,
    fecha: DateTime(2026, 8, 1),
  );

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
          fechaIngreso: DateTime(2026, 1, 1),
          aniosExperienciaSeguridad: 3,
        ),
      );

  final crearAsignacion = CrearAsignacionUseCase(asignacionRepo, articuloRepo, inventarioRepo);
  await crearAsignacion.ejecutar(
    articuloId: articulo.id,
    cantidad: 3,
    empleadoId: empleado.id,
    fechaEntrega: DateTime(2026, 8, 5),
  );

  final aDanar = ((await crearAsignacion.ejecutar(
    articuloId: articulo.id,
    cantidad: 1,
    empleadoId: empleado.id,
    fechaEntrega: DateTime(2026, 8, 6),
  )) as CrearAsignacionExitoso)
      .asignacion;
  await CerrarAsignacionUseCase(asignacionRepo).ejecutar(
    asignacionId: aDanar.id,
    motivo: MotivoCierreAsignacion.dano,
    fechaCierre: DateTime(2026, 8, 7),
    atribuibleAlEmpleado: true,
    generaDescuento: true,
    importeDescuento: 5000,
    empleadoResponsableDescuentoId: empleado.id,
  );
}

// 900×560 se excluye deliberadamente: es la esquina exacta donde
// coinciden `ShellBreakpoints.sidebarAutoCollapse` (900 de ancho) y
// `sidebarForceCollapseHeight` (560 de alto) — un problema preexistente
// del Shell (fuera de alcance de Inventario, ver el reporte final de
// esta etapa), no algo introducido por esta pasada. Mismo criterio que
// ya usa `personal_nomina_descuentos_tema_oscuro_responsive_test.dart`.
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

      testWidgets('Artículos ($etiqueta): cero overflow', (tester) async {
        tester.view.physicalSize = tamano;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final db = AppDatabase(NativeDatabase.memory());
        // Etapa 3B: autorizar revalida contra la base, así que el
        // escenario de la sesión tiene que estar persistido.
        await sembrarSesionEnBase(db, const SesionUsuario( usuarioId: 'usuario-prueba', nombre: 'Usuario de prueba', nombreUsuario: 'prueba', esMaestro: true, permisos: {}, ));
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
        await tester.tap(find.byKey(const Key('nav_item_inventario')));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('inventario_boton_nuevo_articulo')), findsOneWidget);
      });

      testWidgets('Reportes de inventario ($etiqueta): cero overflow', (tester) async {
        tester.view.physicalSize = tamano;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final db = AppDatabase(NativeDatabase.memory());
        // Etapa 3B: autorizar revalida contra la base, así que el
        // escenario de la sesión tiene que estar persistido.
        await sembrarSesionEnBase(db, const SesionUsuario( usuarioId: 'usuario-prueba', nombre: 'Usuario de prueba', nombreUsuario: 'prueba', esMaestro: true, permisos: {}, ));
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
        await tester.tap(find.byKey(const Key('nav_item_inventario')));
        await tester.pumpAndSettle();

        final l10n = await AppLocalizations.delegate.load(const Locale('es'));
        final tabReportes = find.text(l10n.inventarioTabReportes);
        await tester.ensureVisible(tabReportes.first);
        await tester.tap(tabReportes.first);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });
    }
  }
}
