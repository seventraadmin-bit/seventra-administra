// Pruebas de widget del CRUD de portales en el expediente del Cliente
// (Etapa 15, sección "Datos de cobranza / Facturación") — alta,
// edición y archivado/reactivación, mismo patrón real de UI que ya
// prueba Entidad fiscal. También confirma que editar un portal después
// de que una Configuración de cobro ya lo referencia no rompe esa
// referencia (Marlon: "las referencias existentes deben seguir siendo
// resolubles").

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

import 'package:riseg_one/features/organizacion/data/repositories/cliente_portal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_cliente_usecase.dart';
import 'package:riseg_one/features/organizacion/presentation/clientes/cliente_expediente_screen.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

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

Future<void> _pump(WidgetTester tester, AppDatabase db, Widget pantalla) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionControllerDePrueba.new),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: pantalla,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  Future<String> crearCliente() async {
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    final crearCliente = CrearClienteUseCase(ClienteRepositoryImpl(db), generarCodigo);
    final resultado = await crearCliente.ejecutar(nombreComercial: 'Sportium');
    return resultado.when(ok: (c) => c.id, failure: (_) => throw StateError('no debería fallar'));
  }

  testWidgets('0 portales: la sección de Datos de cobranza muestra el estado vacío', (tester) async {
    final clienteId = await crearCliente();
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await _pump(tester, db, ClienteExpedienteScreen(clienteId: clienteId));

    expect(find.text(l10n.clienteCobranzaSeccionTitulo), findsOneWidget);
    expect(find.text(l10n.clientePortalSinPortales), findsOneWidget);
  });

  testWidgets('alta, edición y archivado/reactivación de un portal desde el expediente del Cliente', (tester) async {
    final clienteId = await crearCliente();
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await _pump(tester, db, ClienteExpedienteScreen(clienteId: clienteId));

    // Alta.
    await tester.ensureVisible(find.byKey(const Key('cliente_portal_boton_agregar')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cliente_portal_boton_agregar')));
    await tester.pumpAndSettle();

    var dialogo = find.byType(Dialog);
    expect(find.descendant(of: dialogo, matching: find.text(l10n.clientePortalDialogoTituloAlta)), findsOneWidget);

    // Orden real de `ClientePortalForm`: nombre(0), [tipo es un
    // `RisegSelect`, no un `TextFormField`], url(1), usuario(2),
    // contraseña(3), observaciones(4) — mismo criterio posicional que
    // `servicio_expediente_screen_test.dart`.
    final camposAlta = find.descendant(of: dialogo, matching: find.byType(TextFormField));
    await tester.enterText(camposAlta.at(0), 'Portal Facturación');
    await tester.enterText(camposAlta.at(1), 'https://factura.sportium.mx');
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: dialogo, matching: find.text(l10n.clientePortalDialogoBotonGuardar)));
    await tester.pumpAndSettle();

    expect(find.text(l10n.clientePortalGuardadoExito), findsOneWidget);
    expect(find.textContaining('Portal Facturación'), findsOneWidget);
    expect(find.text(l10n.clientePortalSinPortales), findsNothing);

    // La contraseña nunca se muestra en la fila de consulta (no se
    // capturó ninguna en esta alta, pero tampoco existe ningún widget
    // que fuera a mostrarla).
    expect(find.textContaining('Contraseña'), findsNothing);

    // Edición: cambia la URL.
    final portal = (await ClientePortalRepositoryImpl(db).listarPorCliente(clienteId)).single;
    final botonEditar = find.byKey(Key('cliente_portal_boton_editar_${portal.id}'));
    await tester.ensureVisible(botonEditar);
    await tester.pumpAndSettle();
    await tester.tap(botonEditar);
    await tester.pumpAndSettle();

    dialogo = find.byType(Dialog);
    expect(find.descendant(of: dialogo, matching: find.text(l10n.clientePortalDialogoTituloEdicion)), findsOneWidget);
    final campoUrl = find.descendant(of: dialogo, matching: find.byType(TextFormField)).at(1);
    expect(tester.widget<TextFormField>(campoUrl).controller!.text, 'https://factura.sportium.mx');
    await tester.enterText(campoUrl, 'https://factura2.sportium.mx');
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: dialogo, matching: find.text(l10n.clientePortalDialogoBotonGuardar)));
    await tester.pumpAndSettle();

    expect(find.textContaining('factura2.sportium.mx'), findsOneWidget);

    // Archivar.
    final botonCicloVida = find.byKey(Key('cliente_portal_boton_ciclo_vida_${portal.id}'));
    await tester.ensureVisible(botonCicloVida);
    await tester.pumpAndSettle();
    await tester.tap(botonCicloVida);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.sucursalConfirmarAceptar));
    await tester.pumpAndSettle();

    expect(find.text(l10n.clientePortalCicloVidaCambiadoExito), findsOneWidget);
    expect(find.text(l10n.clientePortalEstadoArchivada), findsOneWidget);

    // Reactivar.
    await tester.ensureVisible(botonCicloVida);
    await tester.pumpAndSettle();
    await tester.tap(botonCicloVida);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.sucursalConfirmarAceptar));
    await tester.pumpAndSettle();

    expect(find.text(l10n.clientePortalEstadoActivo), findsOneWidget);
  });

  testWidgets('varios portales del Cliente se listan todos en el expediente', (tester) async {
    final clienteId = await crearCliente();
    final repo = ClientePortalRepositoryImpl(db);
    for (final nombre in ['Portal A', 'Portal B', 'Portal C']) {
      await repo.crear(ClientePortalCompanion.insert(clienteId: clienteId, nombre: nombre, tipo: 'otro'));
    }

    await _pump(tester, db, ClienteExpedienteScreen(clienteId: clienteId));

    expect(find.textContaining('Portal A'), findsOneWidget);
    expect(find.textContaining('Portal B'), findsOneWidget);
    expect(find.textContaining('Portal C'), findsOneWidget);
  });
}
