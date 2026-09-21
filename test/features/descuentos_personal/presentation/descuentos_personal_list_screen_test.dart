// Etapa 16, evolución visual final de Personal — cubre la identidad
// del Empleado (RisegEntityIdentity), la representación compacta de
// progreso (pagado/original + barra) y su caso especial: un saldo
// `cancelado` (condonado) NUNCA debe mostrarse como si siguiera
// cobrándose o como si se hubiera pagado por completo. También cubre
// responsive/tema oscuro sin overflow.

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/descuentos_personal/data/repositories/descuento_programado_repository_impl.dart';
import 'package:riseg_one/features/descuentos_personal/domain/usecases/cancelar_saldo_descuento_programado_usecase.dart';
import 'package:riseg_one/features/descuentos_personal/domain/usecases/registrar_descuento_programado_usecase.dart';
import 'package:riseg_one/features/descuentos_personal/presentation/descuentos_personal_list_screen.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

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

const _anchos = [
  Size(1536, 864),
  Size(1366, 768),
  Size(1024, 768),
  Size(700, 900),
  Size(500, 900),
];

void main() {
  late AppDatabase db;
  late EmpleadoRepositoryImpl empleadoRepo;
  late DescuentoProgramadoRepositoryImpl descuentoRepo;
  late RegistrarDescuentoProgramadoUseCase registrar;
  late CancelarSaldoDescuentoProgramadoUseCase cancelarSaldo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    final asignacionServicioRepo = AsignacionServicioRepositoryImpl(db);
    empleadoRepo = EmpleadoRepositoryImpl(db, asignacionServicioRepo);
    descuentoRepo = DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db));
    registrar = RegistrarDescuentoProgramadoUseCase(descuentoRepo, empleadoRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));
    cancelarSaldo = CancelarSaldoDescuentoProgramadoUseCase(descuentoRepo);
  });

  tearDown(() => db.close());

  Future<EmpleadoData> crearEmpleadoDePrueba(int numero) {
    final n = numero.toString().padLeft(2, '0');
    return db.into(db.empleado).insertReturning(
          EmpleadoCompanion.insert(
            numeroEmpleado: numero,
            nombres: 'Empleado$n',
            apellidoPaterno: 'Apellido$n',
            sexo: 'masculino',
            fechaNacimiento: DateTime(1990, 1, 1),
            curp: 'PEXJ900101HDFXXX$n',
            rfc: 'PEXJ900101$n',
            nss: '100000000$n',
            estadoCivil: 'soltero',
            fechaIngreso: DateTime(2025, 1, 1),
            aniosExperienciaSeguridad: 3,
          ),
        );
  }

  Future<void> pumpScreen(WidgetTester tester, {required Size tamano, ThemeData? tema}) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: '/personal/descuentos',
      routes: [
        GoRoute(path: '/personal/descuentos', builder: (context, state) => const Scaffold(body: DescuentosPersonalListScreen())),
        GoRoute(path: '/personal/descuentos/:id', builder: (context, state) => const Scaffold(body: SizedBox.shrink())),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          sesionControllerProvider.overrideWith(_SesionControllerDePrueba.new),
        ],
        child: MaterialApp.router(
          theme: tema ?? AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('Identidad del Empleado + progreso', () {
    testWidgets('un préstamo recién registrado (sin abonos) muestra identidad + "0 de \$X pagados" con barra en 0%', (tester) async {
      final empleado = await crearEmpleadoDePrueba(1);
      await registrar.ejecutar(
        empleadoId: empleado.id,
        tipo: 'prestamo',
        fechaRegistro: DateTime(2026, 1, 1),
        importeOriginal: 60000,
        numeroCuotas: 3,
        fechaPrimeraCuota: DateTime(2026, 2, 5),
      );

      await pumpScreen(tester, tamano: const Size(1366, 768));

      expect(tester.takeException(), isNull);
      expect(find.text('Empleado01 Apellido01'), findsWidgets, reason: 'identidad tipo Plantilla activa: nombre visible');
      expect(find.text('No. 1'), findsOneWidget);
      expect(find.textContaining('de \$600.00 pagados'), findsOneWidget);
      expect(find.byType(RisegProgressBar), findsOneWidget);
    });

    testWidgets('un saldo cancelado NUNCA se muestra como si siguiera cobrándose ni como si se hubiera pagado', (tester) async {
      final empleado = await crearEmpleadoDePrueba(2);
      final resultado = await registrar.ejecutar(
        empleadoId: empleado.id,
        tipo: 'botas',
        fechaRegistro: DateTime(2026, 1, 1),
        importeOriginal: 70000,
        numeroCuotas: 2,
        fechaPrimeraCuota: DateTime(2026, 2, 5),
      ) as RegistrarDescuentoProgramadoExitoso;

      final cancelado = await cancelarSaldo.ejecutar(descuentoProgramadoId: resultado.descuento.id, motivo: 'Baja del empleado');
      expect(cancelado, isA<CancelarSaldoDescuentoProgramadoExitoso>());

      await pumpScreen(tester, tamano: const Size(1366, 768));
      // Pedido explícito (división Activos/Cancelados en dos pestañas):
      // un cancelado ya no aparece bajo la pestaña por defecto.
      await tester.tap(find.byKey(const Key('descuentos_personal_grupo_cancelados')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Saldo cancelado'), findsOneWidget);
      expect(find.textContaining('pagados'), findsNothing, reason: 'un saldo condonado no es lo mismo que "pagado"');
      expect(find.byType(RisegProgressBar), findsNothing, reason: 'cancelado nunca muestra barra de progreso');
    });
  });

  group('Listado — responsive sin overflow', () {
    setUp(() async {
      final empleado = await crearEmpleadoDePrueba(1);
      await registrar.ejecutar(
        empleadoId: empleado.id,
        tipo: 'prestamo',
        fechaRegistro: DateTime(2026, 1, 1),
        importeOriginal: 60000,
        numeroCuotas: 3,
        fechaPrimeraCuota: DateTime(2026, 2, 5),
      );
    });

    for (final tamano in _anchos) {
      testWidgets('${tamano.width.toInt()}×${tamano.height.toInt()}: cero overflow', (tester) async {
        await pumpScreen(tester, tamano: tamano);

        expect(tester.takeException(), isNull, reason: 'nunca debe aparecer RenderFlex overflow en Descuentos');
        expect(find.byIcon(Icons.chevron_right), findsWidgets);
      });
    }

    testWidgets('modo oscuro, ancho angosto (700×900): cero overflow', (tester) async {
      await pumpScreen(tester, tamano: const Size(700, 900), tema: AppTheme.dark());
      expect(tester.takeException(), isNull);
    });

    testWidgets('modo oscuro, ancho amplio (1536×864): cero overflow', (tester) async {
      await pumpScreen(tester, tamano: const Size(1536, 864), tema: AppTheme.dark());
      expect(tester.takeException(), isNull);
    });
  });
}
