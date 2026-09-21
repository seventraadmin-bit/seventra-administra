// Recarga de línea = gasto operativo real (schemaVersion 86).
//
// Hueco que cierra: hasta v85 registrar $200 a una línea RISEG subía el
// total de recargas y salía en el historial, pero Finanzas no se
// enteraba — ni Egreso, ni MovimientoDeuda, ni efecto en el resultado
// operativo. La decisión original de la Etapa 9C ("deliberadamente sin
// Egreso automático") dejaba el gasto invisible.
//
// Lo que estas pruebas protegen:
//   1. Cuenta → exactamente UN Egreso; TDC → exactamente UN cargo y
//      CERO Egresos;
//   2. el gasto operativo sube exactamente una vez, y pagar la tarjeta
//      después no lo vuelve a reconocer;
//   3. corregir MUEVE el efecto —las seis transiciones— sin duplicarlo
//      ni perderlo;
//   4. cancelar lo revierte exactamente una vez, y repetir no hace nada;
//   5. las recargas LEGACY (sin origen) se cancelan sin tocar ningún
//      balance;
//   6. una recarga cancelada desaparece de los indicadores.

import 'package:riseg_one/features/finanzas/domain/politica_saldo_cuenta.dart';
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
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/finanzas/domain/usecases/obtener_posicion_de_caja_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_deuda_usecase.dart';
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/repositories/asignacion_linea_telefonica_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/repositories/linea_telefonica_equipo_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/repositories/linea_telefonica_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/repositories/recarga_linea_telefonica_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/tables/linea_telefonica_table.dart';
import 'package:riseg_one/features/telefonia/data/tables/recarga_linea_telefonica_table.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/cancelar_recarga_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/corregir_recarga_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/crear_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/registrar_recarga_linea_telefonica_usecase.dart';

void main() {
  late AppDatabase db;
  late RecargaLineaTelefonicaRepositoryImpl recargaRepo;
  late LineaTelefonicaRepositoryImpl lineaRepo;
  late EgresoRepositoryImpl egresoRepo;
  late DeudaRepositoryImpl deudaRepo;
  late CuentaFinancieraRepositoryImpl cuentaRepo;
  late RegistrarRecargaLineaTelefonicaUseCase registrar;
  late CorregirRecargaLineaTelefonicaUseCase corregir;
  late CancelarRecargaLineaTelefonicaUseCase cancelar;
  late ObtenerPosicionDeCajaUseCase posicionCaja;
  late RegistrarDeudaUseCase registrarDeuda;

  late String lineaId;
  late String cuentaAId;
  late String cuentaBId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    egresoRepo = EgresoRepositoryImpl(db);
    deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
    cuentaRepo = CuentaFinancieraRepositoryImpl(db);
    final codigoSecuencia = CodigoSecuenciaService(db);
    recargaRepo = RecargaLineaTelefonicaRepositoryImpl(db, egresoRepo, deudaRepo, codigoSecuencia);
    lineaRepo = LineaTelefonicaRepositoryImpl(
      db,
      AsignacionLineaTelefonicaRepositoryImpl(db),
      LineaTelefonicaEquipoRepositoryImpl(db, AsignacionLineaTelefonicaRepositoryImpl(db), AsignacionRepositoryImpl(db)),
    );

    registrar = RegistrarRecargaLineaTelefonicaUseCase(recargaRepo, lineaRepo, deudaRepo);
    corregir = CorregirRecargaLineaTelefonicaUseCase(recargaRepo, lineaRepo, deudaRepo);
    cancelar = CancelarRecargaLineaTelefonicaUseCase(recargaRepo, lineaRepo);
    posicionCaja = ObtenerPosicionDeCajaUseCase(cuentaRepo);
    registrarDeuda = RegistrarDeudaUseCase(deudaRepo, GenerarCodigoUseCase(codigoSecuencia));

    final creada = await CrearLineaTelefonicaUseCase(lineaRepo, GenerarCodigoUseCase(codigoSecuencia)).ejecutar(
      numero: '7225562629',
      operador: OperadorTelefonico.telcel.name,
      modalidadSim: ModalidadSim.fisica.name,
    );
    lineaId = (creada as CrearLineaTelefonicaExitoso).linea.id;

    Future<String> crearCuenta(String codigo, String nombre) async {
      final cuenta = await cuentaRepo.crear(
        codigo: codigo,
        nombre: nombre,
        tipo: TipoCuentaFinanciera.banco.name,
        saldoInicial: 10000000,
        // Cubre tambien las recargas legacy de 2025: desde la v91 una
        // salida anterior al saldo inicial de su cuenta se rechaza.
        fechaSaldoInicial: DateTime(2025, 1, 1),
      );
      return cuenta.id;
    }

    cuentaAId = await crearCuenta('CTA-0001', 'BBVA Empresarial');
    cuentaBId = await crearCuenta('CTA-0002', 'Banorte Operativa');
  });

  tearDown(() => db.close());

  // ---------------------------------------------------------------
  // Andamiaje
  // ---------------------------------------------------------------

  Future<String> crearTarjeta(String nombre, {int limite = 5000000}) async {
    final resultado = await registrarDeuda.ejecutar(
      nombre: nombre,
      tipo: TipoDeuda.tarjetaCredito.name,
      saldoInicial: 0,
      tarjetaLimiteCredito: limite,
    );
    return (resultado as RegistrarDeudaExitoso).deuda.id;
  }

  Future<RecargaLineaTelefonicaData> recargarDesdeCuenta({
    int importe = 20000,
    String? cuentaId,
  }) async {
    final r = await registrar.ejecutar(
      lineaTelefonicaId: lineaId,
      fecha: DateTime(2026, 3, 1),
      importe: importe,
      formaPago: FormaPago.transferencia.name,
      cuentaFinancieraId: cuentaId ?? cuentaAId,
    );
    expect(r, isA<RegistrarRecargaLineaTelefonicaExitoso>(), reason: '$r');
    return (r as RegistrarRecargaLineaTelefonicaExitoso).recarga;
  }

  Future<RecargaLineaTelefonicaData> recargarConTarjeta(String deudaId, {int importe = 20000}) async {
    final r = await registrar.ejecutar(
      lineaTelefonicaId: lineaId,
      fecha: DateTime(2026, 3, 1),
      importe: importe,
      formaPago: FormaPago.tarjeta.name,
      deudaIdTarjeta: deudaId,
    );
    expect(r, isA<RegistrarRecargaLineaTelefonicaExitoso>(), reason: '$r');
    return (r as RegistrarRecargaLineaTelefonicaExitoso).recarga;
  }

  Future<RecargaLineaTelefonicaData> recargar(String id) =>
      (db.select(db.recargaLineaTelefonica)..where((t) => t.id.equals(id))).getSingle();

  Future<int> saldoTarjeta(String deudaId) async => (await deudaRepo.obtenerPorId(deudaId))!.saldoActual;

  /// Gasto operativo por tarjeta — la misma cifra que consume el
  /// Resultado operativo, no una suma paralela.
  Future<int> gastoPorTarjeta() => deudaRepo.totalCargadoEnRango();

  // ===============================================================
  // §5 / §40 — CUENTA FINANCIERA
  // ===============================================================
  group('Recarga pagada desde Cuenta', () {
    test('crea exactamente UN Egreso, vinculado por FK real, y cero cargos de tarjeta', () async {
      final recarga = await recargarDesdeCuenta();

      final egresos = await db.select(db.egreso).get();
      expect(egresos, hasLength(1));
      expect(egresos.single.monto, 20000);
      expect(egresos.single.cuentaFinancieraId, cuentaAId);
      expect(recarga.egresoId, egresos.single.id, reason: 'la relación es por FK, nunca por concepto');
      expect(recarga.deudaId, isNull, reason: 'nunca ambos orígenes');
      expect(await db.select(db.movimientoDeuda).get(), isEmpty);
    });

    test('la cuenta disminuye exactamente el importe, una sola vez', () async {
      final antes = (await posicionCaja.ejecutar()).saldoDisponible;
      await recargarDesdeCuenta(importe: 20000);
      final despues = (await posicionCaja.ejecutar()).saldoDisponible;

      expect(antes - despues, 20000);
    });

    test('el concepto del Egreso nombra la línea, pero la relación NO depende de ese texto', () async {
      // DOS recargas de la MISMA línea: sus Egresos tienen el concepto
      // idéntico, así que resolver por texto —o por "la primera que
      // haya"— devolvería la equivocada. Sólo la FK acierta.
      final primera = await recargarDesdeCuenta(importe: 20000);
      final segunda = await recargarDesdeCuenta(importe: 35000);

      final egresos = await db.select(db.egreso).get();
      expect(egresos, hasLength(2));
      expect(egresos.map((e) => e.concepto).toSet(), hasLength(1),
          reason: 'mismo texto: por eso el texto no puede ser la relación');

      final egresoDeSegunda = egresos.firstWhere((e) => e.id == segunda.egresoId);
      final egresoDePrimera = egresos.firstWhere((e) => e.id == primera.egresoId);
      expect(egresoDeSegunda.concepto, contains('7225562629'));

      expect((await recargaRepo.obtenerPorEgresoId(egresoDeSegunda.id))?.id, segunda.id);
      expect((await recargaRepo.obtenerPorEgresoId(egresoDePrimera.id))?.id, primera.id);
      expect(
        (await recargaRepo.listarEgresoIds()).toSet(),
        {primera.egresoId, segunda.egresoId},
      );
    });

    test('un Egreso manual ajeno a Telefonía NUNCA se vincula a una recarga', () async {
      // El caso real: "RECARGA SALDO COYOACAN" es una recarga al número
      // PERSONAL de un guardia sin SIM de RISEG. Es —y debe seguir
      // siendo— un Egreso manual independiente. Que su concepto diga
      // "RECARGA" no puede bastar para atarlo a ninguna línea.
      await recargarDesdeCuenta(importe: 20000);
      final manual = await egresoRepo.crear(
        folioEgreso: 'EGR-MANUAL-001',
        monto: 20000,
        fecha: DateTime(2026, 3, 1),
        cuentaFinancieraId: cuentaAId,
        formaPago: FormaPago.efectivo.name,
        concepto: 'RECARGA SALDO COYOACAN',
      );

      expect(await recargaRepo.obtenerPorEgresoId(manual.id), isNull,
          reason: 'sin FK no hay relación, por más que el texto se parezca');
      expect(await recargaRepo.listarEgresoIds(), isNot(contains(manual.id)));
    });
  });

  // ===============================================================
  // §6 / §40 — TARJETA DE CRÉDITO
  // ===============================================================
  group('Recarga pagada con TDC', () {
    test('crea exactamente UN MovimientoDeuda, cero Egresos, y sube la deuda', () async {
      final tarjeta = await crearTarjeta('TDC Corporativa');
      final recarga = await recargarConTarjeta(tarjeta);

      expect(await db.select(db.egreso).get(), isEmpty, reason: 'a crédito nunca sale dinero del banco');
      final cargos = await (db.select(db.movimientoDeuda)
            ..where((t) => t.recargaLineaTelefonicaId.equals(recarga.id)))
          .get();
      expect(cargos, hasLength(1));
      expect(cargos.single.importe, 20000);
      expect(recarga.deudaId, tarjeta);
      expect(recarga.egresoId, isNull);
      expect(await saldoTarjeta(tarjeta), 20000);
    });

    test('el gasto operativo sube exactamente el importe — nunca 0, nunca el doble', () async {
      final tarjeta = await crearTarjeta('TDC Corporativa');
      expect(await gastoPorTarjeta(), 0);

      await recargarConTarjeta(tarjeta, importe: 20000);

      expect(await gastoPorTarjeta(), 20000);
    });

    test('pagar la tarjeta después NO vuelve a reconocer la recarga como gasto', () async {
      final tarjeta = await crearTarjeta('TDC Corporativa');
      await recargarConTarjeta(tarjeta, importe: 20000);
      final gastoTrasRecarga = await gastoPorTarjeta();

      await deudaRepo.registrarPago(
        deudaId: tarjeta,
        folioEgreso: 'EGR-PAGO-TDC',
        fecha: DateTime(2026, 4, 20),
        importe: 20000,
        formaPago: FormaPago.transferencia.name,
        cuentaFinancieraId: cuentaAId,
      );

      expect(await gastoPorTarjeta(), gastoTrasRecarga,
          reason: 'pagar una deuda mueve dinero, no genera gasto nuevo');
      expect(await saldoTarjeta(tarjeta), 0);
    });
  });

  // ===============================================================
  // §4 / §40 — ORIGEN OBLIGATORIO
  // ===============================================================
  group('Origen financiero obligatorio', () {
    test('sin forma de pago → rechazo, y no queda recarga', () async {
      final r = await registrar.ejecutar(
        lineaTelefonicaId: lineaId,
        fecha: DateTime(2026, 3, 1),
        importe: 20000,
        formaPago: '',
      );
      expect(r, isA<RegistrarRecargaLineaTelefonicaOrigenFinancieroRequerido>());
      expect(await db.select(db.recargaLineaTelefonica).get(), isEmpty);
    });

    test('cuenta Y tarjeta a la vez → rechazo', () async {
      final tarjeta = await crearTarjeta('TDC Corporativa');
      final r = await registrar.ejecutar(
        lineaTelefonicaId: lineaId,
        fecha: DateTime(2026, 3, 1),
        importe: 20000,
        formaPago: FormaPago.tarjeta.name,
        cuentaFinancieraId: cuentaAId,
        deudaIdTarjeta: tarjeta,
      );
      expect(r, isA<RegistrarRecargaLineaTelefonicaOrigenFinancieroAmbiguo>());
      expect(await db.select(db.recargaLineaTelefonica).get(), isEmpty);
      expect(await db.select(db.egreso).get(), isEmpty);
      expect(await db.select(db.movimientoDeuda).get(), isEmpty);
    });

    // El par que define la invariante: con cuenta real entra; sin
    // cuenta NO entra. Deliberadamente más estricto que Compras y
    // Tiempos Extra, que sí aceptan "cuenta no especificada".
    test('Cuenta + cuenta real → registra, y el Egreso apunta a ESA cuenta', () async {
      final r = await registrar.ejecutar(
        lineaTelefonicaId: lineaId,
        fecha: DateTime(2026, 3, 1),
        importe: 20000,
        formaPago: FormaPago.transferencia.name,
        cuentaFinancieraId: cuentaBId,
      );
      expect(r, isA<RegistrarRecargaLineaTelefonicaExitoso>(), reason: '$r');
      final recarga = (r as RegistrarRecargaLineaTelefonicaExitoso).recarga;
      expect(recarga.egresoId, isNotNull);
      expect(await recargaRepo.cuentaDeEgreso(recarga.egresoId!), cuentaBId);
    });

    test('Cuenta SIN cuenta financiera → rechazo, y NADA se persiste', () async {
      final r = await registrar.ejecutar(
        lineaTelefonicaId: lineaId,
        fecha: DateTime(2026, 3, 1),
        importe: 20000,
        formaPago: FormaPago.transferencia.name,
      );
      expect(r, isA<RegistrarRecargaLineaTelefonicaOrigenFinancieroRequerido>(),
          reason: 'no se sabe de qué cuenta salió el dinero: no se registra');
      expect(await db.select(db.recargaLineaTelefonica).get(), isEmpty);
      expect(await db.select(db.egreso).get(), isEmpty,
          reason: 'jamás un Egreso con cuenta inventada ni "Sin especificar"');
      expect(await db.select(db.movimientoDeuda).get(), isEmpty);
    });

    test('TDC + tarjeta real → registra y carga esa tarjeta', () async {
      final tarjeta = await crearTarjeta('TDC Corporativa');
      final recarga = await recargarConTarjeta(tarjeta);
      expect(recarga.deudaId, tarjeta);
      expect(recarga.egresoId, isNull);
      expect(await saldoTarjeta(tarjeta), 20000);
    });

    test('corregir tampoco puede dejar la recarga sin cuenta', () async {
      final recarga = await recargarDesdeCuenta();
      final r = await corregir.ejecutar(
        recargaLineaTelefonicaId: recarga.id,
        importe: 30000,
        formaPago: FormaPago.transferencia.name,
        motivo: 'Importe mal capturado',
      );
      expect(r, isA<CorregirRecargaLineaTelefonicaOrigenFinancieroRequerido>());
      expect((await recargar(recarga.id)).importe, 20000, reason: 'la corrección no llegó a aplicarse');
      expect(await recargaRepo.cuentaDeEgreso((await recargar(recarga.id)).egresoId!), cuentaAId);
    });
    test('forma de pago tarjeta sin tarjeta → rechazo', () async {
      final r = await registrar.ejecutar(
        lineaTelefonicaId: lineaId,
        fecha: DateTime(2026, 3, 1),
        importe: 20000,
        formaPago: FormaPago.tarjeta.name,
      );
      expect(r, isA<RegistrarRecargaLineaTelefonicaOrigenFinancieroRequerido>());
    });
  });

  // ===============================================================
  // §12 / §40 — LAS SEIS TRANSICIONES DE CORRECCIÓN
  // ===============================================================
  group('Corrección: transiciones de origen', () {
    Future<CorregirRecargaLineaTelefonicaResultado> corregirA(
      String recargaId, {
      int? importe,
      required String formaPago,
      String? cuentaFinancieraId,
      String? deudaIdTarjeta,
    }) {
      return corregir.ejecutar(
        recargaLineaTelefonicaId: recargaId,
        importe: importe,
        formaPago: formaPago,
        cuentaFinancieraId: cuentaFinancieraId,
        deudaIdTarjeta: deudaIdTarjeta,
        motivo: 'Ticket real',
      );
    }

    test('Cuenta A → Cuenta A con otro importe: el mismo Egreso cambia, nunca se duplica', () async {
      final recarga = await recargarDesdeCuenta(importe: 20000);
      final egresoOriginal = recarga.egresoId;

      final r = await corregirA(recarga.id,
          importe: 35000, formaPago: FormaPago.transferencia.name, cuentaFinancieraId: cuentaAId);
      expect(r, isA<CorregirRecargaLineaTelefonicaExitoso>(), reason: '$r');

      final egresos = await db.select(db.egreso).get();
      expect(egresos, hasLength(1));
      expect(egresos.single.id, egresoOriginal, reason: 'el mismo Egreso, corregido');
      expect(egresos.single.monto, 35000);
      expect((await recargar(recarga.id)).importe, 35000);
    });

    test('Cuenta A → Cuenta B: el Egreso se mueve de cuenta, sigue siendo uno', () async {
      final recarga = await recargarDesdeCuenta(importe: 20000, cuentaId: cuentaAId);

      await corregirA(recarga.id, formaPago: FormaPago.transferencia.name, cuentaFinancieraId: cuentaBId);

      final egresos = await db.select(db.egreso).get();
      expect(egresos, hasLength(1));
      expect(egresos.single.cuentaFinancieraId, cuentaBId);
    });

    test('TDC A → TDC A con otro importe: ajuste por el delta, nunca un segundo cargo completo', () async {
      final tarjeta = await crearTarjeta('TDC Corporativa');
      final recarga = await recargarConTarjeta(tarjeta, importe: 20000);

      await corregirA(recarga.id, importe: 35000, formaPago: FormaPago.tarjeta.name, deudaIdTarjeta: tarjeta);

      expect(await saldoTarjeta(tarjeta), 35000, reason: '20000 + delta 15000');
      expect(await gastoPorTarjeta(), 35000, reason: 'el gasto sigue el importe real, sin duplicar');
      expect(await db.select(db.egreso).get(), isEmpty);
    });

    test('TDC A → TDC B: la primera queda en cero y la segunda recibe el cargo completo', () async {
      final tarjetaA = await crearTarjeta('TDC A');
      final tarjetaB = await crearTarjeta('TDC B');
      final recarga = await recargarConTarjeta(tarjetaA, importe: 20000);

      await corregirA(recarga.id, formaPago: FormaPago.tarjeta.name, deudaIdTarjeta: tarjetaB);

      expect(await saldoTarjeta(tarjetaA), 0);
      expect(await saldoTarjeta(tarjetaB), 20000);
      expect(await gastoPorTarjeta(), 20000, reason: 'el gasto total no cambió: sólo cambió quién lo financia');
      expect((await recargar(recarga.id)).deudaId, tarjetaB);
    });

    test('Cuenta → TDC: cancela el Egreso y aplica el cargo', () async {
      final tarjeta = await crearTarjeta('TDC Corporativa');
      final recarga = await recargarDesdeCuenta(importe: 20000);

      await corregirA(recarga.id, formaPago: FormaPago.tarjeta.name, deudaIdTarjeta: tarjeta);

      final egresos = await db.select(db.egreso).get();
      expect(egresos.single.estatus, 'cancelado', reason: 'ya no sale dinero del banco');
      expect(await saldoTarjeta(tarjeta), 20000);
      final actualizada = await recargar(recarga.id);
      expect(actualizada.egresoId, isNull);
      expect(actualizada.deudaId, tarjeta);
    });

    test('TDC → Cuenta: revierte el cargo y crea el Egreso', () async {
      final tarjeta = await crearTarjeta('TDC Corporativa');
      final recarga = await recargarConTarjeta(tarjeta, importe: 20000);

      await corregirA(recarga.id, formaPago: FormaPago.transferencia.name, cuentaFinancieraId: cuentaAId);

      expect(await saldoTarjeta(tarjeta), 0);
      expect(await gastoPorTarjeta(), 0, reason: 'ya no lo financia la tarjeta');
      final egresos = await db.select(db.egreso).get();
      expect(egresos.where((e) => e.estatus == 'registrado'), hasLength(1));
      final actualizada = await recargar(recarga.id);
      expect(actualizada.deudaId, isNull);
      expect(actualizada.egresoId, isNotNull);
    });
  });

  // ===============================================================
  // §13 / §40 — CANCELACIÓN
  // ===============================================================
  group('Cancelación', () {
    test('Cuenta: cancela su Egreso, restaura la cuenta y no crea un Ingreso', () async {
      final antes = (await posicionCaja.ejecutar()).saldoDisponible;
      final recarga = await recargarDesdeCuenta(importe: 20000);

      final r = await cancelar.ejecutar(recargaLineaTelefonicaId: recarga.id, motivo: 'Pago rechazado');
      expect(r, isA<CancelarRecargaLineaTelefonicaExitoso>());

      expect((await posicionCaja.ejecutar()).saldoDisponible, antes, reason: 'restaura, no compensa');
      final egresos = await db.select(db.egreso).get();
      expect(egresos, hasLength(1), reason: 'no crea un segundo gasto');
      expect(egresos.single.estatus, 'cancelado');
      expect(await db.select(db.ingreso).get(), isEmpty, reason: 'cancelar no es cobrar');
    });

    test('TDC: revierte el cargo exactamente una vez y no crea Egreso', () async {
      final tarjeta = await crearTarjeta('TDC Corporativa');
      final recarga = await recargarConTarjeta(tarjeta, importe: 20000);

      await cancelar.ejecutar(recargaLineaTelefonicaId: recarga.id, motivo: 'Pago rechazado');

      expect(await saldoTarjeta(tarjeta), 0);
      expect(await gastoPorTarjeta(), 0);
      expect(await db.select(db.egreso).get(), isEmpty);
    });

    test('segunda cancelación → rechazo, y nada se mueve dos veces', () async {
      final tarjeta = await crearTarjeta('TDC Corporativa');
      final recarga = await recargarConTarjeta(tarjeta, importe: 20000);
      await cancelar.ejecutar(recargaLineaTelefonicaId: recarga.id, motivo: 'Pago rechazado');
      final movimientos = (await db.select(db.movimientoDeuda).get()).length;

      final r = await cancelar.ejecutar(recargaLineaTelefonicaId: recarga.id, motivo: 'Otra vez');
      expect(r, isA<CancelarRecargaLineaTelefonicaYaCancelada>());

      expect((await db.select(db.movimientoDeuda).get()).length, movimientos);
      expect(await saldoTarjeta(tarjeta), 0);
    });

    test('corregir una cancelada → rechazo', () async {
      final recarga = await recargarDesdeCuenta();
      await cancelar.ejecutar(recargaLineaTelefonicaId: recarga.id, motivo: 'Pago rechazado');

      final r = await corregir.ejecutar(
        recargaLineaTelefonicaId: recarga.id,
        importe: 99000,
        formaPago: FormaPago.transferencia.name,
        cuentaFinancieraId: cuentaAId,
        motivo: 'Ya no',
      );
      expect(r, isA<CorregirRecargaLineaTelefonicaCancelada>());
      expect((await recargar(recarga.id)).importe, 20000);
    });
  });

  // ===============================================================
  // §14 — RECARGAS LEGACY
  // ===============================================================
  group('Recargas legacy (anteriores a v86)', () {
    /// Una recarga tal como quedó tras la migración: sin forma de pago,
    /// sin Egreso y sin tarjeta. Se inserta directo, que es exactamente
    /// como la dejó v86.
    Future<RecargaLineaTelefonicaData> legacy({int importe = 20000}) {
      return db.into(db.recargaLineaTelefonica).insertReturning(
            RecargaLineaTelefonicaCompanion.insert(
              lineaTelefonicaId: lineaId,
              fecha: DateTime(2025, 12, 1),
              importe: importe,
            ),
          );
    }

    test('se identifica por no tener NINGÚN origen financiero', () async {
      final r = await legacy();
      expect(r.formaPago, isNull);
      expect(r.egresoId, isNull);
      expect(r.deudaId, isNull);
    });

    test('puede cancelarse, y no altera ningún balance', () async {
      final r = await legacy();
      final saldoAntes = (await posicionCaja.ejecutar()).saldoDisponible;

      final resultado = await cancelar.ejecutar(recargaLineaTelefonicaId: r.id, motivo: 'Duplicada');
      expect(resultado, isA<CancelarRecargaLineaTelefonicaExitoso>());

      expect((await recargar(r.id)).estatus, EstatusRecargaLineaTelefonica.cancelada.name);
      expect((await posicionCaja.ejecutar()).saldoDisponible, saldoAntes);
      expect(await db.select(db.egreso).get(), isEmpty);
      expect(await db.select(db.movimientoDeuda).get(), isEmpty);
    });

    test('sale de los totales vigentes al cancelarse, y sigue en el historial', () async {
      final r = await legacy(importe: 20000);
      expect(await recargaRepo.totalPorLinea(lineaId), 20000);

      await cancelar.ejecutar(recargaLineaTelefonicaId: r.id, motivo: 'Duplicada');

      expect(await recargaRepo.totalPorLinea(lineaId), 0);
      expect(await recargaRepo.listarPorLinea(lineaId), hasLength(1), reason: 'el historial la conserva');
    });

    // La excepción legacy es SÓLO conservar lo que no se sabe. No es
    // una puerta para que el origen desconocido se rellene solo.
    test('NUNCA adquiere un origen ficticio: corregirla exige declarar uno real', () async {
      final r = await legacy();

      final sinCuenta = await corregir.ejecutar(
        recargaLineaTelefonicaId: r.id,
        importe: 30000,
        formaPago: FormaPago.transferencia.name,
        motivo: 'Importe mal capturado',
      );
      expect(sinCuenta, isA<CorregirRecargaLineaTelefonicaOrigenFinancieroRequerido>());
      expect((await recargar(r.id)).egresoId, isNull);
      expect((await recargar(r.id)).importe, 20000);
      expect(await db.select(db.egreso).get(), isEmpty, reason: 'no se le inventó una cuenta');

      final conCuenta = await corregir.ejecutar(
        recargaLineaTelefonicaId: r.id,
        importe: 30000,
        formaPago: FormaPago.transferencia.name,
        cuentaFinancieraId: cuentaAId,
        motivo: 'Importe mal capturado y origen identificado',
      );
      expect(conCuenta, isA<CorregirRecargaLineaTelefonicaExitoso>(), reason: '$conCuenta');
      final corregida = await recargar(r.id);
      expect(corregida.egresoId, isNotNull, reason: 'declarado el origen real, sí nace su Egreso');
      expect(await recargaRepo.cuentaDeEgreso(corregida.egresoId!), cuentaAId);
    });
  });

  // ===============================================================
  // §15 / §16 — INDICADORES
  // ===============================================================
  group('Totales e "Última recarga"', () {
    test('una cancelada no entra en el Total', () async {
      final a = await recargarDesdeCuenta(importe: 20000);
      await registrar.ejecutar(
        lineaTelefonicaId: lineaId,
        fecha: DateTime(2026, 4, 1),
        importe: 30000,
        formaPago: FormaPago.transferencia.name,
        cuentaFinancieraId: cuentaAId,
      );
      expect(await recargaRepo.totalPorLinea(lineaId), 50000);

      await cancelar.ejecutar(recargaLineaTelefonicaId: a.id, motivo: 'Error de captura');

      expect(await recargaRepo.totalPorLinea(lineaId), 30000);
    });

    test('la más reciente cancelada NO puede ser "Última recarga": se busca la última vigente', () async {
      await registrar.ejecutar(
        lineaTelefonicaId: lineaId,
        fecha: DateTime(2026, 3, 1),
        importe: 20000,
        formaPago: FormaPago.transferencia.name,
        cuentaFinancieraId: cuentaAId,
      );
      final reciente = (await registrar.ejecutar(
        lineaTelefonicaId: lineaId,
        fecha: DateTime(2026, 5, 1),
        importe: 30000,
        formaPago: FormaPago.transferencia.name,
        cuentaFinancieraId: cuentaAId,
      ) as RegistrarRecargaLineaTelefonicaExitoso)
          .recarga;

      await cancelar.ejecutar(recargaLineaTelefonicaId: reciente.id, motivo: 'Error de captura');

      final ultimas = await recargaRepo.obtenerUltimasPorTodasLasLineas();
      expect(ultimas[lineaId]?.fecha, DateTime(2026, 3, 1));
    });

    test('si TODAS están canceladas: sin última recarga y total en cero', () async {
      final a = await recargarDesdeCuenta(importe: 20000);
      await cancelar.ejecutar(recargaLineaTelefonicaId: a.id, motivo: 'Error de captura');

      expect(await recargaRepo.totalPorLinea(lineaId), 0);
      expect((await recargaRepo.obtenerUltimasPorTodasLasLineas())[lineaId], isNull);
      expect(await recargaRepo.listarPorLinea(lineaId), hasLength(1));
    });
  });

  group('Política de saldo (v91) — Telefonía', () {
    test('A) con saldo suficiente: la recarga se registra', () async {
      final resultado = await registrar.ejecutar(
        lineaTelefonicaId: lineaId,
        fecha: DateTime(2026, 6, 1),
        importe: 20000,
        formaPago: FormaPago.transferencia.name,
        cuentaFinancieraId: cuentaAId,
      );
      expect(resultado, isA<RegistrarRecargaLineaTelefonicaExitoso>());
    });

    test('B y C) sin saldo: rechaza y NO deja persistencia parcial', () async {
      final vacia = await cuentaRepo.crear(
        codigo: 'CTA-VACIA',
        nombre: 'Cuenta vacía',
        tipo: TipoCuentaFinanciera.banco.name,
        saldoInicial: 1000,
        fechaSaldoInicial: DateTime(2025, 1, 1),
      );
      final recargasAntes = (await db.select(db.recargaLineaTelefonica).get()).length;

      await expectLater(
        registrar.ejecutar(
          lineaTelefonicaId: lineaId,
          fecha: DateTime(2026, 6, 1),
          importe: 500000,
          formaPago: FormaPago.transferencia.name,
          cuentaFinancieraId: vacia.id,
        ),
        throwsA(isA<SaldoInsuficienteException>()),
      );

      expect((await db.select(db.recargaLineaTelefonica).get()).length, recargasAntes, reason: 'ni la recarga');
      expect(
        (await db.select(db.egreso).get()).where((e) => e.monto == 500000), isEmpty, reason: 'ni el Egreso');
      expect(
        (await db.select(db.egresoFuente).get()).where((f) => f.cuentaFinancieraId == vacia.id),
        isEmpty,
        reason: 'ni su fuente',
      );
      expect(await cuentaRepo.calcularSaldo(vacia.id), 1000);
    });
  });
}
