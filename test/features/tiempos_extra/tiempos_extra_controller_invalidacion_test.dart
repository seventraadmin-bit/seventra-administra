// Auditoría de integración financiera de Tiempos Extra (2026-09-07,
// punto 5 del diagnóstico) — `TiemposExtraController` no invalidaba
// `cuentasFinancierasControllerProvider`/`deudasCreditoControllerProvider`
// tras registrar/cancelar, a diferencia de `ComprasController` que sí
// lo hace en un caso estructuralmente idéntico (una operación puede
// afectar una CuentaFinanciera o una Deuda). Ejercita la cadena REAL de
// providers (nunca construcción directa de repos/casos de uso), mismo
// criterio que `deuda_pago_reflejo_integration_test.dart`.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/finanzas/data/tables/cuenta_financiera_table.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_deuda_usecase.dart';
import 'package:riseg_one/features/finanzas/finanzas_providers.dart';
import 'package:riseg_one/features/finanzas/presentation/cuentas_financieras/cuentas_financieras_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/deudas_credito/deudas_credito_controller.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_servicio_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/tiempos_extra/data/tables/tiempo_extra_table.dart';
import 'package:riseg_one/features/tiempos_extra/domain/repositories/tiempo_extra_repository.dart';
import 'package:riseg_one/features/tiempos_extra/domain/usecases/cancelar_tiempo_extra_usecase.dart';
import 'package:riseg_one/features/tiempos_extra/domain/usecases/corregir_tiempo_extra_usecase.dart';
import 'package:riseg_one/features/tiempos_extra/domain/usecases/registrar_tiempo_extra_usecase.dart';
import 'package:riseg_one/features/tiempos_extra/presentation/tiempos_extra_controller.dart';
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

/// Sondeo acotado (nunca `pumpAndSettle` — esto no es un widget test): si
/// la invalidación automática NO ocurre, `condicion` ya es verdadera (o
/// falsa para siempre) desde el primer intento y el `expect` posterior
/// falla por el VALOR incorrecto, nunca por timeout — determinista en
/// ambos sentidos.
Future<void> _esperarHasta(bool Function() condicion, {int intentos = 100}) async {
  for (var i = 0; i < intentos && !condicion(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late String servicioId;
  late String empleadoAusenteId;
  late String turnoId;

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

    final asignacionServicioRepo = AsignacionServicioRepositoryImpl(db);
    final servicioRepo = ServicioRepositoryImpl(db, asignacionServicioRepo);
    final clienteRepo = ClienteRepositoryImpl(db);
    final catalogoRepo = CatalogoRepositoryImpl(db);
    final codigoSecuencia = CodigoSecuenciaService(db);

    final cliente = await clienteRepo.crear(ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Sportium'));
    final servicioCreado = await CrearServicioUseCase(servicioRepo, GenerarCodigoUseCase(codigoSecuencia), ServicioValidator(clienteRepo, catalogoRepo))
        .ejecutar(
      clienteId: cliente.id,
      borrador: ServicioBorrador(nombre: 'Vigilancia Sportium', tipoServicioId: SeedIds.tipoServicioVigilanciaFija, fechaInicio: DateTime(2026, 1, 1)),
    );
    servicioId = (servicioCreado as GuardarServicioExitoso).servicio.id;

    final empleado = await db.into(db.empleado).insertReturning(
          EmpleadoCompanion.insert(
            numeroEmpleado: 1,
            nombres: 'Monica',
            apellidoPaterno: 'Ausente',
            sexo: 'femenino',
            fechaNacimiento: DateTime(1990, 1, 1),
            curp: 'PEXJ900101MDFXXX01',
            rfc: 'PEXJ90010101',
            nss: '10000000001',
            estadoCivil: 'soltero',
            fechaIngreso: DateTime(2025, 1, 1),
            aniosExperienciaSeguridad: 3,
          ),
        );
    empleadoAusenteId = empleado.id;
    turnoId = SeedIds.modalidadTurno24x24;

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

  Future<CuentaFinancieraData> crearCuenta({required int saldoInicial}) {
    return container.read(cuentaFinancieraRepositoryProvider).crear(
          codigo: 'CTA-000001',
          nombre: 'BBVA Empresarial',
          tipo: TipoCuentaFinanciera.banco.name,
          saldoInicial: saldoInicial,
          fechaSaldoInicial: DateTime(2026, 1, 1),
        );
  }

  Future<DeudaData> crearTarjeta({required String nombre, required int limite, int saldoInicial = 0}) async {
    final resultado = await container.read(registrarDeudaAutorizadoProvider)(
      nombre: nombre,
      tipo: 'tarjetaCredito',
      saldoInicial: saldoInicial,
      fechaOrigen: saldoInicial > 0 ? DateTime(2026, 1, 1) : null,
      tarjetaLimiteCredito: limite,
    );
    return (resultado as RegistrarDeudaExitoso).deuda;
  }

  test(
    'registrar un Tiempo Extra pagado desde una CuentaFinanciera invalida cuentasFinancierasControllerProvider automáticamente',
    () async {
      final cuenta = await crearCuenta(saldoInicial: 1000000);

      // Mantiene vivo el provider (autoDispose se destruiría sin
      // listeners) y captura su carga inicial.
      container.listen(cuentasFinancierasControllerProvider, (_, __) {}, fireImmediately: true);
      await _esperarHasta(() => container.read(cuentasFinancierasControllerProvider).cargando == false);
      expect(container.read(cuentasFinancierasControllerProvider).saldosPorCuenta[cuenta.id], 1000000);

      final resultado = await container.read(tiemposExtraControllerProvider.notifier).registrar(
            fecha: DateTime(2026, 9, 3),
            servicioId: servicioId,
            origenCobertura: OrigenCoberturaTiempoExtra.ausenciaEmpleado.name,
            empleadoAusenteId: empleadoAusenteId,
            motivoAusencia: MotivoAusenciaTiempoExtra.faltaInjustificada.name,
            nombreExternoCubre: 'Pedro Externo',
            turnoId: turnoId,
            montoTiempoExtra: 162000,
            formaPago: 'transferencia',
            cuentaFinancieraId: cuenta.id,
          );
      expect(resultado, isA<RegistrarTiempoExtraExitoso>());

      // Sin invalidación, `saldosPorCuenta` se quedaría en 1,000,000
      // para siempre — la aserción fallaría por VALOR, no por timeout.
      await _esperarHasta(
        () => container.read(cuentasFinancierasControllerProvider).cargando == false && container.read(cuentasFinancierasControllerProvider).saldosPorCuenta[cuenta.id] != 1000000,
      );
      expect(container.read(cuentasFinancierasControllerProvider).saldosPorCuenta[cuenta.id], 1000000 - 162000);
    },
  );

  test(
    'registrar un costo adicional pagado con TDC invalida deudasCreditoControllerProvider automáticamente',
    () async {
      final konfio = await crearTarjeta(nombre: 'Konfío', limite: 4000000);

      container.listen(deudasCreditoControllerProvider, (_, __) {}, fireImmediately: true);
      await _esperarHasta(() => container.read(deudasCreditoControllerProvider).cargando == false);
      expect(container.read(deudasCreditoControllerProvider).deudas.single.saldoActual, 0);

      final resultado = await container.read(tiemposExtraControllerProvider.notifier).registrar(
            fecha: DateTime(2026, 9, 3),
            servicioId: servicioId,
            origenCobertura: OrigenCoberturaTiempoExtra.ausenciaEmpleado.name,
            empleadoAusenteId: empleadoAusenteId,
            motivoAusencia: MotivoAusenciaTiempoExtra.faltaInjustificada.name,
            nombreExternoCubre: 'Pedro Externo',
            turnoId: turnoId,
            montoTiempoExtra: 1,
            formaPago: 'efectivo',
            costosAdicionales: [
              CostoAdicionalInput(concepto: 'Uber', monto: 35000, formaPago: 'tarjeta', deudaIdTarjeta: konfio.id),
            ],
          );
      expect(resultado, isA<RegistrarTiempoExtraExitoso>());

      await _esperarHasta(
        () => container.read(deudasCreditoControllerProvider).cargando == false && container.read(deudasCreditoControllerProvider).deudas.single.saldoActual != 0,
      );
      expect(container.read(deudasCreditoControllerProvider).deudas.single.saldoActual, 35000);
    },
  );

  test(
    'cancelar un Tiempo Extra con orígenes mixtos (Cuenta + TDC) invalida y refresca ambas vistas',
    () async {
      final cuenta = await crearCuenta(saldoInicial: 1000000);
      final konfio = await crearTarjeta(nombre: 'Konfío', limite: 4000000);

      final registrado = await container.read(tiemposExtraControllerProvider.notifier).registrar(
            fecha: DateTime(2026, 9, 3),
            servicioId: servicioId,
            origenCobertura: OrigenCoberturaTiempoExtra.ausenciaEmpleado.name,
            empleadoAusenteId: empleadoAusenteId,
            motivoAusencia: MotivoAusenciaTiempoExtra.faltaInjustificada.name,
            nombreExternoCubre: 'Pedro Externo',
            turnoId: turnoId,
            montoTiempoExtra: 162000,
            formaPago: 'transferencia',
            cuentaFinancieraId: cuenta.id,
            costosAdicionales: [
              CostoAdicionalInput(concepto: 'Uber', monto: 35000, formaPago: 'tarjeta', deudaIdTarjeta: konfio.id),
            ],
          );
      final tiempoExtra = (registrado as RegistrarTiempoExtraExitoso).tiempoExtra;

      container.listen(cuentasFinancierasControllerProvider, (_, __) {}, fireImmediately: true);
      container.listen(deudasCreditoControllerProvider, (_, __) {}, fireImmediately: true);
      await _esperarHasta(
        () =>
            container.read(cuentasFinancierasControllerProvider).cargando == false &&
            container.read(deudasCreditoControllerProvider).cargando == false,
      );
      expect(container.read(cuentasFinancierasControllerProvider).saldosPorCuenta[cuenta.id], 1000000 - 162000);
      expect(container.read(deudasCreditoControllerProvider).deudas.single.saldoActual, 35000);

      final cancelado = await container.read(tiemposExtraControllerProvider.notifier).cancelar(
            tiempoExtraId: tiempoExtra.id,
            motivo: 'Auditoría de integración financiera',
          );
      expect(cancelado, isA<CancelarTiempoExtraExitoso>());

      await _esperarHasta(
        () =>
            container.read(cuentasFinancierasControllerProvider).cargando == false &&
            container.read(cuentasFinancierasControllerProvider).saldosPorCuenta[cuenta.id] == 1000000 &&
            container.read(deudasCreditoControllerProvider).cargando == false &&
            container.read(deudasCreditoControllerProvider).deudas.single.saldoActual == 0,
      );
      expect(container.read(cuentasFinancierasControllerProvider).saldosPorCuenta[cuenta.id], 1000000, reason: 'la Cuenta debe recuperar exactamente su saldo previo');
      expect(container.read(deudasCreditoControllerProvider).deudas.single.saldoActual, 0, reason: 'Konfío debe revertir exactamente el cargo de Uber');

      // Segunda cancelación: sin efectos adicionales, ninguna vista
      // vuelve a cambiar.
      final segundaCancelacion = await container.read(tiemposExtraControllerProvider.notifier).cancelar(
            tiempoExtraId: tiempoExtra.id,
            motivo: 'De nuevo',
          );
      expect(segundaCancelacion, isA<CancelarTiempoExtraYaCancelado>());
      expect(container.read(cuentasFinancierasControllerProvider).saldosPorCuenta[cuenta.id], 1000000);
      expect(container.read(deudasCreditoControllerProvider).deudas.single.saldoActual, 0);
    },
  );

  test(
    'corregir un Tiempo Extra cambiando el pago base de Cuenta a TDC invalida y refresca ambas vistas',
    () async {
      final cuenta = await crearCuenta(saldoInicial: 1000000);
      final konfio = await crearTarjeta(nombre: 'Konfío', limite: 4000000);

      final registrado = await container.read(tiemposExtraControllerProvider.notifier).registrar(
            fecha: DateTime(2026, 9, 3),
            servicioId: servicioId,
            origenCobertura: OrigenCoberturaTiempoExtra.ausenciaEmpleado.name,
            empleadoAusenteId: empleadoAusenteId,
            motivoAusencia: MotivoAusenciaTiempoExtra.faltaInjustificada.name,
            nombreExternoCubre: 'Pedro Externo',
            turnoId: turnoId,
            montoTiempoExtra: 162000,
            formaPago: 'transferencia',
            cuentaFinancieraId: cuenta.id,
          );
      final tiempoExtra = (registrado as RegistrarTiempoExtraExitoso).tiempoExtra;

      container.listen(cuentasFinancierasControllerProvider, (_, __) {}, fireImmediately: true);
      container.listen(deudasCreditoControllerProvider, (_, __) {}, fireImmediately: true);
      await _esperarHasta(
        () =>
            container.read(cuentasFinancierasControllerProvider).cargando == false &&
            container.read(deudasCreditoControllerProvider).cargando == false,
      );
      expect(container.read(cuentasFinancierasControllerProvider).saldosPorCuenta[cuenta.id], 1000000 - 162000);

      final corregido = await container.read(tiemposExtraControllerProvider.notifier).corregir(
            tiempoExtraId: tiempoExtra.id,
            fecha: tiempoExtra.fecha,
            servicioId: servicioId,
            origenCobertura: OrigenCoberturaTiempoExtra.ausenciaEmpleado.name,
            empleadoAusenteId: empleadoAusenteId,
            motivoAusencia: tiempoExtra.motivoAusencia,
            nombreExternoCubre: 'Pedro Externo',
            turnoId: turnoId,
            montoTiempoExtra: 162000,
            formaPago: 'tarjeta',
            deudaIdTarjeta: konfio.id,
            motivo: 'En realidad se pagó con TDC',
          );
      expect(corregido, isA<CorregirTiempoExtraExitoso>());

      await _esperarHasta(
        () =>
            container.read(cuentasFinancierasControllerProvider).cargando == false &&
            container.read(cuentasFinancierasControllerProvider).saldosPorCuenta[cuenta.id] == 1000000 &&
            container.read(deudasCreditoControllerProvider).cargando == false &&
            container.read(deudasCreditoControllerProvider).deudas.single.saldoActual == 162000,
      );
      expect(container.read(cuentasFinancierasControllerProvider).saldosPorCuenta[cuenta.id], 1000000, reason: 'la Cuenta recupera el monto — el Egreso viejo se canceló');
      expect(container.read(deudasCreditoControllerProvider).deudas.single.saldoActual, 162000, reason: 'Konfío recibe el cargo completo');
    },
  );
}
