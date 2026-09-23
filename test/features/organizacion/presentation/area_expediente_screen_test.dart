// Etapa 16, tercera pasada visual — expediente de Área: nombre/código/
// estado + Puestos realmente asociados, "Editar área" (mismo diálogo
// que el listado, reutilizado) y el menú "⋯" (Activar/Desactivar/
// Eliminar) — las acciones que antes vivían como iconos permanentes en
// cada fila del listado.

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/organizacion/data/repositories/area_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/puesto_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/puesto_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_puesto_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/puesto_validator.dart';
import 'package:riseg_one/features/organizacion/presentation/areas/area_expediente_screen.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import '../../../support/sesion_en_base.dart';

/// La sesión del escenario, en un solo sitio: la usa el doble y la
/// usa la siembra, así no pueden divergir.
SesionUsuario _sesionDePrueba({required bool esMaestro}) => SesionUsuario(
      usuarioId: 'usuario-prueba',
      nombre: 'Usuario de prueba',
      nombreUsuario: 'prueba',
      esMaestro: esMaestro,
      permisos: const {},
    );

class _SesionControllerDePrueba extends SesionController {
  _SesionControllerDePrueba({this.esMaestro = true});
  final bool esMaestro;

  @override
  SesionUsuario? build() => _sesionDePrueba(esMaestro: esMaestro);
}

Future<void> _pumpScreen(
  WidgetTester tester,
  AppDatabase db, {
  Size tamano = const Size(1200, 900),
  ThemeData? tema,
  bool esMaestro = true,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  // Etapa 3B: la autorización se revalida contra la base. El escenario
  // se siembra AQUÍ, no en el `setUp`, porque este archivo usa la misma
  // cuenta como Maestra y como no-Maestra: sembrar una sola volvería
  // positiva la prueba que comprueba justo lo contrario.
  await sembrarSesionEnBase(db, _sesionDePrueba(esMaestro: esMaestro));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(() => _SesionControllerDePrueba(esMaestro: esMaestro)),
      ],
      child: MaterialApp(
        theme: tema ?? AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const AreaExpedienteScreen(areaId: SeedIds.areaOperaciones),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  Future<void> crearPuestoDePrueba({String nombre = 'Guardia', int nivel = 1}) async {
    final crear = CrearPuestoUseCase(
      PuestoRepositoryImpl(db),
      GenerarCodigoUseCase(CodigoSecuenciaService(db)),
      PuestoValidator(AreaRepositoryImpl(db)),
    );
    await crear.ejecutar(PuestoBorrador(
      nombre: nombre,
      areaId: SeedIds.areaOperaciones,
      tipo: TipoPuesto.operativo,
      nivelJerarquico: nivel,
    ));
  }

  testWidgets('muestra nombre, código y estado del Área', (tester) async {
    await _pumpScreen(tester, db);

    final l10n = await AppLocalizations.delegate.load(const Locale('es'));
    expect(find.text('Operaciones'), findsOneWidget);
    expect(find.text(l10n.areaEstadoActivo), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sin Puestos asociados: "0 puestos" y mensaje explícito, nunca una lista vacía muda', (tester) async {
    await _pumpScreen(tester, db);

    final l10n = await AppLocalizations.delegate.load(const Locale('es'));
    expect(find.text(l10n.areaCantidadPuestos(0)), findsOneWidget);
    expect(find.text(l10n.areaSinPuestosAsociados), findsOneWidget);
  });

  testWidgets('con Puestos reales asociados: cuenta correcta y cada uno con su nivel', (tester) async {
    await crearPuestoDePrueba(nombre: 'Elemento Operativo', nivel: 1);
    await crearPuestoDePrueba(nombre: 'Jefe de Turno', nivel: 2);

    await _pumpScreen(tester, db);

    final l10n = await AppLocalizations.delegate.load(const Locale('es'));
    expect(find.text(l10n.areaCantidadPuestos(2)), findsOneWidget);
    expect(find.text('Elemento Operativo'), findsOneWidget);
    expect(find.text('N1'), findsOneWidget);
    expect(find.text('Jefe de Turno'), findsOneWidget);
    expect(find.text('N2'), findsOneWidget);
  });

  testWidgets('"Editar" abre el mismo diálogo de alta/edición y refleja el cambio', (tester) async {
    await _pumpScreen(tester, db);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await tester.tap(find.byKey(const Key('area_expediente_boton_editar')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.areaDialogoTituloEdicion), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, 'Operaciones Renombrada');
    await tester.tap(find.text(l10n.areaDialogoBotonGuardar));
    await tester.pumpAndSettle();

    expect(find.text('Operaciones Renombrada'), findsOneWidget);
  });

  testWidgets('el menú "⋯" ofrece Desactivar (Área activa) y Eliminar solo para el Maestro', (tester) async {
    await _pumpScreen(tester, db);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await tester.tap(find.byKey(const Key('area_expediente_menu')));
    await tester.pumpAndSettle();

    expect(find.text(l10n.areaBotonDesactivar), findsOneWidget);
    expect(find.text(l10n.eliminacionFisicaAccionMenu), findsOneWidget);
  });

  testWidgets('sin ser Maestro, el menú "⋯" no ofrece Eliminar', (tester) async {
    await _pumpScreen(tester, db, esMaestro: false);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await tester.tap(find.byKey(const Key('area_expediente_menu')));
    await tester.pumpAndSettle();

    expect(find.text(l10n.areaBotonDesactivar), findsOneWidget);
    expect(find.text(l10n.eliminacionFisicaAccionMenu), findsNothing);
  });

  testWidgets('desactivar con Puestos activos se bloquea con un error explícito', (tester) async {
    await crearPuestoDePrueba();
    await _pumpScreen(tester, db);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await tester.tap(find.byKey(const Key('area_expediente_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.areaBotonDesactivar));
    await tester.pumpAndSettle();
    expect(find.text(l10n.areaConfirmarDesactivarTitulo), findsOneWidget);

    await tester.tap(find.text(l10n.sucursalConfirmarAceptar));
    await tester.pumpAndSettle();

    expect(find.text(l10n.areaDesactivarBloqueadaError(1)), findsOneWidget);
    expect(find.text(l10n.areaEstadoActivo), findsOneWidget, reason: 'el bloqueo no debe haber modificado el registro');
  });

  testWidgets('desactivar sin Puestos activos funciona tras confirmar', (tester) async {
    await _pumpScreen(tester, db);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await tester.tap(find.byKey(const Key('area_expediente_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.areaBotonDesactivar));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.sucursalConfirmarAceptar));
    await tester.pumpAndSettle();

    expect(find.text(l10n.areaEstadoInactivo), findsOneWidget);
  });

  group('responsive y tema', () {
    for (final tamano in const [Size(1366, 900), Size(1024, 900), Size(700, 900), Size(500, 900)]) {
      testWidgets('${tamano.width.toInt()}×${tamano.height.toInt()}: cero overflow', (tester) async {
        await crearPuestoDePrueba();
        await _pumpScreen(tester, db, tamano: tamano);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('modo oscuro: cero overflow', (tester) async {
      await _pumpScreen(tester, db, tema: AppTheme.dark());
      expect(tester.takeException(), isNull);
    });
  });
}
