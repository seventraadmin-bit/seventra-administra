// Etapa 19D — "Calendario financiero y planeación de liquidez".
// Barrido responsive de la pantalla COMPLETA (KPIs + gráfica +
// calendario/detalle + resumen semanal + pendientes vencidos), a
// diferencia de `calendario_financiero_mes_widget_test.dart` (que solo
// cubre el widget del calendario aislado). Anchos y temas exigidos por
// el pedido (Parte 19): 1366×768, 1024×768, ~700px, ~500px, claro y
// oscuro — cero RenderFlex overflow.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/finanzas/data/tables/deuda_table.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_cuenta_financiera_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_deuda_usecase.dart';
import 'package:riseg_one/features/finanzas/finanzas_providers.dart';
import 'package:riseg_one/features/finanzas/presentation/planeacion/planeacion_financiera_screen.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import '../../support/sesion_en_base.dart';

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

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(
            id: const Value('usuario-maestro'),
            nombre: 'Maestro de prueba',
            nombreUsuario: 'usuario-maestro',
            passwordHash: 'x',
          ),
        );
    // Etapa 3B: la fila anterior existe pero nace sin `esMaestro`, y la
    // autorización se revalida contra la base — sin esto, el propio
    // `setUp` no podría ejecutar las operaciones autorizadas de abajo.
    await sembrarSesionEnBase(
      db,
      const SesionUsuario(
        usuarioId: 'usuario-maestro',
        nombre: 'Maestro de prueba',
        nombreUsuario: 'maestro',
        esMaestro: true,
        permisos: {},
      ),
    );
    container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      sesionControllerProvider.overrideWith(_SesionMaestroDePrueba.new),
    ]);

    // Cuenta financiera + Deuda con nombre largo (para forzar el caso
    // de recorte de texto en KPIs/tabla/pendientes) — el pago
    // programado cae "hoy" (nunca X días adelante) para no depender
    // del día del mes en que corra la prueba (misma lección aprendida
    // que en `planeacion_financiera_widget_test.dart`).
    final resultadoCuenta = await container.read(registrarCuentaFinancieraAutorizadoProvider)(
      nombre: 'BBVA Operativa',
      tipo: 'banco',
      saldoInicial: 10000000,
      fechaSaldoInicial: DateTime.now().subtract(const Duration(days: 60)),
    );
    assert(resultadoCuenta is RegistrarCuentaFinancieraExitoso);

    final resultadoDeuda = await container.read(registrarDeudaAutorizadoProvider)(
      nombre: 'Financiamiento Sportium Cuautitlán de la Suárez y Asociados S.A. de C.V.',
      tipo: TipoDeuda.prestamo.name,
      fechaOrigen: DateTime.now(),
      importeOriginal: 5000000,
      saldoInicial: 5000000,
      pagoProgramado: 1500000,
      fechaVencimiento: DateTime.now(),
    );
    assert(resultadoDeuda is RegistrarDeudaExitoso);

    // Una CxC vencida sin reprogramar — puebla "Pendientes vencidos"
    // con un nombre largo también.
    final ahora = DateTime.now();
    final cliente = await db.into(db.cliente).insertReturning(
          ClienteCompanion.insert(
            codigo: 'CLI-${ahora.microsecondsSinceEpoch}',
            nombreComercial: 'Comercializadora Regiomontana del Noreste S.A. de C.V.',
          ),
        );
    final documento = await db.into(db.documentoPorEmitir).insertReturning(
          DocumentoPorEmitirCompanion.insert(
            codigo: 'DOC-${ahora.microsecondsSinceEpoch}',
            clienteId: cliente.id,
            tipoDocumento: 'cfdi',
            agrupacion: 'porServicio',
            metodo: 'PUE',
            periodoInicio: ahora,
            periodoFin: ahora,
            generationKey: 'clave-${ahora.microsecondsSinceEpoch}',
            importeBaseEsperado: 987654321,
            importeFinalEsperado: 987654321,
          ),
        );
    await db.into(db.cuentaPorCobrar).insert(
          CuentaPorCobrarCompanion.insert(
            documentoPorEmitirId: Value(documento.id),
            clienteId: Value(cliente.id),
            tipoDocumento: 'cfdi',
            metodo: 'PUE',
            fechaEmisionReal: ahora,
            importeEmitido: 987654321,
            saldoOriginal: 987654321,
            saldoPendiente: 987654321,
            fechaVencimiento: Value(ahora.subtract(const Duration(days: 20))),
          ),
        );
    // Etapa 3B: autorizar revalida contra la base, así que el
    // escenario de la sesión tiene que estar persistido.
    await sembrarSesionEnBase(db, const SesionUsuario( usuarioId: 'usuario-maestro', nombre: 'Maestro de prueba', nombreUsuario: 'maestro', esMaestro: true, permisos: {}, ));
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  Future<void> pump(WidgetTester tester, {required Size tamano, required ThemeData tema}) async {
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
          home: const Scaffold(body: PlaneacionFinancieraScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final tamano in [const Size(1366, 768), const Size(1024, 768), const Size(700, 900), const Size(500, 900)]) {
    for (final tema in [AppTheme.light(), AppTheme.dark()]) {
      final nombreTema = tema.brightness == Brightness.dark ? 'oscuro' : 'claro';
      testWidgets('pantalla completa de Planeación no desborda a ${tamano.width.toInt()}px, tema $nombreTema', (tester) async {
        await pump(tester, tamano: tamano, tema: tema);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
