// Etapa 17 — pasada visual de Finanzas. Smoke de tema oscuro +
// breakpoints representativos (1366×768 y ~500px) para las 7 pantallas
// tocadas en esta pasada: Resumen, Cuentas por cobrar, Pagos,
// Complementos, Ingresos, Egresos y Categorías. Mismo criterio que el
// resto de RISEG ONE: sin herramienta de captura de pantalla, la
// evidencia es "cero overflow / cero excepción"
// (`tester.takeException()`), nunca una comparación de píxeles.

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/pago_repository_impl.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_egreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_pago_usecase.dart';
import 'package:riseg_one/features/finanzas/presentation/categorias/categorias_list_screen.dart';
import 'package:riseg_one/features/finanzas/presentation/complementos/complementos_list_screen.dart';
import 'package:riseg_one/features/finanzas/presentation/cuentas_por_cobrar/cuentas_por_cobrar_list_screen.dart';
import 'package:riseg_one/features/finanzas/presentation/egresos/egresos_list_screen.dart';
import 'package:riseg_one/features/finanzas/presentation/ingresos/ingresos_list_screen.dart';
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_list_screen.dart';
import 'package:riseg_one/features/finanzas/presentation/resumen/resumen_financiero_screen.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart';
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

Future<void> _pumpOscuro(
  WidgetTester tester,
  AppDatabase db,
  Directory tempDir, {
  required Widget child,
  required Size tamano,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: '/pantalla',
    routes: [
      GoRoute(path: '/pantalla', builder: (context, state) => Scaffold(body: child)),
      GoRoute(path: '/comercial/clientes/:id', builder: (context, state) => const Scaffold(body: SizedBox.shrink())),
      GoRoute(path: '/comercial/servicios/:id', builder: (context, state) => const Scaffold(body: SizedBox.shrink())),
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
        theme: AppTheme.dark(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.dark,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _anchosRepresentativos = [Size(1366, 768), Size(500, 900)];

void main() {
  late AppDatabase db;
  late Directory tempDir;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    tempDir = Directory.systemTemp.createTempSync('riseg_finanzas_tema_oscuro_test_');

    final clienteRepo = ClienteRepositoryImpl(db);
    final cliente = await clienteRepo.crear(ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Sportium'));
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));

    // Un Pago real (genera su Ingreso automático) y un Egreso manual —
    // suficiente para que Resumen/CxC/Pagos/Ingresos/Egresos tengan
    // contenido real que renderizar, no solo estados vacíos.
    await RegistrarPagoUseCase(PagoRepositoryImpl(db), clienteRepo, generarCodigo).ejecutar(
      clienteId: cliente.id,
      montoTotal: 230000,
      fechaPago: DateTime.now(),
      formaPago: 'transferencia',
    );
    await RegistrarEgresoUseCase(EgresoRepositoryImpl(db), generarCodigo, DeudaRepositoryImpl(db, EgresoRepositoryImpl(db)))
        .ejecutar(monto: 80000, fecha: DateTime.now(), formaPago: 'efectivo', concepto: 'Renta de oficina');
  });

  tearDown(() {
    db.close();
    tempDir.deleteSync(recursive: true);
  });

  for (final tamano in _anchosRepresentativos) {
    final etiqueta = '${tamano.width.toInt()}×${tamano.height.toInt()}';

    testWidgets('Resumen ($etiqueta, oscuro): cero overflow', (tester) async {
      await _pumpOscuro(tester, db, tempDir, child: const ResumenFinancieroScreen(), tamano: tamano);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Cuentas por cobrar ($etiqueta, oscuro): cero overflow', (tester) async {
      await _pumpOscuro(tester, db, tempDir, child: const CuentasPorCobrarListScreen(), tamano: tamano);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Pagos ($etiqueta, oscuro): cero overflow', (tester) async {
      await _pumpOscuro(tester, db, tempDir, child: const PagosListScreen(), tamano: tamano);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Complementos ($etiqueta, oscuro): cero overflow', (tester) async {
      await _pumpOscuro(tester, db, tempDir, child: const ComplementosListScreen(), tamano: tamano);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Ingresos ($etiqueta, oscuro): cero overflow', (tester) async {
      await _pumpOscuro(tester, db, tempDir, child: const IngresosListScreen(), tamano: tamano);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Egresos ($etiqueta, oscuro): cero overflow', (tester) async {
      await _pumpOscuro(tester, db, tempDir, child: const EgresosListScreen(), tamano: tamano);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Categorías ($etiqueta, oscuro): cero overflow', (tester) async {
      await _pumpOscuro(tester, db, tempDir, child: const CategoriasListScreen(), tamano: tamano);
      expect(tester.takeException(), isNull);
    });
  }
}
