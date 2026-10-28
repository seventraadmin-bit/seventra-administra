// Etapa 15 — reproducción real del bug reportado: cuando un Documento
// por emitir pasa a Procesado/Aceptado, `DocumentoPorEmitirRepositoryImpl.
// cambiarEstatus` crea su Cuenta por cobrar en la misma transacción
// (Etapa 4J.1), pero `AgendaController.cambiarEstatus` nunca invalidaba
// `cuentasPorCobrarControllerProvider` — el listado de Finanzas →
// Cuentas por cobrar no mostraba la CxC nueva hasta cambiar de pestaña.
// Corregido: la invalidación ahora vive en `AgendaController.cambiarEstatus`
// mismo (el único punto que genera CxC nuevas), condicionada a la
// transición real, nunca una recarga global en cualquier cambio de
// estatus.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/dashboard/presentation/dashboard_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/cuentas_por_cobrar/cuentas_por_cobrar_controller.dart';
import 'package:riseg_one/features/organizacion/data/tables/documento_por_emitir_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_estatus_documento_por_emitir_usecase.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart';
import 'package:riseg_one/features/organizacion/presentation/agenda/agenda_controller.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import '../../../support/sesion_en_base.dart';

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
  late ProviderContainer container;
  late String documentoId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());

    // Las mutaciones de Agenda registran al actor con FK real contra
    // `usuario`: la cuenta de la sesión de prueba tiene que existir.
    await db.into(db.usuario).insert(
      UsuarioCompanion.insert(
        id: const Value('usuario-maestro'),
        nombre: 'Maestro de prueba',
        nombreUsuario: 'maestro',
        passwordHash: 'x',
      ),
    );
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionMaestroDePrueba.new),
        // `documentoPorEmitirRepositoryProvider` depende de
        // `attachmentStorageProvider` (Etapa 15, eliminación física
        // ampliada) — se sobreescribe directo para no necesitar
        // `appPathsProvider` (requiere `path_provider`, no disponible
        // en pruebas); esta prueba nunca ejercita borrado de archivos.
        attachmentStorageProvider.overrideWithValue(AttachmentStorage('.')),
      ],
    );
    addTearDown(container.dispose);

    final cliente = await container.read(clienteRepositoryProvider).crear(
          ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'TIKAL II'),
        );

    // Documento ya `Emitido` — datos definitivos ya capturados
    // (`fechaEmisionReal`/`importeEmitido`), listo para transicionar
    // directo a `procesadoAceptado` sin pasar por el resto del
    // pipeline de generación (Servicio/Línea comercial), ajeno a lo
    // que esta prueba investiga.
    final documento = await db.into(db.documentoPorEmitir).insertReturning(
          DocumentoPorEmitirCompanion.insert(
            codigo: 'DOC-P900',
            clienteId: cliente.id,
            tipoDocumento: 'reciboDePago',
            agrupacion: 'porServicio',
            metodo: 'noAplica',
            periodoInicio: DateTime(2026, 1, 1),
            periodoFin: DateTime(2026, 1, 31),
            generationKey: 'GK-DOC-P900',
            importeBaseEsperado: 3400000,
            importeFinalEsperado: 3400000,
            estatus: const Value('emitido'),
            folioDocumento: const Value('F-0001'),
            fechaEmisionReal: Value(DateTime(2026, 1, 5)),
            importeEmitido: const Value(3400000),
          ),
        );
    documentoId = documento.id;
    // Etapa 3B: autorizar revalida contra la base, así que la
    // sesión de esta prueba tiene que corresponder a una cuenta real.
    await sembrarSesionEnBase(db, const SesionUsuario( usuarioId: 'usuario-maestro', nombre: 'Maestro de prueba', nombreUsuario: 'maestro', esMaestro: true, permisos: {}, ));
  });

  tearDown(() => db.close());

  Future<void> esperarCargaCuentas() async {
    container.listen(cuentasPorCobrarControllerProvider, (_, _) {});
    while (container.read(cuentasPorCobrarControllerProvider).cargando) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test(
    'transicionar el Documento a Procesado/Aceptado crea la CxC y el listado la refleja de inmediato, '
    'sin cambiar de pestaña ni recargar manualmente',
    () async {
      // El listado de Cuentas por cobrar ya estaba "abierto" (provider
      // vivo) ANTES de la transición — el escenario real reportado.
      await esperarCargaCuentas();
      expect(container.read(cuentasPorCobrarControllerProvider).cuentas, isEmpty, reason: 'todavía no existe ninguna CxC');

      final resultado = await container.read(agendaControllerProvider.notifier).cambiarEstatus(
            documentoPorEmitirId: documentoId,
            nuevo: EstatusDocumentoPorEmitir.procesadoAceptado,
          );
      expect(resultado, isA<CambiarEstatusDocumentoPorEmitirExitoso>());

      // Sin ningún `recargar()`/`invalidate` manual desde la prueba —
      // el propio `AgendaController.cambiarEstatus` debe haber
      // invalidado `cuentasPorCobrarControllerProvider`.
      await Future<void>.delayed(Duration.zero);
      await esperarCargaCuentas();

      final cuentas = container.read(cuentasPorCobrarControllerProvider).cuentas;
      expect(cuentas, hasLength(1), reason: 'la CxC nueva debe aparecer de inmediato');
      expect(cuentas.single.documentoPorEmitirId, documentoId);
      expect(cuentas.single.saldoPendiente, 3400000);
      expect(cuentas.single.estatus, 'pendiente');
    },
  );

  test('una transición que NO crea CxC (ej. pendiente → cancelado) nunca invalida el listado sin necesidad', () async {
    final otroDocumento = await db.into(db.documentoPorEmitir).insertReturning(
          DocumentoPorEmitirCompanion.insert(
            codigo: 'DOC-P901',
            clienteId: (await db.select(db.cliente).getSingle()).id,
            tipoDocumento: 'reciboDePago',
            agrupacion: 'porServicio',
            metodo: 'noAplica',
            periodoInicio: DateTime(2026, 1, 1),
            periodoFin: DateTime(2026, 1, 31),
            generationKey: 'GK-DOC-P901',
            importeBaseEsperado: 100000,
            importeFinalEsperado: 100000,
            estatus: const Value('pendiente'),
          ),
        );

    await esperarCargaCuentas();

    final resultado = await container.read(agendaControllerProvider.notifier).cambiarEstatus(
          documentoPorEmitirId: otroDocumento.id,
          nuevo: EstatusDocumentoPorEmitir.cancelado,
          motivo: 'Prueba',
        );
    expect(resultado, isA<CambiarEstatusDocumentoPorEmitirExitoso>());

    // No se generó ninguna CxC — el listado sigue vacío, sin necesidad
    // de haberse invalidado (comportamiento correcto, no solo casual).
    expect(container.read(cuentasPorCobrarControllerProvider).cuentas, isEmpty);
  });

  test(
    'Etapa 20 — hueco real corregido: la misma transición también invalida el Dashboard '
    '(Cobranza/"Requiere atención" leen la misma CuentaPorCobrar)',
    () async {
      container.listen(dashboardControllerProvider, (_, _) {});
      while (container.read(dashboardControllerProvider).cargando) {
        await Future<void>.delayed(Duration.zero);
      }
      var reconstrucciones = 0;
      container.listen(dashboardControllerProvider, (_, _) => reconstrucciones++);

      final resultado = await container.read(agendaControllerProvider.notifier).cambiarEstatus(
            documentoPorEmitirId: documentoId,
            nuevo: EstatusDocumentoPorEmitir.procesadoAceptado,
          );
      expect(resultado, isA<CambiarEstatusDocumentoPorEmitirExitoso>());

      await Future<void>.delayed(Duration.zero);
      expect(reconstrucciones, greaterThan(0), reason: 'bug real: Agenda nunca invalidaba dashboardControllerProvider al crear una CxC');
    },
  );
}
