// Pedido explícito: dar al Maestro una forma de eliminar por pruebas
// un descuento programado ya cancelado — nunca si alguna cuota ya se
// aplicó realmente en una Nómina (esa historia no se borra en
// silencio).

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/descuentos_personal/data/repositories/descuento_programado_repository_impl.dart';
import 'package:riseg_one/features/descuentos_personal/domain/repositories/descuento_programado_repository.dart';
import 'package:riseg_one/features/descuentos_personal/domain/usecases/cancelar_saldo_descuento_programado_usecase.dart';
import 'package:riseg_one/features/descuentos_personal/domain/usecases/eliminar_descuento_programado_fisicamente_usecase.dart';
import 'package:riseg_one/features/descuentos_personal/domain/usecases/registrar_descuento_programado_usecase.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';

void main() {
  late AppDatabase db;
  late DescuentoProgramadoRepositoryImpl descuentoRepo;
  late EmpleadoRepositoryImpl empleadoRepo;
  late RegistrarDescuentoProgramadoUseCase registrar;
  late CancelarSaldoDescuentoProgramadoUseCase cancelarSaldo;
  late EliminarDescuentoProgramadoFisicamenteUseCase eliminarFisicamente;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    final asignacionServicioRepo = AsignacionServicioRepositoryImpl(db);
    empleadoRepo = EmpleadoRepositoryImpl(db, asignacionServicioRepo);
    descuentoRepo = DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db));
    registrar = RegistrarDescuentoProgramadoUseCase(descuentoRepo, empleadoRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));
    cancelarSaldo = CancelarSaldoDescuentoProgramadoUseCase(descuentoRepo);
    eliminarFisicamente = EliminarDescuentoProgramadoFisicamenteUseCase(descuentoRepo);
  });

  tearDown(() => db.close());

  Future<EmpleadoData> crearEmpleadoDePrueba(int numero) {
    final n = numero.toString().padLeft(2, '0');
    return db.into(db.empleado).insertReturning(
          EmpleadoCompanion.insert(
            numeroEmpleado: numero,
            nombres: 'Empleado$n',
            apellidoPaterno: 'Apellido$n',
            sexo: 'masculino',
            fechaNacimiento: DateTime(1990, 1, 1),
            curp: 'PEXJ900101HDFXXX$n',
            rfc: 'PEXJ900101$n',
            nss: '100000000$n',
            estadoCivil: 'soltero',
            fechaIngreso: DateTime(2025, 1, 1),
            aniosExperienciaSeguridad: 3,
          ),
        );
  }

  /// Fabrica el mínimo real (una `Nomina` + su `NominaEmpleado`) para
  /// poder llevar una cuota a `aplicada` sin pasar por todo el motor de
  /// generación de Nómina — el objetivo es la cuota `aplicada`, no
  /// probar Nómina en sí (ya cubierto en sus propias pruebas).
  Future<String> crearRenglonNominaDePrueba(EmpleadoData empleado) async {
    final nomina = await db.into(db.nomina).insertReturning(
          NominaCompanion.insert(
            folio: 'NOM-PRUEBA-${empleado.id.hashCode.toUnsigned(20)}',
            anio: 2026,
            mes: 1,
            tipoPeriodo: 'primera',
            fechaInicioPeriodo: DateTime(2026, 1, 1),
            fechaFinPeriodo: DateTime(2026, 1, 15),
            fechaPagoOrdinaria: DateTime(2026, 1, 20),
            estatus: const Value('cerrada'),
          ),
        );
    final renglon = await db.into(db.nominaEmpleado).insertReturning(
          NominaEmpleadoCompanion.insert(
            nominaId: nomina.id,
            empleadoId: empleado.id,
            numeroEmpleado: empleado.numeroEmpleado,
            nombreCompleto: '${empleado.nombres} ${empleado.apellidoPaterno}',
            fuenteSueldoUtilizada: 'administrativo',
            diasPagables: 15,
            sueldoMensualUtilizado: 900000,
            sueldoQuincenalReferencia: 450000,
            pagoPorDia: 30000,
            importeBase: 450000,
            totalAPagar: 450000,
          ),
        );
    return renglon.id;
  }

  test('elimina físicamente un descuento cancelado sin cuotas aplicadas', () async {
    final empleado = await crearEmpleadoDePrueba(1);
    final resultado = await registrar.ejecutar(
      empleadoId: empleado.id,
      tipo: 'prestamo',
      fechaRegistro: DateTime(2026, 1, 1),
      importeOriginal: 60000,
      numeroCuotas: 2,
      fechaPrimeraCuota: DateTime(2026, 2, 5),
    ) as RegistrarDescuentoProgramadoExitoso;

    final cancelado = await cancelarSaldo.ejecutar(descuentoProgramadoId: resultado.descuento.id, motivo: 'Error de captura');
    expect(cancelado, isA<CancelarSaldoDescuentoProgramadoExitoso>());

    final eliminado = await eliminarFisicamente.ejecutar(descuentoProgramadoId: resultado.descuento.id, motivo: 'Registro de prueba');
    expect(eliminado, isA<EliminarDescuentoProgramadoFisicamenteExitoso>());

    expect(await descuentoRepo.obtenerPorId(resultado.descuento.id), isNull);
    expect(await descuentoRepo.listarCuotas(resultado.descuento.id), isEmpty);
    expect(await descuentoRepo.listarMovimientos(resultado.descuento.id), isEmpty);

    final eventos = await (db.select(db.eliminacionFisicaEvento)
          ..where((t) => t.entidadIdOriginal.equals(resultado.descuento.id)))
        .get();
    expect(eventos, hasLength(1));
    expect(eventos.single.tipoEntidad, 'descuentoProgramado');
    expect(eventos.single.motivo, 'Registro de prueba');
  });

  test('rechaza eliminar un descuento que no está cancelado (activo)', () async {
    final empleado = await crearEmpleadoDePrueba(2);
    final resultado = await registrar.ejecutar(
      empleadoId: empleado.id,
      tipo: 'botas',
      fechaRegistro: DateTime(2026, 1, 1),
      importeOriginal: 30000,
      numeroCuotas: 1,
      fechaPrimeraCuota: DateTime(2026, 2, 5),
    ) as RegistrarDescuentoProgramadoExitoso;

    final eliminado = await eliminarFisicamente.ejecutar(descuentoProgramadoId: resultado.descuento.id, motivo: 'Registro de prueba');
    expect(eliminado, isA<EliminarDescuentoProgramadoFisicamenteNoPermitido>());
    expect(await descuentoRepo.obtenerPorId(resultado.descuento.id), isNotNull);
  });

  test('rechaza eliminar un descuento cancelado si alguna cuota ya se aplicó en una Nómina real', () async {
    final empleado = await crearEmpleadoDePrueba(3);
    final resultado = await registrar.ejecutar(
      empleadoId: empleado.id,
      tipo: 'prestamo',
      fechaRegistro: DateTime(2026, 1, 1),
      importeOriginal: 60000,
      numeroCuotas: 2,
      fechaPrimeraCuota: DateTime(2026, 1, 20),
    ) as RegistrarDescuentoProgramadoExitoso;

    final cuotas = await descuentoRepo.listarCuotas(resultado.descuento.id);
    final primeraCuota = cuotas.first;

    final nominaEmpleadoId = await crearRenglonNominaDePrueba(empleado);
    await descuentoRepo.reservarCuotas(cuotaIds: [primeraCuota.id], nominaEmpleadoId: nominaEmpleadoId);
    await descuentoRepo.aplicarCuotasReservadas(nominaEmpleadoId: nominaEmpleadoId);

    // La segunda cuota sigue `pendiente` — `cancelarSaldo` la cancela sin
    // tocar la primera, ya `aplicada` (mismo comportamiento documentado
    // en `DescuentoProgramadoRepository.cancelarSaldo`).
    final cancelado = await cancelarSaldo.ejecutar(descuentoProgramadoId: resultado.descuento.id, motivo: 'Baja del empleado');
    expect(cancelado, isA<CancelarSaldoDescuentoProgramadoExitoso>());
    final descuentoCancelado = await descuentoRepo.obtenerPorId(resultado.descuento.id);
    expect(descuentoCancelado!.estatus, 'cancelado');

    final resumen = await eliminarFisicamente.obtenerResumen(resultado.descuento.id);
    expect(resumen.bloqueado, isTrue);
    expect(resumen.detalleBloqueo, contains('1 cuota'));

    final eliminado = await eliminarFisicamente.ejecutar(descuentoProgramadoId: resultado.descuento.id, motivo: 'Registro de prueba');
    expect(eliminado, isA<EliminarDescuentoProgramadoFisicamenteTieneDependencias>());
    expect((eliminado as EliminarDescuentoProgramadoFisicamenteTieneDependencias).detalle, contains('1 cuota'));

    // Nada se borró — la cuota `aplicada` (historia real de Nómina)
    // sigue intacta.
    expect(await descuentoRepo.obtenerPorId(resultado.descuento.id), isNotNull);
    final cuotasFinales = await descuentoRepo.listarCuotas(resultado.descuento.id);
    expect(cuotasFinales.where((c) => c.estatus == 'aplicada'), hasLength(1));
  });

  test('rechaza eliminar un descuento que ya no existe', () async {
    final eliminado = await eliminarFisicamente.ejecutar(descuentoProgramadoId: 'no-existe', motivo: 'Registro de prueba');
    expect(eliminado, isA<EliminarDescuentoProgramadoFisicamenteNoExiste>());
  });
}
