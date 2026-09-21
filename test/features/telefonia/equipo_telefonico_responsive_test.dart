// §21 de la Rebanada 3 — el barrido responsive que le faltaba al
// frente de Equipos: el listado y el expediente, con datos hostiles al
// layout (marca+modelo largos, IMEI de 15 dígitos, custodia con nombre
// largo y línea asociada).
//
// Mismo criterio de evidencia que el resto de RISEG ONE: sin
// herramienta de captura, la prueba es "cero overflow / cero excepción"
// (`tester.takeException()`), nunca comparación de píxeles.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/telefonia/data/tables/linea_telefonica_table.dart';
import 'package:riseg_one/features/telefonia/presentation/equipo_telefonico_expediente_screen.dart';
import 'package:riseg_one/features/telefonia/presentation/equipos_telefonicos_list_screen.dart';
import 'package:riseg_one/features/telefonia/telefonia_providers.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import 'package:riseg_one/features/inventario/inventario_providers.dart';

class _SesionMaestro extends SesionController {
  @override
  SesionUsuario? build() => const SesionUsuario(
        usuarioId: 'maestro',
        nombre: 'Maestro de prueba',
        nombreUsuario: 'maestro',
        esMaestro: true,
        permisos: {},
      );
}

const _anchos = <String, Size>{
  '1536': Size(1536, 1000),
  '1366': Size(1366, 900),
  '1024': Size(1024, 900),
  '700': Size(700, 900),
  '500': Size(500, 900),
};

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late String unidadId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionMaestro.new),
      ],
    );
    addTearDown(container.dispose);

    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(
            id: const Value('maestro'),
            nombre: 'Maestro de prueba',
            nombreUsuario: 'maestro',
            passwordHash: r'pbkdf2$1$c2FsdA==$aGFzaA==',
            esMaestro: const Value(true),
          ),
        );

    final categoria =
        await db.into(db.categoriaArticulo).insertReturning(CategoriaArticuloCompanion.insert(nombre: 'Teléfonos'));
    final articulo = await db.into(db.articulo).insertReturning(
          ArticuloCompanion.insert(
            folio: 'ART-000001',
            categoriaId: categoria.id,
            nombre: 'Smartphone corporativo de gama media con batería extendida',
            manejaSerie: const Value(true),
          ),
        );
    final unidad = await db.into(db.articuloUnidad).insertReturning(
          ArticuloUnidadCompanion.insert(
            articuloId: articulo.id,
            codigo: 'UNI-000001',
            numeroSerie: 'SN-0001-XYZ-LARGO-DE-VERDAD',
            marca: const Value('Xiaomi Communications Co. Ltd.'),
            modelo: const Value('Redmi Note 13 Pro Plus 5G Edición Especial'),
          ),
        );
    unidadId = unidad.id;
    await db.into(db.articuloUnidadTelefono).insert(
          ArticuloUnidadTelefonoCompanion.insert(
            unidadId: unidad.id,
            imei: const Value('351234567890123'),
            imei2: const Value('351234567890124'),
          ),
        );

    // Custodia de un Servicio de nombre largo, y su línea asociada — el
    // caso en que conviven "Custodia" y "Línea actual" en la misma card.
    final tipoServicio = await db
        .into(db.tipoServicio)
        .insertReturning(TipoServicioCompanion.insert(id: 'tipo-1', codigo: 'VIG', nombre: 'Vigilancia fija'));
    final cliente = await db.into(db.cliente).insertReturning(
        ClienteCompanion.insert(codigo: 'CLI-0001', nombreComercial: 'Corporativo Inmobiliario MILOYILE S.A. de C.V.'));
    final servicio = await db.into(db.servicio).insertReturning(
          ServicioCompanion.insert(
            codigo: 'SER-000001',
            clienteId: cliente.id,
            nombre: 'Vigilancia intramuros MILOYILE Torre Norte turno nocturno',
            tipoServicioId: tipoServicio.id,
            fechaInicio: DateTime(2026, 1, 1),
          ),
        );
    await container.read(asignacionRepositoryProvider).crear(
          articuloId: articulo.id,
          unidadId: unidad.id,
          cantidad: 1,
          servicioId: servicio.id,
          fechaEntrega: DateTime(2026, 1, 1),
        );

    final linea = await container.read(lineaTelefonicaRepositoryProvider).crear(
          codigo: 'LIN-000001',
          numero: '7291220187',
          operador: OperadorTelefonico.otro.name,
          operadorOtroNombre: 'Operador Virtual Empresarial de Cobertura Nacional S.A. de C.V.',
          modalidadSim: ModalidadSim.fisica.name,
          iccid: '8952140061234567890',
        );
    await container.read(asociarEquipoLineaTelefonicaUseCaseProvider).ejecutar(
          lineaTelefonicaId: linea.id,
          unidadId: unidad.id,
          fechaInicio: DateTime(2026, 1, 2),
          alinearLineaConCustodia: true,
        );
  });

  tearDown(() => db.close());

  Widget envolver({required bool oscuro, required Widget child}) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: oscuro ? AppTheme.dark() : AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    );
  }

  void fijarTamano(WidgetTester tester, Size tamano) {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  for (final entrada in _anchos.entries) {
    for (final oscuro in [false, true]) {
      final tema = oscuro ? 'oscuro' : 'claro';

      testWidgets('Listado de equipos (${entrada.key}, $tema): cero overflow', (tester) async {
        fijarTamano(tester, entrada.value);
        await tester.pumpWidget(envolver(oscuro: oscuro, child: const Scaffold(body: EquiposTelefonicosListScreen())));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });

      testWidgets('Expediente de equipo (${entrada.key}, $tema): cero overflow', (tester) async {
        fijarTamano(tester, entrada.value);
        await tester.pumpWidget(envolver(oscuro: oscuro, child: EquipoTelefonicoExpedienteScreen(unidadId: unidadId)));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('el encabezado de custodia dice "Custodia", no "Asignado a" (§18)', (tester) async {
    fijarTamano(tester, const Size(1366, 900));
    await tester.pumpWidget(envolver(oscuro: false, child: const Scaffold(body: EquiposTelefonicosListScreen())));
    await tester.pumpAndSettle();
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    expect(l10n.equiposTelefonicosColumnaAsignadoA, 'Custodia',
        reason: 'en el listado de Equipos lo que se muestra es la custodia de Inventario');
    expect(find.text('Custodia'), findsOneWidget);
  });

  testWidgets('las secciones históricas vacías no ocupan media pantalla (§12)', (tester) async {
    fijarTamano(tester, const Size(1366, 900));
    await tester.pumpWidget(envolver(oscuro: false, child: EquipoTelefonicoExpedienteScreen(unidadId: unidadId)));
    await tester.pumpAndSettle();
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    // Sin descuentos ni eventos: una línea de texto, nunca una tabla
    // vacía con su estado grande.
    expect(find.text(l10n.equipoTelefonicoHistoriaDescuentosVacio), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
