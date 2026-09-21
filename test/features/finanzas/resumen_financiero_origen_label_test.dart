// Microcorrección: el `_origenLabel` del Resumen financiero nunca
// nombró a Telefonía ni a Vehículos, así que sus Egresos automáticos
// —bien clasificados y bien protegidos desde las schemaVersion 86 y
// 80— se mostraban como "Manual" en Movimientos recientes.
//
// Es un error de REPRESENTACIÓN y sólo eso: aquí no se toca
// clasificación, fórmula, color ni semántica financiera. La prueba
// monta la pantalla real con un Egreso automático de cada origen y lee
// la etiqueta que el usuario ve.

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
import 'package:riseg_one/features/organizacion/organizacion_providers.dart' show attachmentStorageProvider;
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/finanzas/presentation/resumen/resumen_financiero_screen.dart';
import 'package:riseg_one/features/servicios_eventuales/data/tables/servicio_eventual_table.dart';
import 'package:riseg_one/features/telefonia/data/tables/linea_telefonica_table.dart';
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

/// Fecha dentro del periodo por defecto del Resumen (mes en curso), que
/// es lo que la pantalla carga al abrirse.
final _hoy = DateTime.now();

void main() {
  late AppDatabase db;
  late Directory tempDir;
  late CuentaFinancieraData cuenta;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    tempDir = Directory.systemTemp.createTempSync('riseg_resumen_origen_label_test_');

    cuenta = await db.into(db.cuentaFinanciera).insertReturning(
          CuentaFinancieraCompanion.insert(
            codigo: 'CF-BBVA',
            nombre: 'BBVA',
            tipo: 'cuenta',
            saldoInicial: 100000000,
            fechaSaldoInicial: DateTime(2020),
          ),
        );
  });

  tearDown(() {
    db.close();
    tempDir.deleteSync(recursive: true);
  });

  /// Egreso pagado desde la cuenta — la única forma que el Resumen
  /// cuenta como salida de efectivo.
  Future<EgresoData> crearEgreso(String folio, int monto, String concepto) {
    return db.into(db.egreso).insertReturning(
          EgresoCompanion.insert(
            folioEgreso: folio,
            monto: monto,
            fecha: _hoy,
            formaPago: FormaPago.transferencia.name,
            concepto: concepto,
            cuentaFinancieraId: Value(cuenta.id),
          ),
        );
  }

  Future<void> sembrarTelefonia() async {
    final egreso = await crearEgreso('EGR-000001', 30000, 'Recarga de la línea de operaciones');
    final linea = await db.into(db.lineaTelefonica).insertReturning(
          LineaTelefonicaCompanion.insert(
            codigo: 'LIN-000001',
            numero: const Value('7221234567'),
            operador: OperadorTelefonico.telcel.name,
            modalidadSim: ModalidadSim.fisica.name,
          ),
        );
    await db.into(db.recargaLineaTelefonica).insert(
          RecargaLineaTelefonicaCompanion.insert(
            lineaTelefonicaId: linea.id,
            fecha: _hoy,
            importe: 30000,
            egresoId: Value(egreso.id),
          ),
        );
  }

  Future<void> sembrarVehiculo() async {
    final egreso = await crearEgreso('EGR-000002', 450000, 'Servicio mayor de la camioneta');
    final vehiculo = await db.into(db.vehiculo).insertReturning(
          VehiculoCompanion.insert(
            codigo: 'VEH-000001',
            marca: 'Nissan',
            modelo: 'NP300',
            tipoVehiculo: 'pickup',
          ),
        );
    await db.into(db.vehiculoMantenimiento).insert(
          VehiculoMantenimientoCompanion.insert(
            vehiculoId: vehiculo.id,
            fecha: _hoy,
            tipo: 'preventivo',
            descripcion: 'Servicio mayor',
            costo: const Value(450000),
            egresoId: Value(egreso.id),
          ),
        );
  }

  Future<void> sembrarServicioEventual() async {
    final egreso = await crearEgreso('EGR-000003', 250000, 'Cobertura del concierto');
    final eventual = await db.into(db.servicioEventual).insertReturning(
          ServicioEventualCompanion.insert(
            folio: 'EVT-000001',
            nombre: 'Concierto plaza',
            fechaHoraInicio: _hoy,
            fechaHoraFin: _hoy.add(const Duration(hours: 8)),
            importeAcordado: 5000000,
            tipoSolicitante: TipoSolicitanteServicioEventual.eventual.name,
            solicitanteNombre: const Value('Promotora Norte'),
          ),
        );
    final participante = await db.into(db.servicioEventualParticipante).insertReturning(
          ServicioEventualParticipanteCompanion.insert(
            servicioEventualId: eventual.id,
            nombreExterno: const Value('Refuerzo externo'),
          ),
        );
    await db.into(db.servicioEventualCobertura).insert(
          ServicioEventualCoberturaCompanion.insert(
            servicioEventualId: eventual.id,
            participanteId: participante.id,
            fecha: _hoy,
            horaInicioMinutos: 8 * 60,
            horaFinMinutos: 20 * 60,
            importeAcordado: 250000,
            estatus: Value(EstatusEjecucionServicioEventual.pagada.name),
            egresoId: Value(egreso.id),
          ),
        );
  }

  Future<void> montar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1536, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          sesionControllerProvider.overrideWith(_SesionMaestro.new),
          attachmentStorageProvider.overrideWithValue(AttachmentStorage(tempDir.path)),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: ResumenFinancieroScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('el Egreso automático de Telefonía se etiqueta Telefonía, nunca Manual', (tester) async {
    await sembrarTelefonia();
    await montar(tester);

    expect(find.text('Recarga de la línea de operaciones'), findsOneWidget);
    expect(find.text('Telefonía'), findsOneWidget);
    expect(find.text('Manual'), findsNothing);
  });

  testWidgets('el Egreso automático de Vehículos se etiqueta Vehículos, nunca Manual', (tester) async {
    await sembrarVehiculo();
    await montar(tester);

    expect(find.text('Servicio mayor de la camioneta'), findsOneWidget);
    expect(find.text('Vehículos'), findsOneWidget);
    expect(find.text('Manual'), findsNothing);
  });

  testWidgets('un Egreso manual de verdad sigue etiquetándose Manual', (tester) async {
    await crearEgreso('EGR-000009', 80000, 'Renta de oficina');
    await montar(tester);

    expect(find.text('Renta de oficina'), findsOneWidget);
    expect(find.text('Manual'), findsOneWidget);
  });

  testWidgets('el Egreso de un Servicio Eventual conserva su etiqueta', (tester) async {
    await sembrarServicioEventual();
    await montar(tester);

    expect(find.text('Cobertura del concierto'), findsOneWidget);
    expect(find.text('Servicio eventual'), findsOneWidget);
    expect(find.text('Manual'), findsNothing);
  });

  testWidgets('los cuatro orígenes juntos: cada uno con su nombre', (tester) async {
    await sembrarTelefonia();
    await sembrarVehiculo();
    await sembrarServicioEventual();
    await crearEgreso('EGR-000009', 80000, 'Renta de oficina');
    await montar(tester);

    expect(find.text('Telefonía'), findsOneWidget);
    expect(find.text('Vehículos'), findsOneWidget);
    expect(find.text('Servicio eventual'), findsOneWidget);
    // Exactamente uno: el único Egreso que de verdad es manual.
    expect(find.text('Manual'), findsOneWidget);
  });
}
