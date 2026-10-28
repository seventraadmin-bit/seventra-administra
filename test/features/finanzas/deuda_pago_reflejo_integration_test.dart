// Corrección urgente (Etapa 19) — reproduce EXACTAMENTE el reporte
// real: "registré un pago y no cambió nada". Ejercita la cadena REAL
// de providers (nunca construcción directa de repos/casos de uso) para
// no dejar ninguna duda de que el bug está en la capa de invalidación,
// no en la persistencia.
//
// Parte A del pedido: confirma BD real + traza exacta ANTES de tocar
// UI. Parte B: la operación de pago es una sola transacción real.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/finanzas/data/tables/deuda_table.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_deuda_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_pago_deuda_usecase.dart';
import 'package:riseg_one/features/finanzas/finanzas_providers.dart';
import 'package:riseg_one/features/finanzas/presentation/deudas_credito/deudas_credito_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/egresos/egresos_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/resumen/resumen_financiero_controller.dart';
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
    await sembrarSesionEnBase(db, const SesionUsuario( usuarioId: 'usuario-maestro', nombre: 'Maestro de prueba', nombreUsuario: 'maestro', esMaestro: true, permisos: {}, ));
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  test(
    'registrar un pago de deuda vía la cadena real de providers: persiste todo correctamente '
    '(Deuda/MovimientoDeuda/Egreso/clasificación/Resumen), y el listado de Deudas queda "stale" hasta invalidarlo',
    () async {
      // 1. Crear deuda TDC BBVA, importeOriginal = saldoActual = 50,000.
      final creada = await container.read(registrarDeudaAutorizadoProvider)(
        nombre: 'TDC BBVA',
        tipo: 'tarjetaCredito',
        fechaOrigen: DateTime(2026, 1, 1),
        importeOriginal: 5000000,
        saldoInicial: 5000000,
      );
      final deuda = (creada as RegistrarDeudaExitoso).deuda;
      expect(deuda.saldoActual, 5000000);

      // Cargar el listado UNA vez — mismo ciclo de vida real: el
      // usuario ve la lista antes de entrar al expediente a pagar.
      await container.read(deudasCreditoControllerProvider.notifier).reintentarCarga();
      final listadoAntes = container.read(deudasCreditoControllerProvider);
      expect(listadoAntes.deudas.single.saldoActual, 5000000);

      // 2. Registrar pago de 10,000 con fecha HOY (misma reproducción
      // exacta del reporte real) — misma llamada exacta que usa el
      // diálogo real (`registrarPagoDeudaAutorizadoProvider`). La fecha
      // importa: el Resumen financiero filtra por "este mes" por
      // defecto, así que un pago fechado en el pasado nunca aparecería
      // ahí sin importar qué tan bien esté invalidado el provider.
      final hoy = DateTime.now();
      final resultadoPago = await container.read(registrarPagoDeudaAutorizadoProvider)(
        deudaId: deuda.id,
        fecha: hoy,
        importe: 1000000,
        formaPago: 'transferencia',
      );
      expect(resultadoPago, isA<RegistrarPagoDeudaExitoso>(), reason: 'PARTE A/B: el pago debe persistirse sin error');
      final deudaTrasPago = (resultadoPago as RegistrarPagoDeudaExitoso).deuda;

      // 3. Confirmar en BD REAL (no en el estado del provider todavía)
      // — Deuda.
      expect(deudaTrasPago.saldoActual, 4000000, reason: 'saldo debe reducirse exactamente 10,000');
      expect(deudaTrasPago.importeOriginal! - deudaTrasPago.saldoActual, 1000000, reason: '"pagado" derivado = 10,000');
      expect(deudaTrasPago.estatus, EstatusDeuda.activa.name);

      final deudaEnBd = await container.read(deudaRepositoryProvider).obtenerPorId(deuda.id);
      expect(deudaEnBd!.saldoActual, 4000000, reason: 'una lectura fresca de BD confirma que SÍ se persistió, no es un espejismo del resultado en memoria');

      // MovimientoDeuda.
      final movimientos = await container.read(deudaRepositoryProvider).listarMovimientos(deuda.id);
      final pagos = movimientos.where((m) => m.tipo == TipoMovimientoDeuda.pago.name).toList();
      expect(pagos, hasLength(1), reason: 'exactamente 1 movimiento tipo pago');
      expect(pagos.single.saldoAnterior, 5000000);
      expect(pagos.single.importe, 1000000);
      expect(pagos.single.saldoPosterior, 4000000);
      expect(pagos.single.egresoId, isNotNull);

      // Egreso.
      final egresos = await db.select(db.egreso).get();
      expect(egresos, hasLength(1), reason: 'exactamente 1 Egreso nuevo, ligado al pago');
      final egreso = egresos.single;
      expect(egreso.id, pagos.single.egresoId);
      expect(egreso.monto, 1000000);
      expect(egreso.concepto, contains(deuda.folio));
      expect(egreso.concepto, contains('TDC BBVA'));
      expect(egreso.formaPago, 'transferencia');
      expect(egreso.estatus, 'registrado');

      // Clasificador — el Egreso debe aparecer en origen "deuda", NUNCA
      // "manual"/"Otros".
      // `DateTime(año, mes+1, 0)` da medianoche del último día del mes
      // — el último día del mes en la vida real (hallazgo directo de
      // esta corrección) excluiría el pago de hoy mismo sin la hora
      // 23:59:59.999 explícita.
      final clasificado = await container.read(clasificarEgresosPorOrigenUseCaseProvider).ejecutar(
            rangoInicio: DateTime(hoy.year, hoy.month, 1),
            rangoFin: DateTime(hoy.year, hoy.month + 1, 0, 23, 59, 59, 999),
          );
      expect(clasificado.totalDeuda, 1000000);
      expect(clasificado.totalManual, 0, reason: 'el pago de deuda nunca debe contarse como "Otros"/manual');
      final entradaClasificada = clasificado.detalle.singleWhere((e) => e.egreso.id == egreso.id);
      expect(entradaClasificada.origen, OrigenEgreso.deuda);

      // Resumen financiero — releído explícitamente (reintentarCarga),
      // confirma que la fórmula sí refleja el pago cuando se consulta
      // fresco: pagosDeuda sube, egresosOperativos NO, flujoDespuesDeuda sí baja.
      await container.read(resumenFinancieroControllerProvider.notifier).reintentarCarga();
      final resumen = container.read(resumenFinancieroControllerProvider);
      expect(resumen.egresosDeuda, 1000000, reason: 'Pago de deudas debe subir 10,000');
      expect(resumen.egresosOperativos, 0, reason: 'egresos operativos NO deben subir por un pago de deuda');
      expect(resumen.egresosPeriodo, 1000000);
      expect(resumen.flujoDespuesDeuda, -1000000, reason: 'ingresos 0 - egresos totales 10,000');

      // 4. EL BUG REAL: el listado de Deudas, leído SIN invalidar tras
      // el pago, sigue mostrando el saldo viejo — reproduce
      // exactamente "sigue mostrando $50,000" del reporte.
      final listadoSinInvalidar = container.read(deudasCreditoControllerProvider);
      expect(
        listadoSinInvalidar.deudas.single.saldoActual,
        5000000,
        reason: 'BUG REAL reproducido: el provider del listado queda "stale" — nada lo invalidó tras el pago',
      );

      // Y la prueba de que el arreglo correcto es invalidar el
      // provider (no un recálculo manual): tras invalidar, refleja el
      // dato real sin volver a llamar reintentarCarga() explícitamente.
      container.invalidate(deudasCreditoControllerProvider);
      await container.read(deudasCreditoControllerProvider.notifier).reintentarCarga();
      final listadoTrasInvalidar = container.read(deudasCreditoControllerProvider);
      expect(listadoTrasInvalidar.deudas.single.saldoActual, 4000000);

      // Egresos — mismo problema: su propio controller también queda
      // stale hasta que algo lo invalide.
      final egresosSinInvalidar = container.read(egresosControllerProvider);
      expect(
        egresosSinInvalidar.egresos.where((e) => e.id == egreso.id),
        isEmpty,
        reason: 'BUG REAL reproducido: EgresosController tampoco se entera del nuevo Egreso sin invalidación',
      );
      container.invalidate(egresosControllerProvider);
      await container.read(egresosControllerProvider.notifier).reintentarCarga();
      final egresosTrasInvalidar = container.read(egresosControllerProvider);
      expect(egresosTrasInvalidar.egresos.where((e) => e.id == egreso.id), hasLength(1));
    },
  );
}
