// §10 — responsive de lo que esta pasada agregó: la sección fiscal del
// alta (que la hace bastante más alta) y el diálogo de anulación, que
// enumera listas de longitud variable.
//
// Se assert `tester.takeException() == null`: un overflow de Flutter se
// reporta como excepción del framework, así que esto mide lo que se
// busca y no una promesa visual.

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
    show TipoDocumentoCobro;
import 'package:riseg_one/features/servicios_eventuales/data/tables/servicio_eventual_table.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/totales_venta_eventual.dart';
import 'package:riseg_one/features/servicios_eventuales/presentation/widgets/servicio_eventual_anulacion_dialog.dart';
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
        permisos: {},
      );
}

const _anchos = [1536.0, 1366.0, 1024.0, 700.0, 500.0];

/// Una venta con todo lo que la anulación puede tener que enumerar:
/// dos cobros, una cobertura pagada y un costo pendiente, y textos
/// largos donde los hay.
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
  final cliente = await db.into(db.cliente).insertReturning(
        ClienteCompanion.insert(
          codigo: 'CLI-000001',
          nombreComercial: 'Promotora Metropolitana de Espectáculos y Eventos Masivos del Norte',
        ),
      );
  await db.into(db.entidadFiscal).insert(
        EntidadFiscalCompanion.insert(
          codigo: 'EF-000001',
          clienteId: cliente.id,
          razonSocial: 'Promotora Metropolitana de Espectáculos y Eventos Masivos del Norte, S.A. de C.V.',
          rfc: 'PME010101AB1',
        ),
      );

  final eventual = await db.into(db.servicioEventual).insertReturning(
        ServicioEventualCompanion.insert(
          folio: 'EVT-000900',
          nombre: 'Operativo especial de seguridad para el festival metropolitano de fin de año',
          fechaHoraInicio: DateTime(2026, 12, 31, 18),
          fechaHoraFin: DateTime(2027, 1, 1, 6),
          importeAcordado: 800000,
          tratamientoIva: Value(TratamientoIva.masIva.name),
          tipoSolicitante: TipoSolicitanteServicioEventual.eventual.name,
          solicitanteNombre: const Value('Juan Carlos de la Cruz Villanueva Hernández'),
          solicitanteRazonSocial:
              const Value('Administradora de Bosques Residenciales del Poniente, S.A. de C.V.'),
          solicitanteRfc: const Value('ABR010101AA1'),
          solicitanteCodigoPostalFiscal: const Value('06700'),
          requiereFactura: const Value(true),
        ),
      );

  final cuenta = await db.into(db.cuentaPorCobrar).insertReturning(
        CuentaPorCobrarCompanion.insert(
          servicioEventualId: Value(eventual.id),
          tipoDocumento: TipoDocumentoCobro.cfdi.name,
          metodo: 'pue',
          fechaEmisionReal: DateTime(2026, 12, 31),
          importeEmitido: 928000,
          saldoOriginal: 928000,
          saldoPendiente: 128000,
          estatus: const Value('parcial'),
        ),
      );
  final pago = await db.into(db.pago).insertReturning(
        PagoCompanion.insert(
          folioPago: 'PAG-000001',
          servicioEventualId: Value(eventual.id),
          montoTotal: 800000,
          montoAplicado: const Value(800000),
          fechaPago: DateTime(2026, 12, 31),
          formaPago: FormaPago.transferencia.name,
        ),
      );
  await db.into(db.aplicacionPago).insert(
        AplicacionPagoCompanion.insert(
          pagoId: pago.id,
          cuentaPorCobrarId: cuenta.id,
          monto: 800000,
          saldoAntes: 928000,
          saldoDespues: 128000,
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
          importeAcordado: 150000,
        ),
      );
  await db.into(db.servicioEventualCosto).insert(
        ServicioEventualCostoCompanion.insert(
          servicioEventualId: eventual.id,
          concepto: 'Renta de radios de comunicación y traslado del personal de apoyo',
          monto: 90000,
          fecha: DateTime(2026, 12, 31),
        ),
      );
  return eventual.id;
}

Future<void> _montar(WidgetTester tester, double ancho, bool oscuro, Widget hijo) async {
  tester.view.physicalSize = Size(ancho, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  final id = await _sembrar(db);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionMaestro.new),
        _eventualIdProvider.overrideWithValue(id),
      ],
      child: MaterialApp(
        theme: oscuro ? AppTheme.dark() : AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: hijo),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final _eventualIdProvider = Provider<String>((_) => throw UnimplementedError());

class _AbridorDeAlta extends ConsumerWidget {
  const _AbridorDeAlta();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: ElevatedButton(
        key: const Key('abrir'),
        onPressed: () => mostrarDialogoServicioEventual(context, ref),
        child: const Text('Nuevo'),
      ),
    );
  }
}

class _AbridorDeAnulacion extends ConsumerWidget {
  const _AbridorDeAnulacion();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: ElevatedButton(
        key: const Key('abrir'),
        onPressed: () => mostrarDialogoAnularServicioEventual(
          context,
          ref,
          servicioEventualId: ref.read(_eventualIdProvider),
        ),
        child: const Text('Cancelar evento'),
      ),
    );
  }
}

void main() {
  for (final ancho in _anchos) {
    for (final oscuro in [false, true]) {
      final tema = oscuro ? 'oscuro' : 'claro';

      testWidgets('alta con sección fiscal a ${ancho.toInt()}px, tema $tema: sin overflow',
          (tester) async {
        await _montar(tester, ancho, oscuro, const _AbridorDeAlta());
        await tester.tap(find.byKey(const Key('abrir')));
        await tester.pumpAndSettle();

        // Solicitante externo + factura: es cuando aparecen razón
        // social, RFC y CP, el formulario más alto del módulo.
        final tipo = find.byKey(const Key('servicio_eventual_campo_tipo_solicitante'));
        await tester.ensureVisible(tipo);
        await tester.pumpAndSettle();
        await tester.tap(tipo);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Solicitante externo').last);
        await tester.pumpAndSettle();

        final casilla = find.byKey(const Key('servicio_eventual_campo_requiere_factura'));
        await tester.ensureVisible(casilla);
        await tester.pumpAndSettle();
        await tester.tap(casilla);
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('servicio_eventual_campo_cp_fiscal')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('anulación a ${ancho.toInt()}px, tema $tema: sin overflow', (tester) async {
        await _montar(tester, ancho, oscuro, const _AbridorDeAnulacion());
        await tester.tap(find.byKey(const Key('abrir')));
        await tester.pumpAndSettle();

        // Las dos listas están: lo que se revierte y lo que permanece.
        expect(find.byKey(const Key('servicio_eventual_anular_revierte')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('la anulación enumera el pago, la cuenta y lo que permanece', (tester) async {
    await _montar(tester, 1366, false, const _AbridorDeAnulacion());
    await tester.tap(find.byKey(const Key('abrir')));
    await tester.pumpAndSettle();

    expect(find.textContaining('PAG-000001'), findsOneWidget);
    expect(find.textContaining(r'$8,000.00'), findsOneWidget, reason: 'lo que regresa a la cuenta');
    expect(find.textContaining('Cuenta por cobrar'), findsOneWidget);
    // Nada pagado todavía del lado del gasto: no se promete devolver
    // algo que no salió.
    expect(find.text('Permanece'), findsNothing);
  });
}
