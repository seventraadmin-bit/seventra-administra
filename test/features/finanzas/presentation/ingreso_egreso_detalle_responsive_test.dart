// Etapa "Ingresos y Egresos: corrección, cancelación, origen automático
// y trazabilidad integral", Sección 19: barrido responsive de los
// diálogos modificados — `IngresoDetalleDialog`/`EgresoDetalleDialog`
// (folio/concepto largos, importe grande, motivo largo en historial,
// y — solo para Egreso — origen automático con "Ver origen") y
// `mostrarDialogoCorregirIngreso`/`mostrarDialogoCorregirEgreso` (nuevo
// campo de monto). Anchos: 1536/1366/1024/700/500, claro y oscuro. Cero
// RenderFlex overflow.

import 'package:riseg_one/features/finanzas/data/repositories/cuenta_por_cobrar_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/pago_repository_impl.dart';
import 'package:riseg_one/features/servicios_eventuales/data/repositories/servicio_eventual_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/asignacion_vehiculo_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/vehiculo_mantenimiento_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/vehiculo_repository_impl.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/compras/data/repositories/compra_repository_impl.dart';
import 'package:riseg_one/features/compras/domain/repositories/compra_repository.dart' show PartidaCompraInput;
import 'package:riseg_one/features/compras/domain/usecases/registrar_compra_usecase.dart';
import 'package:riseg_one/features/descuentos_personal/data/repositories/descuento_programado_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/ingreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/corregir_egreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/corregir_ingreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/obtener_origen_automatico_egreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_egreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_ingreso_manual_usecase.dart';
import 'package:riseg_one/features/finanzas/presentation/egresos/widgets/egreso_detalle_dialog.dart';
import 'package:riseg_one/features/finanzas/presentation/ingresos/widgets/ingreso_detalle_dialog.dart';
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/inventario_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/repositories/pago_nomina_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';
import 'package:riseg_one/features/tiempos_extra/data/repositories/tiempo_extra_repository_impl.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/repositories/asignacion_linea_telefonica_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/repositories/linea_telefonica_equipo_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/repositories/linea_telefonica_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/repositories/recarga_linea_telefonica_repository_impl.dart';

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

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late String ingresoManualId;
  late String egresoManualId;
  late String egresoAutomaticoId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(
            id: const Value('usuario-maestro'),
            nombre: 'Maestro de prueba',
            nombreUsuario: 'maestro',
            passwordHash: 'x',
            esMaestro: const Value(true),
          ),
        );

    final ingresoRepo = IngresoRepositoryImpl(db);
    final egresoRepo = EgresoRepositoryImpl(db);
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));

    final articuloRepo = ArticuloRepositoryImpl(db);
    final inventarioRepo = InventarioRepositoryImpl(db);
    final deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
    final compraRepo = CompraRepositoryImpl(db, inventarioRepo, articuloRepo, egresoRepo, deudaRepo);
    final asignacionServicioRepo = AsignacionServicioRepositoryImpl(db);
    final pagoNominaRepo = PagoNominaRepositoryImpl(db, egresoRepo, DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db)));
    final tiempoExtraRepo = TiempoExtraRepositoryImpl(
      db,
      egresoRepo,
      deudaRepo,
      CodigoSecuenciaService(db),
      EmpleadoRepositoryImpl(db, asignacionServicioRepo),
      ServicioRepositoryImpl(db, asignacionServicioRepo),
    );
    final obtenerOrigenAutomatico = ObtenerOrigenAutomaticoEgresoUseCase(
      compraRepo,
      pagoNominaRepo,
      tiempoExtraRepo,
      deudaRepo,
      DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db)),
      VehiculoMantenimientoRepositoryImpl(db),
      VehiculoRepositoryImpl(db, AsignacionVehiculoRepositoryImpl(db)),
      RecargaLineaTelefonicaRepositoryImpl(db, EgresoRepositoryImpl(db), DeudaRepositoryImpl(db, EgresoRepositoryImpl(db)), CodigoSecuenciaService(db)),
      LineaTelefonicaRepositoryImpl(db, AsignacionLineaTelefonicaRepositoryImpl(db), LineaTelefonicaEquipoRepositoryImpl(db, AsignacionLineaTelefonicaRepositoryImpl(db), AsignacionRepositoryImpl(db))),
      ServicioEventualRepositoryImpl(db, EgresoRepositoryImpl(db), DeudaRepositoryImpl(db, EgresoRepositoryImpl(db)), CodigoSecuenciaService(db), CuentaPorCobrarRepositoryImpl(db), PagoRepositoryImpl(db)),
    );

    final ingresoManual = await RegistrarIngresoManualUseCase(ingresoRepo, generarCodigo).ejecutar(
      monto: 987654321,
      fecha: DateTime(2026, 9, 3),
      formaPago: 'transferencia',
      concepto: 'Reembolso de gastos de representación del cliente institucional Comercializadora Internacional del Noreste S.A. de C.V.',
      observaciones: 'Observación administrativa deliberadamente larga para forzar el ajuste responsive del expediente en anchos angostos',
    );
    ingresoManualId = (ingresoManual as RegistrarIngresoManualExitoso).ingreso.id;
    // Motivo largo en el historial.
    await CorregirIngresoUseCase(ingresoRepo).ejecutar(
      ingresoId: ingresoManualId,
      concepto: 'Reembolso de gastos de representación (corregido tras revisión administrativa)',
      motivo: 'El cliente solicitó una corrección administrativa tras detectar una inconsistencia en el concepto original capturado por el área de cobranza',
    );

    final egresoManual = await RegistrarEgresoUseCase(egresoRepo, generarCodigo, deudaRepo).ejecutar(
      monto: 987654321,
      fecha: DateTime(2026, 9, 3),
      formaPago: 'transferencia',
      beneficiario: 'Proveedor Integral de Seguridad Privada del Bajío S.A. de C.V.',
      concepto: 'Pago de servicios de mantenimiento preventivo y correctivo de la flotilla vehicular institucional',
      observaciones: 'Observación administrativa deliberadamente larga para forzar el ajuste responsive del expediente en anchos angostos',
    );
    egresoManualId = (egresoManual as RegistrarEgresoExitoso).egreso.id;
    await CorregirEgresoUseCase(egresoRepo, obtenerOrigenAutomatico, deudaRepo).ejecutar(
      egresoId: egresoManualId,
      concepto: 'Pago de servicios de mantenimiento (corregido tras revisión administrativa)',
      motivo: 'Se detectó un error de captura en el concepto original y se corrigió tras validar con el área operativa responsable del contrato',
    );

    final compra = await RegistrarCompraUseCase(compraRepo, articuloRepo, inventarioRepo, deudaRepo, generarCodigo).ejecutar(
      fecha: DateTime(2026, 9, 3),
      proveedor: 'Proveedor de Insumos Industriales del Noreste S.A. de C.V.',
      formaPago: 'transferencia',
      partidas: [
        const PartidaCompraInput(destino: 'gastoDirecto', concepto: 'Insumos de mantenimiento industrial de largo plazo', cantidad: 1, costoUnitario: 123456),
      ],
    );
    egresoAutomaticoId = (compra as RegistrarCompraExitosa).compra.egresoId!;

    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionMaestroDePrueba.new),
      ],
    );
    addTearDown(container.dispose);
  });

  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester, {required Widget child, required Size tamano, required ThemeData tema}) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: tema,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: child),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final anchos = [const Size(1536, 900), const Size(1366, 768), const Size(1024, 768), const Size(700, 900), const Size(500, 900)];
  final temas = [AppTheme.light(), AppTheme.dark()];

  for (final tamano in anchos) {
    for (final tema in temas) {
      final nombreTema = tema.brightness == Brightness.dark ? 'oscuro' : 'claro';

      testWidgets('IngresoDetalleDialog (manual, motivo largo en historial) no desborda a ${tamano.width.toInt()}px, tema $nombreTema', (tester) async {
        await pump(tester, child: IngresoDetalleDialog(ingresoId: ingresoManualId), tamano: tamano, tema: tema);
        expect(tester.takeException(), isNull);
      });

      testWidgets('EgresoDetalleDialog (manual, motivo largo en historial) no desborda a ${tamano.width.toInt()}px, tema $nombreTema', (tester) async {
        await pump(tester, child: EgresoDetalleDialog(egresoId: egresoManualId), tamano: tamano, tema: tema);
        expect(tester.takeException(), isNull);
      });

      testWidgets('EgresoDetalleDialog (automático — origen/aviso/Ver origen) no desborda a ${tamano.width.toInt()}px, tema $nombreTema', (tester) async {
        await pump(tester, child: EgresoDetalleDialog(egresoId: egresoAutomaticoId), tamano: tamano, tema: tema);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final tamano in [const Size(1536, 900), const Size(700, 900), const Size(500, 900)]) {
    for (final tema in temas) {
      final nombreTema = tema.brightness == Brightness.dark ? 'oscuro' : 'claro';

      testWidgets('mostrarDialogoCorregirIngreso (con campo de monto) no desborda a ${tamano.width.toInt()}px, tema $nombreTema', (tester) async {
        await pump(tester, child: IngresoDetalleDialog(ingresoId: ingresoManualId), tamano: tamano, tema: tema);
        await tester.ensureVisible(find.text('Corregir'));
        await tester.tap(find.text('Corregir'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('mostrarDialogoCorregirEgreso (con campo de monto) no desborda a ${tamano.width.toInt()}px, tema $nombreTema', (tester) async {
        await pump(tester, child: EgresoDetalleDialog(egresoId: egresoManualId), tamano: tamano, tema: tema);
        await tester.ensureVisible(find.text('Corregir'));
        await tester.tap(find.text('Corregir'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
