// Etapa 20 (Dashboard v2) — Parte 7.1/11/16: hueco real encontrado en
// la auditoría — `ObtenerActividadRecienteUseCase` recibía
// `rangoInicio`/`rangoFin` pero nunca los pasaba a
// `CompraRepository.listar`/`PagoRepository.listar` (ambos YA
// soportaban el parámetro): esas dos sub-listas siempre mostraban
// "los últimos 5 jamás registrados", ignorando por completo el
// selector de periodo del Dashboard, mientras Recargas/Vacantes sí lo
// respetaban. Corregido pasando el rango real. Esta prueba usa BD real
// (nunca mocks) para demostrar que cambiar el periodo SÍ cambia el
// resultado.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/compras/data/repositories/compra_repository_impl.dart';
import 'package:riseg_one/features/dashboard/domain/usecases/obtener_actividad_reciente_usecase.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/pago_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/inventario_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/vacante_operativa_repository_impl.dart';
import 'package:riseg_one/features/telefonia/domain/repositories/asignacion_linea_telefonica_repository.dart';
import 'package:riseg_one/features/telefonia/domain/repositories/linea_telefonica_equipo_repository.dart';
import 'package:riseg_one/features/telefonia/data/repositories/linea_telefonica_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/repositories/recarga_linea_telefonica_repository_impl.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:drift/drift.dart' show Value;

// Fakes livianos (nunca invocados: `incluirTelefonia: false` en esta
// prueba) — solo para satisfacer el constructor de
// `LineaTelefonicaRepositoryImpl`, mismo patrón `noSuchMethod` ya
// usado en `dashboard_usecases_test.dart`.
class _AsignacionLineaRepoVacio implements AsignacionLineaTelefonicaRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _LineaTelefonicaEquipoRepoVacio implements LineaTelefonicaEquipoRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  test(
    'cambiar el periodo SÍ cambia Compras/Pagos recientes (antes: siempre "últimos 5 jamás", ignoraba el rango)',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final asignacionServicioRepo = AsignacionServicioRepositoryImpl(db);
      final inventarioRepo = InventarioRepositoryImpl(db);
      final articuloRepo = ArticuloRepositoryImpl(db);
      final egresoRepo = EgresoRepositoryImpl(db);
      final deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
      final useCase = ObtenerActividadRecienteUseCase(
        CompraRepositoryImpl(db, inventarioRepo, articuloRepo, egresoRepo, deudaRepo),
        PagoRepositoryImpl(db),
        ClienteRepositoryImpl(db),
        inventarioRepo,
        articuloRepo,
        RecargaLineaTelefonicaRepositoryImpl(db, EgresoRepositoryImpl(db), DeudaRepositoryImpl(db, EgresoRepositoryImpl(db)), CodigoSecuenciaService(db)),
        LineaTelefonicaRepositoryImpl(db, _AsignacionLineaRepoVacio(), _LineaTelefonicaEquipoRepoVacio()),
        VacanteOperativaRepositoryImpl(db),
        ServicioRepositoryImpl(db, asignacionServicioRepo),
      );

      final cliente = await ClienteRepositoryImpl(db).crear(
        ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Cliente de prueba'),
      );

      // Compra de "este mes" y Compra de "hace 6 meses".
      await db.into(db.compra).insert(
            CompraCompanion.insert(folioCompra: 'COM-RECIENTE', fecha: DateTime(2026, 8, 15), formaPago: 'transferencia'),
          );
      await db.into(db.compra).insert(
            CompraCompanion.insert(folioCompra: 'COM-ANTIGUA', fecha: DateTime(2026, 2, 1), formaPago: 'transferencia'),
          );
      // Pago de "este mes" y Pago de "hace 6 meses".
      await db.into(db.pago).insert(
            PagoCompanion.insert(
              folioPago: 'PAG-RECIENTE',
              clienteId: Value(cliente.id),
              montoTotal: 100000,
              fechaPago: DateTime(2026, 8, 15),
              formaPago: 'transferencia',
            ),
          );
      await db.into(db.pago).insert(
            PagoCompanion.insert(
              folioPago: 'PAG-ANTIGUA',
              clienteId: Value(cliente.id),
              montoTotal: 200000,
              fechaPago: DateTime(2026, 2, 1),
              formaPago: 'transferencia',
            ),
          );

      Future<ActividadRecienteDashboard> actividadDelMes(DateTime inicio, DateTime fin) {
        return useCase.ejecutar(
          incluirCompras: true,
          incluirPagos: true,
          incluirInventario: false,
          incluirTelefonia: false,
          incluirComercial: false,
          rangoInicio: inicio,
          rangoFin: fin,
        );
      }

      // "Este mes" (agosto) — solo debe traer las filas recientes.
      final deAgosto = await actividadDelMes(DateTime(2026, 8, 1), DateTime(2026, 8, 31, 23, 59, 59));
      expect(deAgosto.comprasRecientes!.map((c) => c.folioCompra), ['COM-RECIENTE']);
      expect(deAgosto.pagosRecientes!.map((p) => p.pago.folioPago), ['PAG-RECIENTE']);

      // "Febrero" — solo debe traer las filas antiguas. Si el bug
      // siguiera presente, este resultado sería IDÉNTICO al de agosto
      // (el rango se ignoraría por completo).
      final deFebrero = await actividadDelMes(DateTime(2026, 2, 1), DateTime(2026, 2, 28, 23, 59, 59));
      expect(deFebrero.comprasRecientes!.map((c) => c.folioCompra), ['COM-ANTIGUA']);
      expect(deFebrero.pagosRecientes!.map((p) => p.pago.folioPago), ['PAG-ANTIGUA']);
    },
  );
}
