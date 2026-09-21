// Etapa "origen financiero unificado — TiempoExtra, Egresos manuales,
// TDC". El diálogo "Registrar tiempo extra" ganó, tanto para el pago
// base como para cada costo adicional, un selector dinámico de origen
// financiero (Cuenta de origen / Tarjeta utilizada) — prueba
// responsive en los 4 anchos estándar × claro/oscuro ya usados en el
// proyecto, mismo criterio que `deudas_credito_widget_test.dart`.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/finanzas/data/tables/cuenta_financiera_table.dart';
import 'package:riseg_one/features/finanzas/data/tables/deuda_table.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/tiempos_extra/presentation/widgets/registrar_tiempo_extra_dialog.dart';
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

Future<void> _sembrar(AppDatabase db) async {
  await db.into(db.usuario).insert(
        UsuarioCompanion.insert(
          id: const Value('usuario-maestro'),
          nombre: 'Maestro de prueba',
          nombreUsuario: 'usuario-maestro',
          passwordHash: 'x',
        ),
      );

  final asignacionServicioRepo = AsignacionServicioRepositoryImpl(db);
  final servicioRepo = ServicioRepositoryImpl(db, asignacionServicioRepo);
  final clienteRepo = ClienteRepositoryImpl(db);
  final catalogoRepo = CatalogoRepositoryImpl(db);
  final codigoSecuencia = CodigoSecuenciaService(db);

  final cliente = await clienteRepo.crear(ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Sportium'));
  await CrearServicioUseCase(servicioRepo, GenerarCodigoUseCase(codigoSecuencia), ServicioValidator(clienteRepo, catalogoRepo)).ejecutar(
    clienteId: cliente.id,
    borrador: ServicioBorrador(nombre: 'Vigilancia Sportium', tipoServicioId: SeedIds.tipoServicioVigilanciaFija, fechaInicio: DateTime(2026, 1, 1)),
  );

  await db.into(db.empleado).insertReturning(
        EmpleadoCompanion.insert(
          numeroEmpleado: 1,
          nombres: 'Monica',
          apellidoPaterno: 'Ausente',
          sexo: 'femenino',
          fechaNacimiento: DateTime(1990, 1, 1),
          curp: 'PEXJ900101MDFXXX01',
          rfc: 'PEXJ90010101',
          nss: '10000000001',
          estadoCivil: 'soltero',
          fechaIngreso: DateTime(2025, 1, 1),
          aniosExperienciaSeguridad: 3,
        ),
      );

  await db.into(db.cuentaFinanciera).insert(
        CuentaFinancieraCompanion.insert(
          codigo: 'CTA-0001',
          nombre: 'BBVA Empresarial',
          tipo: TipoCuentaFinanciera.banco.name,
          saldoInicial: 1000000,
          fechaSaldoInicial: DateTime(2026, 1, 1),
        ),
      );

  await db.into(db.deuda).insertReturning(
        DeudaCompanion.insert(
          folio: 'DEU-000001',
          nombre: 'Konfío Empresarial',
          tipo: TipoDeuda.tarjetaCredito.name,
          saldoActual: 0,
          tarjetaLimiteCredito: const Value(4000000),
          estatus: const Value('activa'),
        ),
      );
}

Future<void> _pump(WidgetTester tester, AppDatabase db, {required Size tamano, required ThemeData tema}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Consumer(
          builder: (context, ref, _) => Scaffold(
            body: Center(
              child: RisegButton(
                label: 'Abrir',
                onPressed: () => mostrarDialogoRegistrarTiempoExtra(context, ref),
              ),
            ),
          ),
        ),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionMaestroDePrueba.new),
      ],
      child: MaterialApp.router(
        theme: tema,
        themeMode: ThemeMode.light,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Abrir'));
  await tester.pumpAndSettle();
}

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await _sembrar(db);
  });

  tearDown(() => db.close());

  const anchos = [
    Size(1536, 864),
    Size(1366, 768),
    Size(1024, 768),
    Size(700, 900),
    Size(500, 900),
  ];
  final temas = {'claro': AppTheme.light(), 'oscuro': AppTheme.dark()};

  for (final entradaTema in temas.entries) {
    for (final tamano in anchos) {
      final etiqueta = '${tamano.width.toInt()}×${tamano.height.toInt()}, ${entradaTema.key}';

      testWidgets('Registrar tiempo extra — origen financiero, pago base con Cuenta de origen ($etiqueta): cero overflow', (tester) async {
        await _pump(tester, db, tamano: tamano, tema: entradaTema.value);
        final l10n = await AppLocalizations.delegate.load(const Locale('es'));

        expect(find.text(l10n.registrarTiempoExtraCampoCuentaOrigen), findsOneWidget, reason: 'formaPago por defecto (efectivo) pide cuenta de origen');
        expect(tester.takeException(), isNull);
      });

      testWidgets(
        'Registrar tiempo extra — cambiar entre los tres orígenes de cobertura ($etiqueta): '
        'cero overflow y sin campos del origen anterior',
        (tester) async {
          await _pump(tester, db, tamano: tamano, tema: entradaTema.value);
          final l10n = await AppLocalizations.delegate.load(const Locale('es'));

          final selectorOrigen = find.byKey(const Key('tiempo_extra_campo_origen'));
          Future<void> elegirOrigen(String etiquetaOrigen) async {
            await tester.ensureVisible(selectorOrigen);
            await tester.pumpAndSettle();
            await tester.tap(selectorOrigen);
            await tester.pumpAndSettle();
            await tester.tap(find.text(etiquetaOrigen).last);
            await tester.pumpAndSettle();
          }

          // Arranca en Ausencia: sus dos campos están, los otros no.
          expect(find.byKey(const Key('tiempo_extra_campo_empleado_ausente')), findsOneWidget);
          expect(find.byKey(const Key('tiempo_extra_campo_vacante')), findsNothing);
          expect(find.byKey(const Key('tiempo_extra_campo_descripcion_origen')), findsNothing);
          expect(tester.takeException(), isNull);

          // Ausencia → Vacante: desaparece el empleado faltante.
          await elegirOrigen(l10n.origenCoberturaVacante);
          expect(
            find.byKey(const Key('tiempo_extra_campo_empleado_ausente')),
            findsNothing,
            reason: 'no se conservan campos visuales del origen anterior',
          );
          expect(find.text(l10n.registrarTiempoExtraCampoMotivoAusencia), findsNothing);
          expect(find.byKey(const Key('tiempo_extra_campo_descripcion_origen')), findsNothing);
          // Este Servicio no tiene vacantes abiertas: estado legítimo,
          // no un error ni un selector vacío.
          expect(find.text(l10n.origenCoberturaVacanteSinOpciones), findsOneWidget);
          expect(tester.takeException(), isNull);

          // Vacante → Otro: sólo queda el motivo escrito a mano.
          await elegirOrigen(l10n.origenCoberturaOtro);
          expect(find.byKey(const Key('tiempo_extra_campo_descripcion_origen')), findsOneWidget);
          expect(find.byKey(const Key('tiempo_extra_campo_vacante')), findsNothing);
          expect(find.byKey(const Key('tiempo_extra_campo_empleado_ausente')), findsNothing);
          expect(tester.takeException(), isNull);

          // Otro → Ausencia: vuelve a su forma original.
          await elegirOrigen(l10n.origenCoberturaAusenciaEmpleado);
          expect(find.byKey(const Key('tiempo_extra_campo_empleado_ausente')), findsOneWidget);
          expect(find.byKey(const Key('tiempo_extra_campo_descripcion_origen')), findsNothing);
          expect(tester.takeException(), isNull);

          // El pie del diálogo sigue alcanzable en todo momento.
          expect(find.text(l10n.registrarTiempoExtraBotonConfirmar), findsOneWidget);
        },
      );

      testWidgets(
        'Registrar tiempo extra — origen financiero, pago base con Tarjeta utilizada + costo adicional con su propio origen ($etiqueta): cero overflow',
        (tester) async {
          await _pump(tester, db, tamano: tamano, tema: entradaTema.value);
          final l10n = await AppLocalizations.delegate.load(const Locale('es'));

          final selectorFormaPago = find.byWidgetPredicate((w) => w is RisegSelect<String> && w.value == FormaPago.efectivo.name);
          await tester.ensureVisible(selectorFormaPago);
          await tester.tap(selectorFormaPago);
          await tester.pumpAndSettle();
          await tester.tap(find.text(l10n.formaPagoTarjeta).last);
          await tester.pumpAndSettle();

          expect(find.text(l10n.registrarTiempoExtraCampoTarjetaUtilizada), findsOneWidget, reason: 'formaPago == tarjeta debe pedir la tarjeta, nunca la cuenta');
          expect(find.text(l10n.registrarTiempoExtraCampoCuentaOrigen), findsNothing);

          await tester.tap(find.byKey(const Key('tiempo_extra_boton_agregar_costo')));
          await tester.pumpAndSettle();

          expect(
            find.text(l10n.registrarTiempoExtraCampoFormaPagoCosto),
            findsNWidgets(2),
            reason: 'la etiqueta "Forma de pago" se repite: una para el pago base, otra para el costo adicional',
          );
          expect(
            find.text(l10n.registrarTiempoExtraCampoCuentaOrigen),
            findsOneWidget,
            reason: 'el costo adicional recién agregado tiene su PROPIO origen (efectivo por defecto), independiente del pago base',
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
