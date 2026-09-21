// Etapa "Telefonía" — §15 del pedido: el módulo estaba identificado
// como uno de los que NO tenían cobertura responsive alguna.
//
// Mismo criterio de evidencia que el resto de RISEG ONE: sin
// herramienta de captura, la prueba es "cero overflow / cero excepción"
// (`tester.takeException()`), nunca comparación de píxeles. Los datos
// son deliberadamente hostiles al layout: ICCID de 19 dígitos, nombre
// de operador "otro" largo, motivo de anulación largo e importes
// grandes.

import 'dart:io';

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
import 'package:riseg_one/features/organizacion/organizacion_providers.dart';
import 'package:riseg_one/features/telefonia/data/tables/linea_telefonica_table.dart';
import 'package:riseg_one/features/telefonia/presentation/linea_telefonica_expediente_screen.dart';
import 'package:riseg_one/features/telefonia/presentation/lineas_telefonicas_list_screen.dart';
import 'package:riseg_one/features/telefonia/presentation/widgets/asignar_linea_telefonica_dialog.dart';
import 'package:riseg_one/features/telefonia/presentation/widgets/gestionar_linea_telefonica_dialog.dart';
import 'package:riseg_one/features/telefonia/presentation/widgets/gestionar_recarga_linea_telefonica_dialogs.dart';
import 'package:riseg_one/features/telefonia/presentation/widgets/registrar_recarga_linea_telefonica_dialog.dart';
import 'package:riseg_one/features/telefonia/telefonia_providers.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;

class _SesionMaestro extends SesionController {
  @override
  SesionUsuario? build() => const SesionUsuario(
        usuarioId: 'maestro',
        nombre: 'Maestro de prueba',
        nombreUsuario: 'maestro',
        esMaestro: true,
        permisos: {},
      );
}

const _anchos = <String, Size>{
  '1536': Size(1536, 1000),
  '1366': Size(1366, 900),
  '1024': Size(1024, 900),
  '700': Size(700, 900),
  '500': Size(500, 900),
};

const _motivoLargo =
    'La recarga se capturó en la línea equivocada: el saldo correspondía a la unidad de supervisión '
    'de Atlacomulco y no a la de Toluca, verificado contra el ticket del punto de venta.';

void main() {
  late AppDatabase db;
  late Directory tempDir;
  late ProviderContainer container;
  late String lineaId;
  late RecargaLineaTelefonicaData recargaVigente;
  late RecargaLineaTelefonicaData recargaAnulada;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    tempDir = Directory.systemTemp.createTempSync('riseg_telefonia_responsive_test_');
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionMaestro.new),
        attachmentStorageProvider.overrideWithValue(AttachmentStorage(tempDir.path)),
      ],
    );
    addTearDown(container.dispose);

    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(
            id: const Value('maestro'),
            nombre: 'Maestro de prueba',
            nombreUsuario: 'maestro',
            passwordHash: r'pbkdf2$1$c2FsdA==$aGFzaA==',
            esMaestro: const Value(true),
          ),
        );

    final linea = await container.read(lineaTelefonicaRepositoryProvider).crear(
          codigo: 'LIN-000004',
          numero: '5512345678',
          operador: OperadorTelefonico.otro.name,
          operadorOtroNombre: 'Operador Virtual Empresarial de Cobertura Nacional S.A. de C.V.',
          modalidadSim: ModalidadSim.fisica.name,
          iccid: '8952140061234567890',
          observaciones: _motivoLargo,
        );
    lineaId = linea.id;

    final recargaRepo = container.read(recargaLineaTelefonicaRepositoryProvider);
    recargaVigente = await recargaRepo.registrar(
      lineaTelefonicaId: lineaId,
      fecha: DateTime(2026, 9, 1),
      importe: 50000,
      actorUsuarioId: 'maestro',
      formaPago: FormaPago.efectivo.name,
    );
    recargaAnulada = await recargaRepo.registrar(
      lineaTelefonicaId: lineaId,
      fecha: DateTime(2026, 9, 5),
      importe: 120000,
      observaciones: 'Recarga doble por error del punto de venta',
      actorUsuarioId: 'maestro',
      formaPago: FormaPago.efectivo.name,
    );
    await container.read(cancelarRecargaLineaTelefonicaAutorizadoProvider)(
      recargaLineaTelefonicaId: recargaAnulada.id,
      motivo: _motivoLargo,
    );
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Widget envolver({required bool oscuro, required Widget child}) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: oscuro ? AppTheme.dark() : AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: oscuro ? ThemeMode.dark : ThemeMode.light,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    );
  }

  void fijarTamano(WidgetTester tester, Size tamano) {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> abrirDialogo(
    WidgetTester tester, {
    required Size tamano,
    required bool oscuro,
    required Future<void> Function(BuildContext context, WidgetRef ref) abrir,
  }) async {
    fijarTamano(tester, tamano);
    await tester.pumpWidget(
      envolver(
        oscuro: oscuro,
        child: Consumer(
          builder: (context, ref, _) => Scaffold(
            body: Center(
              child: ElevatedButton(onPressed: () => abrir(context, ref), child: const Text('abrir')),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  for (final entrada in _anchos.entries) {
    final etiqueta = entrada.key;
    final tamano = entrada.value;

    for (final oscuro in [false, true]) {
      final tema = oscuro ? 'oscuro' : 'claro';

      testWidgets('Listado de líneas ($etiqueta, $tema): cero overflow', (tester) async {
        fijarTamano(tester, tamano);
        await tester.pumpWidget(
          envolver(oscuro: oscuro, child: const Scaffold(body: LineasTelefonicasListScreen())),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });

      testWidgets('Expediente de línea ($etiqueta, $tema): cero overflow', (tester) async {
        fijarTamano(tester, tamano);
        await tester.pumpWidget(envolver(oscuro: oscuro, child: LineaTelefonicaExpedienteScreen(lineaTelefonicaId: lineaId)));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        // El historial trae la recarga anulada con su motivo largo.
        expect(find.textContaining('Anulada:'), findsOneWidget);
      });

      testWidgets('Alta/corrección de línea ($etiqueta, $tema): cero overflow', (tester) async {
        await abrirDialogo(
          tester,
          tamano: tamano,
          oscuro: oscuro,
          abrir: (context, ref) async {
            final linea = await ref.read(lineaTelefonicaRepositoryProvider).obtenerPorId(lineaId);
            if (!context.mounted) return;
            await mostrarDialogoGestionarLineaTelefonica(context, ref, linea: linea);
          },
        );

        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('linea_telefonica_campo_motivo')), findsOneWidget);
      });

      testWidgets('Asignación de línea ($etiqueta, $tema): cero overflow', (tester) async {
        await abrirDialogo(
          tester,
          tamano: tamano,
          oscuro: oscuro,
          abrir: (context, ref) =>
              mostrarDialogoAsignarLineaTelefonica(context, ref, lineaId),
        );

        expect(tester.takeException(), isNull);
      });

      testWidgets('Registrar recarga ($etiqueta, $tema): cero overflow', (tester) async {
        await abrirDialogo(
          tester,
          tamano: tamano,
          oscuro: oscuro,
          abrir: (context, ref) => mostrarDialogoRegistrarRecargaLineaTelefonica(context, ref, lineaId),
        );

        expect(tester.takeException(), isNull);
      });

      testWidgets('Corregir recarga ($etiqueta, $tema): cero overflow', (tester) async {
        await abrirDialogo(
          tester,
          tamano: tamano,
          oscuro: oscuro,
          abrir: (context, ref) => mostrarDialogoCorregirRecargaLineaTelefonica(context, ref, recargaVigente),
        );

        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('recarga_corregir_motivo')), findsOneWidget);
      });

      testWidgets('Anular recarga ($etiqueta, $tema): cero overflow', (tester) async {
        await abrirDialogo(
          tester,
          tamano: tamano,
          oscuro: oscuro,
          abrir: (context, ref) => mostrarDialogoAnularRecargaLineaTelefonica(context, ref, recargaVigente),
        );

        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('recarga_anular_motivo')), findsOneWidget);
      });
    }
  }

  testWidgets('la recarga anulada se muestra tachada y no se corrige ni se vuelve a anular; la vigente sí', (tester) async {
    fijarTamano(tester, const Size(1366, 900));
    await tester.pumpWidget(envolver(oscuro: false, child: LineaTelefonicaExpedienteScreen(lineaTelefonicaId: lineaId)));
    await tester.pumpAndSettle();

    // Rebanada 3: la anulada SÍ conserva su menú —su rastro financiero
    // se sigue pudiendo consultar— pero sin las dos acciones que ya no
    // aplican.
    final menuAnulada = find.byKey(Key('recarga_acciones_${recargaAnulada.id}'));
    expect(menuAnulada, findsOneWidget);
    await tester.ensureVisible(menuAnulada);
    await tester.pumpAndSettle();
    await tester.tap(menuAnulada);
    await tester.pumpAndSettle();
    expect(find.byKey(Key('recarga_corregir_${recargaAnulada.id}')), findsNothing,
        reason: 'una recarga anulada no se corrige');
    expect(find.byKey(Key('recarga_anular_${recargaAnulada.id}')), findsNothing,
        reason: 'ni se vuelve a anular');
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    final menuVigente = find.byKey(Key('recarga_acciones_${recargaVigente.id}'));
    expect(menuVigente, findsOneWidget);

    await tester.ensureVisible(menuVigente);
    await tester.pumpAndSettle();
    await tester.tap(menuVigente);
    await tester.pumpAndSettle();
    expect(find.byKey(Key('recarga_corregir_${recargaVigente.id}')), findsOneWidget);
    expect(find.byKey(Key('recarga_anular_${recargaVigente.id}')), findsOneWidget);
  });

  testWidgets('el total de recargas del expediente EXCLUYE la anulada', (tester) async {
    fijarTamano(tester, const Size(1366, 900));
    await tester.pumpWidget(envolver(oscuro: false, child: LineaTelefonicaExpedienteScreen(lineaTelefonicaId: lineaId)));
    await tester.pumpAndSettle();

    // 500 vigente + 1,200 anulada: el total debe decir 500, no 1,700.
    expect(find.textContaining(r'$1,700'), findsNothing, reason: 'el mismo bug que apareció en Vehículos');
    expect(find.textContaining(r'$500.00'), findsWidgets);
  });
}
