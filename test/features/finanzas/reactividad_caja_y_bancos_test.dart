// Reactividad de "Caja y bancos" del Dashboard.
//
// El bug real: tras corregir el origen financiero de EGR-000071
// (null → Klar Empresarial), Cuentas financieras mostraba $56,776.44 y
// el Dashboard seguía en $68,526.44 — exactamente los $11,750 del
// Egreso. La corrección llamaba al provider autorizado desde el
// diálogo, saltándose la invalidación que el controlador sí hace.
//
// Por eso estas pruebas NUNCA recrean el ProviderContainer: eso
// ocultaría justo el fallo. Se mantiene UN consumidor vivo —como la
// pantalla abierta— y se comprueba que recibe el valor nuevo.

import 'package:riseg_one/features/finanzas/domain/politica_saldo_cuenta.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/finanzas/finanzas_providers.dart' show obtenerPosicionDeCajaUseCaseProvider;
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/domain/origen_financiero_gasto.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/corregir_origen_financiero_egreso_usecase.dart';
import 'package:riseg_one/features/finanzas/presentation/cuentas_financieras/cuentas_financieras_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/egresos/egresos_controller.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

/// Anota qué providers se invalidan: es la única forma de comprobar
/// que el Dashboard fue avisado sin construirlo (su árbol real exige
/// `appPathsProvider`, que sólo existe en bootstrap).
class _Observador extends ProviderObserver {
  final invalidados = <String>[];

  @override
  void didDisposeProvider(ProviderBase<Object?> provider, ProviderContainer container) {
    invalidados.add(provider.name ?? provider.runtimeType.toString());
  }
}

// PRIVADA TAMBIÉN LA VARIABLE: una global pública de un tipo privado es lo que el
// analizador señala, y aquí sólo la usa este archivo.
late _Observador _observador;

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

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late EgresoRepositoryImpl egresoRepo;
  late CuentaFinancieraData klar;
  late CuentaFinancieraData bbva;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(
            id: const Value('usuario-maestro'),
            nombre: 'MARLON',
            nombreUsuario: 'MARLONRH',
            passwordHash: r'pbkdf2$1$c2FsdA==$aGFzaA==',
            esMaestro: const Value(true),
          ),
        );
    egresoRepo = EgresoRepositoryImpl(db);

    // Los saldos reales del caso: 63,827.77 y 4,698.67 → 68,526.44.
    klar = await db.into(db.cuentaFinanciera).insertReturning(
          CuentaFinancieraCompanion.insert(
            codigo: 'CF-KLAR',
            nombre: 'Klar Empresarial',
            tipo: 'banco',
            saldoInicial: 6382777,
            fechaSaldoInicial: DateTime(2026, 1, 1),
          ),
        );
    bbva = await db.into(db.cuentaFinanciera).insertReturning(
          CuentaFinancieraCompanion.insert(
            codigo: 'CF-BBVA',
            nombre: 'BBVA Empresarial',
            tipo: 'banco',
            saldoInicial: 469867,
            fechaSaldoInicial: DateTime(2026, 1, 1),
          ),
        );

    _observador = _Observador();
    container = ProviderContainer(
      observers: [_observador],
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionMaestro.new),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(db.close);
  });

  /// "Caja y bancos" tal como lo obtiene el Dashboard: del MISMO caso
  /// de uso canónico (`ObtenerPosicionDeCajaUseCase`), nunca de una
  /// fórmula propia de la prueba.
  Future<int> cajaYBancos() async {
    await _asentar(container);
    final posicion = await container.read(obtenerPosicionDeCajaUseCaseProvider).ejecutar();
    return posicion.saldoDisponible;
  }

  /// ¿Se avisó al Dashboard de que su estado dejó de ser cierto?
  bool dashboardInvalidado() =>
      _observador.invalidados.any((n) => n.toLowerCase().contains('dashboard'));

  Future<EgresoData> egresoSinCuenta({int monto = 1175000}) => egresoRepo.crear(
        folioEgreso: 'EGR-000071',
        monto: monto,
        fecha: DateTime(2026, 9, 20),
        formaPago: 'transferencia',
        concepto: 'Pago de Nómina PAGN-000005',
      );

  /// Consumidores vivos, como las pantallas abiertas: sin un listener,
  /// un provider autoDispose se reconstruye en cada lectura y la prueba
  /// pasaría aunque nadie invalidara nada.
  Future<void> mantenerVivos() async {
    container.listen(cuentasFinancierasControllerProvider, (_, __) {}, fireImmediately: true);
    container.listen(egresosControllerProvider, (_, __) {}, fireImmediately: true);
    await _asentar(container);
    _observador.invalidados.clear();
  }

  test('null → cuenta: el Dashboard baja el monto sin recrear nada', () async {
    final egreso = await egresoSinCuenta();
    await mantenerVivos();

    expect(await cajaYBancos(), 6382777 + 469867, reason: 'el Egreso sin cuenta no descuenta de nadie');

    final resultado = await container
        .read(egresosControllerProvider.notifier)
        .corregirOrigenFinanciero(
          egresoId: egreso.id,
          cuentaFinancieraId: klar.id,
          motivo: 'Pago de nómina registrado sin cuenta.',
        );
    expect(resultado, isA<CorregirOrigenFinancieroEgresoExitoso>());

    // El MISMO contenedor, el MISMO consumidor.
    expect(await cajaYBancos(), 6382777 + 469867 - 1175000);
    expect(dashboardInvalidado(), isTrue,
        reason: 'el Dashboard tenía el valor viejo en su estado: hay que avisarle');

    final saldos = container.read(cuentasFinancierasControllerProvider).saldosPorCuenta;
    expect(saldos[klar.id], 6382777 - 1175000);
    expect(saldos[bbva.id], 469867);
  });

  test('cuenta A → cuenta B con fondos: el total no cambia, pero ambas cuentas sí', () async {
    // Un importe que BBVA sí puede absorber. La versión anterior de
    // esta prueba movía $11,750 a una cuenta con $4,698.67 y
    // afirmaba que BBVA quedaba en negativo: exactamente lo que la
    // v91 prohíbe. El caso sin fondos se prueba abajo.
    final egreso = await egresoRepo.crear(
      folioEgreso: 'EGR-000099',
      monto: 400000,
      fecha: DateTime(2026, 9, 20),
      cuentaFinancieraId: klar.id,
      formaPago: 'transferencia',
      concepto: 'Gasto',
    );
    await mantenerVivos();
    final totalAntes = await cajaYBancos();

    await container.read(egresosControllerProvider.notifier).corregirOrigenFinanciero(
          egresoId: egreso.id,
          cuentaFinancieraId: bbva.id,
          motivo: 'Salió de BBVA.',
        );

    expect(await cajaYBancos(), totalAntes, reason: 'el total de Caja y bancos no se mueve');
    // "El total no cambia" NO significa "no hay que invalidar": las dos
    // cuentas sí cambiaron.
    expect(dashboardInvalidado(), isTrue);
    final saldos = container.read(cuentasFinancierasControllerProvider).saldosPorCuenta;
    expect(saldos[klar.id], 6382777, reason: 'Klar recupera exactamente el monto');
    expect(saldos[bbva.id], 469867 - 400000, reason: 'BBVA lo pierde');
  });

  test('cuenta A → cuenta B SIN fondos: se rechaza y ningún saldo se mueve', () async {
    final egreso = await egresoRepo.crear(
      folioEgreso: 'EGR-000098',
      monto: 1175000,
      fecha: DateTime(2026, 9, 20),
      cuentaFinancieraId: klar.id,
      formaPago: 'transferencia',
      concepto: 'Gasto',
    );
    await mantenerVivos();
    final totalAntes = await cajaYBancos();

    // BBVA tiene $4,698.67 y el gasto es de $11,750. La excepcion se
    // propaga hasta la pantalla, que la traduce con el mensaje central.
    await expectLater(
      container.read(egresosControllerProvider.notifier).corregirOrigenFinanciero(
        egresoId: egreso.id,
        cuentaFinancieraId: bbva.id,
        motivo: 'Salió de BBVA.',
      ),
      throwsA(isA<SaldoInsuficienteException>()),
    );
    expect(await cajaYBancos(), totalAntes);
    final saldos = container.read(cuentasFinancierasControllerProvider).saldosPorCuenta;
    expect(saldos[klar.id], 6382777 - 1175000, reason: 'el gasto sigue en Klar, intacto');
    expect(saldos[bbva.id], 469867, reason: 'BBVA jamás se tocó');
  });

  test('las mutaciones financieras del mismo controlador también refrescan el Dashboard', () async {
    await mantenerVivos();
    final inicial = await cajaYBancos();

    // Alta de Egreso desde cuenta: Caja baja.
    final registrado = await container.read(egresosControllerProvider.notifier).registrar(
          monto: 500000,
          fecha: DateTime(2026, 9, 21),
          concepto: 'Gasto manual',
          formaPago: 'transferencia',
          origen: OrigenFinancieroCuenta(klar.id),
        );
    expect(await cajaYBancos(), inicial - 500000);
    expect(dashboardInvalidado(), isTrue);

    // Cancelarlo: Caja vuelve.
    final egresoId = (await db.select(db.egreso).get()).single.id;
    expect(registrado, isNotNull);
    await container
        .read(egresosControllerProvider.notifier)
        .cancelar(egresoId: egresoId, motivo: 'Error de captura');
    expect(await cajaYBancos(), inicial);
  });
}

/// Deja que la recarga asíncrona de los controladores termine.
///
/// `Duration.zero` no basta: `_cargar` encadena varias consultas, y
/// medir antes de que terminen daría un falso negativo que no dice nada
/// sobre la invalidación.
Future<void> _asentar(ProviderContainer container) async {
  for (var intento = 0; intento < 60; intento++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    if (!container.read(cuentasFinancierasControllerProvider).cargando &&
        !container.read(egresosControllerProvider).cargando) {
      return;
    }
  }
}
