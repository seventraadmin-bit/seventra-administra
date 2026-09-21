// §3, §4, §5 y §6 — lo que la prueba manual vio en pantalla.
//
//   §3 "Registrar el cobro ahora" precargaba $8,000 cuando el cliente
//      debía $9,280: inducía a registrar sólo el subtotal.
//   §4 dos botones "Guardar" en el mismo diálogo, y el de arriba
//      cerraba sin guardar.
//   §5 el historial mostraba `costoAgregado`, un identificador técnico.
//   §6 el KPI decía "Venta acordada" sobre una cifra que es el total.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/servicios_eventuales/data/tables/servicio_eventual_table.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/totales_venta_eventual.dart';
import 'package:riseg_one/features/servicios_eventuales/presentation/servicio_eventual_expediente_screen.dart';
import 'package:riseg_one/features/servicios_eventuales/presentation/servicios_eventuales_list_screen.dart';
import 'package:riseg_one/features/servicios_eventuales/presentation/widgets/servicio_eventual_dialogs.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

class _SesionMaestro extends SesionController {
  @override
  SesionUsuario? build() => const SesionUsuario(
        usuarioId: 'maestro',
        nombre: 'Maestro de prueba',
        nombreUsuario: 'maestro',
        esMaestro: true,
        // Con permisos reales: `autorizarUseCase` los exige, y una
        // sesión sin ellos hace que el alta falle con "No tienes
        // permiso" — un falso negativo disfrazado de bug de UI.
        permisos: {
          'serviciosEventuales.crear',
          'serviciosEventuales.corregir',
          'serviciosEventuales.cancelar',
          'serviciosEventuales.cobrar',
          'serviciosEventuales.facturar',
        },
      );
}

/// El caso exacto de la prueba manual: 8,000 más IVA = 9,280.
Future<String> _sembrarVentaConIva(AppDatabase db) async {
  await db.into(db.usuario).insert(
        UsuarioCompanion.insert(
          id: const Value('maestro'),
          nombre: 'Maestro de prueba',
          nombreUsuario: 'maestro',
          passwordHash: r'pbkdf2$1$c2FsdA==$aGFzaA==',
          esMaestro: const Value(true),
        ),
      );
  final eventual = await db.into(db.servicioEventual).insertReturning(
        ServicioEventualCompanion.insert(
          // Fuera del rango que la secuencia va a emitir: el alta de
          // esta misma prueba pide el siguiente folio y chocaría.
          folio: 'EVT-000900',
          nombre: 'Posada',
          fechaHoraInicio: DateTime(2026, 5, 1, 18),
          fechaHoraFin: DateTime(2026, 5, 2, 2),
          importeAcordado: 800000,
          tratamientoIva: Value(TratamientoIva.masIva.name),
          tipoSolicitante: TipoSolicitanteServicioEventual.eventual.name,
          solicitanteNombre: const Value('Juan del comité'),
        ),
      );
  // Un hecho de cada familia, para leer el historial.
  for (final tipo in [
    TipoEventoServicioEventual.creado,
    TipoEventoServicioEventual.cuentaPorCobrarCreada,
    TipoEventoServicioEventual.costoAgregado,
  ]) {
    await db.into(db.servicioEventualEvento).insert(
          ServicioEventualEventoCompanion.insert(
            servicioEventualId: eventual.id,
            fechaHora: DateTime(2026, 5, 1, 9),
            tipoEvento: tipo.name,
          ),
        );
  }
  return eventual.id;
}

Future<AppDatabase> _montar(
  WidgetTester tester,
  Widget Function(String) pantalla, {
  double ancho = 1366,
  Future<void> Function(AppDatabase db, String eventualId)? sembrarAdemas,
}) async {
  tester.view.physicalSize = Size(ancho, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  final id = await _sembrarVentaConIva(db);
  await sembrarAdemas?.call(db, id);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionMaestro.new),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: pantalla(id)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return db;
}

/// Un botón que abre el alta — el diálogo necesita un `context` bajo un
/// `Navigator`.
class _AbridorDeAlta extends ConsumerWidget {
  const _AbridorDeAlta();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: ElevatedButton(
        key: const Key('abrir_alta'),
        onPressed: () => mostrarDialogoServicioEventual(context, ref),
        child: const Text('Nuevo'),
      ),
    );
  }
}

/// El contenido del diálogo va dentro de un scroll: sin esto, un
/// `tap` sobre un campo de la parte baja no golpea nada.
Future<void> _tocar(WidgetTester tester, Key clave) async {
  await tester.ensureVisible(find.byKey(clave));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(clave));
  await tester.pumpAndSettle();
}

Future<void> _escribir(WidgetTester tester, Key clave, String texto) async {
  await tester.ensureVisible(find.byKey(clave));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(clave), texto);
  await tester.pumpAndSettle();
}

void main() {
  group('§3 — el cobro inmediato precarga el TOTAL, no el subtotal', () {
    Future<void> abrirAltaConIva(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('abrir_alta')));
      await tester.pumpAndSettle();
      await _escribir(tester, const Key('servicio_eventual_campo_importe'), '8000');
      await _tocar(tester, const Key('servicio_eventual_campo_tratamiento_iva'));
      await tester.tap(find.text('Más IVA').last);
      await tester.pumpAndSettle();
    }

    testWidgets('al marcar "cobrar ahora" el monto viene en 9,280', (tester) async {
      await _montar(tester, (_) => const _AbridorDeAlta());
      await abrirAltaConIva(tester);

      await _tocar(tester, const Key('servicio_eventual_campo_cobrar_ahora'));

      final monto = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('servicio_eventual_campo_monto_cobro')),
          matching: find.byType(TextField),
        ),
      );
      expect(monto.controller!.text, '9280.00',
          reason: 'precargar 8,000 inducía a registrar sólo el subtotal');
      expect(
        totalVentaEventual(importeAcordado: 800000, tratamientoIva: TratamientoIva.masIva),
        928000,
      );
    });

    testWidgets('el desglose completo se ve ANTES de guardar', (tester) async {
      await _montar(tester, (_) => const _AbridorDeAlta());
      await abrirAltaConIva(tester);

      final desglose = tester
          .widget<Text>(find.byKey(const Key('servicio_eventual_desglose_venta')))
          .data!;
      expect(desglose, contains(r'$8,000.00'), reason: 'subtotal');
      expect(desglose, contains(r'$1,280.00'), reason: 'IVA');
      expect(desglose, contains(r'$9,280.00'), reason: 'total a cobrar');
    });

    testWidgets('cambiar el tratamiento DESPUÉS arrastra el monto del cobro', (tester) async {
      await _montar(tester, (_) => const _AbridorDeAlta());
      await tester.tap(find.byKey(const Key('abrir_alta')));
      await tester.pumpAndSettle();
      await _escribir(tester, const Key('servicio_eventual_campo_importe'), '8000');
      // Primero se marca el cobro con "No aplica": el monto es 8,000.
      await _tocar(tester, const Key('servicio_eventual_campo_cobrar_ahora'));

      Text totalVisible() =>
          tester.widget<Text>(find.byKey(const Key('servicio_eventual_cobro_total')));
      expect(totalVisible().data, contains(r'$8,000.00'));

      await _tocar(tester, const Key('servicio_eventual_campo_tratamiento_iva'));
      await tester.tap(find.text('Más IVA').last);
      await tester.pumpAndSettle();

      final monto = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('servicio_eventual_campo_monto_cobro')),
          matching: find.byType(TextField),
        ),
      );
      expect(monto.controller!.text, '9280.00');
      expect(totalVisible().data, contains(r'$9,280.00'));
    });

    testWidgets('un cobro parcial escrito a mano NO se pisa', (tester) async {
      await _montar(tester, (_) => const _AbridorDeAlta());
      await abrirAltaConIva(tester);
      await _tocar(tester, const Key('servicio_eventual_campo_cobrar_ahora'));

      await _escribir(tester, const Key('servicio_eventual_campo_monto_cobro'), '5000');
      // El usuario decidió cobrar parcial; cambiar el importe de la
      // venta no puede deshacer esa decisión.
      await _escribir(tester, const Key('servicio_eventual_campo_importe'), '9000');

      final monto = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('servicio_eventual_campo_monto_cobro')),
          matching: find.byType(TextField),
        ),
      );
      expect(monto.controller!.text, '5000');
    });
  });

  group('§4 — un solo footer por diálogo', () {
    testWidgets('el alta tiene Cancelar y UNA acción primaria, con nombre propio', (tester) async {
      await _montar(tester, (_) => const _AbridorDeAlta());
      await tester.tap(find.byKey(const Key('abrir_alta')));
      await tester.pumpAndSettle();

      // El botón genérico que vivía dentro del formulario ya no existe.
      expect(find.byKey(const Key('servicio_eventual_boton_guardar')), findsNothing);
      expect(find.text('Guardar'), findsNothing, reason: 'la acción se llama por su nombre');
      expect(find.widgetWithText(RisegButton, 'Registrar eventual'), findsOneWidget);
      expect(find.widgetWithText(RisegButton, 'Cancelar'), findsOneWidget);
    });

    testWidgets('la acción primaria guarda de verdad (antes cerraba en vacío)', (tester) async {
      final db = await _montar(tester, (_) => const _AbridorDeAlta());
      await tester.tap(find.byKey(const Key('abrir_alta')));
      await tester.pumpAndSettle();

      await _escribir(tester, const Key('servicio_eventual_campo_nombre'), 'Evento nuevo');
      await _escribir(tester, const Key('servicio_eventual_campo_importe'), '1000');
      // Solicitante externo, para no depender de un Cliente sembrado.
      await _tocar(tester, const Key('servicio_eventual_campo_tipo_solicitante'));
      await tester.tap(find.text('Solicitante externo').last);
      await tester.pumpAndSettle();
      await _escribir(
        tester,
        const Key('servicio_eventual_campo_solicitante'),
        'Promotora Norte',
      );

      await tester.tap(find.widgetWithText(RisegButton, 'Registrar eventual'));
      await tester.pumpAndSettle();

      final eventuales = await db.select(db.servicioEventual).get();
      expect(eventuales.where((e) => e.nombre == 'Evento nuevo'), hasLength(1),
          reason: 'el botón del marco no tenía onConfirm: cerraba descartando la captura');
    });
  });

  group('§5 — el historial se lee en español, no en enum', () {
    testWidgets('los tipos de evento salen traducidos', (tester) async {
      await _montar(tester, (id) => ServicioEventualExpedienteScreen(servicioEventualId: id));

      expect(find.text('costoAgregado'), findsNothing);
      expect(find.text('cuentaPorCobrarCreada'), findsNothing);
      expect(find.text('creado'), findsNothing);

      expect(find.text('Costo agregado'), findsOneWidget);
      expect(find.text('Cuenta por cobrar creada'), findsOneWidget);
      expect(find.text('Servicio eventual creado'), findsOneWidget);
    });
  });

  group('Cobranza vigente en el expediente', () {
    testWidgets('una venta anulada muestra Cobrado en cero, no el total', (tester) async {
      await _montar(
        tester,
        (id) => ServicioEventualExpedienteScreen(servicioEventualId: id),
        // La cobranza tal como la deja anular la venta: Cuenta cancelada
        // con saldo 0 —la resta vieja daría el total— y Pago y
        // Aplicación cancelados.
        sembrarAdemas: (db, eventualId) async {
          final cuenta = await db.into(db.cuentaPorCobrar).insertReturning(
                CuentaPorCobrarCompanion.insert(
                  servicioEventualId: Value(eventualId),
                  tipoDocumento: 'reciboDePago',
                  metodo: 'noAplica',
                  fechaEmisionReal: DateTime(2026, 5, 1),
                  importeEmitido: 928000,
                  saldoOriginal: 928000,
                  saldoPendiente: 0,
                  estatus: const Value('cancelada'),
                ),
              );
          final pago = await db.into(db.pago).insertReturning(
                PagoCompanion.insert(
                  folioPago: 'PAG-000900',
                  servicioEventualId: Value(eventualId),
                  montoTotal: 800000,
                  fechaPago: DateTime(2026, 5, 1),
                  formaPago: 'transferencia',
                  estatus: const Value('cancelado'),
                ),
              );
          await db.into(db.aplicacionPago).insert(
                AplicacionPagoCompanion.insert(
                  pagoId: pago.id,
                  cuentaPorCobrarId: cuenta.id,
                  monto: 800000,
                  saldoAntes: 928000,
                  saldoDespues: 128000,
                  estatus: const Value('cancelada'),
                ),
              );
        },
      );

      final cobrado = find.ancestor(
        of: find.text('Cobrado'),
        matching: find.byType(RisegStatCard),
      );
      expect(cobrado, findsOneWidget);
      expect(
        find.descendant(of: cobrado, matching: find.text(r'$0.00')),
        findsOneWidget,
        reason: 'la resta de saldos daba 9,280 justo cuando no se cobró nada',
      );
    });
  });

  group('§6 — una sola definición de venta', () {
    testWidgets('el listado muestra el TOTAL, no el importe capturado', (tester) async {
      await _montar(tester, (_) => const ServiciosEventualesListScreen());

      expect(find.text(r'$9,280.00'), findsWidgets, reason: 'columna y KPI usan el total');
      expect(find.text(r'$8,000.00'), findsNothing,
          reason: 'el importe capturado no es lo que el cliente debe');
      expect(find.text('Total de venta'), findsWidgets);
      expect(find.text('Venta acordada'), findsNothing);
    });

    testWidgets('el expediente desglosa y coincide con el listado', (tester) async {
      await _montar(tester, (id) => ServicioEventualExpedienteScreen(servicioEventualId: id));

      expect(find.text('Total de venta'), findsOneWidget);
      expect(find.text(r'$9,280.00'), findsWidgets);
    });
  });
}
