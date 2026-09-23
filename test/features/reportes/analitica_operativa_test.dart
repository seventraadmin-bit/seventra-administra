// Rediseño de Reportes — capa analítica.
//
// Prueba las tres piezas nuevas del dominio y, sobre todo, la regla
// §16 del pedido: KPI, gráfica y composición tienen que salir del mismo
// cálculo. No basta con que "den parecido" — la suma de las barras debe
// ser exactamente el KPI.
//
// Incluye la demostración del hallazgo que motivó la capa: Reportes →
// General calculaba el Resultado operativo con una fórmula distinta a
// la de Finanzas → Resumen y contaba dos veces el gasto con tarjeta.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/compras/domain/repositories/compra_repository.dart';
import 'package:riseg_one/features/compras/domain/usecases/cancelar_compra_usecase.dart';
import 'package:riseg_one/features/compras/domain/usecases/registrar_compra_usecase.dart';
import 'package:riseg_one/features/compras/presentation/compras_controller.dart';
import 'package:riseg_one/features/finanzas/data/tables/deuda_table.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_deuda_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_egreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_ingreso_manual_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_pago_deuda_usecase.dart';
import 'package:riseg_one/features/finanzas/finanzas_providers.dart';
import 'package:riseg_one/features/finanzas/presentation/resumen/resumen_financiero_controller.dart';
import 'package:riseg_one/features/reportes/domain/analitica/comparacion_periodo.dart';
import 'package:riseg_one/features/reportes/domain/analitica/granularidad_serie.dart';
import 'package:riseg_one/features/reportes/domain/analitica/obtener_analisis_operativo_usecase.dart';
import 'package:riseg_one/features/reportes/domain/usecases/clasificar_egresos_por_origen_usecase.dart';
import 'package:riseg_one/features/reportes/reportes_providers.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import '../../support/sesion_en_base.dart';

class _SesionMaestroDePrueba extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-maestro',
      nombre: 'Maestro de prueba',
      nombreUsuario: 'maestro',
      esMaestro: true,
      permisos: {},
    );
  }
}

void main() {
  group('VariacionPeriodo — §5, comparación honesta', () {
    test('anterior = 0 no produce infinito: se declara sin base comparable', () {
      const v = VariacionPeriodo(actual: 500000, anterior: 0, sentido: SentidoFavorable.masEsMejor);

      expect(v.porcentaje, isNull, reason: 'nunca +∞ % ni un +100 % que fingiría una base inexistente');
      expect(v.sinBaseComparable, isTrue);
      expect(v.delta, 500000, reason: 'el cambio absoluto SÍ es real y sí se puede mostrar');
    });

    test('ambos en cero también es sin base comparable, no "0 %"', () {
      const v = VariacionPeriodo(actual: 0, anterior: 0, sentido: SentidoFavorable.masEsMejor);
      expect(v.sinBaseComparable, isTrue);
      expect(v.porcentaje, isNull);
    });

    test('subir NO siempre es favorable: el sentido lo decide cada indicador', () {
      const ingresos = VariacionPeriodo(actual: 120, anterior: 100, sentido: SentidoFavorable.masEsMejor);
      const gasto = VariacionPeriodo(actual: 120, anterior: 100, sentido: SentidoFavorable.menosEsMejor);
      const compras = VariacionPeriodo(actual: 120, anterior: 100, sentido: SentidoFavorable.neutro);

      expect(ingresos.tono, TonoVariacion.favorable);
      expect(gasto.tono, TonoVariacion.desfavorable, reason: 'que suba el gasto nunca se pinta como una buena noticia');
      expect(compras.tono, TonoVariacion.neutro);
      expect(ingresos.porcentaje, closeTo(0.20, 0.0001));
    });

    test('bajar el gasto es favorable; bajar los ingresos no', () {
      const gasto = VariacionPeriodo(actual: 80, anterior: 100, sentido: SentidoFavorable.menosEsMejor);
      const ingresos = VariacionPeriodo(actual: 80, anterior: 100, sentido: SentidoFavorable.masEsMejor);

      expect(gasto.tono, TonoVariacion.favorable);
      expect(ingresos.tono, TonoVariacion.desfavorable);
    });

    test('sin cambio nunca se pinta con color de juicio', () {
      const v = VariacionPeriodo(actual: 100, anterior: 100, sentido: SentidoFavorable.menosEsMejor);
      expect(v.sinCambio, isTrue);
      expect(v.tono, TonoVariacion.neutro);
      expect(v.porcentaje, 0);
    });

    test('con base negativa el porcentaje usa el valor absoluto (un resultado que mejora sube)', () {
      // Resultado operativo pasó de -$1,000 a -$500: mejoró $500.
      const v = VariacionPeriodo(actual: -50000, anterior: -100000, sentido: SentidoFavorable.masEsMejor);
      expect(v.delta, 50000);
      expect(v.porcentaje, closeTo(0.5, 0.0001), reason: 'dividir entre |anterior| evita que el signo invierta la lectura');
      expect(v.tono, TonoVariacion.favorable);
    });
  });

  group('RangoPeriodo — periodo anterior de la misma longitud', () {
    test('un mes completo compara contra el mes anterior completo', () {
      final septiembre = RangoPeriodo(inicio: _d(2026, 9, 1), fin: _d(2026, 9, 30));
      expect(septiembre.dias, 30);

      final anterior = septiembre.anterior;
      expect(anterior.fin, DateTime(2026, 8, 31));
      expect(anterior.inicio, DateTime(2026, 8, 2), reason: '30 días hacia atrás desde el 31 de agosto');
      expect(anterior.dias, septiembre.dias, reason: 'misma longitud SIEMPRE — es lo que hace comparable la cifra');
    });

    test('medio mes compara contra los 15 días previos, no contra el mes anterior completo', () {
      final quincena = RangoPeriodo(inicio: _d(2026, 9, 1), fin: _d(2026, 9, 15));
      final anterior = quincena.anterior;

      expect(anterior.inicio, DateTime(2026, 8, 17));
      expect(anterior.fin, DateTime(2026, 8, 31));
      expect(anterior.dias, 15, reason: 'comparar 15 días contra 31 fabricaría una caída del 50 % inexistente');
    });

    test('un solo día mide 1 día, no 0', () {
      final unDia = RangoPeriodo(inicio: _d(2026, 9, 10), fin: _d(2026, 9, 10));
      expect(unDia.dias, 1);
      expect(unDia.anterior.inicio, DateTime(2026, 9, 9));
      expect(unDia.anterior.fin, DateTime(2026, 9, 9));
    });
  });

  group('GranularidadSerie — §6, paso apropiado al rango', () {
    test('rangos cortos por día, medianos por semana, largos por mes', () {
      expect(GranularidadSerie.paraRango(RangoPeriodo(inicio: _d(2026, 9, 1), fin: _d(2026, 9, 30))),
          GranularidadSerie.dia);
      expect(GranularidadSerie.paraRango(RangoPeriodo(inicio: _d(2026, 1, 1), fin: _d(2026, 6, 30))),
          GranularidadSerie.semana);
      expect(GranularidadSerie.paraRango(RangoPeriodo(inicio: _d(2026, 1, 1), fin: _d(2026, 12, 31))),
          GranularidadSerie.mes);
    });

    test('ninguna granularidad produce más de 45 barras en su tramo', () {
      for (final rango in [
        RangoPeriodo(inicio: _d(2026, 8, 1), fin: _d(2026, 9, 14)), // 45 días
        RangoPeriodo(inicio: _d(2026, 1, 1), fin: _d(2026, 11, 11)), // 315 días
        RangoPeriodo(inicio: _d(2020, 1, 1), fin: _d(2026, 12, 31)), // 7 años
      ]) {
        final paso = GranularidadSerie.paraRango(rango);
        expect(paso.cubetas(rango).length, lessThanOrEqualTo(90), reason: 'rango de ${rango.dias} días con paso $paso');
      }
    });

    test('la cubeta semanal siempre cae en lunes y absorbe toda la semana', () {
      // 2026-09-10 es jueves.
      final jueves = DateTime(2026, 9, 10, 17, 45);
      final domingo = DateTime(2026, 9, 13, 23, 59);
      final lunesSiguiente = DateTime(2026, 9, 14, 0, 1);

      final cubetaJueves = GranularidadSerie.semana.cubetaDe(jueves);
      expect(cubetaJueves, DateTime(2026, 9, 7));
      expect(cubetaJueves.weekday, DateTime.monday);
      expect(GranularidadSerie.semana.cubetaDe(domingo), cubetaJueves, reason: 'el domingo cierra la MISMA semana');
      expect(GranularidadSerie.semana.cubetaDe(lunesSiguiente), DateTime(2026, 9, 14));
    });

    test('la hora nunca separa dos movimientos del mismo día', () {
      final temprano = DateTime(2026, 9, 10, 0, 10);
      final tarde = DateTime(2026, 9, 10, 23, 50);
      expect(GranularidadSerie.dia.cubetaDe(temprano), GranularidadSerie.dia.cubetaDe(tarde));
    });

    test('las cubetas cubren el rango completo SIN huecos', () {
      final rango = RangoPeriodo(inicio: _d(2026, 9, 1), fin: _d(2026, 9, 30));
      final cubetas = GranularidadSerie.dia.cubetas(rango);

      expect(cubetas, hasLength(30), reason: 'un día sin movimiento sigue siendo un día — saltarlo mentiría sobre el ritmo');
      expect(cubetas.first, DateTime(2026, 9, 1));
      expect(cubetas.last, DateTime(2026, 9, 30));
    });

    test('un rango que cruza el fin de año no se rompe ni se duplica', () {
      final rango = RangoPeriodo(inicio: _d(2025, 12, 15), fin: _d(2026, 1, 15));
      final cubetas = GranularidadSerie.dia.cubetas(rango);
      expect(cubetas, hasLength(32));
      expect(cubetas.toSet(), hasLength(32), reason: 'sin fechas repetidas');
      expect(cubetas[17], DateTime(2026, 1, 1));
    });
  });

  group('ObtenerAnalisisOperativoUseCase — §16, una sola fuente de verdad', () {
    late AppDatabase db;
    late ProviderContainer container;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await db.into(db.usuario).insert(
            UsuarioCompanion.insert(
              id: const Value('usuario-maestro'),
              nombre: 'Maestro de prueba',
              nombreUsuario: 'usuario-maestro',
              passwordHash: 'x',
            ),
          );
      container = ProviderContainer(overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionMaestroDePrueba.new),
      ]);
      // Etapa 3B: autorizar revalida contra la base, así que la
      // sesión de esta prueba tiene que corresponder a una cuenta real.
      await sembrarSesionEnBase(db, SesionUsuario( usuarioId: 'usuario-maestro', nombre: 'Maestro de prueba', nombreUsuario: 'maestro', esMaestro: true, permisos: {}, ));
    });

    tearDown(() {
      container.dispose();
      db.close();
    });

    // El rango vive en el mes en curso porque los controladores reales
    // (`ResumenFinancieroController`) arrancan siempre en el mes actual;
    // fijar un mes del pasado haría que la prueba de paridad comparara
    // rangos distintos y pasara por accidente.
    final hoy = DateTime.now();
    final rango = RangoPeriodo(inicio: DateTime(hoy.year, hoy.month, 1), fin: DateTime(hoy.year, hoy.month + 1, 0));
    final fechaDentro = DateTime(hoy.year, hoy.month, 2, 10);

    Future<void> ingreso(int monto, DateTime fecha) async {
      final r = await container.read(registrarIngresoManualUseCaseProvider).ejecutar(
            monto: monto,
            fecha: fecha,
            formaPago: 'transferencia',
            concepto: 'Cobro de servicio',
          );
      expect(r, isA<RegistrarIngresoManualExitoso>());
    }

    Future<void> egresoEnEfectivo(int monto, DateTime fecha, {String concepto = 'Gasto de oficina'}) async {
      final r = await container.read(registrarEgresoUseCaseProvider).ejecutar(
            monto: monto,
            fecha: fecha,
            formaPago: 'transferencia',
            concepto: concepto,
          );
      expect(r, isA<RegistrarEgresoExitoso>());
    }

    Future<DeudaData> crearTarjeta({int limite = 50000000, int saldoInicial = 1}) async {
      final r = await container.read(registrarDeudaAutorizadoProvider)(
        nombre: 'TDC BBVA',
        tipo: TipoDeuda.tarjetaCredito.name,
        fechaOrigen: DateTime(hoy.year, 1, 1),
        importeOriginal: limite,
        saldoInicial: saldoInicial,
        tarjetaLimiteCredito: limite,
      );
      return (r as RegistrarDeudaExitoso).deuda;
    }

    Future<void> comprarConTarjeta(String deudaId, int monto, DateTime fecha) async {
      final r = await container.read(comprasControllerProvider.notifier).registrarCompra(
            fecha: fecha,
            formaPago: 'tarjeta',
            deudaId: deudaId,
            partidas: [
              PartidaCompraInput(destino: 'gastoDirecto', concepto: 'Uniformes', cantidad: 1, costoUnitario: monto),
            ],
          );
      expect(r, isA<RegistrarCompraExitosa>());
    }

    Future<AnalisisOperativoPeriodo> analizar({GranularidadSerie? granularidad}) {
      return container
          .read(obtenerAnalisisOperativoUseCaseProvider)
          .ejecutar(rango: rango, granularidad: granularidad);
    }

    test('la suma de las barras es EXACTAMENTE el KPI (ingresos, gasto y resultado)', () async {
      await ingreso(1000000, fechaDentro);
      await ingreso(250000, fechaDentro.add(const Duration(days: 3)));
      await egresoEnEfectivo(300000, fechaDentro);
      await egresoEnEfectivo(120000, fechaDentro.add(const Duration(days: 5)));
      final tarjeta = await crearTarjeta();
      await comprarConTarjeta(tarjeta.id, 400000, fechaDentro.add(const Duration(days: 1)));

      final a = await analizar(granularidad: GranularidadSerie.dia);

      final sumaIngresos = a.puntos.fold<int>(0, (acc, p) => acc + p.ingresos);
      final sumaGasto = a.puntos.fold<int>(0, (acc, p) => acc + p.gastoOperativo);
      final sumaResultado = a.puntos.fold<int>(0, (acc, p) => acc + p.resultado);

      expect(sumaIngresos, a.ingresos, reason: 'KPI de Ingresos = suma de la serie');
      expect(sumaGasto, a.gastoOperativo, reason: 'KPI de gasto operativo = suma de la serie');
      expect(sumaResultado, a.resultadoOperativo);
      expect(a.ingresos, 1250000);
      expect(a.gastoOperativo, 820000, reason: r'$3,000 + $1,200 en efectivo + $4,000 cargados a la tarjeta');
    });

    test('la composición del gasto suma exactamente el gasto operativo', () async {
      await egresoEnEfectivo(300000, fechaDentro);
      final tarjeta = await crearTarjeta();
      await comprarConTarjeta(tarjeta.id, 400000, fechaDentro);

      final a = await analizar();

      final sumaComposicion = a.composicion.fold<int>(0, (acc, c) => acc + c.importe);
      expect(sumaComposicion, a.gastoOperativo, reason: 'la barra de composición no puede quedarle corta al KPI');
      expect(a.composicion.map((c) => c.origen), contains(OrigenEgreso.compra));
      expect(a.composicion.map((c) => c.origen), contains(OrigenEgreso.manual));
      expect(a.composicion.first.importe, greaterThanOrEqualTo(a.composicion.last.importe),
          reason: 'ordenada de mayor a menor, para que la lectura empiece por lo que pesa');
    });

    test('gasto con TDC: el pago de la tarjeta NO lo cuenta una segunda vez', () async {
      final tarjeta = await crearTarjeta();
      await comprarConTarjeta(tarjeta.id, 500000, fechaDentro);

      final trasCompra = await analizar();
      expect(trasCompra.gastoOperativo, 500000, reason: 'el gasto se reconoce al comprar, aunque no haya salido caja');
      expect(trasCompra.salidasDeEfectivo, 0);

      final pago = await container.read(registrarPagoDeudaAutorizadoProvider)(
        deudaId: tarjeta.id,
        fecha: fechaDentro.add(const Duration(days: 2)),
        importe: 500000,
        formaPago: 'transferencia',
      );
      expect(pago, isA<RegistrarPagoDeudaExitoso>());

      final trasPago = await analizar(granularidad: GranularidadSerie.dia);

      expect(trasPago.gastoOperativo, 500000, reason: r'JAMÁS $10,000 — el peso ya estaba contado desde la compra');
      expect(trasPago.salidasDeEfectivo, 500000, reason: 'la salida de caja del pago sí es real y sí se registra');
      expect(trasPago.pagosDeDeuda, 500000);
      expect(trasPago.puntos.fold<int>(0, (acc, p) => acc + p.gastoOperativo), 500000,
          reason: 'y la gráfica tampoco pinta la barra doble');
      expect(trasPago.composicion.where((c) => c.origen == OrigenEgreso.deuda), isEmpty,
          reason: 'pagar una deuda no es una categoría de gasto');
    });

    test('cancelar una compra con TDC deja el gasto operativo neto en cero', () async {
      final tarjeta = await crearTarjeta();
      await comprarConTarjeta(tarjeta.id, 700000, fechaDentro);
      final compra = (await db.select(db.compra).get()).single;

      final cancelada = await container.read(comprasControllerProvider.notifier).cancelarCompra(
            compraId: compra.id,
            motivo: MotivoCancelacionCompra.proveedorCancelo,
          );
      expect(cancelada, isA<CancelarCompraExitosa>());

      final a = await analizar(granularidad: GranularidadSerie.dia);
      expect(a.gastoOperativo, 0, reason: 'el ajuste que revierte el cargo netea contra el cargo original');
      expect(a.puntos.fold<int>(0, (acc, p) => acc + p.gastoOperativo), 0);
    });

    test('margen operativo sin ingresos es indefinido, nunca cero ni −100 %', () async {
      await egresoEnEfectivo(300000, fechaDentro);

      final a = await analizar();
      expect(a.ingresos, 0);
      expect(a.margenOperativo, isNull, reason: 'la UI debe decir "sin base", no pintar un margen falso');
      expect(a.resultadoOperativo, -300000, reason: 'el resultado absoluto sí existe y sí se muestra');
    });

    test('margen operativo con ingresos es la fracción real', () async {
      await ingreso(1000000, fechaDentro);
      await egresoEnEfectivo(800000, fechaDentro);

      final a = await analizar();
      expect(a.margenOperativo, closeTo(0.2, 0.0001));
    });

    test('un periodo sin ningún movimiento devuelve la serie completa en ceros, no una lista vacía', () async {
      final a = await analizar(granularidad: GranularidadSerie.dia);

      expect(a.puntos, isNotEmpty, reason: 'el empty state lo decide la UI mirando los totales, no la ausencia de cubetas');
      expect(a.puntos.every((p) => p.ingresos == 0 && p.gastoOperativo == 0), isTrue);
      expect(a.gastoOperativo, 0);
      expect(a.composicion, isEmpty, reason: 'nunca un componente en cero ocupando leyenda');
    });

    test('un movimiento capturado por la tarde del último día del rango NO se pierde', () async {
      final ultimoDia = DateTime(rango.fin.year, rango.fin.month, rango.fin.day, 18, 30);
      await ingreso(450000, ultimoDia);

      final a = await analizar(granularidad: GranularidadSerie.dia);
      expect(a.ingresos, 450000, reason: 'el rango se extiende al último instante del día, no a su medianoche');
      expect(a.puntos.last.ingresos, 450000);
    });

    test(
      'PARIDAD con Finanzas → Resumen: el mismo rango produce el mismo Resultado operativo '
      '(la divergencia que motivó esta capa)',
      () async {
        await ingreso(2000000, fechaDentro);
        await egresoEnEfectivo(450000, fechaDentro);
        final tarjeta = await crearTarjeta();
        await comprarConTarjeta(tarjeta.id, 600000, fechaDentro);
        await container.read(registrarPagoDeudaAutorizadoProvider)(
          deudaId: tarjeta.id,
          fecha: fechaDentro.add(const Duration(days: 1)),
          importe: 600000,
          formaPago: 'transferencia',
        );

        await container.read(resumenFinancieroControllerProvider.notifier).reintentarCarga();
        final finanzas = container.read(resumenFinancieroControllerProvider);
        final reportes = await analizar();

        expect(reportes.gastoOperativo, finanzas.egresosOperativos);
        expect(reportes.resultadoOperativo, finanzas.resultadoOperativo);
        expect(reportes.ingresos, finanzas.ingresosPeriodo);
        expect(reportes.salidasDeEfectivo, finanzas.egresosPeriodo);
        expect(reportes.pagosDeDeuda, finanzas.egresosDeuda);
        expect(reportes.cargosDeTarjeta, finanzas.cargosTarjetaPeriodo);
      },
    );

    test('totalCargadoEnRango es el fold de listarCargosEnRango — un solo predicado', () async {
      final tarjeta = await crearTarjeta();
      await comprarConTarjeta(tarjeta.id, 300000, fechaDentro);
      await comprarConTarjeta(tarjeta.id, 150000, fechaDentro.add(const Duration(days: 4)));

      final deudaRepo = container.read(deudaRepositoryProvider);
      final desde = DateTime(rango.inicio.year, rango.inicio.month, rango.inicio.day);
      final hasta = DateTime(rango.fin.year, rango.fin.month, rango.fin.day, 23, 59, 59, 999);

      final total = await deudaRepo.totalCargadoEnRango(rangoInicio: desde, rangoFin: hasta);
      final cargos = await deudaRepo.listarCargosEnRango(rangoInicio: desde, rangoFin: hasta);

      expect(cargos, hasLength(2));
      expect(cargos.fold<int>(0, (acc, c) => acc + c.importeNeto), total);
      expect(total, 450000);
      expect(cargos.every((c) => c.compraId != null), isTrue, reason: 'el origen se resuelve por FK, nunca por texto');
    });
  });
}

/// Azúcar para escribir fechas constantes en los grupos puros.
DateTime _d(int y, int m, int d) => DateTime(y, m, d);
