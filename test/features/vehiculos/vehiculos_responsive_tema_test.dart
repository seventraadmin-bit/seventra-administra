// Etapa "Vehículos: ciclo de vida, gastos, origen financiero y
// trazabilidad" — §16 del pedido: las pantallas y diálogos que esta
// etapa tocó, a 1536/1366/1024/700/500 × claro/oscuro.
//
// Mismo criterio de evidencia que el resto de RISEG ONE: sin
// herramienta de captura de pantalla, la prueba es "cero overflow /
// cero excepción" (`tester.takeException()`), nunca comparación de
// píxeles. Los datos se eligen a propósito hostiles al layout: nombres
// largos de tarjeta con crédito disponible en la etiqueta, importes
// grandes, y un motivo de anulación largo — que es donde una fila de la
// tabla se desborda.

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
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/domain/origen_financiero_gasto.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_deuda_usecase.dart';
import 'package:riseg_one/features/finanzas/finanzas_providers.dart';
import 'package:riseg_one/features/finanzas/presentation/widgets/origen_financiero_select.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import 'package:riseg_one/features/vehiculos/data/tables/vehiculo_documento_table.dart';
import 'package:riseg_one/features/vehiculos/data/tables/vehiculo_mantenimiento_table.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/registrar_documento_vehiculo_usecase.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/registrar_mantenimiento_vehiculo_usecase.dart';
import 'package:riseg_one/features/vehiculos/presentation/vehiculo_expediente_screen.dart';
import 'package:riseg_one/features/vehiculos/presentation/widgets/anular_mantenimiento_vehiculo_dialog.dart';
import 'package:riseg_one/features/vehiculos/presentation/widgets/corregir_documento_vehiculo_dialog.dart';
import 'package:riseg_one/features/vehiculos/presentation/widgets/corregir_mantenimiento_vehiculo_dialog.dart';
import 'package:riseg_one/features/vehiculos/presentation/widgets/gestionar_vehiculo_dialog.dart';
import 'package:riseg_one/features/vehiculos/presentation/widgets/registrar_mantenimiento_vehiculo_dialog.dart';
import 'package:riseg_one/features/vehiculos/vehiculos_providers.dart';

/// Un usuario normal con toda la operación de Vehículos, pero SIN
/// `vehiculos.cancelar` — el caso que la UI debe reflejar.
class _SesionOperarSinCancelar extends SesionController {
  @override
  SesionUsuario? build() => const SesionUsuario(
        usuarioId: 'usuario-maestro',
        nombre: 'Operador de flotilla',
        nombreUsuario: 'operador',
        esMaestro: false,
        permisos: {'vehiculos.ver', 'vehiculos.crear', 'vehiculos.modificar', 'vehiculos.archivar', 'vehiculos.operar'},
      );
}

class _SesionMaestroDePrueba extends SesionController {
  @override
  SesionUsuario? build() => const SesionUsuario(
        usuarioId: 'usuario-maestro',
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

void main() {
  late AppDatabase db;
  late Directory tempDir;
  late ProviderContainer container;
  late String vehiculoId;
  late VehiculoMantenimientoData mantenimientoConTarjeta;
  late VehiculoMantenimientoData mantenimientoAnulado;
  late VehiculoDocumentoData poliza;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    tempDir = Directory.systemTemp.createTempSync('riseg_vehiculos_responsive_test_');
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionMaestroDePrueba.new),
        attachmentStorageProvider.overrideWithValue(AttachmentStorage(tempDir.path)),
      ],
    );
    addTearDown(container.dispose);

    // El actor de la sesión debe EXISTIR: cada registro de esta etapa
    // graba `actorUsuarioId` con FK real hacia Usuario, y sin la fila
    // el alta falla con FOREIGN KEY constraint (no en silencio).
    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(
            id: const Value('usuario-maestro'),
            nombre: 'Maestro de prueba',
            nombreUsuario: 'maestro',
            passwordHash: r'pbkdf2$1$c2FsdA==$aGFzaA==',
            esMaestro: const Value(true),
          ),
        );

    await container.read(cuentaFinancieraRepositoryProvider).crear(
          codigo: 'CTA-0003',
          nombre: 'BBVA Empresarial',
          tipo: 'banco',
          saldoInicial: 530880000,
          fechaSaldoInicial: DateTime(2026, 1, 1),
        );

    final registrarDeuda = container.read(registrarDeudaUseCaseProvider);
    final konfio = (await registrarDeuda.ejecutar(
      nombre: 'TDC Konfío Empresarial — línea revolvente principal',
      tipo: 'tarjetaCredito',
      saldoInicial: 3326608,
      fechaSaldoInicial: DateTime(2026, 1, 1),
      tarjetaLimiteCredito: 400000000,
    )) as RegistrarDeudaExitoso;

    final vehiculo = await container.read(vehiculoRepositoryProvider).crear(
          codigo: 'VEH-000001',
          marca: 'Nissan',
          modelo: 'NP300 Doble Cabina Estacas',
          tipoVehiculo: 'pickup',
          placas: 'ABC-123-45',
          vin: '3N6DD23T5MK000001',
          costoAdquisicion: 48500000,
        );
    vehiculoId = vehiculo.id;

    final registrarMantenimiento = container.read(registrarMantenimientoVehiculoAutorizadoProvider);
    mantenimientoConTarjeta = (await registrarMantenimiento(
      vehiculoId: vehiculoId,
      fecha: DateTime(2026, 4, 12),
      tipo: TipoMantenimientoVehiculo.servicioGeneral.name,
      descripcion: 'Afinación mayor, cambio de balatas delanteras y alineación completa',
      tallerProveedor: 'Servicio Automotriz Atlacomulco S.A. de C.V.',
      costo: 1875050,
      origen: OrigenFinancieroTarjeta(konfio.deuda.id),
    ) as RegistrarMantenimientoVehiculoExitoso)
        .registro;

    final aAnular = (await registrarMantenimiento(
      vehiculoId: vehiculoId,
      fecha: DateTime(2026, 4, 20),
      tipo: TipoMantenimientoVehiculo.golpe.name,
      descripcion: 'Golpe en salpicadera trasera derecha durante maniobra en patio',
      costo: 940000,
      origen: OrigenFinancieroTarjeta(konfio.deuda.id),
    ) as RegistrarMantenimientoVehiculoExitoso)
        .registro;
    await container.read(cancelarMantenimientoVehiculoAutorizadoProvider)(
      vehiculoMantenimientoId: aAnular.id,
      motivo: 'Se capturó en el vehículo equivocado: el golpe corresponde a la unidad VEH-000004',
    );
    mantenimientoAnulado = (await container.read(vehiculoMantenimientoRepositoryProvider).obtenerPorId(aAnular.id))!;

    poliza = ((await container.read(registrarDocumentoVehiculoAutorizadoProvider)(
      vehiculoId: vehiculoId,
      tipo: TipoDocumentoVehiculo.seguro.name,
      numeroFolio: 'POL-2026-AXA-0099887766',
      fechaEmision: DateTime(2026, 1, 15),
      fechaVencimiento: DateTime(2027, 1, 15),
    )) as RegistrarDocumentoVehiculoExitoso)
        .documento;
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

      testWidgets('Expediente del vehículo ($etiqueta, $tema): cero overflow', (tester) async {
        fijarTamano(tester, tamano);
        await tester.pumpWidget(envolver(oscuro: oscuro, child: VehiculoExpedienteScreen(vehiculoId: vehiculoId)));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        // El historial trae la fila anulada con su motivo largo y la
        // columna de origen: justo lo que esta etapa agregó a la tabla.
        expect(find.text('Anulado'), findsOneWidget);
      });

      testWidgets('Registrar mantenimiento ($etiqueta, $tema): cero overflow', (tester) async {
        await abrirDialogo(
          tester,
          tamano: tamano,
          oscuro: oscuro,
          abrir: (context, ref) => mostrarDialogoRegistrarMantenimientoVehiculo(context, ref, vehiculoId),
        );

        expect(tester.takeException(), isNull);
      });

      testWidgets('Corregir mantenimiento con TDC ($etiqueta, $tema): cero overflow', (tester) async {
        await abrirDialogo(
          tester,
          tamano: tamano,
          oscuro: oscuro,
          abrir: (context, ref) =>
              mostrarDialogoCorregirMantenimientoVehiculo(context, ref, mantenimientoConTarjeta),
        );

        expect(tester.takeException(), isNull);
        // El selector de origen viene precargado: el costo ya existe.
        expect(find.byType(RisegOrigenFinancieroSelect), findsOneWidget);
      });

      testWidgets('Anular mantenimiento ($etiqueta, $tema): cero overflow', (tester) async {
        await abrirDialogo(
          tester,
          tamano: tamano,
          oscuro: oscuro,
          abrir: (context, ref) =>
              mostrarDialogoAnularMantenimientoVehiculo(context, ref, mantenimientoConTarjeta),
        );

        expect(tester.takeException(), isNull);
      });

      testWidgets('Corregir documento ($etiqueta, $tema): cero overflow', (tester) async {
        await abrirDialogo(
          tester,
          tamano: tamano,
          oscuro: oscuro,
          abrir: (context, ref) => mostrarDialogoCorregirDocumentoVehiculo(context, ref, poliza),
        );

        expect(tester.takeException(), isNull);
      });

      testWidgets('Corregir vehículo, con motivo obligatorio ($etiqueta, $tema): cero overflow', (tester) async {
        await abrirDialogo(
          tester,
          tamano: tamano,
          oscuro: oscuro,
          abrir: (context, ref) async {
            final vehiculo = await ref.read(vehiculoRepositoryProvider).obtenerPorId(vehiculoId);
            if (!context.mounted) return;
            await mostrarDialogoGestionarVehiculo(context, ref, vehiculo: vehiculo);
          },
        );

        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('vehiculo_campo_motivo')), findsOneWidget);
      });
    }
  }

  testWidgets('el selector de origen del mantenimiento ofrece cuentas Y tarjetas', (tester) async {
    await abrirDialogo(
      tester,
      tamano: const Size(1366, 900),
      oscuro: false,
      abrir: (context, ref) => mostrarDialogoCorregirMantenimientoVehiculo(context, ref, mantenimientoConTarjeta),
    );

    final select = tester.widget<RisegSelect<ClaveOrigenFinanciero?>>(
      find.descendant(
        of: find.byType(RisegOrigenFinancieroSelect),
        matching: find.byType(RisegSelect<ClaveOrigenFinanciero?>),
      ),
    );
    final etiquetas = select.items.map((i) => i.label).toList();

    expect(etiquetas, contains('BBVA Empresarial'));
    expect(etiquetas.any((e) => e.contains('TDC Konfío Empresarial')), isTrue);
    expect(
      select.value,
      startsWith('tarjeta:'),
      reason: 'la corrección precarga el origen VIGENTE — nunca obliga a re-adivinarlo',
    );
  });

  testWidgets('sin vehiculos.cancelar, el menú ofrece Corregir pero NO Anular', (tester) async {
    // La compuerta real vive en el provider autorizado (ver
    // `vehiculo_cancelar_permiso_test.dart`); esto fija que la UI no
    // ofrezca un botón que de todos modos sería rechazado.
    container.dispose();
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionOperarSinCancelar.new),
        attachmentStorageProvider.overrideWithValue(AttachmentStorage(tempDir.path)),
      ],
    );

    fijarTamano(tester, const Size(1366, 900));
    await tester.pumpWidget(envolver(oscuro: false, child: VehiculoExpedienteScreen(vehiculoId: vehiculoId)));
    await tester.pumpAndSettle();

    final menu = find.byKey(Key('vehiculo_mantenimiento_acciones_${mantenimientoConTarjeta.id}'));
    await tester.ensureVisible(menu);
    await tester.pumpAndSettle();
    await tester.tap(menu);
    await tester.pumpAndSettle();

    expect(
      find.byKey(Key('vehiculo_mantenimiento_corregir_${mantenimientoConTarjeta.id}')),
      findsOneWidget,
      reason: 'corregir sigue siendo parte de vehiculos.operar',
    );
    expect(
      find.byKey(Key('vehiculo_mantenimiento_anular_${mantenimientoConTarjeta.id}')),
      findsNothing,
      reason: 'anular revierte dinero real: exige vehiculos.cancelar',
    );
  });

  testWidgets('el registro anulado muestra su motivo, y ya no ofrece Corregir/Anular', (tester) async {
    fijarTamano(tester, const Size(1366, 900));
    await tester.pumpWidget(envolver(oscuro: false, child: VehiculoExpedienteScreen(vehiculoId: vehiculoId)));
    await tester.pumpAndSettle();

    expect(
      find.byKey(Key('vehiculo_mantenimiento_acciones_${mantenimientoAnulado.id}')),
      findsNothing,
      reason: 'un registro anulado no se corrige ni se vuelve a anular: se registra uno nuevo',
    );
    expect(find.textContaining('el golpe corresponde a la unidad VEH-000004'), findsOneWidget,
        reason: 'en su lugar se ve POR QUÉ se anuló');

    // El vigente sí ofrece ambas — así la ausencia anterior no es vacía.
    final menuVigente = find.byKey(Key('vehiculo_mantenimiento_acciones_${mantenimientoConTarjeta.id}'));
    expect(menuVigente, findsOneWidget);
    // El expediente es largo: la tabla de mantenimiento queda fuera del
    // viewport y `tap` no golpearía nada (Flutter lo avisa, no falla).
    await tester.ensureVisible(menuVigente);
    await tester.pumpAndSettle();
    await tester.tap(menuVigente);
    await tester.pumpAndSettle();
    expect(find.byKey(Key('vehiculo_mantenimiento_corregir_${mantenimientoConTarjeta.id}')), findsOneWidget);
    expect(find.byKey(Key('vehiculo_mantenimiento_anular_${mantenimientoConTarjeta.id}')), findsOneWidget);
  });
}
