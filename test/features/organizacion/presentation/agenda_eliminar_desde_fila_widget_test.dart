// Pedido explícito: agregar la opción de eliminar físicamente un
// Documento por emitir de forma individual directo desde la fila del
// listado de Agenda — antes la única vía era abrir el detalle completo
// primero. Reutiliza el mismo diálogo/use case que
// `AgendaDetalleDialog._eliminarFisicamente`, nunca una segunda ruta.

import 'package:drift/drift.dart' hide isNull, isNotNull;
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
import 'package:riseg_one/features/organizacion/presentation/agenda/agenda_list_screen.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
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

class _SesionNoMaestroDePrueba extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-normal',
      nombre: 'Usuario de prueba',
      nombreUsuario: 'usuario',
      esMaestro: false,
      permisos: {'agenda.ver'},
    );
  }
}

void main() {
  late AppDatabase db;
  late String documentoId;

  Future<void> sembrarDocumento() async {
    final clienteRepo = ClienteRepositoryImpl(db);
    final cliente = await clienteRepo.crear(ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Mirabilia'));
    final hoy = DateTime.now();
    final documento = await db.into(db.documentoPorEmitir).insertReturning(
          DocumentoPorEmitirCompanion.insert(
            codigo: 'DOC-000031',
            clienteId: cliente.id,
            tipoDocumento: 'reciboDePago',
            agrupacion: 'porServicio',
            metodo: 'noAplica',
            periodoInicio: DateTime(hoy.year, hoy.month, 1),
            periodoFin: DateTime(hoy.year, hoy.month + 1, 0),
            generationKey: 'GK-DOC-000031',
            importeBaseEsperado: 3500000,
            importeFinalEsperado: 3500000,
            estatus: const Value('pendiente'),
          ),
        );
    documentoId = documento.id;
  }

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
  });

  tearDown(() => db.close());

  Future<ProviderContainer> pumpAgenda(WidgetTester tester, {required bool esMaestro}) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(esMaestro ? _SesionMaestroDePrueba.new : _SesionNoMaestroDePrueba.new),
        attachmentStorageProvider.overrideWithValue(AttachmentStorage('.')),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: AgendaListScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets(
    'Maestro: el menú ⋮ de la fila permite eliminar físicamente sin abrir el detalle completo',
    (tester) async {
      await sembrarDocumento();
      await pumpAgenda(tester, esMaestro: true);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      expect(find.text('DOC-000031'), findsOneWidget);

      await tester.tap(find.byKey(Key('agenda_fila_menu_acciones_$documentoId')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('agenda_fila_accion_eliminar_fisicamente_$documentoId')));
      await tester.pumpAndSettle();

      final campoMotivo = find.descendant(
        of: find.widgetWithText(RisegTextField, l10n.eliminacionFisicaCampoMotivo),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(campoMotivo, 'Servicio terminado antes de este periodo');
      await tester.tap(find.text(l10n.eliminacionFisicaBotonConfirmar));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('DOC-000031'), findsNothing, reason: 'el documento eliminado desde la fila debe desaparecer del listado sin recargar manualmente');
    },
  );

  testWidgets('sin ser Maestro, la fila no muestra ningún menú de acciones', (tester) async {
    await sembrarDocumento();
    await pumpAgenda(tester, esMaestro: false);

    expect(find.text('DOC-000031'), findsOneWidget);
    expect(find.byKey(Key('agenda_fila_menu_acciones_$documentoId')), findsNothing);
  });
}
