// Pruebas de la pantalla de expediente de Puesto — cancelar con/sin
// cambios (mismo patrón visual que Empresa/Sucursales) y el ciclo de
// vida (archivar/reactivar), incluyendo el bloqueo de reactivación
// cuando el Área quedó inactiva (corrección #2/#7 del plan aprobado).

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
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_puesto_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/puesto_validator.dart';
import 'package:riseg_one/features/organizacion/presentation/puestos/puesto_expediente_screen.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import '../../../support/sesion_en_base.dart';

/// Sesión Maestro fija — Etapa 11C activó autorización real en las
/// acciones de esta pantalla; sin este override todas serían
/// rechazadas por `AuthorizationService` (mismo criterio que
/// `smoke_test.dart`).
class _SesionControllerDePrueba extends SesionController {
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

const _borradorValido = PuestoBorrador(
  nombre: 'Guardia Norte',
  areaId: SeedIds.areaOperaciones,
  tipo: TipoPuesto.operativo,
  nivelJerarquico: 1,
);

Future<void> _pumpScreen(WidgetTester tester, AppDatabase db, String puestoId) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionControllerDePrueba.new),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PuestoExpedienteScreen(puestoId: puestoId),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late AppDatabase db;
  late AreaRepositoryImpl areaRepo;
  late String puestoId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    areaRepo = AreaRepositoryImpl(db);
    final crear = CrearPuestoUseCase(
      PuestoRepositoryImpl(db),
      GenerarCodigoUseCase(CodigoSecuenciaService(db)),
      PuestoValidator(areaRepo),
    );
    final creado = (await crear.ejecutar(_borradorValido)) as GuardarPuestoExitoso;
    puestoId = creado.puesto.id;
    // Etapa 3B: autorizar revalida contra la base, así que la
    // sesión de esta prueba tiene que corresponder a una cuenta real.
    await sembrarSesionEnBase(db, const SesionUsuario( usuarioId: 'usuario-prueba', nombre: 'Usuario de prueba', nombreUsuario: 'prueba', esMaestro: true, permisos: {}, ));
  });

  tearDown(() => db.close());

  testWidgets('cancelar sin cambios regresa a consulta sin pedir confirmación', (tester) async {
    await _pumpScreen(tester, db, puestoId);

    await tester.tap(find.byKey(const Key('puesto_expediente_boton_editar')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('puesto_expediente_boton_guardar')), findsOneWidget);

    await tester.tap(find.byKey(const Key('puesto_expediente_boton_cancelar')));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
    expect(find.byKey(const Key('puesto_expediente_boton_editar')), findsOneWidget);
  });

  testWidgets('cancelar con cambios pide confirmación antes de descartar', (tester) async {
    await _pumpScreen(tester, db, puestoId);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await tester.tap(find.byKey(const Key('puesto_expediente_boton_editar')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'Nombre modificado');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('puesto_expediente_boton_cancelar')));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    await tester.tap(find.text(l10n.empresaCancelarConfirmacionConfirmar));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
    expect(find.byKey(const Key('puesto_expediente_boton_editar')), findsOneWidget);
  });

  testWidgets('archivar y reactivar el Puesto vía confirmación', (tester) async {
    await _pumpScreen(tester, db, puestoId);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    expect(find.text(l10n.puestoEstadoActivo), findsOneWidget);

    await tester.tap(find.byKey(const Key('puesto_boton_ciclo_vida')));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    await tester.tap(find.text(l10n.sucursalConfirmarAceptar));
    await tester.pumpAndSettle();

    expect(find.text(l10n.puestoEstadoArchivado), findsOneWidget);

    await tester.tap(find.byKey(const Key('puesto_boton_ciclo_vida')));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    await tester.tap(find.text(l10n.sucursalConfirmarAceptar));
    await tester.pumpAndSettle();

    expect(find.text(l10n.puestoEstadoActivo), findsOneWidget);
  });

  testWidgets('reactivar se bloquea si el Área quedó inactiva mientras el Puesto estaba archivado', (tester) async {
    await _pumpScreen(tester, db, puestoId);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    // Archiva el Puesto primero.
    await tester.tap(find.byKey(const Key('puesto_boton_ciclo_vida')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.sucursalConfirmarAceptar));
    await tester.pumpAndSettle();
    expect(find.text(l10n.puestoEstadoArchivado), findsOneWidget);

    // El Área se desactiva mientras el Puesto sigue archivado — nunca
    // bloqueó desactivar el Área porque este Puesto ya no cuenta como
    // activo (corrección #7).
    await areaRepo.desactivar(SeedIds.areaOperaciones);

    // Intentar reactivar debe bloquearse: el Puesto permanece archivado.
    await tester.tap(find.byKey(const Key('puesto_boton_ciclo_vida')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.sucursalConfirmarAceptar));
    await tester.pumpAndSettle();

    expect(find.text(l10n.puestoEstadoArchivado), findsOneWidget);
    expect(find.text(l10n.puestoReactivarBloqueadoError), findsOneWidget);
  });
}
