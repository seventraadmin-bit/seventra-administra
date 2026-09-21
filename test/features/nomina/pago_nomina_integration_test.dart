import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/features/finanzas/data/repositories/cuenta_financiera_repository_impl.dart';
import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/codigos/generar_numero_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/egreso_repository.dart';
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/descuentos_personal/data/repositories/descuento_programado_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/repositories/nomina_repository_impl.dart';
import 'package:riseg_one/features/tiempos_extra/data/repositories/tiempo_extra_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/repositories/pago_nomina_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/tables/nomina_table.dart';
import 'package:riseg_one/features/nomina/domain/usecases/adjuntar_comprobante_pago_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/cancelar_pago_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/cerrar_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/corregir_pago_nomina_usecase.dart';
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

void main() {
  late AppDatabase db;
  late Directory tempDir;
  late EmpleadoRepositoryImpl empleadoRepo;
  late EgresoRepository egresoRepo;
  late CrearEmpleadoUseCase crearEmpleado;

  late GenerarNominaUseCase generarNomina;
  late CerrarNominaUseCase cerrarNomina;
  late NominaRepositoryImpl nominaRepo;
  late PagoNominaRepositoryImpl pagoNominaRepo;
  late RegistrarPagoNominaUseCase registrarPagoNomina;
  late CancelarPagoNominaUseCase cancelarPagoNomina;
  late CorregirPagoNominaUseCase corregirPagoNomina;
  late AdjuntarComprobantePagoNominaUseCase adjuntarComprobantePagoNomina;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    tempDir = Directory.systemTemp.createTempSync('riseg_pago_nomina_test_');
    final asignacionRepo = AsignacionServicioRepositoryImpl(db);
    empleadoRepo = EmpleadoRepositoryImpl(db, asignacionRepo);
    final servicioRepo = ServicioRepositoryImpl(db, asignacionRepo);
    egresoRepo = EgresoRepositoryImpl(db);
    final catalogoRepo = CatalogoRepositoryImpl(db);
    final puestoRepo = PuestoRepositoryImpl(db);
    final codigoSecuencia = CodigoSecuenciaService(db);
    final generarCodigo = GenerarCodigoUseCase(codigoSecuencia);
    final generarNumero = GenerarNumeroUseCase(codigoSecuencia);
    const empleadoValidator = EmpleadoValidator();

    crearEmpleado = CrearEmpleadoUseCase(
      empleadoRepo,
      generarNumero,
      empleadoValidator,
      servicioRepo,
      ServicioComercialRepositoryImpl(db),
    );

    nominaRepo = NominaRepositoryImpl(db, AsignacionRepositoryImpl(db), DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db)), TiempoExtraRepositoryImpl(db, EgresoRepositoryImpl(db), DeudaRepositoryImpl(db, EgresoRepositoryImpl(db)), CodigoSecuenciaService(db), EmpleadoRepositoryImpl(db, AsignacionServicioRepositoryImpl(db)), ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db))), PagoNominaRepositoryImpl(db, EgresoRepositoryImpl(db), DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db))));
    final resolverSueldo = ResolverSueldoEmpleadoNomina(empleadoRepo, asignacionRepo, servicioRepo, catalogoRepo);
    generarNomina = GenerarNominaUseCase(nominaRepo, empleadoRepo, puestoRepo, catalogoRepo, resolverSueldo, generarCodigo);
    final evaluarRenglonesRequierenRevision = EvaluarRenglonesRequierenRevisionUseCase(nominaRepo, empleadoRepo, resolverSueldo);
    cerrarNomina = CerrarNominaUseCase(nominaRepo, evaluarRenglonesRequierenRevision);

    pagoNominaRepo = PagoNominaRepositoryImpl(db, egresoRepo, DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db)));
    registrarPagoNomina = RegistrarPagoNominaUseCase(pagoNominaRepo, nominaRepo, generarCodigo, CuentaFinancieraRepositoryImpl(db));
    cancelarPagoNomina = CancelarPagoNominaUseCase(pagoNominaRepo);
    corregirPagoNomina = CorregirPagoNominaUseCase(pagoNominaRepo);
    adjuntarComprobantePagoNomina = AdjuntarComprobantePagoNominaUseCase(pagoNominaRepo, AttachmentStorage(tempDir.path));
  });

  tearDown(() {
    db.close();
    tempDir.deleteSync(recursive: true);
  });

  var empleadoContador = 0;

  Future<EmpleadoData> crearEmpleadoDePrueba({int? sueldoMensualAdministrativo}) async {
    empleadoContador++;
    final n = empleadoContador.toString().padLeft(2, '0');
    final resultado = await crearEmpleado.ejecutar(
      nombres: 'Empleado$n',
      apellidoPaterno: 'Apellido$n',
      sexo: SexoEmpleado.masculino,
      fechaNacimiento: DateTime(1990, 1, 1),
      curp: 'PEXJ900101HDFXXX$n',
      rfc: 'PEXJ900101$n',
      nss: '100000000$n',
      estadoCivil: EstadoCivilEmpleado.soltero,
      fechaIngreso: DateTime(2025, 1, 1),
      aniosExperienciaSeguridad: 3,
      sueldoMensualAdministrativo: sueldoMensualAdministrativo,
    );
    return (resultado as CrearEmpleadoExitoso).empleado;
  }

  /// Genera y cierra una Nómina primera-quincena-enero-2026 con un solo
  /// Empleado administrativo — atajo compartido por casi todos los
  /// escenarios de esta suite, que empiezan siempre en `cerrada`.
  Future<({NominaData nomina, NominaEmpleadoData renglon})> nominaCerradaDePrueba({int sueldoMensualAdministrativo = 1500000}) async {
    await crearEmpleadoDePrueba(sueldoMensualAdministrativo: sueldoMensualAdministrativo);
    final generado = (await generarNomina.ejecutar(anio: 2026, mes: 1, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
    await cerrarNomina.ejecutar(nominaId: generado.nomina.id);
    final nomina = (await nominaRepo.obtenerPorId(generado.nomina.id))!;
    final renglon = (await nominaRepo.listarEmpleados(nomina.id)).single;
    return (nomina: nomina, renglon: renglon);
  }

  group('Integridad financiera: de dónde salió el dinero', () {
    // Un pago de Nómina mueve dinero real. Sin cuenta, el Egreso nace
    // sin origen y NINGÚN saldo baja: el sistema afirmaría que a los
    // empleados se les pagó con dinero que no salió de ningún lado.
    // Ése fue el hueco real que dejó PAGN-000005 / EGR-000071.
    test('sin cuenta financiera se rechaza, y no queda NADA a medias', () async {
      final ctx = await nominaCerradaDePrueba();
      final egresosAntes = (await db.select(db.egreso).get()).length;

      final resultado = await registrarPagoNomina.ejecutar(
        nominaId: ctx.nomina.id,
        fechaPago: DateTime(2026, 1, 20),
        formaPago: 'transferencia',
        // El texto administrativo NO sustituye a la cuenta estructural.
        cuentaBancariaOrigen: 'BBVA 1234567890',
        aplicaciones: [(nominaEmpleadoId: ctx.renglon.id, monto: ctx.renglon.totalAPagar)],
      );

      expect(resultado, isA<RegistrarPagoNominaCuentaFinancieraRequerida>());
      expect(await db.select(db.pagoNomina).get(), isEmpty, reason: '0 PagoNomina nuevos');
      expect((await db.select(db.egreso).get()).length, egresosAntes, reason: '0 Egresos nuevos');
      expect(await db.select(db.aplicacionPagoNomina).get(), isEmpty);
      final renglon = (await nominaRepo.listarEmpleados(ctx.nomina.id)).single;
      expect(renglon.estatusPago, isNot('pagado'), reason: 'ningún empleado quedó marcado como pagado');
    });

    test('una cuenta inexistente o desactivada también se rechaza', () async {
      final ctx = await nominaCerradaDePrueba();

      expect(
        await registrarPagoNomina.ejecutar(
          nominaId: ctx.nomina.id,
          fechaPago: DateTime(2026, 1, 20),
          formaPago: 'transferencia',
          cuentaFinancieraId: 'no-existe',
          aplicaciones: [(nominaEmpleadoId: ctx.renglon.id, monto: 100000)],
        ),
        isA<RegistrarPagoNominaCuentaFinancieraInvalida>(),
      );

      final archivada = await db.into(db.cuentaFinanciera).insertReturning(
            CuentaFinancieraCompanion.insert(
              codigo: 'CF-VIEJA',
              nombre: 'Cuenta dada de baja',
              tipo: 'banco',
              saldoInicial: 0,
              fechaSaldoInicial: DateTime(2020, 1, 1),
              cicloVidaRegistro: const Value('archivado'),
            ),
          );
      expect(
        await registrarPagoNomina.ejecutar(
          nominaId: ctx.nomina.id,
          fechaPago: DateTime(2026, 1, 20),
          formaPago: 'transferencia',
          cuentaFinancieraId: archivada.id,
          aplicaciones: [(nominaEmpleadoId: ctx.renglon.id, monto: 100000)],
        ),
        isA<RegistrarPagoNominaCuentaFinancieraInvalida>(),
      );
      expect(await db.select(db.pagoNomina).get(), isEmpty);
    });

    test('con cuenta válida el saldo baja exactamente el monto pagado, una sola vez', () async {
      final ctx = await nominaCerradaDePrueba();
      final cuentas = CuentaFinancieraRepositoryImpl(db);
      final bbva = await db.into(db.cuentaFinanciera).insertReturning(
            CuentaFinancieraCompanion.insert(
              codigo: 'CF-BBVA',
              nombre: 'BBVA Empresarial',
              tipo: 'banco',
              saldoInicial: 5000000,
              fechaSaldoInicial: DateTime(2026, 1, 1),
            ),
          );

      // Parcial primero: la cuenta pertenece al MOVIMIENTO, no a la
      // Nómina ni al empleado.
      await registrarPagoNomina.ejecutar(
        nominaId: ctx.nomina.id,
        fechaPago: DateTime(2026, 1, 20),
        formaPago: 'transferencia',
        cuentaFinancieraId: bbva.id,
        aplicaciones: [(nominaEmpleadoId: ctx.renglon.id, monto: 200000)],
      );
      expect(await cuentas.calcularSaldo(bbva.id), 5000000 - 200000);
      expect(await pagoNominaRepo.saldoPendientePago(ctx.renglon.id), ctx.renglon.totalAPagar - 200000);

      // Y el resto desde OTRA cuenta: cada lote lleva la suya.
      final banorte = await db.into(db.cuentaFinanciera).insertReturning(
            CuentaFinancieraCompanion.insert(
              codigo: 'CF-BANORTE',
              nombre: 'Banorte',
              tipo: 'banco',
              saldoInicial: 3000000,
              fechaSaldoInicial: DateTime(2026, 1, 1),
            ),
          );
      final resto = ctx.renglon.totalAPagar - 200000;
      await registrarPagoNomina.ejecutar(
        nominaId: ctx.nomina.id,
        fechaPago: DateTime(2026, 1, 25),
        formaPago: 'transferencia',
        cuentaFinancieraId: banorte.id,
        aplicaciones: [(nominaEmpleadoId: ctx.renglon.id, monto: resto)],
      );

      expect(await cuentas.calcularSaldo(bbva.id), 5000000 - 200000, reason: 'BBVA no vuelve a moverse');
      expect(await cuentas.calcularSaldo(banorte.id), 3000000 - resto);
      expect(await db.select(db.egreso).get(), hasLength(2), reason: 'un Egreso por lote, nunca por empleado');
    });

    test('cancelar el pago devuelve el dinero a la cuenta, sin segundo gasto', () async {
      final ctx = await nominaCerradaDePrueba();
      final cuentas = CuentaFinancieraRepositoryImpl(db);
      final bbva = await db.into(db.cuentaFinanciera).insertReturning(
            CuentaFinancieraCompanion.insert(
              codigo: 'CF-BBVA',
              nombre: 'BBVA Empresarial',
              tipo: 'banco',
              saldoInicial: 5000000,
              fechaSaldoInicial: DateTime(2026, 1, 1),
            ),
          );
      final pago = (await registrarPagoNomina.ejecutar(
        nominaId: ctx.nomina.id,
        fechaPago: DateTime(2026, 1, 20),
        formaPago: 'transferencia',
        cuentaFinancieraId: bbva.id,
        aplicaciones: [(nominaEmpleadoId: ctx.renglon.id, monto: ctx.renglon.totalAPagar)],
      )) as RegistrarPagoNominaExitoso;
      expect(await cuentas.calcularSaldo(bbva.id), 5000000 - ctx.renglon.totalAPagar);

      await cancelarPagoNomina.ejecutar(pagoNominaId: pago.pagoNomina.id, motivo: 'Error de captura');

      expect(await cuentas.calcularSaldo(bbva.id), 5000000, reason: 'el importe deja de afectar la cuenta');
      expect(await db.select(db.egreso).get(), hasLength(1), reason: 'no se crea un segundo gasto');
      final renglon = (await nominaRepo.listarEmpleados(ctx.nomina.id)).single;
      expect(renglon.estatusPago, isNot('pagado'));
    });

    test('un PagoNomina legacy sin cuenta sigue siendo legible', () async {
      // Lo que quedó en la base real: el pago y su Egreso existen, y no
      // se tocan. La obligatoriedad rige para lo NUEVO.
      final ctx = await nominaCerradaDePrueba();
      final egreso = await egresoRepo.crear(
        folioEgreso: 'EGR-LEGACY',
        monto: 1175000,
        fecha: DateTime(2026, 9, 20),
        formaPago: 'transferencia',
        concepto: 'Pago de Nómina legacy',
      );
      final legacy = await db.into(db.pagoNomina).insertReturning(
            PagoNominaCompanion.insert(
              folioPagoNomina: 'PAGN-LEGACY',
              nominaId: ctx.nomina.id,
              egresoId: Value(egreso.id),
              montoTotal: 1175000,
              fechaPago: DateTime(2026, 9, 20),
              formaPago: 'transferencia',
            ),
          );

      final leido = await pagoNominaRepo.obtenerPorId(legacy.id);
      expect(leido, isNotNull);
      expect(leido!.montoTotal, 1175000);
      expect((await egresoRepo.obtenerPorId(egreso.id))!.cuentaFinancieraId, isNull,
          reason: 'se conserva tal cual, sin inventarle una cuenta');
    });
  });

  group('RegistrarPagoNominaUseCase', () {
    test('registra un pago que cubre por completo un renglón: genera el Egreso automático y marca el renglón pagado', () async {
      final ctx = await nominaCerradaDePrueba();

      final resultado = await registrarPagoNomina.ejecutar(
        nominaId: ctx.nomina.id,
        fechaPago: DateTime(2026, 1, 20),
        formaPago: 'transferencia',
        cuentaFinancieraId: await _cuentaDePrueba(db),
        aplicaciones: [(nominaEmpleadoId: ctx.renglon.id, monto: ctx.renglon.totalAPagar)],
      );

      expect(resultado, isA<RegistrarPagoNominaExitoso>());
      final pagoNomina = (resultado as RegistrarPagoNominaExitoso).pagoNomina;
      expect(pagoNomina.montoTotal, ctx.renglon.totalAPagar);
      expect(pagoNomina.egresoId, isNotNull);

      final egreso = await egresoRepo.obtenerPorId(pagoNomina.egresoId!);
      expect(egreso, isNotNull);
      expect(egreso!.monto, ctx.renglon.totalAPagar);

      final renglonActualizado = (await nominaRepo.listarEmpleados(ctx.nomina.id)).single;
      expect(renglonActualizado.estatusPago, 'pagado');

      final nominaActualizada = (await nominaRepo.obtenerPorId(ctx.nomina.id))!;
      expect(nominaActualizada.estatus, 'pagada', reason: 'el único renglón ya quedó pagado');
    });

    test('un lote de pago puede cubrir varios renglones a la vez', () async {
      final empleado1 = await crearEmpleadoDePrueba(sueldoMensualAdministrativo: 1500000);
      final empleado2 = await crearEmpleadoDePrueba(sueldoMensualAdministrativo: 2000000);
      final generado = (await generarNomina.ejecutar(anio: 2026, mes: 1, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
      await cerrarNomina.ejecutar(nominaId: generado.nomina.id);
      final renglones = await nominaRepo.listarEmpleados(generado.nomina.id);
      expect(renglones, hasLength(2));
      final r1 = renglones.firstWhere((r) => r.empleadoId == empleado1.id);
      final r2 = renglones.firstWhere((r) => r.empleadoId == empleado2.id);

      final resultado = await registrarPagoNomina.ejecutar(
        nominaId: generado.nomina.id,
        fechaPago: DateTime(2026, 1, 20),
        formaPago: 'transferencia',
        cuentaFinancieraId: await _cuentaDePrueba(db),
        aplicaciones: [
          (nominaEmpleadoId: r1.id, monto: r1.totalAPagar),
          (nominaEmpleadoId: r2.id, monto: r2.totalAPagar),
        ],
      );

      expect(resultado, isA<RegistrarPagoNominaExitoso>());
      final pagoNomina = (resultado as RegistrarPagoNominaExitoso).pagoNomina;
      expect(pagoNomina.montoTotal, r1.totalAPagar + r2.totalAPagar);

      final aplicaciones = await pagoNominaRepo.listarAplicacionesPorPagoNomina(pagoNomina.id);
      expect(aplicaciones, hasLength(2));

      final nominaActualizada = (await nominaRepo.obtenerPorId(generado.nomina.id))!;
      expect(nominaActualizada.estatus, 'pagada');
    });

    test('un pago parcial dejа el renglón en parcial; un segundo pago que completa el saldo lo deja pagado', () async {
      final ctx = await nominaCerradaDePrueba();
      final mitad = ctx.renglon.totalAPagar ~/ 2;

      final primerPago = await registrarPagoNomina.ejecutar(
        nominaId: ctx.nomina.id,
        fechaPago: DateTime(2026, 1, 20),
        formaPago: 'efectivo',
        cuentaFinancieraId: await _cuentaDePrueba(db),
        aplicaciones: [(nominaEmpleadoId: ctx.renglon.id, monto: mitad)],
      );
      expect(primerPago, isA<RegistrarPagoNominaExitoso>());

      var renglon = (await nominaRepo.listarEmpleados(ctx.nomina.id)).single;
      expect(renglon.estatusPago, 'parcial');
      var nomina = (await nominaRepo.obtenerPorId(ctx.nomina.id))!;
      expect(nomina.estatus, 'cerrada', reason: 'todavía queda saldo pendiente, nunca debe marcarse pagada antes de tiempo');

      final saldoRestante = await pagoNominaRepo.saldoPendientePago(ctx.renglon.id);
      expect(saldoRestante, ctx.renglon.totalAPagar - mitad);

      final segundoPago = await registrarPagoNomina.ejecutar(
        nominaId: ctx.nomina.id,
        fechaPago: DateTime(2026, 1, 25),
        formaPago: 'efectivo',
        cuentaFinancieraId: await _cuentaDePrueba(db),
        aplicaciones: [(nominaEmpleadoId: ctx.renglon.id, monto: saldoRestante)],
      );
      expect(segundoPago, isA<RegistrarPagoNominaExitoso>());

      renglon = (await nominaRepo.listarEmpleados(ctx.nomina.id)).single;
      expect(renglon.estatusPago, 'pagado');
      nomina = (await nominaRepo.obtenerPorId(ctx.nomina.id))!;
      expect(nomina.estatus, 'pagada');
    });

    test('rechaza un monto que excede el saldo pendiente del renglón (nunca se sobrepaga)', () async {
      final ctx = await nominaCerradaDePrueba();

      final resultado = await registrarPagoNomina.ejecutar(
        nominaId: ctx.nomina.id,
        fechaPago: DateTime(2026, 1, 20),
        formaPago: 'transferencia',
        cuentaFinancieraId: await _cuentaDePrueba(db),
        aplicaciones: [(nominaEmpleadoId: ctx.renglon.id, monto: ctx.renglon.totalAPagar + 1)],
      );

      expect(resultado, isA<RegistrarPagoNominaSobrepago>());
      expect((resultado as RegistrarPagoNominaSobrepago).saldoDisponible, ctx.renglon.totalAPagar);
    });

    test('rechaza registrar un pago sobre una Nómina en Borrador', () async {
      await crearEmpleadoDePrueba(sueldoMensualAdministrativo: 1500000);
      final generado = (await generarNomina.ejecutar(anio: 2026, mes: 1, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
      final renglon = (await nominaRepo.listarEmpleados(generado.nomina.id)).single;

      final resultado = await registrarPagoNomina.ejecutar(
        nominaId: generado.nomina.id,
        fechaPago: DateTime(2026, 1, 20),
        formaPago: 'transferencia',
        cuentaFinancieraId: await _cuentaDePrueba(db),
        aplicaciones: [(nominaEmpleadoId: renglon.id, monto: renglon.totalAPagar)],
      );

      expect(resultado, isA<RegistrarPagoNominaNominaNoCerrada>());
    });

    test('rechaza un renglón que no pertenece a la Nómina indicada', () async {
      final ctxA = await nominaCerradaDePrueba();
      final empleadoB = await crearEmpleadoDePrueba(sueldoMensualAdministrativo: 1500000);
      final generadoB = (await generarNomina.ejecutar(anio: 2026, mes: 2, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
      await cerrarNomina.ejecutar(nominaId: generadoB.nomina.id);
      final renglonB =
          (await nominaRepo.listarEmpleados(generadoB.nomina.id)).firstWhere((r) => r.empleadoId == empleadoB.id);

      final resultado = await registrarPagoNomina.ejecutar(
        nominaId: ctxA.nomina.id,
        fechaPago: DateTime(2026, 1, 20),
        formaPago: 'transferencia',
        cuentaFinancieraId: await _cuentaDePrueba(db),
        aplicaciones: [(nominaEmpleadoId: renglonB.id, monto: renglonB.totalAPagar)],
      );

      expect(resultado, isA<RegistrarPagoNominaRenglonNoPerteneceANomina>());
    });

    test('la distribución Fiscal/No fiscal de un renglón nunca genera un segundo Egreso', () async {
      final ctx = await nominaCerradaDePrueba();
      // Distribución Fiscal/No fiscal ya poblada en ambos lados — sigue
      // siendo un único renglón, un único total a pagar.
      await nominaRepo.actualizarRenglon(
        nominaEmpleadoId: ctx.renglon.id,
        prestamo: ctx.renglon.prestamo,
        tiempoExtra: ctx.renglon.tiempoExtra,
        bono: ctx.renglon.bono,
        bonoModificadoManualmente: ctx.renglon.bonoModificadoManualmente,
        faltas: ctx.renglon.faltas,
        otrosDescuentos: ctx.renglon.otrosDescuentos,
        observaciones: ctx.renglon.observaciones,
        distribucionManual: (
          montoFiscal: ctx.renglon.totalAPagar ~/ 2,
          montoNoFiscal: ctx.renglon.totalAPagar - ctx.renglon.totalAPagar ~/ 2,
        ),
        tipoEvento: 'movimientoModificado',
      );

      final resultado = await registrarPagoNomina.ejecutar(
        nominaId: ctx.nomina.id,
        fechaPago: DateTime(2026, 1, 20),
        formaPago: 'transferencia',
        cuentaFinancieraId: await _cuentaDePrueba(db),
        aplicaciones: [(nominaEmpleadoId: ctx.renglon.id, monto: ctx.renglon.totalAPagar)],
      );

      final pagoNomina = (resultado as RegistrarPagoNominaExitoso).pagoNomina;
      final egresos = await egresoRepo.listar();
      expect(egresos, hasLength(1), reason: 'Fiscal/No fiscal nunca duplica el Egreso — sigue siendo un solo lote de pago');
      expect(egresos.single.id, pagoNomina.egresoId);
    });
  });

  group('CancelarPagoNominaUseCase', () {
    test('cancela el PagoNomina, revierte estatusPago del renglón y cancela el Egreso ligado', () async {
      final ctx = await nominaCerradaDePrueba();
      final registrado = (await registrarPagoNomina.ejecutar(
        nominaId: ctx.nomina.id,
        fechaPago: DateTime(2026, 1, 20),
        formaPago: 'transferencia',
        cuentaFinancieraId: await _cuentaDePrueba(db),
        aplicaciones: [(nominaEmpleadoId: ctx.renglon.id, monto: ctx.renglon.totalAPagar)],
      )) as RegistrarPagoNominaExitoso;

      final resultado = await cancelarPagoNomina.ejecutar(pagoNominaId: registrado.pagoNomina.id, motivo: 'Error de captura');
      expect(resultado, isA<CancelarPagoNominaExitoso>());

      final renglon = (await nominaRepo.listarEmpleados(ctx.nomina.id)).single;
      expect(renglon.estatusPago, 'pendiente');

      final nomina = (await nominaRepo.obtenerPorId(ctx.nomina.id))!;
      expect(nomina.estatus, 'cerrada', reason: 'una Nómina cancelada de vuelta a pendiente nunca debe quedar marcada pagada');

      final egreso = await egresoRepo.obtenerPorId(registrado.pagoNomina.egresoId!);
      expect(egreso!.estatus, 'cancelado');
    });

    test('rechaza cancelar un PagoNomina ya cancelado', () async {
      final ctx = await nominaCerradaDePrueba();
      final registrado = (await registrarPagoNomina.ejecutar(
        nominaId: ctx.nomina.id,
        fechaPago: DateTime(2026, 1, 20),
        formaPago: 'transferencia',
        cuentaFinancieraId: await _cuentaDePrueba(db),
        aplicaciones: [(nominaEmpleadoId: ctx.renglon.id, monto: ctx.renglon.totalAPagar)],
      )) as RegistrarPagoNominaExitoso;
      await cancelarPagoNomina.ejecutar(pagoNominaId: registrado.pagoNomina.id, motivo: 'primer motivo');

      final resultado = await cancelarPagoNomina.ejecutar(pagoNominaId: registrado.pagoNomina.id, motivo: 'segundo motivo');
      expect(resultado, isA<CancelarPagoNominaYaCancelado>());
    });
  });

  group('CorregirPagoNominaUseCase', () {
    test('corrige metadatos administrativos sin tocar el monto', () async {
      final ctx = await nominaCerradaDePrueba();
      final registrado = (await registrarPagoNomina.ejecutar(
        nominaId: ctx.nomina.id,
        fechaPago: DateTime(2026, 1, 20),
        formaPago: 'transferencia',
        cuentaFinancieraId: await _cuentaDePrueba(db),
        aplicaciones: [(nominaEmpleadoId: ctx.renglon.id, monto: ctx.renglon.totalAPagar)],
      )) as RegistrarPagoNominaExitoso;

      final resultado = await corregirPagoNomina.ejecutar(
        pagoNominaId: registrado.pagoNomina.id,
        referencia: 'REF-CORREGIDA',
        motivo: 'Referencia capturada incorrectamente',
      );

      expect(resultado, isA<CorregirPagoNominaExitoso>());
      final actualizado = (resultado as CorregirPagoNominaExitoso).pagoNomina;
      expect(actualizado.referencia, 'REF-CORREGIDA');
      expect(actualizado.montoTotal, registrado.pagoNomina.montoTotal, reason: 'CorregirPagoNominaUseCase nunca toca montos');
    });
  });

  group('AdjuntarComprobantePagoNominaUseCase', () {
    test('adjunta un comprobante y queda listado', () async {
      final ctx = await nominaCerradaDePrueba();
      final registrado = (await registrarPagoNomina.ejecutar(
        nominaId: ctx.nomina.id,
        fechaPago: DateTime(2026, 1, 20),
        formaPago: 'transferencia',
        cuentaFinancieraId: await _cuentaDePrueba(db),
        aplicaciones: [(nominaEmpleadoId: ctx.renglon.id, monto: ctx.renglon.totalAPagar)],
      )) as RegistrarPagoNominaExitoso;

      final sourceFilePath = '${tempDir.path}/comprobante.pdf';
      File(sourceFilePath).writeAsStringSync('contenido de prueba');

      final resultado = await adjuntarComprobantePagoNomina.ejecutar(
        pagoNominaId: registrado.pagoNomina.id,
        sourceFilePath: sourceFilePath,
        originalFileName: 'comprobante.pdf',
        mimeType: 'application/pdf',
      );

      expect(resultado, isA<AdjuntarComprobantePagoNominaExitoso>());
    });
  });

  group('Política de saldo (v91) — Nómina', () {
    Future<String> cuentaCon(int saldo) async {
      final cuenta = await db.into(db.cuentaFinanciera).insertReturning(
            CuentaFinancieraCompanion.insert(
              codigo: 'CTA-ACOTADA',
              nombre: 'Cuenta acotada',
              tipo: 'banco',
              saldoInicial: saldo,
              fechaSaldoInicial: DateTime(2026, 1, 1),
            ),
          );
      return cuenta.id;
    }

    test('A) con saldo suficiente: el pago se registra', () async {
      final ctx = await nominaCerradaDePrueba();
      final cuenta = await cuentaCon(ctx.renglon.totalAPagar);
      final resultado = await registrarPagoNomina.ejecutar(
        nominaId: ctx.nomina.id,
        fechaPago: DateTime(2026, 1, 20),
        formaPago: 'transferencia',
        cuentaFinancieraId: cuenta,
        aplicaciones: [(nominaEmpleadoId: ctx.renglon.id, monto: ctx.renglon.totalAPagar)],
      );
      expect(resultado, isA<RegistrarPagoNominaExitoso>());
    });

    test('B y C) sin saldo: resultado tipado y CERO persistencia parcial', () async {
      final ctx = await nominaCerradaDePrueba();
      final cuenta = await cuentaCon(ctx.renglon.totalAPagar - 1);

      final resultado = await registrarPagoNomina.ejecutar(
        nominaId: ctx.nomina.id,
        fechaPago: DateTime(2026, 1, 20),
        formaPago: 'transferencia',
        cuentaFinancieraId: cuenta,
        aplicaciones: [(nominaEmpleadoId: ctx.renglon.id, monto: ctx.renglon.totalAPagar)],
      );

      expect(resultado, isA<RegistrarPagoNominaSaldoInsuficiente>());
      final detalle = (resultado as RegistrarPagoNominaSaldoInsuficiente).detalle;
      expect(detalle.disponible, ctx.renglon.totalAPagar - 1);
      expect(detalle.requerido, ctx.renglon.totalAPagar);
      expect(detalle.faltante, 1, reason: 'un centavo basta para rechazar');

      expect(await db.select(db.pagoNomina).get(), isEmpty, reason: 'ni el PagoNomina');
      expect(await db.select(db.egreso).get(), isEmpty, reason: 'ni el Egreso');
      expect(await db.select(db.egresoFuente).get(), isEmpty, reason: 'ni su fuente');
      expect(await db.select(db.aplicacionPagoNomina).get(), isEmpty, reason: 'ni una sola aplicación');
    });
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
          // Fondeada de sobra: desde la v91 una salida sin saldo se
          // rechaza, y estas pruebas no van de eso.
          saldoInicial: 100000000,
          fechaSaldoInicial: DateTime(2020, 1, 1),
        ),
      );
  return cuenta.id;

}
