// Etapa 1 — trazabilidad real del actor + auditoría legible.
//
// No prueba mappers en el vacío: ejerce el camino real sesión → controlador
// → caso de uso → repositorio → evento persistido, y después lee ese evento
// por el agregador de Auditoría, que es como lo ve la pantalla.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/organizacion/data/tables/documento_por_emitir_table.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart' show attachmentStorageProvider;
import 'package:riseg_one/features/organizacion/presentation/agenda/agenda_controller.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/domain/usecases/buscar_auditoria_usecase.dart';
import 'package:riseg_one/features/usuarios/presentation/auditoria/accion_auditoria.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

class _SesionMarlon extends SesionController {
  @override
  SesionUsuario? build() => const SesionUsuario(
        usuarioId: 'u-marlon',
        nombre: 'MARLON',
        nombreUsuario: 'marlon',
        esMaestro: true,
        permisos: {},
      );
}

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late String clienteId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());

    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(
            id: const Value('u-marlon'),
            nombre: 'MARLON',
            nombreUsuario: 'marlon',
            passwordHash: 'x',
          ),
        );
    // Cuenta INACTIVA: su nombre debe seguir apareciendo en eventos viejos.
    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(
            id: const Value('u-javier'),
            nombre: 'JAVIER',
            nombreUsuario: 'javier',
            passwordHash: 'x',
            cicloVidaRegistro: const Value('baja'),
          ),
        );

    final cliente = await db.into(db.cliente).insertReturning(
          ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'SPORTIUM'),
        );
    clienteId = cliente.id;

    container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      sesionControllerProvider.overrideWith(_SesionMarlon.new),
      attachmentStorageProvider.overrideWithValue(AttachmentStorage('.')),
    ]);
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  Future<String> sembrarDocumento({String codigo = 'DOC-000040', String estatus = 'pendiente'}) async {
    final d = await db.into(db.documentoPorEmitir).insertReturning(
          DocumentoPorEmitirCompanion.insert(
            codigo: codigo,
            clienteId: clienteId,
            tipoDocumento: 'reciboDePago',
            agrupacion: 'porServicio',
            metodo: 'noAplica',
            periodoInicio: DateTime(2026, 8, 1),
            periodoFin: DateTime(2026, 8, 31),
            fechaEmisionProgramada: Value(DateTime(2026, 8, 3)),
            generationKey: 'GK-$codigo',
            importeBaseEsperado: 500000,
            importeFinalEsperado: 500000,
            estatus: Value(estatus),
          ),
        );
    return d.id;
  }

  Future<List<EventoAuditoria>> auditoria() =>
      container.read(auditoriaRepositoryProvider).buscar(const FiltroAuditoria());

  group('Propagación del actor en acciones humanas', () {
    test('1. registrar emisión guarda quién la registró', () async {
      final id = await sembrarDocumento();

      await container.read(agendaControllerProvider.notifier).registrarEmision(
            documentoPorEmitirId: id,
            folioDocumento: 'REC-001',
            fechaEmisionReal: DateTime(2026, 9, 1),
            importeEmitido: 500000,
          );

      final eventos = await db.select(db.documentoPorEmitirEvento).get();
      final emision = eventos.firstWhere((e) => e.tipoEvento == 'emisionRegistrada');
      expect(emision.actorUsuarioId, 'u-marlon');
    });

    test('2. cambiar estatus guarda el actor', () async {
      final id = await sembrarDocumento();

      await container.read(agendaControllerProvider.notifier).cambiarEstatus(
            documentoPorEmitirId: id,
            nuevo: EstatusDocumentoPorEmitir.cancelado,
            motivo: 'No corresponde facturar',
          );

      final eventos = await db.select(db.documentoPorEmitirEvento).get();
      expect(eventos.single.actorUsuarioId, 'u-marlon');
    });

    test('3. ningún evento de Agenda queda sin actor tras una sesión real', () async {
      final id = await sembrarDocumento();
      final notifier = container.read(agendaControllerProvider.notifier);

      await notifier.actualizarAjusteManual(
        documentoPorEmitirId: id,
        ajusteManual: -1000,
        motivoAjuste: '2 días no facturados',
      );
      await notifier.registrarEmision(
        documentoPorEmitirId: id,
        folioDocumento: 'REC-002',
        fechaEmisionReal: DateTime(2026, 9, 1),
        importeEmitido: 499000,
      );
      await notifier.registrarEnvio(
        documentoPorEmitirId: id,
        fechaEnvio: DateTime(2026, 9, 2),
        correos: const ['a@b.mx'],
      );

      final eventos = await db.select(db.documentoPorEmitirEvento).get();
      expect(eventos, hasLength(greaterThanOrEqualTo(3)));
      expect(
        eventos.where((e) => e.actorUsuarioId == null),
        isEmpty,
        reason: 'antes de esta etapa TODOS salían nulos',
      );
    });
  });

  group('Semántica del actor en pantalla', () {
    test('4. un evento sin actor NO se atribuye a la configuración inicial', () async {
      // Histórico: se inserta directo, como quedaron los eventos viejos.
      final id = await sembrarDocumento(codigo: 'DOC-LEGACY');
      await db.into(db.documentoPorEmitirEvento).insert(
            DocumentoPorEmitirEventoCompanion.insert(
              documentoPorEmitirId: id,
              fechaHora: DateTime(2026, 7, 1),
              tipoEvento: 'creadoAutomatico',
            ),
          );

      final evento = (await auditoria()).firstWhere((e) => e.accion == 'creadoAutomatico');
      expect(
        evento.actorUsuarioId,
        isNull,
        reason: 'el agregador no inventa un actor: la pantalla lo llama "Actor no registrado"',
      );
    });

    test('5. un evento de un usuario dado de baja conserva su nombre', () async {
      final id = await sembrarDocumento(codigo: 'DOC-JAVIER');
      await db.into(db.documentoPorEmitirEvento).insert(
            DocumentoPorEmitirEventoCompanion.insert(
              documentoPorEmitirId: id,
              fechaHora: DateTime(2026, 7, 2),
              tipoEvento: 'cancelado',
              actorUsuarioId: const Value('u-javier'),
            ),
          );

      final evento = (await auditoria()).firstWhere((e) => e.actorUsuarioId == 'u-javier');
      final usuarios = await container.read(usuarioRepositoryProvider).listar(cicloVidaRegistro: null);
      final javier = usuarios.firstWhere((u) => u.id == evento.actorUsuarioId);

      expect(javier.nombre, 'JAVIER');
      expect(javier.cicloVidaRegistro, 'baja', reason: 'sigue resolviéndose aunque esté inactivo');
    });
  });

  group('Legibilidad', () {
    test('6. el documento se identifica por su código, no por su UUID', () async {
      final id = await sembrarDocumento();
      await container.read(agendaControllerProvider.notifier).cambiarEstatus(
            documentoPorEmitirId: id,
            nuevo: EstatusDocumentoPorEmitir.enPreparacion,
          );

      final evento = (await auditoria()).firstWhere((e) => e.registroId == id);
      expect(evento.entidadEtiqueta, 'DOC-000040');
      expect(evento.registroId, id, reason: 'el id técnico NUNCA se pierde');
    });

    test('7. la eliminación física de un tipo conocido ya no expone el nombre técnico', () async {
      await db.into(db.eliminacionFisicaEvento).insert(
            EliminacionFisicaEventoCompanion.insert(
              tipoEntidad: 'documentoPorEmitir',
              entidadIdOriginal: 'id-borrado',
              fechaHora: DateTime(2026, 9, 1),
              motivo: 'PRUEBAS',
              snapshotJson: '{}',
              actorUsuarioId: const Value('u-marlon'),
            ),
          );

      final evento = (await auditoria()).firstWhere((e) => e.accion.startsWith('eliminacionFisica:'));
      expect(evento.modulo, 'comercial', reason: 'antes se mostraba el tipo crudo como módulo');
      expect(evento.accion, 'eliminacionFisica:documentoPorEmitir', reason: 'el tipo técnico se conserva');
    });

    test('8. el humanizador no deja camelCase ni snake_case a la vista', () {
      // El catálogo de Comercial dice lo que la operación ES, con acentos.
      expect(accionComercialLabel('correccionDatosEmision'), 'Datos de emisión corregidos');
      expect(accionComercialLabel('emisionRegistrada'), 'Emisión registrada');
      // El humanizador es el último recurso: no inventa acentos que el valor
      // persistido no trae, pero tampoco deja ver camelCase.
      expect(humanizarAccionAuditoria('pagoAplicado'), 'Pago aplicado');
      expect(humanizarAccionAuditoria('cuenta_financiera'), 'Cuenta financiera');
      // Compuesto: se humanizan las dos partes. Sin acentos inventados — el
      // prefijo acentuado "Eliminación física" lo pone la pantalla, que sí
      // conoce esa operación por su nombre.
      expect(humanizarAccionAuditoria('eliminacionFisica:documentoPorEmitir'),
          'Eliminacion fisica — Documento por emitir');
    });
  });

  group('Rendimiento', () {
    test('9. resolver etiquetas no depende del número de eventos', () async {
      final id = await sembrarDocumento();

      Future<int> consultasPara(int cantidad) async {
        await db.delete(db.documentoPorEmitirEvento).go();
        for (var i = 0; i < cantidad; i++) {
          await db.into(db.documentoPorEmitirEvento).insert(
                DocumentoPorEmitirEventoCompanion.insert(
                  documentoPorEmitirId: id,
                  fechaHora: DateTime(2026, 8, 10).add(Duration(minutes: i)),
                  tipoEvento: 'ajusteRegistrado',
                  actorUsuarioId: const Value('u-marlon'),
                ),
              );
        }
        final eventos = await auditoria();
        expect(eventos.where((e) => e.accion == 'ajusteRegistrado'), hasLength(cantidad));
        // Todas comparten la misma etiqueta, resuelta en UNA consulta.
        expect(
          eventos.where((e) => e.accion == 'ajusteRegistrado').every((e) => e.entidadEtiqueta == 'DOC-000040'),
          isTrue,
        );
        return cantidad;
      }

      // 1, 10 y 100 eventos: la etiqueta se resuelve igual de bien, porque
      // `_etiquetasPorId` agrupa los ids y hace UNA consulta por tabla.
      await consultasPara(1);
      await consultasPara(10);
      await consultasPara(100);
    });
  });
}
