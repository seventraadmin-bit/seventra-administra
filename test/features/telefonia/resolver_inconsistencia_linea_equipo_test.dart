// §32 / §33 — el recorrido REAL del caso que originó la Rebanada 2:
// expediente de la línea → advertencia → "Resolver inconsistencia" →
// motivo → confirmar, y verificar lo que quedó en la base.
//
// Por qué existe: en la etapa de Tiempo Extra todas las pruebas nuevas
// entraban por el caso de uso, y una prevalidación del diálogo bloqueó
// el flujo real sin que ninguna se enterara. Aquí se aprieta el botón.
//
// Incluye el barrido responsive de la UI nueva (§36).

import 'dart:io';

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
import 'package:riseg_one/features/inventario/inventario_providers.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart';
import 'package:riseg_one/features/telefonia/data/tables/linea_telefonica_table.dart';
import 'package:riseg_one/features/telefonia/presentation/linea_telefonica_expediente_screen.dart';
import 'package:riseg_one/features/telefonia/telefonia_providers.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

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

const _motivo = 'Regularización: el equipo ya estaba entregado a MILOYILE desde noviembre.';

void main() {
  late AppDatabase db;
  late Directory tempDir;
  late ProviderContainer container;
  late String lineaId;
  late String unidadId;
  late String servicioId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    tempDir = Directory.systemTemp.createTempSync('riseg_coherencia_test_');
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionMaestro.new),
        attachmentStorageProvider.overrideWithValue(AttachmentStorage(tempDir.path)),
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

    // --- El caso real, tal cual quedó en la base ---------------------
    final linea = await container.read(lineaTelefonicaRepositoryProvider).crear(
          codigo: 'LIN-000001',
          numero: '7291220187',
          operador: OperadorTelefonico.telcel.name,
          modalidadSim: ModalidadSim.fisica.name,
        );
    lineaId = linea.id;

    final tipoServicio = await db
        .into(db.tipoServicio)
        .insertReturning(TipoServicioCompanion.insert(id: 'tipo-1', codigo: 'VIG', nombre: 'Vigilancia fija'));
    final cliente = await db
        .into(db.cliente)
        .insertReturning(ClienteCompanion.insert(codigo: 'CLI-0001', nombreComercial: 'MILOYILE'));
    final servicio = await db.into(db.servicio).insertReturning(
          ServicioCompanion.insert(
            codigo: 'SER-000001',
            clienteId: cliente.id,
            nombre: 'MILOYILE',
            tipoServicioId: tipoServicio.id,
            fechaInicio: DateTime(2025, 1, 1),
          ),
        );
    servicioId = servicio.id;

    final categoria = await db
        .into(db.categoriaArticulo)
        .insertReturning(CategoriaArticuloCompanion.insert(nombre: 'Teléfonos'));
    final articulo = await db.into(db.articulo).insertReturning(
          ArticuloCompanion.insert(
            folio: 'ART-000001',
            categoriaId: categoria.id,
            nombre: 'Smartphone',
            manejaSerie: const Value(true),
          ),
        );
    final unidad = await db.into(db.articuloUnidad).insertReturning(
          ArticuloUnidadCompanion.insert(
            articuloId: articulo.id,
            codigo: 'UNI-000001',
            numeroSerie: 'SN-0001',
          ),
        );
    unidadId = unidad.id;
    await db.into(db.articuloUnidadTelefono).insert(
          ArticuloUnidadTelefonoCompanion.insert(unidadId: unidad.id, imei: const Value('351234567890123')),
        );

    // Inventario entregó el aparato a MILOYILE...
    await container.read(asignacionRepositoryProvider).crear(
          articuloId: articulo.id,
          unidadId: unidad.id,
          cantidad: 1,
          servicioId: servicio.id,
          fechaEntrega: DateTime(2025, 11, 1),
        );
    // ...y la línea quedó asociada pero SIN asignación: la incoherencia.
    await db.into(db.lineaTelefonicaEquipo).insert(
          LineaTelefonicaEquipoCompanion.insert(
            lineaTelefonicaId: linea.id,
            unidadId: unidad.id,
            fechaInicio: DateTime(2025, 11, 1),
          ),
        );
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Widget envolver({bool oscuro = false}) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: oscuro ? AppTheme.dark() : AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: LineaTelefonicaExpedienteScreen(lineaTelefonicaId: lineaId),
      ),
    );
  }

  void fijarTamano(WidgetTester tester, Size tamano) {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> abrirResolucion(WidgetTester tester) async {
    final boton = find.byKey(const Key('linea_boton_resolver_inconsistencia'));
    await tester.ensureVisible(boton);
    await tester.pumpAndSettle();
    await tester.tap(boton);
    await tester.pumpAndSettle();
  }

  testWidgets('§32 — el expediente muestra la advertencia con el destino real', (tester) async {
    fijarTamano(tester, const Size(1366, 900));
    await tester.pumpWidget(envolver());
    await tester.pumpAndSettle();
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    expect(tester.takeException(), isNull);
    expect(find.text(l10n.lineaTelefonicaCoherenciaEquipoCustodiado('MILOYILE')), findsOneWidget);
    expect(find.byKey(const Key('linea_boton_resolver_inconsistencia')), findsOneWidget);
  });

  testWidgets('§33 — advertencia → Resolver → motivo → confirmar: alinea la línea y NO toca Inventario', (tester) async {
    fijarTamano(tester, const Size(1366, 900));
    await tester.pumpWidget(envolver());
    await tester.pumpAndSettle();
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    final custodiaAntes = (await container.read(asignacionRepositoryProvider).obtenerActivaPorUnidad(unidadId))!;

    await abrirResolucion(tester);
    // El título del diálogo coincide con el rótulo del botón del
    // expediente, así que se busca el contenido propio del diálogo.
    expect(find.byKey(const Key('resolver_inconsistencia_campo_motivo')), findsOneWidget);
    expect(
      find.text(l10n.lineaTelefonicaResolverInconsistenciaAsignarLinea('MILOYILE')),
      findsOneWidget,
      reason: 'la única acción ofrecida toca la línea, no Inventario',
    );

    await tester.enterText(find.byKey(const Key('resolver_inconsistencia_campo_motivo')), _motivo);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(RisegButton, l10n.lineaTelefonicaResolverInconsistenciaConfirmar).last);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    // --- Lo que quedó en la base -----------------------------------
    final vigente = await container.read(asignacionLineaTelefonicaRepositoryProvider).obtenerActivaPorLinea(lineaId);
    expect(vigente, isNotNull, reason: 'el botón tiene que llegar a la base');
    expect(vigente!.servicioId, servicioId);
    expect(vigente.empleadoId, isNull);

    final custodiaDespues = (await container.read(asignacionRepositoryProvider).obtenerActivaPorUnidad(unidadId))!;
    expect(custodiaDespues.id, custodiaAntes.id, reason: 'la MISMA fila de Inventario: no se movió nada allí');

    final eventos = await container.read(lineaTelefonicaRepositoryProvider).listarEventos(lineaId);
    expect(eventos, hasLength(1));
    expect(eventos.single.tipoEvento, TipoEventoLineaTelefonica.incoherenciaResuelta.name);
    expect(eventos.single.observacion, _motivo);
    expect(eventos.single.actorUsuarioId, 'maestro', reason: '§22 — queda el actor');

    // La advertencia desaparece.
    await tester.pumpAndSettle();
    expect(find.text(l10n.lineaTelefonicaCoherenciaEquipoCustodiado('MILOYILE')), findsNothing);
    expect(find.byKey(const Key('linea_boton_resolver_inconsistencia')), findsNothing);
  });

  testWidgets('§22 — confirmar sin motivo no resuelve nada', (tester) async {
    fijarTamano(tester, const Size(1366, 900));
    await tester.pumpWidget(envolver());
    await tester.pumpAndSettle();
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await abrirResolucion(tester);
    await tester.tap(find.widgetWithText(RisegButton, l10n.lineaTelefonicaResolverInconsistenciaConfirmar).last);
    await tester.pumpAndSettle();

    expect(find.text(l10n.lineaTelefonicaCoherenciaMotivoRequerido), findsOneWidget);
    expect(await container.read(asignacionLineaTelefonicaRepositoryProvider).obtenerActivaPorLinea(lineaId), isNull);
    expect(await container.read(lineaTelefonicaRepositoryProvider).listarEventos(lineaId), isEmpty);
  });

  // ---------------------------------------------------------------
  // §36 — responsive de la UI nueva
  // ---------------------------------------------------------------
  for (final entrada in _anchos.entries) {
    for (final oscuro in [false, true]) {
      final tema = oscuro ? 'oscuro' : 'claro';

      testWidgets('Advertencia + botón de resolución (${entrada.key}, $tema): cero overflow', (tester) async {
        fijarTamano(tester, entrada.value);
        await tester.pumpWidget(envolver(oscuro: oscuro));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('linea_boton_resolver_inconsistencia')), findsOneWidget);
      });

      testWidgets('Diálogo Resolver inconsistencia (${entrada.key}, $tema): cero overflow', (tester) async {
        fijarTamano(tester, entrada.value);
        await tester.pumpWidget(envolver(oscuro: oscuro));
        await tester.pumpAndSettle();

        await abrirResolucion(tester);

        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('resolver_inconsistencia_campo_motivo')), findsOneWidget);
      });
    }
  }
}
