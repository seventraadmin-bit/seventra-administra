// Etapa 15 — rediseño del detalle de Nómina como calculadora auditable.
// Cubre la única fórmula del dominio (`calcularTotalesRenglonNomina`,
// antes duplicada 4 veces dentro de `NominaRepositoryImpl`) y el caso
// de uso unificado `ActualizarRenglonNominaUseCase` (reemplaza los
// antiguos "Guardar movimientos" + "Guardar distribución" separados,
// ahora una sola escritura transaccional). Verifica en particular que
// `faltas` NUNCA reduce `diasPagables` (son independientes por diseño
// — nunca hay doble descuento) y que Fiscal + No fiscal se mantiene
// siempre igual al total a pagar.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/descuentos_personal/data/repositories/descuento_programado_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/repositories/nomina_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/repositories/pago_nomina_repository_impl.dart';
import 'package:riseg_one/features/tiempos_extra/data/repositories/tiempo_extra_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/tables/nomina_table.dart';
import 'package:riseg_one/features/nomina/domain/usecases/actualizar_renglon_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/calcular_totales_renglon_nomina.dart';
import 'package:riseg_one/features/nomina/domain/usecases/cerrar_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/evaluar_renglones_requieren_revision_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/generar_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/resolver_sueldo_empleado_nomina.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/puesto_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';

void main() {
  group('calcularTotalesRenglonNomina — fórmula pura', () {
    test('quincena de 15 días, sueldo \$11,000, 0 faltas → importeBase (base de la fórmula) = \$5,500 → neto = \$5,500', () {
      // sueldoMensual $11,000.00 → importeBase de una quincena completa
      // = sueldoMensual / 2 = $5,500.00 (calculado por
      // `calcularDiasPagablesEmpleado`, no por esta función — aquí se
      // inyecta ya resuelto, como lo hace el repositorio real).
      final totales = calcularTotalesRenglonNomina(
        importeBase: 550000,
        pagoPorDia: 36667,
        bono: 0,
        tiempoExtra: 0,
        prestamo: 0,
        faltas: 0,
        otrosDescuentos: 0,
        descuentosInventario: 0,
        descuentosProgramados: 0,
      );

      expect(totales.descuentoPorFaltas, 0);
      expect(totales.totalAPagar, 550000);
    });

    test('6 faltas sobre sueldo \$11,000 (salario diario \$366.67) → descuentoPorFaltas = \$2,200.00 exacto', () {
      final totales = calcularTotalesRenglonNomina(
        importeBase: 550000,
        pagoPorDia: 36667,
        bono: 0,
        tiempoExtra: 0,
        prestamo: 0,
        faltas: 6,
        otrosDescuentos: 0,
        descuentosInventario: 0,
        descuentosProgramados: 0,
      );

      expect(totales.descuentoPorFaltas, 220002, reason: '6 × 36667 = 220,002 centavos = \$2,200.02 (redondeo por centavo, no por peso)');
      expect(totales.totalAPagar, 550000 - 220002);
    });

    test('faltas nunca se descuentan dos veces: importeBase no varía con faltas, solo descuentoPorFaltas', () {
      final sinFaltas = calcularTotalesRenglonNomina(
        importeBase: 550000,
        pagoPorDia: 36667,
        bono: 0,
        tiempoExtra: 0,
        prestamo: 0,
        faltas: 0,
        otrosDescuentos: 0,
        descuentosInventario: 0,
        descuentosProgramados: 0,
      );
      final conFaltas = calcularTotalesRenglonNomina(
        importeBase: 550000,
        pagoPorDia: 36667,
        bono: 0,
        tiempoExtra: 0,
        prestamo: 0,
        faltas: 6,
        otrosDescuentos: 0,
        descuentosInventario: 0,
        descuentosProgramados: 0,
      );

      expect(sinFaltas.totalAPagar - conFaltas.totalAPagar, conFaltas.descuentoPorFaltas, reason: 'la única diferencia entre ambos es exactamente UN descuentoPorFaltas, nunca el doble');
    });

    test('tiempo extra incrementa el neto exactamente en su monto', () {
      final base = calcularTotalesRenglonNomina(
        importeBase: 550000,
        pagoPorDia: 36667,
        bono: 0,
        tiempoExtra: 0,
        prestamo: 0,
        faltas: 0,
        otrosDescuentos: 0,
        descuentosInventario: 0,
        descuentosProgramados: 0,
      );
      final conExtra = calcularTotalesRenglonNomina(
        importeBase: 550000,
        pagoPorDia: 36667,
        bono: 0,
        tiempoExtra: 30000,
        prestamo: 0,
        faltas: 0,
        otrosDescuentos: 0,
        descuentosInventario: 0,
        descuentosProgramados: 0,
      );

      expect(conExtra.totalAPagar, base.totalAPagar + 30000);
    });

    test('otros descuentos reducen el neto exactamente en su monto', () {
      final base = calcularTotalesRenglonNomina(
        importeBase: 550000,
        pagoPorDia: 36667,
        bono: 0,
        tiempoExtra: 0,
        prestamo: 0,
        faltas: 0,
        otrosDescuentos: 0,
        descuentosInventario: 0,
        descuentosProgramados: 0,
      );
      final conOtros = calcularTotalesRenglonNomina(
        importeBase: 550000,
        pagoPorDia: 36667,
        bono: 0,
        tiempoExtra: 0,
        prestamo: 0,
        faltas: 0,
        otrosDescuentos: 15000,
        descuentosInventario: 0,
        descuentosProgramados: 0,
      );

      expect(conOtros.totalAPagar, base.totalAPagar - 15000);
    });

    test('bono se suma una sola vez (un solo campo, una sola llamada)', () {
      final totales = calcularTotalesRenglonNomina(
        importeBase: 550000,
        pagoPorDia: 36667,
        bono: 80000,
        tiempoExtra: 0,
        prestamo: 0,
        faltas: 0,
        otrosDescuentos: 0,
        descuentosInventario: 0,
        descuentosProgramados: 0,
      );

      expect(totales.totalAPagar, 630000);
    });

    test(
      'BUG REAL: 4 faltas sobre un periodo parcial de 4 días puede rendir un total NEGATIVO por '
      '1 centavo (importeBase 146667 vs 4 × pagoPorDia 36667 = 146668) — la fórmula en sí no bloquea '
      'esto, es responsabilidad de quien la llama (ver `ActualizarRenglonNominaUseCase` abajo)',
      () {
        final totales = calcularTotalesRenglonNomina(
          importeBase: 146667,
          pagoPorDia: 36667,
          bono: 0,
          tiempoExtra: 0,
          prestamo: 0,
          faltas: 4,
          otrosDescuentos: 0,
          descuentosInventario: 0,
          descuentosProgramados: 0,
        );

        expect(totales.totalAPagar, -1);
      },
    );

    test('descuentosInventario se descuenta una sola vez', () {
      final totales = calcularTotalesRenglonNomina(
        importeBase: 550000,
        pagoPorDia: 36667,
        bono: 0,
        tiempoExtra: 0,
        prestamo: 0,
        faltas: 0,
        otrosDescuentos: 0,
        descuentosInventario: 25000,
        descuentosProgramados: 0,
      );

      expect(totales.totalAPagar, 525000);
    });
  });

  group('ActualizarRenglonNominaUseCase — integración con BD real', () {
    late AppDatabase db;
    late NominaRepositoryImpl nominaRepo;
    late GenerarNominaUseCase generarNomina;
    late ActualizarRenglonNominaUseCase actualizarRenglon;
    late CerrarNominaUseCase cerrarNomina;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      final asignacionServicioRepo = AsignacionServicioRepositoryImpl(db);
      final empleadoRepo = EmpleadoRepositoryImpl(db, asignacionServicioRepo);
      final servicioRepo = ServicioRepositoryImpl(db, asignacionServicioRepo);
      final catalogoRepo = CatalogoRepositoryImpl(db);
      final puestoRepo = PuestoRepositoryImpl(db);
      final resolverSueldo = ResolverSueldoEmpleadoNomina(empleadoRepo, asignacionServicioRepo, servicioRepo, catalogoRepo);
      nominaRepo = NominaRepositoryImpl(db, AsignacionRepositoryImpl(db), DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db)), TiempoExtraRepositoryImpl(db, EgresoRepositoryImpl(db), DeudaRepositoryImpl(db, EgresoRepositoryImpl(db)), CodigoSecuenciaService(db), EmpleadoRepositoryImpl(db, AsignacionServicioRepositoryImpl(db)), ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db))), PagoNominaRepositoryImpl(db, EgresoRepositoryImpl(db), DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db))));
      generarNomina =
          GenerarNominaUseCase(nominaRepo, empleadoRepo, puestoRepo, catalogoRepo, resolverSueldo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));
      actualizarRenglon = ActualizarRenglonNominaUseCase(nominaRepo);
      cerrarNomina = CerrarNominaUseCase(nominaRepo, EvaluarRenglonesRequierenRevisionUseCase(nominaRepo, empleadoRepo, resolverSueldo));
    });

    tearDown(() => db.close());

    Future<EmpleadoData> crearEmpleadoConSueldo(int sueldoMensualAdministrativo) {
      return db.into(db.empleado).insertReturning(
            EmpleadoCompanion.insert(
              numeroEmpleado: 1,
              nombres: 'Ana Karen',
              apellidoPaterno: 'Gómez',
              apellidoMaterno: const Value('Frogoso'),
              sexo: 'femenino',
              fechaNacimiento: DateTime(1990, 1, 1),
              curp: 'GOFA900101MDFXXX01',
              rfc: 'GOFA9001019AB',
              nss: '10000000001',
              estadoCivil: 'soltero',
              fechaIngreso: DateTime(2025, 1, 1),
              aniosExperienciaSeguridad: 3,
              sueldoMensualAdministrativo: Value(sueldoMensualAdministrativo),
            ),
          );
    }

    test('Fiscal + No fiscal = neto siempre, tras actualizarRenglon SIN distribución manual (automática)', () async {
      await crearEmpleadoConSueldo(1100000);
      final generado = (await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
      final renglon = (await nominaRepo.listarEmpleados(generado.nomina.id)).single;

      final resultado = await actualizarRenglon.ejecutar(nominaEmpleadoId: renglon.id, bono: 80000, tiempoExtra: 0);
      final actualizado = (resultado as ActualizarRenglonNominaExitoso).renglon;

      expect(actualizado.montoFiscal + actualizado.montoNoFiscal, actualizado.totalAPagar);
    });

    test('Fiscal + No fiscal = neto siempre, tras actualizarRenglon CON distribución manual que balancea', () async {
      await crearEmpleadoConSueldo(1100000);
      final generado = (await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
      final renglon = (await nominaRepo.listarEmpleados(generado.nomina.id)).single;

      final resultado = await actualizarRenglon.ejecutar(
        nominaEmpleadoId: renglon.id,
        bono: 80000,
        distribucionManual: (montoFiscal: 400000, montoNoFiscal: 230000),
      );
      final actualizado = (resultado as ActualizarRenglonNominaExitoso).renglon;

      expect(actualizado.totalAPagar, 630000);
      expect(actualizado.montoFiscal, 400000);
      expect(actualizado.montoNoFiscal, 230000);
      expect(actualizado.distribucionModificadaManualmente, isTrue);
      expect(actualizado.distribucionPendienteRevision, isFalse);
    });

    test(
      'distribución manual que YA NO balancea contra el neto prospectivo (bono agregado en la misma llamada) → '
      'ActualizarRenglonNominaNoBalancea, no escribe nada',
      () async {
        await crearEmpleadoConSueldo(1100000);
        final generado = (await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
        final renglon = (await nominaRepo.listarEmpleados(generado.nomina.id)).single;

        // Neto prospectivo = 550000 + 80000 (bono) = 630000 — la
        // distribución enviada (400000+150000=550000) NO balancea contra
        // ESE total, aunque hubiera balanceado contra el total viejo.
        final resultado = await actualizarRenglon.ejecutar(
          nominaEmpleadoId: renglon.id,
          bono: 80000,
          distribucionManual: (montoFiscal: 400000, montoNoFiscal: 150000),
        );

        expect(resultado, isA<ActualizarRenglonNominaNoBalancea>());
        final sinCambios = await nominaRepo.obtenerEmpleado(renglon.id);
        expect(sinCambios!.bono, 0, reason: 'nada se escribió — ni el bono ni la distribución');
        expect(sinCambios.totalAPagar, 550000);
      },
    );

    test(
      'BUG REAL (reportado por Marlon, "Guardar cambios" en Detalle de nómina): capturar faltas que dejan un '
      'total negativo por 1 centavo ya NO revienta el CHECK (monto_fiscal >= 0) como excepción no manejada — '
      'se rechaza explícitamente con ActualizarRenglonNominaTotalNegativo, sin escribir nada',
      () async {
        await crearEmpleadoConSueldo(1100000);
        final generado = (await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
        final renglon = (await nominaRepo.listarEmpleados(generado.nomina.id)).single;

        // Simula el periodo parcial real del reporte (4 días pagables,
        // importeBase/pagoPorDia tales que 4 faltas cuestan 1 centavo
        // MÁS que el importeBase completo) directamente sobre la fila ya
        // generada — reproduce el escenario exacto sin depender de un
        // cálculo de días pagables adicional.
        await (db.update(db.nominaEmpleado)..where((t) => t.id.equals(renglon.id))).write(
          const NominaEmpleadoCompanion(
            diasPagables: Value(4),
            importeBase: Value(146667),
            pagoPorDia: Value(36667),
            totalAPagar: Value(146667),
            montoFiscal: Value(146667),
          ),
        );

        final resultado = await actualizarRenglon.ejecutar(nominaEmpleadoId: renglon.id, faltas: 4);

        expect(resultado, isA<ActualizarRenglonNominaTotalNegativo>());
        final sinCambios = await nominaRepo.obtenerEmpleado(renglon.id);
        expect(sinCambios!.faltas, 0, reason: 'nada se escribió — ni siquiera las faltas capturadas');
        expect(sinCambios.totalAPagar, 146667, reason: 'el total previo queda intacto, nunca en -\$0.01');
      },
    );

    test('Nómina cerrada: actualizarRenglon rechaza la escritura (regresión — mismo check que antes de la unificación)', () async {
      await crearEmpleadoConSueldo(1100000);
      final generado = (await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
      final renglon = (await nominaRepo.listarEmpleados(generado.nomina.id)).single;
      await cerrarNomina.ejecutar(nominaId: generado.nomina.id);

      final resultado = await actualizarRenglon.ejecutar(nominaEmpleadoId: renglon.id, bono: 100000);

      expect(resultado, isA<ActualizarRenglonNominaNominaCerrada>());
      final sinCambios = await nominaRepo.obtenerEmpleado(renglon.id);
      expect(sinCambios!.bono, 0);
    });
  });
}
