import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/codigos/generar_numero_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/egreso_repository.dart';
import 'package:riseg_one/features/nomina/data/repositories/nomina_repository_impl.dart';
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

    nominaRepo = NominaRepositoryImpl(db);
    final resolverSueldo = ResolverSueldoEmpleadoNomina(empleadoRepo, asignacionRepo, servicioRepo, catalogoRepo);
    generarNomina = GenerarNominaUseCase(nominaRepo, empleadoRepo, puestoRepo, catalogoRepo, resolverSueldo, generarCodigo);
    final evaluarRenglonesRequierenRevision = EvaluarRenglonesRequierenRevisionUseCase(nominaRepo, empleadoRepo, resolverSueldo);
    cerrarNomina = CerrarNominaUseCase(nominaRepo, evaluarRenglonesRequierenRevision);

    pagoNominaRepo = PagoNominaRepositoryImpl(db, egresoRepo);
    registrarPagoNomina = RegistrarPagoNominaUseCase(pagoNominaRepo, nominaRepo, generarCodigo);
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

  group('RegistrarPagoNominaUseCase', () {
    test('registra un pago que cubre por completo un renglón: genera el Egreso automático y marca el renglón pagado', () async {
      final ctx = await nominaCerradaDePrueba();

      final resultado = await registrarPagoNomina.ejecutar(
        nominaId: ctx.nomina.id,
        fechaPago: DateTime(2026, 1, 20),
        formaPago: 'transferencia',
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
        aplicaciones: [(nominaEmpleadoId: renglonB.id, monto: renglonB.totalAPagar)],
      );

      expect(resultado, isA<RegistrarPagoNominaRenglonNoPerteneceANomina>());
    });

    test('la distribución Fiscal/No fiscal de un renglón nunca genera un segundo Egreso', () async {
      final ctx = await nominaCerradaDePrueba();
      // Distribución Fiscal/No fiscal ya poblada en ambos lados — sigue
      // siendo un único renglón, un único total a pagar.
      await nominaRepo.actualizarDistribucion(
        nominaEmpleadoId: ctx.renglon.id,
        montoFiscal: ctx.renglon.totalAPagar ~/ 2,
        montoNoFiscal: ctx.renglon.totalAPagar - ctx.renglon.totalAPagar ~/ 2,
      );

      final resultado = await registrarPagoNomina.ejecutar(
        nominaId: ctx.nomina.id,
        fechaPago: DateTime(2026, 1, 20),
        formaPago: 'transferencia',
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
}
