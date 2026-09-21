// Integración Nómina ↔ Tiempos Extra (pedido explícito de Marlon:
// "poner en su nómina... para quien hace los cálculos lo tome en
// cuenta"). Cubre: ausencia incorporada al generar vs. al actualizar
// una Nómina ya existente, autocorrección al cancelar mientras sigue
// en Borrador, historial intacto tras Cerrar/Pagar, dos ausencias del
// mismo periodo no se pisan, y nunca toca faltas/montos del renglón.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/features/descuentos_personal/data/repositories/descuento_programado_repository_impl.dart';
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
import 'package:riseg_one/features/nomina/domain/usecases/resolver_sueldo_empleado_nomina.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/puesto_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_servicio_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';
import 'package:riseg_one/features/tiempos_extra/data/repositories/tiempo_extra_repository_impl.dart';
import 'package:riseg_one/features/tiempos_extra/data/tables/tiempo_extra_table.dart';
import 'package:riseg_one/features/tiempos_extra/domain/usecases/cancelar_tiempo_extra_usecase.dart';
import 'package:riseg_one/features/tiempos_extra/domain/usecases/registrar_tiempo_extra_usecase.dart';
import 'package:riseg_one/features/tiempos_extra/data/repositories/vacante_cobertura_reader.dart';

void main() {
  late AppDatabase db;
  late EmpleadoRepositoryImpl empleadoRepo;
  late NominaRepositoryImpl nominaRepo;
  late GenerarNominaUseCase generarNomina;
  late ActualizarNominaDesdePersonalUseCase actualizarDesdePersonal;
  late CerrarNominaUseCase cerrarNomina;
  late RegistrarTiempoExtraUseCase registrarTiempoExtra;
  late CancelarTiempoExtraUseCase cancelarTiempoExtra;
  late String servicioId;
  late String empleadoAusenteId;
  late String empleadoCubreId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final asignacionServicioRepo = AsignacionServicioRepositoryImpl(db);
    empleadoRepo = EmpleadoRepositoryImpl(db, asignacionServicioRepo);
    final servicioRepo = ServicioRepositoryImpl(db, asignacionServicioRepo);
    final clienteRepo = ClienteRepositoryImpl(db);
    final catalogoRepo = CatalogoRepositoryImpl(db);
    final puestoRepo = PuestoRepositoryImpl(db);
    final codigoSecuencia = CodigoSecuenciaService(db);
    final generarCodigo = GenerarCodigoUseCase(codigoSecuencia);
    final egresoRepo = EgresoRepositoryImpl(db);

    final deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
    final tiempoExtraRepo = TiempoExtraRepositoryImpl(db, egresoRepo, deudaRepo, codigoSecuencia, empleadoRepo, servicioRepo);
    registrarTiempoExtra = RegistrarTiempoExtraUseCase(tiempoExtraRepo, empleadoRepo, servicioRepo, deudaRepo, VacanteCoberturaReader(db));
    cancelarTiempoExtra = CancelarTiempoExtraUseCase(tiempoExtraRepo);

    nominaRepo = NominaRepositoryImpl(
      db,
      AsignacionRepositoryImpl(db),
      DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db)),
      tiempoExtraRepo,
      PagoNominaRepositoryImpl(db, EgresoRepositoryImpl(db), DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db))),
    );
    final resolverSueldo = ResolverSueldoEmpleadoNomina(empleadoRepo, asignacionServicioRepo, servicioRepo, catalogoRepo);
    generarNomina = GenerarNominaUseCase(nominaRepo, empleadoRepo, puestoRepo, catalogoRepo, resolverSueldo, generarCodigo);
    actualizarDesdePersonal = ActualizarNominaDesdePersonalUseCase(nominaRepo, empleadoRepo, puestoRepo, catalogoRepo, resolverSueldo);
    cerrarNomina = CerrarNominaUseCase(
      nominaRepo,
      EvaluarRenglonesRequierenRevisionUseCase(nominaRepo, empleadoRepo, resolverSueldo),
    );

    final cliente = await clienteRepo.crear(ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Sportium'));
    final servicioCreado = await CrearServicioUseCase(servicioRepo, generarCodigo, ServicioValidator(clienteRepo, catalogoRepo)).ejecutar(
      clienteId: cliente.id,
      borrador: ServicioBorrador(nombre: 'Vigilancia Sportium', tipoServicioId: SeedIds.tipoServicioVigilanciaFija, fechaInicio: DateTime(2026, 1, 1)),
    );
    servicioId = (servicioCreado as GuardarServicioExitoso).servicio.id;

    empleadoAusenteId = await _crearEmpleadoDePrueba(db, 1, 'Monica', sueldo: 900000);
    empleadoCubreId = await _crearEmpleadoDePrueba(db, 2, 'Juan', sueldo: 900000);
  });

  tearDown(() => db.close());

  Future<String> registrarAusencia({required DateTime fecha, int monto = 50000}) async {
    final resultado = await registrarTiempoExtra.ejecutar(
      fecha: fecha,
      servicioId: servicioId,
      origenCobertura: OrigenCoberturaTiempoExtra.ausenciaEmpleado.name,
      empleadoAusenteId: empleadoAusenteId,
      motivoAusencia: MotivoAusenciaTiempoExtra.faltaInjustificada.name,
      empleadoCubreId: empleadoCubreId,
      turnoId: SeedIds.modalidadTurno24x24,
      montoTiempoExtra: monto,
      formaPago: 'efectivo',
    );
    return (resultado as RegistrarTiempoExtraExitoso).tiempoExtra.id;
  }

  group('1. Ausencia registrada ANTES de generar la Nómina', () {
    test('se incorpora de una vez al generar', () async {
      await registrarAusencia(fecha: DateTime(2026, 8, 20));

      final generado = (await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.segunda)) as GenerarNominaExitoso;
      final renglon = (await nominaRepo.listarEmpleados(generado.nomina.id)).firstWhere((r) => r.empleadoId == empleadoAusenteId);

      final ausencias = await nominaRepo.listarAusencias(renglon.id);
      expect(ausencias, hasLength(1));
      expect(ausencias.single.motivoAusencia, 'faltaInjustificada');
      expect(ausencias.single.servicioNombre, isNotEmpty);
      expect(ausencias.single.nombreEmpleadoCubrio, contains('Juan'));

      // Puramente informativa — nunca toca faltas/montos reales.
      expect(renglon.faltas, 0);
      expect(renglon.descuentoPorFaltas, 0);
    });
  });

  group('2. Ausencia registrada DESPUÉS de que la Nómina ya existe (Borrador)', () {
    test('se incorpora al llamar Actualizar desde Personal, reprocesando el renglón', () async {
      final generado = (await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.segunda)) as GenerarNominaExitoso;
      var renglon = (await nominaRepo.listarEmpleados(generado.nomina.id)).firstWhere((r) => r.empleadoId == empleadoAusenteId);
      expect(await nominaRepo.listarAusencias(renglon.id), isEmpty);

      await registrarAusencia(fecha: DateTime(2026, 8, 20));
      final resultadoActualizar = await actualizarDesdePersonal.ejecutar(nominaId: generado.nomina.id);
      if (resultadoActualizar is ActualizarNominaDesdePersonalErrorInesperado) {
        fail('Actualizar desde Personal falló: ${resultadoActualizar.mensaje}');
      }

      renglon = (await nominaRepo.listarEmpleados(generado.nomina.id)).firstWhere((r) => r.empleadoId == empleadoAusenteId);
      final ausencias = await nominaRepo.listarAusencias(renglon.id);
      expect(ausencias, hasLength(1));
    });
  });

  group('3. Cancelar el TiempoExtra mientras la Nómina sigue en Borrador', () {
    test('la siguiente actualización deja de traerla (autocorrección, sin borrado especial)', () async {
      final tiempoExtraId = await registrarAusencia(fecha: DateTime(2026, 8, 20));
      final generado = (await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.segunda)) as GenerarNominaExitoso;
      var renglon = (await nominaRepo.listarEmpleados(generado.nomina.id)).firstWhere((r) => r.empleadoId == empleadoAusenteId);
      expect(await nominaRepo.listarAusencias(renglon.id), hasLength(1));

      await cancelarTiempoExtra.ejecutar(tiempoExtraId: tiempoExtraId, motivo: 'Registro de prueba');
      await actualizarDesdePersonal.ejecutar(nominaId: generado.nomina.id);

      renglon = (await nominaRepo.listarEmpleados(generado.nomina.id)).firstWhere((r) => r.empleadoId == empleadoAusenteId);
      expect(await nominaRepo.listarAusencias(renglon.id), isEmpty);
    });
  });

  group('4. Nómina ya Cerrada antes de cancelar el TiempoExtra', () {
    test('la ausencia queda como historial intacto (append-only, nunca se toca una Nómina cerrada)', () async {
      final tiempoExtraId = await registrarAusencia(fecha: DateTime(2026, 8, 20));
      final generado = (await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.segunda)) as GenerarNominaExitoso;
      final renglonAntes = (await nominaRepo.listarEmpleados(generado.nomina.id)).firstWhere((r) => r.empleadoId == empleadoAusenteId);
      expect(await nominaRepo.listarAusencias(renglonAntes.id), hasLength(1));

      final cierre = await cerrarNomina.ejecutar(nominaId: generado.nomina.id);
      expect(cierre, isA<CerrarNominaExitoso>());

      await cancelarTiempoExtra.ejecutar(tiempoExtraId: tiempoExtraId, motivo: 'Registro de prueba');

      final renglonDespues = (await nominaRepo.listarEmpleados(generado.nomina.id)).firstWhere((r) => r.empleadoId == empleadoAusenteId);
      expect(await nominaRepo.listarAusencias(renglonDespues.id), hasLength(1));
    });
  });

  group('5. Dos ausencias del mismo Empleado en el mismo periodo', () {
    test('generan dos filas independientes, ninguna se pisa', () async {
      await registrarAusencia(fecha: DateTime(2026, 8, 18), monto: 40000);
      await registrarAusencia(fecha: DateTime(2026, 8, 22), monto: 60000);

      final generado = (await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.segunda)) as GenerarNominaExitoso;
      final renglon = (await nominaRepo.listarEmpleados(generado.nomina.id)).firstWhere((r) => r.empleadoId == empleadoAusenteId);

      final ausencias = await nominaRepo.listarAusencias(renglon.id);
      expect(ausencias, hasLength(2));
      expect(ausencias.map((a) => a.fecha), containsAll([DateTime(2026, 8, 18), DateTime(2026, 8, 22)]));
    });
  });

  group('6. Nunca toca faltas/montos del renglón', () {
    test('el renglón del Empleado ausente conserva sus percepciones/deducciones normales', () async {
      await registrarAusencia(fecha: DateTime(2026, 8, 20), monto: 999999);

      final generado = (await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.segunda)) as GenerarNominaExitoso;
      final renglonAusente = (await nominaRepo.listarEmpleados(generado.nomina.id)).firstWhere((r) => r.empleadoId == empleadoAusenteId);
      final renglonCubre = (await nominaRepo.listarEmpleados(generado.nomina.id)).firstWhere((r) => r.empleadoId == empleadoCubreId);

      // El monto del tiempo extra (999999) no debe aparecer en ningún
      // lado de Nómina — ni del ausente ni de quien cubrió — porque se
      // paga entero vía el Egreso automático, nunca vía payroll.
      expect(renglonAusente.tiempoExtra, 0);
      expect(renglonCubre.tiempoExtra, 0);
      expect(renglonAusente.faltas, 0);
      expect(renglonAusente.totalAPagar, greaterThan(0));
    });
  });
}

Future<String> _crearEmpleadoDePrueba(AppDatabase db, int numero, String nombre, {required int sueldo}) async {
  final n = numero.toString().padLeft(2, '0');
  final empleado = await db.into(db.empleado).insertReturning(
        EmpleadoCompanion.insert(
          numeroEmpleado: numero,
          nombres: nombre,
          apellidoPaterno: 'Apellido$n',
          sexo: 'masculino',
          fechaNacimiento: DateTime(1990, 1, 1),
          curp: 'PEXJ900101HDFXXX$n',
          rfc: 'PEXJ900101$n',
          nss: '100000000$n',
          estadoCivil: 'soltero',
          fechaIngreso: DateTime(2025, 1, 1),
          aniosExperienciaSeguridad: 3,
          sueldoMensualAdministrativo: Value(sueldo),
        ),
      );
  return empleado.id;
}
