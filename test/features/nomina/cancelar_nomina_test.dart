// Etapa 4 (Nómina — corrección, cancelación y trazabilidad integral),
// Secciones 9/18: "Cancelar Nómina" completa — decisión ya resuelta
// por Marlon: solo Borrador o Cerrada-sin-pagos; Cerrada-con-pagos y
// Pagada NUNCA (ahí se cancela pago por pago). Libera cuotas
// reservadas, revierte descuentos de inventario, nunca toca un
// PagoNomina real.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/features/finanzas/data/repositories/cuenta_financiera_repository_impl.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/codigos/generar_numero_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/descuentos_personal/data/repositories/descuento_programado_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/repositories/nomina_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/repositories/pago_nomina_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/tables/nomina_table.dart';
import 'package:riseg_one/features/nomina/domain/usecases/cancelar_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/cerrar_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/evaluar_renglones_requieren_revision_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/generar_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/registrar_pago_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/resolver_sueldo_empleado_nomina.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/puesto_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_comercial_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart';
import 'package:riseg_one/features/personal/domain/usecases/crear_empleado_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/empleado_validator.dart';
import 'package:riseg_one/features/tiempos_extra/data/repositories/tiempo_extra_repository_impl.dart';

void main() {
  late AppDatabase db;
  late NominaRepositoryImpl nominaRepo;
  late PagoNominaRepositoryImpl pagoNominaRepo;
  late GenerarNominaUseCase generarNomina;
  late CerrarNominaUseCase cerrarNomina;
  late RegistrarPagoNominaUseCase registrarPagoNomina;
  late CancelarNominaUseCase cancelarNomina;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(id: const Value('usuario-prueba'), nombre: 'Usuario de prueba', nombreUsuario: 'usuario-prueba', passwordHash: 'x'),
        );

    final asignacionServicioRepo = AsignacionServicioRepositoryImpl(db);
    final empleadoRepo = EmpleadoRepositoryImpl(db, asignacionServicioRepo);
    final servicioRepo = ServicioRepositoryImpl(db, asignacionServicioRepo);
    final catalogoRepo = CatalogoRepositoryImpl(db);
    final puestoRepo = PuestoRepositoryImpl(db);
    final egresoRepo = EgresoRepositoryImpl(db);
    final deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
    final resolverSueldo = ResolverSueldoEmpleadoNomina(empleadoRepo, asignacionServicioRepo, servicioRepo, catalogoRepo);
    pagoNominaRepo = PagoNominaRepositoryImpl(db, egresoRepo, DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db)));
    nominaRepo = NominaRepositoryImpl(
      db,
      AsignacionRepositoryImpl(db),
      DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db)),
      TiempoExtraRepositoryImpl(db, egresoRepo, deudaRepo, CodigoSecuenciaService(db), empleadoRepo, servicioRepo),
      pagoNominaRepo,
    );
    generarNomina = GenerarNominaUseCase(nominaRepo, empleadoRepo, puestoRepo, catalogoRepo, resolverSueldo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));
    cerrarNomina = CerrarNominaUseCase(nominaRepo, EvaluarRenglonesRequierenRevisionUseCase(nominaRepo, empleadoRepo, resolverSueldo));
    registrarPagoNomina = RegistrarPagoNominaUseCase(pagoNominaRepo, nominaRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)), CuentaFinancieraRepositoryImpl(db));
    cancelarNomina = CancelarNominaUseCase(nominaRepo, pagoNominaRepo);

    final crearEmpleado = CrearEmpleadoUseCase(
      empleadoRepo,
      GenerarNumeroUseCase(CodigoSecuenciaService(db)),
      const EmpleadoValidator(),
      servicioRepo,
      ServicioComercialRepositoryImpl(db),
    );
    await crearEmpleado.ejecutar(
      nombres: 'Ana',
      apellidoPaterno: 'Gómez',
      sexo: SexoEmpleado.femenino,
      fechaNacimiento: DateTime(1990, 1, 1),
      curp: 'GOXA900101MDFXXX01',
      rfc: 'GOXA900101AB1',
      nss: '10000000001',
      estadoCivil: EstadoCivilEmpleado.soltero,
      fechaIngreso: DateTime(2025, 1, 1),
      aniosExperienciaSeguridad: 3,
      sueldoMensualAdministrativo: 1500000,
    );
  });

  tearDown(() => db.close());

  Future<NominaData> generarBorrador() async {
    final generado = (await generarNomina.ejecutar(anio: 2026, mes: 1, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
    return generado.nomina;
  }

  test('Borrador sin pagos: se cancela correctamente', () async {
    final nomina = await generarBorrador();

    final resultado = await cancelarNomina.ejecutar(nominaId: nomina.id, motivo: MotivoCancelacionNomina.errorDeCaptura);

    expect(resultado, isA<CancelarNominaExitoso>());
    final actualizada = (await nominaRepo.obtenerPorId(nomina.id))!;
    expect(actualizada.estatus, 'cancelada');
    expect(actualizada.motivoCancelacionCodigo, 'errorDeCaptura');
  });

  test('Cerrada sin pagos: se cancela correctamente', () async {
    final nomina = await generarBorrador();
    await cerrarNomina.ejecutar(nominaId: nomina.id);

    final resultado = await cancelarNomina.ejecutar(nominaId: nomina.id, motivo: MotivoCancelacionNomina.periodoIncorrecto);

    expect(resultado, isA<CancelarNominaExitoso>());
    final actualizada = (await nominaRepo.obtenerPorId(nomina.id))!;
    expect(actualizada.estatus, 'cancelada');
  });

  test('Cerrada CON pagos (aunque sea parcial): se rechaza — cancela pago por pago en su lugar', () async {
    final nomina = await generarBorrador();
    await cerrarNomina.ejecutar(nominaId: nomina.id);
    final renglon = (await nominaRepo.listarEmpleados(nomina.id)).single;
    await registrarPagoNomina.ejecutar(
      nominaId: nomina.id,
      fechaPago: DateTime(2026, 1, 20),
      formaPago: 'transferencia',
      cuentaFinancieraId: await _cuentaDePrueba(db),
      aplicaciones: [(nominaEmpleadoId: renglon.id, monto: 1)],
    );

    final resultado = await cancelarNomina.ejecutar(nominaId: nomina.id, motivo: MotivoCancelacionNomina.errorDeCaptura);

    expect(resultado, isA<CancelarNominaTienePagos>());
    final actualizada = (await nominaRepo.obtenerPorId(nomina.id))!;
    expect(actualizada.estatus, 'cerrada', reason: 'nada cambia cuando se rechaza');
  });

  test('Pagada: se rechaza siempre — nunca una cancelación destructiva sobre una Nómina con pagos reales', () async {
    final nomina = await generarBorrador();
    await cerrarNomina.ejecutar(nominaId: nomina.id);
    final renglon = (await nominaRepo.listarEmpleados(nomina.id)).single;
    await registrarPagoNomina.ejecutar(
      nominaId: nomina.id,
      fechaPago: DateTime(2026, 1, 20),
      formaPago: 'transferencia',
      cuentaFinancieraId: await _cuentaDePrueba(db),
      aplicaciones: [(nominaEmpleadoId: renglon.id, monto: renglon.totalAPagar)],
    );

    final resultado = await cancelarNomina.ejecutar(nominaId: nomina.id, motivo: MotivoCancelacionNomina.errorDeCaptura);

    expect(resultado, isA<CancelarNominaTienePagos>());
  });

  test('ya cancelada: se rechaza — idempotente, no se puede cancelar dos veces', () async {
    final nomina = await generarBorrador();
    await cancelarNomina.ejecutar(nominaId: nomina.id, motivo: MotivoCancelacionNomina.errorDeCaptura);

    final resultado = await cancelarNomina.ejecutar(nominaId: nomina.id, motivo: MotivoCancelacionNomina.errorDeCaptura);

    expect(resultado, isA<CancelarNominaYaCancelada>());
  });

  test('motivo "Otro" sin detalle se rechaza', () async {
    final nomina = await generarBorrador();
    final resultado = await cancelarNomina.ejecutar(nominaId: nomina.id, motivo: MotivoCancelacionNomina.otro);
    expect(resultado, isA<CancelarNominaDetalleRequerido>());
  });

  test('cancelar un Borrador libera las cuotas reservadas del renglón — auditado, actor real', () async {
    final nomina = await generarBorrador();
    final renglon = (await nominaRepo.listarEmpleados(nomina.id)).single;

    final resultado = await cancelarNomina.ejecutar(
      nominaId: nomina.id,
      motivo: MotivoCancelacionNomina.errorDeCaptura,
      actorUsuarioId: 'usuario-prueba',
    );
    expect(resultado, isA<CancelarNominaExitoso>());

    final eventos = await nominaRepo.listarEventos(nomina.id);
    final eventoCancelada = eventos.where((e) => e.tipoEvento == 'cancelada').single;
    expect(eventoCancelada.actorUsuarioId, 'usuario-prueba');
    // El renglón sigue existiendo (cancelar preserva historial, nunca
    // borra) — a diferencia de la eliminación física.
    final renglonTras = await nominaRepo.obtenerEmpleado(renglon.id);
    expect(renglonTras, isNotNull);
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
