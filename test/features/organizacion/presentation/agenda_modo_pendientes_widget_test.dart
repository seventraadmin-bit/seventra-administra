// Modo "Pendientes de emisión" en la Agenda — la vista a la que lleva la
// alerta "Documentos por emitir pendientes" del Dashboard.
//
// Lo que se prueba aquí es el contrato de la URL: `?filtro=pendientes` abre
// el modo, la ausencia del parámetro abre la vista mensual, y el modo no se
// recuerda por inercia. La regla de qué documento es accionable ya está
// probada en `dashboard_agenda_documentos_pendientes_test.dart`.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart' show attachmentStorageProvider;
import 'package:riseg_one/features/organizacion/presentation/agenda/agenda_controller.dart';
import 'package:riseg_one/features/organizacion/presentation/comercial_shell_screen.dart';
import 'package:riseg_one/features/organizacion/presentation/agenda/agenda_list_screen.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

class _SesionMaestroDePrueba extends SesionController {
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
  late String clienteId;

  // Dos meses atrás: fuera de la ventana de la vista mensual, dentro del
  // conjunto accionable. Ése es justamente el caso que motivó el modo.
  final fechaVencida = DateTime.now().subtract(const Duration(days: 60));

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final cliente = await db.into(db.cliente).insertReturning(
          ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'SPORTIUM'),
        );
    clienteId = cliente.id;
  });

  tearDown(() => db.close());

  Future<void> sembrarPendienteAtrasado() async {
    await db.into(db.documentoPorEmitir).insert(
          DocumentoPorEmitirCompanion.insert(
            codigo: 'DOC-000020',
            clienteId: clienteId,
            tipoDocumento: 'reciboDePago',
            agrupacion: 'porServicio',
            metodo: 'noAplica',
            periodoInicio: fechaVencida,
            periodoFin: fechaVencida.add(const Duration(days: 30)),
            fechaEmisionProgramada: Value(fechaVencida),
            generationKey: 'GK-DOC-000020',
            importeBaseEsperado: 1850000,
            importeFinalEsperado: 1850000,
            estatus: const Value('pendiente'),
          ),
        );
  }

  Future<ProviderContainer> pumpAgenda(WidgetTester tester, {required bool modoPendientes}) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      sesionControllerProvider.overrideWith(_SesionMaestroDePrueba.new),
      attachmentStorageProvider.overrideWithValue(AttachmentStorage('.')),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: AgendaListScreen(modoPendientes: modoPendientes)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('con ?filtro=pendientes abre el modo y muestra el documento atrasado', (tester) async {
    await sembrarPendienteAtrasado();

    final container = await pumpAgenda(tester, modoPendientes: true);

    expect(container.read(agendaControllerProvider).modoPendientes, isTrue);
    expect(find.text('DOC-000020'), findsOneWidget);
    expect(find.byKey(const Key('agenda_distintivo_modo_pendientes')), findsOneWidget);
    expect(find.byKey(const Key('agenda_boton_volver_al_mes')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('en modo Pendientes no hay navegador de mes ni filtro de estatus', (tester) async {
    await sembrarPendienteAtrasado();
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await pumpAgenda(tester, modoPendientes: true);

    expect(find.byTooltip(l10n.agendaListadoBotonMesAnterior), findsNothing);
    expect(find.byTooltip(l10n.agendaListadoBotonMesSiguiente), findsNothing);
    expect(
      find.byKey(const Key('agenda_filtro_estatus')),
      findsNothing,
      reason: 'el conjunto ya es accionable: filtrar por Procesado no puede dar nada',
    );
    // Los filtros que sí conservan sentido siguen ahí: Cliente y Tipo de
    // documento. Se cuentan los selectores porque sus etiquetas coinciden con
    // encabezados de la tabla.
    expect(find.byType(RisegSelect<String?>), findsNWidgets(2));
  });

  testWidgets('sin el parámetro abre la vista mensual, y el documento atrasado no aparece', (tester) async {
    await sembrarPendienteAtrasado();
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    final container = await pumpAgenda(tester, modoPendientes: false);

    expect(container.read(agendaControllerProvider).modoPendientes, isFalse);
    expect(find.byKey(const Key('agenda_distintivo_modo_pendientes')), findsNothing);
    expect(find.byTooltip(l10n.agendaListadoBotonMesAnterior), findsOneWidget);
    expect(find.text('DOC-000020'), findsNothing, reason: 'es de hace dos meses');
  });

  testWidgets('"Volver al mes" sale del modo sin recargar la pantalla', (tester) async {
    await sembrarPendienteAtrasado();

    final container = await pumpAgenda(tester, modoPendientes: true);
    expect(find.text('DOC-000020'), findsOneWidget);

    await tester.tap(find.byKey(const Key('agenda_boton_volver_al_mes')));
    await tester.pumpAndSettle();

    expect(container.read(agendaControllerProvider).modoPendientes, isFalse);
    expect(find.byKey(const Key('agenda_distintivo_modo_pendientes')), findsNothing);
    expect(find.text('DOC-000020'), findsNothing);
  });

  testWidgets('sin pendientes, el modo lo dice con sus propias palabras y se queda', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    final container = await pumpAgenda(tester, modoPendientes: true);

    expect(find.text(l10n.agendaPendientesVacioMensaje), findsOneWidget);
    expect(
      container.read(agendaControllerProvider).modoPendientes,
      isTrue,
      reason: 'llegar a cero es un resultado, no un motivo para devolver al mes',
    );
  });

  testWidgets('el Shell de Comercial traslada el contexto de la URL a la Agenda', (tester) async {
    await sembrarPendienteAtrasado();
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      sesionControllerProvider.overrideWith(_SesionMaestroDePrueba.new),
      attachmentStorageProvider.overrideWithValue(AttachmentStorage('.')),
    ]);
    addTearDown(container.dispose);

    // Monta el Shell, no la pantalla suelta: es el eslabon que traduce el
    // query param de la ruta en el modo. Romperlo aqui reproduce el bug
    // original (Dashboard N, Agenda 0) y esta prueba lo detecta.
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: ComercialShellScreen(tab: ComercialTab.agenda, agendaModoPendientes: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(container.read(agendaControllerProvider).modoPendientes, isTrue);
    expect(find.text('DOC-000020'), findsOneWidget);
  });
}
