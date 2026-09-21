// Etapa 5 (Descuentos programados — CRUD corregible, trazabilidad y
// consistencia con Nómina), Sección 12: responsive SOLO de lo
// realmente modificado — `DescuentoProgramadoDetalleScreen` (nueva
// tarjeta "Reservado" + botón "Corregir") y el nuevo diálogo
// "Corregir descuento" — en los 5 anchos pedidos × claro/oscuro. Sin
// herramienta de captura de pantalla: la evidencia es "cero overflow /
// cero excepción", nunca una comparación de píxeles.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/descuentos_personal/data/repositories/descuento_programado_repository_impl.dart';
import 'package:riseg_one/features/descuentos_personal/domain/usecases/registrar_descuento_programado_usecase.dart';
import 'package:riseg_one/features/descuentos_personal/presentation/descuento_programado_detalle_screen.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart' show attachmentStorageProvider;
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

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

Future<void> _pump(
  WidgetTester tester,
  AppDatabase db,
  Directory tempDir, {
  required Widget child,
  required Size tamano,
  required ThemeData tema,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: '/pantalla',
    routes: [
      GoRoute(path: '/pantalla', builder: (context, state) => Scaffold(body: child)),
      GoRoute(path: '/personal/empleados/:id', builder: (context, state) => const Scaffold(body: SizedBox.shrink())),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionMaestroDePrueba.new),
        attachmentStorageProvider.overrideWithValue(AttachmentStorage(tempDir.path)),
      ],
      child: MaterialApp.router(
        theme: tema,
        // Solo `theme` + `ThemeMode.light` (mismo criterio que el
        // resto de RISEG ONE): así el `ThemeData` renderizado es
        // exactamente `tema`, sin importar si semánticamente es claro
        // u oscuro.
        themeMode: ThemeMode.light,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _anchos = [
  Size(1536, 864),
  Size(1366, 768),
  Size(1024, 768),
  Size(700, 900),
  Size(500, 900),
];

void main() {
  late AppDatabase db;
  late Directory tempDir;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    tempDir = Directory.systemTemp.createTempSync('riseg_corregir_descuento_responsive_test_');
  });

  tearDown(() {
    db.close();
    tempDir.deleteSync(recursive: true);
  });

  Future<String> crearDescuentoDePrueba() async {
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
            fechaIngreso: DateTime(2025, 1, 1),
            aniosExperienciaSeguridad: 3,
            sueldoMensualAdministrativo: const Value(1500000),
          ),
        );
    final repo = DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db));
    final useCase = RegistrarDescuentoProgramadoUseCase(
      repo,
      EmpleadoRepositoryImpl(db, AsignacionServicioRepositoryImpl(db)),
      GenerarCodigoUseCase(CodigoSecuenciaService(db)),
    );
    final resultado = await useCase.ejecutar(
      empleadoId: empleado.id,
      tipo: 'prestamo',
      fechaRegistro: DateTime(2026, 1, 1),
      importeOriginal: 300000,
      numeroCuotas: 3,
      fechaPrimeraCuota: DateTime(2026, 1, 20),
    );
    return (resultado as RegistrarDescuentoProgramadoExitoso).descuento.id;
  }

  final temas = {'claro': AppTheme.light(), 'oscuro': AppTheme.dark()};
  for (final entradaTema in temas.entries) {
    final etiquetaTema = entradaTema.key;
    final tema = entradaTema.value;

    for (final tamano in _anchos) {
      final etiqueta = '${tamano.width.toInt()}×${tamano.height.toInt()}, $etiquetaTema';

      testWidgets('Expediente de Descuento ($etiqueta): tarjeta Reservado + botón Corregir, cero overflow', (tester) async {
        final descuentoId = await crearDescuentoDePrueba();

        await _pump(
          tester,
          db,
          tempDir,
          child: DescuentoProgramadoDetalleScreen(descuentoProgramadoId: descuentoId),
          tamano: tamano,
          tema: tema,
        );

        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('descuento_programado_boton_corregir')), findsOneWidget);
      });

      testWidgets('Diálogo "Corregir descuento" ($etiqueta): abre sin overflow, con motivo y nuevo importe visibles', (tester) async {
        final descuentoId = await crearDescuentoDePrueba();

        await _pump(
          tester,
          db,
          tempDir,
          child: DescuentoProgramadoDetalleScreen(descuentoProgramadoId: descuentoId),
          tamano: tamano,
          tema: tema,
        );

        await tester.tap(find.byKey(const Key('descuento_programado_boton_corregir')));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold).first))!;
        expect(find.text(l10n.corregirDescuentoDialogoTitulo), findsOneWidget);
        expect(find.text(l10n.corregirDescuentoCampoMotivo), findsOneWidget);
        expect(find.text(l10n.corregirDescuentoCampoImporte), findsOneWidget);
      });
    }
  }
}
