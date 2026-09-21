// Etapa 15 — PDF de control de dispersión de Nómina (hoja operativa
// para ejecutar/verificar transferencias bancarias). Cubre: solo
// disponible Cerrada/Pagada (nunca en Borrador); usa EXCLUSIVAMENTE el
// snapshot de `NominaEmpleado` (banco/cuenta/CLABE), nunca el
// expediente bancario en vivo del Empleado; advertencia "REQUIERE
// VERIFICACIÓN" cuando faltan datos, sin bloquear la generación;
// totales exactos; orden Banco→Nombre; multipágina.

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/features/finanzas/data/repositories/cuenta_financiera_repository_impl.dart';
import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/codigos/generar_numero_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/pdf/nomina_dispersion_pdf_renderer.dart';
import 'package:riseg_one/features/descuentos_personal/data/repositories/descuento_programado_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/repositories/nomina_repository_impl.dart';
import 'package:riseg_one/features/tiempos_extra/data/repositories/tiempo_extra_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/repositories/pago_nomina_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/tables/nomina_table.dart';
import 'package:riseg_one/features/nomina/domain/usecases/cerrar_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/evaluar_renglones_requieren_revision_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/generar_nomina_dispersion_pdf_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/generar_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/nomina_dispersion_pdf_data.dart';
import 'package:riseg_one/features/nomina/domain/usecases/registrar_pago_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/resolver_sueldo_empleado_nomina.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/puesto_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_comercial_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart';
import 'package:riseg_one/features/personal/domain/usecases/corregir_empleado_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/crear_empleado_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/empleado_validator.dart';

void main() {
  late AppDatabase db;
  late Directory tempDir;
  late EmpleadoRepositoryImpl empleadoRepo;
  late CrearEmpleadoUseCase crearEmpleado;
  late CorregirEmpleadoUseCase corregirEmpleado;
  late NominaRepositoryImpl nominaRepo;
  late GenerarNominaUseCase generarNomina;
  late CerrarNominaUseCase cerrarNomina;
  late RegistrarPagoNominaUseCase registrarPagoNomina;
  late GenerarNominaDispersionPdfUseCase generarDispersionPdf;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    tempDir = Directory.systemTemp.createTempSync('riseg_dispersion_pdf_test_');
    final asignacionServicioRepo = AsignacionServicioRepositoryImpl(db);
    empleadoRepo = EmpleadoRepositoryImpl(db, asignacionServicioRepo);
    final servicioRepo = ServicioRepositoryImpl(db, asignacionServicioRepo);
    final catalogoRepo = CatalogoRepositoryImpl(db);
    final puestoRepo = PuestoRepositoryImpl(db);
    final codigoSecuencia = CodigoSecuenciaService(db);
    final generarCodigo = GenerarCodigoUseCase(codigoSecuencia);
    final generarNumero = GenerarNumeroUseCase(codigoSecuencia);
    const empleadoValidator = EmpleadoValidator();

    crearEmpleado = CrearEmpleadoUseCase(empleadoRepo, generarNumero, empleadoValidator, servicioRepo, ServicioComercialRepositoryImpl(db));
    corregirEmpleado = CorregirEmpleadoUseCase(empleadoRepo, empleadoValidator, AsignacionServicioRepositoryImpl(db));

    nominaRepo = NominaRepositoryImpl(db, AsignacionRepositoryImpl(db), DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db)), TiempoExtraRepositoryImpl(db, EgresoRepositoryImpl(db), DeudaRepositoryImpl(db, EgresoRepositoryImpl(db)), CodigoSecuenciaService(db), EmpleadoRepositoryImpl(db, AsignacionServicioRepositoryImpl(db)), ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db))), PagoNominaRepositoryImpl(db, EgresoRepositoryImpl(db), DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db))));
    final resolverSueldo = ResolverSueldoEmpleadoNomina(empleadoRepo, asignacionServicioRepo, servicioRepo, catalogoRepo);
    generarNomina = GenerarNominaUseCase(nominaRepo, empleadoRepo, puestoRepo, catalogoRepo, resolverSueldo, generarCodigo);
    cerrarNomina = CerrarNominaUseCase(nominaRepo, EvaluarRenglonesRequierenRevisionUseCase(nominaRepo, empleadoRepo, resolverSueldo));

    final pagoNominaRepo = PagoNominaRepositoryImpl(db, EgresoRepositoryImpl(db), DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db)));
    registrarPagoNomina = RegistrarPagoNominaUseCase(pagoNominaRepo, nominaRepo, generarCodigo, CuentaFinancieraRepositoryImpl(db));

    final attachmentStorage = AttachmentStorage(tempDir.path);
    generarDispersionPdf = GenerarNominaDispersionPdfUseCase(
      nominaRepo,
      attachmentStorage,
      '${tempDir.path}/nomina_dispersion',
      NominaDispersionPdfRenderer(),
    );
  });

  tearDown(() {
    db.close();
    tempDir.deleteSync(recursive: true);
  });

  var empleadoContador = 0;

  Future<EmpleadoData> crearEmpleadoDePrueba({
    required int sueldoMensualAdministrativo,
    String? nombres,
    String? bancoId,
    String? numeroCuentaTarjeta,
    String? clabe,
  }) async {
    empleadoContador++;
    final n = empleadoContador.toString().padLeft(2, '0');
    final resultado = await crearEmpleado.ejecutar(
      nombres: nombres ?? 'Empleado$n',
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
      bancoId: bancoId,
      numeroCuentaTarjeta: numeroCuentaTarjeta,
      clabe: clabe,
    );
    return (resultado as CrearEmpleadoExitoso).empleado;
  }

  Future<({NominaData nomina, List<NominaEmpleadoData> renglones})> generarYCerrar() async {
    final generado = (await generarNomina.ejecutar(anio: 2026, mes: 1, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
    await cerrarNomina.ejecutar(nominaId: generado.nomina.id);
    final nomina = (await nominaRepo.obtenerPorId(generado.nomina.id))!;
    final renglones = await nominaRepo.listarEmpleados(nomina.id);
    return (nomina: nomina, renglones: renglones);
  }

  test('Nómina cerrada permite generar el PDF de dispersión', () async {
    await crearEmpleadoDePrueba(
      sueldoMensualAdministrativo: 1500000,
      bancoId: SeedIds.bancoBbva,
      numeroCuentaTarjeta: '1234567890',
      clabe: '012345678901234567',
    );
    final ctx = await generarYCerrar();

    final resultado = await generarDispersionPdf.ejecutar(nominaId: ctx.nomina.id);

    expect(resultado, isA<GenerarNominaDispersionPdfExitoso>());
    final archivo = File((resultado as GenerarNominaDispersionPdfExitoso).rutaArchivo);
    expect(archivo.existsSync(), isTrue);
    final bytes = await archivo.readAsBytes();
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });

  test('Nómina pagada permite generar el PDF de dispersión', () async {
    final empleado = await crearEmpleadoDePrueba(
      sueldoMensualAdministrativo: 1500000,
      bancoId: SeedIds.bancoBbva,
      numeroCuentaTarjeta: '1234567890',
      clabe: '012345678901234567',
    );
    final ctx = await generarYCerrar();
    final renglon = ctx.renglones.singleWhere((r) => r.empleadoId == empleado.id);

    await registrarPagoNomina.ejecutar(
      nominaId: ctx.nomina.id,
      fechaPago: DateTime(2026, 1, 20),
      formaPago: 'transferencia',
      cuentaFinancieraId: await _cuentaDePrueba(db),
      aplicaciones: [(nominaEmpleadoId: renglon.id, monto: renglon.totalAPagar)],
    );
    final nominaPagada = (await nominaRepo.obtenerPorId(ctx.nomina.id))!;
    expect(nominaPagada.estatus, 'pagada', reason: 'precondición del escenario');

    final resultado = await generarDispersionPdf.ejecutar(nominaId: nominaPagada.id);
    expect(resultado, isA<GenerarNominaDispersionPdfExitoso>());
  });

  test('Nómina en Borrador NO ofrece el PDF de dispersión como documento definitivo', () async {
    await crearEmpleadoDePrueba(sueldoMensualAdministrativo: 1500000);
    final generado = (await generarNomina.ejecutar(anio: 2026, mes: 1, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;

    final resultado = await generarDispersionPdf.ejecutar(nominaId: generado.nomina.id);

    expect(resultado, isA<GenerarNominaDispersionPdfNominaEnBorrador>());
  });

  group('construirNominaDispersionPdfData — snapshot y totales', () {
    test('todos los empleados aparecen exactamente una vez, con nombre/banco/cuenta/CLABE/Fiscal/No fiscal/total correctos', () async {
      await crearEmpleadoDePrueba(
        sueldoMensualAdministrativo: 1500000,
        nombres: 'Zaira',
        bancoId: SeedIds.bancoSantander,
        numeroCuentaTarjeta: '9998887776',
        clabe: '014180000000000019',
      );
      await crearEmpleadoDePrueba(
        sueldoMensualAdministrativo: 2000000,
        nombres: 'Andres',
        bancoId: SeedIds.bancoBbva,
        numeroCuentaTarjeta: '1112223334',
        clabe: '012180000000000018',
      );
      final ctx = await generarYCerrar();
      expect(ctx.renglones, hasLength(2));

      final data = construirNominaDispersionPdfData(nomina: ctx.nomina, renglones: ctx.renglones, fechaGeneracion: DateTime(2026, 1, 20));

      expect(data.renglones, hasLength(2), reason: 'cada Empleado aparece exactamente una vez, sin duplicar ni omitir');
      final nombres = data.renglones.map((r) => r.nombreCompleto).toSet();
      expect(nombres, {for (final r in ctx.renglones) r.nombreCompleto});

      for (final renglonOriginal in ctx.renglones) {
        final fila = data.renglones.singleWhere((r) => r.nombreCompleto == renglonOriginal.nombreCompleto);
        expect(fila.bancoNombre, renglonOriginal.bancoNombre);
        expect(fila.numeroCuentaTarjeta, renglonOriginal.numeroCuentaTarjeta);
        expect(fila.clabe, renglonOriginal.clabe);
        expect(fila.montoFiscal, renglonOriginal.montoFiscal);
        expect(fila.montoNoFiscal, renglonOriginal.montoNoFiscal);
        expect(fila.totalAPagar, renglonOriginal.totalAPagar);
      }
    });

    test('orden: Banco, luego Nombre — Banorte antes que Santander, y dentro del mismo banco por nombre', () async {
      await crearEmpleadoDePrueba(sueldoMensualAdministrativo: 1500000, nombres: 'Zaira', bancoId: SeedIds.bancoSantander, numeroCuentaTarjeta: '1');
      await crearEmpleadoDePrueba(sueldoMensualAdministrativo: 1500000, nombres: 'Beto', bancoId: SeedIds.bancoBanorte, numeroCuentaTarjeta: '2');
      await crearEmpleadoDePrueba(sueldoMensualAdministrativo: 1500000, nombres: 'Ana', bancoId: SeedIds.bancoBanorte, numeroCuentaTarjeta: '3');
      final ctx = await generarYCerrar();

      final data = construirNominaDispersionPdfData(nomina: ctx.nomina, renglones: ctx.renglones, fechaGeneracion: DateTime(2026, 1, 20));

      expect(data.renglones.map((r) => r.nombreCompleto).toList(), [
        contains('Ana'),
        contains('Beto'),
        contains('Zaira'),
      ], reason: 'Banorte (Ana, Beto) antes que Santander (Zaira); dentro de Banorte, Ana antes que Beto por nombre');
    });

    test('totales generales coinciden exactamente con la suma de los renglones', () async {
      await crearEmpleadoDePrueba(sueldoMensualAdministrativo: 1500000, bancoId: SeedIds.bancoBbva, numeroCuentaTarjeta: '1');
      await crearEmpleadoDePrueba(sueldoMensualAdministrativo: 2200000, bancoId: SeedIds.bancoBbva, numeroCuentaTarjeta: '2');
      final ctx = await generarYCerrar();

      final data = construirNominaDispersionPdfData(nomina: ctx.nomina, renglones: ctx.renglones, fechaGeneracion: DateTime(2026, 1, 20));

      expect(data.totalEmpleados, ctx.renglones.length);
      expect(data.totalFiscal, ctx.renglones.fold<int>(0, (s, r) => s + r.montoFiscal));
      expect(data.totalNoFiscal, ctx.renglones.fold<int>(0, (s, r) => s + r.montoNoFiscal));
      expect(data.totalGeneral, ctx.renglones.fold<int>(0, (s, r) => s + r.totalAPagar));
    });

    test('Empleado con datos bancarios incompletos (sin banco) aparece marcado "requiere verificación"', () async {
      await crearEmpleadoDePrueba(sueldoMensualAdministrativo: 1500000); // sin banco/cuenta/CLABE
      final ctx = await generarYCerrar();

      final data = construirNominaDispersionPdfData(nomina: ctx.nomina, renglones: ctx.renglones, fechaGeneracion: DateTime(2026, 1, 20));

      expect(data.renglones.single.requiereVerificacion, isTrue);
      expect(data.totalRequierenVerificacion, 1);
    });

    test('Empleado con banco + cuenta pero sin CLABE NO requiere verificación (basta un identificador de destino)', () async {
      await crearEmpleadoDePrueba(sueldoMensualAdministrativo: 1500000, bancoId: SeedIds.bancoBbva, numeroCuentaTarjeta: '1234567890');
      final ctx = await generarYCerrar();

      final data = construirNominaDispersionPdfData(nomina: ctx.nomina, renglones: ctx.renglones, fechaGeneracion: DateTime(2026, 1, 20));

      expect(data.renglones.single.requiereVerificacion, isFalse);
    });

    test('la generación del PDF sigue permitida aunque haya renglones con advertencia (nunca bloquea)', () async {
      await crearEmpleadoDePrueba(sueldoMensualAdministrativo: 1500000); // sin datos bancarios
      final ctx = await generarYCerrar();

      final resultado = await generarDispersionPdf.ejecutar(nominaId: ctx.nomina.id);

      expect(resultado, isA<GenerarNominaDispersionPdfExitoso>());
    });
  });

  test(
    'modificar después el expediente bancario del Empleado NO cambia el PDF de una Nómina ya cerrada — usa el snapshot, nunca el dato en vivo',
    () async {
      final empleado = await crearEmpleadoDePrueba(
        sueldoMensualAdministrativo: 1500000,
        bancoId: SeedIds.bancoBbva,
        numeroCuentaTarjeta: '1111111111',
        clabe: '012345678901234567',
      );
      final ctx = await generarYCerrar();
      final renglonOriginal = ctx.renglones.single;
      expect(renglonOriginal.bancoNombre, 'BBVA');
      expect(renglonOriginal.numeroCuentaTarjeta, '1111111111');

      // El Empleado corrige su cuenta DESPUÉS de que la Nómina ya está
      // cerrada.
      await corregirEmpleado.ejecutar(
        empleadoId: empleado.id,
        bancoId: SeedIds.bancoSantander,
        numeroCuentaTarjeta: '9999999999',
        clabe: '999999999999999999',
        motivo: 'Corrección de datos bancarios (prueba)',
      );

      // El renglón de la Nómina ya cerrada permanece exactamente igual
      // — nunca se re-consulta contra Personal.
      final renglonTrasCorreccion = (await nominaRepo.obtenerEmpleado(renglonOriginal.id))!;
      expect(renglonTrasCorreccion.bancoNombre, 'BBVA', reason: 'el snapshot histórico nunca cambia');
      expect(renglonTrasCorreccion.numeroCuentaTarjeta, '1111111111');
      expect(renglonTrasCorreccion.clabe, '012345678901234567');

      final data = construirNominaDispersionPdfData(
        nomina: ctx.nomina,
        renglones: [renglonTrasCorreccion],
        fechaGeneracion: DateTime(2026, 1, 25),
      );
      expect(data.renglones.single.bancoNombre, 'BBVA');
      expect(data.renglones.single.numeroCuentaTarjeta, '1111111111');
    },
  );

  test('PDF multipágina: genera correctamente con suficientes empleados para forzar más de una página', () async {
    for (var i = 0; i < 60; i++) {
      await crearEmpleadoDePrueba(
        sueldoMensualAdministrativo: 1500000,
        nombres: 'Empleado de prueba con nombre razonablemente largo numero $i',
        bancoId: i.isEven ? SeedIds.bancoBbva : SeedIds.bancoSantander,
        numeroCuentaTarjeta: '123456789$i',
        clabe: i.isEven ? null : '01234567890123456$i',
      );
    }
    final ctx = await generarYCerrar();
    expect(ctx.renglones, hasLength(60));

    final resultado = await generarDispersionPdf.ejecutar(nominaId: ctx.nomina.id);

    expect(resultado, isA<GenerarNominaDispersionPdfExitoso>());
    final archivo = File((resultado as GenerarNominaDispersionPdfExitoso).rutaArchivo);
    final bytes = await archivo.readAsBytes();
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    // `pw.MultiPage` + `TableHelper.fromTextArray` maneja la paginación
    // y repetición de encabezados automáticamente (mismo mecanismo que
    // `ReciboPagoPdfRenderer`); no hay en este proyecto una herramienta
    // de parseo de PDF para contar páginas o inspeccionar texto
    // renderizado (mismo límite documentado en Etapa 12D) — se verifica
    // que la generación con 60 renglones no lanza excepción y produce
    // un PDF sustancialmente más grande que el de un solo renglón.
    expect(bytes.length, greaterThan(3000));
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
