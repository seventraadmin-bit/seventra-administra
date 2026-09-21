// Etapa "Telefonía: ciclo de vida, recargas, trazabilidad y corrección"
// (schemaVersion 81).
//
// LOS DOS GAPS QUE CIERRA:
//
//  1. `CorregirLineaTelefonicaUseCase` cambiaba número, ICCID, operador
//     y modalidad de SIM —la identidad de la línea— **sin motivo, sin
//     actor y sin dejar rastro**. Telefonía no tenía ninguna tabla de
//     eventos propia de la línea.
//
//  2. Una recarga solo podía registrarse. Un importe mal capturado
//     obligaba a borrar la fila, que es justo lo que este proyecto no
//     hace con historial.
//
// Y el bug que ya nos mordió en Vehículos: una recarga anulada NO debe
// seguir sumando en ningún totalizador.

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/auditoria/enmascarar_identificador.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/telefonia/data/repositories/asignacion_linea_telefonica_repository_impl.dart';
import 'package:riseg_one/features/telefonia/domain/repositories/linea_telefonica_equipo_repository.dart';
import 'package:riseg_one/features/telefonia/data/repositories/linea_telefonica_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/repositories/recarga_linea_telefonica_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/tables/linea_telefonica_table.dart';
import 'package:riseg_one/features/telefonia/data/tables/recarga_linea_telefonica_table.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/cancelar_recarga_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/corregir_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/corregir_recarga_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/registrar_recarga_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/usuarios/data/repositories/auditoria_repository_impl.dart';
import 'package:riseg_one/features/usuarios/domain/usecases/buscar_auditoria_usecase.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/features/finanzas/data/tables/cuenta_financiera_table.dart';

/// La relación línea↔equipo no participa en nada de esta etapa (ni la
/// corrección de metadatos ni el ciclo de recarga la tocan): se aísla,
/// igual que ya hace `dashboard_actividad_reciente_periodo_test.dart`.
class _LineaTelefonicaEquipoRepoVacio implements LineaTelefonicaEquipoRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

const _cuentaRecargaDePrueba = 'cuenta-recarga-de-prueba';

void main() {
  late AppDatabase db;
  late LineaTelefonicaRepositoryImpl lineaRepo;
  late RecargaLineaTelefonicaRepositoryImpl recargaRepo;
  late CorregirLineaTelefonicaUseCase corregirLinea;
  late RegistrarRecargaLineaTelefonicaUseCase registrarRecarga;
  late CorregirRecargaLineaTelefonicaUseCase corregirRecarga;
  late CancelarRecargaLineaTelefonicaUseCase cancelarRecarga;
  late String lineaId;
  late String actorId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    // Cuenta REAL para las recargas: el dominio exige saber de dónde
    // salió el dinero de una recarga nueva.
    await db.into(db.cuentaFinanciera).insert(
          CuentaFinancieraCompanion.insert(
            id: const Value(_cuentaRecargaDePrueba),
            codigo: 'CTA-REC',
            nombre: 'BBVA Empresarial',
            tipo: TipoCuentaFinanciera.banco.name,
            saldoInicial: 100000000,
            fechaSaldoInicial: DateTime(2026, 1, 1),
          ),
        );
    final asignacionRepo = AsignacionLineaTelefonicaRepositoryImpl(db);
    lineaRepo = LineaTelefonicaRepositoryImpl(db, asignacionRepo, _LineaTelefonicaEquipoRepoVacio());
    recargaRepo = RecargaLineaTelefonicaRepositoryImpl(db, EgresoRepositoryImpl(db), DeudaRepositoryImpl(db, EgresoRepositoryImpl(db)), CodigoSecuenciaService(db));
    corregirLinea = CorregirLineaTelefonicaUseCase(lineaRepo);
    registrarRecarga = RegistrarRecargaLineaTelefonicaUseCase(recargaRepo, lineaRepo, DeudaRepositoryImpl(db, EgresoRepositoryImpl(db)));
    corregirRecarga = CorregirRecargaLineaTelefonicaUseCase(recargaRepo, lineaRepo, DeudaRepositoryImpl(db, EgresoRepositoryImpl(db)));
    cancelarRecarga = CancelarRecargaLineaTelefonicaUseCase(recargaRepo, lineaRepo);

    final actor = await db.into(db.usuario).insertReturning(
          UsuarioCompanion.insert(
            nombre: 'MARLON',
            nombreUsuario: 'marlon',
            passwordHash: r'pbkdf2$1$c2FsdA==$aGFzaA==',
            esMaestro: const Value(true),
          ),
        );
    actorId = actor.id;

    final linea = await lineaRepo.crear(
      codigo: 'LIN-000004',
      numero: '5512345678',
      operador: OperadorTelefonico.telcel.name,
      modalidadSim: ModalidadSim.fisica.name,
      iccid: '8952140061234567890',
    );
    lineaId = linea.id;
  });

  tearDown(() => db.close());

  // ---------------------------------------------------------------
  // §2 — corrección de línea con el estándar completo
  // ---------------------------------------------------------------

  group('§2 — corregir una línea exige motivo, actor y deja diff', () {
    test('sin motivo se rechaza, y NADA cambia', () async {
      final r = await corregirLinea.ejecutar(
        lineaTelefonicaId: lineaId,
        numero: '5599999999',
        motivo: '   ',
      );

      expect(r, isA<CorregirLineaTelefonicaMotivoRequerido>());
      expect((await lineaRepo.obtenerPorId(lineaId))!.numero, '5512345678');
      expect(await lineaRepo.listarEventos(lineaId), isEmpty);
    });

    test('cambiar número e ICCID deja evento con antes/después y actor', () async {
      final r = await corregirLinea.ejecutar(
        lineaTelefonicaId: lineaId,
        numero: '5598765432',
        iccid: '8952140069876543210',
        motivo: 'Reposición de SIM por robo del equipo',
        actorUsuarioId: actorId,
      );
      expect(r, isA<CorregirLineaTelefonicaExitoso>());

      final evento = (await lineaRepo.listarEventos(lineaId)).single;
      expect(evento.tipoEvento, TipoEventoLineaTelefonica.corregida.name);
      expect(evento.actorUsuarioId, actorId, reason: 'quién lo hizo');
      expect(evento.observacion, contains('Reposición'), reason: 'por qué');

      final antes = jsonDecode(evento.estadoAnterior!) as Map<String, dynamic>;
      final despues = jsonDecode(evento.estadoNuevo!) as Map<String, dynamic>;
      expect(antes.keys.toSet(), {'numero', 'iccid'}, reason: 'solo lo que cambió');
      expect(despues.keys.toSet(), {'numero', 'iccid'});
    });

    test('§7 — el diff NO guarda el número ni el ICCID completos', () async {
      await corregirLinea.ejecutar(
        lineaTelefonicaId: lineaId,
        numero: '5598765432',
        iccid: '8952140069876543210',
        motivo: 'Reposición de SIM',
        actorUsuarioId: actorId,
      );

      final evento = (await lineaRepo.listarEventos(lineaId)).single;
      final crudo = '${evento.estadoAnterior}${evento.estadoNuevo}';

      expect(crudo, isNot(contains('5512345678')), reason: 'el número anterior en claro nunca entra al evento');
      expect(crudo, isNot(contains('5598765432')));
      expect(crudo, isNot(contains('8952140061234567890')), reason: 'ni el ICCID');
      expect(crudo, isNot(contains('8952140069876543210')));
      // Pero sí queda verificable QUE cambió, y distinguible.
      expect(crudo, contains('····5678'));
      expect(crudo, contains('····5432'));
      expect(crudo, contains('····7890'));
      expect(crudo, contains('····3210'));
    });

    test('la máscara conserva null y no deja casi-completo un valor corto', () {
      expect(enmascararIdentificador(null), isNull);
      expect(enmascararIdentificador('  '), isNull);
      expect(enmascararIdentificador('123'), '···', reason: 'un valor corto se oculta entero');
      expect(enmascararIdentificador('8952140061234567890'), '····7890');
    });

    test('una corrección que no cambia nada NO genera evento', () async {
      final r = await corregirLinea.ejecutar(
        lineaTelefonicaId: lineaId,
        numero: '5512345678',
        operador: OperadorTelefonico.telcel.name,
        motivo: 'Revisión sin cambios',
        actorUsuarioId: actorId,
      );

      expect(r, isA<CorregirLineaTelefonicaExitoso>());
      expect(await lineaRepo.listarEventos(lineaId), isEmpty);
    });
  });

  // ---------------------------------------------------------------
  // §13 — caso integral de la recarga
  // ---------------------------------------------------------------

  Future<RecargaLineaTelefonicaData> registrar500() async {
    final r = await registrarRecarga.ejecutar(
      lineaTelefonicaId: lineaId,
      fecha: DateTime(2026, 9, 1),
      importe: 50000,
      actorUsuarioId: actorId,
      formaPago: FormaPago.efectivo.name,
        cuentaFinancieraId: _cuentaRecargaDePrueba,
    );
    return (r as RegistrarRecargaLineaTelefonicaExitoso).recarga;
  }

  group('§13 — registrar → corregir → cancelar, sin borrar historial', () {
    test('registrar deja la recarga vigente y sumando', () async {
      final recarga = await registrar500();

      expect(recarga.importe, 50000);
      expect(recarga.estatus, EstatusRecargaLineaTelefonica.registrada.name);
      expect(await recargaRepo.totalPorLinea(lineaId), 50000);
    });

    test('corregir 500 → 650 mantiene la MISMA fila, con motivo y antes/después', () async {
      final recarga = await registrar500();

      final r = await corregirRecarga.ejecutar(
        recargaLineaTelefonicaId: recarga.id,
        importe: 65000,
        motivo: 'El ticket del OXXO dice 650',
        actorUsuarioId: actorId,
        formaPago: FormaPago.efectivo.name,
        cuentaFinancieraId: _cuentaRecargaDePrueba,
      );

      expect(r, isA<CorregirRecargaLineaTelefonicaExitoso>());
      final historial = await recargaRepo.listarPorLinea(lineaId);
      expect(historial, hasLength(1), reason: 'jamás una "recarga sustituta" que inflaría los totales');
      expect(historial.single.id, recarga.id, reason: 'misma identidad lógica');
      expect(historial.single.importe, 65000);
      expect(await recargaRepo.totalPorLinea(lineaId), 65000);

      final evento = (await lineaRepo.listarEventos(lineaId)).single;
      expect(evento.tipoEvento, TipoEventoLineaTelefonica.recargaCorregida.name);
      expect(evento.recargaId, recarga.id);
      expect(evento.actorUsuarioId, actorId);
      expect(evento.observacion, contains('OXXO'));
      final antes = jsonDecode(evento.estadoAnterior!) as Map<String, dynamic>;
      final despues = jsonDecode(evento.estadoNuevo!) as Map<String, dynamic>;
      expect(antes['importe'], 50000);
      expect(despues['importe'], 65000);
    });

    test('cancelar conserva el registro, lo marca y genera evento', () async {
      final recarga = await registrar500();

      final r = await cancelarRecarga.ejecutar(
        recargaLineaTelefonicaId: recarga.id,
        motivo: 'La recarga nunca se hizo: el pago fue rechazado',
        actorUsuarioId: actorId,
      );

      expect(r, isA<CancelarRecargaLineaTelefonicaExitoso>());
      final historial = await recargaRepo.listarPorLinea(lineaId);
      expect(historial, hasLength(1), reason: 'no desaparece del historial');
      expect(historial.single.estatus, EstatusRecargaLineaTelefonica.cancelada.name);
      expect(historial.single.motivoCancelacion, contains('rechazado'));
      expect(historial.single.importe, 50000, reason: 'el importe original se conserva como evidencia');

      final evento = (await lineaRepo.listarEventos(lineaId)).single;
      expect(evento.tipoEvento, TipoEventoLineaTelefonica.recargaCancelada.name);
      expect(evento.estadoAnterior, 'registrada');
      expect(evento.estadoNuevo, 'cancelada');
    });

    test('la segunda cancelación: cero mutación, cero segundo evento', () async {
      final recarga = await registrar500();
      await cancelarRecarga.ejecutar(
        recargaLineaTelefonicaId: recarga.id,
        motivo: 'Pago rechazado',
        actorUsuarioId: actorId,
      );

      final segunda = await cancelarRecarga.ejecutar(
        recargaLineaTelefonicaId: recarga.id,
        motivo: 'Segundo intento',
        actorUsuarioId: actorId,
      );

      expect(segunda, isA<CancelarRecargaLineaTelefonicaYaCancelada>());
      expect((await recargaRepo.obtenerPorId(recarga.id))!.motivoCancelacion, 'Pago rechazado');
      expect(await lineaRepo.listarEventos(lineaId), hasLength(1), reason: 'nunca un segundo evento');
    });

    test('una recarga anulada ya no se corrige: se registra una nueva', () async {
      final recarga = await registrar500();
      await cancelarRecarga.ejecutar(recargaLineaTelefonicaId: recarga.id, motivo: 'Pago rechazado');

      final r = await corregirRecarga.ejecutar(
        recargaLineaTelefonicaId: recarga.id,
        importe: 65000,
        motivo: 'Intento de corregir lo anulado',
        formaPago: FormaPago.efectivo.name,
        cuentaFinancieraId: _cuentaRecargaDePrueba,
      );

      expect(r, isA<CorregirRecargaLineaTelefonicaCancelada>());
      expect((await recargaRepo.obtenerPorId(recarga.id))!.importe, 50000);
    });

    test('corregir y cancelar exigen motivo', () async {
      final recarga = await registrar500();

      expect(
        await corregirRecarga.ejecutar(recargaLineaTelefonicaId: recarga.id, importe: 65000, motivo: ' ', formaPago: FormaPago.efectivo.name, cuentaFinancieraId: _cuentaRecargaDePrueba),
        isA<CorregirRecargaLineaTelefonicaMotivoRequerido>(),
      );
      expect(
        await cancelarRecarga.ejecutar(recargaLineaTelefonicaId: recarga.id, motivo: ''),
        isA<CancelarRecargaLineaTelefonicaMotivoRequerido>(),
      );
      expect((await recargaRepo.obtenerPorId(recarga.id))!.importe, 50000);
      expect(await lineaRepo.listarEventos(lineaId), isEmpty);
    });

    test('un importe corregido a cero o negativo se rechaza', () async {
      final recarga = await registrar500();

      expect(
        await corregirRecarga.ejecutar(recargaLineaTelefonicaId: recarga.id, importe: 0, motivo: 'x', formaPago: FormaPago.efectivo.name, cuentaFinancieraId: _cuentaRecargaDePrueba),
        isA<CorregirRecargaLineaTelefonicaImporteInvalido>(),
      );
      expect((await recargaRepo.obtenerPorId(recarga.id))!.importe, 50000);
    });
  });

  // ---------------------------------------------------------------
  // §14 — TODOS los totalizadores
  // ---------------------------------------------------------------

  group('§14 — una recarga anulada deja de sumar en TODOS los totales', () {
    test('total por línea, por rango y "última recarga"', () async {
      final vigente = await registrar500();
      final aAnular = (await registrarRecarga.ejecutar(
        lineaTelefonicaId: lineaId,
        fecha: DateTime(2026, 9, 10),
        importe: 80000,
        formaPago: FormaPago.efectivo.name,
        cuentaFinancieraId: _cuentaRecargaDePrueba,
        actorUsuarioId: actorId,
      ) as RegistrarRecargaLineaTelefonicaExitoso)
          .recarga;

      expect(await recargaRepo.totalPorLinea(lineaId), 130000);
      expect(await recargaRepo.totalPorRango(), 130000);
      expect((await recargaRepo.obtenerUltimasPorTodasLasLineas())[lineaId]!.id, aAnular.id);

      await cancelarRecarga.ejecutar(recargaLineaTelefonicaId: aAnular.id, motivo: 'Pago rechazado');

      expect(await recargaRepo.totalPorLinea(lineaId), 50000, reason: 'el mismo bug que apareció en Vehículos');
      expect(await recargaRepo.totalPorRango(), 50000);
      expect(
        (await recargaRepo.obtenerUltimasPorTodasLasLineas())[lineaId]!.id,
        vigente.id,
        reason: '"última recarga" es la última que SÍ ocurrió',
      );
      // Pero sigue en el historial.
      expect(await recargaRepo.listarPorLinea(lineaId), hasLength(2));
    });

    test('total por empleado, por servicio y el desglose de Reportes', () async {
      final empleado = await db.into(db.empleado).insertReturning(
            EmpleadoCompanion.insert(
              numeroEmpleado: 1,
              nombres: 'Javier',
              apellidoPaterno: 'Ruiz',
              sexo: 'masculino',
              fechaNacimiento: DateTime(1990, 1, 1),
              curp: 'RUSJ900101HDFXXX01',
              rfc: 'RUSJ900101AB1',
              nss: '12345678901',
              estadoCivil: 'soltero',
              fechaIngreso: DateTime(2025, 1, 1),
              aniosExperienciaSeguridad: 3,
            ),
          );
      await db.into(db.asignacionLineaTelefonica).insert(
            AsignacionLineaTelefonicaCompanion.insert(
              lineaTelefonicaId: lineaId,
              fechaInicio: DateTime(2026, 1, 1),
              empleadoId: Value(empleado.id),
            ),
          );

      final recarga = await registrar500();
      expect(await recargaRepo.totalPorEmpleado(empleado.id), 50000);
      expect(await recargaRepo.listarConDestinoEnRango(), hasLength(1));

      await cancelarRecarga.ejecutar(recargaLineaTelefonicaId: recarga.id, motivo: 'Pago rechazado');

      expect(await recargaRepo.totalPorEmpleado(empleado.id), 0);
      expect(
        await recargaRepo.listarConDestinoEnRango(),
        isEmpty,
        reason: 'Reportes y el Dashboard leen de aquí: tampoco deben verla',
      );
    });
  });

  // ---------------------------------------------------------------
  // §5 — el dinero NO se toca
  // ---------------------------------------------------------------

  // schemaVersion 86 invierte la decisión de la Etapa 9C: una recarga
  // ES una salida de dinero y Finanzas tiene que enterarse. Lo que
  // antes se protegía —"Telefonía no genera movimientos"— ahora sería
  // el bug. Lo que se protege es el efecto EXACTO: uno, ni cero ni dos.
  group('§5 — Telefonía genera exactamente un movimiento de dinero por recarga', () {
    test('registrar crea UN Egreso; corregir lo mueve sin duplicar; cancelar lo revierte una vez', () async {
      final recarga = await registrar500();

      final egresosTrasRegistrar = await db.select(db.egreso).get();
      expect(egresosTrasRegistrar, hasLength(1), reason: 'Cuenta → exactamente un Egreso');
      expect(egresosTrasRegistrar.single.monto, 50000);
      expect(await db.select(db.movimientoDeuda).get(), isEmpty, reason: 'sin tarjeta, sin cargo');

      await corregirRecarga.ejecutar(
        recargaLineaTelefonicaId: recarga.id,
        importe: 65000,
        motivo: 'Ticket real',
        actorUsuarioId: actorId,
        formaPago: FormaPago.efectivo.name,
        cuentaFinancieraId: _cuentaRecargaDePrueba,
      );
      final egresosTrasCorregir = await db.select(db.egreso).get();
      expect(egresosTrasCorregir, hasLength(1), reason: 'corregir MUEVE el efecto, nunca lo duplica');
      expect(egresosTrasCorregir.single.monto, 65000);

      await cancelarRecarga.ejecutar(
        recargaLineaTelefonicaId: recarga.id,
        motivo: 'Pago rechazado',
        actorUsuarioId: actorId,
      );
      final egresosTrasCancelar = await db.select(db.egreso).get();
      expect(egresosTrasCancelar, hasLength(1), reason: 'cancelar no crea un Egreso nuevo');
      expect(egresosTrasCancelar.single.estatus, 'cancelado');
      expect(await db.select(db.movimientoDeuda).get(), isEmpty);
    });
  });

  // ---------------------------------------------------------------
  // §6 — Auditoría central
  // ---------------------------------------------------------------

  group('§6 — Telefonía llega completa a Auditoría central', () {
    test('corrección de línea, corrección y anulación de recarga, sin duplicar el alta', () async {
      final buscar = BuscarAuditoriaUseCase(AuditoriaRepositoryImpl(db));

      await corregirLinea.ejecutar(
        lineaTelefonicaId: lineaId,
        numero: '5598765432',
        motivo: 'Reposición de SIM',
        actorUsuarioId: actorId,
      );
      final recarga = await registrar500();
      await corregirRecarga.ejecutar(
        recargaLineaTelefonicaId: recarga.id,
        importe: 65000,
        motivo: 'Ticket real',
        actorUsuarioId: actorId,
        formaPago: FormaPago.efectivo.name,
        cuentaFinancieraId: _cuentaRecargaDePrueba,
      );
      await cancelarRecarga.ejecutar(
        recargaLineaTelefonicaId: recarga.id,
        motivo: 'Pago rechazado',
        actorUsuarioId: actorId,
      );

      final telefonia = (await buscar.ejecutar(const FiltroAuditoria(modulo: 'telefonia'))).toList();
      final acciones = telefonia.map((e) => e.accion).toList();

      expect(acciones, contains('corregida'));
      expect(acciones, contains('recargaCorregida'));
      expect(acciones, contains('recargaCancelada'));
      // El ALTA de la recarga ya la proyecta la propia fila (Etapa 11D):
      // no se emite además un evento, para no duplicar el mismo hecho.
      expect(acciones.where((a) => a == 'recarga'), hasLength(1));
      expect(
        acciones.where((a) => a == 'recargaRegistrada'),
        isEmpty,
        reason: 'duplicar el alta era exactamente lo que había que evitar',
      );
      expect(telefonia.every((e) => e.actorUsuarioId == actorId), isTrue);
    });

    test('la Auditoría identifica la línea por código, nunca por número ni ICCID', () async {
      final buscar = BuscarAuditoriaUseCase(AuditoriaRepositoryImpl(db));
      await corregirLinea.ejecutar(
        lineaTelefonicaId: lineaId,
        operador: OperadorTelefonico.att.name,
        motivo: 'Portabilidad',
        actorUsuarioId: actorId,
      );

      final evento = (await buscar.ejecutar(const FiltroAuditoria(modulo: 'telefonia')))
          .firstWhere((e) => e.accion == 'corregida');

      expect(evento.entidadEtiqueta, 'LIN-000004');
      final volcado = '${evento.entidadEtiqueta}|${evento.motivo}|${evento.detalleJson}|'
          '${evento.cambios.map((c) => '${c.campo}${c.antes}${c.despues}').join()}';
      expect(volcado, isNot(contains('5512345678')));
      expect(volcado, isNot(contains('8952140061234567890')));
    });

    test('el cambio de operador se lee como campo: antes → después', () async {
      final buscar = BuscarAuditoriaUseCase(AuditoriaRepositoryImpl(db));
      await corregirLinea.ejecutar(
        lineaTelefonicaId: lineaId,
        operador: OperadorTelefonico.att.name,
        motivo: 'Portabilidad a AT&T',
        actorUsuarioId: actorId,
      );

      final evento = (await buscar.ejecutar(const FiltroAuditoria(modulo: 'telefonia')))
          .firstWhere((e) => e.accion == 'corregida');

      expect(evento.cambios, hasLength(1));
      expect(evento.cambios.single.campo, 'operador');
      expect(evento.cambios.single.antes, 'telcel');
      expect(evento.cambios.single.despues, 'att');
    });
  });
}
