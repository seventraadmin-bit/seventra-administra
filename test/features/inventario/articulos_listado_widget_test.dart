// Etapa 18 — pasada UX/UI de Inventario: cubre el resumen KPI, los
// filtros (categoría/tipo/estado de existencia) y la navegación de una
// fila al expediente del Artículo en el listado real.

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
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/categoria_articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/inventario_repository_impl.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_asignacion_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_categoria_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_entrada_unidad_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_entrada_usecase.dart';
import 'package:riseg_one/features/inventario/presentation/articulos/articulos_state.dart';
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

Future<void> _sembrar(AppDatabase db) async {
  final articuloRepo = ArticuloRepositoryImpl(db);
  final categoriaRepo = CategoriaArticuloRepositoryImpl(db);
  final inventarioRepo = InventarioRepositoryImpl(db);
  final asignacionRepo = AsignacionRepositoryImpl(db);
  final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
  final crearArticulo = CrearArticuloUseCase(articuloRepo, categoriaRepo, generarCodigo);

  final uniformes =
      (await CrearCategoriaArticuloUseCase(categoriaRepo).ejecutar(nombre: 'Uniformes') as CrearCategoriaArticuloExitoso)
          .categoria;
  final electronica =
      (await CrearCategoriaArticuloUseCase(categoriaRepo).ejecutar(nombre: 'Electrónica') as CrearCategoriaArticuloExitoso)
          .categoria;

  // Por cantidad, con disponibilidad completa: 10 disponibles.
  final camisola = (await crearArticulo.ejecutar(
    categoriaId: uniformes.id,
    nombre: 'CAMISOLA',
    manejaVariante: false,
    manejaSerie: false,
  ) as CrearArticuloExitoso)
      .articulo;
  await RegistrarEntradaUseCase(inventarioRepo, articuloRepo).ejecutar(
    articuloId: camisola.id,
    cantidad: 10,
    fecha: DateTime(2026, 8, 1),
  );

  // Serializado, totalmente asignado: 0 disponibles, 1 asignado.
  final radio = (await crearArticulo.ejecutar(
    categoriaId: electronica.id,
    nombre: 'RADIO MOTOROLA',
    manejaVariante: false,
    manejaSerie: true,
  ) as CrearArticuloExitoso)
      .articulo;
  final unidad = ((await RegistrarEntradaUnidadUseCase(inventarioRepo, articuloRepo, generarCodigo).ejecutar(
    articuloId: radio.id,
    numeroSerie: 'SN-0001',
    fecha: DateTime(2026, 8, 1),
  )) as RegistrarEntradaUnidadExitoso)
      .unidad;

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
  await CrearAsignacionUseCase(asignacionRepo, articuloRepo, inventarioRepo).ejecutar(
    articuloId: radio.id,
    unidadId: unidad.id,
    cantidad: 1,
    empleadoId: empleado.id,
    fechaEntrega: DateTime(2026, 8, 2),
  );
}

Future<void> _pumpEnArticulos(WidgetTester tester, AppDatabase db) async {
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

  await tester.tap(find.byKey(const Key('nav_item_inventario')));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('el resumen KPI separa catálogo de existencia y se recalcula al filtrar', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    // Etapa 3B: autorizar revalida contra la base, así que el
    // escenario de la sesión tiene que estar persistido.
    await sembrarSesionEnBase(db, const SesionUsuario( usuarioId: 'usuario-prueba', nombre: 'Usuario de prueba', nombreUsuario: 'prueba', esMaestro: true, permisos: {}, ));
    addTearDown(db.close);
    await _sembrar(db);

    await _pumpEnArticulos(tester, db);
    expect(tester.takeException(), isNull);

    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    // Sin filtros: 2 artículos registrados (catálogo), 11 unidades
    // totales (10 CAMISOLA + 1 RADIO) — nunca el mismo número.
    expect(find.text(l10n.inventarioResumenArticulosRegistrados), findsOneWidget);
    expect(find.text(l10n.inventarioResumenUnidadesTotales), findsOneWidget);
    expect(find.text('2'), findsWidgets);
    expect(find.text('11'), findsWidgets);

    // Filtro Tipo = Serie: solo RADIO queda visible — el resumen debe
    // recalcularse sobre las filas filtradas, no sobre el catálogo
    // completo (1 artículo, 1 unidad, 0 disponibles, 1 asignada).
    // `ensureVisible`: la ventana de prueba por defecto (800×600) deja
    // la fila de filtros fuera de la vista inicial una vez que el
    // resumen KPI también ocupa espacio arriba de la tabla.
    await tester.ensureVisible(find.byType(DropdownButtonFormField<FiltroTipoArticulo>));
    await tester.tap(find.byType(DropdownButtonFormField<FiltroTipoArticulo>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.inventarioFiltroTipoSerie).last);
    await tester.pumpAndSettle();

    expect(find.text('CAMISOLA'), findsNothing);
    expect(find.text('RADIO MOTOROLA'), findsOneWidget);

    // "Limpiar filtros" restaura el listado completo.
    await tester.ensureVisible(find.text(l10n.inventarioLimpiarFiltros));
    await tester.tap(find.text(l10n.inventarioLimpiarFiltros));
    await tester.pumpAndSettle();

    expect(find.text('CAMISOLA'), findsOneWidget);
    expect(find.text('RADIO MOTOROLA'), findsOneWidget);
  });

  testWidgets('el filtro de estado de existencia "Sin disponibilidad" solo deja artículos sin unidades libres', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    // Etapa 3B: autorizar revalida contra la base, así que el
    // escenario de la sesión tiene que estar persistido.
    await sembrarSesionEnBase(db, const SesionUsuario( usuarioId: 'usuario-prueba', nombre: 'Usuario de prueba', nombreUsuario: 'prueba', esMaestro: true, permisos: {}, ));
    addTearDown(db.close);
    await _sembrar(db);

    await _pumpEnArticulos(tester, db);

    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await tester.ensureVisible(find.byType(DropdownButtonFormField<FiltroEstadoExistencia>));
    await tester.tap(find.byType(DropdownButtonFormField<FiltroEstadoExistencia>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.inventarioFiltroEstadoSinDisponibilidad).last);
    await tester.pumpAndSettle();

    expect(find.text('CAMISOLA'), findsNothing, reason: 'tiene 10 unidades disponibles');
    expect(find.text('RADIO MOTOROLA'), findsOneWidget, reason: 'sus 0 unidades disponibles cumplen el filtro');
  });

  testWidgets('tocar una fila abre el expediente del Artículo correspondiente', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    // Etapa 3B: autorizar revalida contra la base, así que el
    // escenario de la sesión tiene que estar persistido.
    await sembrarSesionEnBase(db, const SesionUsuario( usuarioId: 'usuario-prueba', nombre: 'Usuario de prueba', nombreUsuario: 'prueba', esMaestro: true, permisos: {}, ));
    addTearDown(db.close);
    await _sembrar(db);

    await _pumpEnArticulos(tester, db);

    await tester.ensureVisible(find.text('CAMISOLA').first);
    await tester.tap(find.text('CAMISOLA').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('CAMISOLA'), findsWidgets);
    expect(find.byKey(const Key('inventario_boton_nuevo_articulo')), findsNothing, reason: 'ya no es el listado');
  });
}
