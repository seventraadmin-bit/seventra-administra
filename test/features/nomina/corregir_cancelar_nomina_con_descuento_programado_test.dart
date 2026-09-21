// Etapa 5 (Descuentos programados — CRUD corregible, trazabilidad y
// consistencia con Nómina), Sección 10: la auditoría encontró que
// ningún test existente combinaba `CorregirRenglonNominaUseCase`/
// `CancelarNominaUseCase` (Etapa 4) con una `DescuentoProgramadoCuota`
// REAL en estatus `reservada`/`aplicada` — solo se había probado con
// campos manuales (`otrosDescuentos`/`bono`). Esta suite cierra ese
// hueco: corregir un renglón nunca debe duplicar/tocar la cuota
// reservada o aplicada de Descuentos Programados, y cancelar una
// Nómina Cerrada-sin-pagos debe liberarla correctamente de vuelta a
// `pendiente`, sin huérfanos ni doble liberación.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/features/finanzas/data/repositories/cuenta_financiera_repository_impl.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/codigos/generar_numero_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/descuentos_personal/data/repositories/descuento_programado_repository_impl.dart';
import 'package:riseg_one/features/descuentos_personal/domain/repositories/descuento_programado_repository.dart';
import 'package:riseg_one/features/descuentos_personal/domain/usecases/registrar_descuento_programado_usecase.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/repositories/nomina_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/repositories/pago_nomina_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/tables/nomina_table.dart';
import 'package:riseg_one/features/nomina/domain/usecases/cancelar_nomina_usecase.dart';
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
  late CancelarNominaUseCase cancelarNomina;
  late DescuentoProgramadoRepository descuentoRepo;
  late RegistrarDescuentoProgramadoUseCase registrarDescuento;
  late EmpleadoData empleado;

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
    descuentoRepo = DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db));
    pagoNominaRepo = PagoNominaRepositoryImpl(db, egresoRepo, descuentoRepo);
    nominaRepo = NominaRepositoryImpl(
      db,
      AsignacionRepositoryImpl(db),
      descuentoRepo,
      TiempoExtraRepositoryImpl(db, egresoRepo, deudaRepo, CodigoSecuenciaService(db), empleadoRepo, servicioRepo),
      pagoNominaRepo,
    );
    generarNomina = GenerarNominaUseCase(nominaRepo, empleadoRepo, puestoRepo, catalogoRepo, resolverSueldo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));
    cerrarNomina = CerrarNominaUseCase(nominaRepo, EvaluarRenglonesRequierenRevisionUseCase(nominaRepo, empleadoRepo, resolverSueldo));
    registrarPagoNomina = RegistrarPagoNominaUseCase(pagoNominaRepo, nominaRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)), CuentaFinancieraRepositoryImpl(db));
    corregirRenglon = CorregirRenglonNominaUseCase(nominaRepo, pagoNominaRepo);
    cancelarNomina = CancelarNominaUseCase(nominaRepo, pagoNominaRepo);
    registrarDescuento = RegistrarDescuentoProgramadoUseCase(descuentoRepo, empleadoRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));

    final crearEmpleado = CrearEmpleadoUseCase(
      empleadoRepo,
      GenerarNumeroUseCase(CodigoSecuenciaService(db)),
      const EmpleadoValidator(),
      servicioRepo,
      ServicioComercialRepositoryImpl(db),
    );
    final creado = await crearEmpleado.ejecutar(
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
      sueldoMensualAdministrativo: 3000000,
    );
    empleado = (creado as CrearEmpleadoExitoso).empleado;
  });

  tearDown(() => db.close());

  test(
    'CorregirRenglonNominaUseCase sobre una Nómina Cerrada-sin-pagos con una cuota REAL `reservada`: '
    'la cuota permanece intacta, sin duplicarse ni desvincularse',
    () async {
      final registrado = await registrarDescuento.ejecutar(
        empleadoId: empleado.id,
        tipo: 'prestamo',
        fechaRegistro: DateTime(2026, 1, 1),
        importeOriginal: 100000,
        numeroCuotas: 1,
        fechaPrimeraCuota: DateTime(2026, 1, 20),
      );
      final descuentoId = (registrado as RegistrarDescuentoProgramadoExitoso).descuento.id;

      final generado = (await generarNomina.ejecutar(anio: 2026, mes: 1, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
      var renglon = (await nominaRepo.listarEmpleados(generado.nomina.id)).single;
      expect(renglon.descuentosProgramados, 100000);
      await cerrarNomina.ejecutar(nominaId: generado.nomina.id);

      final cuotaAntes = (await descuentoRepo.listarCuotas(descuentoId)).single;
      expect(cuotaAntes.estatus, 'reservada');
      expect(cuotaAntes.nominaEmpleadoId, renglon.id);

      final resultado = await corregirRenglon.ejecutar(
        nominaEmpleadoId: renglon.id,
        bono: renglon.bono + 50000,
        motivo: r'Se omitió un bono real de $500',
      );
      expect(resultado, isA<CorregirRenglonNominaExitoso>());

      final cuotaDespues = (await descuentoRepo.listarCuotas(descuentoId)).single;
      expect(cuotaDespues.id, cuotaAntes.id, reason: 'la cuota nunca se reemplaza por corregir el renglón');
      expect(cuotaDespues.estatus, 'reservada', reason: 'sigue reservada — corregir el renglón nunca la aplica ni la libera');
      expect(cuotaDespues.nominaEmpleadoId, renglon.id);
      expect(cuotaDespues.importeProgramado, cuotaAntes.importeProgramado);

      renglon = (await nominaRepo.listarEmpleados(generado.nomina.id)).single;
      expect(renglon.descuentosProgramados, 100000, reason: 'la corrección de bono nunca duplica ni cambia el descuento programado ya reservado');
      expect((await descuentoRepo.obtenerPorId(descuentoId))!.saldoPendiente, 100000, reason: 'reservada nunca decrementa saldoPendiente');
    },
  );

  test(
    'CorregirRenglonNominaUseCase sobre una Nómina Pagada con una cuota REAL `aplicada`: '
    'la cuota y el saldo ya decrecido permanecen intactos',
    () async {
      final registrado = await registrarDescuento.ejecutar(
        empleadoId: empleado.id,
        tipo: 'prestamo',
        fechaRegistro: DateTime(2026, 1, 1),
        importeOriginal: 100000,
        numeroCuotas: 1,
        fechaPrimeraCuota: DateTime(2026, 1, 20),
      );
      final descuentoId = (registrado as RegistrarDescuentoProgramadoExitoso).descuento.id;

      final generado = (await generarNomina.ejecutar(anio: 2026, mes: 1, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
      var renglon = (await nominaRepo.listarEmpleados(generado.nomina.id)).single;
      await cerrarNomina.ejecutar(nominaId: generado.nomina.id);
      await registrarPagoNomina.ejecutar(
        nominaId: generado.nomina.id,
        fechaPago: DateTime(2026, 1, 20),
        formaPago: 'transferencia',
        cuentaFinancieraId: await _cuentaDePrueba(db),
        aplicaciones: [(nominaEmpleadoId: renglon.id, monto: renglon.totalAPagar)],
      );

      final cuotaAntes = (await descuentoRepo.listarCuotas(descuentoId)).single;
      expect(cuotaAntes.estatus, 'aplicada');
      final saldoAntes = (await descuentoRepo.obtenerPorId(descuentoId))!.saldoPendiente;
      expect(saldoAntes, 0);

      // Corrección que NO cambia el total neto (bono y otrosDescuentos
      // suben lo mismo) — el renglón sigue `pagado`, así que la cuota
      // ya aplicada debe permanecer intacta, sin duplicarse.
      final resultado = await corregirRenglon.ejecutar(
        nominaEmpleadoId: renglon.id,
        bono: renglon.bono + 50000,
        otrosDescuentos: renglon.otrosDescuentos + 50000,
        motivo: r'Reclasificación: $500 que eran bono en realidad eran un descuento — el total no cambia',
      );
      expect(resultado, isA<CorregirRenglonNominaExitoso>());

      final cuotaDespues = (await descuentoRepo.listarCuotas(descuentoId)).single;
      expect(cuotaDespues.id, cuotaAntes.id);
      expect(cuotaDespues.estatus, 'aplicada', reason: 'el renglón sigue pagado — corregir sin cambiar el total nunca toca la cuota ya aplicada');
      expect(cuotaDespues.fechaAplicacion, cuotaAntes.fechaAplicacion);
      final saldoTrasCorregirSinCambio = (await descuentoRepo.obtenerPorId(descuentoId))!.saldoPendiente;
      expect(saldoTrasCorregirSinCambio, saldoAntes);

      // Corrección que SÍ sube el total por encima de lo ya pagado —
      // comportamiento real y correcto del sistema (Sección 6): el
      // renglón deja de estar `pagado` (queda con saldo pendiente
      // real), y por eso la cuota correctamente REVIERTE a `reservada`
      // (mismo mecanismo que cancelar un pago) — nunca queda
      // `aplicada` con dinero que en los hechos ya no está cubierto.
      final resultadoArriba = await corregirRenglon.ejecutar(
        nominaEmpleadoId: renglon.id,
        bono: renglon.bono + 100000,
        motivo: r'Se debía un bono adicional real de $1,000, no cubierto por el pago ya registrado',
      );
      expect(resultadoArriba, isA<CorregirRenglonNominaExitoso>());
      final cuotaTrasSubir = (await descuentoRepo.listarCuotas(descuentoId)).single;
      expect(
        cuotaTrasSubir.estatus,
        'reservada',
        reason: 'el pago ya no cubre el nuevo total — la Nómina se reabre y la cuota correctamente vuelve a reservada, no queda aplicada a medias',
      );
      final saldoTrasSubir = (await descuentoRepo.obtenerPorId(descuentoId))!.saldoPendiente;
      expect(saldoTrasSubir, 100000, reason: 'se restaura exactamente el saldo del descuento — ya no está cubierto por el pago viejo');
    },
  );

  test(
    'CancelarNominaUseCase sobre Cerrada-sin-pagos con una cuota REAL `reservada`: '
    'libera la cuota a `pendiente`, restaura disponibilidad, sin huérfanos',
    () async {
      final registrado = await registrarDescuento.ejecutar(
        empleadoId: empleado.id,
        tipo: 'prestamo',
        fechaRegistro: DateTime(2026, 1, 1),
        importeOriginal: 100000,
        numeroCuotas: 1,
        fechaPrimeraCuota: DateTime(2026, 1, 20),
      );
      final descuentoId = (registrado as RegistrarDescuentoProgramadoExitoso).descuento.id;

      final generado = (await generarNomina.ejecutar(anio: 2026, mes: 1, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
      final renglon = (await nominaRepo.listarEmpleados(generado.nomina.id)).single;
      await cerrarNomina.ejecutar(nominaId: generado.nomina.id);
      expect((await descuentoRepo.listarCuotas(descuentoId)).single.estatus, 'reservada');

      final resultado = await cancelarNomina.ejecutar(nominaId: generado.nomina.id, motivo: MotivoCancelacionNomina.errorDeCaptura);
      expect(resultado, isA<CancelarNominaExitoso>());

      final cuotaTrasCancelar = (await descuentoRepo.listarCuotas(descuentoId)).single;
      expect(cuotaTrasCancelar.estatus, 'pendiente', reason: 'liberada de vuelta al pool disponible, nunca huérfana');
      expect(cuotaTrasCancelar.nominaEmpleadoId, isNull);
      final descuentoTrasCancelar = (await descuentoRepo.obtenerPorId(descuentoId))!;
      expect(descuentoTrasCancelar.saldoPendiente, 100000, reason: 'reservada nunca había decrementado el saldo — sigue intacto');
      expect(descuentoTrasCancelar.estatus, 'activo');

      // La cuota liberada sí está disponible para una Nómina futura —
      // confirma que no quedó en un limbo inconsistente.
      final generadoSiguiente = (await generarNomina.ejecutar(anio: 2026, mes: 1, tipo: TipoPeriodoNomina.segunda)) as GenerarNominaExitoso;
      final renglonSiguiente = (await nominaRepo.listarEmpleados(generadoSiguiente.nomina.id)).single;
      expect(renglonSiguiente.descuentosProgramados, 100000, reason: 'la cuota liberada se vuelve a ofrecer normalmente');
      expect(renglon.id, isNot(renglonSiguiente.id));
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
