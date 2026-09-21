// Etapa "Tarjeta de crédito como línea revolvente" — cubre el ajuste
// pedido por Marlon: una TDC deja de tratarse como deuda fija (sin
// "importe original", saldo inicial + su propia fecha, crédito
// disponible como única fuente de verdad, regla explícita de fecha
// límite de pago con 2 variantes) sin romper préstamos/financiamientos
// existentes.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_financiera_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/tables/cuenta_financiera_table.dart';
import 'package:riseg_one/features/finanzas/data/tables/deuda_table.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/calcular_fecha_tarjeta_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/corregir_deuda_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/obtener_posicion_de_caja_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_deuda_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_pago_deuda_usecase.dart';
import 'package:riseg_one/features/finanzas/presentation/deudas_credito/deudas_credito_list_screen.dart' show contarProximosVencimientos;

void main() {
  late AppDatabase db;
  late DeudaRepositoryImpl deudaRepo;
  late RegistrarDeudaUseCase registrarDeuda;
  late RegistrarPagoDeudaUseCase registrarPago;
  late CorregirDeudaUseCase corregirDeuda;
  late CuentaFinancieraRepositoryImpl cuentaFinancieraRepo;
  late ObtenerPosicionDeCajaUseCase obtenerPosicionCaja;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    final egresoRepo = EgresoRepositoryImpl(db);
    deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    registrarDeuda = RegistrarDeudaUseCase(deudaRepo, generarCodigo);
    registrarPago = RegistrarPagoDeudaUseCase(deudaRepo, generarCodigo);
    corregirDeuda = CorregirDeudaUseCase(deudaRepo);
    cuentaFinancieraRepo = CuentaFinancieraRepositoryImpl(db);
    obtenerPosicionCaja = ObtenerPosicionDeCajaUseCase(cuentaFinancieraRepo);
  });

  tearDown(() => db.close());

  group('1. Alta de préstamo conserva el comportamiento actual', () {
    test('fechaOrigen/importeOriginal siguen siendo obligatorios para deuda fija', () async {
      final sinFecha = await registrarDeuda.ejecutar(
        nombre: 'Préstamo refacciones',
        tipo: TipoDeuda.prestamo.name,
        importeOriginal: 1000000,
        saldoInicial: 1000000,
      );
      expect(sinFecha, isA<RegistrarDeudaFechaOrigenRequerida>());

      final sinImporte = await registrarDeuda.ejecutar(
        nombre: 'Préstamo refacciones',
        tipo: TipoDeuda.prestamo.name,
        fechaOrigen: DateTime(2026, 1, 1),
        saldoInicial: 0,
      );
      expect(sinImporte, isA<RegistrarDeudaImporteInvalido>());
    });

    test('alta normal: saldoActual == importeOriginal, sin campos de tarjeta', () async {
      final resultado = await registrarDeuda.ejecutar(
        nombre: 'Préstamo refacciones',
        tipo: TipoDeuda.prestamo.name,
        fechaOrigen: DateTime(2026, 1, 1),
        importeOriginal: 1000000,
        saldoInicial: 1000000,
      );
      final deuda = (resultado as RegistrarDeudaExitoso).deuda;
      expect(deuda.importeOriginal, 1000000);
      expect(deuda.saldoActual, 1000000);
      expect(deuda.tarjetaLimiteCredito, isNull);
      expect(deuda.tarjetaReglaFechaPago, isNull);
    });
  });

  group('2. Alta de TDC con saldo inicial', () {
    test('sin importeOriginal/fechaOrigen — el MovimientoDeuda.altaInicial usa fechaSaldoInicial, no fechaOrigen', () async {
      final resultado = await registrarDeuda.ejecutar(
        nombre: 'Konfío empresarial',
        tipo: TipoDeuda.tarjetaCredito.name,
        saldoInicial: 3326608,
        fechaSaldoInicial: DateTime(2026, 9, 5),
        tarjetaLimiteCredito: 4000000,
        tarjetaUltimosDigitos: '4321',
      );
      final deuda = (resultado as RegistrarDeudaExitoso).deuda;
      expect(deuda.importeOriginal, isNull, reason: 'una TDC no tiene "importe original" real');
      expect(deuda.fechaOrigen, isNull, reason: 'no se capturó — nunca se inventa');
      expect(deuda.saldoActual, 3326608);

      final movimientos = await deudaRepo.listarMovimientos(deuda.id);
      expect(movimientos, hasLength(1));
      expect(movimientos.single.tipo, TipoMovimientoDeuda.altaInicial.name);
      expect(movimientos.single.fecha, DateTime(2026, 9, 5));
    });

    test('saldoInicial > 0 sin fechaSaldoInicial se rechaza — nunca se asume "hoy" en silencio', () async {
      final resultado = await registrarDeuda.ejecutar(
        nombre: 'Konfío empresarial',
        tipo: TipoDeuda.tarjetaCredito.name,
        saldoInicial: 3326608,
        tarjetaLimiteCredito: 4000000,
      );
      expect(resultado, isA<RegistrarDeudaFechaSaldoInicialRequerida>());
    });

    test('TDC nueva sin saldo previo (saldoInicial 0) no genera ningún MovimientoDeuda', () async {
      final resultado = await registrarDeuda.ejecutar(
        nombre: 'Clara empresarial',
        tipo: TipoDeuda.tarjetaCredito.name,
        saldoInicial: 0,
        tarjetaLimiteCredito: 5000000,
      );
      final deuda = (resultado as RegistrarDeudaExitoso).deuda;
      expect(deuda.saldoActual, 0);
      expect(await deudaRepo.listarMovimientos(deuda.id), isEmpty);
    });
  });

  test(
    '3. TDC con saldo inicial \$33,266.08 y límite \$40,000 produce disponible \$6,733.92',
    () async {
      final resultado = await registrarDeuda.ejecutar(
        nombre: 'Konfío empresarial',
        tipo: TipoDeuda.tarjetaCredito.name,
        saldoInicial: 3326608,
        fechaSaldoInicial: DateTime(2026, 9, 5),
        tarjetaLimiteCredito: 4000000,
      );
      final deuda = (resultado as RegistrarDeudaExitoso).deuda;
      final disponible = creditoDisponibleTarjeta(limiteCredito: deuda.tarjetaLimiteCredito, saldoActual: deuda.saldoActual);
      expect(disponible, 673392);
    },
  );

  test('4. Un pago posterior reduce el saldo y aumenta el disponible', () async {
    final creada = await registrarDeuda.ejecutar(
      nombre: 'Konfío empresarial',
      tipo: TipoDeuda.tarjetaCredito.name,
      saldoInicial: 3326608,
      fechaSaldoInicial: DateTime(2026, 9, 5),
      tarjetaLimiteCredito: 4000000,
    );
    final deuda = (creada as RegistrarDeudaExitoso).deuda;
    final disponibleAntes = creditoDisponibleTarjeta(limiteCredito: deuda.tarjetaLimiteCredito, saldoActual: deuda.saldoActual)!;

    final pagado = await registrarPago.ejecutar(
      deudaId: deuda.id,
      fecha: DateTime(2026, 9, 10),
      importe: 100000,
      formaPago: 'transferencia',
    );
    final deudaPagada = (pagado as RegistrarPagoDeudaExitoso).deuda;
    final disponibleDespues =
        creditoDisponibleTarjeta(limiteCredito: deudaPagada.tarjetaLimiteCredito, saldoActual: deudaPagada.saldoActual)!;

    expect(deudaPagada.saldoActual, 3226608);
    expect(disponibleDespues, disponibleAntes + 100000, reason: 'el disponible sube exactamente lo que se pagó');
  });

  test('5. El disponible de una TDC nunca se suma a la posición de caja', () async {
    await cuentaFinancieraRepo.crear(
      codigo: 'CTA-000001',
      nombre: 'BBVA Principal',
      tipo: TipoCuentaFinanciera.banco.name,
      saldoInicial: 500000,
      fechaSaldoInicial: DateTime(2026, 1, 1),
    );
    final antes = await obtenerPosicionCaja.ejecutar();
    expect(antes.configurada, isTrue);
    expect(antes.saldoDisponible, 500000);

    // Una TDC con un disponible enorme — no debe alterar ni un centavo
    // la posición de caja, que solo lee CuentaFinanciera.
    await registrarDeuda.ejecutar(
      nombre: 'Konfío empresarial',
      tipo: TipoDeuda.tarjetaCredito.name,
      saldoInicial: 0,
      tarjetaLimiteCredito: 100000000,
    );

    final despues = await obtenerPosicionCaja.ejecutar();
    expect(despues.saldoDisponible, 500000, reason: 'el crédito disponible de una tarjeta nunca es efectivo/saldo bancario');
  });

  group('6. Regla "día fijo del mes"', () {
    test('un día que ya pasó este mes rueda al mes siguiente', () {
      final hoy = DateTime(2026, 9, 20);
      final proxima = proximaFechaLimitePago(regla: ReglaFechaLimitePagoTarjeta.diaFijo.name, diaFijo: 7, hoy: hoy);
      expect(proxima, DateTime(2026, 10, 7));
    });

    test('un día que todavía no llega este mes se queda en el mes actual', () {
      final hoy = DateTime(2026, 9, 3);
      final proxima = proximaFechaLimitePago(regla: ReglaFechaLimitePagoTarjeta.diaFijo.name, diaFijo: 7, hoy: hoy);
      expect(proxima, DateTime(2026, 9, 7));
    });
  });

  group('7. Regla "N días después del corte"', () {
    test('corte 17 + 20 días naturales cruza correctamente de mes', () {
      final hoy = DateTime(2026, 9, 25);
      final proxima = proximaFechaDiasDespuesDeCorte(diaCorte: 17, diasDespuesCorte: 20, hoy: hoy);
      // Corte más reciente: 17/sep. 17/sep + 20 días = 7/oct.
      expect(proxima, DateTime(2026, 10, 7));
    });

    test('si la fecha límite del ciclo actual ya pasó, avanza al siguiente ciclo completo', () {
      final hoy = DateTime(2026, 10, 10);
      // Corte más reciente: 17/sep. 17/sep + 20 días = 7/oct — ya pasó.
      final proxima = proximaFechaDiasDespuesDeCorte(diaCorte: 17, diasDespuesCorte: 20, hoy: hoy);
      // Siguiente corte: 17/oct. 17/oct + 20 días = 6/nov.
      expect(proxima, DateTime(2026, 11, 6));
    });
  });

  group('8. Cruce diciembre → enero', () {
    test('regla día fijo: día 5 ya pasado en diciembre rueda a enero del año siguiente', () {
      final hoy = DateTime(2026, 12, 20);
      final proxima = proximaFechaLimitePago(regla: ReglaFechaLimitePagoTarjeta.diaFijo.name, diaFijo: 5, hoy: hoy);
      expect(proxima, DateTime(2027, 1, 5));
    });

    test('regla días después del corte: corte 25 + 15 días cruza de diciembre a enero', () {
      final hoy = DateTime(2026, 12, 28);
      final proxima = proximaFechaDiasDespuesDeCorte(diaCorte: 25, diasDespuesCorte: 15, hoy: hoy);
      // Corte más reciente: 25/dic. 25/dic + 15 días = 9/ene/2027.
      expect(proxima, DateTime(2027, 1, 9));
    });
  });

  test('9. Editar una TDC conserva saldoActual/tipo intactos y actualiza la regla de fecha de pago', () async {
    final creada = await registrarDeuda.ejecutar(
      nombre: 'Konfío empresarial',
      tipo: TipoDeuda.tarjetaCredito.name,
      fechaOrigen: DateTime(2024, 1, 1),
      saldoInicial: 3326608,
      fechaSaldoInicial: DateTime(2026, 9, 5),
      tarjetaLimiteCredito: 4000000,
      tarjetaDiaCorte: 17,
      tarjetaDiaPago: 7,
      tarjetaReglaFechaPago: ReglaFechaLimitePagoTarjeta.diaFijo.name,
    );
    final deuda = (creada as RegistrarDeudaExitoso).deuda;

    final editado = await corregirDeuda.ejecutar(
      deudaId: deuda.id,
      limpiarFechaOrigen: true,
      tarjetaReglaFechaPago: ReglaFechaLimitePagoTarjeta.diasDespuesDeCorte.name,
      tarjetaDiasDespuesCorte: 20,
    );
    final actualizada = (editado as CorregirDeudaExitoso).deuda;

    expect(actualizada.tipo, TipoDeuda.tarjetaCredito.name, reason: 'tipo nunca es editable');
    expect(actualizada.saldoActual, 3326608, reason: 'corregir nunca toca el saldo');
    expect(actualizada.tarjetaLimiteCredito, 4000000, reason: 'corregir no tocó el límite en esta llamada — debe conservarse');
    expect(actualizada.fechaOrigen, isNull, reason: '"no se conoce" debe poder limpiarse');
    expect(actualizada.tarjetaReglaFechaPago, ReglaFechaLimitePagoTarjeta.diasDespuesDeCorte.name);
    expect(actualizada.tarjetaDiasDespuesCorte, 20);

    // La CorregirDeudaUseCase no acepta `tipo`/`saldoInicial` en su
    // firma — no hay forma de intentar cambiarlos desde este caso de
    // uso (bloqueo estructural, no solo una validación).
  });

  group('10. Tasa fija/variable y CAT para TDC (caso real Konfío Empresarial)', () {
    test('alta de TDC con tasa variable + CAT — exactamente el caso real, nunca colapsado a un porcentaje falso', () async {
      final creada = await registrarDeuda.ejecutar(
        nombre: 'Konfío Empresarial',
        tipo: TipoDeuda.tarjetaCredito.name,
        saldoInicial: 0,
        tarjetaLimiteCredito: 4000000,
        tarjetaDiaCorte: 17,
        tarjetaReglaFechaPago: ReglaFechaLimitePagoTarjeta.diasDespuesDeCorte.name,
        tarjetaDiasDespuesCorte: 20,
        tarjetaTipoTasa: TipoTasaTarjeta.variable.name,
        tarjetaTasaReferencia: 'TIIE 28 días',
        tarjetaTasaDiferencial: 60.0,
        tarjetaTasaMasIva: true,
        tarjetaTasaDescripcion: 'TIIE a 28 días + 60 puntos porcentuales + IVA',
        tarjetaCat: 105.7,
        tarjetaCatIncluyeIva: false,
      );
      final deuda = (creada as RegistrarDeudaExitoso).deuda;

      expect(deuda.tarjetaTipoTasa, 'variable');
      expect(deuda.tasaInteres, isNull, reason: 'nunca se guarda un porcentaje fijo falso para una tasa variable');
      expect(deuda.tarjetaTasaReferencia, 'TIIE 28 días');
      expect(deuda.tarjetaTasaDiferencial, 60.0);
      expect(deuda.tarjetaTasaMasIva, isTrue);
      expect(deuda.tarjetaTasaDescripcion, 'TIIE a 28 días + 60 puntos porcentuales + IVA');
      expect(deuda.tarjetaCat, 105.7);
      expect(deuda.tarjetaCatIncluyeIva, isFalse, reason: 'CAT sin IVA — dato real de la carátula, nunca "60%"');

      final releida = await deudaRepo.obtenerPorId(deuda.id);
      expect(releida!.tarjetaTasaReferencia, 'TIIE 28 días', reason: 'se lee de vuelta sin pérdida');
      expect(releida.tarjetaCat, 105.7);
    });

    test('alta de TDC con tasa fija sigue funcionando igual que antes (regresión)', () async {
      final creada = await registrarDeuda.ejecutar(
        nombre: 'TDC BBVA',
        tipo: TipoDeuda.tarjetaCredito.name,
        saldoInicial: 0,
        tarjetaLimiteCredito: 5000000,
        tarjetaTipoTasa: TipoTasaTarjeta.fija.name,
        tasaInteres: 24.5,
      );
      final deuda = (creada as RegistrarDeudaExitoso).deuda;

      expect(deuda.tarjetaTipoTasa, 'fija');
      expect(deuda.tasaInteres, 24.5);
      expect(deuda.tarjetaTasaReferencia, isNull);
      expect(deuda.tarjetaTasaDiferencial, isNull);
      expect(deuda.tarjetaCat, isNull);
    });

    test('alta de TDC sin tasa capturada — ningún campo se inventa', () async {
      final creada = await registrarDeuda.ejecutar(
        nombre: 'TDC Santander',
        tipo: TipoDeuda.tarjetaCredito.name,
        saldoInicial: 0,
        tarjetaLimiteCredito: 2000000,
      );
      final deuda = (creada as RegistrarDeudaExitoso).deuda;

      expect(deuda.tarjetaTipoTasa, isNull);
      expect(deuda.tasaInteres, isNull);
      expect(deuda.tarjetaTasaReferencia, isNull);
      expect(deuda.tarjetaTasaDiferencial, isNull);
      expect(deuda.tarjetaTasaMasIva, isNull);
      expect(deuda.tarjetaCat, isNull);
      expect(deuda.tarjetaCatIncluyeIva, isNull);
    });

    test('préstamo/financiamiento: tasaInteres sigue funcionando exactamente igual, sin exposición a los campos nuevos', () async {
      final creada = await registrarDeuda.ejecutar(
        nombre: 'Préstamo refacciones',
        tipo: TipoDeuda.prestamo.name,
        fechaOrigen: DateTime(2026, 1, 1),
        importeOriginal: 1000000,
        saldoInicial: 1000000,
        tasaInteres: 18.5,
      );
      final deuda = (creada as RegistrarDeudaExitoso).deuda;

      expect(deuda.tasaInteres, 18.5);
      expect(deuda.tarjetaTipoTasa, isNull, reason: 'un préstamo nunca tiene tipo de tasa — ese concepto es exclusivo de tarjeta');
      expect(deuda.tarjetaCat, isNull);
    });

    test('edición de TDC: cambiar de tasa fija a variable limpia los campos de la fija y viceversa', () async {
      final creada = await registrarDeuda.ejecutar(
        nombre: 'Konfío Empresarial',
        tipo: TipoDeuda.tarjetaCredito.name,
        saldoInicial: 0,
        tarjetaLimiteCredito: 4000000,
        tarjetaTipoTasa: TipoTasaTarjeta.fija.name,
        tasaInteres: 24.5,
      );
      final deuda = (creada as RegistrarDeudaExitoso).deuda;

      final editadaAVariable = await corregirDeuda.ejecutar(
        deudaId: deuda.id,
        tarjetaTipoTasa: TipoTasaTarjeta.variable.name,
        limpiarTasaInteres: true,
        tarjetaTasaReferencia: 'TIIE 28 días',
        tarjetaTasaDiferencial: 60.0,
        tarjetaTasaMasIva: true,
      );
      final variable = (editadaAVariable as CorregirDeudaExitoso).deuda;
      expect(variable.tarjetaTipoTasa, 'variable');
      expect(variable.tasaInteres, isNull, reason: 'la tasa fija anterior debe limpiarse — nunca queda un 24.5% fantasma');
      expect(variable.tarjetaTasaReferencia, 'TIIE 28 días');
      expect(variable.tarjetaTasaDiferencial, 60.0);

      final editadaAFija = await corregirDeuda.ejecutar(
        deudaId: deuda.id,
        tarjetaTipoTasa: TipoTasaTarjeta.fija.name,
        tasaInteres: 30.0,
        limpiarTasaVariable: true,
      );
      final fija = (editadaAFija as CorregirDeudaExitoso).deuda;
      expect(fija.tarjetaTipoTasa, 'fija');
      expect(fija.tasaInteres, 30.0);
      expect(fija.tarjetaTasaReferencia, isNull, reason: 'la referencia variable anterior debe limpiarse — nunca queda TIIE fantasma');
      expect(fija.tarjetaTasaDiferencial, isNull);
      expect(fija.tarjetaTasaMasIva, isNull);
    });
  });

  group('11. proximaFechaPagoDeuda — única fuente de verdad para "Próximo pago" (corrección real: la '
      'columna del listado seguía usando fechaVencimiento, siempre null para una TDC)', () {
    test('deuda fija: usa fechaVencimiento tal cual, sin cambios', () async {
      final creada = await registrarDeuda.ejecutar(
        nombre: 'Préstamo refacciones',
        tipo: TipoDeuda.prestamo.name,
        fechaOrigen: DateTime(2026, 1, 1),
        importeOriginal: 1000000,
        saldoInicial: 1000000,
        fechaVencimiento: DateTime(2026, 10, 30),
      );
      final deuda = (creada as RegistrarDeudaExitoso).deuda;

      expect(proximaFechaPagoDeuda(deuda, DateTime(2026, 9, 5)), DateTime(2026, 10, 30));
    });

    test('deuda fija sin fechaVencimiento capturada: null, nunca se inventa', () async {
      final creada = await registrarDeuda.ejecutar(
        nombre: 'Préstamo refacciones',
        tipo: TipoDeuda.prestamo.name,
        fechaOrigen: DateTime(2026, 1, 1),
        importeOriginal: 1000000,
        saldoInicial: 1000000,
      );
      final deuda = (creada as RegistrarDeudaExitoso).deuda;

      expect(proximaFechaPagoDeuda(deuda, DateTime(2026, 9, 5)), isNull);
    });

    test('TDC regla día fijo: calcula la próxima fecha, incluye cruce de mes/año', () async {
      final creada = await registrarDeuda.ejecutar(
        nombre: 'TDC BBVA',
        tipo: TipoDeuda.tarjetaCredito.name,
        saldoInicial: 0,
        tarjetaLimiteCredito: 5000000,
        tarjetaReglaFechaPago: ReglaFechaLimitePagoTarjeta.diaFijo.name,
        tarjetaDiaPago: 5,
      );
      final deuda = (creada as RegistrarDeudaExitoso).deuda;

      expect(proximaFechaPagoDeuda(deuda, DateTime(2026, 9, 3)), DateTime(2026, 9, 5), reason: 'el día 5 todavía no llega en septiembre');
      expect(
        proximaFechaPagoDeuda(deuda, DateTime(2026, 12, 20)),
        DateTime(2027, 1, 5),
        reason: 'cruce diciembre → enero del año siguiente',
      );
    });

    test('TDC regla días después del corte (caso real Konfío: corte 17 + 20 días): calcula correctamente, incluye cruce de mes', () async {
      final creada = await registrarDeuda.ejecutar(
        nombre: 'Konfío Empresarial',
        tipo: TipoDeuda.tarjetaCredito.name,
        saldoInicial: 3326608,
        fechaSaldoInicial: DateTime(2026, 9, 5),
        tarjetaLimiteCredito: 4000000,
        tarjetaDiaCorte: 17,
        tarjetaReglaFechaPago: ReglaFechaLimitePagoTarjeta.diasDespuesDeCorte.name,
        tarjetaDiasDespuesCorte: 20,
      );
      final deuda = (creada as RegistrarDeudaExitoso).deuda;

      expect(
        proximaFechaPagoDeuda(deuda, DateTime(2026, 9, 25)),
        DateTime(2026, 10, 7),
        reason: 'corte más reciente 17/sep + 20 días = 7/oct',
      );
      expect(
        proximaFechaPagoDeuda(deuda, DateTime(2026, 12, 28)),
        DateTime(2027, 1, 6),
        reason: 'corte 17/dic + 20 días cruza a enero del año siguiente',
      );
    });

    test('TDC con configuración incompleta (sin regla capturada): null — nunca "Sin vencimiento" ni una fecha inventada', () async {
      final creada = await registrarDeuda.ejecutar(
        nombre: 'TDC nueva sin configurar',
        tipo: TipoDeuda.tarjetaCredito.name,
        saldoInicial: 0,
        tarjetaLimiteCredito: 2000000,
      );
      final deuda = (creada as RegistrarDeudaExitoso).deuda;

      expect(deuda.fechaVencimiento, isNull, reason: 'una TDC nunca usa fechaVencimiento');
      expect(proximaFechaPagoDeuda(deuda, DateTime(2026, 9, 5)), isNull);
    });

    test('KPI "Próximos vencimientos": una TDC con regla días-después-de-corte cuenta correctamente, y deuda fija no cambia', () {
      final hoy = DateTime(2026, 9, 25);

      final tarjetaProxima = DeudaData(
        id: 'tdc-1',
        createdAt: hoy,
        updatedAt: hoy,
        cicloVidaRegistro: 'activo',
        folio: 'DEU-000010',
        nombre: 'Konfío',
        tipo: TipoDeuda.tarjetaCredito.name,
        saldoActual: 3326608,
        estatus: EstatusDeuda.activa.name,
        tarjetaLimiteCredito: 4000000,
        tarjetaDiaCorte: 17,
        tarjetaReglaFechaPago: ReglaFechaLimitePagoTarjeta.diasDespuesDeCorte.name,
        tarjetaDiasDespuesCorte: 20,
      );
      final prestamoConVencimientoLejano = DeudaData(
        id: 'prestamo-1',
        createdAt: hoy,
        updatedAt: hoy,
        cicloVidaRegistro: 'activo',
        folio: 'DEU-000011',
        nombre: 'Préstamo Jessica',
        tipo: TipoDeuda.prestamo.name,
        saldoActual: 1000000,
        estatus: EstatusDeuda.activa.name,
        fechaVencimiento: DateTime(2027, 6, 1),
      );

      final proximosVencimientos = contarProximosVencimientos([tarjetaProxima, prestamoConVencimientoLejano], hoy);

      expect(proximosVencimientos, 1, reason: 'la TDC (7/oct) cae dentro de los 30 días — el préstamo (2027) no; antes la TDC nunca contaba');
    });
  });

  group(
    'KPI "Próximos vencimientos" — ventana estable sin ambigüedad de hora (corrección real: comparar '
    'contra ahora.add(Duration(days: 30)) SIN truncar la hora dejaba el resultado a merced del reloj)',
    () {
      DeudaData prestamoConVencimiento(String id, DateTime fechaVencimiento) => DeudaData(
            id: id,
            createdAt: fechaVencimiento,
            updatedAt: fechaVencimiento,
            cicloVidaRegistro: 'activo',
            folio: 'DEU-$id',
            nombre: 'Préstamo $id',
            tipo: TipoDeuda.prestamo.name,
            saldoActual: 1000000,
            estatus: EstatusDeuda.activa.name,
            fechaVencimiento: fechaVencimiento,
          );

      test('vencimiento exactamente hoy cuenta (extremo inferior incluido)', () {
        final ahora = DateTime(2026, 9, 7, 16, 45);
        final deuda = prestamoConVencimiento('hoy', DateTime(2026, 9, 7));
        expect(contarProximosVencimientos([deuda], ahora), 1);
      });

      test('vencimiento exactamente en el día +30 cuenta (extremo superior incluido)', () {
        final ahora = DateTime(2026, 9, 7, 16, 45);
        final deuda = prestamoConVencimiento('dia30', DateTime(2026, 10, 7));
        expect(contarProximosVencimientos([deuda], ahora), 1);
      });

      test('vencimiento en el día +31 NO cuenta', () {
        final ahora = DateTime(2026, 9, 7, 16, 45);
        final deuda = prestamoConVencimiento('dia31', DateTime(2026, 10, 8));
        expect(contarProximosVencimientos([deuda], ahora), 0);
      });

      test('ejecutar a distintas horas del mismo día siempre da el mismo resultado', () {
        // Antes de la corrección, un vencimiento exactamente en el día
        // +30 dependía de que "ahora" tuviera cualquier hora posterior
        // a medianoche de ese mismo día — aquí se prueba el caso más
        // exigente, el propio borde del día 30, a las 3 horas del
        // reloj más distintas posibles del mismo 07/09/2026.
        final deuda = prestamoConVencimiento('dia30', DateTime(2026, 10, 7));
        final horas = [DateTime(2026, 9, 7, 0, 0, 1), DateTime(2026, 9, 7, 12, 0), DateTime(2026, 9, 7, 23, 59, 59)];
        for (final ahora in horas) {
          expect(contarProximosVencimientos([deuda], ahora), 1, reason: 'la hora del reloj ($ahora) nunca debe cambiar el resultado');
        }
      });

      test(
        'caso real (07/09/2026, 6 deudas activas): cuenta TDC y deuda fija por igual, con proximaFechaPagoDeuda '
        'como única fuente — resultado 3, estable sin importar la hora',
        () {
          final claraTdc = DeudaData(
            id: 'clara',
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
            cicloVidaRegistro: 'activo',
            folio: 'DEU-clara',
            nombre: 'Clara',
            tipo: TipoDeuda.tarjetaCredito.name,
            saldoActual: 100000,
            estatus: EstatusDeuda.activa.name,
            tarjetaLimiteCredito: 2000000,
            tarjetaReglaFechaPago: ReglaFechaLimitePagoTarjeta.diaFijo.name,
            tarjetaDiaPago: 27, // → 27/09/2026
          );
          final konfioTdc = DeudaData(
            id: 'konfio',
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
            cicloVidaRegistro: 'activo',
            folio: 'DEU-konfio',
            nombre: 'Konfío',
            tipo: TipoDeuda.tarjetaCredito.name,
            saldoActual: 300000,
            estatus: EstatusDeuda.activa.name,
            tarjetaLimiteCredito: 4000000,
            tarjetaDiaCorte: 17,
            tarjetaReglaFechaPago: ReglaFechaLimitePagoTarjeta.diasDespuesDeCorte.name,
            tarjetaDiasDespuesCorte: 20, // → 07/10/2026 (borde superior)
          );
          final danielPrestamo = prestamoConVencimiento('daniel', DateTime(2026, 9, 30));
          final sandraPrestamo = prestamoConVencimiento('sandra-prestamo', DateTime(2026, 10, 30));
          final sandraFinanciamiento = DeudaData(
            id: 'sandra-bbva',
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
            cicloVidaRegistro: 'activo',
            folio: 'DEU-sandra-bbva',
            nombre: 'Sandra BBVA',
            tipo: TipoDeuda.financiamiento.name,
            saldoActual: 1000000,
            estatus: EstatusDeuda.activa.name,
            fechaVencimiento: DateTime(2026, 11, 30),
          );
          final jessicaPrestamo = prestamoConVencimiento('jessica', DateTime(2027, 2, 28));

          final deudas = [claraTdc, konfioTdc, danielPrestamo, sandraPrestamo, sandraFinanciamiento, jessicaPrestamo];

          for (final ahora in [DateTime(2026, 9, 7, 0, 30), DateTime(2026, 9, 7, 13, 0), DateTime(2026, 9, 7, 23, 30)]) {
            expect(
              contarProximosVencimientos(deudas, ahora),
              3,
              reason: 'Clara (27/sep) + Daniel (30/sep) + Konfío (7/oct, borde) — Sandra préstamo/BBVA y Jessica quedan fuera, sin importar la hora',
            );
          }
        },
      );
    },
  );

  group('12. Ciclo de TDC — reconciliación de apertura y avance automático (caso real Konfío)', () {
    test(
      'sin conciliar, el 05/09/2026 calcula 06/09/2026 (ciclo anterior) — el mismo caso YA conciliado calcula 07/10/2026',
      () {
        final hoy = DateTime(2026, 9, 5);
        final sinConciliar = proximaFechaLimitePago(
          regla: ReglaFechaLimitePagoTarjeta.diasDespuesDeCorte.name,
          diaCorte: 17,
          diasDespuesCorte: 20,
          hoy: hoy,
        );
        expect(sinConciliar, DateTime(2026, 9, 6), reason: 'ese pago ya se hizo en la vida real ANTES de capturar los saldos en RISEG ONE');

        final conciliado = proximaFechaLimitePago(
          regla: ReglaFechaLimitePagoTarjeta.diasDespuesDeCorte.name,
          diaCorte: 17,
          diasDespuesCorte: 20,
          hoy: hoy,
          vencimientoCubiertoHasta: DateTime(2026, 9, 6),
        );
        expect(conciliado, DateTime(2026, 10, 7), reason: 'corte de septiembre (17/sep) + 20 días — el siguiente ciclo real');
      },
    );

    test('alta histórica con el ciclo vigente ya cubierto — nunca genera Egreso/MovimientoDeuda por la reconciliación en sí', () async {
      final creada = await registrarDeuda.ejecutar(
        nombre: 'Konfío Empresarial',
        tipo: TipoDeuda.tarjetaCredito.name,
        saldoInicial: 3326608,
        fechaSaldoInicial: DateTime(2026, 9, 5),
        tarjetaLimiteCredito: 4000000,
        tarjetaDiaCorte: 17,
        tarjetaReglaFechaPago: ReglaFechaLimitePagoTarjeta.diasDespuesDeCorte.name,
        tarjetaDiasDespuesCorte: 20,
        tarjetaVencimientoCubiertoHasta: DateTime(2026, 9, 6),
      );
      final deuda = (creada as RegistrarDeudaExitoso).deuda;
      expect(deuda.tarjetaVencimientoCubiertoHasta, DateTime(2026, 9, 6));

      // Único movimiento: el altaInicial del saldo capturado (ya
      // existía antes de este campo) — la reconciliación del ciclo no
      // agrega nada más, es pura columna.
      final movimientos = await deudaRepo.listarMovimientos(deuda.id);
      expect(movimientos, hasLength(1));
      expect(movimientos.single.tipo, TipoMovimientoDeuda.altaInicial.name);

      expect(proximaFechaPagoDeuda(deuda, DateTime(2026, 9, 5)), DateTime(2026, 10, 7),
          reason: 'nunca vuelve a proponer 06/09/2026 — ese ciclo ya está marcado cubierto');
    });

    test('un pago real avanza el ciclo cubierto automáticamente — el próximo pago pasa al siguiente ciclo', () async {
      final creada = await registrarDeuda.ejecutar(
        nombre: 'TDC BBVA',
        tipo: TipoDeuda.tarjetaCredito.name,
        saldoInicial: 100000,
        fechaSaldoInicial: DateTime(2026, 9, 1),
        tarjetaLimiteCredito: 5000000,
        tarjetaReglaFechaPago: ReglaFechaLimitePagoTarjeta.diaFijo.name,
        tarjetaDiaPago: 15,
      );
      final deuda = (creada as RegistrarDeudaExitoso).deuda;
      expect(deuda.tarjetaVencimientoCubiertoHasta, isNull, reason: 'sin conciliar al alta — nunca se inventa una cobertura');

      // Pago real el 20/sep — el día 15 ya pasó ese mes, así que el
      // ciclo vigente en ese momento (sin cobertura previa) era 15/oct.
      final pagado = await registrarPago.ejecutar(
        deudaId: deuda.id,
        fecha: DateTime(2026, 9, 20),
        importe: 50000,
        formaPago: 'transferencia',
      );
      final deudaPagada = (pagado as RegistrarPagoDeudaExitoso).deuda;
      expect(deudaPagada.tarjetaVencimientoCubiertoHasta, DateTime(2026, 10, 15),
          reason: 'un pago real siempre avanza el ciclo cubierto, nunca hacia atrás');

      // Con el ciclo ya avanzado a 15/oct, el próximo pago es 15/nov —
      // sin importar qué tan cerca de "hoy" se consulte.
      expect(proximaFechaPagoDeuda(deudaPagada, DateTime(2026, 9, 25)), DateTime(2026, 11, 15));
    });

    test('un ciclo cubierto viejo con ciclos reales saltados de por medio se detecta como "vencida"', () async {
      final creada = await registrarDeuda.ejecutar(
        nombre: 'TDC Santander',
        tipo: TipoDeuda.tarjetaCredito.name,
        saldoInicial: 0,
        tarjetaLimiteCredito: 3000000,
        tarjetaReglaFechaPago: ReglaFechaLimitePagoTarjeta.diaFijo.name,
        tarjetaDiaPago: 10,
        tarjetaVencimientoCubiertoHasta: DateTime(2026, 1, 10),
      );
      final deuda = (creada as RegistrarDeudaExitoso).deuda;

      // "Hoy" muy posterior al último ciclo cubierto — la próxima
      // ocurrencia estrictamente posterior a 10/ene es 10/feb, que ya
      // quedó en el pasado respecto de septiembre: eso es "vencida".
      final hoy = DateTime(2026, 9, 5);
      final proxima = proximaFechaPagoDeuda(deuda, hoy);
      expect(proxima, DateTime(2026, 2, 10));
      expect(proxima!.isBefore(DateTime(hoy.year, hoy.month, hoy.day)), isTrue, reason: 'antes de este campo, esto era estructuralmente imposible');
    });

    test('préstamo/financiamiento nunca lee tarjetaVencimientoCubiertoHasta — proximaFechaPagoDeuda sigue usando fechaVencimiento tal cual', () async {
      final creada = await registrarDeuda.ejecutar(
        nombre: 'Préstamo refacciones',
        tipo: TipoDeuda.prestamo.name,
        fechaOrigen: DateTime(2026, 1, 1),
        importeOriginal: 1000000,
        saldoInicial: 1000000,
        fechaVencimiento: DateTime(2026, 10, 30),
        tarjetaVencimientoCubiertoHasta: DateTime(2026, 1, 1),
      );
      final deuda = (creada as RegistrarDeudaExitoso).deuda;

      expect(proximaFechaPagoDeuda(deuda, DateTime(2026, 9, 5)), DateTime(2026, 10, 30),
          reason: 'un préstamo nunca despacha por proximaFechaLimitePago — el campo, aunque guardado, es letra muerta para deuda fija');
    });
  });
}
