// Etapa "Origen financiero de Egresos manuales: Cuenta vs. TDC" —
// punto 17 del pedido: los dos diálogos modificados (Registrar egreso y
// Corregir egreso) a 1536/1366/1024/700/500 × claro/oscuro. Mismo
// criterio de evidencia que el resto de RISEG ONE: sin herramienta de
// captura, la prueba es "cero overflow / cero excepción"
// (`tester.takeException()`), nunca comparación de píxeles.
//
// Además de no desbordarse, se verifica lo que esta etapa agregó al
// selector: cuentas Y tarjetas conviven en la misma lista de Origen
// financiero, y una tarjeta muestra su crédito disponible.

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_financiera_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/domain/origen_financiero_gasto.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_deuda_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_egreso_usecase.dart';
import 'package:riseg_one/features/finanzas/presentation/egresos/widgets/corregir_egreso_dialog.dart';
import 'package:riseg_one/features/finanzas/presentation/egresos/widgets/registrar_egreso_dialog.dart';
import 'package:riseg_one/features/finanzas/presentation/widgets/origen_financiero_select.dart';
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

/// Los 5 anchos del pedido. Alto generoso: estos diálogos son largos y
/// lo que se mide aquí es el desbordamiento horizontal del contenido,
/// no el recorte vertical del `Scaffold` de prueba.
const _anchos = <String, Size>{
  '1536': Size(1536, 1000),
  '1366': Size(1366, 900),
  '1024': Size(1024, 900),
  '700': Size(700, 900),
  '500': Size(500, 900),
};

void main() {
  late AppDatabase db;
  late Directory tempDir;
  late EgresoData egresoConTarjeta;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    tempDir = Directory.systemTemp.createTempSync('riseg_egreso_origen_responsive_test_');

    final egresoRepo = EgresoRepositoryImpl(db);
    final deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
    final cuentaRepo = CuentaFinancieraRepositoryImpl(db);
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));

    await cuentaRepo.crear(
      codigo: 'CTA-0002',
      nombre: 'Klar Empresarial',
      tipo: 'banco',
      saldoInicial: 174717700,
      fechaSaldoInicial: DateTime(2026, 1, 1),
    );
    await cuentaRepo.crear(
      codigo: 'CTA-0003',
      nombre: 'BBVA Empresarial',
      tipo: 'banco',
      saldoInicial: 530880000,
      fechaSaldoInicial: DateTime(2026, 1, 1),
    );

    // Importes grandes y nombre largo a propósito (punto 19 del pedido
    // de la etapa anterior, mismo criterio): es donde un selector con
    // etiqueta compuesta "tarjeta · disponible X" se desbordaría.
    final registrarDeuda = RegistrarDeudaUseCase(deudaRepo, generarCodigo);
    final konfio = (await registrarDeuda.ejecutar(
      nombre: 'TDC Konfío Empresarial — línea revolvente principal',
      tipo: 'tarjetaCredito',
      saldoInicial: 3326608,
      fechaSaldoInicial: DateTime(2026, 1, 1),
      tarjetaLimiteCredito: 400000000,
    )) as RegistrarDeudaExitoso;
    await registrarDeuda.ejecutar(
      nombre: 'TDC Clara Empresarial',
      tipo: 'tarjetaCredito',
      saldoInicial: 0,
      tarjetaLimiteCredito: 300000000,
    );

    final registrarEgreso = RegistrarEgresoUseCase(egresoRepo, generarCodigo, deudaRepo);
    egresoConTarjeta = (await registrarEgreso.ejecutar(
      monto: 135998000,
      fecha: DateTime(2026, 3, 5),
      formaPago: 'tarjeta',
      concepto: 'Gasolina de la flotilla completa durante el periodo de auditoría',
      origen: OrigenFinancieroTarjeta(konfio.deuda.id),
    ) as RegistrarEgresoExitoso)
        .egreso;
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> abrirDialogo(
    WidgetTester tester, {
    required Size tamano,
    required bool oscuro,
    required Future<void> Function(BuildContext context, WidgetRef ref) abrir,
  }) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          sesionControllerProvider.overrideWith(_SesionMaestroDePrueba.new),
          attachmentStorageProvider.overrideWithValue(AttachmentStorage(tempDir.path)),
        ],
        child: MaterialApp(
          theme: oscuro ? AppTheme.dark() : AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: oscuro ? ThemeMode.dark : ThemeMode.light,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => abrir(context, ref),
                  child: const Text('abrir'),
                ),
              ),
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

      testWidgets('Registrar egreso ($etiqueta, $tema): cero overflow', (tester) async {
        await abrirDialogo(
          tester,
          tamano: tamano,
          oscuro: oscuro,
          abrir: (context, ref) => mostrarDialogoRegistrarEgreso(context, ref, servicios: const []),
        );

        expect(tester.takeException(), isNull);
        expect(find.text('Origen financiero'), findsOneWidget);
      });

      testWidgets('Corregir egreso con TDC ($etiqueta, $tema): cero overflow', (tester) async {
        await abrirDialogo(
          tester,
          tamano: tamano,
          oscuro: oscuro,
          abrir: (context, ref) => mostrarDialogoCorregirEgreso(context, ref, egresoConTarjeta),
        );

        expect(tester.takeException(), isNull);
        expect(find.text('Origen financiero'), findsOneWidget);
      });
    }
  }

  testWidgets('el selector de Origen financiero ofrece cuentas Y tarjetas, con el disponible de cada TDC', (tester) async {
    await abrirDialogo(
      tester,
      tamano: const Size(1366, 900),
      oscuro: false,
      abrir: (context, ref) => mostrarDialogoRegistrarEgreso(context, ref, servicios: const []),
    );

    // Se inspeccionan las opciones del selector directamente, en vez de
    // abrir el overlay del `DropdownButton`: varios campos del
    // formulario muestran "Sin asignar", y el menú de Material vive en
    // un overlay cuyo comportamiento en pruebas no es lo que esta
    // prueba quiere fijar. Lo que importa es el contrato de datos —
    // qué opciones ofrece el selector.
    final select = tester.widget<RisegSelect<ClaveOrigenFinanciero?>>(
      find.descendant(
        of: find.byType(RisegOrigenFinancieroSelect),
        matching: find.byType(RisegSelect<ClaveOrigenFinanciero?>),
      ),
    );
    final etiquetas = select.items.map((i) => i.label).toList();

    expect(etiquetas, contains('Sin asignar'));
    expect(etiquetas, contains('Klar Empresarial'), reason: 'las cuentas siguen ahí');
    expect(etiquetas, contains('BBVA Empresarial'));
    expect(
      etiquetas.any((e) => e.contains('TDC Konfío Empresarial')),
      isTrue,
      reason: 'la tarjeta que financió el caso real ahora SÍ aparece como origen',
    );
    expect(
      etiquetas.where((e) => e.contains('disponible')).length,
      2,
      reason: 'las 2 TDC activas muestran su crédito disponible (creditoDisponibleTarjeta)',
    );
    expect(
      select.items.where((i) => i.value != null && i.value!.startsWith('tarjeta:')).length,
      2,
      reason: 'las tarjetas se distinguen por clave, nunca se confunden con una cuenta',
    );
  });
}
