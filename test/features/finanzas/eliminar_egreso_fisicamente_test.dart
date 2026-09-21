// Etapa 15 — Eliminación física de Egreso (Maestro), patrón exacto de
// la Etapa 11D. Cubre las reglas de elegibilidad por origen: manual
// sin dependencias (elegible, incluso cancelado), generado por Compra
// o por PagoNomina (siempre bloqueado, con el folio real del origen).

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/compras/data/repositories/compra_repository_impl.dart';
import 'package:riseg_one/features/compras/data/tables/compra_partida_table.dart' show DestinoCompraPartida;
import 'package:riseg_one/features/compras/domain/repositories/compra_repository.dart' show PartidaCompraInput;
import 'package:riseg_one/features/compras/domain/usecases/registrar_compra_usecase.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/finanzas/domain/usecases/eliminar_egreso_fisicamente_usecase.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/inventario_repository_impl.dart';

void main() {
  late AppDatabase db;
  late EgresoRepositoryImpl egresoRepo;
  late EliminarEgresoFisicamenteUseCase eliminarEgreso;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    egresoRepo = EgresoRepositoryImpl(db);
    eliminarEgreso = EliminarEgresoFisicamenteUseCase(egresoRepo);
    // `EliminacionFisicaEvento.actorUsuarioId` es una FK real hacia
    // `Usuario` — a diferencia de otros flujos de este proyecto que
    // todavía no propagan `actorUsuarioId` (ej. `AgendaController`),
    // la eliminación física sí lo hace siempre, así que el actor debe
    // existir físicamente o la operación falla por violación de FK.
    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(
            id: const Value('usuario-maestro'),
            nombre: 'Maestro de prueba',
            nombreUsuario: 'maestro',
            passwordHash: 'x',
            esMaestro: const Value(true),
          ),
        );
  });

  tearDown(() => db.close());

  Future<String> crearEgresoManual({String folio = 'EGR-000001', bool cancelado = false}) async {
    final egreso = await egresoRepo.crear(
      folioEgreso: folio,
      monto: 150000,
      fecha: DateTime(2026, 1, 5),
      formaPago: 'efectivo',
      concepto: 'Papelería de oficina',
    );
    if (cancelado) {
      await egresoRepo.cancelar(egresoId: egreso.id, motivo: 'Registro duplicado por error');
    }
    return egreso.id;
  }

  group('Egreso manual sin dependencias', () {
    test('Maestro elimina físicamente un Egreso manual sin dependencias', () async {
      final egresoId = await crearEgresoManual();

      final resultado = await eliminarEgreso.ejecutar(
        egresoId: egresoId,
        motivo: 'Captura de prueba, nunca fue un gasto real',
        actorUsuarioId: 'usuario-maestro',
      );

      expect(resultado, isA<EliminarEgresoFisicamenteExitoso>());
      expect(await egresoRepo.obtenerPorId(egresoId), isNull);
    });

    test('un Egreso manual ya cancelado también es elegible (caso real: limpiar captura de prueba)', () async {
      final egresoId = await crearEgresoManual(cancelado: true);

      final resultado = await eliminarEgreso.ejecutar(
        egresoId: egresoId,
        motivo: 'Captura de prueba cancelada, ya no aporta nada',
        actorUsuarioId: 'usuario-maestro',
      );

      expect(resultado, isA<EliminarEgresoFisicamenteExitoso>());
    });

    test('exige motivo', () async {
      final egresoId = await crearEgresoManual();
      final resultado = await eliminarEgreso.ejecutar(egresoId: egresoId, motivo: '   ');
      expect(resultado, isA<EliminarEgresoFisicamenteMotivoRequerido>());
      expect(await egresoRepo.obtenerPorId(egresoId), isNotNull, reason: 'sin motivo, nunca se elimina nada');
    });

    test('rechaza un Egreso inexistente', () async {
      final resultado = await eliminarEgreso.ejecutar(egresoId: 'no-existe', motivo: 'Cualquiera');
      expect(resultado, isA<EliminarEgresoFisicamenteNoExiste>());
    });

    test('crea el snapshot y el evento de EliminacionFisicaEvento con el motivo y el actor', () async {
      final egresoId = await crearEgresoManual();

      final resultado = await eliminarEgreso.ejecutar(
        egresoId: egresoId,
        motivo: 'Captura de prueba',
        actorUsuarioId: 'usuario-maestro',
      );
      expect(resultado, isA<EliminarEgresoFisicamenteExitoso>());

      final eventos = await (db.select(db.eliminacionFisicaEvento)
            ..where((t) => t.tipoEntidad.equals('egreso') & t.entidadIdOriginal.equals(egresoId)))
          .get();
      expect(eventos, hasLength(1));
      expect(eventos.single.motivo, 'Captura de prueba');
      expect(eventos.single.actorUsuarioId, 'usuario-maestro');
      expect(eventos.single.snapshotJson, contains('EGR-000001'));
    });
  });

  group('Egreso generado por una Compra — siempre bloqueado', () {
    test('rechaza eliminar el Egreso de una Compra, con el folio real de la Compra en el mensaje', () async {
      final articuloRepo = ArticuloRepositoryImpl(db);
      final inventarioRepo = InventarioRepositoryImpl(db);
      final deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
      final compraRepo = CompraRepositoryImpl(db, inventarioRepo, articuloRepo, egresoRepo, deudaRepo);
      final registrarCompra = RegistrarCompraUseCase(
        compraRepo,
        articuloRepo,
        inventarioRepo,
        deudaRepo,
        GenerarCodigoUseCase(CodigoSecuenciaService(db)),
      );

      final resultadoCompra = await registrarCompra.ejecutar(
        fecha: DateTime(2026, 8, 10),
        formaPago: FormaPago.efectivo.name,
        partidas: [
          PartidaCompraInput(
            destino: DestinoCompraPartida.gastoDirecto.name,
            concepto: 'Papelería',
            cantidad: 1,
            costoUnitario: 45000,
          ),
        ],
      );
      final compra = (resultadoCompra as RegistrarCompraExitosa).compra;
      final egreso = await db.select(db.egreso).getSingle();

      final resultado = await eliminarEgreso.ejecutar(
        egresoId: egreso.id,
        motivo: 'Intento de eliminarlo aislado',
        actorUsuarioId: 'usuario-maestro',
      );

      expect(resultado, isA<EliminarEgresoFisicamenteTieneDependencias>());
      expect(
        (resultado as EliminarEgresoFisicamenteTieneDependencias).detalle,
        contains(compra.folioCompra),
      );
      expect(await egresoRepo.obtenerPorId(egreso.id), isNotNull, reason: 'nunca se elimina cuando está bloqueado');
    });
  });

  group('Egreso generado por un Pago de Nómina — siempre bloqueado', () {
    test('rechaza eliminar el Egreso de un PagoNomina, con el folio real del Pago de Nómina en el mensaje', () async {
      final egresoId = await crearEgresoManual(folio: 'EGR-000002');

      final nomina = await db.into(db.nomina).insertReturning(
            NominaCompanion.insert(
              folio: 'NOM-000001',
              anio: 2026,
              mes: 1,
              tipoPeriodo: 'primera',
              fechaInicioPeriodo: DateTime(2026, 1, 1),
              fechaFinPeriodo: DateTime(2026, 1, 15),
              fechaPagoOrdinaria: DateTime(2026, 1, 15),
            ),
          );
      await db.into(db.pagoNomina).insert(
            PagoNominaCompanion.insert(
              folioPagoNomina: 'PAGN-000001',
              nominaId: nomina.id,
              egresoId: Value(egresoId),
              montoTotal: 150000,
              fechaPago: DateTime(2026, 1, 15),
              formaPago: 'transferencia',
            ),
          );

      final resultado = await eliminarEgreso.ejecutar(
        egresoId: egresoId,
        motivo: 'Intento de eliminarlo aislado',
        actorUsuarioId: 'usuario-maestro',
      );

      expect(resultado, isA<EliminarEgresoFisicamenteTieneDependencias>());
      expect((resultado as EliminarEgresoFisicamenteTieneDependencias).detalle, contains('PAGN-000001'));
      expect(await egresoRepo.obtenerPorId(egresoId), isNotNull);
    });
  });
}
