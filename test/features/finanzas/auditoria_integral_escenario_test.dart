// Auditoría integral 19A-19D — "Cierre de bloque Finanzas" (Parte 2 del
// pedido: "Auditar los números"). Escenario único, contra una BD real
// (nunca fakes), recorriendo la cadena completa Compra → Gasto →
// TDC/Deuda → Pago → Caja → CxC → Nómina → Resumen → Planeación con los
// montos exactos pedidos:
//
//   Saldo inicial BBVA:  $100,000
//   CxC cliente A:        $30,000
//   Compra transferencia: $10,000
//   Compra TDC:            $5,000
//   Nómina:               $20,000
//   Pago de TDC:           $3,000
//   Cobro cliente:        $15,000
//
// Cada assertion, según pide el enunciado, se verifica de forma
// INDEPENDIENTE de la fórmula de producción: o bien contra un literal
// calculado a mano a partir del escenario (no una re-derivación de la
// misma fórmula), o bien contando/sumando filas crudas de la tabla
// correspondiente en vez de leer un getter ya combinado.

import 'package:riseg_one/features/finanzas/domain/usecases/resolver_nombres_contraparte_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/data/repositories/servicio_eventual_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/vehiculo_mantenimiento_repository_impl.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/compras/data/repositories/compra_repository_impl.dart';
import 'package:riseg_one/features/compras/domain/repositories/compra_repository.dart';
import 'package:riseg_one/features/compras/domain/usecases/registrar_compra_usecase.dart';
import 'package:riseg_one/features/descuentos_personal/data/repositories/descuento_programado_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_financiera_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_por_cobrar_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/ingreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/pago_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/tables/deuda_table.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/finanzas/domain/usecases/obtener_proyeccion_caja_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_cuenta_financiera_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_deuda_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_pago_aplicado_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_pago_deuda_usecase.dart';
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/inventario_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/repositories/nomina_repository_impl.dart';
import 'package:riseg_one/features/tiempos_extra/data/repositories/tiempo_extra_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/repositories/pago_nomina_repository_impl.dart';
import 'package:riseg_one/features/nomina/domain/usecases/registrar_pago_nomina_usecase.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/reportes/domain/usecases/clasificar_egresos_por_origen_usecase.dart';
import 'package:riseg_one/features/telefonia/data/repositories/recarga_linea_telefonica_repository_impl.dart';

/// El resolutor de nombres de contraparte, armado sobre la BD real de
/// la prueba — Cliente o Servicio Eventual (schemaVersion 88).
ResolverNombresContraparteUseCase resolverNombresDePrueba(AppDatabase db) {
  return ResolverNombresContraparteUseCase(
    ClienteRepositoryImpl(db),
    ServicioEventualRepositoryImpl(
      db,
      EgresoRepositoryImpl(db),
      DeudaRepositoryImpl(db, EgresoRepositoryImpl(db)),
      CodigoSecuenciaService(db),
      CuentaPorCobrarRepositoryImpl(db),
      PagoRepositoryImpl(db),
    ),
  );
}


void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  test(
    'Escenario integral 19A-19D: Compra→Gasto→TDC/Deuda→Pago→Caja→CxC→Nómina→Resumen→Planeación coherente end-to-end',
    () async {
      final hoy = DateTime.now();
      final hoySinHora = DateTime(hoy.year, hoy.month, hoy.day);

      // --- Construcción de repos/use cases contra la BD real ---
      final cuentaFinancieraRepo = CuentaFinancieraRepositoryImpl(db);
      final egresoRepo = EgresoRepositoryImpl(db);
      final ingresoRepo = IngresoRepositoryImpl(db);
      final deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
      final articuloRepo = ArticuloRepositoryImpl(db);
      final inventarioRepo = InventarioRepositoryImpl(db);
      final compraRepo = CompraRepositoryImpl(db, inventarioRepo, articuloRepo, egresoRepo, deudaRepo);
      final pagoRepo = PagoRepositoryImpl(db);
      final cxcRepo = CuentaPorCobrarRepositoryImpl(db);
      final clienteRepo = ClienteRepositoryImpl(db);
      final nominaRepo = NominaRepositoryImpl(db, AsignacionRepositoryImpl(db), DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db)), TiempoExtraRepositoryImpl(db, EgresoRepositoryImpl(db), DeudaRepositoryImpl(db, EgresoRepositoryImpl(db)), CodigoSecuenciaService(db), EmpleadoRepositoryImpl(db, AsignacionServicioRepositoryImpl(db)), ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db))), PagoNominaRepositoryImpl(db, EgresoRepositoryImpl(db), DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db))));
      final pagoNominaRepo = PagoNominaRepositoryImpl(db, egresoRepo, DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db)));
      final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));

      final registrarCuentaFinanciera = RegistrarCuentaFinancieraUseCase(cuentaFinancieraRepo, generarCodigo);
      final registrarCompra = RegistrarCompraUseCase(compraRepo, articuloRepo, inventarioRepo, deudaRepo, generarCodigo);
      final registrarDeuda = RegistrarDeudaUseCase(deudaRepo, generarCodigo);
      final registrarPagoDeuda = RegistrarPagoDeudaUseCase(deudaRepo, generarCodigo);
      final registrarPagoAplicado = RegistrarPagoAplicadoUseCase(pagoRepo, cxcRepo, generarCodigo);
      final registrarPagoNomina = RegistrarPagoNominaUseCase(pagoNominaRepo, nominaRepo, generarCodigo, CuentaFinancieraRepositoryImpl(db));

      // --- 1. Saldo inicial BBVA: $100,000 ---
      final cuentaResultado = await registrarCuentaFinanciera.ejecutar(
        nombre: 'BBVA Operativa',
        tipo: 'banco',
        saldoInicial: 10000000, // $100,000.00
        fechaSaldoInicial: hoy.subtract(const Duration(days: 90)),
      );
      final bbva = (cuentaResultado as RegistrarCuentaFinancieraExitoso).cuenta;

      // --- 2. CxC cliente A: $30,000, vencimiento futuro válido (+20 días) ---
      final cliente = await clienteRepo.crear(
        ClienteCompanion.insert(codigo: 'CLI-AUDIT-01', nombreComercial: 'Cliente Auditoría A'),
      );
      final fechaVencimientoCxc = hoySinHora.add(const Duration(days: 20));
      final documento = await db.into(db.documentoPorEmitir).insertReturning(
            DocumentoPorEmitirCompanion.insert(
              codigo: 'DOC-AUDIT-01',
              clienteId: cliente.id,
              tipoDocumento: 'cfdi',
              agrupacion: 'porServicio',
              metodo: 'PUE',
              periodoInicio: hoy,
              periodoFin: hoy,
              generationKey: 'clave-audit-01',
              importeBaseEsperado: 3000000,
              importeFinalEsperado: 3000000,
            ),
          );
      final cxc = await db.into(db.cuentaPorCobrar).insertReturning(
            CuentaPorCobrarCompanion.insert(
              documentoPorEmitirId: Value(documento.id),
              clienteId: Value(cliente.id),
              tipoDocumento: 'cfdi',
              metodo: 'PUE',
              fechaEmisionReal: hoy,
              importeEmitido: 3000000, // $30,000.00
              saldoOriginal: 3000000,
              saldoPendiente: 3000000,
              fechaVencimiento: Value(fechaVencimientoCxc),
            ),
          );

      // --- 3. Compra por transferencia: $10,000, ligada a BBVA ---
      final compraTransferenciaResultado = await registrarCompra.ejecutar(
        fecha: hoy,
        proveedor: 'Arrendadora del Centro',
        formaPago: FormaPago.transferencia.name,
        cuentaFinancieraId: bbva.id,
        partidas: const [
          PartidaCompraInput(
            destino: 'gastoDirecto',
            concepto: 'Renta de oficina',
            cantidad: 1,
            costoUnitario: 1000000, // $10,000.00
          ),
        ],
      );
      expect(compraTransferenciaResultado, isA<RegistrarCompraExitosa>());

      // --- 4. Alta de la tarjeta de crédito (TDC) ---
      final deudaResultado = await registrarDeuda.ejecutar(
        nombre: 'TDC BBVA',
        tipo: TipoDeuda.tarjetaCredito.name,
        fechaOrigen: hoy,
        importeOriginal: 2000000,
        saldoInicial: 0,
        tarjetaLimiteCredito: 2000000, // $20,000.00 de límite
        tarjetaUltimosDigitos: '4242',
      );
      if (deudaResultado is RegistrarDeudaErrorInesperado) {
        fail('RegistrarDeuda falló: ${deudaResultado.mensaje}');
      }
      final tarjeta = (deudaResultado as RegistrarDeudaExitoso).deuda;

      // --- 5. Compra con TDC: $5,000 ---
      final compraTarjetaResultado = await registrarCompra.ejecutar(
        fecha: hoy,
        proveedor: 'Agencia de Publicidad',
        formaPago: FormaPago.tarjeta.name,
        deudaId: tarjeta.id,
        partidas: const [
          PartidaCompraInput(
            destino: 'gastoDirecto',
            concepto: 'Campaña de publicidad',
            cantidad: 1,
            costoUnitario: 500000, // $5,000.00
          ),
        ],
      );
      expect(compraTarjetaResultado, isA<RegistrarCompraExitosa>());

      // --- 6. Nómina de $20,000, cerrada y pagada por completo ---
      final empleado = await db.into(db.empleado).insertReturning(
            EmpleadoCompanion.insert(
              numeroEmpleado: 1,
              nombres: 'Empleado',
              apellidoPaterno: 'Auditoría',
              sexo: 'masculino',
              fechaNacimiento: DateTime(1990, 1, 1),
              curp: 'AUDI900101HDFXXX01',
              rfc: 'AUDI900101AB1',
              nss: '12345678901',
              estadoCivil: 'soltero',
              fechaIngreso: DateTime(2026, 1, 1),
              aniosExperienciaSeguridad: 1,
            ),
          );
      final nomina = await db.into(db.nomina).insertReturning(
            NominaCompanion.insert(
              folio: 'NOM-AUDIT-01',
              anio: hoy.year,
              mes: hoy.month,
              tipoPeriodo: 'segundaQuincena',
              fechaInicioPeriodo: hoy.subtract(const Duration(days: 14)),
              fechaFinPeriodo: hoy,
              fechaPagoOrdinaria: hoy,
              estatus: const Value('cerrada'),
            ),
          );
      final renglon = await db.into(db.nominaEmpleado).insertReturning(
            NominaEmpleadoCompanion.insert(
              nominaId: nomina.id,
              empleadoId: empleado.id,
              numeroEmpleado: 1,
              nombreCompleto: 'Empleado Auditoría',
              fuenteSueldoUtilizada: 'referencia',
              diasPagables: 15,
              sueldoMensualUtilizado: 4000000,
              sueldoQuincenalReferencia: 2000000,
              pagoPorDia: 133333,
              importeBase: 2000000,
              totalAPagar: 2000000, // $20,000.00
            ),
          );
      final pagoNominaResultado = await registrarPagoNomina.ejecutar(
        nominaId: nomina.id,
        fechaPago: hoy,
        formaPago: FormaPago.transferencia.name,
        cuentaFinancieraId: bbva.id,
        aplicaciones: [(nominaEmpleadoId: renglon.id, monto: 2000000)],
      );
      expect(pagoNominaResultado, isA<RegistrarPagoNominaExitoso>());

      // --- 7. Pago de TDC: $3,000 ---
      final pagoDeudaResultado = await registrarPagoDeuda.ejecutar(
        deudaId: tarjeta.id,
        fecha: hoy,
        importe: 300000, // $3,000.00
        formaPago: FormaPago.transferencia.name,
        cuentaFinancieraId: bbva.id,
      );
      expect(pagoDeudaResultado, isA<RegistrarPagoDeudaExitoso>());

      // --- 8. Cobro al cliente: $15,000 ---
      final cobroResultado = await registrarPagoAplicado.ejecutar(
        cuentaPorCobrarId: cxc.id,
        monto: 1500000, // $15,000.00
        fechaPago: hoy,
        formaPago: FormaPago.transferencia.name,
        cuentaFinancieraId: bbva.id,
      );
      expect(cobroResultado, isA<RegistrarPagoAplicadoExitoso>());

      // ============================================================
      // ASSERTIONS INDEPENDIENTES — cada una contra un literal
      // calculado a mano a partir del escenario de arriba, o contra un
      // conteo/suma de filas crudas, NUNCA releyendo directamente el
      // resultado combinado de un getter de producción.
      // ============================================================

      // --- A. La Compra TDC se reconoce como GASTO (vía MovimientoDeuda
      // .cargoCompra), independientemente de que nunca generó Egreso.
      final cargosCompraTdc = await (db.select(db.movimientoDeuda)
            ..where((m) => m.deudaId.equals(tarjeta.id) & m.tipo.equals(TipoMovimientoDeuda.cargoCompra.name)))
          .get();
      expect(cargosCompraTdc, hasLength(1), reason: 'la Compra TDC debe reconocerse como UN cargo real a la tarjeta');
      expect(cargosCompraTdc.single.importe, 500000, reason: r'el cargo reconocido debe ser exactamente $5,000');

      // Conteo crudo de Egresos: deben ser EXACTAMENTE 3 (transferencia,
      // Nómina, pago de TDC) — la Compra TDC NUNCA genera un 4º Egreso.
      final todosLosEgresos = await db.select(db.egreso).get();
      expect(todosLosEgresos, hasLength(3), reason: 'compra transferencia + pago Nómina + pago TDC = 3 Egresos, la Compra TDC no genera un 4°');
      final sumaEgresos = todosLosEgresos.fold<int>(0, (s, e) => s + e.monto);
      expect(sumaEgresos, 3300000, reason: r'$10,000 (compra) + $20,000 (nómina) + $3,000 (pago TDC) = $33,000');

      // Resultado operativo esperado A MANO (nunca releído de
      // `ResumenFinancieroState.resultadoOperativo`): ingresos − (egresos
      // que NO sean pago de deuda) + cargos de TDC del periodo
      //   = $15,000 − ($10,000 + $20,000) + $5,000 = −$20,000
      final egresosPorOrigen = await ClasificarEgresosPorOrigenUseCase(
        egresoRepo,
        compraRepo,
        pagoNominaRepo,
        TiempoExtraRepositoryImpl(
          db,
          egresoRepo,
          deudaRepo,
          CodigoSecuenciaService(db),
          EmpleadoRepositoryImpl(db, AsignacionServicioRepositoryImpl(db)),
          ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db)),
        ),
        RecargaLineaTelefonicaRepositoryImpl(db, EgresoRepositoryImpl(db), DeudaRepositoryImpl(db, EgresoRepositoryImpl(db)), CodigoSecuenciaService(db)),
        deudaRepo,
        DescuentoProgramadoRepositoryImpl(db, egresoRepo, CodigoSecuenciaService(db)),
        VehiculoMantenimientoRepositoryImpl(db),
        ServicioEventualRepositoryImpl(db, EgresoRepositoryImpl(db), DeudaRepositoryImpl(db, EgresoRepositoryImpl(db)), CodigoSecuenciaService(db), CuentaPorCobrarRepositoryImpl(db), PagoRepositoryImpl(db)),
      ).ejecutar();
      final cargosTarjetaPeriodo = await deudaRepo.totalCargadoEnRango();
      final totalIngresos = await ingresoRepo.totalIngresos();
      final resultadoOperativoReal =
          totalIngresos - ((sumaEgresos - egresosPorOrigen.totalDeuda) + cargosTarjetaPeriodo);
      expect(
        resultadoOperativoReal,
        -2000000,
        reason: r'−$20,000: ingresos $15,000 − gasto operativo $35,000 ($10,000 renta + $20,000 nómina + $5,000 cargo TDC)',
      );

      // --- B. CAJA: la Compra TDC no la redujo; el pago de TDC sí. ---
      // Suma cruda, independiente de `calcularSaldo`: cada Ingreso/Egreso
      // ligado a BBVA, sumado a mano.
      final ingresosBbva = await (db.select(db.ingreso)..where((i) => i.cuentaFinancieraId.equals(bbva.id))).get();
      final egresosBbva = await (db.select(db.egreso)..where((e) => e.cuentaFinancieraId.equals(bbva.id))).get();
      expect(egresosBbva, hasLength(3), reason: 'los 3 Egresos de este escenario están ligados a BBVA — ninguno de la Compra TDC');
      final sumaIngresosBbva = ingresosBbva.fold<int>(0, (s, i) => s + i.monto);
      final sumaEgresosBbva = egresosBbva.fold<int>(0, (s, e) => s + e.monto);
      final saldoBbvaEsperado = 10000000 + sumaIngresosBbva - sumaEgresosBbva;
      expect(
        saldoBbvaEsperado,
        8200000,
        reason: r'$100,000 + $15,000 (cobro) − $10,000 (renta) − $20,000 (nómina) − $3,000 (pago TDC) = $82,000; '
            r'el cargo TDC de $5,000 NUNCA aparece aquí porque no generó Egreso/Ingreso',
      );
      final saldoBbvaReal = await cuentaFinancieraRepo.calcularSaldo(bbva.id);
      expect(saldoBbvaReal, saldoBbvaEsperado, reason: 'el saldo derivado real debe coincidir con la suma cruda independiente');

      // --- C. CXC: deben quedar $15,000 pendientes. ---
      final cxcActualizada = await cxcRepo.obtenerPorId(cxc.id);
      expect(cxcActualizada!.saldoPendiente, 1500000, reason: r'$30,000 − $15,000 cobrados = $15,000 pendientes');
      expect(cxcActualizada.estatus, 'parcial');

      // --- D. TDC: saldo = cargo $5,000 − pago $3,000 = $2,000. ---
      final tarjetaActualizada = await deudaRepo.obtenerPorId(tarjeta.id);
      expect(tarjetaActualizada!.saldoActual, 200000, reason: r'cargo $5,000 − pago $3,000 = $2,000 de saldo restante en la TDC');

      // --- E. PLANEACIÓN: solo la obligación/cobro con fecha futura
      // válida (la CxC de $15,000 restante) debe aparecer como
      // compromiso; nada vencido, nada inventado. ---
      final proyeccion = await ObtenerProyeccionCajaUseCase(
        cuentaFinancieraRepo,
        cxcRepo,
        resolverNombresDePrueba(db),
        nominaRepo,
        pagoNominaRepo,
        deudaRepo,
      ).ejecutar(hoy: hoy, hasta: hoySinHora.add(const Duration(days: 30)));

      expect(proyeccion.pendientesVencidos, isEmpty, reason: 'nada en este escenario está vencido');
      expect(proyeccion.compromisos, hasLength(1), reason: 'la Nómina ya está pagada, la TDC no tiene pagoProgramado — solo la CxC restante debe aparecer');
      final compromisoCxc = proyeccion.compromisos.single;
      expect(compromisoCxc.origen, OrigenCompromiso.cuentaPorCobrar);
      expect(compromisoCxc.importe, 1500000, reason: r'debe proyectar exactamente el saldo pendiente restante, no el importe original de $30,000');
      expect(compromisoCxc.fecha, fechaVencimientoCxc, reason: 'la fecha proyectada debe ser la fecha futura real capturada, nunca inventada');
    },
  );
}
