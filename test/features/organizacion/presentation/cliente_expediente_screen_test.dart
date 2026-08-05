// Pruebas de la pantalla de expediente de Cliente — cancelar con/sin
// cambios (mismo patrón visual que Empresa/Sucursal/Puesto), cambio de
// estatus, y la sección de Contactos (terreno nuevo: alta, marcar como
// principal, archivar).

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
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/cliente_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/contacto_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_cliente_usecase.dart';
import 'package:riseg_one/features/organizacion/presentation/clientes/cliente_expediente_screen.dart';

Future<String> _crearCliente(AppDatabase db) async {
  final crear = CrearClienteUseCase(ClienteRepositoryImpl(db), GenerarCodigoUseCase(CodigoSecuenciaService(db)));
  final creado = await crear.ejecutar(nombreComercial: 'Sportium');
  return creado.when(ok: (c) => c.id, failure: (f) => throw StateError(f.message));
}

Future<void> _pumpScreen(WidgetTester tester, AppDatabase db, String clienteId) async {
  // Ventana amplia: a diferencia de Puesto/Sucursal, el expediente de
  // Cliente apila tres secciones (datos generales, dirección de
  // referencia, contactos) que no caben en el tamaño de prueba por
  // defecto (800x600) — sin esto, "Agregar contacto" queda fuera del
  // viewport y los `tap()` fallan aunque el `SingleChildScrollView` sí
  // lo pueda desplazar.
  tester.view.physicalSize = const Size(1440, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ClienteExpedienteScreen(clienteId: clienteId),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late AppDatabase db;
  late String clienteId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    clienteId = await _crearCliente(db);
  });

  tearDown(() => db.close());

  testWidgets('cancelar sin cambios regresa a consulta sin pedir confirmación', (tester) async {
    await _pumpScreen(tester, db, clienteId);

    await tester.tap(find.byKey(const Key('cliente_expediente_boton_editar')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cliente_expediente_boton_guardar')), findsOneWidget);

    await tester.tap(find.byKey(const Key('cliente_expediente_boton_cancelar')));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
    expect(find.byKey(const Key('cliente_expediente_boton_editar')), findsOneWidget);
  });

  testWidgets('cancelar con cambios pide confirmación antes de descartar', (tester) async {
    await _pumpScreen(tester, db, clienteId);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await tester.tap(find.byKey(const Key('cliente_expediente_boton_editar')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'Nombre modificado');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('cliente_expediente_boton_cancelar')));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    await tester.tap(find.text(l10n.empresaCancelarConfirmacionConfirmar));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
    expect(find.byKey(const Key('cliente_expediente_boton_editar')), findsOneWidget);
  });

  testWidgets('guardar cambios de datos generales y dirección de referencia', (tester) async {
    await _pumpScreen(tester, db, clienteId);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await tester.tap(find.byKey(const Key('cliente_expediente_boton_editar')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'Sportium Renombrado');
    await tester.tap(find.byKey(const Key('cliente_expediente_boton_guardar')));
    await tester.pumpAndSettle();

    expect(find.text('Sportium Renombrado'), findsWidgets);
    expect(find.text(l10n.clienteGuardadoExito), findsOneWidget);
  });

  testWidgets('cambiar estatus mediante el diálogo de selección', (tester) async {
    await _pumpScreen(tester, db, clienteId);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    expect(find.text(l10n.clienteEstatusProspecto), findsOneWidget);

    await tester.tap(find.byKey(const Key('cliente_boton_cambiar_estatus')));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<EstatusCliente>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.clienteEstatusActivo).last);
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.clienteCambiarEstatusBotonGuardar));
    await tester.pumpAndSettle();

    expect(find.text(l10n.clienteEstatusActivo), findsOneWidget);
  });

  testWidgets('agregar un contacto lo muestra en la lista con su tipo', (tester) async {
    await _pumpScreen(tester, db, clienteId);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await tester.tap(find.byKey(const Key('cliente_contacto_boton_agregar')));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, 'Juan Pérez');

    await tester.tap(find.byType(DropdownButtonFormField<TipoContacto>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.clienteContactoTipoComercial).last);
    await tester.pumpAndSettle();

    // Teléfono, para satisfacer "al menos un medio de contacto".
    await tester.enterText(find.byType(TextFormField).at(2), '5555555555');

    await tester.tap(find.text(l10n.clienteContactoDialogoBotonGuardar));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
    expect(find.text('Juan Pérez'), findsOneWidget);
    expect(find.text(l10n.clienteContactoTipoComercial), findsOneWidget);
  });

  testWidgets('agregar un contacto sin teléfono ni correo muestra el error sin cerrar el diálogo', (tester) async {
    await _pumpScreen(tester, db, clienteId);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await tester.tap(find.byKey(const Key('cliente_contacto_boton_agregar')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'Sin medio de contacto');
    await tester.tap(find.byType(DropdownButtonFormField<TipoContacto>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.clienteContactoTipoOperativo).last);
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.clienteContactoDialogoBotonGuardar));
    await tester.pumpAndSettle();

    // El diálogo no se cierra ante un error de validación — el
    // controlador devuelve `GuardarContactoErroresValidacion`, y la
    // pantalla lo muestra como un error general (no persiste).
    expect(find.text('Sin medio de contacto'), findsNothing);
  });

  testWidgets('marcar un contacto como principal y luego archivarlo', (tester) async {
    await _pumpScreen(tester, db, clienteId);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await tester.tap(find.byKey(const Key('cliente_contacto_boton_agregar')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Juan Pérez');
    await tester.tap(find.byType(DropdownButtonFormField<TipoContacto>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.clienteContactoTipoComercial).last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(2), '5555555555');
    await tester.tap(find.text(l10n.clienteContactoDialogoBotonGuardar));
    await tester.pumpAndSettle();

    expect(find.text(l10n.clienteContactoPrincipalBadge), findsNothing);

    await tester.tap(find.widgetWithIcon(IconButton, Icons.star_outline));
    await tester.pumpAndSettle();
    expect(find.text(l10n.clienteContactoPrincipalBadge), findsOneWidget);

    await tester.tap(find.widgetWithIcon(IconButton, Icons.archive_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    await tester.tap(find.text(l10n.sucursalConfirmarAceptar));
    await tester.pumpAndSettle();

    expect(find.text('Juan Pérez'), findsNothing);
    expect(find.text(l10n.clienteContactosVacioMensaje), findsOneWidget);
  });
}
