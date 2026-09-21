// Etapa "Vehículos: origen financiero" (schemaVersion 80) — la VÍA DE
// PROVIDERS.
//
// Existe aparte de `vehiculo_gasto_origen_financiero_test.dart` por una
// razón concreta y ya vivida en este proyecto: un ciclo de dependencias
// de Riverpod es INVISIBLE para cualquier prueba que construya los
// repositorios a mano. Aquí Vehículos depende de Finanzas (Egreso/Deuda)
// y Finanzas depende de Vehículos (`ObtenerOrigenAutomaticoEgreso`,
// `ClasificarEgresosPorOrigen`) — exactamente la forma que produjo un
// `CircularDependencyError` real en la etapa de Egresos v76.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/finanzas/domain/origen_financiero_gasto.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cancelar_egreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/corregir_egreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/obtener_origen_automatico_egreso_usecase.dart';
import 'package:riseg_one/features/finanzas/finanzas_providers.dart';
import 'package:riseg_one/features/finanzas/data/tables/deuda_table.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart';
import 'package:riseg_one/features/reportes/domain/usecases/clasificar_egresos_por_origen_usecase.dart';
import 'package:riseg_one/features/reportes/reportes_providers.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import 'package:riseg_one/features/vehiculos/data/tables/vehiculo_mantenimiento_table.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/registrar_mantenimiento_vehiculo_usecase.dart';
import 'package:riseg_one/features/vehiculos/vehiculos_providers.dart';

class _SesionMaestro extends SesionController {
  @override
  SesionUsuario? build() => const SesionUsuario(
        usuarioId: 'maestro',
        nombre: 'MARLON',
        nombreUsuario: 'marlon',
        esMaestro: true,
        permisos: {},
      );
}

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late String vehiculoId;
  late String bbvaId;
  late String konfioId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionMaestro.new),
        attachmentStorageProvider.overrideWithValue(AttachmentStorage('.')),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(db.close);

    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(
            id: const Value('maestro'),
            nombre: 'MARLON',
            nombreUsuario: 'marlon',
            passwordHash: r'pbkdf2$1$c2FsdA==$aGFzaA==',
            esMaestro: const Value(true),
          ),
        );

    final bbva = await container.read(cuentaFinancieraRepositoryProvider).crear(
          codigo: 'CTA-BBVA',
          nombre: 'BBVA Empresarial',
          tipo: 'banco',
          saldoInicial: 2000000,
          fechaSaldoInicial: DateTime(2026, 1, 1),
        );
    bbvaId = bbva.id;

    final konfio = await db.into(db.deuda).insertReturning(
          DeudaCompanion.insert(
            folio: 'DEU-KONFIO',
            nombre: 'TDC Konfío',
            tipo: TipoDeuda.tarjetaCredito.name,
            saldoActual: 0,
            tarjetaLimiteCredito: const Value(1500000),
          ),
        );
    konfioId = konfio.id;

    final vehiculo = await container.read(vehiculoRepositoryProvider).crear(
          codigo: 'VEH-000001',
          marca: 'Nissan',
          modelo: 'NP300',
          tipoVehiculo: 'pickup',
        );
    vehiculoId = vehiculo.id;
  });

  test('el grafo de providers se construye en AMBAS direcciones, sin ciclo', () {
    // Si Vehículos y Finanzas se referenciaran mutuamente vía `watch`,
    // cualquiera de estas líneas lanzaría `CircularDependencyError`.
    expect(() => container.read(registrarMantenimientoVehiculoUseCaseProvider), returnsNormally);
    expect(() => container.read(corregirMantenimientoVehiculoUseCaseProvider), returnsNormally);
    expect(() => container.read(cancelarMantenimientoVehiculoUseCaseProvider), returnsNormally);
    expect(() => container.read(obtenerOrigenAutomaticoEgresoUseCaseProvider), returnsNormally);
    expect(() => container.read(clasificarEgresosPorOrigenUseCaseProvider), returnsNormally);
    expect(() => container.read(corregirEgresoUseCaseProvider), returnsNormally);
  });

  Future<VehiculoMantenimientoData> registrarConCuenta() async {
    final r = await container.read(registrarMantenimientoVehiculoAutorizadoProvider)(
      vehiculoId: vehiculoId,
      fecha: DateTime(2026, 5, 10),
      tipo: TipoMantenimientoVehiculo.servicioGeneral.name,
      descripcion: 'Afinación',
      costo: 250000,
      origen: OrigenFinancieroCuenta(bbvaId),
    );
    return (r as RegistrarMantenimientoVehiculoExitoso).registro;
  }

  group('§9 — protección desde Finanzas', () {
    test('el Egreso de un mantenimiento NO se corrige desde Finanzas', () async {
      final registro = await registrarConCuenta();

      final r = await container.read(corregirEgresoUseCaseProvider).ejecutar(
            egresoId: registro.egresoId!,
            monto: 999999,
            motivo: 'Intento directo desde Finanzas',
          );

      expect(r, isA<CorregirEgresoOrigenAutomatico>(), reason: 'se resuelve desde el vehículo, no desde el Egreso');
    });

    test('tampoco se cancela desde Finanzas', () async {
      final registro = await registrarConCuenta();

      final r = await container.read(cancelarEgresoUseCaseProvider).ejecutar(
            egresoId: registro.egresoId!,
            motivo: 'Intento directo',
          );

      expect(r, isA<CancelarEgresoOrigenAutomatico>());
    });

    test('"Ver origen" resuelve el vehículo por FK real', () async {
      final registro = await registrarConCuenta();

      final origen = await container.read(obtenerOrigenAutomaticoEgresoUseCaseProvider).ejecutar(registro.egresoId!);

      expect(origen, isA<OrigenAutomaticoEgresoVehiculo>());
      final vehiculoOrigen = origen! as OrigenAutomaticoEgresoVehiculo;
      expect(vehiculoOrigen.vehiculoId, vehiculoId);
      expect(vehiculoOrigen.vehiculoMantenimientoId, registro.id);
      expect(vehiculoOrigen.folio, 'VEH-000001');
    });
  });

  group('§9 — el clasificador NO deja el gasto como "manual"', () {
    test('un Egreso de Vehículos se clasifica como vehiculo, no manual', () async {
      await registrarConCuenta();

      final resumen = await container.read(clasificarEgresosPorOrigenUseCaseProvider).ejecutar();

      expect(resumen.totalVehiculo, 250000);
      expect(resumen.totalManual, 0, reason: 'el gap de Préstamos era exactamente este: caer en manual');
      expect(resumen.detalle.single.origen, OrigenEgreso.vehiculo);
    });

    test('un gasto con TDC no aparece aquí — no genera Egreso', () async {
      await container.read(registrarMantenimientoVehiculoAutorizadoProvider)(
        vehiculoId: vehiculoId,
        fecha: DateTime(2026, 5, 10),
        tipo: TipoMantenimientoVehiculo.llantas.name,
        descripcion: 'Llantas',
        costo: 800000,
        origen: OrigenFinancieroTarjeta(konfioId),
      );

      final resumen = await container.read(clasificarEgresosPorOrigenUseCaseProvider).ejecutar();
      expect(resumen.detalle, isEmpty, reason: 'el gasto con TDC vive en totalCargadoEnRango');
      expect(resumen.totalVehiculo, 0);

      // …pero SÍ es gasto operativo del periodo.
      expect(await container.read(deudaRepositoryProvider).totalCargadoEnRango(), 800000);
    });
  });

  group('§15 — el gasto reconstruye Finanzas', () {
    test('registrar y anular dejan el saldo de la cuenta consistente por la vía de providers', () async {
      final cuentaRepo = container.read(cuentaFinancieraRepositoryProvider);
      expect(await cuentaRepo.calcularSaldo(bbvaId), 2000000);

      final registro = await registrarConCuenta();
      expect(await cuentaRepo.calcularSaldo(bbvaId), 1750000);

      await container.read(cancelarMantenimientoVehiculoAutorizadoProvider)(
        vehiculoMantenimientoId: registro.id,
        motivo: 'No se realizó',
      );
      expect(await cuentaRepo.calcularSaldo(bbvaId), 2000000);
    });
  });
}
