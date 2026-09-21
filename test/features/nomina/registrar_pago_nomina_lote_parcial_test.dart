// Etapa 15 — rediseño de "Registrar pago de nómina" como tabla
// interactiva de dispersión. Cubre el escenario central del pedido:
// pagar un SUBCONJUNTO de empleados de una Nómina (ej. 3 de 5 hoy, el
// resto después) — confirma que las cuotas de préstamos/botas SOLO se
// aplican a los empleados efectivamente cubiertos por ese
// `PagoNomina`, que la Nómina nunca pasa a `pagada` hasta que TODOS
// los renglones queden `pagado`, y que un renglón ya pagado no puede
// volver a recibir una aplicación (nunca doble pago).

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/features/finanzas/data/repositories/cuenta_financiera_repository_impl.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/descuentos_personal/data/repositories/descuento_programado_repository_impl.dart';
import 'package:riseg_one/features/descuentos_personal/domain/repositories/descuento_programado_repository.dart';
import 'package:riseg_one/features/descuentos_personal/domain/usecases/registrar_descuento_programado_usecase.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/egreso_repository.dart';
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/repositories/nomina_repository_impl.dart';
import 'package:riseg_one/features/tiempos_extra/data/repositories/tiempo_extra_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/repositories/pago_nomina_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/tables/nomina_table.dart';
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

void main() {
  late AppDatabase db;
  late EmpleadoRepositoryImpl empleadoRepo;
  late NominaRepositoryImpl nominaRepo;
  late GenerarNominaUseCase generarNomina;
  late CerrarNominaUseCase cerrarNomina;
  late PagoNominaRepositoryImpl pagoNominaRepo;
  late RegistrarPagoNominaUseCase registrarPagoNomina;
  late DescuentoProgramadoRepository descuentoRepo;
  late RegistrarDescuentoProgramadoUseCase registrarDescuento;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final asignacionServicioRepo = AsignacionServicioRepositoryImpl(db);
    empleadoRepo = EmpleadoRepositoryImpl(db, asignacionServicioRepo);
    final servicioRepo = ServicioRepositoryImpl(db, asignacionServicioRepo);
    final EgresoRepository egresoRepo = EgresoRepositoryImpl(db);
    final catalogoRepo = CatalogoRepositoryImpl(db);
    final puestoRepo = PuestoRepositoryImpl(db);
    final codigoSecuencia = CodigoSecuenciaService(db);
    final generarCodigo = GenerarCodigoUseCase(codigoSecuencia);

    descuentoRepo = DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db));
    nominaRepo = NominaRepositoryImpl(db, AsignacionRepositoryImpl(db), descuentoRepo, TiempoExtraRepositoryImpl(db, EgresoRepositoryImpl(db), DeudaRepositoryImpl(db, EgresoRepositoryImpl(db)), CodigoSecuenciaService(db), EmpleadoRepositoryImpl(db, AsignacionServicioRepositoryImpl(db)), ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db))), PagoNominaRepositoryImpl(db, EgresoRepositoryImpl(db), DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db))));
    final resolverSueldo = ResolverSueldoEmpleadoNomina(empleadoRepo, asignacionServicioRepo, servicioRepo, catalogoRepo);
    generarNomina = GenerarNominaUseCase(nominaRepo, empleadoRepo, puestoRepo, catalogoRepo, resolverSueldo, generarCodigo);
    final evaluarRenglonesRequierenRevision = EvaluarRenglonesRequierenRevisionUseCase(nominaRepo, empleadoRepo, resolverSueldo);
    cerrarNomina = CerrarNominaUseCase(nominaRepo, evaluarRenglonesRequierenRevision);

    pagoNominaRepo = PagoNominaRepositoryImpl(db, egresoRepo, descuentoRepo);
    registrarPagoNomina = RegistrarPagoNominaUseCase(pagoNominaRepo, nominaRepo, generarCodigo, CuentaFinancieraRepositoryImpl(db));
    registrarDescuento = RegistrarDescuentoProgramadoUseCase(descuentoRepo, empleadoRepo, generarCodigo);
  });

  tearDown(() => db.close());

  var empleadoContador = 0;
  Future<EmpleadoData> crearEmpleadoDePrueba({int sueldoMensualAdministrativo = 3000000}) async {
    empleadoContador++;
    final n = empleadoContador.toString().padLeft(2, '0');
    return db.into(db.empleado).insertReturning(
          EmpleadoCompanion.insert(
            numeroEmpleado: empleadoContador,
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
            sueldoMensualAdministrativo: Value(sueldoMensualAdministrativo),
          ),
        );
  }

  test('pagar 3 de 5 empleados aplica cuotas de préstamo SOLO a esos 3 — los otros 2 quedan `reservada`', () async {
    final empleados = [for (var i = 0; i < 5; i++) await crearEmpleadoDePrueba()];
    for (final e in empleados) {
      await registrarDescuento.ejecutar(
        empleadoId: e.id,
        tipo: 'prestamo',
        fechaRegistro: DateTime(2026, 8, 20),
        importeOriginal: 100000,
        numeroCuotas: 1,
        fechaPrimeraCuota: DateTime(2026, 8, 20),
      );
    }

    final generado = (await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
    await cerrarNomina.ejecutar(nominaId: generado.nomina.id);
    final renglones = await nominaRepo.listarEmpleados(generado.nomina.id);
    expect(renglones, hasLength(5));

    final aPagar = renglones.take(3).toList();
    final resultado = await registrarPagoNomina.ejecutar(
      nominaId: generado.nomina.id,
      fechaPago: DateTime(2026, 8, 20),
      formaPago: 'transferencia',
      cuentaFinancieraId: await _cuentaDePrueba(db),
      aplicaciones: [for (final r in aPagar) (nominaEmpleadoId: r.id, monto: r.totalAPagar)],
    );
    expect(resultado, isA<RegistrarPagoNominaExitoso>());

    for (final r in aPagar) {
      final cuota = (await descuentoRepo.listarCuotasPorRenglon(r.id)).single;
      expect(cuota.estatus, 'aplicada', reason: 'este empleado sí fue cubierto por el PagoNomina');
    }

    final noPagados = renglones.skip(3).toList();
    for (final r in noPagados) {
      final cuota = (await descuentoRepo.listarCuotasPorRenglon(r.id)).single;
      expect(cuota.estatus, 'reservada', reason: 'este empleado NO fue cubierto — su cuota nunca se toca');
    }

    final nominaTrasPrimerLote = (await nominaRepo.obtenerPorId(generado.nomina.id))!;
    expect(nominaTrasPrimerLote.estatus, 'cerrada', reason: 'nunca pasa a pagada por cubrir solo un subconjunto');
  });

  test('segundo pago que cubre a los restantes completa la Nómina y aplica las cuotas que faltaban', () async {
    final empleados = [for (var i = 0; i < 5; i++) await crearEmpleadoDePrueba()];
    for (final e in empleados) {
      await registrarDescuento.ejecutar(
        empleadoId: e.id,
        tipo: 'prestamo',
        fechaRegistro: DateTime(2026, 8, 20),
        importeOriginal: 100000,
        numeroCuotas: 1,
        fechaPrimeraCuota: DateTime(2026, 8, 20),
      );
    }

    final generado = (await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
    await cerrarNomina.ejecutar(nominaId: generado.nomina.id);
    final renglones = await nominaRepo.listarEmpleados(generado.nomina.id);

    await registrarPagoNomina.ejecutar(
      nominaId: generado.nomina.id,
      fechaPago: DateTime(2026, 8, 20),
      formaPago: 'transferencia',
      cuentaFinancieraId: await _cuentaDePrueba(db),
      aplicaciones: [for (final r in renglones.take(3)) (nominaEmpleadoId: r.id, monto: r.totalAPagar)],
    );

    final resultadoSegundo = await registrarPagoNomina.ejecutar(
      nominaId: generado.nomina.id,
      fechaPago: DateTime(2026, 8, 21),
      formaPago: 'transferencia',
      cuentaFinancieraId: await _cuentaDePrueba(db),
      aplicaciones: [for (final r in renglones.skip(3)) (nominaEmpleadoId: r.id, monto: r.totalAPagar)],
    );
    expect(resultadoSegundo, isA<RegistrarPagoNominaExitoso>());

    for (final r in renglones) {
      final cuota = (await descuentoRepo.listarCuotasPorRenglon(r.id)).single;
      expect(cuota.estatus, 'aplicada');
    }

    final nominaFinal = (await nominaRepo.obtenerPorId(generado.nomina.id))!;
    expect(nominaFinal.estatus, 'pagada', reason: 'todos los renglones ya están pagado');
  });

  test('un renglón ya pagado NUNCA puede recibir una segunda aplicación — no hay doble pago', () async {
    // Segundo empleado sin pagar a propósito, para que la Nómina se
    // quede `cerrada` (no `pagada`) y el segundo intento sobre el
    // primer renglón golpee de verdad la compuerta de sobrepago, no la
    // de "Nómina no cerrada".
    await crearEmpleadoDePrueba();
    await crearEmpleadoDePrueba();
    final generado = (await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
    await cerrarNomina.ejecutar(nominaId: generado.nomina.id);
    final renglones = await nominaRepo.listarEmpleados(generado.nomina.id);
    final renglonPagado = renglones.first;

    await registrarPagoNomina.ejecutar(
      nominaId: generado.nomina.id,
      fechaPago: DateTime(2026, 8, 20),
      formaPago: 'transferencia',
      cuentaFinancieraId: await _cuentaDePrueba(db),
      aplicaciones: [(nominaEmpleadoId: renglonPagado.id, monto: renglonPagado.totalAPagar)],
    );

    final segundoIntento = await registrarPagoNomina.ejecutar(
      nominaId: generado.nomina.id,
      fechaPago: DateTime(2026, 8, 21),
      formaPago: 'transferencia',
      cuentaFinancieraId: await _cuentaDePrueba(db),
      aplicaciones: [(nominaEmpleadoId: renglonPagado.id, monto: 100)],
    );

    expect(segundoIntento, isA<RegistrarPagoNominaSobrepago>(), reason: 'la Nómina sigue cerrada (el otro renglón no se pagó), así que la compuerta real que debe rechazar es sobrepago');
  });

  test('un pago parcial dentro de un lote mixto (algunos completos, uno parcial) suma exactamente lo aplicado', () async {
    for (var i = 0; i < 3; i++) {
      await crearEmpleadoDePrueba();
    }
    final generado = (await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
    await cerrarNomina.ejecutar(nominaId: generado.nomina.id);
    final renglones = await nominaRepo.listarEmpleados(generado.nomina.id);

    final montoParcial = renglones[2].totalAPagar ~/ 2;
    final resultado = await registrarPagoNomina.ejecutar(
      nominaId: generado.nomina.id,
      fechaPago: DateTime(2026, 8, 20),
      formaPago: 'transferencia',
      cuentaFinancieraId: await _cuentaDePrueba(db),
      aplicaciones: [
        (nominaEmpleadoId: renglones[0].id, monto: renglones[0].totalAPagar),
        (nominaEmpleadoId: renglones[1].id, monto: renglones[1].totalAPagar),
        (nominaEmpleadoId: renglones[2].id, monto: montoParcial),
      ],
    );
    final pago = (resultado as RegistrarPagoNominaExitoso).pagoNomina;
    expect(pago.montoTotal, renglones[0].totalAPagar + renglones[1].totalAPagar + montoParcial);

    final saldoTercero = await pagoNominaRepo.saldoPendientePago(renglones[2].id);
    expect(saldoTercero, renglones[2].totalAPagar - montoParcial);

    final renglonTercero = await nominaRepo.obtenerEmpleado(renglones[2].id);
    expect(renglonTercero!.estatusPago, 'parcial');
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
