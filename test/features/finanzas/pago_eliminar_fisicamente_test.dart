// Etapa 15 — Eliminación física de Pago (Maestro), patrón exacto de la
// Etapa 11D. Cubre: bloqueo mientras el Pago sigue activo, bloqueo
// real si tiene un Complemento de pago (CFDI ya timbrado, nunca
// elegible sin importar su estatus), y elegible una vez cancelado
// (borra sus AplicacionPago canceladas y su Ingreso automático
// cancelado junto con él, sin tocar la CuentaPorCobrar ni el Cliente).

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/repositories/complemento_pago_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/pago_repository_impl.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cancelar_pago_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/eliminar_pago_fisicamente_usecase.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_cliente_usecase.dart';

void main() {
  late AppDatabase db;
  late PagoRepositoryImpl pagoRepo;
  late CancelarPagoUseCase cancelarPago;
  late EliminarPagoFisicamenteUseCase eliminarPago;
  late String clienteId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    pagoRepo = PagoRepositoryImpl(db);
    cancelarPago = CancelarPagoUseCase(pagoRepo, ComplementoPagoRepositoryImpl(db));
    eliminarPago = EliminarPagoFisicamenteUseCase(pagoRepo);

    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(
            id: const Value('usuario-maestro'),
            nombre: 'Maestro de prueba',
            nombreUsuario: 'maestro',
            passwordHash: 'x',
            esMaestro: const Value(true),
          ),
        );

    final clienteRepo = ClienteRepositoryImpl(db);
    final crearCliente = CrearClienteUseCase(clienteRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));
    final resultado = await crearCliente.ejecutar(nombreComercial: 'Sportium');
    clienteId = resultado.when(ok: (c) => c.id, failure: (f) => throw StateError(f.message));
  });

  tearDown(() => db.close());

  Future<String> crearDocumentoYCuentaDePrueba({required String codigo}) async {
    final documento = await db.into(db.documentoPorEmitir).insertReturning(
          DocumentoPorEmitirCompanion.insert(
            codigo: codigo,
            clienteId: clienteId,
            tipoDocumento: 'reciboDePago',
            agrupacion: 'porServicio',
            metodo: 'noAplica',
            periodoInicio: DateTime(2026, 1, 1),
            periodoFin: DateTime(2026, 1, 31),
            generationKey: 'GK-$codigo',
            importeBaseEsperado: 2180000,
            importeFinalEsperado: 2180000,
            estatus: const Value('procesadoAceptado'),
          ),
        );
    final cuenta = await db.into(db.cuentaPorCobrar).insertReturning(
          CuentaPorCobrarCompanion.insert(
            documentoPorEmitirId: Value(documento.id),
            clienteId: Value(clienteId),
            tipoDocumento: 'reciboDePago',
            metodo: 'noAplica',
            fechaEmisionReal: DateTime(2026, 1, 5),
            importeEmitido: 2180000,
            saldoOriginal: 2180000,
            saldoPendiente: 2180000,
          ),
        );
    return cuenta.id;
  }

  group('Pago activo — siempre bloqueado', () {
    test('rechaza eliminar un Pago registrado (nunca cancelado)', () async {
      final pago = await pagoRepo.crear(
        folioPago: 'PAG-000001',
        clienteId: clienteId,
        montoTotal: 3400000,
        fechaPago: DateTime(2026, 8, 10),
        formaPago: 'transferencia',
      );

      final r = await eliminarPago.ejecutar(pagoId: pago.id, motivo: 'intento', actorUsuarioId: 'usuario-maestro');

      expect(r, isA<EliminarPagoFisicamenteTieneDependencias>());
      expect((r as EliminarPagoFisicamenteTieneDependencias).detalle, contains('sigue activo'));
      expect(await pagoRepo.obtenerPorId(pago.id), isNotNull);
    });
  });

  group('Pago cancelado sin Complemento — elegible', () {
    test('Maestro elimina físicamente un Pago cancelado con una aplicación cancelada, y su Ingreso automático', () async {
      final cuentaId = await crearDocumentoYCuentaDePrueba(codigo: 'DOC-P001');
      final pago = await pagoRepo.crear(
        folioPago: 'PAG-000002',
        clienteId: clienteId,
        montoTotal: 2180000,
        fechaPago: DateTime(2026, 8, 10),
        formaPago: 'transferencia',
      );
      await pagoRepo.aplicar(pagoId: pago.id, cuentaPorCobrarId: cuentaId, monto: 2180000);
      final ingresoAntes = await (db.select(db.ingreso)..where((t) => t.pagoId.equals(pago.id))).getSingle();

      final cancelacion = await cancelarPago.ejecutar(pagoId: pago.id, motivo: 'Duplicado por error');
      expect(cancelacion, isA<CancelarPagoExitoso>());

      final r = await eliminarPago.ejecutar(
        pagoId: pago.id,
        motivo: 'Captura de prueba cancelada',
        actorUsuarioId: 'usuario-maestro',
      );

      expect(r, isA<EliminarPagoFisicamenteExitoso>());
      expect(await pagoRepo.obtenerPorId(pago.id), isNull);
      final aplicacionSigueExistiendo =
          await (db.select(db.aplicacionPago)..where((t) => t.pagoId.equals(pago.id))).getSingleOrNull();
      expect(aplicacionSigueExistiendo, isNull, reason: 'la aplicación cancelada se elimina junto con el Pago');
      final ingresoSigueExistiendo =
          await (db.select(db.ingreso)..where((t) => t.id.equals(ingresoAntes.id))).getSingleOrNull();
      expect(ingresoSigueExistiendo, isNull, reason: 'el Ingreso automático (ya cancelado) se elimina junto con el Pago');
      final cuentaSigueExistiendo = await (db.select(db.cuentaPorCobrar)..where((t) => t.id.equals(cuentaId))).getSingleOrNull();
      expect(cuentaSigueExistiendo, isNotNull, reason: 'la eliminación del Pago nunca toca la CuentaPorCobrar');
    });

    test('un Pago cancelado sin ninguna aplicación (nunca se aplicó a nada) también es elegible', () async {
      final pago = await pagoRepo.crear(
        folioPago: 'PAG-000003',
        clienteId: clienteId,
        montoTotal: 100000,
        fechaPago: DateTime(2026, 8, 10),
        formaPago: 'efectivo',
      );
      await cancelarPago.ejecutar(pagoId: pago.id, motivo: 'Captura duplicada');

      final r = await eliminarPago.ejecutar(pagoId: pago.id, motivo: 'limpieza', actorUsuarioId: 'usuario-maestro');
      expect(r, isA<EliminarPagoFisicamenteExitoso>());
    });

    test('exige motivo', () async {
      final pago = await pagoRepo.crear(
        folioPago: 'PAG-000004',
        clienteId: clienteId,
        montoTotal: 100000,
        fechaPago: DateTime(2026, 8, 10),
        formaPago: 'efectivo',
      );
      await cancelarPago.ejecutar(pagoId: pago.id, motivo: 'Captura duplicada');

      final r = await eliminarPago.ejecutar(pagoId: pago.id, motivo: '   ');
      expect(r, isA<EliminarPagoFisicamenteMotivoRequerido>());
      expect(await pagoRepo.obtenerPorId(pago.id), isNotNull);
    });

    test('rechaza un Pago inexistente', () async {
      final r = await eliminarPago.ejecutar(pagoId: 'no-existe', motivo: 'cualquiera');
      expect(r, isA<EliminarPagoFisicamenteNoExiste>());
    });
  });

  group('Pago con Complemento de pago real — siempre bloqueado', () {
    test('rechaza eliminar un Pago cancelado que tiene un Complemento registrado, con su folio fiscal en el mensaje', () async {
      final pago = await pagoRepo.crear(
        folioPago: 'PAG-000005',
        clienteId: clienteId,
        montoTotal: 100000,
        fechaPago: DateTime(2026, 8, 10),
        formaPago: 'efectivo',
      );
      // Se cancela ANTES de insertar el Complemento (Etapa 6:
      // `CancelarPagoUseCase` ahora bloquea la cancelación de un Pago
      // con un Complemento vigente) — el Complemento se inserta directo
      // sobre la tabla, sin pasar por `RegistrarComplementoPagoUseCase`
      // (que tampoco permitiría registrarlo sobre un Pago ya
      // cancelado), justo para simular defensivamente que el
      // Complemento terminó asociado a un Pago cancelado sin importar
      // el orden real de captura — la eliminación física debe seguir
      // bloqueada de todas formas.
      await cancelarPago.ejecutar(pagoId: pago.id, motivo: 'Duplicado');
      await db.into(db.complementoPago).insert(
            ComplementoPagoCompanion.insert(
              pagoId: pago.id,
              uuid: '11111111-2222-3333-4444-555555555555',
              fechaTimbrado: DateTime(2026, 8, 11),
              montoTotal: 100000,
              folioFiscal: const Value('CFDI-9001'),
            ),
          );

      final r = await eliminarPago.ejecutar(pagoId: pago.id, motivo: 'intento', actorUsuarioId: 'usuario-maestro');

      expect(r, isA<EliminarPagoFisicamenteTieneDependencias>());
      expect((r as EliminarPagoFisicamenteTieneDependencias).detalle, contains('CFDI-9001'));
      expect(await pagoRepo.obtenerPorId(pago.id), isNotNull, reason: 'un Complemento real nunca se pierde silenciosamente');
    });
  });
}
