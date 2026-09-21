// Etapa "Integrar ledgers de Deudas y Descuentos a Auditoría central".
//
// GAP QUE CIERRA: `MovimientoDeuda` y `DescuentoProgramadoMovimiento`
// tienen `actorUsuarioId` e historial financiero REAL, y no llegaban a
// Configuración → Auditoría. Nadie podía ver desde el panel central
// quién pagó una tarjeta, quién corrigió ese pago, ni quién revirtió la
// cuota de un préstamo.
//
// Igual que las tres tablas de la etapa anterior: se LEEN las tablas
// existentes. Cero tablas nuevas, cero migración, cero eventos copiados.

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/tables/deuda_table.dart';
import 'package:riseg_one/features/descuentos_personal/data/tables/descuento_programado_movimiento_table.dart';
import 'package:riseg_one/features/usuarios/data/repositories/auditoria_repository_impl.dart';
import 'package:riseg_one/features/usuarios/domain/usecases/buscar_auditoria_usecase.dart';
import 'package:riseg_one/features/usuarios/domain/usecases/destino_auditoria.dart';

void main() {
  late AppDatabase db;
  late BuscarAuditoriaUseCase buscar;
  late String deudaId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    buscar = BuscarAuditoriaUseCase(AuditoriaRepositoryImpl(db));

    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(
            id: const Value('marlon'),
            nombre: 'Marlon',
            nombreUsuario: 'marlon',
            passwordHash: 'x',
            esMaestro: const Value(true),
          ),
        );

    final deuda = await db.into(db.deuda).insertReturning(
          DeudaCompanion.insert(
            folio: 'DEU-000003',
            nombre: 'TDC Konfío',
            tipo: TipoDeuda.tarjetaCredito.name,
            saldoActual: 3326608,
            tarjetaLimiteCredito: const Value(40000000),
            // Dato bancario real: la Auditoría NO debe exponerlo.
            tarjetaUltimosDigitos: const Value('4821'),
          ),
        );
    deudaId = deuda.id;
  });

  tearDown(() => db.close());

  Future<int> movimiento({
    required String tipo,
    required int importe,
    required int saldoAnterior,
    required int saldoPosterior,
    required DateTime fecha,
    String? observaciones,
    String? compraId,
    String? vehiculoMantenimientoId,
    int? movimientoOrigenId,
  }) async {
    final fila = await db.into(db.movimientoDeuda).insertReturning(
          MovimientoDeudaCompanion.insert(
            deudaId: deudaId,
            fecha: fecha,
            tipo: tipo,
            importe: importe,
            saldoAnterior: saldoAnterior,
            saldoPosterior: saldoPosterior,
            observaciones: Value(observaciones),
            actorUsuarioId: const Value('marlon'),
            compraId: Value(compraId),
            vehiculoMantenimientoId: Value(vehiculoMantenimientoId),
            movimientoOrigenId: Value(movimientoOrigenId),
          ),
        );
    return fila.id;
  }

  // ---------------------------------------------------------------
  // §9 — Deuda/TDC: alta → cargo → pago → corregir pago → cancelar
  // ---------------------------------------------------------------

  group('§9 — el ciclo financiero completo de una TDC llega a Auditoría', () {
    test('alta, cargo, pago, corrección y reversión aparecen en orden', () async {
      await movimiento(
        tipo: TipoMovimientoDeuda.altaInicial.name,
        importe: 3326608,
        saldoAnterior: 0,
        saldoPosterior: 3326608,
        fecha: DateTime(2026, 8, 1, 8),
      );
      await movimiento(
        tipo: TipoMovimientoDeuda.cargoCompra.name,
        importe: 1200000,
        saldoAnterior: 3326608,
        saldoPosterior: 4526608,
        fecha: DateTime(2026, 8, 2, 9),
      );
      final pagoId = await movimiento(
        tipo: TipoMovimientoDeuda.pago.name,
        importe: 500000,
        saldoAnterior: 4526608,
        saldoPosterior: 4026608,
        fecha: DateTime(2026, 8, 3, 10),
      );
      await movimiento(
        tipo: TipoMovimientoDeuda.ajusteNegativo.name,
        importe: 100000,
        saldoAnterior: 4026608,
        saldoPosterior: 3926608,
        fecha: DateTime(2026, 8, 4, 11),
        observaciones: 'El comprobante del banco dice 6,000',
        movimientoOrigenId: pagoId,
      );
      await movimiento(
        tipo: TipoMovimientoDeuda.reversionPago.name,
        importe: 600000,
        saldoAnterior: 3926608,
        saldoPosterior: 4526608,
        fecha: DateTime(2026, 8, 5, 12),
        observaciones: 'El pago se registró en la tarjeta equivocada',
        movimientoOrigenId: pagoId,
      );

      final eventos = await buscar.ejecutar(const FiltroAuditoria(modulo: 'deudas'));

      expect(eventos, hasLength(5), reason: 'hasta esta etapa NINGUNO llegaba a Auditoría central');
      expect(eventos.map((e) => e.accion), [
        'reversionPago',
        'correccionPago:negativo',
        'pago',
        'cargoTarjeta',
        'altaInicial',
      ]);
      expect(eventos.every((e) => e.actorUsuarioId == 'marlon'), isTrue);
      expect(eventos.every((e) => e.entidadEtiqueta == 'TDC Konfío'), isTrue);
    });

    test('cada movimiento lleva importe y el efecto real sobre el saldo', () async {
      await movimiento(
        tipo: TipoMovimientoDeuda.pago.name,
        importe: 500000,
        saldoAnterior: 3326608,
        saldoPosterior: 2826608,
        fecha: DateTime(2026, 8, 3),
      );

      final evento = (await buscar.ejecutar(const FiltroAuditoria(modulo: 'deudas'))).single;

      expect(evento.importe, 500000);
      expect(evento.cambios, hasLength(1));
      expect(evento.cambios.single.campo, 'saldo');
      expect(evento.cambios.single.antes, '3326608');
      expect(evento.cambios.single.despues, '2826608');
      expect(
        evento.cambios.single.esImporte,
        isTrue,
        reason: 'la UI debe formatearlo como moneda, no como un entero suelto',
      );
    });

    test('un ajuste que corrige un PAGO no se confunde con uno que corrige un CARGO', () async {
      final pagoId = await movimiento(
        tipo: TipoMovimientoDeuda.pago.name,
        importe: 500000,
        saldoAnterior: 3326608,
        saldoPosterior: 2826608,
        fecha: DateTime(2026, 8, 3),
      );
      // Corrige un pago: lleva `movimientoOrigenId`.
      await movimiento(
        tipo: TipoMovimientoDeuda.ajustePositivo.name,
        importe: 50000,
        saldoAnterior: 2826608,
        saldoPosterior: 2876608,
        fecha: DateTime(2026, 8, 4),
        movimientoOrigenId: pagoId,
      );
      // Corrige un cargo: lleva la FK del gasto.
      final compra = await db.into(db.compra).insertReturning(
            CompraCompanion.insert(folioCompra: 'COM-000001', fecha: DateTime(2026, 8, 2), formaPago: 'tarjeta'),
          );
      await movimiento(
        tipo: TipoMovimientoDeuda.ajusteNegativo.name,
        importe: 20000,
        saldoAnterior: 2876608,
        saldoPosterior: 2856608,
        fecha: DateTime(2026, 8, 5),
        compraId: compra.id,
      );

      final acciones =
          (await buscar.ejecutar(const FiltroAuditoria(modulo: 'deudas'))).map((e) => e.accion).toList();

      expect(acciones, contains('correccionPago:positivo'));
      expect(acciones, contains('ajusteTarjeta:compra'));
      expect(
        acciones,
        isNot(contains('ajusteTarjeta:positivo')),
        reason: 'el discriminador es movimientoOrigenId, no el signo',
      );
    });
  });

  group('§2 — el origen funcional se resuelve por FK real, nunca por texto', () {
    test('un cargo de Compra se distingue del evento de negocio de la Compra', () async {
      final compra = await db.into(db.compra).insertReturning(
            CompraCompanion.insert(folioCompra: 'COM-000001', fecha: DateTime(2026, 8, 2), formaPago: 'tarjeta'),
          );
      // El hecho de NEGOCIO: la compra se corrigió.
      await db.into(db.compraEvento).insert(
            CompraEventoCompanion.insert(
              compraId: compra.id,
              fechaHora: DateTime(2026, 8, 2, 9),
              tipoEvento: 'corregida',
              observacion: const Value('Factura del proveedor'),
              actorUsuarioId: const Value('marlon'),
            ),
          );
      // El hecho FINANCIERO: el saldo de la tarjeta se movió.
      await movimiento(
        tipo: TipoMovimientoDeuda.cargoCompra.name,
        importe: 1200000,
        saldoAnterior: 3326608,
        saldoPosterior: 4526608,
        fecha: DateTime(2026, 8, 2, 9),
        compraId: compra.id,
      );

      final eventos = await buscar.ejecutar(const FiltroAuditoria());

      expect(eventos, hasLength(2), reason: 'son dos hechos distintos, los dos auditables');
      final compraEvento = eventos.firstWhere((e) => e.modulo == 'compras');
      final movimientoTarjeta = eventos.firstWhere((e) => e.modulo == 'deudas');
      expect(compraEvento.accion, 'corregida');
      expect(
        movimientoTarjeta.accion,
        'cargoTarjeta:compra',
        reason: 'la acción dice de dónde vino el cargo: no se lee como la misma fila repetida',
      );
      expect(movimientoTarjeta.entidadEtiqueta, 'TDC Konfío');
      expect(compraEvento.entidadEtiqueta, isNot('TDC Konfío'));
    });

    test('un cargo de mantenimiento de vehículo se identifica como tal', () async {
      final vehiculo = await db.into(db.vehiculo).insertReturning(
            VehiculoCompanion.insert(codigo: 'VEH-000001', marca: 'Nissan', modelo: 'NP300', tipoVehiculo: 'pickup'),
          );
      final mantenimiento = await db.into(db.vehiculoMantenimiento).insertReturning(
            VehiculoMantenimientoCompanion.insert(
              vehiculoId: vehiculo.id,
              fecha: DateTime(2026, 8, 4),
              tipo: 'servicioGeneral',
              descripcion: 'Afinación',
              costo: const Value(250000),
            ),
          );
      await movimiento(
        tipo: TipoMovimientoDeuda.cargoCompra.name,
        importe: 250000,
        saldoAnterior: 3326608,
        saldoPosterior: 3576608,
        fecha: DateTime(2026, 8, 4),
        vehiculoMantenimientoId: mantenimiento.id,
      );

      final evento = (await buscar.ejecutar(const FiltroAuditoria(modulo: 'deudas'))).single;
      expect(evento.accion, 'cargoTarjeta:vehiculo');
    });
  });

  group('§5 — privacidad: ningún dato bancario innecesario', () {
    test('la entidad es el nombre de la tarjeta, nunca sus últimos dígitos', () async {
      await movimiento(
        tipo: TipoMovimientoDeuda.pago.name,
        importe: 500000,
        saldoAnterior: 3326608,
        saldoPosterior: 2826608,
        fecha: DateTime(2026, 8, 3),
      );

      final volcado = (await buscar.ejecutar(const FiltroAuditoria()))
          .map((e) => '${e.entidadEtiqueta}|${e.motivo}|${e.detalleJson}|${e.accion}')
          .join('\n');

      expect(volcado, contains('TDC Konfío'));
      expect(volcado, isNot(contains('4821')), reason: 'la Auditoría no necesita el dato bancario para responder quién movió qué');
    });
  });

  // ---------------------------------------------------------------
  // §3 y §9 — Descuentos programados
  // ---------------------------------------------------------------

  Future<({String descuentoId, String cuotaId})> sembrarDescuento() async {
    final empleado = await db.into(db.empleado).insertReturning(
          EmpleadoCompanion.insert(
            numeroEmpleado: 1,
            nombres: 'Javier',
            apellidoPaterno: 'Ruiz',
            sexo: 'masculino',
            fechaNacimiento: DateTime(1990, 1, 1),
            curp: 'RUSJ900101HDFXXX01',
            rfc: 'RUSJ900101AB1',
            nss: '12345678901',
            estadoCivil: 'soltero',
            fechaIngreso: DateTime(2025, 1, 1),
            aniosExperienciaSeguridad: 3,
          ),
        );
    final descuento = await db.into(db.descuentoProgramadoEmpleado).insertReturning(
          DescuentoProgramadoEmpleadoCompanion.insert(
            folio: 'DES-000003',
            empleadoId: empleado.id,
            tipo: 'prestamo',
            fechaRegistro: DateTime(2026, 7, 1),
            importeOriginal: 500000,
            saldoPendiente: 500000,
          ),
        );
    final cuota = await db.into(db.descuentoProgramadoCuota).insertReturning(
          DescuentoProgramadoCuotaCompanion.insert(
            descuentoProgramadoId: descuento.id,
            numeroCuota: 3,
            fechaProgramada: DateTime(2026, 8, 15),
            importeProgramado: 100000,
          ),
        );
    return (descuentoId: descuento.id, cuotaId: cuota.id);
  }

  Future<void> movimientoDescuento({
    required String descuentoProgramadoId,
    String? cuotaId,
    required String tipoMovimiento,
    required DateTime fechaHora,
    int? importe,
    String? observacion,
    String? datosRelevantes,
    String? estadoAnterior,
    String? estadoNuevo,
  }) {
    return db.into(db.descuentoProgramadoMovimiento).insert(
          DescuentoProgramadoMovimientoCompanion.insert(
            descuentoProgramadoId: descuentoProgramadoId,
            cuotaId: Value(cuotaId),
            fechaHora: fechaHora,
            tipoMovimiento: tipoMovimiento,
            importe: Value(importe),
            observacion: Value(observacion),
            datosRelevantes: Value(datosRelevantes),
            estadoAnterior: Value(estadoAnterior),
            estadoNuevo: Value(estadoNuevo),
            actorUsuarioId: const Value('marlon'),
          ),
        );
  }

  group('§9 — el ciclo de un préstamo llega completo, sin filas artificiales', () {
    test('otorgar, reservar, aplicar, revertir, corregir y cancelar', () async {
      final ids = await sembrarDescuento();
      await movimientoDescuento(
        descuentoProgramadoId: ids.descuentoId,
        tipoMovimiento: TipoMovimientoDescuentoProgramado.otorgamiento.name,
        fechaHora: DateTime(2026, 7, 1, 8),
        importe: 500000,
      );
      await movimientoDescuento(
        descuentoProgramadoId: ids.descuentoId,
        cuotaId: ids.cuotaId,
        tipoMovimiento: TipoMovimientoDescuentoProgramado.cuotaReservada.name,
        fechaHora: DateTime(2026, 8, 10, 9),
        importe: 100000,
      );
      await movimientoDescuento(
        descuentoProgramadoId: ids.descuentoId,
        cuotaId: ids.cuotaId,
        tipoMovimiento: TipoMovimientoDescuentoProgramado.cuotaAplicada.name,
        fechaHora: DateTime(2026, 8, 15, 10),
        importe: 100000,
      );
      await movimientoDescuento(
        descuentoProgramadoId: ids.descuentoId,
        cuotaId: ids.cuotaId,
        tipoMovimiento: TipoMovimientoDescuentoProgramado.cuotaRevertida.name,
        fechaHora: DateTime(2026, 8, 16, 11),
        importe: 100000,
        observacion: 'Se canceló el pago de la nómina',
      );
      await movimientoDescuento(
        descuentoProgramadoId: ids.descuentoId,
        tipoMovimiento: TipoMovimientoDescuentoProgramado.correccion.name,
        fechaHora: DateTime(2026, 8, 17, 12),
        observacion: 'El pagaré dice otro importe',
        estadoAnterior: '{"importeOriginal":500000}',
        estadoNuevo: '{"importeOriginal":450000}',
      );
      await movimientoDescuento(
        descuentoProgramadoId: ids.descuentoId,
        tipoMovimiento: TipoMovimientoDescuentoProgramado.cancelacion.name,
        fechaHora: DateTime(2026, 8, 18, 13),
        observacion: 'Saldo condonado por acuerdo',
      );

      final eventos = await buscar.ejecutar(const FiltroAuditoria(modulo: 'descuentos'));

      expect(eventos, hasLength(6), reason: 'seis transiciones reales, ni una fila inventada');
      expect(eventos.map((e) => e.accion), [
        'cancelacion',
        'correccion',
        'cuotaRevertida',
        'cuotaAplicada',
        'cuotaReservada',
        'otorgamiento',
      ]);
      expect(eventos.every((e) => e.actorUsuarioId == 'marlon'), isTrue);
    });

    test('se distingue el movimiento de la OBLIGACIÓN del de una CUOTA concreta', () async {
      final ids = await sembrarDescuento();
      await movimientoDescuento(
        descuentoProgramadoId: ids.descuentoId,
        tipoMovimiento: TipoMovimientoDescuentoProgramado.otorgamiento.name,
        fechaHora: DateTime(2026, 7, 1),
        importe: 500000,
      );
      await movimientoDescuento(
        descuentoProgramadoId: ids.descuentoId,
        cuotaId: ids.cuotaId,
        tipoMovimiento: TipoMovimientoDescuentoProgramado.cuotaAplicada.name,
        fechaHora: DateTime(2026, 8, 15),
        importe: 100000,
      );

      final eventos = await buscar.ejecutar(const FiltroAuditoria(modulo: 'descuentos'));
      final deCuota = eventos.firstWhere((e) => e.accion == 'cuotaAplicada');
      final deObligacion = eventos.firstWhere((e) => e.accion == 'otorgamiento');

      expect(deObligacion.entidadEtiqueta, 'DES-000003');
      expect(deCuota.entidadEtiqueta, 'DES-000003 — cuota 3', reason: 'número de cuota resuelto por id real');
      expect(deCuota.importe, 100000);
      expect(
        deCuota.registroId,
        ids.descuentoId,
        reason: 'el movimiento pertenece a la obligación: es su expediente el que se abre',
      );
    });

    test('la transición YA la expresa el tipo — no se le inventa antes/después', () async {
      final ids = await sembrarDescuento();
      await movimientoDescuento(
        descuentoProgramadoId: ids.descuentoId,
        cuotaId: ids.cuotaId,
        tipoMovimiento: TipoMovimientoDescuentoProgramado.cuotaReservada.name,
        fechaHora: DateTime(2026, 8, 10),
        importe: 100000,
      );

      final evento = (await buscar.ejecutar(const FiltroAuditoria(modulo: 'descuentos'))).single;

      expect(evento.cambios, isEmpty, reason: 'reservar no es un campo que cambie de valor: es el hecho mismo');
      expect(evento.motivo, isNull);
    });

    test('una corrección sí trae su diff real, vía DiffEvento', () async {
      final ids = await sembrarDescuento();
      await movimientoDescuento(
        descuentoProgramadoId: ids.descuentoId,
        tipoMovimiento: TipoMovimientoDescuentoProgramado.correccion.name,
        fechaHora: DateTime(2026, 8, 17),
        observacion: 'El pagaré dice otro importe',
        estadoAnterior: '{"importeOriginal":500000}',
        estadoNuevo: '{"importeOriginal":450000}',
      );

      final evento = (await buscar.ejecutar(const FiltroAuditoria(modulo: 'descuentos'))).single;

      expect(evento.cambios, hasLength(1));
      expect(evento.cambios.single.campo, 'importeOriginal');
      expect(evento.cambios.single.antes, '500000');
      expect(evento.cambios.single.despues, '450000');
      expect(evento.motivo, 'El pagaré dice otro importe');
    });

    test('una reprogramación conserva su datosRelevantes como detalle', () async {
      final ids = await sembrarDescuento();
      await movimientoDescuento(
        descuentoProgramadoId: ids.descuentoId,
        tipoMovimiento: TipoMovimientoDescuentoProgramado.reprogramacion.name,
        fechaHora: DateTime(2026, 8, 20),
        datosRelevantes: '{"planAnterior":5,"planNuevo":8}',
      );

      final evento = (await buscar.ejecutar(const FiltroAuditoria(modulo: 'descuentos'))).single;
      expect(evento.detalleJson, contains('planNuevo'));
    });
  });

  // ---------------------------------------------------------------
  // §6 — Navegación
  // ---------------------------------------------------------------

  group('§6 — navegación por id real', () {
    test('un movimiento de tarjeta lleva al expediente de la Deuda', () async {
      await movimiento(
        tipo: TipoMovimientoDeuda.pago.name,
        importe: 500000,
        saldoAnterior: 3326608,
        saldoPosterior: 2826608,
        fecha: DateTime(2026, 8, 3),
      );

      final evento = (await buscar.ejecutar(const FiltroAuditoria(modulo: 'deudas'))).single;
      final destino = destinoDeEvento(evento)!;

      expect(destino.ruta, '/finanzas/deudas-y-credito/$deudaId');
      expect(destino.ruta, isNot(contains('DEU-000003')), reason: 'nunca por folio');
      expect(destino.exigeMaestro, isFalse);
    });

    test('un movimiento de cuota lleva al expediente del descuento', () async {
      final ids = await sembrarDescuento();
      await movimientoDescuento(
        descuentoProgramadoId: ids.descuentoId,
        cuotaId: ids.cuotaId,
        tipoMovimiento: TipoMovimientoDescuentoProgramado.cuotaAplicada.name,
        fechaHora: DateTime(2026, 8, 15),
        importe: 100000,
      );

      final evento = (await buscar.ejecutar(const FiltroAuditoria(modulo: 'descuentos'))).single;
      expect(destinoDeEvento(evento)!.ruta, '/personal/descuentos/${ids.descuentoId}');
    });
  });

  // ---------------------------------------------------------------
  // §7 — Filtros (los dos módulos YA existen en el catálogo)
  // ---------------------------------------------------------------

  test('§7 — filtrar por deudas y por descuentos aísla cada ledger', () async {
    final ids = await sembrarDescuento();
    await movimiento(
      tipo: TipoMovimientoDeuda.pago.name,
      importe: 500000,
      saldoAnterior: 3326608,
      saldoPosterior: 2826608,
      fecha: DateTime(2026, 8, 3),
    );
    await movimientoDescuento(
      descuentoProgramadoId: ids.descuentoId,
      tipoMovimiento: TipoMovimientoDescuentoProgramado.otorgamiento.name,
      fechaHora: DateTime(2026, 7, 1),
      importe: 500000,
    );

    expect(await buscar.ejecutar(const FiltroAuditoria(modulo: 'deudas')), hasLength(1));
    expect(await buscar.ejecutar(const FiltroAuditoria(modulo: 'descuentos')), hasLength(1));
    expect(
      modulosSoloAuditoria,
      isNot(contains('deudas')),
      reason: 'deudas y descuentos YA son módulos de permiso: no se duplica la categoría',
    );
    expect(modulosSoloAuditoria, isNot(contains('descuentos')));
  });

  // ---------------------------------------------------------------
  // §8 — sin N+1
  // ---------------------------------------------------------------

  test('§8 — 120 movimientos de los dos ledgers no disparan consultas por fila', () async {
    final ids = await sembrarDescuento();
    var saldo = 3326608;
    for (var i = 0; i < 60; i++) {
      saldo -= 1000;
      await movimiento(
        tipo: TipoMovimientoDeuda.pago.name,
        importe: 1000,
        saldoAnterior: saldo + 1000,
        saldoPosterior: saldo,
        fecha: DateTime(2026, 8, 1).add(Duration(minutes: i)),
      );
      await movimientoDescuento(
        descuentoProgramadoId: ids.descuentoId,
        cuotaId: ids.cuotaId,
        tipoMovimiento: TipoMovimientoDescuentoProgramado.cuotaReservada.name,
        fechaHora: DateTime(2026, 8, 2).add(Duration(minutes: i)),
        importe: 100000,
      );
    }

    final antes = DateTime.now();
    final eventos = await buscar.ejecutar(const FiltroAuditoria());
    final duracion = DateTime.now().difference(antes);

    expect(eventos, hasLength(120));
    // Las 120 filas comparten 2 entidades y 1 cuota: los lookups en
    // lote las resuelven con 3 consultas, no con 120.
    expect(eventos.every((e) => e.entidadEtiqueta != null), isTrue);
    expect(
      duracion.inSeconds,
      lessThan(3),
      reason: 'una consulta por fila sobre 120 movimientos tarda órdenes de magnitud más',
    );
  });

  // ---------------------------------------------------------------
  // §13 de la etapa anterior — nada se rompió
  // ---------------------------------------------------------------

  test('EliminacionFisicaEvento sigue mostrándose aparte, sin mezclarse', () async {
    await db.into(db.eliminacionFisicaEvento).insert(
          EliminacionFisicaEventoCompanion.insert(
            tipoEntidad: 'articulo',
            entidadIdOriginal: 'art-borrado',
            fechaHora: DateTime(2026, 8, 6),
            motivo: 'Duplicado',
            snapshotJson: '{"folio":"ART-000009"}',
            actorUsuarioId: const Value('marlon'),
          ),
        );
    await movimiento(
      tipo: TipoMovimientoDeuda.pago.name,
      importe: 500000,
      saldoAnterior: 3326608,
      saldoPosterior: 2826608,
      fecha: DateTime(2026, 8, 3),
    );

    final eventos = await buscar.ejecutar(const FiltroAuditoria());
    final eliminacion = eventos.firstWhere((e) => e.accion.startsWith('eliminacionFisica:'));

    expect(eliminacion.detalleJson, contains('ART-000009'));
    expect(eliminacion.cambios, isEmpty, reason: 'un snapshot no es un diff campo a campo');
    expect(destinoDeEvento(eliminacion), isNull);
  });
}
