// Etapa 5 (Descuentos programados — CRUD corregible, trazabilidad y
// consistencia con Nómina), Sección 13: escenario integral exacto del
// pedido. Empleado A, préstamo $5,000 en 5 cuotas de $1,000, se pagan
// 2 Nóminas reales (aplicado=$2,000/pendiente=$3,000), se corrige el
// monto total hacia arriba ($6,000: aplicado intacto, pendiente=$4,000,
// cuotas futuras correctas), hacia abajo válido ($4,000:
// aplicado=$2,000/pendiente=$2,000), hacia abajo inválido ($1,500:
// rechazo, CERO mutación), corrección con una cuota `reservada` en una
// Nómina Borrador, y finalmente cancelación (aplicado histórico se
// conserva, sin cuotas fantasma). También cubre atomicidad (rollback
// real) — Secciones 3, 4, 13 y 14 del pedido.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/features/finanzas/data/repositories/cuenta_financiera_repository_impl.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/descuentos_personal/data/repositories/descuento_programado_repository_impl.dart';
import 'package:riseg_one/features/descuentos_personal/domain/repositories/descuento_programado_repository.dart';
import 'package:riseg_one/features/descuentos_personal/domain/usecases/cancelar_saldo_descuento_programado_usecase.dart';
import 'package:riseg_one/features/descuentos_personal/domain/usecases/corregir_descuento_programado_usecase.dart';
import 'package:riseg_one/features/descuentos_personal/domain/usecases/registrar_descuento_programado_usecase.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/repositories/nomina_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/repositories/pago_nomina_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/tables/nomina_table.dart';
import 'package:riseg_one/features/nomina/domain/usecases/actualizar_nomina_desde_personal_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/cerrar_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/evaluar_renglones_requieren_revision_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/generar_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/registrar_pago_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/resolver_sueldo_empleado_nomina.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/puesto_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';
import 'package:riseg_one/features/tiempos_extra/data/repositories/tiempo_extra_repository_impl.dart';

void main() {
  late AppDatabase db;
  late DescuentoProgramadoRepository descuentoRepo;
  late RegistrarDescuentoProgramadoUseCase registrarDescuento;
  late CorregirDescuentoProgramadoUseCase corregirDescuento;
  late CancelarSaldoDescuentoProgramadoUseCase cancelarSaldo;
  late GenerarNominaUseCase generarNomina;
  late CerrarNominaUseCase cerrarNomina;
  late RegistrarPagoNominaUseCase registrarPagoNomina;
  late NominaRepositoryImpl nominaRepo;
  late ActualizarNominaDesdePersonalUseCase actualizarDesdePersonal;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final asignacionServicioRepo = AsignacionServicioRepositoryImpl(db);
    final empleadoRepo = EmpleadoRepositoryImpl(db, asignacionServicioRepo);
    final servicioRepo = ServicioRepositoryImpl(db, asignacionServicioRepo);
    final catalogoRepo = CatalogoRepositoryImpl(db);
    final puestoRepo = PuestoRepositoryImpl(db);
    final codigoSecuencia = CodigoSecuenciaService(db);
    final generarCodigo = GenerarCodigoUseCase(codigoSecuencia);
    final egresoRepo = EgresoRepositoryImpl(db);
    final asignacionRepo = AsignacionRepositoryImpl(db);

    descuentoRepo = DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db));
    registrarDescuento = RegistrarDescuentoProgramadoUseCase(descuentoRepo, empleadoRepo, generarCodigo);
    corregirDescuento = CorregirDescuentoProgramadoUseCase(descuentoRepo);
    cancelarSaldo = CancelarSaldoDescuentoProgramadoUseCase(descuentoRepo);

    nominaRepo = NominaRepositoryImpl(
      db,
      asignacionRepo,
      descuentoRepo,
      TiempoExtraRepositoryImpl(
        db,
        egresoRepo,
        DeudaRepositoryImpl(db, egresoRepo),
        codigoSecuencia,
        empleadoRepo,
        servicioRepo,
      ),
      PagoNominaRepositoryImpl(db, egresoRepo, descuentoRepo),
    );
    final resolverSueldo = ResolverSueldoEmpleadoNomina(empleadoRepo, asignacionServicioRepo, servicioRepo, catalogoRepo);
    generarNomina = GenerarNominaUseCase(nominaRepo, empleadoRepo, puestoRepo, catalogoRepo, resolverSueldo, generarCodigo);
    cerrarNomina = CerrarNominaUseCase(nominaRepo, EvaluarRenglonesRequierenRevisionUseCase(nominaRepo, empleadoRepo, resolverSueldo));
    actualizarDesdePersonal = ActualizarNominaDesdePersonalUseCase(nominaRepo, empleadoRepo, puestoRepo, catalogoRepo, resolverSueldo);
    registrarPagoNomina = RegistrarPagoNominaUseCase(
      PagoNominaRepositoryImpl(db, egresoRepo, descuentoRepo),
      nominaRepo,
      generarCodigo,
     CuentaFinancieraRepositoryImpl(db),);

    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(id: const Value('usuario-maestro'), nombre: 'Maestro', nombreUsuario: 'maestro', passwordHash: 'x'),
        );
  });

  tearDown(() => db.close());

  Future<EmpleadoData> crearEmpleado() {
    return db.into(db.empleado).insertReturning(
          EmpleadoCompanion.insert(
            numeroEmpleado: 1,
            nombres: 'Empleado',
            apellidoPaterno: 'A',
            sexo: 'masculino',
            fechaNacimiento: DateTime(1990, 1, 1),
            curp: 'PEXJ900101HDFXXX01',
            rfc: 'PEXJ900101AB1',
            nss: '10000000001',
            estadoCivil: 'soltero',
            fechaIngreso: DateTime(2025, 1, 1),
            aniosExperienciaSeguridad: 3,
            sueldoMensualAdministrativo: const Value(3000000),
          ),
        );
  }

  Future<void> pagarNominaCompleta(int anio, int mes, TipoPeriodoNomina tipo) async {
    final generado = (await generarNomina.ejecutar(anio: anio, mes: mes, tipo: tipo)) as GenerarNominaExitoso;
    await cerrarNomina.ejecutar(nominaId: generado.nomina.id);
    final renglon = (await nominaRepo.listarEmpleados(generado.nomina.id)).single;
    await registrarPagoNomina.ejecutar(
      nominaId: generado.nomina.id,
      fechaPago: DateTime(anio, mes, 20),
      formaPago: 'transferencia',
      cuentaFinancieraId: await _cuentaDePrueba(db),
      aplicaciones: [(nominaEmpleadoId: renglon.id, monto: renglon.totalAPagar)],
    );
  }

  test(r'escenario integral completo: $5,000/5 cuotas de $1,000 → 2 pagadas → corregir arriba/abajo/rechazo/reservada/cancelar', () async {
    final empleado = await crearEmpleado();
    final registrado = await registrarDescuento.ejecutar(
      empleadoId: empleado.id,
      tipo: 'prestamo',
      fechaRegistro: DateTime(2026, 1, 1),
      importeOriginal: 500000,
      numeroCuotas: 5,
      fechaPrimeraCuota: DateTime(2026, 1, 20),
    );
    final descuentoId = (registrado as RegistrarDescuentoProgramadoExitoso).descuento.id;

    // Paga 2 quincenas completas: aplicado=$2,000, pendiente=$3,000.
    await pagarNominaCompleta(2026, 1, TipoPeriodoNomina.primera);
    await pagarNominaCompleta(2026, 1, TipoPeriodoNomina.segunda);
    var actual = (await descuentoRepo.obtenerPorId(descuentoId))!;
    expect(actual.saldoPendiente, 300000, reason: r'aplicado=$2,000, pendiente=$3,000');
    expect(actual.importeOriginal, 500000);

    // Corrección hacia arriba: $5,000 → $6,000. aplicado sigue $2,000,
    // pendiente pasa a $4,000, con un nuevo plan de cuotas futuras.
    final arriba = await corregirDescuento.ejecutar(
      descuentoProgramadoId: descuentoId,
      importeOriginal: 600000,
      numeroCuotas: 4,
      fechaPrimeraCuota: DateTime(2026, 2, 20),
      motivo: 'Se detectó que el préstamo real era mayor',
    );
    expect(arriba, isA<CorregirDescuentoProgramadoExitoso>());
    actual = (await descuentoRepo.obtenerPorId(descuentoId))!;
    expect(actual.importeOriginal, 600000);
    expect(actual.saldoPendiente, 400000, reason: r'aplicado histórico $2,000 nunca se toca');
    expect(actual.estatus, 'activo');
    var cuotas = await descuentoRepo.listarCuotas(descuentoId);
    expect(cuotas.where((c) => c.estatus == 'aplicada'), hasLength(2), reason: 'las 2 cuotas ya pagadas siguen intactas');
    final futurasArriba = cuotas.where((c) => c.estatus == 'pendiente').toList();
    expect(futurasArriba, hasLength(4));
    expect(futurasArriba.fold<int>(0, (s, c) => s + c.importeProgramado), 400000, reason: 'el nuevo plan suma exacto el nuevo pendiente');

    // Corrección hacia abajo VÁLIDA: $6,000 → $4,000. aplicado sigue
    // $2,000, pendiente baja a $2,000.
    final abajoValido = await corregirDescuento.ejecutar(
      descuentoProgramadoId: descuentoId,
      importeOriginal: 400000,
      numeroCuotas: 2,
      fechaPrimeraCuota: DateTime(2026, 2, 20),
      motivo: 'El préstamo real era menor de lo corregido antes',
    );
    expect(abajoValido, isA<CorregirDescuentoProgramadoExitoso>());
    actual = (await descuentoRepo.obtenerPorId(descuentoId))!;
    expect(actual.importeOriginal, 400000);
    expect(actual.saldoPendiente, 200000);

    // Corrección hacia abajo INVÁLIDA: $4,000 → $1,500 (por debajo de
    // lo ya aplicado, $2,000) — rechazo, CERO mutación.
    final antesDelRechazo = (await descuentoRepo.obtenerPorId(descuentoId))!;
    final cuotasAntesDelRechazo = await descuentoRepo.listarCuotas(descuentoId);
    final rechazado = await corregirDescuento.ejecutar(
      descuentoProgramadoId: descuentoId,
      importeOriginal: 150000,
      numeroCuotas: 1,
      fechaPrimeraCuota: DateTime(2026, 2, 20),
      motivo: 'Intento de corrección por debajo de lo aplicado',
    );
    expect(rechazado, isA<CorregirDescuentoProgramadoExcedeLoAplicado>());
    expect((rechazado as CorregirDescuentoProgramadoExcedeLoAplicado).totalAplicado, 200000);
    final trasElRechazo = (await descuentoRepo.obtenerPorId(descuentoId))!;
    expect(trasElRechazo.importeOriginal, antesDelRechazo.importeOriginal, reason: 'cero mutación');
    expect(trasElRechazo.saldoPendiente, antesDelRechazo.saldoPendiente, reason: 'cero mutación');
    final cuotasTrasElRechazo = await descuentoRepo.listarCuotas(descuentoId);
    expect(cuotasTrasElRechazo.length, cuotasAntesDelRechazo.length, reason: 'ninguna cuota nueva/cancelada por el intento rechazado');
    for (var i = 0; i < cuotasAntesDelRechazo.length; i++) {
      expect(cuotasTrasElRechazo[i].estatus, cuotasAntesDelRechazo[i].estatus);
      expect(cuotasTrasElRechazo[i].importeProgramado, cuotasAntesDelRechazo[i].importeProgramado);
    }

    // Corrección con una cuota `reservada`: genera una Nómina que
    // reserva la próxima cuota futura, y corrige el monto total con
    // esa cuota todavía reservada — debe liberarse y el plan nuevo
    // nace `pendiente`, nunca sigue atado al renglón viejo.
    final generadoConReserva = (await generarNomina.ejecutar(anio: 2026, mes: 2, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
    final renglonConReserva = (await nominaRepo.listarEmpleados(generadoConReserva.nomina.id)).single;
    final cuotaReservada = (await descuentoRepo.listarCuotas(descuentoId)).firstWhere((c) => c.estatus == 'reservada');
    expect(cuotaReservada.nominaEmpleadoId, renglonConReserva.id);

    final conReserva = await corregirDescuento.ejecutar(
      descuentoProgramadoId: descuentoId,
      importeOriginal: 300000,
      numeroCuotas: 1,
      fechaPrimeraCuota: DateTime(2026, 3, 5),
      motivo: 'Ajuste final con una cuota ya reservada en una Nómina Borrador',
    );
    expect(conReserva, isA<CorregirDescuentoProgramadoExitoso>());
    final cuotasConReserva = await descuentoRepo.listarCuotas(descuentoId);
    expect(cuotasConReserva.where((c) => c.estatus == 'reservada'), isEmpty, reason: 'la cuota reservada se liberó, no sigue atada');
    expect(cuotasConReserva.where((c) => c.estatus == 'pendiente'), hasLength(1));
    // El renglón Borrador conserva su total cacheado hasta que algo lo
    // vuelva a resolver — mismo comportamiento exacto que un préstamo
    // nuevo registrado después de generar la Nómina (ver
    // "Actualizar desde Personal" en `descuentos_personal_nomina_integration_test.dart`):
    // liberar la cuota reservada NO reescribe `descuentosProgramados`
    // por sí sola, hace falta el mismo mecanismo de siempre.
    final renglonAntesDeActualizar = (await nominaRepo.listarEmpleados(generadoConReserva.nomina.id)).single;
    expect(renglonAntesDeActualizar.descuentosProgramados, 100000, reason: 'el renglón conserva su total cacheado hasta que se actualice');
    final actualizado = await actualizarDesdePersonal.ejecutar(nominaId: generadoConReserva.nomina.id);
    expect(actualizado, isA<ActualizarNominaDesdePersonalExitoso>());
    final renglonTrasCorreccion = (await nominaRepo.listarEmpleados(generadoConReserva.nomina.id)).single;
    expect(
      renglonTrasCorreccion.descuentosProgramados,
      0,
      reason: 'tras actualizar desde Personal, el renglón ya no reserva ninguna cuota de este descuento (la nueva cae en marzo)',
    );

    // Cancelación: el aplicado histórico ($2,000) se conserva, nunca
    // vuelve a Nómina; no aparecen cuotas fantasma.
    final cancelado = await cancelarSaldo.ejecutar(descuentoProgramadoId: descuentoId, motivo: 'Empleado liquidó por fuera');
    expect(cancelado, isA<CancelarSaldoDescuentoProgramadoExitoso>());
    final final_ = (await descuentoRepo.obtenerPorId(descuentoId))!;
    expect(final_.saldoPendiente, 0);
    expect(final_.estatus, 'cancelado');
    final cuotasFinales = await descuentoRepo.listarCuotas(descuentoId);
    expect(cuotasFinales.where((c) => c.estatus == 'aplicada'), hasLength(2), reason: 'el historial de lo aplicado nunca se toca al cancelar');
    expect(cuotasFinales.where((c) => c.estatus == 'pendiente'), isEmpty);

    final generadoTrasCancelar = (await generarNomina.ejecutar(anio: 2026, mes: 3, tipo: TipoPeriodoNomina.segunda)) as GenerarNominaExitoso;
    final renglonTrasCancelar = (await nominaRepo.listarEmpleados(generadoTrasCancelar.nomina.id)).single;
    expect(renglonTrasCancelar.descuentosProgramados, 0, reason: 'un descuento cancelado nunca vuelve a aparecer en una Nómina futura');
  });

  test('bloquea corregir un descuento que ya no está activo (liquidado)', () async {
    final empleado = await crearEmpleado();
    final registrado = await registrarDescuento.ejecutar(
      empleadoId: empleado.id,
      tipo: 'prestamo',
      fechaRegistro: DateTime(2026, 1, 1),
      importeOriginal: 100000,
      numeroCuotas: 1,
      fechaPrimeraCuota: DateTime(2026, 1, 20),
    );
    final descuentoId = (registrado as RegistrarDescuentoProgramadoExitoso).descuento.id;
    await pagarNominaCompleta(2026, 1, TipoPeriodoNomina.primera);
    expect((await descuentoRepo.obtenerPorId(descuentoId))!.estatus, 'liquidado');

    final resultado = await corregirDescuento.ejecutar(
      descuentoProgramadoId: descuentoId,
      importeOriginal: 200000,
      numeroCuotas: 1,
      fechaPrimeraCuota: DateTime(2026, 2, 20),
      motivo: 'Intento sobre un descuento ya liquidado',
    );
    expect(resultado, isA<CorregirDescuentoProgramadoNoActivo>());
  });

  test('exige motivo para corregir', () async {
    final empleado = await crearEmpleado();
    final registrado = await registrarDescuento.ejecutar(
      empleadoId: empleado.id,
      tipo: 'prestamo',
      fechaRegistro: DateTime(2026, 1, 1),
      importeOriginal: 100000,
      numeroCuotas: 1,
      fechaPrimeraCuota: DateTime(2026, 1, 20),
    );
    final descuentoId = (registrado as RegistrarDescuentoProgramadoExitoso).descuento.id;

    final resultado = await corregirDescuento.ejecutar(descuentoProgramadoId: descuentoId, observaciones: 'Sin motivo', motivo: '   ');
    expect(resultado, isA<CorregirDescuentoProgramadoMotivoRequerido>());
  });

  test('exige numeroCuotas/fechaPrimeraCuota cuando el monto total cambia y el nuevo saldo es > 0', () async {
    final empleado = await crearEmpleado();
    final registrado = await registrarDescuento.ejecutar(
      empleadoId: empleado.id,
      tipo: 'prestamo',
      fechaRegistro: DateTime(2026, 1, 1),
      importeOriginal: 100000,
      numeroCuotas: 1,
      fechaPrimeraCuota: DateTime(2026, 1, 20),
    );
    final descuentoId = (registrado as RegistrarDescuentoProgramadoExitoso).descuento.id;

    final resultado = await corregirDescuento.ejecutar(
      descuentoProgramadoId: descuentoId,
      importeOriginal: 200000,
      motivo: 'Cambia el monto sin dar plan nuevo',
    );
    expect(resultado, isA<CorregirDescuentoProgramadoRequiereNuevoPlan>());
  });

  test('corregir solo campos administrativos (sin tocar importeOriginal) no exige ningún plan nuevo', () async {
    final empleado = await crearEmpleado();
    final registrado = await registrarDescuento.ejecutar(
      empleadoId: empleado.id,
      tipo: 'prestamo',
      fechaRegistro: DateTime(2026, 1, 1),
      importeOriginal: 100000,
      numeroCuotas: 2,
      fechaPrimeraCuota: DateTime(2026, 1, 20),
    );
    final descuentoId = (registrado as RegistrarDescuentoProgramadoExitoso).descuento.id;
    final cuotasAntes = await descuentoRepo.listarCuotas(descuentoId);

    final resultado = await corregirDescuento.ejecutar(
      descuentoProgramadoId: descuentoId,
      tipo: 'botas',
      observaciones: 'Era realmente un cobro de botas, no un préstamo',
      motivo: 'Corrección de captura del tipo',
    );
    expect(resultado, isA<CorregirDescuentoProgramadoExitoso>());
    final actualizado = (resultado as CorregirDescuentoProgramadoExitoso).descuento;
    expect(actualizado.tipo, 'botas');
    expect(actualizado.observaciones, 'Era realmente un cobro de botas, no un préstamo');
    final cuotasDespues = await descuentoRepo.listarCuotas(descuentoId);
    expect(cuotasDespues.length, cuotasAntes.length, reason: 'ninguna cuota se toca cuando el monto total no cambió');
  });

  test('corregir sin ningún cambio real no escribe ningún movimiento de correccion', () async {
    final empleado = await crearEmpleado();
    final registrado = await registrarDescuento.ejecutar(
      empleadoId: empleado.id,
      tipo: 'prestamo',
      fechaRegistro: DateTime(2026, 1, 1),
      importeOriginal: 100000,
      numeroCuotas: 1,
      fechaPrimeraCuota: DateTime(2026, 1, 20),
    );
    final descuentoId = (registrado as RegistrarDescuentoProgramadoExitoso).descuento.id;
    final movimientosAntes = await descuentoRepo.listarMovimientos(descuentoId);

    final resultado = await corregirDescuento.ejecutar(
      descuentoProgramadoId: descuentoId,
      tipo: 'prestamo',
      motivo: 'Nada realmente cambió',
    );
    expect(resultado, isA<CorregirDescuentoProgramadoExitoso>());
    final movimientosDespues = await descuentoRepo.listarMovimientos(descuentoId);
    expect(
      movimientosDespues.where((m) => m.tipoMovimiento == 'correccion'),
      isEmpty,
      reason: 'una "corrección" que no cambió ningún campo no es una corrección real',
    );
    expect(movimientosDespues.length, movimientosAntes.length);
  });

  test('atomicidad: una falla real a mitad de la corrección revierte TODO (rollback completo)', () async {
    final empleado = await crearEmpleado();
    final registrado = await registrarDescuento.ejecutar(
      empleadoId: empleado.id,
      tipo: 'prestamo',
      fechaRegistro: DateTime(2026, 1, 1),
      importeOriginal: 100000,
      numeroCuotas: 1,
      fechaPrimeraCuota: DateTime(2026, 1, 20),
    );
    final descuentoId = (registrado as RegistrarDescuentoProgramadoExitoso).descuento.id;
    final antes = (await descuentoRepo.obtenerPorId(descuentoId))!;
    final cuotasAntes = await descuentoRepo.listarCuotas(descuentoId);
    final movimientosAntes = await descuentoRepo.listarMovimientos(descuentoId);

    // Provoca una falla real a mitad de la transacción: la segunda
    // cuota del plan nuevo viola el `CHECK (importe_programado > 0)`
    // real de la tabla, DESPUÉS de que la primera fila del plan nuevo
    // ya se insertó exitosamente — el resto de la transacción
    // (incluida la actualización del padre y el registro del
    // movimiento) debe revertirse por completo.
    await expectLater(
      descuentoRepo.corregir(
        descuentoProgramadoId: descuentoId,
        nuevoImporteOriginal: 200000,
        nuevoSaldoPendiente: 200000,
        nuevoPlanCuotas: [
          (numeroCuota: 1, fechaProgramada: DateTime(2026, 2, 20), importe: 100000),
          (numeroCuota: 2, fechaProgramada: DateTime(2026, 3, 5), importe: 0),
        ],
        motivo: 'Provoca una falla real a mitad de transacción',
      ),
      throwsA(anything),
    );

    final despues = (await descuentoRepo.obtenerPorId(descuentoId))!;
    expect(despues.importeOriginal, antes.importeOriginal, reason: 'rollback completo — el padre nunca quedó a medias');
    expect(despues.saldoPendiente, antes.saldoPendiente);
    expect(despues.estatus, antes.estatus);
    final cuotasDespues = await descuentoRepo.listarCuotas(descuentoId);
    expect(cuotasDespues.length, cuotasAntes.length, reason: 'ninguna cuota del plan nuevo sobrevive el rollback');
    expect(cuotasDespues.single.estatus, cuotasAntes.single.estatus, reason: 'la cuota original nunca se marcó cancelada a medias');
    final movimientosDespues = await descuentoRepo.listarMovimientos(descuentoId);
    expect(movimientosDespues.length, movimientosAntes.length, reason: 'ningún movimiento de correccion a medio escribir sobrevive');
  });
}

/// La cuenta de origen de los pagos de Nómina en esta prueba.
///
/// Reutiliza la primera que el archivo ya haya creado; sólo inventa una
/// si no hay ninguna. Desde la Etapa de integridad financiera, un pago
/// de Nómina con monto > 0 exige cuenta: sin ella el Egreso nacería sin
/// origen y ningún saldo bajaría.
Future<String> _cuentaDePrueba(AppDatabase db) async {
  final existentes = await db.select(db.cuentaFinanciera).get();
  if (existentes.isNotEmpty) return existentes.first.id;
  final cuenta = await db.into(db.cuentaFinanciera).insertReturning(
        CuentaFinancieraCompanion.insert(
          codigo: 'CF-NOMINA-PRUEBA',
          nombre: 'Cuenta de prueba',
          tipo: 'banco',
          saldoInicial: 100000000, // fondeada: la v91 rechaza salidas sin saldo
          fechaSaldoInicial: DateTime(2020, 1, 1),
        ),
      );
  return cuenta.id;
}
