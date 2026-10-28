// Etapa 18 — pasada UX/UI de Inventario, pantalla Reportes: cubre el
// resumen KPI superior (incluida la ocultación honesta de "Valor del
// inventario" cuando falta cobertura de costo), los filtros del
// Historial de movimientos, la búsqueda de Existencias actuales y el
// empty state compacto de Descuentos pendientes — todo sobre la
// pantalla real, no solo el cálculo de `ReportesState`/`ReportesController`
// (que ya cubre `reportes_test.dart` a nivel repositorio).

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
import 'package:riseg_one/core/design_system/design_system.dart' show RisegCard;
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
import 'package:riseg_one/features/inventario/presentation/articulos/articulos_list_screen.dart' show formatoCosto;
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

Future<String> _crearEmpleado(AppDatabase db, {int numeroEmpleado = 1, String nombres = 'Juan'}) async {
  final empleado = await db.into(db.empleado).insertReturning(
        EmpleadoCompanion.insert(
          numeroEmpleado: numeroEmpleado,
          nombres: nombres,
          apellidoPaterno: 'Pérez',
          sexo: 'masculino',
          fechaNacimiento: DateTime(1990, 1, 1),
          curp: 'PEXJ900101HDFXXX0$numeroEmpleado',
          rfc: 'PEXJ900101AB$numeroEmpleado',
          nss: '1234567890$numeroEmpleado',
          estadoCivil: 'soltero',
          fechaIngreso: DateTime(2026, 1, 1),
          aniosExperienciaSeguridad: 3,
        ),
      );
  return empleado.id;
}

/// Un artículo con costo completo, una asignación activa y una cerrada
/// por daño con descuento generado — cubre KPIs, Asignaciones vigentes,
/// Descuentos pendientes e Historial con más de un tipo de movimiento.
Future<void> _sembrarConDanoYDescuento(AppDatabase db) async {
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

  final empleado = await _crearEmpleado(db);
  final crearAsignacion = CrearAsignacionUseCase(asignacionRepo, articuloRepo, inventarioRepo);

  await crearAsignacion.ejecutar(
    articuloId: articulo.id,
    cantidad: 3,
    empleadoId: empleado,
    fechaEntrega: DateTime(2026, 8, 5),
  );

  final aDanar = ((await crearAsignacion.ejecutar(
    articuloId: articulo.id,
    cantidad: 1,
    empleadoId: empleado,
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
    empleadoResponsableDescuentoId: empleado,
  );
}

/// Dos artículos SIN ninguna asignación/descuento — uno con costo
/// conocido y otro sin él, para probar que "Valor del inventario" se
/// oculta cuando falta cobertura, y para tener 2 filas distinguibles
/// en Existencias (búsqueda) y un Descuentos pendientes vacío de
/// verdad.
Future<void> _sembrarCostoParcialSinDescuentos(AppDatabase db) async {
  final articuloRepo = ArticuloRepositoryImpl(db);
  final categoriaRepo = CategoriaArticuloRepositoryImpl(db);
  final inventarioRepo = InventarioRepositoryImpl(db);
  final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
  final crearArticulo = CrearArticuloUseCase(articuloRepo, categoriaRepo, generarCodigo);

  final uniformes =
      (await CrearCategoriaArticuloUseCase(categoriaRepo).ejecutar(nombre: 'Uniformes') as CrearCategoriaArticuloExitoso)
          .categoria;
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
    costoUnitario: 20000,
    fecha: DateTime(2026, 8, 1),
  );

  final papeleria =
      (await CrearCategoriaArticuloUseCase(categoriaRepo).ejecutar(nombre: 'Papelería') as CrearCategoriaArticuloExitoso)
          .categoria;
  final guantes = (await crearArticulo.ejecutar(
    categoriaId: papeleria.id,
    nombre: 'GUANTES',
    manejaVariante: false,
    manejaSerie: false,
  ) as CrearArticuloExitoso)
      .articulo;
  await RegistrarEntradaUseCase(inventarioRepo, articuloRepo).ejecutar(
    articuloId: guantes.id,
    cantidad: 5,
    fecha: DateTime(2026, 8, 1),
  );
}

Future<void> _pumpEnReportes(WidgetTester tester, AppDatabase db) async {
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

  final l10n = await AppLocalizations.delegate.load(const Locale('es'));
  await tester.tap(find.text(l10n.inventarioTabReportes));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('el resumen KPI muestra Disponible/Asignado/Dañado-Perdido/Asignaciones vigentes y Valor del inventario', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    // Etapa 3B: autorizar revalida contra la base, así que el
    // escenario de la sesión tiene que estar persistido.
    await sembrarSesionEnBase(db, const SesionUsuario( usuarioId: 'usuario-prueba', nombre: 'Usuario de prueba', nombreUsuario: 'prueba', esMaestro: true, permisos: {}, ));
    addTearDown(db.close);
    await _sembrarConDanoYDescuento(db);

    await _pumpEnReportes(tester, db);
    expect(tester.takeException(), isNull);

    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    // 10 entrada − 3 asignadas activas − 1 dañada = 6 disponibles;
    // asignado = 3 (solo la vigente); dañado/perdido = 1. Las
    // etiquetas "Disponible"/"Asignado"/"Dañado/Perdido" también son
    // encabezados de columna en Existencias, así que se espera más de
    // una aparición — solo "Asignaciones vigentes" es exclusiva del KPI.
    expect(find.text(l10n.reportesResumenDisponible), findsWidgets);
    expect(find.text('6'), findsWidgets);
    expect(find.text(l10n.reportesResumenAsignado), findsWidgets);
    expect(find.text(l10n.reportesResumenDanadoPerdido), findsWidgets);
    expect(find.text(l10n.reportesResumenAsignacionesVigentes), findsOneWidget);
    expect(find.text('1'), findsWidgets);

    // Costo conocido en el 100% de la existencia real (10 × $200.00) →
    // el KPI de valor debe mostrarse, no ocultarse.
    expect(find.text(l10n.reportesResumenValorInventario), findsOneWidget);
    expect(find.text(formatoCosto(200000)), findsWidgets);
  });

  testWidgets('el Historial de movimientos filtra por tipo y muestra la nota de "Últimos 100"', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    // Etapa 3B: autorizar revalida contra la base, así que el
    // escenario de la sesión tiene que estar persistido.
    await sembrarSesionEnBase(db, const SesionUsuario( usuarioId: 'usuario-prueba', nombre: 'Usuario de prueba', nombreUsuario: 'prueba', esMaestro: true, permisos: {}, ));
    addTearDown(db.close);
    await _sembrarConDanoYDescuento(db);

    await _pumpEnReportes(tester, db);

    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    // Acotado a la tarjeta de Historial: `l10n.movimientoTipoSalidaDano`
    // ("Dañado") coincide textualmente con `l10n.motivoCierreDano`, que
    // también aparece en la columna Motivo de Descuentos pendientes —
    // una coincidencia real de idioma, no una fuga de datos.
    final tarjetaHistorial = find
        .ancestor(of: find.text(l10n.reportesSeccionMovimientos), matching: find.byType(RisegCard))
        .first;

    expect(find.text(l10n.reportesMovimientosNota), findsOneWidget);
    expect(find.descendant(of: tarjetaHistorial, matching: find.text(l10n.movimientoTipoEntrada)), findsWidgets);
    expect(find.descendant(of: tarjetaHistorial, matching: find.text(l10n.movimientoTipoSalidaDano)), findsWidgets);

    // El filtro de Tipo de movimiento es el primer `RisegSelect<String?>`
    // de la pantalla (antes que el de Artículo, mismo tipo genérico).
    await tester.ensureVisible(find.byType(DropdownButtonFormField<String?>).first);
    await tester.tap(find.byType(DropdownButtonFormField<String?>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.movimientoTipoEntrada).last);
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: tarjetaHistorial, matching: find.text(l10n.movimientoTipoSalidaDano)),
      findsNothing,
      reason: 'solo debe quedar el movimiento de tipo Entrada',
    );
    expect(find.descendant(of: tarjetaHistorial, matching: find.text(l10n.movimientoTipoEntrada)), findsWidgets);
  });

  testWidgets('"Valor del inventario" se oculta cuando algún artículo con existencia carece de costo', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    // Etapa 3B: autorizar revalida contra la base, así que el
    // escenario de la sesión tiene que estar persistido.
    await sembrarSesionEnBase(db, const SesionUsuario( usuarioId: 'usuario-prueba', nombre: 'Usuario de prueba', nombreUsuario: 'prueba', esMaestro: true, permisos: {}, ));
    addTearDown(db.close);
    await _sembrarCostoParcialSinDescuentos(db);

    await _pumpEnReportes(tester, db);
    expect(tester.takeException(), isNull);

    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    expect(
      find.text(l10n.reportesResumenValorInventario),
      findsNothing,
      reason: 'GUANTES no tiene costoUnitario capturado — mostrar un total sería engañoso',
    );
  });

  testWidgets('Descuentos pendientes usa el empty state compacto cuando no hay ninguno', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    // Etapa 3B: autorizar revalida contra la base, así que el
    // escenario de la sesión tiene que estar persistido.
    await sembrarSesionEnBase(db, const SesionUsuario( usuarioId: 'usuario-prueba', nombre: 'Usuario de prueba', nombreUsuario: 'prueba', esMaestro: true, permisos: {}, ));
    addTearDown(db.close);
    await _sembrarCostoParcialSinDescuentos(db);

    await _pumpEnReportes(tester, db);

    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    expect(find.text(l10n.reportesDescuentosPendientesVacioTitulo), findsOneWidget);
    expect(find.text(l10n.reportesDescuentosPendientesVacioMensaje), findsOneWidget);
  });

  testWidgets('Existencias actuales se filtra por nombre o folio sin tocar el resto de las secciones', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    // Etapa 3B: autorizar revalida contra la base, así que el
    // escenario de la sesión tiene que estar persistido.
    await sembrarSesionEnBase(db, const SesionUsuario( usuarioId: 'usuario-prueba', nombre: 'Usuario de prueba', nombreUsuario: 'prueba', esMaestro: true, permisos: {}, ));
    addTearDown(db.close);
    await _sembrarCostoParcialSinDescuentos(db);

    await _pumpEnReportes(tester, db);

    final l10n = await AppLocalizations.delegate.load(const Locale('es'));
    // Acotado a la tarjeta de Existencias: ambos nombres también
    // aparecen en Historial de movimientos (columna Artículo, por la
    // entrada de cada uno) — la búsqueda de Existencias no debe tocar
    // esa otra sección.
    final tarjetaExistencias = find
        .ancestor(of: find.text(l10n.reportesSeccionExistencias), matching: find.byType(RisegCard))
        .first;
    expect(find.descendant(of: tarjetaExistencias, matching: find.text('CAMISOLA')), findsOneWidget);
    expect(find.descendant(of: tarjetaExistencias, matching: find.text('GUANTES')), findsOneWidget);

    // Ubicado por su hint, no por posición: la barra de búsqueda
    // global de arriba de la pantalla también es un `TextField`.
    final campoExistencias = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == l10n.reportesExistenciasBuscar,
    );
    await tester.ensureVisible(campoExistencias);
    await tester.enterText(campoExistencias, 'CAM');
    await tester.pumpAndSettle();

    expect(find.descendant(of: tarjetaExistencias, matching: find.text('CAMISOLA')), findsOneWidget);
    expect(find.descendant(of: tarjetaExistencias, matching: find.text('GUANTES')), findsNothing);
  });
}
