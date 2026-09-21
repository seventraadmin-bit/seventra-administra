// Etapa 4 (Nómina — corrección, cancelación y trazabilidad integral).
// `CorregirRenglonNominaUseCase` — corrección de un renglón mientras la
// Nómina ya está cerrada/pagada. Cubre el punto de decisión de la
// Sección 18 ya resuelto por Marlon (bloquear el sobrepago, nunca
// inventar una figura contable nueva) y los dos sentidos del renglón
// en $0 (Sección 10).

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
import 'package:riseg_one/features/nomina/domain/usecases/cerrar_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/corregir_renglon_nomina_usecase.dart';
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
  late CorregirRenglonNominaUseCase corregirRenglon;

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
    corregirRenglon = CorregirRenglonNominaUseCase(nominaRepo, pagoNominaRepo);

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
      sueldoMensualAdministrativo: 10000,
    );
  });

  tearDown(() => db.close());

  Future<({NominaData nomina, NominaEmpleadoData renglon})> nominaCerradaConTotal(int total) async {
    final generado = (await generarNomina.ejecutar(anio: 2026, mes: 1, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
    final renglon = (await nominaRepo.listarEmpleados(generado.nomina.id)).single;
    await nominaRepo.actualizarRenglon(
      nominaEmpleadoId: renglon.id,
      prestamo: 0,
      tiempoExtra: 0,
      bono: (total - renglon.importeBase).clamp(0, 1 << 30),
      bonoModificadoManualmente: true,
      faltas: 0,
      otrosDescuentos: (renglon.importeBase - total).clamp(0, 1 << 30),
      observaciones: null,
      tipoEvento: 'movimientoModificado',
    );
    await cerrarNomina.ejecutar(nominaId: generado.nomina.id);
    final nomina = (await nominaRepo.obtenerPorId(generado.nomina.id))!;
    final renglonFinal = (await nominaRepo.listarEmpleados(nomina.id)).single;
    return (nomina: nomina, renglon: renglonFinal);
  }

  test(
    'Sección 18 (decisión ya resuelta): corregir un total por debajo de lo ya pagado se BLOQUEA, '
    'nunca se inventa un saldo a favor',
    () async {
      final ctx = await nominaCerradaConTotal(1000000);
      await registrarPagoNomina.ejecutar(
        nominaId: ctx.nomina.id,
        fechaPago: DateTime(2026, 1, 20),
        formaPago: 'transferencia',
        cuentaFinancieraId: await _cuentaDePrueba(db),
        aplicaciones: [(nominaEmpleadoId: ctx.renglon.id, monto: 1000000)],
      );

      // Se descubre que debían ser solo $9,500 — pero ya se pagó el
      // total completo de $10,000: la corrección caería por debajo de
      // lo pagado.
      final resultado = await corregirRenglon.ejecutar(
        nominaEmpleadoId: ctx.renglon.id,
        prestamo: ctx.renglon.prestamo,
        tiempoExtra: ctx.renglon.tiempoExtra,
        bono: ctx.renglon.bono - 50000,
        faltas: ctx.renglon.faltas,
        otrosDescuentos: ctx.renglon.otrosDescuentos,
        observaciones: ctx.renglon.observaciones,
        motivo: 'Se descubrió un error después de pagar todo',
      );

      expect(resultado, isA<CorregirRenglonNominaExcedeLoPagado>());
      expect((resultado as CorregirRenglonNominaExcedeLoPagado).totalPagadoHistorico, 1000000);
      final renglonTrasIntento = (await nominaRepo.listarEmpleados(ctx.nomina.id)).single;
      expect(renglonTrasIntento.totalAPagar, 1000000, reason: 'nada cambia cuando la corrección se rechaza');
      expect(renglonTrasIntento.estatusPago, 'pagado');
    },
  );

  test('corregir exactamente al monto ya pagado (ni un centavo menos) SÍ se permite — pendiente final \$0', () async {
    final ctx = await nominaCerradaConTotal(1000000);
    await registrarPagoNomina.ejecutar(
      nominaId: ctx.nomina.id,
      fechaPago: DateTime(2026, 1, 20),
      formaPago: 'transferencia',
      cuentaFinancieraId: await _cuentaDePrueba(db),
      aplicaciones: [(nominaEmpleadoId: ctx.renglon.id, monto: 400000)],
    );

    final resultado = await corregirRenglon.ejecutar(
      nominaEmpleadoId: ctx.renglon.id,
      prestamo: ctx.renglon.prestamo,
      tiempoExtra: ctx.renglon.tiempoExtra,
      bono: ctx.renglon.bono - 600000,
      faltas: ctx.renglon.faltas,
      otrosDescuentos: ctx.renglon.otrosDescuentos,
      observaciones: ctx.renglon.observaciones,
      motivo: 'El total real era exactamente lo ya pagado',
    );

    expect(resultado, isA<CorregirRenglonNominaExitoso>());
    expect(await pagoNominaRepo.saldoPendientePago(ctx.renglon.id), 0);
  });

  test('Sección 6 (arquitectura ya lo soporta): corregir HACIA ARRIBA una Nómina ya pagada la reabre a cerrada, con saldo pendiente real', () async {
    final ctx = await nominaCerradaConTotal(1000000);
    await registrarPagoNomina.ejecutar(
      nominaId: ctx.nomina.id,
      fechaPago: DateTime(2026, 1, 20),
      formaPago: 'transferencia',
      cuentaFinancieraId: await _cuentaDePrueba(db),
      aplicaciones: [(nominaEmpleadoId: ctx.renglon.id, monto: 1000000)],
    );
    var nomina = (await nominaRepo.obtenerPorId(ctx.nomina.id))!;
    expect(nomina.estatus, 'pagada');

    final resultado = await corregirRenglon.ejecutar(
      nominaEmpleadoId: ctx.renglon.id,
      prestamo: ctx.renglon.prestamo,
      tiempoExtra: ctx.renglon.tiempoExtra,
      bono: ctx.renglon.bono + 50000,
      faltas: ctx.renglon.faltas,
      otrosDescuentos: ctx.renglon.otrosDescuentos,
      observaciones: ctx.renglon.observaciones,
      motivo: 'Debían ser \$10,500, no \$10,000',
    );

    expect(resultado, isA<CorregirRenglonNominaExitoso>());
    nomina = (await nominaRepo.obtenerPorId(ctx.nomina.id))!;
    expect(nomina.estatus, 'cerrada', reason: 'se reabre — ya no todos los renglones están pagado con el nuevo total');
    expect(await pagoNominaRepo.saldoPendientePago(ctx.renglon.id), 50000, reason: 'el excedente de \$500 queda como saldo pendiente real, un nuevo pago lo cubre');
  });

  test('Sección 10: corrección mueve un renglón de monto positivo a \$0 — pasa a pagado sin Pago/Egreso ficticio', () async {
    final ctx = await nominaCerradaConTotal(1000000);

    final resultado = await corregirRenglon.ejecutar(
      nominaEmpleadoId: ctx.renglon.id,
      prestamo: ctx.renglon.prestamo,
      tiempoExtra: ctx.renglon.tiempoExtra,
      bono: ctx.renglon.bono,
      faltas: ctx.renglon.faltas,
      otrosDescuentos: ctx.renglon.otrosDescuentos + ctx.renglon.totalAPagar,
      observaciones: ctx.renglon.observaciones,
      motivo: 'Se debe un adeudo igual al total — queda en ceros',
    );

    expect(resultado, isA<CorregirRenglonNominaExitoso>());
    final renglonTras = (await nominaRepo.listarEmpleados(ctx.nomina.id)).single;
    expect(renglonTras.totalAPagar, 0);
    expect(renglonTras.estatusPago, 'pagado');
    final pagos = await pagoNominaRepo.listarPorNomina(ctx.nomina.id);
    expect(pagos, isEmpty);
    final nomina = (await nominaRepo.obtenerPorId(ctx.nomina.id))!;
    expect(nomina.estatus, 'pagada', reason: 'único renglón, ahora en \$0 sin deuda — la Nómina completa pasa a pagada');
  });

  test('Sección 10: corrección mueve un renglón de \$0 de vuelta a positivo — recupera pendiente real', () async {
    final ctx = await nominaCerradaConTotal(0);
    expect(ctx.renglon.estatusPago, 'pagado', reason: 'saneamiento de \$0 al cerrar');

    final resultado = await corregirRenglon.ejecutar(
      nominaEmpleadoId: ctx.renglon.id,
      prestamo: ctx.renglon.prestamo,
      tiempoExtra: ctx.renglon.tiempoExtra,
      bono: ctx.renglon.bono + 500000,
      faltas: ctx.renglon.faltas,
      otrosDescuentos: ctx.renglon.otrosDescuentos,
      observaciones: ctx.renglon.observaciones,
      motivo: 'Se había omitido un bono real de \$5,000',
    );

    expect(resultado, isA<CorregirRenglonNominaExitoso>());
    final renglonTras = (await nominaRepo.listarEmpleados(ctx.nomina.id)).single;
    expect(renglonTras.totalAPagar, 500000);
    expect(renglonTras.estatusPago, 'pendiente');
    final nomina = (await nominaRepo.obtenerPorId(ctx.nomina.id))!;
    expect(nomina.estatus, 'cerrada', reason: 'ya no está pagada — vuelve a tener un saldo real por pagar');
  });

  test('motivo vacío se rechaza — validación de dominio, no solo de UI', () async {
    final ctx = await nominaCerradaConTotal(1000000);
    final resultado = await corregirRenglon.ejecutar(nominaEmpleadoId: ctx.renglon.id, bono: ctx.renglon.bono + 1000, motivo: '   ');
    expect(resultado, isA<CorregirRenglonNominaMotivoRequerido>());
  });

  test('corregir un renglón mientras la Nómina sigue en Borrador se rechaza — usa ActualizarRenglonNominaUseCase', () async {
    final generado = (await generarNomina.ejecutar(anio: 2026, mes: 1, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
    final renglon = (await nominaRepo.listarEmpleados(generado.nomina.id)).single;

    final resultado = await corregirRenglon.ejecutar(nominaEmpleadoId: renglon.id, bono: renglon.bono + 1000, motivo: 'Intento en Borrador');
    expect(resultado, isA<CorregirRenglonNominaNominaBorrador>());
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
