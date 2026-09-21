// Bug real reportado por Marlon (Etapa 15): "RIGHT OVERFLOWED BY 43
// PIXELS" en `NominaDetalleScreen` — la barra de acciones superior
// (Actualizar desde Personal / Cerrar nómina / Eliminar físicamente)
// vivía en un `Row` rígido con `Spacer()`, sin forma de pasar a una
// segunda línea en anchos reducidos. Se corrigió reemplazando ese `Row`
// por un `Wrap` (mismo patrón ya usado en `ServicioExpedienteScreen`).
// Estas pruebas confirman ancho amplio, el ancho real reportado, y un
// ancho menor razonable, tanto para una Nómina Borrador (con todas sus
// acciones) como Pagada (con las acciones Maestro) — sin overflow.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/features/finanzas/data/repositories/cuenta_financiera_repository_impl.dart';
import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/descuentos_personal/data/repositories/descuento_programado_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/repositories/nomina_repository_impl.dart';
import 'package:riseg_one/features/tiempos_extra/data/repositories/tiempo_extra_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/repositories/pago_nomina_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/tables/nomina_table.dart';
import 'package:riseg_one/features/nomina/domain/usecases/cerrar_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/evaluar_renglones_requieren_revision_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/generar_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/registrar_pago_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/resolver_sueldo_empleado_nomina.dart';
import 'package:riseg_one/features/nomina/presentation/nominas/nomina_detalle_screen.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/puesto_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

// Ancho amplio de escritorio típico.
const _anchoAmplio = 1400.0;
// Ancho real reportado por Marlon donde aparecía "RIGHT OVERFLOWED BY
// 43 PIXELS" — una ventana de escritorio angosta pero común, no
// maximizada.
const _anchoReporteReal = 860.0;
// Ancho menor razonable ya soportado por el resto de la aplicación
// (mismo piso que `organizacion_expediente_layout_test.dart`).
const _anchoMenor = 580.0;

class _SesionControllerMaestroDePrueba extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-maestro',
      nombre: 'Usuario Maestro',
      nombreUsuario: 'maestro',
      esMaestro: true,
      permisos: {},
    );
  }
}

Future<void> _fijarAncho(WidgetTester tester, double ancho) async {
  tester.view.physicalSize = Size(ancho, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pump(WidgetTester tester, AppDatabase db, String nominaId) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionControllerMaestroDePrueba.new),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: NominaDetalleScreen(nominaId: nominaId),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late AppDatabase db;
  late NominaRepositoryImpl nominaRepo;
  late GenerarNominaUseCase generarNomina;
  late CerrarNominaUseCase cerrarNomina;
  late RegistrarPagoNominaUseCase registrarPagoNomina;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    final asignacionServicioRepo = AsignacionServicioRepositoryImpl(db);
    final empleadoRepo = EmpleadoRepositoryImpl(db, asignacionServicioRepo);
    final servicioRepo = ServicioRepositoryImpl(db, asignacionServicioRepo);
    final catalogoRepo = CatalogoRepositoryImpl(db);
    final puestoRepo = PuestoRepositoryImpl(db);
    final codigoSecuencia = CodigoSecuenciaService(db);
    final generarCodigo = GenerarCodigoUseCase(codigoSecuencia);

    nominaRepo = NominaRepositoryImpl(db, AsignacionRepositoryImpl(db), DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db)), TiempoExtraRepositoryImpl(db, EgresoRepositoryImpl(db), DeudaRepositoryImpl(db, EgresoRepositoryImpl(db)), CodigoSecuenciaService(db), EmpleadoRepositoryImpl(db, AsignacionServicioRepositoryImpl(db)), ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db))), PagoNominaRepositoryImpl(db, EgresoRepositoryImpl(db), DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db))));
    final resolverSueldo = ResolverSueldoEmpleadoNomina(empleadoRepo, asignacionServicioRepo, servicioRepo, catalogoRepo);
    generarNomina = GenerarNominaUseCase(nominaRepo, empleadoRepo, puestoRepo, catalogoRepo, resolverSueldo, generarCodigo);
    final evaluarRenglonesRequierenRevision = EvaluarRenglonesRequierenRevisionUseCase(nominaRepo, empleadoRepo, resolverSueldo);
    cerrarNomina = CerrarNominaUseCase(nominaRepo, evaluarRenglonesRequierenRevision);

    final pagoNominaRepo = PagoNominaRepositoryImpl(db, EgresoRepositoryImpl(db), DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db)));
    registrarPagoNomina = RegistrarPagoNominaUseCase(pagoNominaRepo, nominaRepo, generarCodigo, CuentaFinancieraRepositoryImpl(db));
  });

  tearDown(() => db.close());

  Future<EmpleadoData> crearEmpleadoDePrueba({int sueldoMensualAdministrativo = 1500000}) {
    return db.into(db.empleado).insertReturning(
          EmpleadoCompanion.insert(
            numeroEmpleado: 1,
            nombres: 'Juan',
            apellidoPaterno: 'Pérez',
            sexo: 'masculino',
            fechaNacimiento: DateTime(1990, 1, 1),
            curp: 'PEXJ900101HDFXXX01',
            rfc: 'PEXJ900101AB1',
            nss: '12345678901',
            estadoCivil: 'soltero',
            fechaIngreso: DateTime(2025, 1, 1),
            aniosExperienciaSeguridad: 3,
            sueldoMensualAdministrativo: Value(sueldoMensualAdministrativo),
          ),
        );
  }

  Future<String> crearNominaBorrador() async {
    await crearEmpleadoDePrueba();
    final generado = (await generarNomina.ejecutar(anio: 2026, mes: 1, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
    return generado.nomina.id;
  }

  Future<String> crearNominaPagada() async {
    final nominaId = await crearNominaBorrador();
    await cerrarNomina.ejecutar(nominaId: nominaId);
    final renglon = (await nominaRepo.listarEmpleados(nominaId)).single;
    final pago = await registrarPagoNomina.ejecutar(
      nominaId: nominaId,
      fechaPago: DateTime(2026, 1, 20),
      formaPago: 'transferencia',
      cuentaFinancieraId: await _cuentaDePrueba(db),
      aplicaciones: [(nominaEmpleadoId: renglon.id, monto: renglon.totalAPagar)],
    );
    expect(pago, isA<RegistrarPagoNominaExitoso>());
    return nominaId;
  }

  group('Nómina Borrador — Actualizar desde Personal + Cerrar nómina + Eliminar físicamente (Maestro)', () {
    testWidgets('ancho amplio: todas las acciones en una fila, sin overflow', (tester) async {
      final nominaId = await crearNominaBorrador();
      await _fijarAncho(tester, _anchoAmplio);
      await _pump(tester, db, nominaId);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ancho del reporte real (860px): las acciones pasan a una segunda línea ordenadamente, sin overflow', (tester) async {
      final nominaId = await crearNominaBorrador();
      await _fijarAncho(tester, _anchoReporteReal);
      await _pump(tester, db, nominaId);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ancho menor razonable (580px), sin overflow', (tester) async {
      final nominaId = await crearNominaBorrador();
      await _fijarAncho(tester, _anchoMenor);
      await _pump(tester, db, nominaId);
      expect(tester.takeException(), isNull);
    });
  });

  group('Nómina Pagada — Eliminar físicamente + Eliminar cadena de prueba (Maestro)', () {
    // Etapa 17: ambas acciones se movieron del `Wrap` de botones rojos
    // permanentes a un menú ⋯ (`RisegActionsMenu`) — sus
    // `PopupMenuItem` solo existen en el árbol una vez abierto el
    // menú, así que cada prueba lo abre antes de buscar la llave.
    testWidgets('ancho amplio, sin overflow', (tester) async {
      final nominaId = await crearNominaPagada();
      await _fijarAncho(tester, _anchoAmplio);
      await _pump(tester, db, nominaId);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const Key('nomina_detalle_menu_acciones')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // Pagada: la eliminación física normal está bloqueada — debe
      // ofrecerse la alternativa de cadena de prueba.
      expect(find.byKey(const Key('nomina_detalle_boton_eliminar_cadena_prueba')), findsOneWidget);
    });

    testWidgets('ancho del reporte real (860px), sin overflow', (tester) async {
      final nominaId = await crearNominaPagada();
      await _fijarAncho(tester, _anchoReporteReal);
      await _pump(tester, db, nominaId);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const Key('nomina_detalle_menu_acciones')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('nomina_detalle_boton_eliminar_cadena_prueba')), findsOneWidget);
    });

    testWidgets('ancho menor razonable (580px), sin overflow', (tester) async {
      final nominaId = await crearNominaPagada();
      await _fijarAncho(tester, _anchoMenor);
      await _pump(tester, db, nominaId);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const Key('nomina_detalle_menu_acciones')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('nomina_detalle_boton_eliminar_cadena_prueba')), findsOneWidget);
    });
  });
}

/// La cuenta de origen de los pagos de Nómina en esta prueba.
///
/// Reutiliza la primera que el archivo ya haya creado; sólo inventa una
/// si no hay ninguna. Desde la Etapa de integridad financiera, un pago
/// de Nómina con monto > 0 exige cuenta: sin ella el Egreso nacería sin
/// origen y ningún saldo bajaría.
Future<String> _cuentaDePrueba(AppDatabase db) async {
  final existentes = await db.select(db.cuentaFinanciera).get();
  if (existentes.isNotEmpty) return existentes.first.id;
  final cuenta = await db.into(db.cuentaFinanciera).insertReturning(
        CuentaFinancieraCompanion.insert(
          codigo: 'CF-NOMINA-PRUEBA',
          nombre: 'Cuenta de prueba',
          tipo: 'banco',
          saldoInicial: 100000000, // fondeada: la v91 rechaza salidas sin saldo
          fechaSaldoInicial: DateTime(2020, 1, 1),
        ),
      );
  return cuenta.id;
}
