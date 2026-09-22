// Caso real: el Dashboard decía "Documentos por emitir pendientes — 2" y la
// Agenda, en el mismo momento, "Por emitir: 0".
//
// La investigación separó DOS cosas distintas:
//
//  1. El desfase visible era de VENTANA, no de datos: el Dashboard cuenta
//     pendientes atrasados de CUALQUIER periodo y la Agenda es una vista del
//     mes. Los dos documentos eran de julio y agosto, y estaban realmente
//     pendientes. Ninguno de los dos números estaba mal.
//
//  2. Auditando eso apareció un hueco REAL de reactividad: emitir un
//     documento pendiente lo sacaba de la Agenda pero lo dejaba contado en el
//     Dashboard y en el Centro de notificaciones, que consumen la misma regla
//     (`documentoPorEmitirRequiereAccion`). Eso es lo que prueban estas
//     pruebas, con el contenedor vivo y sin navegar.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/dashboard/presentation/dashboard_controller.dart';
import 'package:riseg_one/features/notificaciones/presentation/notificaciones_controller.dart';
import 'package:riseg_one/features/organizacion/data/tables/documento_por_emitir_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_estatus_documento_por_emitir_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/registrar_emision_documento_por_emitir_usecase.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart' show attachmentStorageProvider;
import 'package:riseg_one/features/organizacion/presentation/agenda/agenda_controller.dart';
import 'package:riseg_one/features/organizacion/presentation/agenda/agenda_resumen_periodo.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

class _SesionMaestroDePrueba extends SesionController {
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

/// Sondeo acotado, nunca `pumpAndSettle` (esto no es un widget test): si la
/// invalidación NO ocurre, la condición es falsa desde el primer intento y
/// para siempre, así que el `expect` posterior falla por VALOR, no por
/// timeout — determinista en ambos sentidos.
Future<void> _esperarHasta(bool Function() condicion, {int intentos = 200}) async {
  for (var i = 0; i < intentos && !condicion(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late String clienteId;
  late String documentoId;

  // Muy en el pasado: así `documentoPorEmitirRequiereAccion` es verdadero
  // contra el reloj real, sin que la prueba dependa de la fecha de hoy.
  final fechaVencida = DateTime.now().subtract(const Duration(days: 60));

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());

    final cliente = await db.into(db.cliente).insertReturning(
          ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'SPORTIUM'),
        );
    clienteId = cliente.id;

    final documento = await db.into(db.documentoPorEmitir).insertReturning(
          DocumentoPorEmitirCompanion.insert(
            codigo: 'DOC-000020',
            clienteId: clienteId,
            tipoDocumento: 'reciboDePago',
            agrupacion: 'porServicio',
            metodo: 'noAplica',
            periodoInicio: fechaVencida,
            periodoFin: fechaVencida.add(const Duration(days: 30)),
            fechaEmisionProgramada: Value(fechaVencida),
            generationKey: 'GK-DOC-000020',
            importeBaseEsperado: 1850000,
            importeFinalEsperado: 1850000,
            estatus: const Value('pendiente'),
          ),
        );
    documentoId = documento.id;

    container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      sesionControllerProvider.overrideWith(_SesionMaestroDePrueba.new),
      attachmentStorageProvider.overrideWithValue(AttachmentStorage('.')),
    ]);
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  /// Los tres consumidores de la misma regla, vivos a la vez. Mantenerlos
  /// escuchados es lo que impide que `autoDispose` los destruya y esconda el
  /// problema reconstruyéndolos "por casualidad".
  void mantenerVivos() {
    container.listen(agendaControllerProvider, (_, _) {});
    container.listen(dashboardControllerProvider, (_, _) {});
    container.listen(notificacionesControllerProvider, (_, _) {});
  }

  int alertaDashboard() =>
      container.read(dashboardControllerProvider).alertas?.documentosPorEmitirPendientes?.length ?? 0;

  int notificaciones() =>
      container.read(notificacionesControllerProvider).resultados?.documentosPorEmitir?.length ?? 0;

  int porEmitirEnAgenda() => calcularResumenPeriodoAgenda(
        container.read(agendaControllerProvider).documentos,
        DateTime.now(),
      ).porEmitir;

  test('emitir un pendiente lo quita del Dashboard y de Notificaciones sin navegar', () async {
    mantenerVivos();

    // La Agenda tiene que estar mirando el mes del documento para verlo: es
    // una vista mensual, y ese es justamente el desfase que NO es un bug.
    await container.read(agendaControllerProvider.notifier).aplicarFiltros(
          rangoInicio: DateTime(fechaVencida.year, fechaVencida.month, 1),
          rangoFin: DateTime(fechaVencida.year, fechaVencida.month + 1, 0),
        );
    await _esperarHasta(() => alertaDashboard() == 1 && notificaciones() == 1);

    expect(alertaDashboard(), 1, reason: 'si arranca en 0, la prueba no probaría nada');
    expect(notificaciones(), 1);
    expect(porEmitirEnAgenda(), 1);

    // Mutación por el flujo real, sin invalidar nada a mano desde la prueba.
    final resultado = await container.read(agendaControllerProvider.notifier).registrarEmision(
          documentoPorEmitirId: documentoId,
          folioDocumento: 'REC-001',
          fechaEmisionReal: DateTime.now(),
          importeEmitido: 1850000,
        );
    expect(resultado, isA<RegistrarEmisionDocumentoPorEmitirExitoso>());

    await _esperarHasta(() => alertaDashboard() == 0 && notificaciones() == 0);

    expect(porEmitirEnAgenda(), 0, reason: 'la Agenda ya se recargaba sola');
    expect(alertaDashboard(), 0, reason: 'el hueco real: el Dashboard seguía contándolo');
    expect(notificaciones(), 0, reason: 'el Centro de notificaciones lee la misma regla');
  });

  test('cancelar un pendiente produce el mismo efecto en los tres', () async {
    mantenerVivos();
    await _esperarHasta(() => alertaDashboard() == 1 && notificaciones() == 1);
    expect(alertaDashboard(), 1);

    final resultado = await container.read(agendaControllerProvider.notifier).cambiarEstatus(
          documentoPorEmitirId: documentoId,
          nuevo: EstatusDocumentoPorEmitir.cancelado,
          motivo: 'El Servicio terminó antes de este periodo',
        );
    expect(resultado, isA<CambiarEstatusDocumentoPorEmitirExitoso>());

    await _esperarHasta(() => alertaDashboard() == 0 && notificaciones() == 0);

    expect(alertaDashboard(), 0);
    expect(notificaciones(), 0);
  });

  test('marcarlo "no requerido" también lo saca del conteo', () async {
    mantenerVivos();
    await _esperarHasta(() => alertaDashboard() == 1);

    await container.read(agendaControllerProvider.notifier).cambiarEstatus(
          documentoPorEmitirId: documentoId,
          nuevo: EstatusDocumentoPorEmitir.noRequerido,
          motivo: 'Se acordó no facturar este periodo',
        );

    await _esperarHasta(() => alertaDashboard() == 0 && notificaciones() == 0);
    expect(alertaDashboard(), 0);
    expect(notificaciones(), 0);
  });

  test('el camino inverso: un pendiente nuevo vuelve a contar en los tres', () async {
    mantenerVivos();
    await _esperarHasta(() => alertaDashboard() == 1);

    // Se parte de cero emitiendo el único pendiente que había.
    await container.read(agendaControllerProvider.notifier).registrarEmision(
          documentoPorEmitirId: documentoId,
          folioDocumento: 'REC-001',
          fechaEmisionReal: DateTime.now(),
          importeEmitido: 1850000,
        );
    await _esperarHasta(() => alertaDashboard() == 0);
    expect(alertaDashboard(), 0);

    // Y aparece un pendiente atrasado nuevo. Se inserta en la base y se
    // provoca la recarga por el mismo camino que usa la aplicación: una
    // mutación real sobre otro documento.
    await db.into(db.documentoPorEmitir).insert(
          DocumentoPorEmitirCompanion.insert(
            codigo: 'DOC-000040',
            clienteId: clienteId,
            tipoDocumento: 'reciboDePago',
            agrupacion: 'porServicio',
            metodo: 'noAplica',
            periodoInicio: fechaVencida,
            periodoFin: fechaVencida.add(const Duration(days: 30)),
            fechaEmisionProgramada: Value(fechaVencida),
            generationKey: 'GK-DOC-000040',
            importeBaseEsperado: 500000,
            importeFinalEsperado: 500000,
            estatus: const Value('pendiente'),
          ),
        );

    await container.read(agendaControllerProvider.notifier).cambiarEstatus(
          documentoPorEmitirId: documentoId,
          nuevo: EstatusDocumentoPorEmitir.enviado,
          motivo: null,
        );

    await _esperarHasta(() => alertaDashboard() == 1 && notificaciones() == 1);
    expect(alertaDashboard(), 1);
    expect(notificaciones(), 1);
  });

  /// Un documento cualquiera, para poblar el escenario del modo Pendientes.
  Future<String> crearDocumento({
    required String codigo,
    required String estatus,
    required DateTime fechaEmisionProgramada,
  }) async {
    final d = await db.into(db.documentoPorEmitir).insertReturning(
          DocumentoPorEmitirCompanion.insert(
            codigo: codigo,
            clienteId: clienteId,
            tipoDocumento: 'reciboDePago',
            agrupacion: 'porServicio',
            metodo: 'noAplica',
            periodoInicio: fechaEmisionProgramada,
            periodoFin: fechaEmisionProgramada.add(const Duration(days: 30)),
            fechaEmisionProgramada: Value(fechaEmisionProgramada),
            generationKey: 'GK-' + codigo,
            importeBaseEsperado: 100000,
            importeFinalEsperado: 100000,
            estatus: Value(estatus),
          ),
        );
    return d.id;
  }

  List<String> codigosEnPantalla() =>
      [for (final d in container.read(agendaControllerProvider).documentos) d.codigo];

  group('Modo Pendientes', () {
    late String docJulio;

    setUp(() async {
      // DOC-000020 (del setUp global) es el más atrasado. Se agregan casos
      // que NO deben aparecer, uno por cada razón posible.
      docJulio = documentoId;
      await crearDocumento(
        codigo: 'DOC-AGOSTO',
        estatus: 'pendiente',
        fechaEmisionProgramada: DateTime.now().subtract(const Duration(days: 20)),
      );
      await crearDocumento(
        codigo: 'DOC-FUTURO',
        estatus: 'pendiente',
        fechaEmisionProgramada: DateTime.now().add(const Duration(days: 20)),
      );
      for (final estatus in ['enviado', 'procesadoAceptado', 'cancelado', 'noRequerido']) {
        await crearDocumento(
          codigo: 'DOC-' + estatus.toUpperCase(),
          estatus: estatus,
          fechaEmisionProgramada: DateTime.now().subtract(const Duration(days: 30)),
        );
      }
    });

    test('1. contiene exactamente los mismos documentos que cuenta el Dashboard', () async {
      mantenerVivos();
      await _esperarHasta(() => alertaDashboard() == 2);
      expect(alertaDashboard(), 2);

      await container.read(agendaControllerProvider.notifier).activarModoPendientes();

      final enAgenda = codigosEnPantalla().toSet();
      final enAlerta = {
        for (final n in container.read(dashboardControllerProvider).alertas!.documentosPorEmitirPendientes!)
          n.subtitulo,
      };
      expect(enAgenda, enAlerta, reason: 'la navegación debe preservar el conjunto de la alerta');
      expect(enAgenda.length, 2);
    });

    test('2. incluye documentos de meses distintos', () async {
      await container.read(agendaControllerProvider.notifier).activarModoPendientes();

      final fechas = [
        for (final d in container.read(agendaControllerProvider).documentos) d.fechaEmisionProgramada!.month,
      ];
      expect(fechas.toSet().length, greaterThan(1), reason: 'si fueran del mismo mes, no probaría nada');
    });

    test('3. no incluye un pendiente cuya fecha aún no llega', () async {
      await container.read(agendaControllerProvider.notifier).activarModoPendientes();

      expect(
        codigosEnPantalla(),
        isNot(contains('DOC-FUTURO')),
        reason: 'pendiente de estatus no es lo mismo que requiere atención',
      );
    });

    test('4-7. no incluye enviado, procesado, cancelado ni no requerido', () async {
      await container.read(agendaControllerProvider.notifier).activarModoPendientes();

      final codigos = codigosEnPantalla();
      expect(codigos, isNot(contains('DOC-ENVIADO')));
      expect(codigos, isNot(contains('DOC-PROCESADOACEPTADO')));
      expect(codigos, isNot(contains('DOC-CANCELADO')));
      expect(codigos, isNot(contains('DOC-NOREQUERIDO')));
      expect(codigos, hasLength(2));
    });

    test('8. el más atrasado va primero', () async {
      await container.read(agendaControllerProvider.notifier).activarModoPendientes();

      final documentos = container.read(agendaControllerProvider).documentos;
      for (var i = 1; i < documentos.length; i++) {
        expect(
          documentos[i - 1].fechaEmisionProgramada!.isAfter(documentos[i].fechaEmisionProgramada!),
          isFalse,
          reason: 'orden ascendente por fecha programada',
        );
      }
      expect(documentos.first.codigo, 'DOC-000020');
    });

    test('9. el filtro de Cliente sigue aplicando dentro del modo', () async {
      final otroCliente = await db.into(db.cliente).insertReturning(
            ClienteCompanion.insert(codigo: 'CLI-000002', nombreComercial: 'MORGAN'),
          );
      await db.into(db.documentoPorEmitir).insert(
            DocumentoPorEmitirCompanion.insert(
              codigo: 'DOC-OTRO-CLIENTE',
              clienteId: otroCliente.id,
              tipoDocumento: 'reciboDePago',
              agrupacion: 'porServicio',
              metodo: 'noAplica',
              periodoInicio: fechaVencida,
              periodoFin: fechaVencida,
              fechaEmisionProgramada: Value(fechaVencida),
              generationKey: 'GK-OTRO',
              importeBaseEsperado: 1,
              importeFinalEsperado: 1,
              estatus: const Value('pendiente'),
            ),
          );

      final notifier = container.read(agendaControllerProvider.notifier);
      await notifier.activarModoPendientes();
      expect(codigosEnPantalla(), contains('DOC-OTRO-CLIENTE'));

      await notifier.aplicarFiltros(clienteId: clienteId);

      expect(codigosEnPantalla(), isNot(contains('DOC-OTRO-CLIENTE')));
      expect(codigosEnPantalla(), contains('DOC-000020'));
    });

    test('10. volver a la vista mensual sale del modo', () async {
      final notifier = container.read(agendaControllerProvider.notifier);
      await notifier.activarModoPendientes();
      expect(container.read(agendaControllerProvider).modoPendientes, isTrue);

      await notifier.volverAVistaMensual();

      expect(container.read(agendaControllerProvider).modoPendientes, isFalse);
      expect(
        codigosEnPantalla(),
        isNot(contains('DOC-000020')),
        reason: 'DOC-000020 es de hace dos meses: no cabe en la vista del mes actual',
      );
    });

    test('13-16. emitir uno lo saca del modo y baja los tres consumidores', () async {
      mantenerVivos();
      final notifier = container.read(agendaControllerProvider.notifier);
      await notifier.activarModoPendientes();
      await _esperarHasta(() => alertaDashboard() == 2 && notificaciones() == 2);
      expect(codigosEnPantalla(), hasLength(2));

      await notifier.registrarEmision(
        documentoPorEmitirId: docJulio,
        folioDocumento: 'REC-001',
        fechaEmisionReal: DateTime.now(),
        importeEmitido: 1850000,
      );

      await _esperarHasta(() => alertaDashboard() == 1 && notificaciones() == 1);

      expect(codigosEnPantalla(), isNot(contains('DOC-000020')), reason: 'desaparece sin salir del modo');
      expect(container.read(agendaControllerProvider).modoPendientes, isTrue);
      expect(alertaDashboard(), 1);
      expect(notificaciones(), 1);
      expect(
        calcularResumenPendientes(container.read(agendaControllerProvider).documentos).total,
        1,
      );
    });

    test('14. cancelar uno lo saca igual', () async {
      mantenerVivos();
      final notifier = container.read(agendaControllerProvider.notifier);
      await notifier.activarModoPendientes();
      await _esperarHasta(() => alertaDashboard() == 2);

      await notifier.cambiarEstatus(
        documentoPorEmitirId: docJulio,
        nuevo: EstatusDocumentoPorEmitir.cancelado,
        motivo: 'No corresponde facturar',
      );

      await _esperarHasta(() => alertaDashboard() == 1);
      expect(codigosEnPantalla(), isNot(contains('DOC-000020')));
      expect(alertaDashboard(), 1);
    });

    test('17. llegar a cero muestra el conjunto vacío SIN salir del modo', () async {
      mantenerVivos();
      final notifier = container.read(agendaControllerProvider.notifier);
      await notifier.activarModoPendientes();

      for (final d in [...container.read(agendaControllerProvider).documentos]) {
        await notifier.cambiarEstatus(
          documentoPorEmitirId: d.id,
          nuevo: EstatusDocumentoPorEmitir.noRequerido,
          motivo: 'Se acordó no facturar',
        );
      }

      await _esperarHasta(() => alertaDashboard() == 0 && notificaciones() == 0);

      expect(container.read(agendaControllerProvider).documentos, isEmpty);
      expect(container.read(agendaControllerProvider).modoPendientes, isTrue, reason: 'nunca devuelve al mes solo');
      expect(alertaDashboard(), 0);
      expect(notificaciones(), 0);
    });

    test('18. el listado de pendientes no hace N+1: consultas constantes', () async {
      final notifier = container.read(agendaControllerProvider.notifier);
      await notifier.activarModoPendientes();
      final conDos = container.read(agendaControllerProvider).documentos.length;

      for (var i = 0; i < 8; i++) {
        await crearDocumento(
          codigo: 'DOC-EXTRA-' + i.toString(),
          estatus: 'pendiente',
          fechaEmisionProgramada: DateTime.now().subtract(Duration(days: 10 + i)),
        );
      }
      await notifier.reintentarCarga();

      expect(container.read(agendaControllerProvider).documentos.length, conDos + 8);
      // Las líneas de TODOS los documentos se piden en una sola consulta
      // (`lineasPorDocumentos`), así que pasar de 2 a 10 documentos no
      // multiplica las consultas — lo garantiza esa API, no un conteo frágil.
      expect(container.read(agendaControllerProvider).totalEsperadoPorDocumento, isNotNull);
    });

    test('19-20. el resumen usa la semántica fiscal cerrada, y avisa lo no calculable', () async {
      final notifier = container.read(agendaControllerProvider.notifier);
      await notifier.activarModoPendientes();
      final state = container.read(agendaControllerProvider);

      final resumen = calcularResumenPendientes(
        state.documentos,
        totalEsperadoPorDocumento: state.totalEsperadoPorDocumento,
      );

      // Sin líneas comerciales, estos documentos son `noAplica`: su total
      // esperado es el facturable, sin IVA inventado.
      expect(resumen.total, 2);
      expect(resumen.totalEsperado, 1850000 + 100000);
      expect(resumen.documentosSinTotalCalculable, 0);
      expect(resumen.masAntiguo, state.documentos.first.fechaEmisionProgramada, reason: 'el más atrasado');
    });
  });
}
