// Servicios Eventuales — Rebanada 1, núcleo operativo (schemaVersion
// 87). Contra BD real (Drift `NativeDatabase.memory()`, sin mocks).
//
// Lo que se protege aquí es el contrato del dominio: el XOR del
// solicitante, el rango de fechas, el horario que cruza la medianoche,
// y —lo más importante— que **programar no mueve dinero** y que
// **cancelar un evento no borra lo ya pagado**.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/features/servicios_eventuales/data/repositories/servicio_eventual_documento_fiscal_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/complemento_pago_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/entidad_fiscal_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_por_cobrar_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/pago_repository_impl.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart'
    show MetodoPagoCobro;
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';
import 'package:riseg_one/features/servicios_eventuales/data/repositories/servicio_eventual_repository_impl.dart';
import 'package:riseg_one/features/servicios_eventuales/data/tables/servicio_eventual_table.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/agregar_cobertura_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/agregar_costo_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/agregar_participante_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/cancelar_cobertura_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/cancelar_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/corregir_cobertura_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/corregir_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/crear_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/finalizar_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/listar_servicios_eventuales_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/pagar_cobertura_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/retirar_participante_servicio_eventual_usecase.dart';

void main() {
  late AppDatabase db;
  late ServicioEventualRepositoryImpl repo;
  late ClienteRepositoryImpl clienteRepo;
  late EmpleadoRepositoryImpl empleadoRepo;
  late EgresoRepositoryImpl egresoRepo;

  late CrearServicioEventualUseCase crear;
  late CorregirServicioEventualUseCase corregir;
  late FinalizarServicioEventualUseCase finalizar;
  late CancelarServicioEventualUseCase cancelar;
  late AgregarParticipanteServicioEventualUseCase agregarParticipante;
  late RetirarParticipanteServicioEventualUseCase retirarParticipante;
  late AgregarCoberturaServicioEventualUseCase agregarCobertura;
  late CorregirCoberturaServicioEventualUseCase corregirCobertura;
  late CancelarCoberturaServicioEventualUseCase cancelarCobertura;
  late AgregarCostoServicioEventualUseCase agregarCosto;
  late PagarCoberturaServicioEventualUseCase pagarCobertura;
  late ListarServiciosEventualesUseCase listar;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    egresoRepo = EgresoRepositoryImpl(db);
    final deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
    repo = ServicioEventualRepositoryImpl(db, egresoRepo, deudaRepo, CodigoSecuenciaService(db), CuentaPorCobrarRepositoryImpl(db), PagoRepositoryImpl(db));
    clienteRepo = ClienteRepositoryImpl(db);
    empleadoRepo = EmpleadoRepositoryImpl(db, AsignacionServicioRepositoryImpl(db));

    crear = CrearServicioEventualUseCase(repo, clienteRepo, EntidadFiscalRepositoryImpl(db));
    corregir = CorregirServicioEventualUseCase(repo, CuentaPorCobrarRepositoryImpl(db), PagoRepositoryImpl(db));
    finalizar = FinalizarServicioEventualUseCase(repo);
    cancelar = CancelarServicioEventualUseCase(
      repo,
      ServicioEventualDocumentoFiscalRepositoryImpl(db, CuentaPorCobrarRepositoryImpl(db), repo),
      ComplementoPagoRepositoryImpl(db),
    );
    agregarParticipante = AgregarParticipanteServicioEventualUseCase(repo, empleadoRepo);
    retirarParticipante = RetirarParticipanteServicioEventualUseCase(repo);
    agregarCobertura = AgregarCoberturaServicioEventualUseCase(repo);
    corregirCobertura = CorregirCoberturaServicioEventualUseCase(repo);
    cancelarCobertura = CancelarCoberturaServicioEventualUseCase(repo);
    agregarCosto = AgregarCostoServicioEventualUseCase(repo);
    pagarCobertura = PagarCoberturaServicioEventualUseCase(repo, deudaRepo);
    listar = ListarServiciosEventualesUseCase(repo, clienteRepo, CuentaPorCobrarRepositoryImpl(db));
  });

  tearDown(() => db.close());

  Future<ClienteData> crearCliente() {
    return db.into(db.cliente).insertReturning(
          ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Corporativo Sur'),
        );
  }

  Future<EmpleadoData> crearEmpleado({int numero = 1}) {
    return db.into(db.empleado).insertReturning(
          EmpleadoCompanion.insert(
            numeroEmpleado: numero,
            nombres: 'Empleado$numero',
            apellidoPaterno: 'Apellido$numero',
            sexo: 'masculino',
            fechaNacimiento: DateTime(1990, 1, 1),
            curp: 'PEXJ90010${numero}HDFXXX0$numero',
            rfc: 'PEXJ90010${numero}AB$numero',
            nss: '1000000000$numero',
            estadoCivil: 'soltero',
            fechaIngreso: DateTime(2025, 1, 1),
            aniosExperienciaSeguridad: 3,
          ),
        );
  }

  Future<CuentaFinancieraData> crearCuenta() {
    return db.into(db.cuentaFinanciera).insertReturning(
          CuentaFinancieraCompanion.insert(
            codigo: 'CF-BBVA',
            nombre: 'BBVA',
            tipo: 'cuenta',
            saldoInicial: 100000000,
            fechaSaldoInicial: DateTime(2026, 1, 1),
          ),
        );
  }

  Future<ServicioEventualData> crearEventualExterno({int importe = 5000000}) async {
    final resultado = await crear.ejecutar(
      nombre: 'Concierto plaza',
      fechaHoraInicio: DateTime(2026, 5, 1, 18),
      fechaHoraFin: DateTime(2026, 5, 2, 2),
      importeAcordado: importe,
      tipoSolicitante: TipoSolicitanteServicioEventual.eventual,
      solicitanteNombre: 'Promotora Norte',
    );
    return (resultado as CrearServicioEventualExitoso).servicioEventual;
  }

  group('Alta', () {
    test('folio automático EVT-000001 y estatus programado', () async {
      final eventual = await crearEventualExterno();
      expect(eventual.folio, 'EVT-000001');
      expect(eventual.estatus, EstatusServicioEventual.programado.name);
      // schemaVersion 88 — vender ES generar la obligación de cobro:
      // exactamente una CxC, de origen eventual y por el importe de la
      // venta.
      final cuentas = await db.select(db.cuentaPorCobrar).get();
      expect(cuentas, hasLength(1));
      expect(cuentas.single.servicioEventualId, eventual.id);
      expect(cuentas.single.metodo, MetodoPagoCobro.noAplica.name);
      expect(cuentas.single.requiereComplemento, isFalse);
      expect(cuentas.single.saldoPendiente, 5000000);
    });

    test('el folio no se reutiliza entre eventuales', () async {
      await crearEventualExterno();
      final segundo = await crearEventualExterno();
      expect(segundo.folio, 'EVT-000002');
    });

    test('solicitante Cliente exige clienteId y deja el nombre externo nulo', () async {
      final cliente = await crearCliente();
      final resultado = await crear.ejecutar(
        nombre: 'Evento corporativo',
        fechaHoraInicio: DateTime(2026, 5, 1, 8),
        fechaHoraFin: DateTime(2026, 5, 1, 20),
        importeAcordado: 1000000,
        tipoSolicitante: TipoSolicitanteServicioEventual.cliente,
        clienteId: cliente.id,
        // Se mandan datos de externo A PROPÓSITO: el caso de uso tiene
        // que descartarlos, no guardarlos junto al Cliente.
        solicitanteNombre: 'Alguien más',
      );
      final eventual = (resultado as CrearServicioEventualExitoso).servicioEventual;
      expect(eventual.clienteId, cliente.id);
      expect(eventual.solicitanteNombre, isNull);
    });

    test('solicitante Cliente sin clienteId se rechaza', () async {
      final resultado = await crear.ejecutar(
        nombre: 'Evento corporativo',
        fechaHoraInicio: DateTime(2026, 5, 1, 8),
        fechaHoraFin: DateTime(2026, 5, 1, 20),
        importeAcordado: 1000000,
        tipoSolicitante: TipoSolicitanteServicioEventual.cliente,
      );
      expect(resultado, isA<CrearServicioEventualSolicitanteIncompleto>());
    });

    test('solicitante externo sin nombre se rechaza', () async {
      final resultado = await crear.ejecutar(
        nombre: 'Evento',
        fechaHoraInicio: DateTime(2026, 5, 1, 8),
        fechaHoraFin: DateTime(2026, 5, 1, 20),
        importeAcordado: 1000000,
        tipoSolicitante: TipoSolicitanteServicioEventual.eventual,
      );
      expect(resultado, isA<CrearServicioEventualSolicitanteIncompleto>());
    });

    test('Cliente inexistente se rechaza antes de escribir', () async {
      final resultado = await crear.ejecutar(
        nombre: 'Evento',
        fechaHoraInicio: DateTime(2026, 5, 1, 8),
        fechaHoraFin: DateTime(2026, 5, 1, 20),
        importeAcordado: 1000000,
        tipoSolicitante: TipoSolicitanteServicioEventual.cliente,
        clienteId: 'no-existe',
      );
      expect(resultado, isA<CrearServicioEventualClienteNoExiste>());
      expect(await db.select(db.servicioEventual).get(), isEmpty);
    });

    test('fin anterior al inicio e importe cero se rechazan', () async {
      final rango = await crear.ejecutar(
        nombre: 'Evento',
        fechaHoraInicio: DateTime(2026, 5, 2),
        fechaHoraFin: DateTime(2026, 5, 1),
        importeAcordado: 1000,
        tipoSolicitante: TipoSolicitanteServicioEventual.eventual,
        solicitanteNombre: 'X',
      );
      expect(rango, isA<CrearServicioEventualRangoInvalido>());

      final importe = await crear.ejecutar(
        nombre: 'Evento',
        fechaHoraInicio: DateTime(2026, 5, 1),
        fechaHoraFin: DateTime(2026, 5, 2),
        importeAcordado: 0,
        tipoSolicitante: TipoSolicitanteServicioEventual.eventual,
        solicitanteNombre: 'X',
      );
      expect(importe, isA<CrearServicioEventualImporteInvalido>());
    });
  });

  group('Corrección y ciclo', () {
    test('corregir exige motivo y registra el diff, no un snapshot', () async {
      final eventual = await crearEventualExterno();
      expect(
        await corregir.ejecutar(servicioEventualId: eventual.id, nombre: 'Otro', motivo: '   '),
        isA<CorregirServicioEventualMotivoRequerido>(),
      );

      await corregir.ejecutar(
        servicioEventualId: eventual.id,
        importeAcordado: 6000000,
        motivo: 'Se renegoció el precio',
      );
      final eventos = await repo.listarEventos(eventual.id);
      final correccion = eventos.firstWhere((e) => e.tipoEvento == TipoEventoServicioEventual.corregido.name);
      expect(correccion.estadoAnterior, contains('5000000'));
      expect(correccion.estadoNuevo, contains('6000000'));
      // Sólo el campo que cambió: el nombre no se tocó y no aparece.
      expect(correccion.estadoAnterior, isNot(contains('nombre')));
    });

    test('una corrección sin cambios reales no registra evento', () async {
      final eventual = await crearEventualExterno();
      await corregir.ejecutar(
        servicioEventualId: eventual.id,
        nombre: eventual.nombre,
        importeAcordado: eventual.importeAcordado,
        motivo: 'Sin cambios',
      );
      final eventos = await repo.listarEventos(eventual.id);
      expect(eventos.where((e) => e.tipoEvento == TipoEventoServicioEventual.corregido.name), isEmpty);
    });

    test('el rango se valida contra el estado resultante, no sólo contra lo enviado', () async {
      final eventual = await crearEventualExterno();
      // Sólo se mueve el inicio, pero lo deja después del fin guardado.
      final resultado = await corregir.ejecutar(
        servicioEventualId: eventual.id,
        fechaHoraInicio: DateTime(2026, 6, 1),
        motivo: 'Cambio de fecha',
      );
      expect(resultado, isA<CorregirServicioEventualRangoInvalido>());
    });

    test('un eventual cancelado ya no se corrige', () async {
      final eventual = await crearEventualExterno();
      await cancelar.ejecutar(servicioEventualId: eventual.id, motivo: 'Se cayó el evento');
      expect(
        await corregir.ejecutar(servicioEventualId: eventual.id, nombre: 'Otro', motivo: 'x'),
        isA<CorregirServicioEventualCancelado>(),
      );
    });

    test('finalizar no cobra, no paga y no cierra coberturas pendientes', () async {
      final eventual = await crearEventualExterno();
      final empleado = await crearEmpleado();
      final participante = (await agregarParticipante.ejecutar(
        servicioEventualId: eventual.id,
        empleadoId: empleado.id,
      ) as AgregarParticipanteServicioEventualExitoso)
          .participante;
      await agregarCobertura.ejecutar(
        servicioEventualId: eventual.id,
        participanteId: participante.id,
        fecha: DateTime(2026, 5, 1),
        horaInicioMinutos: 18 * 60,
        horaFinMinutos: 2 * 60,
        importeAcordado: 100000,
      );

      final resultado = await finalizar.ejecutar(servicioEventualId: eventual.id);
      expect(resultado, isA<FinalizarServicioEventualExitoso>());

      final coberturas = await repo.listarCoberturas(eventual.id);
      expect(coberturas.single.estatus, EstatusEjecucionServicioEventual.programada.name);
      // Finalizar no cobra: la CxC de la venta sigue con su saldo
      // íntegro y no se registró ningún Pago.
      expect((await db.select(db.cuentaPorCobrar).get()).single.saldoPendiente, 5000000);
      expect(await db.select(db.pago).get(), isEmpty);
      expect(await db.select(db.egreso).get(), isEmpty);
    });

    test('cancelar el evento arrastra lo programado y NO toca lo pagado', () async {
      final eventual = await crearEventualExterno();
      final cuenta = await crearCuenta();
      final empleado = await crearEmpleado();
      final participante = (await agregarParticipante.ejecutar(
        servicioEventualId: eventual.id,
        empleadoId: empleado.id,
      ) as AgregarParticipanteServicioEventualExitoso)
          .participante;

      final pagada = (await agregarCobertura.ejecutar(
        servicioEventualId: eventual.id,
        participanteId: participante.id,
        fecha: DateTime(2026, 5, 1),
        horaInicioMinutos: 18 * 60,
        horaFinMinutos: 23 * 60,
        importeAcordado: 100000,
      ) as AgregarCoberturaServicioEventualExitoso)
          .cobertura;
      await pagarCobertura.ejecutar(
        coberturaId: pagada.id,
        formaPago: FormaPago.transferencia.name,
        cuentaFinancieraId: cuenta.id,
      );

      final programada = (await agregarCobertura.ejecutar(
        servicioEventualId: eventual.id,
        participanteId: participante.id,
        fecha: DateTime(2026, 5, 2),
        horaInicioMinutos: 0,
        horaFinMinutos: 6 * 60,
        importeAcordado: 80000,
      ) as AgregarCoberturaServicioEventualExitoso)
          .cobertura;
      await agregarCosto.ejecutar(
        servicioEventualId: eventual.id,
        concepto: 'Traslado',
        monto: 30000,
        fecha: DateTime(2026, 5, 1),
      );

      await cancelar.ejecutar(servicioEventualId: eventual.id, motivo: 'Suspendido por lluvia');

      final coberturas = {for (final c in await repo.listarCoberturas(eventual.id)) c.id: c};
      expect(coberturas[pagada.id]!.estatus, EstatusEjecucionServicioEventual.pagada.name);
      expect(coberturas[pagada.id]!.egresoId, isNotNull);
      expect(coberturas[programada.id]!.estatus, EstatusEjecucionServicioEventual.cancelada.name);
      expect((await repo.listarCostos(eventual.id)).single.estatus,
          EstatusEjecucionServicioEventual.cancelada.name);

      // El Egreso del pago real sigue existiendo y sigue registrado:
      // cancelar el evento no devuelve dinero por sí solo.
      final egresos = await db.select(db.egreso).get();
      expect(egresos, hasLength(1));
      expect(egresos.single.estatus, 'registrado');
    });

    test('cancelar dos veces no vuelve a escribir', () async {
      final eventual = await crearEventualExterno();
      await cancelar.ejecutar(servicioEventualId: eventual.id, motivo: 'Primera');
      expect(
        await cancelar.ejecutar(servicioEventualId: eventual.id, motivo: 'Segunda'),
        isA<CancelarServicioEventualYaCancelado>(),
      );
    });
  });

  group('Participantes', () {
    test('empleado y externo son excluyentes', () async {
      final eventual = await crearEventualExterno();
      expect(
        await agregarParticipante.ejecutar(servicioEventualId: eventual.id),
        isA<AgregarParticipanteServicioEventualIdentidadInvalida>(),
      );
      final empleado = await crearEmpleado();
      expect(
        await agregarParticipante.ejecutar(
          servicioEventualId: eventual.id,
          empleadoId: empleado.id,
          nombreExterno: 'También externo',
        ),
        isA<AgregarParticipanteServicioEventualIdentidadInvalida>(),
      );
    });

    test('el mismo empleado no se agrega dos veces al mismo evento', () async {
      final eventual = await crearEventualExterno();
      final empleado = await crearEmpleado();
      await agregarParticipante.ejecutar(servicioEventualId: eventual.id, empleadoId: empleado.id);
      expect(
        await agregarParticipante.ejecutar(servicioEventualId: eventual.id, empleadoId: empleado.id),
        isA<AgregarParticipanteServicioEventualDuplicado>(),
      );
    });

    test('un participante con coberturas no se retira', () async {
      final eventual = await crearEventualExterno();
      final participante = (await agregarParticipante.ejecutar(
        servicioEventualId: eventual.id,
        nombreExterno: 'Refuerzo externo',
      ) as AgregarParticipanteServicioEventualExitoso)
          .participante;
      await agregarCobertura.ejecutar(
        servicioEventualId: eventual.id,
        participanteId: participante.id,
        fecha: DateTime(2026, 5, 1),
        horaInicioMinutos: 8 * 60,
        horaFinMinutos: 20 * 60,
        importeAcordado: 50000,
      );
      expect(
        await retirarParticipante.ejecutar(participanteId: participante.id),
        isA<RetirarParticipanteServicioEventualTieneCoberturas>(),
      );
    });

    test('un participante sin coberturas sí se retira', () async {
      final eventual = await crearEventualExterno();
      final participante = (await agregarParticipante.ejecutar(
        servicioEventualId: eventual.id,
        nombreExterno: 'Capturado por error',
      ) as AgregarParticipanteServicioEventualExitoso)
          .participante;
      expect(
        await retirarParticipante.ejecutar(participanteId: participante.id),
        isA<RetirarParticipanteServicioEventualExitoso>(),
      );
      expect(await repo.listarParticipantes(eventual.id), isEmpty);
    });
  });

  group('Coberturas', () {
    late ServicioEventualData eventual;
    late ServicioEventualParticipanteData participante;

    setUp(() async {
      eventual = await crearEventualExterno();
      participante = (await agregarParticipante.ejecutar(
        servicioEventualId: eventual.id,
        nombreExterno: 'Refuerzo externo',
      ) as AgregarParticipanteServicioEventualExitoso)
          .participante;
    });

    test('programar no crea Egreso ni cargo a tarjeta', () async {
      await agregarCobertura.ejecutar(
        servicioEventualId: eventual.id,
        participanteId: participante.id,
        fecha: DateTime(2026, 5, 1),
        horaInicioMinutos: 8 * 60,
        horaFinMinutos: 20 * 60,
        importeAcordado: 50000,
      );
      expect(await db.select(db.egreso).get(), isEmpty);
      expect(await db.select(db.movimientoDeuda).get(), isEmpty);
    });

    test('un turno que cruza la medianoche es válido y dura lo que debe', () async {
      final resultado = await agregarCobertura.ejecutar(
        servicioEventualId: eventual.id,
        participanteId: participante.id,
        fecha: DateTime(2026, 5, 1),
        horaInicioMinutos: 20 * 60,
        horaFinMinutos: 6 * 60,
        importeAcordado: 50000,
      );
      expect(resultado, isA<AgregarCoberturaServicioEventualExitoso>());
      expect(
        duracionCoberturaMinutos(horaInicioMinutos: 20 * 60, horaFinMinutos: 6 * 60),
        10 * 60,
      );
    });

    test('inicio igual a fin se rechaza', () async {
      expect(
        await agregarCobertura.ejecutar(
          servicioEventualId: eventual.id,
          participanteId: participante.id,
          fecha: DateTime(2026, 5, 1),
          horaInicioMinutos: 8 * 60,
          horaFinMinutos: 8 * 60,
          importeAcordado: 50000,
        ),
        isA<AgregarCoberturaServicioEventualHorarioInvalido>(),
      );
    });

    test('un participante de otro evento se rechaza', () async {
      final otro = await crearEventualExterno();
      expect(
        await agregarCobertura.ejecutar(
          servicioEventualId: otro.id,
          participanteId: participante.id,
          fecha: DateTime(2026, 5, 1),
          horaInicioMinutos: 8 * 60,
          horaFinMinutos: 20 * 60,
          importeAcordado: 50000,
        ),
        isA<AgregarCoberturaServicioEventualParticipanteInvalido>(),
      );
    });

    test('una cobertura pagada no se corrige ni se cancela', () async {
      final cuenta = await crearCuenta();
      final cobertura = (await agregarCobertura.ejecutar(
        servicioEventualId: eventual.id,
        participanteId: participante.id,
        fecha: DateTime(2026, 5, 1),
        horaInicioMinutos: 8 * 60,
        horaFinMinutos: 20 * 60,
        importeAcordado: 50000,
      ) as AgregarCoberturaServicioEventualExitoso)
          .cobertura;
      await pagarCobertura.ejecutar(
        coberturaId: cobertura.id,
        formaPago: FormaPago.transferencia.name,
        cuentaFinancieraId: cuenta.id,
      );

      expect(
        await corregirCobertura.ejecutar(coberturaId: cobertura.id, importeAcordado: 90000, motivo: 'x'),
        isA<CorregirCoberturaServicioEventualPagada>(),
      );
      expect(
        await cancelarCobertura.ejecutar(coberturaId: cobertura.id, motivo: 'x'),
        isA<CancelarCoberturaServicioEventualPagada>(),
      );
    });
  });

  group('Totales del listado', () {
    test('derivan de las coberturas y costos, sin persistirse', () async {
      final eventual = await crearEventualExterno(importe: 1000000);
      final cuenta = await crearCuenta();
      final participante = (await agregarParticipante.ejecutar(
        servicioEventualId: eventual.id,
        nombreExterno: 'Refuerzo',
      ) as AgregarParticipanteServicioEventualExitoso)
          .participante;

      final cobertura = (await agregarCobertura.ejecutar(
        servicioEventualId: eventual.id,
        participanteId: participante.id,
        fecha: DateTime(2026, 5, 1),
        horaInicioMinutos: 8 * 60,
        horaFinMinutos: 20 * 60,
        importeAcordado: 300000,
      ) as AgregarCoberturaServicioEventualExitoso)
          .cobertura;
      await agregarCosto.ejecutar(
        servicioEventualId: eventual.id,
        concepto: 'Traslado',
        monto: 100000,
        fecha: DateTime(2026, 5, 1),
      );
      await pagarCobertura.ejecutar(
        coberturaId: cobertura.id,
        formaPago: FormaPago.transferencia.name,
        cuentaFinancieraId: cuenta.id,
      );

      final renglon = (await listar.ejecutar()).single;
      expect(renglon.totales.costoComprometido, 400000);
      expect(renglon.totales.costoPagado, 300000);
      expect(renglon.resultado, 600000);
      expect(renglon.nombreSolicitante, 'Promotora Norte');
    });

    test('una cobertura cancelada deja de contar en el costo', () async {
      final eventual = await crearEventualExterno(importe: 1000000);
      final participante = (await agregarParticipante.ejecutar(
        servicioEventualId: eventual.id,
        nombreExterno: 'Refuerzo',
      ) as AgregarParticipanteServicioEventualExitoso)
          .participante;
      final cobertura = (await agregarCobertura.ejecutar(
        servicioEventualId: eventual.id,
        participanteId: participante.id,
        fecha: DateTime(2026, 5, 1),
        horaInicioMinutos: 8 * 60,
        horaFinMinutos: 20 * 60,
        importeAcordado: 300000,
      ) as AgregarCoberturaServicioEventualExitoso)
          .cobertura;

      await cancelarCobertura.ejecutar(coberturaId: cobertura.id, motivo: 'No se presentó');
      expect((await listar.ejecutar()).single.totales.costoComprometido, 0);
    });

    test('el nombre del solicitante sale del Cliente cuando lo hay', () async {
      final cliente = await crearCliente();
      await crear.ejecutar(
        nombre: 'Evento corporativo',
        fechaHoraInicio: DateTime(2026, 5, 1, 8),
        fechaHoraFin: DateTime(2026, 5, 1, 20),
        importeAcordado: 1000000,
        tipoSolicitante: TipoSolicitanteServicioEventual.cliente,
        clienteId: cliente.id,
      );
      expect((await listar.ejecutar()).single.nombreSolicitante, 'Corporativo Sur');
    });
  });

  test('el estatus filtra el listado', () async {
    final uno = await crearEventualExterno();
    await crearEventualExterno();
    await cancelar.ejecutar(servicioEventualId: uno.id, motivo: 'Cancelado');

    expect((await listar.ejecutar()).length, 2);
    expect((await listar.ejecutar(estatus: EstatusServicioEventual.cancelado)).single.servicioEventual.id, uno.id);
    expect((await listar.ejecutar(estatus: EstatusServicioEventual.programado)).length, 1);
  });
}
