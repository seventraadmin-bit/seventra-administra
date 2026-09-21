// Etapa 2 (convención común de auditoría para correcciones sensibles)
// — Compra como dominio piloto: `motivo` ahora se exige real (nunca
// vacío/solo espacios), `actorUsuarioId` se registra, y
// `CompraEvento.estadoAnterior`/`estadoNuevo` (columnas que ya
// existían pero nunca se poblaban) ahora capturan, vía `DiffEvento`,
// únicamente los campos escalares que realmente cambiaron — nunca un
// snapshot completo.

import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/compras/data/repositories/compra_repository_impl.dart';
import 'package:riseg_one/features/compras/domain/repositories/compra_repository.dart';
import 'package:riseg_one/features/compras/domain/usecases/correccion_partida_compra.dart';
import 'package:riseg_one/features/compras/domain/usecases/corregir_compra_usecase.dart';
import 'package:riseg_one/features/compras/domain/usecases/registrar_compra_usecase.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/tables/deuda_table.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_deuda_usecase.dart';
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/inventario_repository_impl.dart';

void main() {
  late AppDatabase db;
  late CompraRepositoryImpl compraRepo;
  late RegistrarCompraUseCase registrarCompra;
  late CorregirCompraUseCase corregirCompra;
  late String compraId;

  const actorId = 'usuario-actor-real';

  final partidas = [
    const PartidaCompraInput(destino: 'gastoDirecto', concepto: 'Papelería', cantidad: 1, costoUnitario: 50000),
  ];

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final articuloRepo = ArticuloRepositoryImpl(db);
    final inventarioRepo = InventarioRepositoryImpl(db);
    final egresoRepo = EgresoRepositoryImpl(db);
    final deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
    compraRepo = CompraRepositoryImpl(db, inventarioRepo, articuloRepo, egresoRepo, deudaRepo);
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    registrarCompra = RegistrarCompraUseCase(compraRepo, articuloRepo, inventarioRepo, deudaRepo, generarCodigo);
    corregirCompra = CorregirCompraUseCase(compraRepo, articuloRepo, inventarioRepo, deudaRepo);

    // FK real (Etapa 11D): actorUsuarioId exige una fila de Usuario.
    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(id: const Value(actorId), nombre: 'Actor Real', nombreUsuario: 'actor', passwordHash: 'x'),
        );

    final creada = (await registrarCompra.ejecutar(
      fecha: DateTime(2026, 8, 10),
      formaPago: FormaPago.efectivo.name,
      proveedor: 'Proveedor Original',
      partidas: partidas,
    ) as RegistrarCompraExitosa)
        .compra;
    compraId = creada.id;
  });

  tearDown(() => db.close());

  test('motivo vacío se rechaza — ninguna fila de CompraEvento nueva, la Compra no cambia', () async {
    final resultado = await corregirCompra.ejecutar(compraId: compraId, proveedor: 'Proveedor Nuevo', motivo: '   ');

    expect(resultado, isA<CorregirCompraMotivoRequerido>());
    final actual = await compraRepo.obtenerPorId(compraId);
    expect(actual!.proveedor, 'Proveedor Original', reason: 'nunca se corrige sin un motivo real');
    final eventos = await (db.select(db.compraEvento)..where((t) => t.compraId.equals(compraId))).get();
    expect(eventos.where((e) => e.tipoEvento == 'corregida'), isEmpty);
  });

  test('actorUsuarioId real se registra en el evento de corrección (FK a Usuario)', () async {
    final resultado = await corregirCompra.ejecutar(
      compraId: compraId,
      proveedor: 'Proveedor Nuevo',
      motivo: 'Corrección de proveedor',
      actorUsuarioId: actorId,
    );
    expect(resultado, isA<CorregirCompraExitosa>());

    final evento = await (db.select(db.compraEvento)
          ..where((t) => t.compraId.equals(compraId) & t.tipoEvento.equals('corregida')))
        .getSingle();
    expect(evento.actorUsuarioId, actorId);
  });

  test('fecha/hora del evento se registra (no queda en null ni en una fecha arbitraria)', () async {
    final antesDeCorregir = DateTime.now();
    await corregirCompra.ejecutar(compraId: compraId, proveedor: 'Proveedor Nuevo', motivo: 'Corrección de proveedor');
    final despuesDeCorregir = DateTime.now();

    final evento = await (db.select(db.compraEvento)
          ..where((t) => t.compraId.equals(compraId) & t.tipoEvento.equals('corregida')))
        .getSingle();
    expect(
      evento.fechaHora.isAfter(antesDeCorregir.subtract(const Duration(seconds: 1))) &&
          evento.fechaHora.isBefore(despuesDeCorregir.add(const Duration(seconds: 1))),
      isTrue,
      reason: 'fechaHora debe ser el momento real de la corrección',
    );
  });

  test('corrección de un solo campo (proveedor) — estadoAnterior/estadoNuevo contienen solo ese campo', () async {
    await corregirCompra.ejecutar(compraId: compraId, proveedor: 'Proveedor Nuevo', motivo: 'Corrección de proveedor');

    final evento = await (db.select(db.compraEvento)
          ..where((t) => t.compraId.equals(compraId) & t.tipoEvento.equals('corregida')))
        .getSingle();
    final antes = jsonDecode(evento.estadoAnterior!) as Map;
    final despues = jsonDecode(evento.estadoNuevo!) as Map;
    expect(antes, {'proveedor': 'Proveedor Original'});
    expect(despues, {'proveedor': 'Proveedor Nuevo'});
  });

  test('corrección de múltiples campos (proveedor + forma de pago) — ambos aparecen, sin campos sin cambio', () async {
    await corregirCompra.ejecutar(
      compraId: compraId,
      proveedor: 'Proveedor Nuevo',
      formaPago: FormaPago.transferencia.name,
      motivo: 'Corrección de proveedor y forma de pago',
    );

    final evento = await (db.select(db.compraEvento)
          ..where((t) => t.compraId.equals(compraId) & t.tipoEvento.equals('corregida')))
        .getSingle();
    final antes = jsonDecode(evento.estadoAnterior!) as Map;
    final despues = jsonDecode(evento.estadoNuevo!) as Map;
    expect(antes, {'proveedor': 'Proveedor Original', 'formaPago': FormaPago.efectivo.name});
    expect(despues, {'proveedor': 'Proveedor Nuevo', 'formaPago': FormaPago.transferencia.name});
    // Nunca observaciones u otros campos no tocados.
    expect(antes.containsKey('observaciones'), isFalse);
  });

  test('histórico previo a esta convención (estadoAnterior/estadoNuevo NULL) sigue siendo legible', () async {
    // Simula un evento "registrada" tal como quedaban ANTES de esta
    // etapa — estadoAnterior/estadoNuevo nunca se poblaban salvo para
    // corregida, y aun en corregida quedaban NULL antes de este fix.
    // Las columnas siempre fueron nullable — nunca se requiere ninguna
    // migración de esquema para que sigan siendo válidas.
    final eventoHistorico = await (db.select(db.compraEvento)
          ..where((t) => t.compraId.equals(compraId) & t.tipoEvento.equals('registrada')))
        .getSingle();

    expect(eventoHistorico.estadoAnterior, isNull);
    expect(eventoHistorico.estadoNuevo, isNull);
    // Leerlo de vuelta no lanza ninguna excepción — el registro
    // histórico simplemente no tiene diff estructurado, y eso es
    // válido.
    expect(() => (db.select(db.compraEvento)..where((t) => t.id.equals(eventoHistorico.id))).getSingle(), returnsNormally);
  });

  test('una segunda corrección genera un evento NUEVO — nunca sobrescribe el anterior', () async {
    await corregirCompra.ejecutar(compraId: compraId, proveedor: 'Proveedor Nuevo', motivo: 'Primera corrección');
    await corregirCompra.ejecutar(compraId: compraId, proveedor: 'Proveedor Final', motivo: 'Segunda corrección');

    final eventos = await (db.select(db.compraEvento)
          ..where((t) => t.compraId.equals(compraId) & t.tipoEvento.equals('corregida'))
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
    expect(eventos, hasLength(2), reason: 'cada corrección deja su propio evento, ninguno se sobrescribe');

    final primero = jsonDecode(eventos.first.estadoAnterior!) as Map;
    final segundo = jsonDecode(eventos.last.estadoAnterior!) as Map;
    expect(primero['proveedor'], 'Proveedor Original', reason: 'el primer evento conserva el estado ANTES de la primera corrección');
    expect(segundo['proveedor'], 'Proveedor Nuevo', reason: 'el segundo evento conserva el estado ANTES de la segunda corrección, no del original');
  });

  test('cambiar el monto (vía partidas) captura total antes/después en centavos, sin pérdida', () async {
    final resumen = await compraRepo.obtenerResumenCorreccion(compraId: compraId, cambiosPartidas: const []);
    expect(resumen.bloqueado, isFalse);

    final compraAntes = await compraRepo.obtenerPorId(compraId);
    final totalAntes = await compraRepo.calcularTotal(compraId);
    expect(totalAntes, 50000);
    final partidaId = (await compraRepo.listarPartidas(compraId)).single.id;

    await corregirCompra.ejecutar(
      compraId: compraId,
      motivo: 'Corrección de costo unitario',
      cambiosPartidas: [CorreccionPartidaCantidadCosto(compraPartidaId: partidaId, nuevoCostoUnitario: 75000)],
    );

    final evento = await (db.select(db.compraEvento)
          ..where((t) => t.compraId.equals(compraId) & t.tipoEvento.equals('corregida')))
        .getSingle();
    final antes = jsonDecode(evento.estadoAnterior!) as Map;
    final despues = jsonDecode(evento.estadoNuevo!) as Map;
    expect(antes['total'], isA<int>());
    expect(antes['total'], 50000);
    expect(despues['total'], isA<int>());
    expect(despues['total'], 75000);
    expect(compraAntes!.id, compraId);
  });

  test(
    'Etapa 3, Sección 6: una corrección de origen (Cuenta -> TDC) audita cuentaFinancieraId/deudaId como IDs '
    'crudos — nunca nombres de cuenta/tarjeta como sustituto',
    () async {
      final egresoRepo = EgresoRepositoryImpl(db);
      final deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
      final tarjeta = (await RegistrarDeudaUseCase(deudaRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db))).ejecutar(
        nombre: 'Konfío',
        tipo: TipoDeuda.tarjetaCredito.name,
        saldoInicial: 0,
        tarjetaLimiteCredito: 4000000,
      ) as RegistrarDeudaExitoso)
          .deuda;

      final resultado = await corregirCompra.ejecutar(compraId: compraId, nuevaDeudaId: tarjeta.id, motivo: 'En realidad se pagó con tarjeta');
      expect(resultado, isA<CorregirCompraExitosa>());

      final evento = await (db.select(db.compraEvento)
            ..where((t) => t.compraId.equals(compraId) & t.tipoEvento.equals('corregida'))
            ..orderBy([(t) => OrderingTerm.asc(t.id)]))
          .get();
      final ultimo = evento.last;
      final antes = jsonDecode(ultimo.estadoAnterior!) as Map;
      final despues = jsonDecode(ultimo.estadoNuevo!) as Map;

      expect(antes.containsKey('deudaId'), isTrue);
      expect(antes['deudaId'], isNull, reason: 'antes de la corrección la Compra no tenía tarjeta');
      expect(despues['deudaId'], tarjeta.id, reason: 'el ID crudo de la tarjeta, nunca su nombre');
      expect(antes.values.any((v) => v == 'Konfío'), isFalse, reason: 'nunca se guarda el nombre de la tarjeta como sustituto de su ID');
      expect(despues.values.any((v) => v == 'Konfío'), isFalse);
    },
  );
}
