// §27 — el listado y el expediente de Eventuales a cinco anchos y en
// los dos temas, con datos que fuerzan el caso feo: nombres largos,
// resultado negativo, turno que cruza la medianoche y —desde la
// schemaVersion 88— cobranza real con factura y pagos aplicados.
//
// `tester.takeException() == null` es lo que se asserta: un overflow de
// Flutter se reporta como excepción del framework, así que esto detecta
// exactamente lo que se busca y no una promesa visual.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart'
    show MetodoPagoCobro, TipoDocumentoCobro;
import 'package:riseg_one/features/servicios_eventuales/data/tables/servicio_eventual_table.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/totales_venta_eventual.dart';
import 'package:riseg_one/features/servicios_eventuales/presentation/widgets/servicio_eventual_dialogs.dart';
import 'package:riseg_one/features/servicios_eventuales/presentation/servicio_eventual_expediente_screen.dart';
import 'package:riseg_one/features/servicios_eventuales/presentation/servicios_eventuales_list_screen.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

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

const _anchos = [1536.0, 1366.0, 1024.0, 700.0, 500.0];

/// Un eventual con todo lo que puede desbordar: solicitante de nombre
/// larguísimo, costo por encima de la venta (resultado negativo) y una
/// cobertura que cruza la medianoche.
Future<String> _sembrar(AppDatabase db) async {
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
          folio: 'EVT-000001',
          nombre: 'Operativo especial de seguridad para el festival metropolitano de fin de año',
          fechaHoraInicio: DateTime(2026, 12, 31, 18),
          fechaHoraFin: DateTime(2027, 1, 1, 6),
          importeAcordado: 1500000,
          tipoSolicitante: TipoSolicitanteServicioEventual.eventual.name,
          solicitanteNombre: const Value('Promotora Metropolitana de Espectáculos y Eventos Masivos del Norte, S.A. de C.V.'),
          ubicacion: const Value('Explanada del recinto ferial, avenida de los Insurgentes sin número'),
          notas: const Value('El cliente pidió refuerzo en los tres accesos principales durante toda la noche.'),
          requiereFactura: const Value(true),
          tratamientoIva: Value(TratamientoIva.masIva.name),
        ),
      );

  final participante = await db.into(db.servicioEventualParticipante).insertReturning(
        ServicioEventualParticipanteCompanion.insert(
          servicioEventualId: eventual.id,
          nombreExterno: const Value('Juan Carlos de la Cruz Villanueva Hernández'),
        ),
      );

  await db.into(db.servicioEventualCobertura).insert(
        ServicioEventualCoberturaCompanion.insert(
          servicioEventualId: eventual.id,
          participanteId: participante.id,
          fecha: DateTime(2026, 12, 31),
          horaInicioMinutos: 20 * 60,
          horaFinMinutos: 6 * 60,
          importeAcordado: 1200000,
        ),
      );
  await db.into(db.servicioEventualCosto).insert(
        ServicioEventualCostoCompanion.insert(
          servicioEventualId: eventual.id,
          concepto: 'Renta de radios de comunicación y traslado del personal de apoyo',
          monto: 900000,
          fecha: DateTime(2026, 12, 31),
        ),
      );

  // schemaVersion 88 — su cobranza: cuenta parcialmente cobrada, con
  // factura PPD y un documento fiscal cancelado más su sustituto, que
  // es la pestaña con más contenido del expediente.
  final cuenta = await db.into(db.cuentaPorCobrar).insertReturning(
        CuentaPorCobrarCompanion.insert(
          servicioEventualId: Value(eventual.id),
          tipoDocumento: TipoDocumentoCobro.cfdi.name,
          metodo: MetodoPagoCobro.ppd.name,
          requiereComplemento: const Value(true),
          folioDocumento: const Value('A-000123456789'),
          fechaEmisionReal: DateTime(2026, 12, 31),
          importeEmitido: 1500000,
          saldoOriginal: 1500000,
          saldoPendiente: 900000,
          estatus: const Value('parcial'),
          fechaVencimiento: Value(DateTime(2027, 1, 31)),
        ),
      );
  final pago = await db.into(db.pago).insertReturning(
        PagoCompanion.insert(
          folioPago: 'PAG-000001',
          servicioEventualId: Value(eventual.id),
          montoTotal: 600000,
          montoAplicado: const Value(600000),
          fechaPago: DateTime(2027, 1, 5),
          formaPago: FormaPago.transferencia.name,
        ),
      );
  await db.into(db.aplicacionPago).insert(
        AplicacionPagoCompanion.insert(
          pagoId: pago.id,
          cuentaPorCobrarId: cuenta.id,
          monto: 600000,
          saldoAntes: 1500000,
          saldoDespues: 900000,
        ),
      );
  for (final (folio, estatus) in [('A-000123456788', 'cancelado'), ('A-000123456789', 'registrado')]) {
    await db.into(db.servicioEventualDocumentoFiscal).insert(
          ServicioEventualDocumentoFiscalCompanion.insert(
            servicioEventualId: eventual.id,
            folio: folio,
            uuid: const Value('123e4567-e89b-12d3-a456-426614174000'),
            fechaEmision: DateTime(2026, 12, 31),
            importe: 1500000,
            metodo: MetodoPagoCobro.ppd.name,
            requiereComplemento: const Value(true),
            snapshotRazonSocial:
                'Promotora Metropolitana de Espectáculos y Eventos Masivos del Norte, S.A. de C.V.',
            snapshotRfc: 'PME123456AB1',
            estatus: Value(estatus),
          ),
        );
  }

  return eventual.id;
}

Future<AppDatabase> _montar(WidgetTester tester, double ancho, bool oscuro, Widget Function(String) pantalla) async {
  tester.view.physicalSize = Size(ancho, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  final eventualId = await _sembrar(db);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionMaestro.new),
      ],
      child: MaterialApp(
        theme: oscuro ? AppTheme.dark() : AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: pantalla(eventualId)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return db;
}

void main() {
  for (final ancho in _anchos) {
    for (final oscuro in [false, true]) {
      final tema = oscuro ? 'oscuro' : 'claro';

      testWidgets('listado de Eventuales a ${ancho.toInt()}px, tema $tema: sin overflow', (tester) async {
        await _montar(tester, ancho, oscuro, (_) => const ServiciosEventualesListScreen());
        expect(tester.takeException(), isNull);
      });

      testWidgets('expediente de un Eventual a ${ancho.toInt()}px, tema $tema: sin overflow', (tester) async {
        await _montar(
          tester,
          ancho,
          oscuro,
          (id) => ServicioEventualExpedienteScreen(servicioEventualId: id),
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('las cuatro pestañas del expediente abren sin excepción', (tester) async {
    await _montar(
      tester,
      1366,
      false,
      (id) => ServicioEventualExpedienteScreen(servicioEventualId: id),
    );

    // Cada pestaña se comprueba por su CONTENIDO, no sólo por la
    // ausencia de excepción: un tap que no cambiara nada dejaría la
    // prueba pasando sin haber probado nada.
    await tester.tap(find.byType(Tab).at(1));
    await tester.pumpAndSettle();
    expect(find.text('Juan Carlos de la Cruz Villanueva Hernández'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byType(Tab).at(2));
    await tester.pumpAndSettle();
    expect(find.text('Renta de radios de comunicación y traslado del personal de apoyo'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Cobro y documento: la cobranza real del evento.
    await tester.tap(find.byType(Tab).at(3));
    await tester.pumpAndSettle();
    expect(find.text('A-000123456789'), findsWidgets);
    expect(find.text('PAG-000001'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // El Historial dejó de ser una quinta pestaña: vive dentro del
    // Resumen, que es donde se lee junto al resto del contexto.
    await tester.tap(find.byType(Tab).at(0));
    await tester.pumpAndSettle();
    expect(find.text('Historial'), findsOneWidget);
    expect(find.text('PAG-000001'), findsNothing);
    expect(tester.takeException(), isNull);
  });
for (final ancho in _anchos) {
    for (final oscuro in [false, true]) {
      final tema = oscuro ? 'oscuro' : 'claro';

      testWidgets('alta de Eventual a ${ancho.toInt()}px, tema $tema: sin overflow', (tester) async {
        await _montar(tester, ancho, oscuro, (_) => const _AbridorDeAlta());
        await tester.tap(find.byKey(const Key('abrir_alta')));
        await tester.pumpAndSettle();

        // El formulario completo, con su desglose, a este ancho.
        await tester.enterText(find.byKey(const Key('servicio_eventual_campo_importe')), '10000');
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('servicio_eventual_campo_tratamiento_iva')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('el desglose de IVA se ve antes de guardar', (tester) async {
    await _montar(tester, 1366, false, (_) => const _AbridorDeAlta());
    await tester.tap(find.byKey(const Key('abrir_alta')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('servicio_eventual_campo_importe')), '10000');
    await tester.pumpAndSettle();

    // Con "No aplica" no hay impuesto que mostrar.
    expect(find.byKey(const Key('servicio_eventual_desglose_venta')), findsOneWidget);
    final sinIva = tester.widget<Text>(find.byKey(const Key('servicio_eventual_desglose_venta'))).data!;
    expect(sinIva, contains('\$10,000.00'));
    expect(sinIva, isNot(contains('IVA')));

    // Al cambiar a "Más IVA" el usuario ve el total que se cobrará.
    await tester.tap(find.byKey(const Key('servicio_eventual_campo_tratamiento_iva')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Más IVA').last);
    await tester.pumpAndSettle();

    final conIva = tester.widget<Text>(find.byKey(const Key('servicio_eventual_desglose_venta'))).data!;
    expect(conIva, contains('\$1,600.00'), reason: 'el IVA derivado');
    expect(conIva, contains('\$11,600.00'), reason: 'el total que se le cobrará al cliente');
    expect(tester.takeException(), isNull);
  });
}

/// Un botón que abre el alta — el diálogo necesita un `context` bajo un
/// `Navigator`, y montarlo directo no lo tendría.
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
