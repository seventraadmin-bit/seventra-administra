// Bug real reportado por Marlon (2026-08-30): dos renglones de
// NOM-000012 con Neto=$0.00 aparecían con Estado "Pendiente" en el
// detalle de Nómina, incluso después de "pagar" la Nómina — porque
// nunca pasan por un pago real (no hay nada que pagar), así que
// `NominaEmpleado.estatusPago` se quedaba atorado en el default
// `pendiente` para siempre. Eso a su vez dejaba la Nómina completa
// atorada en `cerrada` (`_evaluarNominaPagada` exige que TODOS los
// renglones reporten `pagado`), así que "Próxima nómina" seguía
// apareciendo en el Dashboard aun después de pagar el renglón real —
// el segundo síntoma reportado, mismo origen.
//
// Fix: `NominaRepositoryImpl` ahora compone `PagoNominaRepository` y
// llama `sincronizarEstatusPago` después de cada escritura de
// `totalAPagar` (`generar`/`guardarRenglon`/`actualizarRenglon`), que
// aplica exactamente el mismo criterio saldo<=0 → `pagado` que ya usa
// la propia `PagoNominaRepositoryImpl`, incluyendo el efecto
// secundario sobre `DescuentoProgramadoCuota` (`reservada` → `aplicada`).

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
import 'package:riseg_one/features/tiempos_extra/data/repositories/tiempo_extra_repository_impl.dart';

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

  test(
    'un renglón cuyo neto llega a \$0 por una cuota programada reservada queda `pagado` de inmediato al '
    'generar la Nómina — nunca se queda atorado en `pendiente` esperando un pago real que nunca llegará',
    () async {
      final empleado = await crearEmpleadoDePrueba(sueldoMensualAdministrativo: 3000000);
      final descuento = await registrarDescuento.ejecutar(
        empleadoId: empleado.id,
        tipo: 'prestamo',
        fechaRegistro: DateTime(2026, 8, 10),
        importeOriginal: 1500000,
        numeroCuotas: 1,
        fechaPrimeraCuota: DateTime(2026, 8, 10),
      );
      final descuentoId = (descuento as RegistrarDescuentoProgramadoExitoso).descuento.id;

      final generado = await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera);
      final exitoso = generado as GenerarNominaExitoso;
      final renglon = (await nominaRepo.listarEmpleados(exitoso.nomina.id)).single;

      expect(renglon.totalAPagar, 0, reason: 'importeBase (1,500,000) menos la cuota reservada (1,500,000)');
      expect(
        renglon.estatusPago,
        'pagado',
        reason: 'saldoPendiente (0) <= 0 ya significa pagado, mismo criterio que usa el diálogo de pago en vivo',
      );

      final cuotas = await descuentoRepo.listarCuotas(descuentoId);
      expect(cuotas.single.estatus, 'aplicada', reason: 'el renglón ya cruzó a pagado — la cuota reservada debe liberarse con él');
      final saldo = await descuentoRepo.obtenerPorId(descuentoId);
      expect(saldo!.saldoPendiente, 0);
      expect(saldo.estatus, 'liquidado');
    },
  );

  test(
    'una Nómina con un renglón en \$0 y otro con neto real alcanza `pagada` en cuanto se paga solo el renglón '
    'real — nunca se queda atorada en `cerrada` (bug real: el Dashboard seguía mostrando "Próxima nómina")',
    () async {
      final empleadoCero = await crearEmpleadoDePrueba(sueldoMensualAdministrativo: 3000000);
      await registrarDescuento.ejecutar(
        empleadoId: empleadoCero.id,
        tipo: 'prestamo',
        fechaRegistro: DateTime(2026, 8, 10),
        importeOriginal: 1500000,
        numeroCuotas: 1,
        fechaPrimeraCuota: DateTime(2026, 8, 10),
      );
      await crearEmpleadoDePrueba(sueldoMensualAdministrativo: 3000000);

      final generado = (await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
      await cerrarNomina.ejecutar(nominaId: generado.nomina.id);

      final renglones = await nominaRepo.listarEmpleados(generado.nomina.id);
      final renglonCero = renglones.firstWhere((r) => r.totalAPagar == 0);
      final renglonReal = renglones.firstWhere((r) => r.totalAPagar > 0);

      expect(renglonCero.estatusPago, 'pagado', reason: 'ya cruzó a pagado desde la generación, cerrar no lo toca');
      expect(
        (await nominaRepo.obtenerPorId(generado.nomina.id))!.estatus,
        'cerrada',
        reason: 'el renglón real todavía no se ha pagado de verdad',
      );

      await registrarPagoNomina.ejecutar(
        nominaId: generado.nomina.id,
        fechaPago: DateTime(2026, 8, 20),
        formaPago: 'transferencia',
        cuentaFinancieraId: await _cuentaDePrueba(db),
        aplicaciones: [(nominaEmpleadoId: renglonReal.id, monto: renglonReal.totalAPagar)],
      );

      expect(
        (await nominaRepo.obtenerPorId(generado.nomina.id))!.estatus,
        'pagada',
        reason: 'los dos renglones ya reportan pagado — nunca debe seguir apareciendo como "Próxima nómina"',
      );
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
