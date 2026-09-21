// Contingencia del Maestro: corregir de qué CuentaFinanciera salió un
// Egreso ya registrado.
//
// El caso real: PAGN-000005 generó EGR-000071 por $11,750 con
// `cuentaFinancieraId = null` — el dinero salió, pero ningún saldo
// bajó. Corregir la asociación NO es crear otro movimiento: el saldo se
// deriva de la asociación vigente del MISMO Egreso.

import 'package:riseg_one/features/finanzas/domain/politica_saldo_cuenta.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_financiera_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/tables/deuda_table.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/corregir_origen_financiero_egreso_usecase.dart';
import 'package:riseg_one/features/finanzas/finanzas_providers.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

class _SesionMaestro extends SesionController {
  @override
  SesionUsuario? build() => const SesionUsuario(
        usuarioId: 'usuario-maestro',
        nombre: 'MARLON',
        nombreUsuario: 'MARLONRH',
        esMaestro: true,
        permisos: {},
      );

}

class _SesionUsuarioNormal extends SesionController {
  @override
  SesionUsuario? build() => const SesionUsuario(
        usuarioId: 'usuario-normal',
        nombre: 'JAVIER',
        nombreUsuario: 'JAVIER',
        esMaestro: false,
        // Con TODOS los permisos de Finanzas y de Nómina:
        // `exigirMaestro` no consulta esta lista.
        permisos: {
          'finanzas.crear',
          'finanzas.corregir',
          'finanzas.cancelar',
          'finanzas.ver',
          'nomina.crear',
          'nomina.pagar',
          'nomina.corregir',
        },
      );
}

void main() {
  late AppDatabase db;
  late EgresoRepositoryImpl egresoRepo;
  late CuentaFinancieraRepositoryImpl cuentasFinancieras;
  late CorregirOrigenFinancieroEgresoUseCase corregir;
  late CuentaFinancieraData bbva;
  late CuentaFinancieraData banorte;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    // El actor es FK real: sin la fila, la bitácora revienta.
    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(
            id: const Value('usuario-maestro'),
            nombre: 'MARLON',
            nombreUsuario: 'MARLONRH',
            passwordHash: r'pbkdf2\====',
            esMaestro: const Value(true),
          ),
        );
    egresoRepo = EgresoRepositoryImpl(db);
    cuentasFinancieras = CuentaFinancieraRepositoryImpl(db);
    // El resolvedor de origen se toma del contenedor real: cablearlo a
    // mano exigiría los diez repositorios que ya conoce el provider.
    final contenedor = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
    addTearDown(contenedor.dispose);
    corregir = CorregirOrigenFinancieroEgresoUseCase(
      egresoRepo,
      cuentasFinancieras,
      contenedor.read(obtenerOrigenAutomaticoEgresoUseCaseProvider),
    );

    bbva = await db.into(db.cuentaFinanciera).insertReturning(
          CuentaFinancieraCompanion.insert(
            codigo: 'CF-BBVA',
            nombre: 'BBVA Empresarial',
            tipo: 'banco',
            saldoInicial: 5000000,
            fechaSaldoInicial: DateTime(2026, 1, 1),
          ),
        );
    banorte = await db.into(db.cuentaFinanciera).insertReturning(
          CuentaFinancieraCompanion.insert(
            codigo: 'CF-BANORTE',
            nombre: 'Banorte',
            tipo: 'banco',
            saldoInicial: 3000000,
            fechaSaldoInicial: DateTime(2026, 1, 1),
          ),
        );
    addTearDown(db.close);
  });

  /// Un Egreso como el de Nómina: real, vigente y —si se pide— huérfano
  /// de cuenta, tal cual quedó EGR-000071.
  Future<EgresoData> egresoDePrueba({String? cuentaFinancieraId, int monto = 1175000}) {
    return egresoRepo.crear(
      folioEgreso: 'EGR-000071',
      monto: monto,
      fecha: DateTime(2026, 9, 20),
      cuentaFinancieraId: cuentaFinancieraId,
      formaPago: 'transferencia',
      concepto: 'Pago de Nómina PAGN-000005',
    );
  }

  Future<int> saldo(String cuentaId) => cuentasFinancieras.calcularSaldo(cuentaId);

  group('A y B — los dos caminos que la herramienta resuelve', () {
    test('A: null → cuenta. El saldo baja exactamente una vez', () async {
      final egreso = await egresoDePrueba();
      expect(await saldo(bbva.id), 5000000, reason: 'un Egreso sin cuenta no descuenta de nadie');

      final resultado = await corregir.ejecutar(
        egresoId: egreso.id,
        cuentaFinancieraId: bbva.id,
        motivo: 'El pago de nómina se registró sin cuenta por el hueco anterior.',
        actorUsuarioId: 'usuario-maestro',
      );
      expect(resultado, isA<CorregirOrigenFinancieroEgresoExitoso>());

      expect(await saldo(bbva.id), 5000000 - 1175000);
      expect(await saldo(banorte.id), 3000000, reason: 'la otra cuenta no se entera');
    });

    test('B: cuenta A → cuenta B. A recupera, B pierde, el gasto no cambia', () async {
      final egreso = await egresoDePrueba(cuentaFinancieraId: bbva.id, monto: 500000);
      expect(await saldo(bbva.id), 5000000 - 500000);

      await corregir.ejecutar(
        egresoId: egreso.id,
        cuentaFinancieraId: banorte.id,
        motivo: 'Salió de Banorte, no de BBVA.',
        actorUsuarioId: 'usuario-maestro',
      );

      expect(await saldo(bbva.id), 5000000, reason: 'BBVA recupera exactamente el monto');
      expect(await saldo(banorte.id), 3000000 - 500000, reason: 'Banorte pierde exactamente el monto');
    });
  });

  group('G a L — lo que la corrección NO puede mover', () {
    test('no cambia monto, folio, fecha ni concepto', () async {
      final egreso = await egresoDePrueba();
      final resultado = await corregir.ejecutar(
        egresoId: egreso.id,
        cuentaFinancieraId: bbva.id,
        motivo: 'Reconciliación',
      ) as CorregirOrigenFinancieroEgresoExitoso;

      expect(resultado.egreso.monto, egreso.monto);
      expect(resultado.egreso.folioEgreso, egreso.folioEgreso);
      expect(resultado.egreso.fecha, egreso.fecha);
      expect(resultado.egreso.concepto, egreso.concepto);
      expect(resultado.egreso.formaPago, egreso.formaPago);
      expect(resultado.egreso.id, egreso.id, reason: 'es EL MISMO Egreso');
    });

    test('no crea un segundo Egreso ni un Ingreso compensatorio', () async {
      final egreso = await egresoDePrueba();
      await corregir.ejecutar(egresoId: egreso.id, cuentaFinancieraId: bbva.id, motivo: 'Reconciliación');

      expect(await db.select(db.egreso).get(), hasLength(1));
      expect(await db.select(db.ingreso).get(), isEmpty,
          reason: 'el saldo se deriva de la asociación, no de un movimiento inventado');
    });

    test('el gasto operativo total no se mueve: sigue siendo el mismo Egreso', () async {
      final egreso = await egresoDePrueba();
      final gastoAntes = (await db.select(db.egreso).get())
          .where((e) => e.estatus == 'registrado')
          .fold<int>(0, (s, e) => s + e.monto);

      await corregir.ejecutar(egresoId: egreso.id, cuentaFinancieraId: bbva.id, motivo: 'Reconciliación');

      final gastoDespues = (await db.select(db.egreso).get())
          .where((e) => e.estatus == 'registrado')
          .fold<int>(0, (s, e) => s + e.monto);
      expect(gastoDespues, gastoAntes);
    });
  });

  group('D, E, F y P — lo que se rechaza', () {
    test('D: cuenta → null se rechaza', () async {
      final egreso = await egresoDePrueba(cuentaFinancieraId: bbva.id);
      expect(
        await corregir.ejecutar(egresoId: egreso.id, cuentaFinancieraId: null, motivo: 'Quitarla'),
        isA<CorregirOrigenFinancieroEgresoNoPuedeQuedarSinCuenta>(),
      );
      expect((await egresoRepo.obtenerPorId(egreso.id))!.cuentaFinancieraId, bbva.id);
    });

    test('E: la misma cuenta se rechaza como no-op explícito', () async {
      final egreso = await egresoDePrueba(cuentaFinancieraId: bbva.id);
      expect(
        await corregir.ejecutar(egresoId: egreso.id, cuentaFinancieraId: bbva.id, motivo: 'Igual'),
        isA<CorregirOrigenFinancieroEgresoSinCambio>(),
      );
      expect(
        (await db.select(db.egresoEvento).get()).where((e) => e.tipoEvento == 'corregido'),
        isEmpty,
        reason: 'no se asienta una corrección que no corrige nada',
      );
    });

    test('F: un Egreso cancelado no se corrige', () async {
      final egreso = await egresoDePrueba(cuentaFinancieraId: bbva.id);
      await egresoRepo.cancelar(egresoId: egreso.id, motivo: 'Error');
      expect(
        await corregir.ejecutar(egresoId: egreso.id, cuentaFinancieraId: banorte.id, motivo: 'Reasignar'),
        isA<CorregirOrigenFinancieroEgresoCancelado>(),
      );
    });

    test('P: un Egreso financiado con TARJETA nunca se vuelve bancario', () async {
      final tarjeta = await db.into(db.deuda).insertReturning(
            DeudaCompanion.insert(
              folio: 'DEU-TDC',
              nombre: 'TDC',
              tipo: TipoDeuda.tarjetaCredito.name,
              saldoActual: 0,
              tarjetaLimiteCredito: const Value(5000000),
            ),
          );
      final egreso = await egresoRepo.crear(
        folioEgreso: 'EGR-TDC',
        monto: 200000,
        fecha: DateTime(2026, 9, 20),
        deudaId: tarjeta.id,
        formaPago: 'tarjeta',
        concepto: 'Gasto con TDC',
      );
      expect(
        await corregir.ejecutar(egresoId: egreso.id, cuentaFinancieraId: bbva.id, motivo: 'Reasignar'),
        isA<CorregirOrigenFinancieroEgresoFinanciadoConTarjeta>(),
      );
      expect(await saldo(bbva.id), 5000000, reason: 'un cargo a crédito no sale del banco');
    });

    test('el motivo es obligatorio, y una cuenta inexistente se rechaza', () async {
      final egreso = await egresoDePrueba();
      expect(
        await corregir.ejecutar(egresoId: egreso.id, cuentaFinancieraId: bbva.id, motivo: '   '),
        isA<CorregirOrigenFinancieroEgresoMotivoRequerido>(),
      );
      expect(
        await corregir.ejecutar(egresoId: egreso.id, cuentaFinancieraId: 'no-existe', motivo: 'X'),
        isA<CorregirOrigenFinancieroEgresoCuentaInvalida>(),
      );
      expect((await egresoRepo.obtenerPorId(egreso.id))!.cuentaFinancieraId, isNull);
    });
  });

  group('M — auditoría', () {
    test('queda el antes, el después, el actor y el motivo', () async {
      final egreso = await egresoDePrueba(cuentaFinancieraId: bbva.id, monto: 500000);
      await corregir.ejecutar(
        egresoId: egreso.id,
        cuentaFinancieraId: banorte.id,
        motivo: 'Salió de Banorte.',
        actorUsuarioId: 'usuario-maestro',
      );

      // Hay además el asiento 'registrado' del alta: se busca el de la corrección.
      final evento =
          (await db.select(db.egresoEvento).get()).singleWhere((e) => e.tipoEvento == 'corregido');
      expect(evento.egresoId, egreso.id);
      expect(evento.actorUsuarioId, 'usuario-maestro');
      expect(evento.observacion, contains('Corrección de origen financiero (Maestro)'));
      expect(evento.observacion, contains('Salió de Banorte.'));
      expect(evento.estadoAnterior, contains(bbva.id), reason: 'la cuenta anterior');
      expect(evento.estadoNuevo, contains(banorte.id), reason: 'la cuenta nueva');
    });
  });

  group('C — la frontera Maestro', () {
    test('un usuario NO Maestro no puede, ni con todos los permisos', () async {
      final egreso = await egresoDePrueba();
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          sesionControllerProvider.overrideWith(_SesionUsuarioNormal.new),
        ],
      );
      addTearDown(container.dispose);

      final resultado = await container.read(corregirOrigenFinancieroEgresoAutorizadoProvider)(
        egresoId: egreso.id,
        cuentaFinancieraId: bbva.id,
        motivo: 'Intento',
      );
      expect(resultado, isA<CorregirOrigenFinancieroEgresoErrorInesperado>());
      expect((await egresoRepo.obtenerPorId(egreso.id))!.cuentaFinancieraId, isNull);
      expect(await saldo(bbva.id), 5000000, reason: 'ningún saldo se movió');
    });

    test('el Maestro sí puede, y el actor queda registrado', () async {
      final egreso = await egresoDePrueba();
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          sesionControllerProvider.overrideWith(_SesionMaestro.new),
        ],
      );
      addTearDown(container.dispose);

      final resultado = await container.read(corregirOrigenFinancieroEgresoAutorizadoProvider)(
        egresoId: egreso.id,
        cuentaFinancieraId: bbva.id,
        motivo: 'Reconciliación de PAGN-000005.',
      );
      expect(resultado, isA<CorregirOrigenFinancieroEgresoExitoso>());
      expect(await saldo(bbva.id), 5000000 - 1175000);
      final corregido =
          (await db.select(db.egresoEvento).get()).singleWhere((e) => e.tipoEvento == 'corregido');
      expect(corregido.actorUsuarioId, 'usuario-maestro');
    });
  });

  group('Política de saldo (v91) — corrección Maestro del origen', () {
    test('A) la cuenta destino tiene fondos: la corrección pasa y ambas cuentas se mueven', () async {
      final egreso = await egresoRepo.crear(
        folioEgreso: 'EGR-SALDO-OK',
        monto: 1000000,
        fecha: DateTime(2026, 6, 15),
        cuentaFinancieraId: bbva.id,
        formaPago: 'transferencia',
        concepto: 'Gasto',
      );

      final resultado = await corregir.ejecutar(
        egresoId: egreso.id,
        cuentaFinancieraId: banorte.id,
        motivo: 'Salió de Banorte.',
        actorUsuarioId: 'usuario-maestro',
      );

      expect(resultado, isA<CorregirOrigenFinancieroEgresoExitoso>());
      expect(await cuentasFinancieras.calcularSaldo(bbva.id), 5000000, reason: 'BBVA recupera');
      expect(await cuentasFinancieras.calcularSaldo(banorte.id), 3000000 - 1000000, reason: 'Banorte lo pierde');
    });

    test('B y C) la cuenta destino NO alcanza: rechaza y NADA se mueve', () async {
      final egreso = await egresoRepo.crear(
        folioEgreso: 'EGR-SALDO-NO',
        monto: 4000000,
        fecha: DateTime(2026, 6, 15),
        cuentaFinancieraId: bbva.id,
        formaPago: 'transferencia',
        concepto: 'Gasto grande',
      );

      // Banorte tiene $30,000 y el gasto es de $40,000. La excepcion se
      // propaga para que la pantalla muestre los tres numeros, en vez de
      // un "error inesperado".
      await expectLater(
        corregir.ejecutar(
          egresoId: egreso.id,
          cuentaFinancieraId: banorte.id,
          motivo: 'Salió de Banorte.',
          actorUsuarioId: 'usuario-maestro',
        ),
        throwsA(isA<SaldoInsuficienteException>()),
      );
      expect(
        await cuentasFinancieras.calcularSaldo(bbva.id),
        5000000 - 4000000,
        reason: 'el gasto sigue en BBVA, intacto',
      );
      expect(await cuentasFinancieras.calcularSaldo(banorte.id), 3000000, reason: 'Banorte jamás se tocó');

      final fuentes = await (db.select(db.egresoFuente)..where((t) => t.egresoId.equals(egreso.id))).get();
      expect(fuentes, hasLength(1));
      expect(fuentes.single.cuentaFinancieraId, bbva.id, reason: 'la fuente no se sustituyó');
      expect(fuentes.single.importe, 4000000);
    });
  });
}
