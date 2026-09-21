// §20 — invalidación tras cada operación.
//
// El listado, el expediente, Finanzas y el Dashboard tienen que
// reflejar el cambio **sin reiniciar la app**. Lo que se comprueba no
// es que se llame a `invalidate()` —eso sería probar la implementación—
// sino el efecto: leer el provider después de la operación devuelve el
// dato nuevo.
//
// También se comprueba lo contrario, que es igual de importante:
// programar una cobertura NO invalida Finanzas, porque no movió un solo
// peso y recargar Egresos ahí le mentiría al usuario sobre lo que acaba
// de pasar.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/finanzas/presentation/cuentas_por_cobrar/cuentas_por_cobrar_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/egresos/egresos_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/ingresos/ingresos_controller.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/totales_venta_eventual.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/agregar_cobertura_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/agregar_participante_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/crear_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/data/tables/servicio_eventual_table.dart';
import 'package:riseg_one/features/servicios_eventuales/presentation/servicios_eventuales_controller.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

class _SesionMaestro extends SesionController {
  @override
  SesionUsuario? build() => const SesionUsuario(
        usuarioId: 'maestro',
        nombre: 'Maestro de prueba',
        nombreUsuario: 'maestro',
        esMaestro: true,
        permisos: {},
      );
}

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late CuentaFinancieraData cuentaBanco;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    // El actor de la sesion tiene que existir de verdad:
    // actorUsuarioId es una FK real, no un texto libre.
    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(
            id: const Value('maestro'),
            nombre: 'Maestro de prueba',
            nombreUsuario: 'maestro',
            passwordHash: r'pbkdf2$1$c2FsdA==$aGFzaA==',
            esMaestro: const Value(true),
          ),
        );
    cuentaBanco = await db.into(db.cuentaFinanciera).insertReturning(
          CuentaFinancieraCompanion.insert(
            codigo: 'CF-BBVA',
            nombre: 'BBVA',
            tipo: 'cuenta',
            saldoInicial: 100000000, // fondeada: la v91 rechaza salidas sin saldo
            fechaSaldoInicial: DateTime(2026, 1, 1),
          ),
        );

    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionMaestro.new),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(db.close);
  });

  /// Un provider autoDispose sin oyentes se destruye entre lecturas y
  /// su carga vuelve a empezar: para medir invalidacion hay que
  /// mantenerlo vivo, igual que lo mantiene vivo una pantalla abierta.
  void mantenerVivo<T>(ProviderListenable<T> provider) {
    container.listen<T>(provider, (_, __) {}, fireImmediately: true);
  }

  ServiciosEventualesController notifier() =>
      container.read(serviciosEventualesControllerProvider.notifier);

  /// Espera a que los controladores terminen de recargar.
  ///
  /// Un `Duration.zero` no basta: `_cargar` encadena varias consultas,
  /// y medir "ya se actualizó" antes de que termine daría un falso
  /// negativo que no dice nada sobre la invalidación.
  Future<void> asentar() async {
    for (var intento = 0; intento < 50; intento++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      if (!container.read(serviciosEventualesControllerProvider).cargando) return;
    }
  }

  Future<CrearServicioEventualExitoso> vender({int importe = 1000000}) async {
    final resultado = await notifier().crear(
      nombre: 'Concierto plaza',
      fechaHoraInicio: DateTime(2026, 5, 1),
      fechaHoraFin: DateTime(2026, 5, 2),
      importeAcordado: importe,
      tipoSolicitante: TipoSolicitanteServicioEventual.eventual,
      solicitanteNombre: 'Promotora Norte',
      tratamientoIva: TratamientoIva.masIva,
    );
    return resultado as CrearServicioEventualExitoso;
  }

  test('vender aparece en el listado y en Cuentas por cobrar sin reiniciar', () async {
    // Se leen los dos providers ANTES: así se prueba invalidación real,
    // no simplemente que la primera lectura traiga el dato.
    mantenerVivo(serviciosEventualesControllerProvider);
    mantenerVivo(cuentasPorCobrarControllerProvider);
    await asentar();

    final venta = await vender();
    await asentar();

    expect(
      container.read(serviciosEventualesControllerProvider).renglones.map((r) => r.servicioEventual.id),
      contains(venta.servicioEventual.id),
    );
    expect(
      container.read(cuentasPorCobrarControllerProvider).cuentas.map((c) => c.id),
      contains(venta.cuenta.id),
      reason: 'la CxC nueva tiene que verse en Finanzas sin reiniciar',
    );
  });

  test('corregir el importe actualiza el total del listado y el saldo de la CxC', () async {
    final venta = await vender(importe: 1000000);
    mantenerVivo(serviciosEventualesControllerProvider);
    mantenerVivo(cuentasPorCobrarControllerProvider);
    await asentar();

    await notifier().corregir(
      servicioEventualId: venta.servicioEventual.id,
      importeAcordado: 2000000,
      motivo: 'Se renegoció',
    );
    await asentar();

    final renglon = container
        .read(serviciosEventualesControllerProvider)
        .renglones
        .firstWhere((r) => r.servicioEventual.id == venta.servicioEventual.id);
    expect(renglon.totalVenta, 2320000);
    expect(renglon.pendiente, 2320000);

    final cuenta = container
        .read(cuentasPorCobrarControllerProvider)
        .cuentas
        .firstWhere((c) => c.id == venta.cuenta.id);
    expect(cuenta.saldoPendiente, 2320000);
  });

  test('cobrar al cliente se refleja en el listado, en la CxC y en Ingresos', () async {
    final venta = await vender(importe: 1000000);
    mantenerVivo(serviciosEventualesControllerProvider);
    mantenerVivo(cuentasPorCobrarControllerProvider);
    mantenerVivo(ingresosControllerProvider);
    await asentar();

    await notifier().registrarCobro(
      servicioEventualId: venta.servicioEventual.id,
      monto: 500000,
      fechaPago: DateTime(2026, 5, 10),
      formaPago: FormaPago.transferencia.name,
      cuentaFinancieraId: cuentaBanco.id,
    );
    await asentar();

    final renglon = container
        .read(serviciosEventualesControllerProvider)
        .renglones
        .firstWhere((r) => r.servicioEventual.id == venta.servicioEventual.id);
    expect(renglon.cobrado, 500000);
    expect(renglon.pendiente, 660000);

    expect(
      container.read(cuentasPorCobrarControllerProvider).cuentas.firstWhere((c) => c.id == venta.cuenta.id).saldoPendiente,
      660000,
    );
    expect(container.read(ingresosControllerProvider).ingresos, hasLength(1));
  });

  group('pagar a quien cubrió', () {
    Future<ServicioEventualCoberturaData> nuevaCobertura(String eventualId) async {
      final participante = ((await notifier().agregarParticipante(
        servicioEventualId: eventualId,
        nombreExterno: 'Refuerzo externo',
      )) as AgregarParticipanteServicioEventualExitoso)
          .participante;
      return ((await notifier().agregarCobertura(
        servicioEventualId: eventualId,
        participanteId: participante.id,
        fecha: DateTime(2026, 5, 1),
        horaInicioMinutos: 8 * 60,
        horaFinMinutos: 20 * 60,
        importeAcordado: 200000,
      )) as AgregarCoberturaServicioEventualExitoso)
          .cobertura;
    }

    test('programar NO recarga Egresos: no movió un solo peso', () async {
      final venta = await vender();
      mantenerVivo(egresosControllerProvider);
      await asentar();

      await nuevaCobertura(venta.servicioEventual.id);
      await asentar();

      expect(
        container.read(egresosControllerProvider).egresos,
        isEmpty,
        reason: 'programar una cobertura no genera gasto, y la pantalla no debe fingir que sí',
      );
    });

    test('pagar y revertir se reflejan en Egresos en el mismo ciclo', () async {
      final venta = await vender();
      final cobertura = await nuevaCobertura(venta.servicioEventual.id);
      mantenerVivo(egresosControllerProvider);
      await asentar();

      await notifier().pagarCobertura(
        coberturaId: cobertura.id,
        formaPago: FormaPago.transferencia.name,
        cuentaFinancieraId: cuentaBanco.id,
      );
      await asentar();
      expect(container.read(egresosControllerProvider).egresos, hasLength(1));

      await notifier().revertirPagoCobertura(coberturaId: cobertura.id, motivo: 'Error de captura');
      await asentar();
      expect(
        container.read(egresosControllerProvider).egresos.single.estatus,
        'cancelado',
        reason: 'la reversión tiene que verse sin reiniciar',
      );
    });
  });

  test('cancelar el eventual se refleja en el listado', () async {
    final venta = await vender();
    mantenerVivo(serviciosEventualesControllerProvider);
    await asentar();

    await notifier().cancelar(servicioEventualId: venta.servicioEventual.id, motivo: 'Se cayó el evento');
    await asentar();

    final renglon = container
        .read(serviciosEventualesControllerProvider)
        .renglones
        .firstWhere((r) => r.servicioEventual.id == venta.servicioEventual.id);
    expect(renglon.servicioEventual.estatus, EstatusServicioEventual.cancelado.name);
  });
}
