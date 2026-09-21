// Bug real reportado por Marlon (2026-09-05), continuación del fix de
// `sincronizarEstatusPago`: ese fix solo corrige escrituras FUTURAS de
// `totalAPagar` (`generar`/`guardarRenglon`/`actualizarRenglon`) — una
// Nómina ya `cerrada`/`pagada` ANTES de que existiera ese método
// (NOM-000012, el caso real reportado: $74,383.31 pagados en su
// totalidad, pero un par de renglones en $0.00 seguían `pendiente` y
// por eso la Nómina completa seguía atorada en `cerrada`, y por eso
// el Dashboard seguía mostrándola como "Próxima nómina") nunca vuelve
// a pasar por esos tres métodos — nadie edita/regenera una Nómina ya
// cerrada. `ReconciliarEstatusPagoNominaUseCase` repara esos datos
// HISTÓRICOS, reutilizando la misma fórmula de dominio
// (`PagoNominaRepository.sincronizarEstatusPago`) en vez de
// reimplementarla en SQL.
//
// Estas pruebas simulan datos "de antes del fix" escribiendo
// directamente sobre las tablas (Companion.write, nunca SQL crudo) —
// exactamente lo que una instalación real tendría si esos renglones
// se hubieran generado con el código anterior a `sincronizarEstatusPago`.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/features/finanzas/data/repositories/cuenta_financiera_repository_impl.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/dashboard/domain/usecases/obtener_proxima_nomina_usecase.dart';
import 'package:riseg_one/features/descuentos_personal/data/repositories/descuento_programado_repository_impl.dart';
import 'package:riseg_one/features/descuentos_personal/domain/repositories/descuento_programado_repository.dart';
import 'package:riseg_one/features/descuentos_personal/domain/usecases/registrar_descuento_programado_usecase.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/egreso_repository.dart';
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/repositories/nomina_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/repositories/pago_nomina_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/tables/nomina_table.dart';
import 'package:riseg_one/features/nomina/domain/usecases/actualizar_renglon_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/cerrar_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/evaluar_renglones_requieren_revision_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/generar_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/reconciliar_estatus_pago_nomina_usecase.dart';
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
  late EmpleadoRepositoryImpl empleadoRepo;
  late NominaRepositoryImpl nominaRepo;
  late GenerarNominaUseCase generarNomina;
  late CerrarNominaUseCase cerrarNomina;
  late ActualizarRenglonNominaUseCase actualizarRenglon;
  late PagoNominaRepositoryImpl pagoNominaRepo;
  late RegistrarPagoNominaUseCase registrarPagoNomina;
  late DescuentoProgramadoRepository descuentoRepo;
  late RegistrarDescuentoProgramadoUseCase registrarDescuento;
  late ReconciliarEstatusPagoNominaUseCase reconciliar;
  late ObtenerProximaNominaUseCase obtenerProximaNomina;

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
    pagoNominaRepo = PagoNominaRepositoryImpl(db, egresoRepo, descuentoRepo);
    nominaRepo = NominaRepositoryImpl(
      db,
      AsignacionRepositoryImpl(db),
      descuentoRepo,
      TiempoExtraRepositoryImpl(
        db,
        EgresoRepositoryImpl(db),
        DeudaRepositoryImpl(db, EgresoRepositoryImpl(db)),
        CodigoSecuenciaService(db),
        EmpleadoRepositoryImpl(db, AsignacionServicioRepositoryImpl(db)),
        ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db)),
      ),
      pagoNominaRepo,
    );
    final resolverSueldo = ResolverSueldoEmpleadoNomina(empleadoRepo, asignacionServicioRepo, servicioRepo, catalogoRepo);
    generarNomina = GenerarNominaUseCase(nominaRepo, empleadoRepo, puestoRepo, catalogoRepo, resolverSueldo, generarCodigo);
    final evaluarRenglonesRequierenRevision = EvaluarRenglonesRequierenRevisionUseCase(nominaRepo, empleadoRepo, resolverSueldo);
    cerrarNomina = CerrarNominaUseCase(nominaRepo, evaluarRenglonesRequierenRevision);
    actualizarRenglon = ActualizarRenglonNominaUseCase(nominaRepo);
    registrarPagoNomina = RegistrarPagoNominaUseCase(pagoNominaRepo, nominaRepo, generarCodigo, CuentaFinancieraRepositoryImpl(db));
    registrarDescuento = RegistrarDescuentoProgramadoUseCase(descuentoRepo, empleadoRepo, generarCodigo);
    reconciliar = ReconciliarEstatusPagoNominaUseCase(nominaRepo, pagoNominaRepo);
    obtenerProximaNomina = ObtenerProximaNominaUseCase(nominaRepo);
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

  // Simula datos "de antes del fix": fuerza la columna persistida de
  // vuelta a como habría quedado sin `sincronizarEstatusPago` — nunca
  // se usa SQL crudo, solo el mismo `Companion.write` tipado que usa
  // el propio código de producción.
  Future<void> forzarComoHistoricoSinReconciliar(String nominaEmpleadoId) {
    return (db.update(db.nominaEmpleado)..where((t) => t.id.equals(nominaEmpleadoId))).write(
      const NominaEmpleadoCompanion(estatusPago: Value('pendiente')),
    );
  }

  test(
    'Nómina histórica con un renglón en \$0.00 marcado `pendiente` (datos de antes del fix) → '
    'reconciliar → `pagado`',
    () async {
      await crearEmpleadoDePrueba(sueldoMensualAdministrativo: 3000000);
      final generado = (await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
      final renglon = (await nominaRepo.listarEmpleados(generado.nomina.id)).single;
      await actualizarRenglon.ejecutar(nominaEmpleadoId: renglon.id, otrosDescuentos: renglon.totalAPagar);
      await cerrarNomina.ejecutar(nominaId: generado.nomina.id);

      final renglonEnCero = (await nominaRepo.obtenerEmpleado(renglon.id))!;
      expect(renglonEnCero.totalAPagar, 0);
      await forzarComoHistoricoSinReconciliar(renglon.id);
      expect((await nominaRepo.obtenerEmpleado(renglon.id))!.estatusPago, 'pendiente', reason: 'estado histórico simulado');

      final resultado = await reconciliar.ejecutar();

      expect(resultado.renglonesCorregidos, 1);
      expect(resultado.nominasActualizadas, 1);
      expect((await nominaRepo.obtenerEmpleado(renglon.id))!.estatusPago, 'pagado');
      expect((await nominaRepo.obtenerPorId(generado.nomina.id))!.estatus, 'pagada');
    },
  );

  test(
    '18 renglones ya pagados de verdad + 1 renglón histórico en \$0.00 pendiente → reconciliar → Nómina `pagada`',
    () async {
      final aplicaciones = <({String nominaEmpleadoId, int monto})>[];
      for (var i = 0; i < 18; i++) {
        await crearEmpleadoDePrueba(sueldoMensualAdministrativo: 3000000);
      }
      await crearEmpleadoDePrueba(sueldoMensualAdministrativo: 3000000);

      final generado = (await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
      final renglones = await nominaRepo.listarEmpleados(generado.nomina.id);
      expect(renglones, hasLength(19));

      final renglonCero = renglones.first;
      await actualizarRenglon.ejecutar(nominaEmpleadoId: renglonCero.id, otrosDescuentos: renglonCero.totalAPagar);
      for (final r in renglones.skip(1)) {
        aplicaciones.add((nominaEmpleadoId: r.id, monto: r.totalAPagar));
      }

      await cerrarNomina.ejecutar(nominaId: generado.nomina.id);
      // El histórico se simula DESPUÉS de cerrar (nunca se puede tocar
      // un renglón vía `actualizarRenglon` con la Nómina ya cerrada).
      await forzarComoHistoricoSinReconciliar(renglonCero.id);

      await registrarPagoNomina.ejecutar(
        nominaId: generado.nomina.id,
        fechaPago: DateTime(2026, 8, 20),
        formaPago: 'transferencia',
        cuentaFinancieraId: await _cuentaDePrueba(db),
        aplicaciones: aplicaciones,
      );

      expect(
        (await nominaRepo.obtenerPorId(generado.nomina.id))!.estatus,
        'cerrada',
        reason: 'el renglón histórico en \$0.00 todavía figura pendiente — la Nómina no puede estar pagada todavía',
      );

      final resultado = await reconciliar.ejecutar();

      expect(resultado.renglonesCorregidos, 1);
      expect(resultado.nominasActualizadas, 1);
      expect((await nominaRepo.obtenerEmpleado(renglonCero.id))!.estatusPago, 'pagado');
      expect((await nominaRepo.obtenerPorId(generado.nomina.id))!.estatus, 'pagada');
    },
  );

  test('ejecutar la reconciliación dos veces produce el mismo resultado — cero cambios/pagos/movimientos duplicados', () async {
    await crearEmpleadoDePrueba(sueldoMensualAdministrativo: 3000000);
    final generado = (await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
    final renglon = (await nominaRepo.listarEmpleados(generado.nomina.id)).single;
    await actualizarRenglon.ejecutar(nominaEmpleadoId: renglon.id, otrosDescuentos: renglon.totalAPagar);
    await cerrarNomina.ejecutar(nominaId: generado.nomina.id);
    await forzarComoHistoricoSinReconciliar(renglon.id);

    final primera = await reconciliar.ejecutar();
    expect(primera.renglonesCorregidos, 1);
    expect(primera.nominasActualizadas, 1);

    final segunda = await reconciliar.ejecutar();
    expect(segunda.renglonesCorregidos, 0, reason: 'ya no hay nada que corregir — la segunda corrida debe ser un no-op total');
    expect(segunda.nominasActualizadas, 0);

    // Ningún PagoNomina/AplicacionPagoNomina fantasma se creó — el
    // renglón sigue en $0.00 sin ningún pago real asociado.
    expect(await pagoNominaRepo.listarAplicacionesPorRenglon(renglon.id), isEmpty);
    expect(await pagoNominaRepo.listarPorNomina(generado.nomina.id), isEmpty);
  });

  test(
    'renglón en \$0.00 por una cuota programada reservada (histórico) → reconciliar → la cuota pasa a `aplicada` '
    'EXACTAMENTE una vez, incluso ejecutando la reconciliación dos veces',
    () async {
      final empleado = await crearEmpleadoDePrueba(sueldoMensualAdministrativo: 3000000);
      final registrado = await registrarDescuento.ejecutar(
        empleadoId: empleado.id,
        tipo: 'prestamo',
        fechaRegistro: DateTime(2026, 8, 10),
        importeOriginal: 1500000,
        numeroCuotas: 1,
        fechaPrimeraCuota: DateTime(2026, 8, 10),
      );
      final descuentoId = (registrado as RegistrarDescuentoProgramadoExitoso).descuento.id;

      final generado = (await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
      final renglon = (await nominaRepo.listarEmpleados(generado.nomina.id)).single;
      expect(renglon.totalAPagar, 0);

      // El generar() actual (ya con el fix de la sesión anterior) ya
      // deja esto correcto de inmediato — se revierte aquí a mano para
      // simular fielmente cómo habría quedado la BD con el código
      // ANTERIOR a `sincronizarEstatusPago` (cuota reservada, nunca
      // liberada; renglón `pendiente`, nunca `pagado`).
      await forzarComoHistoricoSinReconciliar(renglon.id);
      final cuotaId = (await descuentoRepo.listarCuotas(descuentoId)).single.id;
      await (db.update(db.descuentoProgramadoCuota)..where((t) => t.id.equals(cuotaId))).write(
        const DescuentoProgramadoCuotaCompanion(estatus: Value('reservada'), fechaAplicacion: Value(null)),
      );
      await (db.update(db.descuentoProgramadoEmpleado)..where((t) => t.id.equals(descuentoId))).write(
        const DescuentoProgramadoEmpleadoCompanion(saldoPendiente: Value(1500000), estatus: Value('activo')),
      );
      expect((await descuentoRepo.listarCuotas(descuentoId)).single.estatus, 'reservada', reason: 'estado histórico simulado');

      final primera = await reconciliar.ejecutar();
      expect(primera.renglonesCorregidos, 1);

      final trasPrimera = await descuentoRepo.obtenerPorId(descuentoId);
      expect((await descuentoRepo.listarCuotas(descuentoId)).single.estatus, 'aplicada');
      expect(trasPrimera!.saldoPendiente, 0);
      expect(trasPrimera.estatus, 'liquidado');

      final segunda = await reconciliar.ejecutar();
      expect(segunda.renglonesCorregidos, 0, reason: 'la cuota ya está aplicada — nunca debe volver a aplicarse');
      final trasSegunda = await descuentoRepo.obtenerPorId(descuentoId);
      expect(trasSegunda!.saldoPendiente, 0, reason: 'nunca debe decrementarse una segunda vez');
      expect((await descuentoRepo.listarCuotas(descuentoId)).single.estatus, 'aplicada');
    },
  );

  test(
    'Dashboard — antes de reconciliar, ObtenerProximaNominaUseCase devuelve la Nómina completamente cubierta '
    'como pendiente; después de reconciliar, deja de aparecer',
    () async {
      await crearEmpleadoDePrueba(sueldoMensualAdministrativo: 3000000);
      final generado = (await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
      final renglon = (await nominaRepo.listarEmpleados(generado.nomina.id)).single;
      await actualizarRenglon.ejecutar(nominaEmpleadoId: renglon.id, otrosDescuentos: renglon.totalAPagar);
      await cerrarNomina.ejecutar(nominaId: generado.nomina.id);
      await forzarComoHistoricoSinReconciliar(renglon.id);

      final antes = await obtenerProximaNomina.ejecutar();
      expect(antes?.id, generado.nomina.id, reason: 'histórico simulado: sigue "cerrada", aparece como próxima nómina pendiente');

      await reconciliar.ejecutar();

      final despues = await obtenerProximaNomina.ejecutar();
      expect(despues, isNull, reason: 'ya está `pagada` en su totalidad — nunca debe seguir apareciendo como próxima nómina');
    },
  );

  test('una Nómina realmente parcialmente pagada NUNCA se marca `pagada` por la reconciliación', () async {
    await crearEmpleadoDePrueba(sueldoMensualAdministrativo: 3000000);
    await crearEmpleadoDePrueba(sueldoMensualAdministrativo: 3000000);
    final generado = (await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
    final renglones = await nominaRepo.listarEmpleados(generado.nomina.id);
    await cerrarNomina.ejecutar(nominaId: generado.nomina.id);

    // Solo se paga el primero — el segundo tiene saldo real pendiente,
    // nunca debe confundirse con un renglón en $0.00.
    await registrarPagoNomina.ejecutar(
      nominaId: generado.nomina.id,
      fechaPago: DateTime(2026, 8, 20),
      formaPago: 'transferencia',
      cuentaFinancieraId: await _cuentaDePrueba(db),
      aplicaciones: [(nominaEmpleadoId: renglones.first.id, monto: renglones.first.totalAPagar)],
    );

    final resultado = await reconciliar.ejecutar();

    expect(resultado.nominasActualizadas, 0);
    expect((await nominaRepo.obtenerPorId(generado.nomina.id))!.estatus, 'cerrada');
    expect((await nominaRepo.obtenerEmpleado(renglones.last.id))!.estatusPago, 'pendiente', reason: 'saldo real > 0, nunca debe marcarse pagado');
  });

  test('un renglón con saldo real pendiente > 0 permanece `pendiente` tras reconciliar (nunca se le fuerza a pagado)', () async {
    await crearEmpleadoDePrueba(sueldoMensualAdministrativo: 3000000);
    final generado = (await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
    final renglon = (await nominaRepo.listarEmpleados(generado.nomina.id)).single;
    expect(renglon.totalAPagar, greaterThan(0));
    await cerrarNomina.ejecutar(nominaId: generado.nomina.id);

    final resultado = await reconciliar.ejecutar();

    expect(resultado.renglonesCorregidos, 0);
    expect((await nominaRepo.obtenerEmpleado(renglon.id))!.estatusPago, 'pendiente');
    expect((await nominaRepo.obtenerPorId(generado.nomina.id))!.estatus, 'cerrada');
  });

  test(
    'registrar un pago nuevo después del fix mantiene el comportamiento correcto sin necesitar reconciliación manual '
    '(la reconciliación es un respaldo para datos históricos, nunca un paso obligatorio para operación normal)',
    () async {
      await crearEmpleadoDePrueba(sueldoMensualAdministrativo: 3000000);
      final generado = (await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
      final renglon = (await nominaRepo.listarEmpleados(generado.nomina.id)).single;
      await cerrarNomina.ejecutar(nominaId: generado.nomina.id);

      await registrarPagoNomina.ejecutar(
        nominaId: generado.nomina.id,
        fechaPago: DateTime(2026, 8, 20),
        formaPago: 'transferencia',
        cuentaFinancieraId: await _cuentaDePrueba(db),
        aplicaciones: [(nominaEmpleadoId: renglon.id, monto: renglon.totalAPagar)],
      );

      expect((await nominaRepo.obtenerEmpleado(renglon.id))!.estatusPago, 'pagado');
      expect((await nominaRepo.obtenerPorId(generado.nomina.id))!.estatus, 'pagada');
      expect(await obtenerProximaNomina.ejecutar(), isNull);

      // Correr la reconciliación encima no cambia nada — ya estaba
      // correcto sin necesitar este mecanismo.
      final resultado = await reconciliar.ejecutar();
      expect(resultado.renglonesCorregidos, 0);
      expect(resultado.nominasActualizadas, 0);
    },
  );
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
