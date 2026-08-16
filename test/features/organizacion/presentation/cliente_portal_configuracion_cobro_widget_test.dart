// Pruebas de widget del portal del Cliente y del selector múltiple de
// correos dentro de Configuración de cobro (Etapa 15, ClientePortal) —
// verifica los 5 escenarios de UI pedidos explícitamente por Marlon:
// Cliente con 0/1/varios portales activos, selector múltiple de
// correos de Contacto, y correo manual extraordinario como opción
// secundaria. La migración/cifrado/Agenda se cubren aparte en
// `cliente_portal_test.dart` (no requieren UI real).

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
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/di/providers.dart';

import 'package:riseg_one/features/organizacion/data/repositories/cliente_portal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/cliente_portal_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_cliente_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_servicio_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/presentation/servicios/servicio_expediente_screen.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
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

  /// Cliente + Servicio reales, listos para abrir el diálogo de alta de
  /// Configuración de cobro. `portales` se crean directo por el
  /// repositorio (sin `CrearClientePortalUseCase`/`CredentialCipher` —
  /// estas pruebas no ejercitan contraseñas, así que evitan la
  /// dependencia de `flutter_secure_storage`, que no responde bajo
  /// `flutter test`).
  Future<String> crearServicioConPortalesYContactos({
    required List<({String nombre, String? tipo, String? url, String? usuario})> portales,
    required List<({String nombre, String? puesto, String? correo})> contactos,
  }) async {
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    final clienteRepo = ClienteRepositoryImpl(db);
    final servicioRepo = ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db));
    final catalogoRepo = CatalogoRepositoryImpl(db);
    final clientePortalRepo = ClientePortalRepositoryImpl(db);

    final crearCliente = CrearClienteUseCase(clienteRepo, generarCodigo);
    final cliente = await crearCliente.ejecutar(nombreComercial: 'Sportium');
    final clienteId = cliente.when(ok: (c) => c.id, failure: (_) => throw StateError('no debería fallar'));

    for (final p in portales) {
      await clientePortalRepo.crear(
        ClientePortalCompanion.insert(
          clienteId: clienteId,
          nombre: p.nombre,
          tipo: p.tipo ?? TipoPortalCliente.otro.name,
          url: Value(p.url),
          usuario: Value(p.usuario),
        ),
      );
    }

    for (final c in contactos) {
      await clienteRepo.agregarContacto(
        ContactoCompanion.insert(clienteId: clienteId, nombre: c.nombre, tipo: 'comercial', puesto: Value(c.puesto), correo: Value(c.correo)),
      );
    }

    final crearServicio = CrearServicioUseCase(servicioRepo, generarCodigo, ServicioValidator(clienteRepo, catalogoRepo));
    final creado = await crearServicio.ejecutar(
      clienteId: clienteId,
      borrador: ServicioBorrador(
        nombre: 'Club Sportium Toluca',
        tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
        fechaInicio: DateTime(2026, 1, 1),
      ),
    );
    return (creado as GuardarServicioExitoso).servicio.id;
  }

  Future<Finder> abrirDialogoAltaCobro(WidgetTester tester, String servicioId) async {
    await _pump(tester, db, ServicioExpedienteScreen(servicioId: servicioId));
    await tester.ensureVisible(find.byKey(const Key('servicio_boton_agregar_configuracion_cobro')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('servicio_boton_agregar_configuracion_cobro')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    return find.byType(Dialog);
  }

  testWidgets('Cliente sin portales: el diálogo muestra "Sin portal configurado", sin selector', (tester) async {
    final servicioId = await crearServicioConPortalesYContactos(portales: const [], contactos: const []);
    final dialogo = await abrirDialogoAltaCobro(tester, servicioId);

    expect(find.descendant(of: dialogo, matching: find.byKey(const Key('servicio_cobro_sin_portal'))), findsOneWidget);
    expect(find.descendant(of: dialogo, matching: find.byKey(const Key('servicio_cobro_portal_unico'))), findsNothing);
    expect(find.descendant(of: dialogo, matching: find.byKey(const Key('servicio_cobro_selector_portal'))), findsNothing);
  });

  testWidgets('Cliente con exactamente 1 portal activo: se preselecciona automáticamente, sin selector', (tester) async {
    final servicioId = await crearServicioConPortalesYContactos(
      portales: const [(nombre: 'Portal SIPOT', tipo: 'facturacion', url: 'https://sipot.example.com', usuario: 'sportium')],
      contactos: const [],
    );
    final dialogo = await abrirDialogoAltaCobro(tester, servicioId);

    expect(find.descendant(of: dialogo, matching: find.byKey(const Key('servicio_cobro_portal_unico'))), findsOneWidget);
    expect(find.descendant(of: dialogo, matching: find.textContaining('Portal SIPOT')), findsOneWidget);
    expect(find.descendant(of: dialogo, matching: find.byKey(const Key('servicio_cobro_selector_portal'))), findsNothing);
    expect(find.descendant(of: dialogo, matching: find.byKey(const Key('servicio_cobro_sin_portal'))), findsNothing);
    // La URL/usuario se muestran para distinguirlo, nunca una contraseña.
    expect(find.descendant(of: dialogo, matching: find.textContaining('sipot.example.com')), findsOneWidget);
  });

  testWidgets('Cliente con 2+ portales activos: selector visible, con suficiente información para distinguirlos', (tester) async {
    final servicioId = await crearServicioConPortalesYContactos(
      portales: const [
        (nombre: 'Portal Facturación', tipo: 'facturacion', url: 'https://factura.example.com', usuario: 'user1'),
        (nombre: 'Portal Pagos', tipo: 'pagos', url: 'https://pagos.example.com', usuario: 'user2'),
      ],
      contactos: const [],
    );
    final dialogo = await abrirDialogoAltaCobro(tester, servicioId);

    expect(find.descendant(of: dialogo, matching: find.byKey(const Key('servicio_cobro_selector_portal'))), findsOneWidget);
    expect(find.descendant(of: dialogo, matching: find.byKey(const Key('servicio_cobro_portal_unico'))), findsNothing);

    final selector = find.descendant(of: dialogo, matching: find.byKey(const Key('servicio_cobro_selector_portal')));
    await tester.ensureVisible(selector);
    await tester.pumpAndSettle();
    await tester.tap(selector);
    await tester.pumpAndSettle();
    expect(find.textContaining('Portal Facturación'), findsWidgets);
    expect(find.textContaining('Portal Pagos'), findsWidgets);
  });

  testWidgets('Selector múltiple de correos: los Contactos con correo aparecen como opciones marcables', (tester) async {
    final servicioId = await crearServicioConPortalesYContactos(
      portales: const [],
      contactos: const [
        (nombre: 'Ana Ruiz', puesto: 'Contadora', correo: 'ana.ruiz@sportium.mx'),
        (nombre: 'Luis Pérez', puesto: null, correo: 'luis.perez@sportium.mx'),
        (nombre: 'Sin correo', puesto: 'Gerente', correo: null),
      ],
    );
    final dialogo = await abrirDialogoAltaCobro(tester, servicioId);

    // Solo los 2 contactos con correo aparecen — "Sin correo" queda
    // fuera del selector (nunca se ofrece un correo inexistente).
    expect(find.descendant(of: dialogo, matching: find.textContaining('Ana Ruiz')), findsOneWidget);
    expect(find.descendant(of: dialogo, matching: find.text('ana.ruiz@sportium.mx')), findsOneWidget);
    expect(find.descendant(of: dialogo, matching: find.textContaining('Luis Pérez')), findsOneWidget);
    expect(find.descendant(of: dialogo, matching: find.text('luis.perez@sportium.mx')), findsOneWidget);
    expect(find.descendant(of: dialogo, matching: find.widgetWithText(CheckboxListTile, 'Sin correo')), findsNothing);

    // Antes de marcar nada, la lista de seleccionados está vacía.
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));
    expect(find.descendant(of: dialogo, matching: find.text(l10n.servicioCobroSinCorreos)), findsOneWidget);

    // Marcar el checkbox de Ana Ruiz (ubicado por su correo, sin
    // adivinar su id generado) agrega su correo a la lista de
    // seleccionados (mostrada abajo, con su propio botón de quitar) —
    // nunca se vuelve a pedir escribirlo a mano.
    final filaAna = find.ancestor(
      of: find.text('ana.ruiz@sportium.mx'),
      matching: find.byType(CheckboxListTile),
    );
    await tester.ensureVisible(filaAna);
    await tester.pumpAndSettle();
    await tester.tap(filaAna);
    await tester.pumpAndSettle();
    expect(find.descendant(of: dialogo, matching: find.text(l10n.servicioCobroSinCorreos)), findsNothing);
    expect(find.descendant(of: dialogo, matching: find.text('ana.ruiz@sportium.mx')), findsWidgets);
  });

  testWidgets('Correo manual extraordinario: "Agregar otro correo" añade uno que no está registrado como Contacto', (tester) async {
    final servicioId = await crearServicioConPortalesYContactos(portales: const [], contactos: const []);
    final dialogo = await abrirDialogoAltaCobro(tester, servicioId);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    expect(find.descendant(of: dialogo, matching: find.text(l10n.servicioCobroCampoOtroCorreoTitulo)), findsOneWidget);

    await tester.enterText(
      find.descendant(of: dialogo, matching: find.byKey(const Key('servicio_cobro_campo_otro_correo'))),
      'facturacion.extra@sportium.mx',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: dialogo, matching: find.byKey(const Key('servicio_cobro_boton_agregar_otro_correo'))));
    await tester.pumpAndSettle();

    expect(find.descendant(of: dialogo, matching: find.text('facturacion.extra@sportium.mx')), findsOneWidget);
    expect(find.descendant(of: dialogo, matching: find.text(l10n.servicioCobroSinCorreos)), findsNothing);
  });
}
