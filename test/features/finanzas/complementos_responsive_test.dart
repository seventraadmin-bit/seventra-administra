// Etapa "Complemento de pago dependiente del Pago real" — §18.
//
// La pantalla Finanzas → Complementos ganó una vista nueva
// (Pendientes, una proyección) y dos columnas más en Registrados
// (fecha real del Pago y facturas cubiertas). Matriz
// 1536/1366/1024/700/500 × claro/oscuro, con datos reales en ambas
// vistas — una tabla vacía no probaría el ancho de nada.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/finanzas/finanzas_providers.dart';
import 'package:riseg_one/features/finanzas/presentation/complementos/complementos_list_screen.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

class _SesionFinanzas extends SesionController {
  @override
  SesionUsuario? build() => const SesionUsuario(
        usuarioId: 'u1',
        nombre: 'TESORERA',
        nombreUsuario: 'tesorera',
        esMaestro: false,
        permisos: {'finanzas.ver', 'pagos.registrar', 'pagos.corregir', 'pagos.cancelar'},
      );
}

void main() {
  late AppDatabase db;
  late String clienteId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final cliente = await db.into(db.cliente).insertReturning(
          ClienteCompanion.insert(
            codigo: 'CLI-000050',
            // Nombre largo a propósito: la columna Cliente debe truncar,
            // no desbordar, a 500px.
            nombreComercial: 'MORGAN ATLACOMULCO SERVICIOS INTEGRALES',
          ),
        );
    clienteId = cliente.id;
  });

  tearDown(() => db.close());

  /// Un Pago pendiente (sin Complemento) y otro ya complementado, para
  /// que las dos vistas tengan filas reales.
  Future<void> sembrarDatos(ProviderContainer container) async {
    Future<CuentaPorCobrarData> cuenta(String sufijo, int importe) async {
      await db.into(db.documentoPorEmitir).insert(
            DocumentoPorEmitirCompanion.insert(
              id: Value('doc-$sufijo'),
              codigo: 'DPE-$sufijo',
              generationKey: 'gk-$sufijo',
              clienteId: clienteId,
              tipoDocumento: 'cfdi',
              metodo: 'ppd',
              requiereComplemento: const Value(true),
              periodoInicio: DateTime(2026, 9, 1),
              periodoFin: DateTime(2026, 9, 30),
              agrupacion: 'porServicio',
              importeBaseEsperado: importe,
              importeFinalEsperado: importe,
            ),
          );
      return container.read(cuentaPorCobrarRepositoryProvider).crear(
            documentoPorEmitirId: 'doc-$sufijo',
            clienteId: clienteId,
            tipoDocumento: 'cfdi',
            metodo: 'ppd',
            requiereComplemento: true,
            folioDocumento: 'FAC-2026-$sufijo',
            fechaEmisionReal: DateTime(2026, 9, 3),
            importeEmitido: importe,
          );
    }

    final pagoRepo = container.read(pagoRepositoryProvider);

    // Pendiente, con DOS facturas cubiertas por un solo Pago.
    final a = await cuenta('A', 1000000);
    final b = await cuenta('B', 2000000);
    final pendiente = await pagoRepo.crear(
      folioPago: 'PAG-000200',
      clienteId: clienteId,
      montoTotal: 3000000,
      fechaPago: DateTime(2026, 10, 12),
      formaPago: 'transferencia',
    );
    await pagoRepo.aplicar(pagoId: pendiente.id, cuentaPorCobrarId: a.id, monto: 1000000);
    await pagoRepo.aplicar(pagoId: pendiente.id, cuentaPorCobrarId: b.id, monto: 2000000);

    // Ya complementado.
    final c = await cuenta('C', 5000000);
    final complementado = await pagoRepo.crear(
      folioPago: 'PAG-000201',
      clienteId: clienteId,
      montoTotal: 5000000,
      fechaPago: DateTime(2026, 10, 14),
      formaPago: 'transferencia',
    );
    await pagoRepo.aplicar(pagoId: complementado.id, cuentaPorCobrarId: c.id, monto: 5000000);
    await container.read(registrarComplementoPagoUseCaseProvider).ejecutar(
          pagoId: complementado.id,
          uuid: 'dddddddd-1111-2222-3333-444444444444',
          fechaTimbrado: DateTime(2026, 10, 16),
          montoTotal: 5000000,
        );
  }

  Future<void> montar(WidgetTester tester, Size tamano, ThemeData tema) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionFinanzas.new),
        attachmentStorageProvider.overrideWithValue(AttachmentStorage('.')),
      ],
    );
    addTearDown(container.dispose);
    await sembrarDatos(container);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: tema,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: ComplementosListScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  const anchos = [Size(1536, 864), Size(1366, 768), Size(1024, 768), Size(700, 900), Size(500, 900)];
  final temas = {'claro': AppTheme.light(), 'oscuro': AppTheme.dark()};

  for (final entradaTema in temas.entries) {
    for (final tamano in anchos) {
      final etiqueta = '${tamano.width.toInt()}x${tamano.height.toInt()}, ${entradaTema.key}';

      testWidgets('Pendientes ($etiqueta): sin overflow, con el Pago real y sus facturas', (tester) async {
        await montar(tester, tamano, entradaTema.value);
        final l10n = await AppLocalizations.delegate.load(const Locale('es'));

        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('complementos_tabla_pendientes')), findsOneWidget);

        // La vista arranca en Pendientes: es la pregunta que la pantalla
        // no sabía responder.
        expect(find.text('PAG-000200'), findsOneWidget);
        expect(find.text('12/10/2026'), findsOneWidget, reason: 'la fecha REAL del pago');
        expect(find.text(l10n.complementosEstadoPendiente), findsWidgets);
        // El Pago ya complementado NO aparece aquí.
        expect(find.text('PAG-000201'), findsNothing);
      });

      testWidgets('Registrados ($etiqueta): sin overflow, con trazabilidad completa', (tester) async {
        await montar(tester, tamano, entradaTema.value);
        final l10n = await AppLocalizations.delegate.load(const Locale('es'));

        await tester.tap(find.byKey(const Key('complementos_selector_vista')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.complementosFiltroVistaRegistrados).last);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('complementos_tabla_registrados')), findsOneWidget);
        expect(find.text('PAG-000201'), findsOneWidget);
        expect(find.text('14/10/2026'), findsOneWidget, reason: 'fecha del Pago');
        expect(find.text('16/10/2026'), findsOneWidget, reason: 'fecha de timbrado, distinta de la del Pago');
        expect(find.text('FAC-2026-C'), findsOneWidget, reason: 'la factura cubierta, derivada de la aplicación');
      });
    }
  }

  testWidgets('un Pago aplicado a dos facturas las muestra ambas sin duplicar el Pago', (tester) async {
    await montar(tester, const Size(1366, 768), AppTheme.light());

    expect(find.text('PAG-000200'), findsOneWidget, reason: 'una sola obligación, aunque cubra dos facturas');
    expect(find.text('FAC-2026-A, FAC-2026-B'), findsOneWidget);
  });

  testWidgets('varios Complementos históricos del mismo Pago no duplican la obligación pendiente', (tester) async {
    // Escenario del modelo de sustitutos (schemaVersion 79): el Pago
    // PAG-000201 acumula A cancelado + B vigente; PAG-000200 sigue sin
    // ninguno.
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionFinanzas.new),
        attachmentStorageProvider.overrideWithValue(AttachmentStorage('.')),
      ],
    );
    addTearDown(container.dispose);
    await sembrarDatos(container);

    // Cancela el Complemento de PAG-000201 y registra un sustituto.
    final complementoRepo = container.read(complementoPagoRepositoryProvider);
    final vigente = (await complementoRepo.listar()).single;
    await container.read(cancelarComplementoPagoUseCaseProvider).ejecutar(
          complementoPagoId: vigente.id,
          motivo: 'Timbrado incorrecto',
        );
    await container.read(registrarComplementoPagoUseCaseProvider).ejecutar(
          pagoId: vigente.pagoId,
          uuid: 'eeeeeeee-1111-2222-3333-444444444444',
          fechaTimbrado: DateTime(2026, 10, 18),
          montoTotal: 5000000,
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: ComplementosListScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    // Pendientes: SOLO PAG-000200. El Pago con sustituto vigente no
    // reaparece, y no se cuenta dos veces por tener dos Complementos.
    expect(find.text('PAG-000200'), findsOneWidget);
    expect(find.text('PAG-000201'), findsNothing);
    expect(find.text(l10n.complementosPendientesConteo(1)), findsOneWidget);

    // Cancelados: el A histórico, con su Pago.
    await tester.tap(find.byKey(const Key('complementos_selector_vista')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.complementosFiltroVistaCancelados).last);
    await tester.pumpAndSettle();
    expect(find.text('PAG-000201'), findsOneWidget, reason: 'el cancelado se conserva en el histórico');

    // Todos: ambos Complementos del mismo Pago, dos filas distintas.
    await tester.tap(find.byKey(const Key('complementos_selector_vista')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.complementosFiltroVistaTodos).last);
    await tester.pumpAndSettle();
    expect(find.text('PAG-000201'), findsNWidgets(2), reason: 'A y B, ambos del mismo Pago');
    expect(tester.takeException(), isNull);
  });

  testWidgets('el contador de pendientes sigue siendo correcto desde otra vista', (tester) async {
    await montar(tester, const Size(1366, 768), AppTheme.light());
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await tester.tap(find.byKey(const Key('complementos_selector_vista')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.complementosFiltroVistaRegistrados).last);
    await tester.pumpAndSettle();

    // El contador vive fuera del selector, así que sigue a la vista:
    // dice cuántos faltan aunque se esté mirando Registrados.
    expect(find.byKey(const Key('complementos_contador_pendientes')), findsOneWidget);
    expect(find.text(l10n.complementosPendientesConteo(1)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
