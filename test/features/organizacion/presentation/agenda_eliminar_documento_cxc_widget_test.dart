// Etapa 15 — reproducción real del caso pedido: eliminar físicamente
// un Documento por emitir (Maestro) borra su Cuenta por cobrar en la
// misma transacción, pero el listado de Finanzas → Cuentas por cobrar
// es un provider aparte (`cuentasPorCobrarControllerProvider`) que solo
// se entera si `agenda_detalle_dialog.dart._eliminarFisicamente` lo
// invalida explícitamente. Esta prueba ejercita el flujo real de UI
// (tap en el menú ⋮, capturar motivo, confirmar) contra el mismo
// `ProviderContainer` que ya está "escuchando" el listado — igual que
// una pestaña abierta en segundo plano — para probar el camino real,
// no solo el backend.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/finanzas/presentation/cuentas_por_cobrar/cuentas_por_cobrar_controller.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart' show attachmentStorageProvider;
import 'package:riseg_one/features/organizacion/presentation/agenda/widgets/agenda_detalle_dialog.dart';
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

void main() {
  late AppDatabase db;
  late String documentoId;
  late String clienteId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    // `EliminacionFisicaEvento.actorUsuarioId` es una FK real hacia
    // `Usuario` — debe existir de antemano o la eliminación física
    // falla con `ErrorInesperado` (silencioso: la CxC nunca se borra,
    // y por eso tampoco se invalida el listado).
    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(
            id: const Value('usuario-maestro'),
            nombre: 'Maestro de prueba',
            nombreUsuario: 'maestro',
            passwordHash: 'x',
            esMaestro: const Value(true),
          ),
        );
    final clienteRepo = ClienteRepositoryImpl(db);
    final cliente = await clienteRepo.crear(ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'TIKAL II'));
    clienteId = cliente.id;

    final documento = await db.into(db.documentoPorEmitir).insertReturning(
          DocumentoPorEmitirCompanion.insert(
            codigo: 'DOC-P900',
            clienteId: clienteId,
            tipoDocumento: 'reciboDePago',
            agrupacion: 'porServicio',
            metodo: 'noAplica',
            periodoInicio: DateTime(2026, 1, 1),
            periodoFin: DateTime(2026, 1, 31),
            generationKey: 'GK-DOC-P900',
            importeBaseEsperado: 3400000,
            importeFinalEsperado: 3400000,
            estatus: const Value('procesadoAceptado'),
          ),
        );
    documentoId = documento.id;

    // CxC sin pagos aplicados — elegible para eliminación física.
    await db.into(db.cuentaPorCobrar).insert(
          CuentaPorCobrarCompanion.insert(
            documentoPorEmitirId: Value(documentoId),
            clienteId: Value(clienteId),
            tipoDocumento: 'reciboDePago',
            metodo: 'noAplica',
            fechaEmisionReal: DateTime(2026, 1, 5),
            importeEmitido: 3400000,
            saldoOriginal: 3400000,
            saldoPendiente: 3400000,
          ),
        );
  });

  tearDown(() => db.close());

  testWidgets(
    'eliminar físicamente el Documento desde su diálogo de detalle invalida cuentasPorCobrarControllerProvider — '
    'la CxC desaparece de inmediato del listado, sin cambiar de pestaña',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          sesionControllerProvider.overrideWith(_SesionMaestroDePrueba.new),
          attachmentStorageProvider.overrideWithValue(AttachmentStorage('.')),
        ],
      );
      addTearDown(container.dispose);

      // El listado de Cuentas por cobrar ya estaba "abierto" (mismo
      // `container`, provider vivo) ANTES de abrir el diálogo y
      // eliminar el documento — el escenario real reportado (una
      // pestaña de Finanzas en segundo plano).
      container.listen(cuentasPorCobrarControllerProvider, (_, _) {});
      // Dentro de `testWidgets` el reloj es falso (`FakeAsync`) — hay
      // que avanzarlo con `tester.pump()`, nunca con un `Future.delayed`
      // crudo (eso nunca se resuelve aquí y cuelga la prueba).
      while (container.read(cuentasPorCobrarControllerProvider).cargando) {
        await tester.pump();
      }
      expect(container.read(cuentasPorCobrarControllerProvider).cuentas, hasLength(1));

      // `AgendaDetalleDialog._eliminarFisicamente` termina con
      // `Navigator.of(context).pop()` — necesita una ruta real de
      // diálogo debajo (como en el uso real, `showDialog`), nunca
      // colocarse directo como `home`, o ese `pop()` intenta cerrar la
      // app entera.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => AgendaDetalleDialog(documentoPorEmitirId: documentoId),
                    ),
                    child: const Text('abrir'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('agenda_detalle_menu_acciones')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.eliminacionFisicaAccionMenu).last);
      await tester.pumpAndSettle();

      final campoMotivo = find.descendant(
        of: find.widgetWithText(RisegTextField, l10n.eliminacionFisicaCampoMotivo),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(campoMotivo, 'Prueba de limpieza');
      await tester.tap(find.text(l10n.eliminacionFisicaBotonConfirmar));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      while (container.read(cuentasPorCobrarControllerProvider).cargando) {
        await tester.pump();
      }
      expect(
        container.read(cuentasPorCobrarControllerProvider).cuentas,
        isEmpty,
        reason: 'la CxC eliminada junto con el Documento debe desaparecer de inmediato, sin recargar manualmente',
      );
    },
  );
}
