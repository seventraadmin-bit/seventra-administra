// Etapa 15 — "Registrar pago de nómina" rediseñado como tabla
// interactiva de dispersión. Cubre: la tabla muestra TODOS los
// renglones (incluidos los ya pagados); banco/cuenta/CLABE vienen del
// snapshot de NominaEmpleado; seleccionar un subconjunto registra
// EXCLUSIVAMENTE esos renglones; un renglón pagado queda bloqueado
// (no se puede volver a seleccionar); datos bancarios incompletos
// muestran "REQUIERE VERIFICACIÓN"; cancelar el diálogo no registra
// nada; progreso monetario/por-empleados exacto; responsive; modo
// oscuro/claro.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChannels;
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/descuentos_personal/data/repositories/descuento_programado_repository_impl.dart';
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_list_screen.dart' show formatoCentavosPago;
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/repositories/nomina_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/repositories/pago_nomina_repository_impl.dart';
import 'package:riseg_one/features/tiempos_extra/data/repositories/tiempo_extra_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/tables/nomina_table.dart';
import 'package:riseg_one/features/nomina/domain/usecases/cerrar_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/evaluar_renglones_requieren_revision_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/generar_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/resolver_sueldo_empleado_nomina.dart';
import 'package:riseg_one/features/nomina/presentation/nominas/widgets/registrar_pago_nomina_dialog.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/puesto_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import '../../support/sesion_en_base.dart';

class _SesionControllerDePrueba extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-prueba',
      nombre: 'Usuario de prueba',
      nombreUsuario: 'prueba',
      esMaestro: true,
      permisos: {},
    );
  }
}

void main() {
  late AppDatabase db;
  late NominaRepositoryImpl nominaRepo;
  late String nominaId;
  late List<NominaEmpleadoData> renglones;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    // La cuenta de origen del pago: obligatoria desde la Etapa de
    // integridad financiera de Nómina.
    await db.into(db.cuentaFinanciera).insertReturning(
          CuentaFinancieraCompanion.insert(
            codigo: 'CF-BBVA-PRUEBA',
            nombre: 'BBVA de prueba',
            tipo: 'banco',
            saldoInicial: 100000000, // fondeada: la v91 rechaza salidas sin saldo
            fechaSaldoInicial: DateTime(2020, 1, 1),
          ),
        );
    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(id: const Value('usuario-prueba'), nombre: 'Usuario de prueba', nombreUsuario: 'usuario-prueba', passwordHash: 'x'),
        );

    final asignacionServicioRepo = AsignacionServicioRepositoryImpl(db);
    final empleadoRepo = EmpleadoRepositoryImpl(db, asignacionServicioRepo);
    final servicioRepo = ServicioRepositoryImpl(db, asignacionServicioRepo);
    final catalogoRepo = CatalogoRepositoryImpl(db);
    final puestoRepo = PuestoRepositoryImpl(db);
    final resolverSueldo = ResolverSueldoEmpleadoNomina(empleadoRepo, asignacionServicioRepo, servicioRepo, catalogoRepo);
    nominaRepo = NominaRepositoryImpl(db, AsignacionRepositoryImpl(db), DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db)), TiempoExtraRepositoryImpl(db, EgresoRepositoryImpl(db), DeudaRepositoryImpl(db, EgresoRepositoryImpl(db)), CodigoSecuenciaService(db), EmpleadoRepositoryImpl(db, AsignacionServicioRepositoryImpl(db)), ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db))), PagoNominaRepositoryImpl(db, EgresoRepositoryImpl(db), DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db))));
    final generarNomina =
        GenerarNominaUseCase(nominaRepo, empleadoRepo, puestoRepo, catalogoRepo, resolverSueldo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));
    final cerrarNomina = CerrarNominaUseCase(nominaRepo, EvaluarRenglonesRequierenRevisionUseCase(nominaRepo, empleadoRepo, resolverSueldo));

    for (var i = 1; i <= 4; i++) {
      final n = i.toString().padLeft(2, '0');
      await db.into(db.empleado).insertReturning(
            EmpleadoCompanion.insert(
              numeroEmpleado: i,
              nombres: 'Empleado$n',
              apellidoPaterno: 'Apellido$n',
              sexo: 'femenino',
              fechaNacimiento: DateTime(1990, 1, 1),
              curp: 'GOFA900101MDFXXX$n',
              rfc: 'GOFA9001019A$n',
              nss: '1000000000$n',
              estadoCivil: 'soltero',
              fechaIngreso: DateTime(2025, 1, 1),
              aniosExperienciaSeguridad: 3,
              sueldoMensualAdministrativo: const Value(1100000),
            ),
          );
    }

    final generado = (await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
    nominaId = generado.nomina.id;
    await cerrarNomina.ejecutar(nominaId: nominaId);
    renglones = await nominaRepo.listarEmpleados(nominaId);

    // `Empleado` nunca capturó banco en este setup — el snapshot de
    // `NominaEmpleado` completa 3 de los 4 renglones directamente aquí
    // (nunca vía Personal, solo para tener datos de prueba realistas),
    // dejando el renglón 4 explícitamente SIN banco a propósito: debe
    // mostrar "REQUIERE VERIFICACIÓN" y no ordenarse junto a los demás.
    for (var i = 0; i < 3; i++) {
      await (db.update(db.nominaEmpleado)..where((t) => t.id.equals(renglones[i].id))).write(
        NominaEmpleadoCompanion(
          bancoNombre: const Value('Banorte'),
          numeroCuentaTarjeta: Value('****000$i'),
          clabe: Value('07201000000000000$i'),
        ),
      );
    }
    renglones = await nominaRepo.listarEmpleados(nominaId);
    // Etapa 3B: autorizar revalida contra la base, así que la
    // sesión de esta prueba tiene que corresponder a una cuenta real.
    await sembrarSesionEnBase(db, SesionUsuario( usuarioId: 'usuario-prueba', nombre: 'Usuario de prueba', nombreUsuario: 'prueba', esMaestro: true, permisos: {}, ));
  });

  tearDown(() => db.close());

  Future<void> abrirDialogo(WidgetTester tester, {Size tamano = const Size(1440, 1400), bool oscuro = false}) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          sesionControllerProvider.overrideWith(_SesionControllerDePrueba.new),
        ],
        child: MaterialApp(
          theme: oscuro ? AppTheme.dark() : AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => ElevatedButton(
                key: const Key('abrir'),
                onPressed: () => showDialog<bool>(
                  context: context,
                  builder: (_) => RegistrarPagoNominaDialog(nominaId: nominaId, renglones: renglones),
                ),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('abrir')));
    await tester.pumpAndSettle();
  }

  /// Elige la cuenta de origen: desde la Etapa de integridad financiera
  /// es obligatoria, porque sin ella el Egreso nacería sin origen y
  /// ningún saldo bajaría.
  Future<void> elegirCuenta(WidgetTester tester) async {
    final campo = find.byKey(const Key('registrar_pago_nomina_campo_cuenta_financiera'));
    await tester.ensureVisible(campo);
    await tester.pumpAndSettle();
    await tester.tap(campo);
    await tester.pumpAndSettle();
    // La opción ahora lleva el saldo pegado al nombre: elegir de qué
    // cuenta sale el dinero sin verlo sería adivinar.
    await tester.tap(find.textContaining('BBVA de prueba').last);
    await tester.pumpAndSettle();
  }

  testWidgets('la tabla muestra TODOS los renglones de la Nómina, con banco/cuenta/CLABE del snapshot', (tester) async {
    await abrirDialogo(tester);

    for (final r in renglones) {
      expect(find.textContaining(r.nombreCompleto), findsWidgets);
    }
    expect(find.textContaining('Banorte').evaluate().isNotEmpty || find.textContaining(renglones.first.bancoNombre ?? '—').evaluate().isNotEmpty, isTrue);
  });

  testWidgets(
    'tocar el ícono de copiar junto a Cuenta/Tarjeta pone el número EXACTO en el portapapeles '
    '(pedido explícito de Marlon: pegarlo tal cual en el portal del banco)',
    (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));
      // `Clipboard.getData` no responde bajo `flutter test` en este
      // entorno (se queda esperando el canal de plataforma real) —
      // se mockea `SystemChannels.platform` para capturar el argumento
      // de `Clipboard.setData` directamente, sin depender de un
      // roundtrip real de portapapeles.
      String? copiado;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copiado = (call.arguments as Map)['text'] as String?;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

      await abrirDialogo(tester);

      final renglonConBanco = renglones.firstWhere((r) => r.numeroCuentaTarjeta != null);
      await tester.tap(find.byKey(ValueKey('dispersion_copiar_cuenta_${renglonConBanco.id}')));
      await tester.pump();

      expect(copiado, renglonConBanco.numeroCuentaTarjeta);
      expect(find.text(l10n.registrarPagoNominaDatoCopiado), findsOneWidget);
    },
  );

  testWidgets(
    'tocar el ícono de copiar junto a CLABE pone la CLABE EXACTA en el portapapeles',
    (tester) async {
      String? copiado;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copiado = (call.arguments as Map)['text'] as String?;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

      await abrirDialogo(tester);

      final renglonConBanco = renglones.firstWhere((r) => r.clabe != null);
      await tester.tap(find.byKey(ValueKey('dispersion_copiar_clabe_${renglonConBanco.id}')));
      await tester.pump();

      expect(copiado, renglonConBanco.clabe);
    },
  );

  testWidgets('empleado sin datos bancarios muestra "REQUIERE VERIFICACIÓN"', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));
    await abrirDialogo(tester);

    expect(find.text(l10n.registrarPagoNominaRequiereVerificacion), findsOneWidget);
  });

  testWidgets('seleccionar 3 de 4 y registrar aplica EXCLUSIVAMENTE esos 3 — el 4º permanece pendiente', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));
    await abrirDialogo(tester);

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(ValueKey('dispersion_checkbox_${renglones[i].id}')));
      await tester.pump();
    }

    expect(find.text(l10n.registrarPagoNominaSeleccionResumen(3, formatoCentavosPago(renglones.take(3).fold(0, (s, r) => s + r.totalAPagar)))), findsOneWidget);

    await elegirCuenta(tester);
    await tester.tap(find.byKey(const Key('registrar_pago_nomina_boton_registrar')));
    await tester.pumpAndSettle();
    // Diálogo de confirmación (Parte 11 del pedido).
    await tester.tap(find.text(l10n.registrarPagoNominaConfirmacionBotonConfirmar));
    await tester.pumpAndSettle();

    for (var i = 0; i < 3; i++) {
      final renglonActualizado = await nominaRepo.obtenerEmpleado(renglones[i].id);
      expect(renglonActualizado!.estatusPago, 'pagado');
    }
    final cuarto = await nominaRepo.obtenerEmpleado(renglones[3].id);
    expect(cuarto!.estatusPago, 'pendiente', reason: 'nunca se tocó — no estaba seleccionado');

    final nominaTrasPago = await nominaRepo.obtenerPorId(nominaId);
    expect(nominaTrasPago!.estatus, 'cerrada', reason: 'un renglón sigue sin pagar, nunca pasa a pagada');
  });

  testWidgets('al reabrir el diálogo tras pagar, esos renglones aparecen bloqueados (checkbox deshabilitado)', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));
    await abrirDialogo(tester);

    await tester.tap(find.byKey(ValueKey('dispersion_checkbox_${renglones[0].id}')));
    await tester.pump();
    await elegirCuenta(tester);
    await tester.tap(find.byKey(const Key('registrar_pago_nomina_boton_registrar')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.registrarPagoNominaConfirmacionBotonConfirmar));
    await tester.pumpAndSettle();
    // El diálogo se cierra solo al confirmar con éxito — se reabre con
    // los renglones frescos (mismo patrón que la pantalla real:
    // `NominaDetalleScreen._cargar()` tras `huboCambio`).
    renglones = await nominaRepo.listarEmpleados(nominaId);
    await tester.tap(find.byKey(const Key('abrir')));
    await tester.pumpAndSettle();

    final checkboxPagado = tester.widget<Checkbox>(find.byKey(ValueKey('dispersion_checkbox_${renglones[0].id}')));
    expect(checkboxPagado.value, isTrue);
    expect(checkboxPagado.onChanged, isNull, reason: 'un renglón ya pagado no puede volver a seleccionarse — nunca doble pago');
  });

  testWidgets('cancelar el diálogo (botón Cancelar) no registra ningún pago', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));
    await abrirDialogo(tester);

    await tester.tap(find.byKey(ValueKey('dispersion_checkbox_${renglones[0].id}')));
    await tester.pump();
    await tester.tap(find.text(l10n.registrarPagoNominaBotonCancelar));
    await tester.pumpAndSettle();

    final renglon = await nominaRepo.obtenerEmpleado(renglones[0].id);
    expect(renglon!.estatusPago, 'pendiente');
    final pagos = await (db.select(db.pagoNomina)..where((t) => t.nominaId.equals(nominaId))).get();
    expect(pagos, isEmpty);
  });

  testWidgets('cerrar con la X tras seleccionar no registra ningún pago', (tester) async {
    await abrirDialogo(tester);

    await tester.tap(find.byKey(ValueKey('dispersion_checkbox_${renglones[0].id}')));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    final pagos = await (db.select(db.pagoNomina)..where((t) => t.nominaId.equals(nominaId))).get();
    expect(pagos, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('el progreso inicial muestra 0 de N pagados y el pendiente exacto', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));
    await abrirDialogo(tester);

    expect(find.text(l10n.registrarPagoNominaProgresoEmpleados(0, 4)), findsOneWidget);
    final totalGeneral = renglones.fold<int>(0, (s, r) => s + r.totalAPagar);
    expect(find.text(l10n.registrarPagoNominaProgresoPendiente(formatoCentavosPago(totalGeneral))), findsOneWidget);
  });

  group('Responsive — cero RenderFlex overflow', () {
    testWidgets('1920×1080', (tester) async {
      await abrirDialogo(tester, tamano: const Size(1920, 1080));
      expect(tester.takeException(), isNull);
    });

    testWidgets('1366×768', (tester) async {
      await abrirDialogo(tester, tamano: const Size(1366, 768));
      expect(tester.takeException(), isNull);
    });

    testWidgets('~1000px de ancho (borde de AppBreakpoints.medium, tabla vs. tarjetas)', (tester) async {
      await abrirDialogo(tester, tamano: const Size(1000, 900));
      expect(tester.takeException(), isNull);
    });

    testWidgets('ancho mínimo razonable soportado (~480px, tarjetas apiladas)', (tester) async {
      await abrirDialogo(tester, tamano: const Size(480, 1400));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('modo oscuro no produce excepciones', (tester) async {
    await abrirDialogo(tester, oscuro: true);
    expect(tester.takeException(), isNull);
  });
}
