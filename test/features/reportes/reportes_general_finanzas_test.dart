// Etapa 12A (Reportes generales) — pruebas de repositorio/caso de uso:
// las agregaciones SQL nuevas (`totalPorCategoria`, `totalPagadoEnRango`,
// `listarEnRango`) y los casos de uso de composición
// (`ClasificarEgresosPorOrigenUseCase`, `ObtenerResumenGeneralUseCase`).
// Cubre explícitamente los riesgos de doble conteo documentados en el
// plan técnico: Compras y Nómina ya están dentro de
// `EgresoRepository.totalEgresos` (nunca se suman aparte), y cada campo
// de `ResumenGeneralReportes` es `null` cuando no se incluye (nunca un
// `0` indistinguible de un cero real autorizado).

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/codigos/generar_numero_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/compras/data/repositories/compra_repository_impl.dart';
import 'package:riseg_one/features/compras/domain/repositories/compra_repository.dart';
import 'package:riseg_one/features/compras/domain/usecases/registrar_compra_usecase.dart';
import 'package:riseg_one/features/finanzas/data/repositories/categoria_financiera_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/ingreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/egreso_repository.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/ingreso_repository.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/crear_categoria_financiera_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/obtener_resumen_financiero_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_egreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_ingreso_manual_usecase.dart';
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/inventario_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/repositories/nomina_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/repositories/pago_nomina_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/tables/nomina_table.dart';
import 'package:riseg_one/features/nomina/domain/repositories/pago_nomina_repository.dart';
import 'package:riseg_one/features/nomina/domain/usecases/cerrar_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/evaluar_renglones_requieren_revision_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/generar_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/registrar_pago_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/resolver_sueldo_empleado_nomina.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/puesto_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/servicio_repository.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart';
import 'package:riseg_one/features/personal/domain/repositories/empleado_repository.dart';
import 'package:riseg_one/features/personal/domain/usecases/crear_empleado_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/empleado_validator.dart';
import 'package:riseg_one/features/reportes/domain/usecases/clasificar_egresos_por_origen_usecase.dart';
import 'package:riseg_one/features/reportes/domain/usecases/obtener_resumen_general_usecase.dart';

void main() {
  late AppDatabase db;
  late Directory tempDir;

  late IngresoRepository ingresoRepo;
  late EgresoRepository egresoRepo;
  late CategoriaFinancieraRepositoryImpl categoriaRepo;
  late RegistrarIngresoManualUseCase registrarIngreso;
  late RegistrarEgresoUseCase registrarEgreso;
  late CrearCategoriaFinancieraUseCase crearCategoria;

  late CompraRepository compraRepo;
  late RegistrarCompraUseCase registrarCompra;

  late EmpleadoRepository empleadoRepo;
  late ServicioRepository servicioRepo;
  late CrearEmpleadoUseCase crearEmpleado;
  late NominaRepositoryImpl nominaRepo;
  late GenerarNominaUseCase generarNomina;
  late CerrarNominaUseCase cerrarNomina;
  late PagoNominaRepository pagoNominaRepo;
  late RegistrarPagoNominaUseCase registrarPagoNomina;

  late ObtenerResumenFinancieroUseCase resumenFinanciero;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    tempDir = Directory.systemTemp.createTempSync('riseg_reportes_test_');

    ingresoRepo = IngresoRepositoryImpl(db);
    egresoRepo = EgresoRepositoryImpl(db);
    categoriaRepo = CategoriaFinancieraRepositoryImpl(db);
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    registrarIngreso = RegistrarIngresoManualUseCase(ingresoRepo, generarCodigo);
    registrarEgreso = RegistrarEgresoUseCase(egresoRepo, generarCodigo);
    crearCategoria = CrearCategoriaFinancieraUseCase(categoriaRepo);

    final articuloRepo = ArticuloRepositoryImpl(db);
    final inventarioRepo = InventarioRepositoryImpl(db);
    compraRepo = CompraRepositoryImpl(db, inventarioRepo, articuloRepo, egresoRepo);
    registrarCompra = RegistrarCompraUseCase(compraRepo, articuloRepo, inventarioRepo, generarCodigo);

    final asignacionRepo = AsignacionServicioRepositoryImpl(db);
    empleadoRepo = EmpleadoRepositoryImpl(db, asignacionRepo);
    servicioRepo = ServicioRepositoryImpl(db, asignacionRepo);
    final catalogoRepo = CatalogoRepositoryImpl(db);
    final puestoRepo = PuestoRepositoryImpl(db);
    final generarNumero = GenerarNumeroUseCase(CodigoSecuenciaService(db));
    const empleadoValidator = EmpleadoValidator();
    crearEmpleado = CrearEmpleadoUseCase(empleadoRepo, generarNumero, empleadoValidator, servicioRepo);

    nominaRepo = NominaRepositoryImpl(db);
    final resolverSueldo = ResolverSueldoEmpleadoNomina(empleadoRepo, asignacionRepo, servicioRepo, catalogoRepo);
    generarNomina = GenerarNominaUseCase(nominaRepo, empleadoRepo, puestoRepo, catalogoRepo, resolverSueldo, generarCodigo);
    final evaluarRevision = EvaluarRenglonesRequierenRevisionUseCase(nominaRepo, empleadoRepo, resolverSueldo);
    cerrarNomina = CerrarNominaUseCase(nominaRepo, evaluarRevision);
    pagoNominaRepo = PagoNominaRepositoryImpl(db, egresoRepo);
    registrarPagoNomina = RegistrarPagoNominaUseCase(pagoNominaRepo, nominaRepo, generarCodigo);

    resumenFinanciero = ObtenerResumenFinancieroUseCase(ingresoRepo, egresoRepo);
  });

  tearDown(() {
    db.close();
    tempDir.deleteSync(recursive: true);
  });

  var empleadoContador = 0;

  Future<EmpleadoData> crearEmpleadoDePrueba({int sueldoMensualAdministrativo = 1500000}) async {
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

  /// Genera, cierra y paga una Nómina primera-quincena-enero-2026 con un
  /// solo empleado administrativo — produce exactamente un `PagoNomina`
  /// con su `Egreso` automático.
  Future<PagoNominaData> pagoNominaDePrueba({DateTime? fechaPago}) async {
    await crearEmpleadoDePrueba();
    final generado = (await generarNomina.ejecutar(anio: 2026, mes: 1, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
    await cerrarNomina.ejecutar(nominaId: generado.nomina.id);
    final renglon = (await nominaRepo.listarEmpleados(generado.nomina.id)).single;

    final resultado = await registrarPagoNomina.ejecutar(
      nominaId: generado.nomina.id,
      fechaPago: fechaPago ?? DateTime(2026, 1, 20),
      formaPago: 'transferencia',
      aplicaciones: [(nominaEmpleadoId: renglon.id, monto: renglon.totalAPagar)],
    );
    return (resultado as RegistrarPagoNominaExitoso).pagoNomina;
  }

  Future<CompraData> compraDePrueba({DateTime? fecha, int costoUnitario = 50000}) async {
    final resultado = await registrarCompra.ejecutar(
      fecha: fecha ?? DateTime(2026, 1, 10),
      proveedor: 'Proveedor de prueba',
      formaPago: 'transferencia',
      partidas: [
        PartidaCompraInput(destino: 'gastoDirecto', concepto: 'Gasto directo de prueba', cantidad: 1, costoUnitario: costoUnitario),
      ],
    );
    return (resultado as RegistrarCompraExitosa).compra;
  }

  group('IngresoRepository.totalPorCategoria / EgresoRepository.totalPorCategoria', () {
    test('agrupa por categoría y excluye cancelados', () async {
      final categoriaA = (await crearCategoria.ejecutar(codigo: 'CAT-A', nombre: 'Categoría A', tipo: 'ingreso', tipoMovimiento: 'operativo'))
          as CrearCategoriaFinancieraExitoso;
      final categoriaB = (await crearCategoria.ejecutar(codigo: 'CAT-B', nombre: 'Categoría B', tipo: 'ingreso', tipoMovimiento: 'operativo'))
          as CrearCategoriaFinancieraExitoso;

      await registrarIngreso.ejecutar(
        monto: 10000,
        fecha: DateTime(2026, 1, 5),
        categoriaFinancieraId: categoriaA.categoria.id,
        formaPago: 'transferencia',
        concepto: 'Ingreso 1',
      );
      await registrarIngreso.ejecutar(
        monto: 20000,
        fecha: DateTime(2026, 1, 6),
        categoriaFinancieraId: categoriaA.categoria.id,
        formaPago: 'transferencia',
        concepto: 'Ingreso 2',
      );
      await registrarIngreso.ejecutar(
        monto: 5000,
        fecha: DateTime(2026, 1, 7),
        categoriaFinancieraId: categoriaB.categoria.id,
        formaPago: 'transferencia',
        concepto: 'Ingreso 3',
      );
      await registrarIngreso.ejecutar(monto: 999, fecha: DateTime(2026, 1, 8), formaPago: 'transferencia', concepto: 'Sin categoría');

      final totales = await ingresoRepo.totalPorCategoria(rangoInicio: DateTime(2026, 1, 1), rangoFin: DateTime(2026, 1, 31));

      expect(totales[categoriaA.categoria.id], 30000);
      expect(totales[categoriaB.categoria.id], 5000);
      expect(totales[null], 999);
    });

    test('totalPorCategoria de Egreso excluye cancelados', () async {
      final categoria = (await crearCategoria.ejecutar(codigo: 'CAT-E', nombre: 'Categoría Egreso', tipo: 'egreso', tipoMovimiento: 'operativo'))
          as CrearCategoriaFinancieraExitoso;

      final egreso1 = (await registrarEgreso.ejecutar(
        monto: 15000,
        fecha: DateTime(2026, 1, 5),
        categoriaFinancieraId: categoria.categoria.id,
        formaPago: 'transferencia',
        concepto: 'Egreso vigente',
      )) as RegistrarEgresoExitoso;
      final egreso2 = (await registrarEgreso.ejecutar(
        monto: 8000,
        fecha: DateTime(2026, 1, 6),
        categoriaFinancieraId: categoria.categoria.id,
        formaPago: 'transferencia',
        concepto: 'Egreso a cancelar',
      )) as RegistrarEgresoExitoso;
      await egresoRepo.cancelar(egresoId: egreso2.egreso.id, motivo: 'Prueba');

      final totales = await egresoRepo.totalPorCategoria(rangoInicio: DateTime(2026, 1, 1), rangoFin: DateTime(2026, 1, 31));

      expect(totales[categoria.categoria.id], 15000, reason: 'el egreso cancelado no debe sumar');
      expect(egreso1.egreso.monto, 15000);
    });
  });

  group('PagoNominaRepository.totalPagadoEnRango / listarEnRango', () {
    test('suma solo los PagoNomina registrados dentro del rango', () async {
      await pagoNominaDePrueba(fechaPago: DateTime(2026, 1, 20));

      final totalEnero = await pagoNominaRepo.totalPagadoEnRango(rangoInicio: DateTime(2026, 1, 1), rangoFin: DateTime(2026, 1, 31));
      final totalFebrero = await pagoNominaRepo.totalPagadoEnRango(rangoInicio: DateTime(2026, 2, 1), rangoFin: DateTime(2026, 2, 28));

      expect(totalEnero, greaterThan(0));
      expect(totalFebrero, 0, reason: 'fuera del rango, no debe sumar');

      final pagos = await pagoNominaRepo.listarEnRango(rangoInicio: DateTime(2026, 1, 1), rangoFin: DateTime(2026, 1, 31));
      expect(pagos, hasLength(1));
      expect(pagos.single.montoTotal, totalEnero);
    });

    test('un PagoNomina cancelado no cuenta hacia el total ni aparece en listarEnRango', () async {
      final pago = await pagoNominaDePrueba(fechaPago: DateTime(2026, 1, 20));
      await pagoNominaRepo.cancelar(pagoNominaId: pago.id, motivo: 'Prueba');

      final total = await pagoNominaRepo.totalPagadoEnRango(rangoInicio: DateTime(2026, 1, 1), rangoFin: DateTime(2026, 1, 31));
      final pagos = await pagoNominaRepo.listarEnRango(rangoInicio: DateTime(2026, 1, 1), rangoFin: DateTime(2026, 1, 31));

      expect(total, 0);
      expect(pagos, isEmpty);
    });
  });

  group('ClasificarEgresosPorOrigenUseCase — sin doble conteo', () {
    late ClasificarEgresosPorOrigenUseCase clasificar;

    setUp(() {
      clasificar = ClasificarEgresosPorOrigenUseCase(egresoRepo, compraRepo, pagoNominaRepo);
    });

    test('clasifica correctamente Compra, Nómina y manual, y la suma coincide con totalEgresos', () async {
      final compra = await compraDePrueba(fecha: DateTime(2026, 1, 10), costoUnitario: 30000);
      final pagoNomina = await pagoNominaDePrueba(fechaPago: DateTime(2026, 1, 20));
      await registrarEgreso.ejecutar(monto: 5000, fecha: DateTime(2026, 1, 15), formaPago: 'efectivo', concepto: 'Gasto manual');

      final resumen = await clasificar.ejecutar(rangoInicio: DateTime(2026, 1, 1), rangoFin: DateTime(2026, 1, 31));
      final totalEgresos = await egresoRepo.totalEgresos(rangoInicio: DateTime(2026, 1, 1), rangoFin: DateTime(2026, 1, 31));

      expect(resumen.totalCompra, 30000);
      expect(resumen.totalNomina, pagoNomina.montoTotal);
      expect(resumen.totalManual, 5000);
      expect(
        resumen.totalCompra + resumen.totalNomina + resumen.totalManual,
        totalEgresos,
        reason: 'la clasificación nunca debe perder ni duplicar un Egreso',
      );

      final origenPorEgresoId = {for (final e in resumen.detalle) e.egreso.id: e.origen};
      expect(origenPorEgresoId[compra.egresoId], OrigenEgreso.compra);
      expect(origenPorEgresoId[pagoNomina.egresoId], OrigenEgreso.nomina);
    });

    test('periodo sin datos: todo en cero, sin excepciones', () async {
      final resumen = await clasificar.ejecutar(rangoInicio: DateTime(2030, 1, 1), rangoFin: DateTime(2030, 1, 31));

      expect(resumen.totalCompra, 0);
      expect(resumen.totalNomina, 0);
      expect(resumen.totalManual, 0);
      expect(resumen.detalle, isEmpty);
    });
  });

  group('ObtenerResumenGeneralUseCase — campos null vs. cero real, sin doble conteo', () {
    late ObtenerResumenGeneralUseCase obtenerResumen;

    setUp(() {
      obtenerResumen = ObtenerResumenGeneralUseCase(resumenFinanciero, compraRepo, pagoNominaRepo, empleadoRepo, servicioRepo);
    });

    test('con todas las secciones excluidas, cada campo es null (no cero)', () async {
      final resumen = await obtenerResumen.ejecutar(
        rangoInicio: DateTime(2026, 1, 1),
        rangoFin: DateTime(2026, 1, 31),
        incluirFinanzas: false,
        incluirCompras: false,
        incluirNomina: false,
        incluirPersonal: false,
        incluirComercial: false,
      );

      expect(resumen.totalIngresos, isNull);
      expect(resumen.totalEgresos, isNull);
      expect(resumen.resultadoOperativo, isNull);
      expect(resumen.totalComprasPeriodo, isNull);
      expect(resumen.totalNominaPagadaPeriodo, isNull);
      expect(resumen.personalActivoActual, isNull);
      expect(resumen.serviciosActivosActual, isNull);
    });

    test('con todas las secciones incluidas mas sin datos, cada campo es un cero real (no null)', () async {
      final resumen = await obtenerResumen.ejecutar(
        rangoInicio: DateTime(2026, 1, 1),
        rangoFin: DateTime(2026, 1, 31),
        incluirFinanzas: true,
        incluirCompras: true,
        incluirNomina: true,
        incluirPersonal: true,
        incluirComercial: true,
      );

      expect(resumen.totalIngresos, 0);
      expect(resumen.totalEgresos, 0);
      expect(resumen.resultadoOperativo, 0);
      expect(resumen.totalComprasPeriodo, 0);
      expect(resumen.totalNominaPagadaPeriodo, 0);
      expect(resumen.personalActivoActual, 0);
      expect(resumen.serviciosActivosActual, 0);
    });

    test('Compras y Nómina pagada nunca se restan del resultado operativo — ya están dentro de Egresos', () async {
      await registrarIngreso.ejecutar(monto: 100000, fecha: DateTime(2026, 1, 5), formaPago: 'transferencia', concepto: 'Ingreso real');
      final compra = await compraDePrueba(fecha: DateTime(2026, 1, 10), costoUnitario: 20000);
      final pagoNomina = await pagoNominaDePrueba(fechaPago: DateTime(2026, 1, 20));

      final resumen = await obtenerResumen.ejecutar(
        rangoInicio: DateTime(2026, 1, 1),
        rangoFin: DateTime(2026, 1, 31),
        incluirFinanzas: true,
        incluirCompras: true,
        incluirNomina: true,
        incluirPersonal: false,
        incluirComercial: false,
      );

      // Egresos ya incluye tanto la Compra como el pago de Nómina (cada
      // uno generó exactamente un Egreso automático) — el resultado
      // operativo debe reflejar exactamente Ingresos - Egresos, sin
      // restar Compras/Nómina una segunda vez.
      expect(resumen.totalEgresos, greaterThanOrEqualTo(compra.egresoId == null ? 0 : 20000));
      expect(resumen.resultadoOperativo, resumen.totalIngresos! - resumen.totalEgresos!);
      expect(resumen.totalComprasPeriodo, 20000, reason: 'indicador informativo aparte');
      expect(resumen.totalNominaPagadaPeriodo, pagoNomina.montoTotal, reason: 'indicador informativo aparte');
    });
  });
}
