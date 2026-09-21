// Etapa 15 — reproducción exacta del caso real reportado: MIRABILIA
// tenía una CxC; se eliminó/canceló el flujo anterior (la CxC
// desapareció correctamente); se regeneró el documento y se llevó a
// Procesado/Aceptado; Agenda lo reflejó bien, pero Finanzas → Cuentas
// por cobrar (ya montada, sin cambiar de pestaña) NO mostró la CxC
// nueva — solo apareció al navegar a Pagos y volver.
//
// Esta prueba monta AMBAS pantallas simultáneamente dentro de un
// `IndexedStack` (el mismo mecanismo real que usa
// `StatefulShellRoute.indexedStack` para preservar las ramas del shell
// — Agenda y Finanzas nunca se desmontan al cambiar de rama) y NUNCA
// cambia el índice activo: si `cuentasPorCobrarControllerProvider` se
// actualiza solo porque el widget se reconstruye desde cero (como
// pasa realmente al cambiar de pestaña DENTRO de Finanzas, que no usa
// `IndexedStack` — ver `FinanzasShellScreen`), esta prueba lo
// detectaría como una falla real.

import 'package:drift/drift.dart' hide isNull, isNotNull, Column;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/presentation/cuentas_por_cobrar/cuentas_por_cobrar_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/cuentas_por_cobrar/cuentas_por_cobrar_list_screen.dart';
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

/// "Agenda" simplificada — solo lo necesario para abrir el expediente
/// del documento antiguo o el nuevo, sin la maquinaria completa de
/// listado/filtros (ajena a lo que esta prueba investiga).
class _AgendaDePrueba extends StatelessWidget {
  const _AgendaDePrueba({required this.documentoAntiguoId, required this.documentoNuevoId});

  final String documentoAntiguoId;
  final String documentoNuevoId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          ElevatedButton(
            key: const Key('abrir_documento_antiguo'),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => AgendaDetalleDialog(documentoPorEmitirId: documentoAntiguoId),
            ),
            child: const Text('abrir antiguo'),
          ),
          ElevatedButton(
            key: const Key('abrir_documento_nuevo'),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => AgendaDetalleDialog(documentoPorEmitirId: documentoNuevoId),
            ),
            child: const Text('abrir nuevo'),
          ),
        ],
      ),
    );
  }
}

void main() {
  late AppDatabase db;
  late String clienteId;
  late String documentoAntiguoId;
  late String documentoNuevoId;

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

    final clienteRepo = ClienteRepositoryImpl(db);
    final cliente = await clienteRepo.crear(ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'MIRABILIA'));
    clienteId = cliente.id;

    // El documento/CxC "anterior" — el que se elimina en el primer
    // paso del caso real.
    final documentoAntiguo = await db.into(db.documentoPorEmitir).insertReturning(
          DocumentoPorEmitirCompanion.insert(
            codigo: 'DOC-M001',
            clienteId: clienteId,
            tipoDocumento: 'reciboDePago',
            agrupacion: 'porServicio',
            metodo: 'noAplica',
            periodoInicio: DateTime(2026, 1, 1),
            periodoFin: DateTime(2026, 1, 31),
            generationKey: 'GK-DOC-M001',
            importeBaseEsperado: 3400000,
            importeFinalEsperado: 3400000,
            estatus: const Value('procesadoAceptado'),
          ),
        );
    documentoAntiguoId = documentoAntiguo.id;
    await db.into(db.cuentaPorCobrar).insert(
          CuentaPorCobrarCompanion.insert(
            documentoPorEmitirId: Value(documentoAntiguoId),
            clienteId: Value(clienteId),
            tipoDocumento: 'reciboDePago',
            metodo: 'noAplica',
            fechaEmisionReal: DateTime(2026, 1, 5),
            importeEmitido: 3400000,
            saldoOriginal: 3400000,
            saldoPendiente: 3400000,
          ),
        );

    // El documento "regenerado" — ya en `Emitido`, listo para marcarse
    // Procesado/Aceptado igual que en el caso real (mismo período,
    // mismo cliente, otro folio — una regeneración real genera un id
    // nuevo).
    final documentoNuevo = await db.into(db.documentoPorEmitir).insertReturning(
          DocumentoPorEmitirCompanion.insert(
            codigo: 'DOC-M002',
            clienteId: clienteId,
            tipoDocumento: 'reciboDePago',
            agrupacion: 'porServicio',
            metodo: 'noAplica',
            periodoInicio: DateTime(2026, 2, 1),
            periodoFin: DateTime(2026, 2, 28),
            generationKey: 'GK-DOC-M002',
            importeBaseEsperado: 3400000,
            importeFinalEsperado: 3400000,
            estatus: const Value('emitido'),
            folioDocumento: const Value('F-0002'),
            fechaEmisionReal: Value(DateTime(2026, 2, 5)),
            importeEmitido: const Value(3400000),
          ),
        );
    documentoNuevoId = documentoNuevo.id;
  });

  tearDown(() => db.close());

  testWidgets(
    'CxC existente → eliminar origen → CxC desaparece → regenerar documento → Procesado/Aceptado → '
    'sin cambiar de pestaña, el listado de CxC muestra la cuenta nueva',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          sesionControllerProvider.overrideWith(_SesionMaestroDePrueba.new),
          attachmentStorageProvider.overrideWithValue(AttachmentStorage('.')),
        ],
      );
      addTearDown(container.dispose);
      container.listen(cuentasPorCobrarControllerProvider, (_, _) {});

      // El mismo mecanismo real que preserva las ramas del shell
      // (`StatefulShellRoute.indexedStack`): ambas pantallas montadas
      // a la vez, el índice activo NUNCA cambia durante la prueba —
      // Finanzas → Cuentas por cobrar queda "en segundo plano" todo
      // el tiempo, igual que en el caso real.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: IndexedStack(
                index: 0,
                children: [
                  _AgendaDePrueba(documentoAntiguoId: documentoAntiguoId, documentoNuevoId: documentoNuevoId),
                  const CuentasPorCobrarListScreen(),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      while (container.read(cuentasPorCobrarControllerProvider).cargando) {
        await tester.pump();
      }
      expect(
        container.read(cuentasPorCobrarControllerProvider).cuentas.map((c) => c.documentoPorEmitirId),
        contains(documentoAntiguoId),
        reason: 'la CxC antigua debe estar visible al inicio',
      );

      // --- Paso 1: eliminar físicamente el documento/CxC anterior ---
      await tester.tap(find.byKey(const Key('abrir_documento_antiguo')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('agenda_detalle_menu_acciones')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.eliminacionFisicaAccionMenu).last);
      await tester.pumpAndSettle();
      final campoMotivo = find.descendant(
        of: find.widgetWithText(RisegTextField, l10n.eliminacionFisicaCampoMotivo),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(campoMotivo, 'Prueba: limpiar CxC anterior');
      await tester.tap(find.text(l10n.eliminacionFisicaBotonConfirmar));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      while (container.read(cuentasPorCobrarControllerProvider).cargando) {
        await tester.pump();
      }
      expect(
        container.read(cuentasPorCobrarControllerProvider).cuentas.map((c) => c.documentoPorEmitirId),
        isNot(contains(documentoAntiguoId)),
        reason: 'la CxC anterior debe desaparecer de inmediato tras eliminar su Documento',
      );

      // --- Paso 2: "regenerar" ya está hecho en el setUp (documento
      // nuevo en Emitido) — llevarlo a Procesado/Aceptado, igual que
      // el caso real (Emitido → Procesado/Aceptado omitiendo Envío).
      await tester.tap(find.byKey(const Key('abrir_documento_nuevo')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(l10n.agendaDetalleBotonMarcarProcesadoAceptado));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.agendaDetalleBotonMarcarProcesadoAceptado));
      await tester.pumpAndSettle();
      // Confirmación explícita de "omitir envío" (Resolución 5 de Marlon).
      await tester.tap(find.text(l10n.agendaDetalleOmitirEnvioConfirmacionConfirmar));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // El diálogo del documento nuevo sigue abierto (nunca se cerró
      // ni se cambió de pestaña) — exactamente el escenario real.
      expect(find.text(l10n.agendaEstatusProcesadoAceptado), findsWidgets);

      while (container.read(cuentasPorCobrarControllerProvider).cargando) {
        await tester.pump();
      }
      final cuentas = container.read(cuentasPorCobrarControllerProvider).cuentas;
      expect(
        cuentas.map((c) => c.documentoPorEmitirId),
        contains(documentoNuevoId),
        reason: 'la CxC nueva debe aparecer de inmediato en el listado ya montado, sin cambiar de pestaña',
      );
    },
  );
}
