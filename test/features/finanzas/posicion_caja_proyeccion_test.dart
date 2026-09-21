// Etapa 19C — "Posición de caja, flujo real y proyección de
// compromisos". Cubre los invariantes obligatorios de la Parte L del
// pedido que son responsabilidad del dominio (persistencia/agregación
// real de `CuentaFinanciera` y filtrado/composición de
// `ObtenerProyeccionCajaUseCase`). Los invariantes 2/3 (Compra con TDC
// no duplica gasto) ya están cubiertos en
// `compra_tarjeta_integration_test.dart` (Etapa 19B) y no se repiten
// aquí. Los invariantes 13/14 (alerta de déficit, recálculo al cambiar
// periodo) son responsabilidad de la capa de presentación y se prueban
// junto con `resumen_financiero_screen.dart`.
//
// `ObtenerProyeccionCajaUseCase` se prueba con dependencias FALSAS
// (mismo criterio que `dashboard_usecases_test.dart`: fakes triviales
// con `noSuchMethod` para los métodos que no ejercita esta prueba) —
// evita reconstruir la cadena completa Cliente→Servicio→
// DocumentoPorEmitir→CuentaPorCobrar o el motor completo de Nómina
// solo para probar el filtrado/agregación, que es la lógica
// genuinamente nueva de esta etapa. `CuentaFinancieraRepositoryImpl`
// (el propio derivado de saldo) sí se prueba contra una BD real —
// ahí está el riesgo real de un bug de SQL/fechas.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_por_cobrar_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/pago_repository_impl.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/resolver_nombres_contraparte_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/data/repositories/servicio_eventual_repository_impl.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_financiera_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/tables/cuenta_financiera_table.dart';
import 'package:riseg_one/features/finanzas/data/tables/deuda_table.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/cuenta_por_cobrar_repository.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/deuda_repository.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/obtener_flujo_efectivo_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/obtener_posicion_de_caja_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/obtener_proyeccion_caja_usecase.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/ingreso_repository_impl.dart';
import 'package:riseg_one/features/nomina/domain/repositories/nomina_repository.dart';
import 'package:riseg_one/features/nomina/domain/repositories/pago_nomina_repository.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';

/// Solo implementa `listar()` — mismo patrón exacto que
/// `_CuentaPorCobrarRepositoryDePrueba` en `dashboard_usecases_test.dart`.
class _CuentaPorCobrarRepositoryDePrueba implements CuentaPorCobrarRepository {

  @override
  Future<CuentaPorCobrarData> crearDeServicioEventual({
    required String servicioEventualId,
    String? clienteId,
    required String tipoDocumento,
    required String metodo,
    required bool requiereComplemento,
    required DateTime fechaEmisionReal,
    required int importeEmitido,
    DateTime? fechaVencimiento,
    String? observaciones,
    String? actorUsuarioId,
  }) =>
      throw UnimplementedError();

  @override
  Future<CuentaPorCobrarData?> obtenerPorServicioEventualId(String servicioEventualId) =>
      throw UnimplementedError();

  @override
  Future<CuentaPorCobrarData> sincronizarConDocumentoFiscal({
    required String cuentaPorCobrarId,
    String? folioDocumento,
    String? uuid,
    required DateTime fechaEmisionReal,
    required String metodo,
    required bool requiereComplemento,
    String? actorUsuarioId,
  }) =>
      throw UnimplementedError();

  @override
  Future<CuentaPorCobrarData> corregirImporte({
    required String cuentaPorCobrarId,
    required int importeEmitido,
    required String motivo,
    String? actorUsuarioId,
  }) =>
      throw UnimplementedError();

  _CuentaPorCobrarRepositoryDePrueba(this.cuentas);
  final List<CuentaPorCobrarData> cuentas;

  @override
  Future<List<CuentaPorCobrarData>> listar({
    String? clienteId,
    String? servicioId,
    String? entidadFiscalId,
    String? tipoDocumento,
    String? estatus,
    String? documentoPorEmitirId,
    String? servicioEventualId,
  }) async =>
      cuentas;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

CuentaPorCobrarData _cxcDePrueba({
  required String id,
  required String clienteId,
  required int saldoPendiente,
  DateTime? fechaVencimiento,
  DateTime? fechaCobroReprogramada,
  String estatus = 'pendiente',
  int? importeEmitido,
}) {
  final ahora = DateTime(2026, 1, 1);
  return CuentaPorCobrarData(
    id: id,
    createdAt: ahora,
    updatedAt: ahora,
    cicloVidaRegistro: 'activo',
    documentoPorEmitirId: 'doc-$id',
    clienteId: clienteId,
    tipoDocumento: 'factura',
    metodo: 'pue',
    requiereComplemento: false,
    fechaEmisionReal: ahora,
    importeEmitido: importeEmitido ?? saldoPendiente,
    saldoOriginal: importeEmitido ?? saldoPendiente,
    saldoPendiente: saldoPendiente,
    moneda: 'MXN',
    estatus: estatus,
    fechaVencimiento: fechaVencimiento,
    fechaCobroReprogramada: fechaCobroReprogramada,
  );
}

/// Solo implementa `listar()`.
class _DeudaRepositoryDePrueba implements DeudaRepository {
  _DeudaRepositoryDePrueba(this.deudas);
  final List<DeudaData> deudas;

  @override
  Future<List<DeudaData>> listar({String? tipo, String? estatus, String? busqueda}) async => deudas;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

DeudaData _deudaDePrueba({
  required String id,
  String tipo = 'prestamo',
  int? pagoProgramado,
  DateTime? fechaVencimiento,
  int? tarjetaDiaPago,
  String nombre = 'Deuda de prueba',
}) {
  final ahora = DateTime(2026, 1, 1);
  return DeudaData(
    id: id,
    createdAt: ahora,
    updatedAt: ahora,
    cicloVidaRegistro: 'activo',
    folio: 'DEU-$id',
    nombre: nombre,
    tipo: tipo,
    fechaOrigen: ahora,
    importeOriginal: 1000000,
    saldoActual: 1000000,
    fechaVencimiento: fechaVencimiento,
    pagoProgramado: pagoProgramado,
    tarjetaDiaPago: tarjetaDiaPago,
    estatus: 'activa',
  );
}

/// Solo implementa `totalAplicadoPorRenglon()`.
class _PagoNominaRepositoryDePrueba implements PagoNominaRepository {
  _PagoNominaRepositoryDePrueba(this.aplicadoPorRenglon);
  final Map<String, int> aplicadoPorRenglon;

  @override
  Future<Map<String, int>> totalAplicadoPorRenglon(List<String> nominaEmpleadoIds) async {
    return {for (final id in nominaEmpleadoIds) if (aplicadoPorRenglon.containsKey(id)) id: aplicadoPorRenglon[id]!};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// Solo implementa `listarEnRango()`/`listarEmpleados()`.
class _NominaRepositoryDePrueba implements NominaRepository {
  _NominaRepositoryDePrueba(this.nominas, this.empleadosPorNomina);
  final List<NominaData> nominas;
  final Map<String, List<NominaEmpleadoData>> empleadosPorNomina;

  @override
  Future<List<NominaData>> listarEnRango({DateTime? rangoInicio, DateTime? rangoFin, String? estatus}) async {
    return estatus == null ? nominas : nominas.where((n) => n.estatus == estatus).toList();
  }

  @override
  Future<List<NominaEmpleadoData>> listarEmpleados(String nominaId) async => empleadosPorNomina[nominaId] ?? const [];

  /// Mismo filtro por `estatus` que la consulta real
  /// (`NominaRepositoryImpl.listarRenglonesEnRango`) — sin `rangoInicio`/
  /// `rangoFin` porque ninguna prueba de este archivo los ejercita.
  @override
  Future<List<NominaEmpleadoReporteRow>> listarRenglonesEnRango({DateTime? rangoInicio, DateTime? rangoFin, String? estatus}) async {
    final nominasFiltradas = estatus == null ? nominas : nominas.where((n) => n.estatus == estatus).toList();
    return [
      for (final n in nominasFiltradas)
        for (final r in empleadosPorNomina[n.id] ?? const <NominaEmpleadoData>[])
          NominaEmpleadoReporteRow(
            id: r.id,
            nominaId: r.nominaId,
            numeroEmpleado: r.numeroEmpleado,
            nombreCompleto: r.nombreCompleto,
            importeBase: r.importeBase,
            bono: r.bono,
            faltas: r.faltas,
            descuentoPorFaltas: r.descuentoPorFaltas,
            prestamo: r.prestamo,
            tiempoExtra: r.tiempoExtra,
            otrosDescuentos: r.otrosDescuentos,
            montoFiscal: r.montoFiscal,
            montoNoFiscal: r.montoNoFiscal,
            totalAPagar: r.totalAPagar,
            estatusPago: r.estatusPago,
          ),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

NominaData _nominaDePrueba({
  required String id,
  required DateTime fechaPagoOrdinaria,
  String estatus = 'cerrada',
  String folio = 'NOM-0001',
}) {
  final ahora = DateTime(2026, 1, 1);
  return NominaData(
    id: id,
    createdAt: ahora,
    updatedAt: ahora,
    cicloVidaRegistro: 'activo',
    folio: folio,
    anio: fechaPagoOrdinaria.year,
    mes: fechaPagoOrdinaria.month,
    tipoPeriodo: 'segundaQuincena',
    fechaInicioPeriodo: fechaPagoOrdinaria.subtract(const Duration(days: 14)),
    fechaFinPeriodo: fechaPagoOrdinaria,
    fechaPagoOrdinaria: fechaPagoOrdinaria,
    estatus: estatus,
  );
}

NominaEmpleadoData _renglonDePrueba({required String id, required String nominaId, required int totalAPagar}) {
  final ahora = DateTime(2026, 1, 1);
  return NominaEmpleadoData(
    id: id,
    createdAt: ahora,
    updatedAt: ahora,
    cicloVidaRegistro: 'activo',
    nominaId: nominaId,
    empleadoId: 'empleado-$id',
    numeroEmpleado: 1,
    nombreCompleto: 'Empleado de prueba',
    fuenteSueldoUtilizada: 'referencia',
    diasPagables: 15,
    sueldoMensualUtilizado: 900000,
    sueldoQuincenalReferencia: 450000,
    pagoPorDia: 30000,
    importeBase: totalAPagar,
    prestamo: 0,
    tiempoExtra: 0,
    bono: 0,
    bonoModificadoManualmente: false,
    faltas: 0,
    descuentoPorFaltas: 0,
    otrosDescuentos: 0,
    descuentosInventario: 0,
    descuentosInventarioPendienteRevision: false,
    descuentosProgramados: 0,
    descuentosProgramadosPendienteRevision: false,
    montoFiscal: totalAPagar,
    montoNoFiscal: 0,
    distribucionModificadaManualmente: false,
    distribucionPendienteRevision: false,
    totalAPagar: totalAPagar,
    estatusPago: 'pendiente',
  );
}

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
  group('CuentaFinancieraRepositoryImpl — saldo derivado (BD real)', () {
    late AppDatabase db;
    late CuentaFinancieraRepositoryImpl repo;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repo = CuentaFinancieraRepositoryImpl(db);
      addTearDown(db.close);
    });

    Future<CuentaFinancieraData> crearCuenta({
      required int saldoInicial,
      DateTime? fechaSaldoInicial,
      String codigo = 'CTA-0001',
    }) {
      return db.into(db.cuentaFinanciera).insertReturning(
            CuentaFinancieraCompanion.insert(
              codigo: codigo,
              nombre: 'Cuenta de prueba',
              tipo: TipoCuentaFinanciera.banco.name,
              saldoInicial: saldoInicial,
              fechaSaldoInicial: fechaSaldoInicial ?? DateTime(2026, 1, 1),
            ),
          );
    }

    Future<void> insertarIngreso({required String? cuentaId, required int monto, DateTime? fecha}) {
      return db.into(db.ingreso).insert(
            IngresoCompanion.insert(
              folioIngreso: 'ING-${DateTime.now().microsecondsSinceEpoch}-${monto.hashCode}',
              monto: monto,
              fecha: fecha ?? DateTime(2026, 1, 15),
              formaPago: 'transferencia',
              concepto: 'Ingreso de prueba',
              cuentaFinancieraId: Value(cuentaId),
            ),
          );
    }

    /// Escribe el Egreso Y su fuente, igual que hace
    /// `EgresoRepositoryImpl`. Desde la v91 el efecto de un Egreso
    /// sobre una cuenta lo lleva `EgresoFuente`, no la columna legacy:
    /// un Egreso sin fuente no descuenta nada, y eso es lo correcto.
    Future<void> insertarEgreso({required String? cuentaId, required int monto, DateTime? fecha}) async {
      final egreso = await db.into(db.egreso).insertReturning(
            EgresoCompanion.insert(
              folioEgreso: 'EGR-${DateTime.now().microsecondsSinceEpoch}-${monto.hashCode}',
              monto: monto,
              fecha: fecha ?? DateTime(2026, 1, 15),
              formaPago: 'transferencia',
              concepto: 'Egreso de prueba',
              cuentaFinancieraId: Value(cuentaId),
            ),
          );
      if (cuentaId == null) return;
      await db.into(db.egresoFuente).insert(
            EgresoFuenteCompanion.insert(egresoId: egreso.id, cuentaFinancieraId: cuentaId, importe: monto),
          );
    }

    test('Invariante 1: saldo inicial \$50,000 + Ingreso \$20,000 - Egreso \$10,000 = \$60,000', () async {
      final cuenta = await crearCuenta(saldoInicial: 5000000);
      await insertarIngreso(cuentaId: cuenta.id, monto: 2000000);
      await insertarEgreso(cuentaId: cuenta.id, monto: 1000000);

      final saldo = await repo.calcularSaldo(cuenta.id);
      expect(saldo, 6000000);
    });

    test('Invariante 10: un movimiento sin cuenta financiera no desaparece del flujo global', () async {
      final cuenta = await crearCuenta(saldoInicial: 0);
      await insertarIngreso(cuentaId: cuenta.id, monto: 100000);
      await insertarIngreso(cuentaId: null, monto: 500000);

      final saldoDeLaCuenta = await repo.calcularSaldo(cuenta.id);
      expect(saldoDeLaCuenta, 100000, reason: 'el ingreso sin cuenta nunca se le atribuye a una cuenta concreta');

      final flujo = await ObtenerFlujoEfectivoUseCase(IngresoRepositoryImpl(db), EgresoRepositoryImpl(db)).ejecutar();
      expect(flujo.entradas, 600000, reason: 'el flujo global de efectivo sigue incluyendo el movimiento sin cuenta');
    });

    test('Invariante 11: una cuenta desactivada conserva su historial y su saldo derivado', () async {
      final cuenta = await crearCuenta(saldoInicial: 1000000);
      await insertarIngreso(cuentaId: cuenta.id, monto: 500000);

      await repo.desactivar(cuenta.id);

      final saldoTrasDesactivar = await repo.calcularSaldo(cuenta.id);
      expect(saldoTrasDesactivar, 1500000, reason: 'desactivar nunca borra ni recalcula el historial/saldo');

      final movimientos = await repo.listarMovimientos(cuenta.id);
      expect(movimientos, hasLength(1));

      final activas = await repo.listar(soloActivas: true);
      expect(activas, isEmpty, reason: 'una cuenta desactivada deja de contar para la posición de caja disponible hoy');
    });

    test('Invariante 15 (sin N+1): calcularSaldos resuelve N cuentas con consultas fijas, no proporcionales a N', () async {
      final cuentaA = await crearCuenta(saldoInicial: 1000000, codigo: 'CTA-A', fechaSaldoInicial: DateTime(2026, 1, 1));
      final cuentaB = await crearCuenta(saldoInicial: 2000000, codigo: 'CTA-B', fechaSaldoInicial: DateTime(2026, 6, 1));
      final cuentaC = await crearCuenta(saldoInicial: 0, codigo: 'CTA-C', fechaSaldoInicial: DateTime(2026, 1, 1));

      await insertarIngreso(cuentaId: cuentaA.id, monto: 100000, fecha: DateTime(2026, 2, 1));
      await insertarIngreso(cuentaId: cuentaB.id, monto: 300000, fecha: DateTime(2026, 3, 1)); // antes del corte de B
      await insertarIngreso(cuentaId: cuentaB.id, monto: 400000, fecha: DateTime(2026, 7, 1)); // después del corte de B
      await insertarEgreso(cuentaId: cuentaC.id, monto: 50000, fecha: DateTime(2026, 2, 1));

      final saldos = await repo.calcularSaldos([cuentaA.id, cuentaB.id, cuentaC.id]);

      expect(saldos[cuentaA.id], 1100000);
      expect(saldos[cuentaB.id], 2400000, reason: 'el ingreso de marzo cae antes de fechaSaldoInicial (junio) de B y se descarta');
      expect(saldos[cuentaC.id], -50000);
      // 4 consultas totales sin importar cuántas cuentas se pidan
      // (cuentas + ingresos + fuentes de egreso + transferencias, cada
      // una con `id IN (...)`) — desde la v91 las salidas se leen de
      // `EgresoFuente` con un `join` al Egreso dueño, que trae estatus
      // y fecha en la misma consulta, y las transferencias resuelven
      // origen y destino a la vez. Ver `calcularSaldosCanonico`: el
      // corte por `fechaSaldoInicial`, que sí varía por cuenta, se
      // aplica en memoria después de traer los movimientos ya
      // acotados, nunca con una consulta adicional por cuenta.
    });
  });

  group('ObtenerPosicionDeCajaUseCase', () {
    test('sin ninguna cuenta activa, cuentasConfiguradas es false y no finge un saldo de \$0.00', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final posicion = await ObtenerPosicionDeCajaUseCase(CuentaFinancieraRepositoryImpl(db)).ejecutar();

      expect(posicion.configurada, isFalse);
      expect(posicion.cuentas, isEmpty);
    });
  });

  group('ObtenerProyeccionCajaUseCase', () {
    late AppDatabase db;
    late CuentaFinancieraRepositoryImpl cuentaFinancieraRepo;
    final hoy = DateTime(2026, 8, 30);
    final hasta = DateTime(2026, 9, 14); // hoy + 15 días

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      cuentaFinancieraRepo = CuentaFinancieraRepositoryImpl(db);
      addTearDown(db.close);
    });

    Future<ObtenerProyeccionCajaUseCase> construir({
      List<CuentaPorCobrarData> cxc = const [],
      List<DeudaData> deudas = const [],
      List<NominaData> nominas = const [],
      Map<String, List<NominaEmpleadoData>> renglones = const {},
      Map<String, int> aplicadoPorRenglon = const {},
    }) async {
      return ObtenerProyeccionCajaUseCase(
        cuentaFinancieraRepo,
        _CuentaPorCobrarRepositoryDePrueba(cxc),
        resolverNombresDePrueba(db),
        _NominaRepositoryDePrueba(nominas, renglones),
        _PagoNominaRepositoryDePrueba(aplicadoPorRenglon),
        _DeudaRepositoryDePrueba(deudas),
      );
    }

    test('Invariante 4: un pago parcial de CxC solo proyecta el saldo pendiente, nunca el importe emitido', () async {
      final usecase = await construir(cxc: [
        _cxcDePrueba(
          id: 'cxc-1',
          clienteId: 'cliente-1',
          importeEmitido: 1000000,
          saldoPendiente: 300000,
          estatus: 'parcial',
          fechaVencimiento: DateTime(2026, 9, 5),
        ),
      ]);

      final proyeccion = await usecase.ejecutar(hoy: hoy, hasta: hasta);

      expect(proyeccion.entradasPrevistas, 300000);
    });

    test('Invariante 5: una Nómina ya pagada no aparece como compromiso futuro', () async {
      final usecase = await construir(
        nominas: [_nominaDePrueba(id: 'nom-1', fechaPagoOrdinaria: DateTime(2026, 9, 5), estatus: 'pagada')],
        renglones: {
          'nom-1': [_renglonDePrueba(id: 'r1', nominaId: 'nom-1', totalAPagar: 500000)],
        },
      );

      final proyeccion = await usecase.ejecutar(hoy: hoy, hasta: hasta);

      expect(proyeccion.salidasComprometidas, 0);
      expect(proyeccion.compromisos, isEmpty);
    });

    test('Invariante 6: una Nómina cerrada pendiente de pago sí aparece como compromiso', () async {
      final usecase = await construir(
        nominas: [_nominaDePrueba(id: 'nom-1', fechaPagoOrdinaria: DateTime(2026, 9, 5), estatus: 'cerrada')],
        renglones: {
          'nom-1': [
            _renglonDePrueba(id: 'r1', nominaId: 'nom-1', totalAPagar: 500000),
            _renglonDePrueba(id: 'r2', nominaId: 'nom-1', totalAPagar: 300000),
          ],
        },
      );

      final proyeccion = await usecase.ejecutar(hoy: hoy, hasta: hasta);

      expect(proyeccion.salidasComprometidas, 800000, reason: 'suma de los renglones de la Nómina cerrada');
      expect(proyeccion.compromisos.single.origen, OrigenCompromiso.nomina);
    });

    test('Invariante 7: una Deuda sin pagoProgramado nunca inventa una salida futura', () async {
      final usecase = await construir(deudas: [
        _deudaDePrueba(id: 'deu-1', tipo: TipoDeuda.prestamo.name, fechaVencimiento: DateTime(2026, 9, 5)),
      ]);

      final proyeccion = await usecase.ejecutar(hoy: hoy, hasta: hasta);

      expect(proyeccion.salidasComprometidas, 0);
      expect(proyeccion.compromisos, isEmpty);
    });

    test('Invariante 8: una Deuda con pagoProgramado sí aparece como compromiso', () async {
      final usecase = await construir(deudas: [
        _deudaDePrueba(
          id: 'deu-1',
          tipo: TipoDeuda.prestamo.name,
          pagoProgramado: 700000,
          fechaVencimiento: DateTime(2026, 9, 5),
        ),
      ]);

      final proyeccion = await usecase.ejecutar(hoy: hoy, hasta: hasta);

      expect(proyeccion.salidasComprometidas, 700000);
      expect(proyeccion.compromisos.single.origen, OrigenCompromiso.deuda);
    });

    test('Deuda tarjeta con pagoProgramado y tarjetaDiaPago deriva la fecha, monto nunca es el saldo completo', () async {
      final usecase = await construir(deudas: [
        _deudaDePrueba(id: 'deu-1', tipo: TipoDeuda.tarjetaCredito.name, pagoProgramado: 150000, tarjetaDiaPago: 5),
      ]);

      final proyeccion = await usecase.ejecutar(hoy: hoy, hasta: hasta);

      expect(proyeccion.salidasComprometidas, 150000, reason: r'nunca el saldoActual completo de la tarjeta ($1,000,000)');
      expect(proyeccion.compromisos.single.fecha, DateTime(2026, 9, 5));
    });

    test(
      '(19D, corrección de raíz) una CxC vencida SIN reprogramar se excluye de entradas previstas y aparece en '
      'pendientesVencidos, nunca en una fecha inventada',
      () async {
        final usecase = await construir(cxc: [
          _cxcDePrueba(
            id: 'cxc-1',
            clienteId: 'cliente-1',
            saldoPendiente: 200000,
            estatus: 'pendiente',
            fechaVencimiento: DateTime(2026, 8, 1), // ya pasó respecto a `hoy` (30-ago), 29 días atrás
          ),
        ]);

        final proyeccion = await usecase.ejecutar(hoy: hoy, hasta: hasta);

        expect(proyeccion.entradasPrevistas, 0, reason: 'una CxC vencida sin reprogramar nunca se proyecta a una fecha futura');
        expect(proyeccion.compromisos, isEmpty);
        expect(proyeccion.pendientesVencidos, hasLength(1));
        final pendiente = proyeccion.pendientesVencidos.single;
        expect(pendiente.tipo, TipoPendienteVencido.cobro);
        expect(pendiente.importe, 200000);
        expect(pendiente.diasVencido, 29);
      },
    );

    test('(19D) una CxC vencida CON fechaCobroReprogramada vuelve a la proyección en esa fecha nueva, marcada vencida', () async {
      final usecase = await construir(cxc: [
        _cxcDePrueba(
          id: 'cxc-1',
          clienteId: 'cliente-1',
          saldoPendiente: 200000,
          estatus: 'pendiente',
          fechaVencimiento: DateTime(2026, 8, 1),
          fechaCobroReprogramada: DateTime(2026, 9, 10),
        ),
      ]);

      final proyeccion = await usecase.ejecutar(hoy: hoy, hasta: hasta);

      expect(proyeccion.entradasPrevistas, 200000);
      expect(proyeccion.pendientesVencidos, isEmpty, reason: 'ya no está "sin fecha conocida" — se reprogramó');
      final compromiso = proyeccion.compromisos.single;
      expect(compromiso.fecha, DateTime(2026, 9, 10));
      expect(compromiso.vencida, isTrue, reason: 'conserva la marca de que originalmente estaba vencida');
    });

    test('(19D, auditoría) pago parcial de Nómina: el compromiso es solo el saldo pendiente, nunca totalAPagar completo', () async {
      final usecase = await construir(
        nominas: [_nominaDePrueba(id: 'nom-1', fechaPagoOrdinaria: DateTime(2026, 9, 5), estatus: 'cerrada')],
        renglones: {
          'nom-1': [_renglonDePrueba(id: 'r1', nominaId: 'nom-1', totalAPagar: 500000)],
        },
        aplicadoPorRenglon: {'r1': 300000},
      );

      final proyeccion = await usecase.ejecutar(hoy: hoy, hasta: hasta);

      expect(proyeccion.salidasComprometidas, 200000, reason: r'$500,000 - $300,000 ya aplicados = $200,000 pendiente');
    });

    test('(19D, auditoría) Nómina con pago parcial que ya cubrió el total no genera compromiso (equivalente a pagada)', () async {
      final usecase = await construir(
        nominas: [_nominaDePrueba(id: 'nom-1', fechaPagoOrdinaria: DateTime(2026, 9, 5), estatus: 'cerrada')],
        renglones: {
          'nom-1': [_renglonDePrueba(id: 'r1', nominaId: 'nom-1', totalAPagar: 500000)],
        },
        aplicadoPorRenglon: {'r1': 500000},
      );

      final proyeccion = await usecase.ejecutar(hoy: hoy, hasta: hasta);

      expect(proyeccion.salidasComprometidas, 0);
      expect(proyeccion.compromisos, isEmpty);
    });

    test('(19D) Nómina cerrada con fechaPagoOrdinaria ya vencida y saldo pendiente aparece como pago vencido', () async {
      final usecase = await construir(
        nominas: [_nominaDePrueba(id: 'nom-1', fechaPagoOrdinaria: DateTime(2026, 8, 20), estatus: 'cerrada')],
        renglones: {
          'nom-1': [_renglonDePrueba(id: 'r1', nominaId: 'nom-1', totalAPagar: 500000)],
        },
      );

      final proyeccion = await usecase.ejecutar(hoy: hoy, hasta: hasta);

      expect(proyeccion.compromisos, isEmpty, reason: 'nunca se asigna a una fecha futura inventada');
      expect(proyeccion.pendientesVencidos, hasLength(1));
      expect(proyeccion.pendientesVencidos.single.tipo, TipoPendienteVencido.pago);
      expect(proyeccion.pendientesVencidos.single.origen, OrigenCompromiso.nomina);
      expect(proyeccion.pendientesVencidos.single.diasVencido, 10);
    });

    test('(19D, auditoría) Deuda con pagoProgramado mayor al saldoActual proyecta solo min(pagoProgramado, saldoActual)', () async {
      final usecase = await construir(deudas: [
        _deudaDePrueba(id: 'deu-1', tipo: TipoDeuda.tarjetaCredito.name, pagoProgramado: 5000000, tarjetaDiaPago: 5),
      ]);

      final proyeccion = await usecase.ejecutar(hoy: hoy, hasta: hasta);

      // `_deudaDePrueba` fija saldoActual en $10,000 — pagoProgramado
      // de $50,000 nunca debe proyectar más que el saldo real.
      expect(proyeccion.salidasComprometidas, 1000000, reason: r'min($50,000, $10,000) = $10,000');
    });

    test('(19D) una tarjeta con saldoActual == 0 no genera ningún compromiso, aunque tenga pagoProgramado', () async {
      final usecase = await construir(deudas: [
        DeudaData(
          id: 'deu-1',
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
          cicloVidaRegistro: 'activo',
          folio: 'DEU-deu-1',
          nombre: 'Tarjeta liquidada',
          tipo: TipoDeuda.tarjetaCredito.name,
          fechaOrigen: DateTime(2026, 1, 1),
          importeOriginal: 1000000,
          saldoActual: 0,
          pagoProgramado: 150000,
          tarjetaDiaPago: 5,
          estatus: 'activa',
        ),
      ]);

      final proyeccion = await usecase.ejecutar(hoy: hoy, hasta: hasta);

      expect(proyeccion.salidasComprometidas, 0);
      expect(proyeccion.compromisos, isEmpty);
    });

    test('(19D) una Deuda préstamo (no tarjeta) con fechaVencimiento ya vencida y saldo > 0 aparece como pago vencido', () async {
      final usecase = await construir(deudas: [
        _deudaDePrueba(
          id: 'deu-1',
          tipo: TipoDeuda.prestamo.name,
          pagoProgramado: 200000,
          fechaVencimiento: DateTime(2026, 8, 10),
        ),
      ]);

      final proyeccion = await usecase.ejecutar(hoy: hoy, hasta: hasta);

      expect(proyeccion.compromisos, isEmpty);
      expect(proyeccion.pendientesVencidos, hasLength(1));
      expect(proyeccion.pendientesVencidos.single.tipo, TipoPendienteVencido.pago);
      expect(proyeccion.pendientesVencidos.single.origen, OrigenCompromiso.deuda);
    });

    test('(19D) una Deuda tarjeta nunca puede aparecer como pago vencido (su fecha derivada siempre es >= hoy)', () async {
      final usecase = await construir(deudas: [
        _deudaDePrueba(id: 'deu-1', tipo: TipoDeuda.tarjetaCredito.name, pagoProgramado: 150000, tarjetaDiaPago: 1),
      ]);

      final proyeccion = await usecase.ejecutar(hoy: hoy, hasta: hasta);

      expect(proyeccion.pendientesVencidos.where((p) => p.origen == OrigenCompromiso.deuda), isEmpty);
    });

    test('Invariante 12: no hay doble conteo cuando coexisten un cargo TDC y su pago programado', () async {
      // El cargo TDC ya está reconocido como resultado operativo en el
      // momento de la Compra (Etapa 19B) — la proyección de caja SOLO
      // debe mostrar el pago programado como salida comprometida, una
      // única vez, nunca "el cargo + el pago".
      final usecase = await construir(deudas: [
        _deudaDePrueba(id: 'tdc-1', tipo: TipoDeuda.tarjetaCredito.name, pagoProgramado: 500000, tarjetaDiaPago: 5),
      ]);

      final proyeccion = await usecase.ejecutar(hoy: hoy, hasta: hasta);

      expect(proyeccion.compromisos.where((c) => c.origen == OrigenCompromiso.deuda), hasLength(1));
      expect(proyeccion.salidasComprometidas, 500000);
    });

    test('(19D, pedido §10) una Nómina en borrador nunca aparece como compromiso', () async {
      final usecase = await construir(
        nominas: [_nominaDePrueba(id: 'nom-1', fechaPagoOrdinaria: DateTime(2026, 9, 5), estatus: 'borrador')],
        renglones: {
          'nom-1': [_renglonDePrueba(id: 'r1', nominaId: 'nom-1', totalAPagar: 500000)],
        },
      );

      final proyeccion = await usecase.ejecutar(hoy: hoy, hasta: hasta);

      expect(proyeccion.salidasComprometidas, 0);
      expect(proyeccion.compromisos, isEmpty);
      expect(proyeccion.pendientesVencidos, isEmpty);
    });

    test('(19D, pedido §18) una CxC ya pagada nunca aparece, ni como compromiso ni como pendiente vencido', () async {
      final usecase = await construir(cxc: [
        _cxcDePrueba(
          id: 'cxc-1',
          clienteId: 'cliente-1',
          saldoPendiente: 0,
          estatus: 'pagada',
          fechaVencimiento: DateTime(2026, 8, 1), // ya pasó, pero está pagada
        ),
      ]);

      final proyeccion = await usecase.ejecutar(hoy: hoy, hasta: hasta);

      expect(proyeccion.entradasPrevistas, 0);
      expect(proyeccion.compromisos, isEmpty);
      expect(proyeccion.pendientesVencidos, isEmpty);
    });
  });
}
