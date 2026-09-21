// La frontera de autorización del borrado Maestro de un Servicio
// Eventual, en sus dos capas:
//
//   * el caso de uso: `exigirMaestro`, nunca un permiso dinámico;
//   * la pantalla: la acción se ofrece —y se puede pulsar— sólo si la
//     sesión es Maestro, con evento vigente o cancelado.
//
// La prueba de autorización sola no bastaba: comprobaba que el menú
// EXISTE, no que contuviera la acción ni que se pudiera abrir. Un menú
// dibujado vacío pasaba esa prueba.

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
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/eliminar_servicio_eventual_fisicamente_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/presentation/servicio_eventual_expediente_screen.dart';
import 'package:riseg_one/features/servicios_eventuales/servicios_eventuales_providers.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

class _SesionMaestro extends SesionController {
  @override
  SesionUsuario? build() => const SesionUsuario(
        usuarioId: 'usuario-maestro',
        nombre: 'MARLON',
        nombreUsuario: 'MARLONRH',
        esMaestro: true,
        permisos: {},
      );
}

class _SesionUsuarioNormal extends SesionController {
  @override
  SesionUsuario? build() => const SesionUsuario(
        usuarioId: 'usuario-normal',
        nombre: 'JAVIER',
        nombreUsuario: 'JAVIER',
        esMaestro: false,
        // Con TODOS los permisos dinámicos del módulo: `exigirMaestro`
        // no consulta esta lista, así que ninguno puede conceder esto.
        permisos: {
          'serviciosEventuales.crear',
          'serviciosEventuales.corregir',
          'serviciosEventuales.cancelar',
          'serviciosEventuales.cobrar',
          'serviciosEventuales.facturar',
          'serviciosEventuales.pagar',
          'serviciosEventuales.revertirPago',
        },
      );
}

Future<String> _sembrar(AppDatabase db) async {
  await db.into(db.usuario).insert(
        UsuarioCompanion.insert(
          id: const Value('usuario-maestro'),
          nombre: 'MARLON',
          nombreUsuario: 'MARLONRH',
          passwordHash: r'pbkdf2$1$c2FsdA==$aGFzaA==',
          esMaestro: const Value(true),
        ),
      );
  final eventual = await db.into(db.servicioEventual).insertReturning(
        ServicioEventualCompanion.insert(
          folio: 'EVT-000900',
          nombre: 'Posada',
          fechaHoraInicio: DateTime(2026, 9, 17, 18),
          fechaHoraFin: DateTime(2026, 9, 18, 2),
          importeAcordado: 800000,
          tipoSolicitante: TipoSolicitanteServicioEventual.eventual.name,
          solicitanteNombre: const Value('Juan del comité'),
        ),
      );
  return eventual.id;
}

void main() {
  late AppDatabase db;
  late String eventualId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    eventualId = await _sembrar(db);
    addTearDown(db.close);
  });

  /// Deja el eventual como EVT-000001: cancelado y con su cobranza ya
  /// revertida (cuenta, pago y aplicación cancelados).
  Future<void> dejarloComoEvt1() async {
    final cuenta = await db.into(db.cuentaPorCobrar).insertReturning(
          CuentaPorCobrarCompanion.insert(
            servicioEventualId: Value(eventualId),
            tipoDocumento: 'cfdi',
            metodo: 'pue',
            fechaEmisionReal: DateTime(2026, 9, 17),
            importeEmitido: 928000,
            saldoOriginal: 928000,
            saldoPendiente: 0,
            estatus: const Value('cancelada'),
          ),
        );
    final pago = await db.into(db.pago).insertReturning(
          PagoCompanion.insert(
            folioPago: 'PAG-000019',
            servicioEventualId: Value(eventualId),
            montoTotal: 800000,
            fechaPago: DateTime(2026, 9, 17),
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
    await db.customStatement("UPDATE servicio_eventual SET estatus = 'cancelado'");
  }

  // ----------------------------------------------------------------
  // Capa 1: el caso de uso
  // ----------------------------------------------------------------
  test('un usuario NO Maestro no puede ejecutarla, ni con todos los permisos', () async {
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionUsuarioNormal.new),
      ],
    );
    addTearDown(container.dispose);

    final resultado = await container.read(eliminarServicioEventualFisicamenteAutorizadoProvider)(
      servicioEventualId: eventualId,
      motivo: 'Intento',
    );
    expect(resultado, isA<EliminarServicioEventualFisicamenteErrorInesperado>());
    expect(await db.select(db.servicioEventual).get(), hasLength(1), reason: 'no borró nada');
  });

  test('el Maestro sí puede', () async {
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionMaestro.new),
      ],
    );
    addTearDown(container.dispose);

    final resultado = await container.read(eliminarServicioEventualFisicamenteAutorizadoProvider)(
      servicioEventualId: eventualId,
      motivo: 'Registro de prueba',
    );
    expect(resultado, isA<EliminarServicioEventualFisicamenteExitoso>());
    expect(await db.select(db.servicioEventual).get(), isEmpty);
    final eliminaciones = await db.select(db.eliminacionFisicaEvento).get();
    expect(eliminaciones.single.actorUsuarioId, 'usuario-maestro',
        reason: 'la auditoría dice QUIÉN eliminó');
  });

  // ----------------------------------------------------------------
  // Capa 2: la pantalla
  // ----------------------------------------------------------------
  //
  // Cada prueba monta UNA sola vez: reusar el mismo `pumpWidget` para
  // dos sesiones distintas no vuelve a aplicar el override del
  // `ProviderScope`, y la segunda medición sale con la sesión de la
  // primera — un falso positivo real, encontrado al diagnosticar esto.
  Future<void> montar(WidgetTester tester, SesionController Function() sesion) async {
    tester.view.physicalSize = const Size(1366, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          sesionControllerProvider.overrideWith(sesion),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: ServicioEventualExpedienteScreen(servicioEventualId: eventualId)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// El ⋯ del ENCABEZADO — no cualquier menú de la pantalla.
  ///
  /// Se busca como descendiente del `RisegSectionHeader` que lleva el
  /// folio: que exista un menú en algún lado no sirve de nada si está
  /// perdido en el cuerpo de una pestaña, que es justo donde estaba y
  /// por lo que no se encontraba.
  Finder menuDelEncabezado() => find.descendant(
        of: find.ancestor(
          of: find.textContaining('EVT-000900'),
          matching: find.byType(RisegSectionHeader),
        ),
        matching: find.byKey(const Key('servicio_eventual_expediente_menu_acciones')),
      );

  /// Abre el ⋯ del encabezado y devuelve cuántas acciones ofrece. Cero
  /// si no está.
  Future<int> abrirMenu(WidgetTester tester) async {
    final boton = menuDelEncabezado();
    if (boton.evaluate().isEmpty) return 0;
    await tester.tap(boton);
    await tester.pumpAndSettle();
    return find.byType(PopupMenuItem<VoidCallback>).evaluate().length;
  }

  /// Ningún otro ⋯ fuera del encabezado: mover la acción no puede
  /// dejar un menú huérfano donde estaba.
  void sinMenusSueltos(WidgetTester tester) {
    final todos = find.byType(RisegActionsMenu).evaluate().length;
    expect(todos, menuDelEncabezado().evaluate().length,
        reason: 'hay un RisegActionsMenu fuera del encabezado');
  }

  testWidgets('Maestro + eventual VIGENTE: el ⋯ del encabezado ofrece Eliminar definitivamente',
      (tester) async {
    await montar(tester, _SesionMaestro.new);
    expect(menuDelEncabezado(), findsOneWidget, reason: 'va junto a la identidad del registro');
    sinMenusSueltos(tester);
    expect(await abrirMenu(tester), 1);
    expect(find.text('Eliminar definitivamente'), findsOneWidget);
  });

  testWidgets('Maestro + eventual CANCELADO: la ofrece igual', (tester) async {
    // El caso principal del borrado: el registro de prueba que ya se
    // canceló. Ocultarla aquí dejaría EVT-000001 imposible de limpiar.
    await dejarloComoEvt1();
    await montar(tester, _SesionMaestro.new);
    expect(menuDelEncabezado(), findsOneWidget);
    sinMenusSueltos(tester);
    expect(await abrirMenu(tester), 1);
    expect(find.text('Eliminar definitivamente'), findsOneWidget);
  });

  testWidgets('usuario normal: no la ve', (tester) async {
    await dejarloComoEvt1();
    await montar(tester, _SesionUsuarioNormal.new);
    expect(find.text('Eliminar definitivamente'), findsNothing);
    expect(await abrirMenu(tester), 0);
  });

  testWidgets('sin acciones disponibles NO se dibuja un menú vacío', (tester) async {
    await dejarloComoEvt1();
    await montar(tester, _SesionUsuarioNormal.new);
    // Un evento cancelado no ofrece Finalizar ni Cancelar, y este
    // usuario no es Maestro: no queda ninguna acción, así que tampoco
    // debe quedar el menú prometiendo alguna.
    expect(find.byType(RisegActionsMenu), findsNothing);
  });

  testWidgets('el ⋯ NO se queda además en el cuerpo, con el evento vigente', (tester) async {
    // La regresión concreta: el menú vivía en la pestaña Resumen, entre
    // la ficha y el Historial, y ahí no se encontraba.
    await montar(tester, _SesionMaestro.new);
    sinMenusSueltos(tester);
  });

  testWidgets('pulsarla como Maestro abre el diálogo de eliminación', (tester) async {
    await dejarloComoEvt1();
    await montar(tester, _SesionMaestro.new);

    await tester.tap(menuDelEncabezado());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('servicio_eventual_boton_eliminar_fisicamente')));
    await tester.pumpAndSettle();

    // El caparazón compartido: título con el folio, advertencia de que
    // es permanente y motivo obligatorio.
    expect(find.textContaining('EVT-000900'), findsWidgets);
    expect(find.textContaining('permanente'), findsOneWidget);
    expect(find.byType(RisegTextField), findsOneWidget, reason: 'el campo de motivo');
    expect(tester.takeException(), isNull);
  });
}
