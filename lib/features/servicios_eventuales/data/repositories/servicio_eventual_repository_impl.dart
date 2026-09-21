import 'dart:convert';

import 'package:drift/drift.dart';

import 'package:riseg_one/core/auditoria/diff_evento.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/tables/cuenta_por_cobrar_table.dart' show EstatusCuentaPorCobrar;
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show EstatusAplicacionPago, EstatusPago;
import 'package:riseg_one/features/finanzas/domain/repositories/cuenta_por_cobrar_repository.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/deuda_repository.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/egreso_repository.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/pago_repository.dart';

import 'package:riseg_one/features/finanzas/domain/usecases/eliminar_pago_fisicamente_usecase.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart'
    show TipoDocumentoCobro;

import '../../domain/repositories/servicio_eventual_repository.dart';
import '../../domain/totales_venta_eventual.dart';
import '../../domain/usecases/eliminar_servicio_eventual_fisicamente_usecase.dart';
import '../tables/servicio_eventual_table.dart';

/// Núcleo operativo de Servicios Eventuales (Rebanada 1).
///
/// **Compone Finanzas por el camino de escritura oficial**, mismo
/// criterio que `RecargaLineaTelefonicaRepositoryImpl`: el Egreso se
/// crea con `EgresoRepository.crear` y el cargo a tarjeta con
/// `DeudaRepository`, nunca con un insert directo. Un pago produce
/// **exactamente uno de los dos**, nunca ambos, nunca ninguno.
class ServicioEventualRepositoryImpl implements ServicioEventualRepository {
  ServicioEventualRepositoryImpl(
    this._db,
    this._egresoRepository,
    this._deudaRepository,
    this._codigoSecuencia,
    this._cuentaPorCobrarRepository,
    this._pagoRepository,
  );

  final AppDatabase _db;
  final EgresoRepository _egresoRepository;
  final DeudaRepository _deudaRepository;
  final CodigoSecuenciaService _codigoSecuencia;

  /// Cobranza por el camino oficial de Finanzas — igual que el gasto:
  /// este dominio nunca inserta una CxC, un Pago ni un Ingreso a mano.
  final CuentaPorCobrarRepository _cuentaPorCobrarRepository;
  final PagoRepository _pagoRepository;

  // ================================================================
  // Raíz
  // ================================================================
  @override
  Future<ServicioEventualData?> obtenerPorId(String id) {
    return (_db.select(_db.servicioEventual)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  @override
  Future<List<ServicioEventualData>> listar({String? estatus}) {
    final query = _db.select(_db.servicioEventual)
      ..orderBy([(t) => OrderingTerm.desc(t.fechaHoraInicio)]);
    if (estatus != null) query.where((t) => t.estatus.equals(estatus));
    return query.get();
  }

  @override
  Future<Map<String, TotalesServicioEventual>> totalesPorEventual(Iterable<String> servicioEventualIds) async {
    final ids = servicioEventualIds.toSet().toList();
    if (ids.isEmpty) return const {};

    // Cuatro consultas agregadas en total, sin importar cuántos
    // eventuales haya. Nunca una por fila del listado.
    final coberturas = _db.selectOnly(_db.servicioEventualCobertura)
      ..addColumns([
        _db.servicioEventualCobertura.servicioEventualId,
        _db.servicioEventualCobertura.estatus,
        _db.servicioEventualCobertura.importeAcordado.sum(),
      ])
      ..where(_db.servicioEventualCobertura.servicioEventualId.isIn(ids))
      ..groupBy([_db.servicioEventualCobertura.servicioEventualId, _db.servicioEventualCobertura.estatus]);

    final costos = _db.selectOnly(_db.servicioEventualCosto)
      ..addColumns([
        _db.servicioEventualCosto.servicioEventualId,
        _db.servicioEventualCosto.estatus,
        _db.servicioEventualCosto.monto.sum(),
      ])
      ..where(_db.servicioEventualCosto.servicioEventualId.isIn(ids))
      ..groupBy([_db.servicioEventualCosto.servicioEventualId, _db.servicioEventualCosto.estatus]);

    final acumulado = <String, TotalesServicioEventual>{for (final id in ids) id: const TotalesServicioEventual()};

    for (final fila in await coberturas.get()) {
      final id = fila.read(_db.servicioEventualCobertura.servicioEventualId)!;
      final estatus = fila.read(_db.servicioEventualCobertura.estatus)!;
      final total = fila.read(_db.servicioEventualCobertura.importeAcordado.sum()) ?? 0;
      final actual = acumulado[id]!;
      acumulado[id] = TotalesServicioEventual(
        coberturasProgramadas: estatus == EstatusEjecucionServicioEventual.programada.name
            ? actual.coberturasProgramadas + total
            : actual.coberturasProgramadas,
        coberturasPagadas: estatus == EstatusEjecucionServicioEventual.pagada.name
            ? actual.coberturasPagadas + total
            : actual.coberturasPagadas,
        costosProgramados: actual.costosProgramados,
        costosPagados: actual.costosPagados,
      );
    }

    for (final fila in await costos.get()) {
      final id = fila.read(_db.servicioEventualCosto.servicioEventualId)!;
      final estatus = fila.read(_db.servicioEventualCosto.estatus)!;
      final total = fila.read(_db.servicioEventualCosto.monto.sum()) ?? 0;
      final actual = acumulado[id]!;
      acumulado[id] = TotalesServicioEventual(
        coberturasProgramadas: actual.coberturasProgramadas,
        coberturasPagadas: actual.coberturasPagadas,
        costosProgramados: estatus == EstatusEjecucionServicioEventual.programada.name
            ? actual.costosProgramados + total
            : actual.costosProgramados,
        costosPagados: estatus == EstatusEjecucionServicioEventual.pagada.name
            ? actual.costosPagados + total
            : actual.costosPagados,
      );
    }

    return acumulado;
  }

  @override
  Future<VentaServicioEventual> crear({
    required String nombre,
    required DateTime fechaHoraInicio,
    required DateTime fechaHoraFin,
    String? ubicacion,
    String? notas,
    required int importeAcordado,
    required TipoSolicitanteServicioEventual tipoSolicitante,
    String? clienteId,
    String? solicitanteNombre,
    String? solicitanteContacto,
    String? solicitanteTelefono,
    String? solicitanteCorreo,
    String? entidadFiscalId,
    String? solicitanteRazonSocial,
    String? solicitanteRfc,
    String? solicitanteCodigoPostalFiscal,
    required bool requiereFactura,
    required String tratamientoIva,
    required String metodoCobro,
    required bool requiereComplemento,
    DateTime? fechaVencimiento,
    CobroInmediatoServicioEventual? cobroInmediato,
    String? actorUsuarioId,
  }) {
    // Una sola transacción para los tres hechos: se vendió, se debe, y
    // (si aplica) ya se cobró. Si algo falla, no queda un eventual sin
    // cobranza ni una pantalla diciendo que entró dinero que no entró.
    return _db.transaction(() async {
      final folio = await _codigoSecuencia.siguienteCodigo('servicioEventual');
      final eventual = await _db.into(_db.servicioEventual).insertReturning(
            ServicioEventualCompanion.insert(
              folio: folio,
              nombre: nombre,
              fechaHoraInicio: fechaHoraInicio,
              fechaHoraFin: fechaHoraFin,
              ubicacion: Value(ubicacion),
              notas: Value(notas),
              importeAcordado: importeAcordado,
              tipoSolicitante: tipoSolicitante.name,
              clienteId: Value(clienteId),
              solicitanteNombre: Value(solicitanteNombre),
              solicitanteContacto: Value(solicitanteContacto),
              solicitanteTelefono: Value(solicitanteTelefono),
              solicitanteCorreo: Value(solicitanteCorreo),
              entidadFiscalId: Value(entidadFiscalId),
              solicitanteRazonSocial: Value(solicitanteRazonSocial),
              solicitanteRfc: Value(solicitanteRfc),
              solicitanteCodigoPostalFiscal: Value(solicitanteCodigoPostalFiscal),
              requiereFactura: Value(requiereFactura),
              tratamientoIva: Value(tratamientoIva),
              actorUsuarioId: Value(actorUsuarioId),
            ),
          );
      await _asentar(
        servicioEventualId: eventual.id,
        tipoEvento: TipoEventoServicioEventual.creado,
        actorUsuarioId: actorUsuarioId,
      );

      // `tipoDocumento` es 'factura' cuando se va a facturar y
      // 'reciboDePago' cuando no: reutiliza `TipoDocumentoCobro`, nunca
      // un valor inventado, y jamás se crea un `DocumentoPorEmitir`.
      final cuenta = await _cuentaPorCobrarRepository.crearDeServicioEventual(
        servicioEventualId: eventual.id,
        clienteId: clienteId,
        tipoDocumento:
            requiereFactura ? TipoDocumentoCobro.cfdi.name : TipoDocumentoCobro.reciboDePago.name,
        metodo: metodoCobro,
        requiereComplemento: requiereComplemento,
        // La obligación nace con la venta. Cuando exista el CFDI, el
        // documento fiscal refina esta fecha y aporta folio y UUID.
        fechaEmisionReal: fechaHoraInicio,
        // El TOTAL derivado, nunca el importe capturado: con `masIva`
        // son números distintos y la deuda es el total.
        importeEmitido: totalVentaEventual(
          importeAcordado: importeAcordado,
          tratamientoIva: TratamientoIva.values.byName(tratamientoIva),
        ),
        fechaVencimiento: fechaVencimiento,
        actorUsuarioId: actorUsuarioId,
      );
      await _asentar(
        servicioEventualId: eventual.id,
        tipoEvento: TipoEventoServicioEventual.cuentaPorCobrarCreada,
        observacion: 'Cuenta por cobrar de la venta',
        actorUsuarioId: actorUsuarioId,
      );

      PagoData? pago;
      if (cobroInmediato != null) {
        final resultado = await _pagoRepository.crearAplicado(
          folioPago: await _codigoSecuencia.siguienteCodigo('pago'),
          // La contraparte NO se captura: se deriva de la Cuenta, que
          // la derivó del eventual. Así nunca pueden contradecirse.
          clienteId: cuenta.clienteId,
          servicioEventualId: cuenta.servicioEventualId,
          montoTotal: cobroInmediato.monto,
          fechaPago: cobroInmediato.fechaPago,
          formaPago: cobroInmediato.formaPago,
          cuentaPorCobrarId: cuenta.id,
          referencia: cobroInmediato.referencia,
          cuentaFinancieraId: cobroInmediato.cuentaFinancieraId,
          observaciones: cobroInmediato.observaciones,
          actorUsuarioId: actorUsuarioId,
        );
        pago = resultado.pago;
      }

      final cuentaFinal = (await _cuentaPorCobrarRepository.obtenerPorId(cuenta.id))!;
      return (eventual: eventual, cuenta: cuentaFinal, pago: pago);
    });
  }

  @override
  Future<CuentaPorCobrarData?> obtenerCuentaPorCobrar(String servicioEventualId) {
    return _cuentaPorCobrarRepository.obtenerPorServicioEventualId(servicioEventualId);
  }

  @override
  Future<Map<String, String>> nombresSolicitantePorIds(Iterable<String> servicioEventualIds) async {
    final ids = servicioEventualIds.toSet().toList();
    if (ids.isEmpty) return const {};

    final query = _db.selectOnly(_db.servicioEventual)
      ..addColumns([_db.servicioEventual.id, _db.servicioEventual.solicitanteNombre])
      ..where(_db.servicioEventual.id.isIn(ids) & _db.servicioEventual.solicitanteNombre.isNotNull());

    return {
      for (final fila in await query.get())
        fila.read(_db.servicioEventual.id)!: fila.read(_db.servicioEventual.solicitanteNombre)!,
    };
  }

  @override
  Future<ServicioEventualData> corregir({
    required String servicioEventualId,
    String? nombre,
    String? tratamientoIva,
    DateTime? fechaHoraInicio,
    DateTime? fechaHoraFin,
    String? ubicacion,
    String? notas,
    int? importeAcordado,
    bool? requiereFactura,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final antes = (await obtenerPorId(servicioEventualId))!;
      await (_db.update(_db.servicioEventual)..where((t) => t.id.equals(servicioEventualId))).write(
        ServicioEventualCompanion(
          nombre: nombre == null ? const Value.absent() : Value(nombre),
          fechaHoraInicio: fechaHoraInicio == null ? const Value.absent() : Value(fechaHoraInicio),
          fechaHoraFin: fechaHoraFin == null ? const Value.absent() : Value(fechaHoraFin),
          ubicacion: Value(ubicacion),
          notas: Value(notas),
          importeAcordado: importeAcordado == null ? const Value.absent() : Value(importeAcordado),
          tratamientoIva: tratamientoIva == null ? const Value.absent() : Value(tratamientoIva),
          requiereFactura: requiereFactura == null ? const Value.absent() : Value(requiereFactura),
          updatedAt: Value(DateTime.now()),
          actorUsuarioId: Value(actorUsuarioId),
        ),
      );
      final despues = (await obtenerPorId(servicioEventualId))!;

      final diff = DiffEvento()
        ..anotar('nombre', antes.nombre, despues.nombre)
        ..anotar('fechaHoraInicio', antes.fechaHoraInicio, despues.fechaHoraInicio)
        ..anotar('fechaHoraFin', antes.fechaHoraFin, despues.fechaHoraFin)
        ..anotar('ubicacion', antes.ubicacion, despues.ubicacion)
        ..anotar('notas', antes.notas, despues.notas)
        ..anotar('importeAcordado', antes.importeAcordado, despues.importeAcordado)
        ..anotar('tratamientoIva', antes.tratamientoIva, despues.tratamientoIva)
        ..anotar('requiereFactura', antes.requiereFactura, despues.requiereFactura);

      if (diff.hayCambios) {
        await _asentar(
          servicioEventualId: servicioEventualId,
          tipoEvento: TipoEventoServicioEventual.corregido,
          observacion: motivo,
          estadoAnterior: diff.estadoAnteriorJson,
          estadoNuevo: diff.estadoNuevoJson,
          actorUsuarioId: actorUsuarioId,
        );
      }
      return despues;
    });
  }

  @override
  Future<ServicioEventualData> cambiarEstatus({
    required String servicioEventualId,
    required EstatusServicioEventual estatus,
    String? motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final antes = (await obtenerPorId(servicioEventualId))!;
      await (_db.update(_db.servicioEventual)..where((t) => t.id.equals(servicioEventualId))).write(
        ServicioEventualCompanion(
          estatus: Value(estatus.name),
          motivoCancelacion:
              estatus == EstatusServicioEventual.cancelado ? Value(motivo) : const Value.absent(),
          updatedAt: Value(DateTime.now()),
          actorUsuarioId: Value(actorUsuarioId),
        ),
      );

      // Cancelar el evento cancela lo que todavía no ocurrió; lo ya
      // pagado no se toca, porque el dinero salió de verdad.
      if (estatus == EstatusServicioEventual.cancelado) {
        await (_db.update(_db.servicioEventualCobertura)
              ..where((t) =>
                  t.servicioEventualId.equals(servicioEventualId) &
                  t.estatus.equals(EstatusEjecucionServicioEventual.programada.name)))
            .write(ServicioEventualCoberturaCompanion(
          estatus: Value(EstatusEjecucionServicioEventual.cancelada.name),
          motivoCancelacion: Value(motivo),
          updatedAt: Value(DateTime.now()),
        ));
        await (_db.update(_db.servicioEventualCosto)
              ..where((t) =>
                  t.servicioEventualId.equals(servicioEventualId) &
                  t.estatus.equals(EstatusEjecucionServicioEventual.programada.name)))
            .write(ServicioEventualCostoCompanion(
          estatus: Value(EstatusEjecucionServicioEventual.cancelada.name),
          motivoCancelacion: Value(motivo),
          updatedAt: Value(DateTime.now()),
        ));
      }

      final diff = DiffEvento()..anotar('estatus', antes.estatus, estatus.name);
      await _asentar(
        servicioEventualId: servicioEventualId,
        tipoEvento: estatus == EstatusServicioEventual.cancelado
            ? TipoEventoServicioEventual.cancelado
            : TipoEventoServicioEventual.finalizado,
        observacion: motivo,
        estadoAnterior: diff.estadoAnteriorJson,
        estadoNuevo: diff.estadoNuevoJson,
        actorUsuarioId: actorUsuarioId,
      );
      return (await obtenerPorId(servicioEventualId))!;
    });
  }


  @override
  Future<Map<String, int>> cobradoVigentePorEventual(Iterable<String> servicioEventualIds) async {
    final ids = servicioEventualIds.toSet().toList();
    if (ids.isEmpty) return const {};

    final monto = _db.aplicacionPago.monto.sum();
    final query = _db.selectOnly(_db.aplicacionPago).join([
      innerJoin(
        _db.cuentaPorCobrar,
        _db.cuentaPorCobrar.id.equalsExp(_db.aplicacionPago.cuentaPorCobrarId),
      ),
      innerJoin(_db.pago, _db.pago.id.equalsExp(_db.aplicacionPago.pagoId)),
    ])
      ..addColumns([_db.cuentaPorCobrar.servicioEventualId, monto])
      ..where(_db.cuentaPorCobrar.servicioEventualId.isIn(ids) &
          _db.aplicacionPago.estatus.equals(EstatusAplicacionPago.aplicada.name) &
          // El estatus del Pago se comprueba además de la aplicación:
          // cancelar un Pago ya cancela sus aplicaciones, pero depender
          // de esa cascada haría que un futuro camino que la olvide
          // volviera a inflar lo cobrado en silencio.
          _db.pago.estatus.equals(EstatusPago.cancelado.name).not())
      ..groupBy([_db.cuentaPorCobrar.servicioEventualId]);

    final filas = await query.get();
    return {
      for (final id in ids) id: 0,
      for (final fila in filas)
        fila.read(_db.cuentaPorCobrar.servicioEventualId)!: fila.read(monto) ?? 0,
    };
  }

  @override
  Future<List<CobroDeVentaEventual>> cobrosDeLaVenta(String servicioEventualId) async {
    final cuenta = await obtenerCuentaPorCobrar(servicioEventualId);
    if (cuenta == null) return const [];

    final aplicaciones = await _pagoRepository.listarAplicacionesPorCuenta(cuenta.id);
    final vigentes = aplicaciones
        .where((a) => a.estatus == EstatusAplicacionPago.aplicada.name)
        .toList();
    if (vigentes.isEmpty) return const [];

    final cobros = <CobroDeVentaEventual>[];
    for (final aplicacion in vigentes) {
      final pago = await _pagoRepository.obtenerPorId(aplicacion.pagoId);
      if (pago == null) continue;
      // ¿Este Pago cubre algo más? Si sí, cancelarlo entero devolvería
      // dinero de otra cobranza.
      final delPago = await _pagoRepository.listarAplicacionesPorPago(pago.id);
      final otras = delPago.where(
        (a) => a.estatus == EstatusAplicacionPago.aplicada.name && a.cuentaPorCobrarId != cuenta.id,
      );
      cobros.add(CobroDeVentaEventual(
        pago: pago,
        aplicacionId: aplicacion.id,
        monto: aplicacion.monto,
        exclusivoDeEstaVenta: otras.isEmpty,
      ));
    }
    return cobros;
  }

  @override
  Future<ServicioEventualData> anularVenta({
    required String servicioEventualId,
    required String motivo,
    String? actorUsuarioId,
  }) {
    // Una sola transacción: o la venta queda anulada entera —sin saldo
    // por cobrar y sin dinero fantasma en el banco— o no cambia nada.
    // Un estado intermedio es exactamente lo que la prueba manual
    // encontró y esto corrige.
    return _db.transaction(() async {
      await revertirCobranzaDeLaVenta(
        servicioEventualId: servicioEventualId,
        motivo: motivo,
        actorUsuarioId: actorUsuarioId,
      );

      // 3. Y el evento operativo, con lo que todavía no ocurría. Los
      //    gastos ya pagados NO se tocan aquí ni en ningún paso.
      return cambiarEstatus(
        servicioEventualId: servicioEventualId,
        estatus: EstatusServicioEventual.cancelado,
        motivo: motivo,
        actorUsuarioId: actorUsuarioId,
      );
    });
  }

  @override
  Future<List<ServicioEventualData>> listarCanceladosConCobranzaViva() async {
    // La firma exacta de "cancelado con la implementación anterior a la
    // v90", por FK y estatus — nunca por folio, monto ni texto: el
    // evento está cancelado pero su Cuenta por cobrar NO. La anulación
    // nueva cancela ambos en la misma transacción, y cuando se bloquea
    // por CFDI tampoco cancela el evento; así que este estado sólo lo
    // pudo dejar el `cambiarEstatus` viejo.
    final query = _db.select(_db.servicioEventual).join([
      innerJoin(
        _db.cuentaPorCobrar,
        _db.cuentaPorCobrar.servicioEventualId.equalsExp(_db.servicioEventual.id),
      ),
    ])
      ..where(_db.servicioEventual.estatus.equals(EstatusServicioEventual.cancelado.name) &
          _db.cuentaPorCobrar.estatus.equals(EstatusCuentaPorCobrar.cancelada.name).not());
    final filas = await query.get();
    return [for (final fila in filas) fila.readTable(_db.servicioEventual)];
  }

  @override
  Future<void> revertirCobranzaDeLaVenta({
    required String servicioEventualId,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final cobros = await cobrosDeLaVenta(servicioEventualId);

      // 1. El dinero de ESTA venta, de vuelta. Los Pagos exclusivos se
      //    cancelan enteros (cascada a aplicación, Ingreso y saldo de
      //    la cuenta); de los compartidos sólo se suelta la aplicación,
      //    porque el depósito sí ocurrió y cubría algo más.
      final pagosCancelados = <String>{};
      for (final cobro in cobros) {
        if (cobro.exclusivoDeEstaVenta) {
          if (pagosCancelados.add(cobro.pago.id)) {
            await _pagoRepository.cancelar(
              pagoId: cobro.pago.id,
              motivo: motivo,
              actorUsuarioId: actorUsuarioId,
            );
          }
        } else {
          await _pagoRepository.cancelarAplicacion(
            aplicacionPagoId: cobro.aplicacionId,
            motivo: motivo,
            actorUsuarioId: actorUsuarioId,
          );
        }
        await _asentar(
          servicioEventualId: servicioEventualId,
          tipoEvento: TipoEventoServicioEventual.cobroRevertido,
          observacion: cobro.exclusivoDeEstaVenta
              ? 'Pago ${cobro.pago.folioPago} cancelado (${cobro.monto}).'
              : 'Aplicación del pago ${cobro.pago.folioPago} cancelada (${cobro.monto}); el pago sigue vigente para otras cuentas.',
          actorUsuarioId: actorUsuarioId,
        );
      }

      // 2. La obligación de cobro. Se cancela DESPUÉS de soltar los
      //    pagos: una Cuenta con aplicaciones vigentes no se puede
      //    cancelar (regla de `CancelarCuentaPorCobrarUseCase`), y ese
      //    orden es justamente la garantía de que no quedó ninguna.
      final cuenta = await obtenerCuentaPorCobrar(servicioEventualId);
      if (cuenta != null && cuenta.estatus != EstatusCuentaPorCobrar.cancelada.name) {
        await _cuentaPorCobrarRepository.cancelar(
          cuentaPorCobrarId: cuenta.id,
          motivo: motivo,
          actorUsuarioId: actorUsuarioId,
        );
      }

      await _asentar(
        servicioEventualId: servicioEventualId,
        tipoEvento: TipoEventoServicioEventual.ventaAnulada,
        observacion: motivo,
        actorUsuarioId: actorUsuarioId,
      );
    });
  }

  // ================================================================
  // Participantes
  // ================================================================
  @override
  Future<List<ServicioEventualParticipanteData>> listarParticipantes(String servicioEventualId) {
    return (_db.select(_db.servicioEventualParticipante)
          ..where((t) => t.servicioEventualId.equals(servicioEventualId))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  @override
  Future<ServicioEventualParticipanteData> agregarParticipante({
    required String servicioEventualId,
    String? empleadoId,
    String? nombreExterno,
    String? telefonoExterno,
    String? observaciones,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final participante = await _db.into(_db.servicioEventualParticipante).insertReturning(
            ServicioEventualParticipanteCompanion.insert(
              servicioEventualId: servicioEventualId,
              empleadoId: Value(empleadoId),
              nombreExterno: Value(nombreExterno),
              telefonoExterno: Value(telefonoExterno),
              observaciones: Value(observaciones),
              actorUsuarioId: Value(actorUsuarioId),
            ),
          );
      await _asentar(
        servicioEventualId: servicioEventualId,
        tipoEvento: TipoEventoServicioEventual.participanteAgregado,
        participanteId: participante.id,
        actorUsuarioId: actorUsuarioId,
      );
      return participante;
    });
  }

  @override
  Future<void> retirarParticipante({required String participanteId, String? actorUsuarioId}) {
    return _db.transaction(() async {
      final participante = await (_db.select(_db.servicioEventualParticipante)
            ..where((t) => t.id.equals(participanteId)))
          .getSingle();
      await (_db.delete(_db.servicioEventualParticipante)..where((t) => t.id.equals(participanteId))).go();
      await _asentar(
        servicioEventualId: participante.servicioEventualId,
        tipoEvento: TipoEventoServicioEventual.participanteRetirado,
        participanteId: participanteId,
        actorUsuarioId: actorUsuarioId,
      );
    });
  }

  // ================================================================
  // Coberturas
  // ================================================================
  @override
  Future<ServicioEventualCoberturaData?> obtenerCobertura(String coberturaId) {
    return (_db.select(_db.servicioEventualCobertura)..where((t) => t.id.equals(coberturaId))).getSingleOrNull();
  }

  @override
  Future<List<ServicioEventualCoberturaData>> listarCoberturas(String servicioEventualId) {
    return (_db.select(_db.servicioEventualCobertura)
          ..where((t) => t.servicioEventualId.equals(servicioEventualId))
          ..orderBy([(t) => OrderingTerm.asc(t.fecha), (t) => OrderingTerm.asc(t.horaInicioMinutos)]))
        .get();
  }

  @override
  Future<List<ServicioEventualCoberturaData>> listarCoberturasPorParticipante(String participanteId) {
    return (_db.select(_db.servicioEventualCobertura)..where((t) => t.participanteId.equals(participanteId))).get();
  }

  @override
  Future<ServicioEventualCoberturaData> agregarCobertura({
    required String servicioEventualId,
    required String participanteId,
    required DateTime fecha,
    required int horaInicioMinutos,
    required int horaFinMinutos,
    String? descripcionHorario,
    required int importeAcordado,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final cobertura = await _db.into(_db.servicioEventualCobertura).insertReturning(
            ServicioEventualCoberturaCompanion.insert(
              servicioEventualId: servicioEventualId,
              participanteId: participanteId,
              fecha: fecha,
              horaInicioMinutos: horaInicioMinutos,
              horaFinMinutos: horaFinMinutos,
              descripcionHorario: Value(descripcionHorario),
              importeAcordado: importeAcordado,
              actorUsuarioId: Value(actorUsuarioId),
            ),
          );
      // Programar es comprometer un costo, no moverlo: aquí no se crea
      // Egreso ni cargo de tarjeta.
      await _asentar(
        servicioEventualId: servicioEventualId,
        tipoEvento: TipoEventoServicioEventual.coberturaAgregada,
        coberturaId: cobertura.id,
        actorUsuarioId: actorUsuarioId,
      );
      return cobertura;
    });
  }

  @override
  Future<ServicioEventualCoberturaData> corregirCobertura({
    required String coberturaId,
    DateTime? fecha,
    int? horaInicioMinutos,
    int? horaFinMinutos,
    String? descripcionHorario,
    int? importeAcordado,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final antes = (await obtenerCobertura(coberturaId))!;
      await (_db.update(_db.servicioEventualCobertura)..where((t) => t.id.equals(coberturaId))).write(
        ServicioEventualCoberturaCompanion(
          fecha: fecha == null ? const Value.absent() : Value(fecha),
          horaInicioMinutos: horaInicioMinutos == null ? const Value.absent() : Value(horaInicioMinutos),
          horaFinMinutos: horaFinMinutos == null ? const Value.absent() : Value(horaFinMinutos),
          descripcionHorario: Value(descripcionHorario),
          importeAcordado: importeAcordado == null ? const Value.absent() : Value(importeAcordado),
          updatedAt: Value(DateTime.now()),
          actorUsuarioId: Value(actorUsuarioId),
        ),
      );
      final despues = (await obtenerCobertura(coberturaId))!;
      final diff = DiffEvento()
        ..anotar('fecha', antes.fecha, despues.fecha)
        ..anotar('horaInicioMinutos', antes.horaInicioMinutos, despues.horaInicioMinutos)
        ..anotar('horaFinMinutos', antes.horaFinMinutos, despues.horaFinMinutos)
        ..anotar('importeAcordado', antes.importeAcordado, despues.importeAcordado);
      if (diff.hayCambios) {
        await _asentar(
          servicioEventualId: antes.servicioEventualId,
          tipoEvento: TipoEventoServicioEventual.coberturaCorregida,
          coberturaId: coberturaId,
          observacion: motivo,
          estadoAnterior: diff.estadoAnteriorJson,
          estadoNuevo: diff.estadoNuevoJson,
          actorUsuarioId: actorUsuarioId,
        );
      }
      return despues;
    });
  }

  @override
  Future<ServicioEventualCoberturaData> cancelarCobertura({
    required String coberturaId,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final antes = (await obtenerCobertura(coberturaId))!;
      await (_db.update(_db.servicioEventualCobertura)..where((t) => t.id.equals(coberturaId))).write(
        ServicioEventualCoberturaCompanion(
          estatus: Value(EstatusEjecucionServicioEventual.cancelada.name),
          motivoCancelacion: Value(motivo),
          updatedAt: Value(DateTime.now()),
          actorUsuarioId: Value(actorUsuarioId),
        ),
      );
      await _asentar(
        servicioEventualId: antes.servicioEventualId,
        tipoEvento: TipoEventoServicioEventual.coberturaCancelada,
        coberturaId: coberturaId,
        observacion: motivo,
        actorUsuarioId: actorUsuarioId,
      );
      return (await obtenerCobertura(coberturaId))!;
    });
  }

  @override
  Future<ServicioEventualCoberturaData> pagarCobertura({
    required String coberturaId,
    required String formaPago,
    String? cuentaFinancieraId,
    String? deudaId,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final cobertura = (await obtenerCobertura(coberturaId))!;
      final eventual = (await obtenerPorId(cobertura.servicioEventualId))!;
      final concepto = 'Cobertura ${eventual.folio} - ${eventual.nombre}';

      String? egresoId;
      if (deudaId != null) {
        // TDC: sube el pasivo y NUNCA crea un Egreso — la salida de
        // banco ocurrirá al pagar la tarjeta.
        await _deudaRepository.registrarCargoCoberturaServicioEventual(
          deudaId: deudaId,
          coberturaId: coberturaId,
          monto: cobertura.importeAcordado,
          fecha: cobertura.fecha,
          observaciones: concepto,
          actorUsuarioId: actorUsuarioId,
        );
      } else {
        final egreso = await _egresoRepository.crear(
          folioEgreso: await _codigoSecuencia.siguienteCodigo('egreso'),
          monto: cobertura.importeAcordado,
          fecha: cobertura.fecha,
          cuentaFinancieraId: cuentaFinancieraId,
          formaPago: formaPago,
          concepto: concepto,
          actorUsuarioId: actorUsuarioId,
        );
        egresoId = egreso.id;
      }

      await (_db.update(_db.servicioEventualCobertura)..where((t) => t.id.equals(coberturaId))).write(
        ServicioEventualCoberturaCompanion(
          estatus: Value(EstatusEjecucionServicioEventual.pagada.name),
          formaPago: Value(formaPago),
          egresoId: Value(egresoId),
          deudaId: Value(deudaId),
          cuentaFinancieraId: Value(cuentaFinancieraId),
          updatedAt: Value(DateTime.now()),
          actorUsuarioId: Value(actorUsuarioId),
        ),
      );
      await _asentar(
        servicioEventualId: cobertura.servicioEventualId,
        tipoEvento: TipoEventoServicioEventual.coberturaPagada,
        coberturaId: coberturaId,
        observacion: concepto,
        actorUsuarioId: actorUsuarioId,
      );
      return (await obtenerCobertura(coberturaId))!;
    });
  }

  @override
  Future<ServicioEventualCoberturaData> revertirPagoCobertura({
    required String coberturaId,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final cobertura = (await obtenerCobertura(coberturaId))!;

      if (cobertura.deudaId != null) {
        await _deudaRepository.revertirCargoCoberturaServicioEventual(
          deudaId: cobertura.deudaId!,
          coberturaId: coberturaId,
          motivo: motivo,
          actorUsuarioId: actorUsuarioId,
        );
      } else if (cobertura.egresoId != null) {
        await _egresoRepository.cancelar(
          egresoId: cobertura.egresoId!,
          motivo: motivo,
          actorUsuarioId: actorUsuarioId,
        );
      }

      // Revertir el PAGO no cancela la COBERTURA: el trabajo se sigue
      // habiendo comprometido, y puede volver a pagarse.
      await (_db.update(_db.servicioEventualCobertura)..where((t) => t.id.equals(coberturaId))).write(
        ServicioEventualCoberturaCompanion(
          estatus: Value(EstatusEjecucionServicioEventual.programada.name),
          formaPago: const Value(null),
          egresoId: const Value(null),
          deudaId: const Value(null),
          cuentaFinancieraId: const Value(null),
          updatedAt: Value(DateTime.now()),
          actorUsuarioId: Value(actorUsuarioId),
        ),
      );
      await _asentar(
        servicioEventualId: cobertura.servicioEventualId,
        tipoEvento: TipoEventoServicioEventual.coberturaPagoRevertido,
        coberturaId: coberturaId,
        observacion: motivo,
        actorUsuarioId: actorUsuarioId,
      );
      return (await obtenerCobertura(coberturaId))!;
    });
  }

  // ================================================================
  // Costos
  // ================================================================
  @override
  Future<ServicioEventualCostoData?> obtenerCosto(String costoId) {
    return (_db.select(_db.servicioEventualCosto)..where((t) => t.id.equals(costoId))).getSingleOrNull();
  }

  @override
  Future<List<ServicioEventualCostoData>> listarCostos(String servicioEventualId) {
    return (_db.select(_db.servicioEventualCosto)
          ..where((t) => t.servicioEventualId.equals(servicioEventualId))
          ..orderBy([(t) => OrderingTerm.asc(t.fecha)]))
        .get();
  }

  @override
  Future<ServicioEventualCostoData> agregarCosto({
    required String servicioEventualId,
    required String concepto,
    required int monto,
    required DateTime fecha,
    String? observaciones,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final costo = await _db.into(_db.servicioEventualCosto).insertReturning(
            ServicioEventualCostoCompanion.insert(
              servicioEventualId: servicioEventualId,
              concepto: concepto,
              monto: monto,
              fecha: fecha,
              observaciones: Value(observaciones),
              actorUsuarioId: Value(actorUsuarioId),
            ),
          );
      await _asentar(
        servicioEventualId: servicioEventualId,
        tipoEvento: TipoEventoServicioEventual.costoAgregado,
        costoId: costo.id,
        actorUsuarioId: actorUsuarioId,
      );
      return costo;
    });
  }

  @override
  Future<ServicioEventualCostoData> corregirCosto({
    required String costoId,
    String? concepto,
    int? monto,
    DateTime? fecha,
    String? observaciones,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final antes = (await obtenerCosto(costoId))!;
      await (_db.update(_db.servicioEventualCosto)..where((t) => t.id.equals(costoId))).write(
        ServicioEventualCostoCompanion(
          concepto: concepto == null ? const Value.absent() : Value(concepto),
          monto: monto == null ? const Value.absent() : Value(monto),
          fecha: fecha == null ? const Value.absent() : Value(fecha),
          observaciones: Value(observaciones),
          updatedAt: Value(DateTime.now()),
          actorUsuarioId: Value(actorUsuarioId),
        ),
      );
      final despues = (await obtenerCosto(costoId))!;
      final diff = DiffEvento()
        ..anotar('concepto', antes.concepto, despues.concepto)
        ..anotar('monto', antes.monto, despues.monto)
        ..anotar('fecha', antes.fecha, despues.fecha);
      if (diff.hayCambios) {
        await _asentar(
          servicioEventualId: antes.servicioEventualId,
          tipoEvento: TipoEventoServicioEventual.costoCorregido,
          costoId: costoId,
          observacion: motivo,
          estadoAnterior: diff.estadoAnteriorJson,
          estadoNuevo: diff.estadoNuevoJson,
          actorUsuarioId: actorUsuarioId,
        );
      }
      return despues;
    });
  }

  @override
  Future<ServicioEventualCostoData> cancelarCosto({
    required String costoId,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final antes = (await obtenerCosto(costoId))!;
      await (_db.update(_db.servicioEventualCosto)..where((t) => t.id.equals(costoId))).write(
        ServicioEventualCostoCompanion(
          estatus: Value(EstatusEjecucionServicioEventual.cancelada.name),
          motivoCancelacion: Value(motivo),
          updatedAt: Value(DateTime.now()),
          actorUsuarioId: Value(actorUsuarioId),
        ),
      );
      await _asentar(
        servicioEventualId: antes.servicioEventualId,
        tipoEvento: TipoEventoServicioEventual.costoCancelado,
        costoId: costoId,
        observacion: motivo,
        actorUsuarioId: actorUsuarioId,
      );
      return (await obtenerCosto(costoId))!;
    });
  }

  @override
  Future<ServicioEventualCostoData> pagarCosto({
    required String costoId,
    required String formaPago,
    String? cuentaFinancieraId,
    String? deudaId,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final costo = (await obtenerCosto(costoId))!;
      final eventual = (await obtenerPorId(costo.servicioEventualId))!;
      final concepto = '${costo.concepto} - ${eventual.folio}';

      String? egresoId;
      if (deudaId != null) {
        await _deudaRepository.registrarCargoCostoServicioEventual(
          deudaId: deudaId,
          costoId: costoId,
          monto: costo.monto,
          fecha: costo.fecha,
          observaciones: concepto,
          actorUsuarioId: actorUsuarioId,
        );
      } else {
        final egreso = await _egresoRepository.crear(
          folioEgreso: await _codigoSecuencia.siguienteCodigo('egreso'),
          monto: costo.monto,
          fecha: costo.fecha,
          cuentaFinancieraId: cuentaFinancieraId,
          formaPago: formaPago,
          concepto: concepto,
          actorUsuarioId: actorUsuarioId,
        );
        egresoId = egreso.id;
      }

      await (_db.update(_db.servicioEventualCosto)..where((t) => t.id.equals(costoId))).write(
        ServicioEventualCostoCompanion(
          estatus: Value(EstatusEjecucionServicioEventual.pagada.name),
          formaPago: Value(formaPago),
          egresoId: Value(egresoId),
          deudaId: Value(deudaId),
          cuentaFinancieraId: Value(cuentaFinancieraId),
          updatedAt: Value(DateTime.now()),
          actorUsuarioId: Value(actorUsuarioId),
        ),
      );
      await _asentar(
        servicioEventualId: costo.servicioEventualId,
        tipoEvento: TipoEventoServicioEventual.costoPagado,
        costoId: costoId,
        observacion: concepto,
        actorUsuarioId: actorUsuarioId,
      );
      return (await obtenerCosto(costoId))!;
    });
  }

  @override
  Future<ServicioEventualCostoData> revertirPagoCosto({
    required String costoId,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final costo = (await obtenerCosto(costoId))!;

      if (costo.deudaId != null) {
        await _deudaRepository.revertirCargoCostoServicioEventual(
          deudaId: costo.deudaId!,
          costoId: costoId,
          motivo: motivo,
          actorUsuarioId: actorUsuarioId,
        );
      } else if (costo.egresoId != null) {
        await _egresoRepository.cancelar(
          egresoId: costo.egresoId!,
          motivo: motivo,
          actorUsuarioId: actorUsuarioId,
        );
      }

      await (_db.update(_db.servicioEventualCosto)..where((t) => t.id.equals(costoId))).write(
        ServicioEventualCostoCompanion(
          estatus: Value(EstatusEjecucionServicioEventual.programada.name),
          formaPago: const Value(null),
          egresoId: const Value(null),
          deudaId: const Value(null),
          cuentaFinancieraId: const Value(null),
          updatedAt: Value(DateTime.now()),
          actorUsuarioId: Value(actorUsuarioId),
        ),
      );
      await _asentar(
        servicioEventualId: costo.servicioEventualId,
        tipoEvento: TipoEventoServicioEventual.costoPagoRevertido,
        costoId: costoId,
        observacion: motivo,
        actorUsuarioId: actorUsuarioId,
      );
      return (await obtenerCosto(costoId))!;
    });
  }

  // ================================================================
  // Bitácora y utilidades
  // ================================================================
  Future<void> _asentar({
    required String servicioEventualId,
    required TipoEventoServicioEventual tipoEvento,
    String? coberturaId,
    String? costoId,
    String? participanteId,
    String? observacion,
    String? estadoAnterior,
    String? estadoNuevo,
    String? actorUsuarioId,
  }) {
    return registrarEvento(
      servicioEventualId: servicioEventualId,
      tipoEvento: tipoEvento,
      coberturaId: coberturaId,
      costoId: costoId,
      participanteId: participanteId,
      observacion: observacion,
      estadoAnterior: estadoAnterior,
      estadoNuevo: estadoNuevo,
      actorUsuarioId: actorUsuarioId,
    );
  }

  @override
  Future<void> registrarEvento({
    required String servicioEventualId,
    required TipoEventoServicioEventual tipoEvento,
    String? coberturaId,
    String? costoId,
    String? participanteId,
    String? observacion,
    String? estadoAnterior,
    String? estadoNuevo,
    String? actorUsuarioId,
  }) async {
    await _db.into(_db.servicioEventualEvento).insert(
          ServicioEventualEventoCompanion.insert(
            servicioEventualId: servicioEventualId,
            fechaHora: DateTime.now(),
            tipoEvento: tipoEvento.name,
            coberturaId: Value(coberturaId),
            costoId: Value(costoId),
            participanteId: Value(participanteId),
            observacion: Value(observacion),
            estadoAnterior: Value(estadoAnterior),
            estadoNuevo: Value(estadoNuevo),
            actorUsuarioId: Value(actorUsuarioId),
          ),
        );
  }

  @override
  Future<List<ServicioEventualEventoData>> listarEventos(String servicioEventualId) {
    return (_db.select(_db.servicioEventualEvento)
          ..where((t) => t.servicioEventualId.equals(servicioEventualId))
          ..orderBy([(t) => OrderingTerm.desc(t.fechaHora), (t) => OrderingTerm.desc(t.id)]))
        .get();
  }

  @override
  Future<ServicioEventualCoberturaData?> obtenerCoberturaPorEgresoId(String egresoId) {
    return (_db.select(_db.servicioEventualCobertura)..where((t) => t.egresoId.equals(egresoId)))
        .getSingleOrNull();
  }

  @override
  Future<ServicioEventualCostoData?> obtenerCostoPorEgresoId(String egresoId) {
    return (_db.select(_db.servicioEventualCosto)..where((t) => t.egresoId.equals(egresoId))).getSingleOrNull();
  }

  @override
  Future<List<String>> listarEgresoIds() async {
    final coberturas = _db.selectOnly(_db.servicioEventualCobertura)
      ..addColumns([_db.servicioEventualCobertura.egresoId])
      ..where(_db.servicioEventualCobertura.egresoId.isNotNull());
    final costos = _db.selectOnly(_db.servicioEventualCosto)
      ..addColumns([_db.servicioEventualCosto.egresoId])
      ..where(_db.servicioEventualCosto.egresoId.isNotNull());

    return [
      for (final fila in await coberturas.get()) fila.read(_db.servicioEventualCobertura.egresoId)!,
      for (final fila in await costos.get()) fila.read(_db.servicioEventualCosto.egresoId)!,
    ];
  }

  @override
  Future<EliminarServicioEventualFisicamenteResultado> eliminarFisicamente({
    required String servicioEventualId,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final eventual = await obtenerPorId(servicioEventualId);
      if (eventual == null) return EliminarServicioEventualFisicamenteNoExiste();

      // Huella financiera real: un Egreso emitido o un cargo vivo en
      // una tarjeta. Revertir el pago los deja en `null`, así que un
      // eventual cuyos pagos ya se revirtieron sí es elegible.
      final coberturasPagadas = await (_db.select(_db.servicioEventualCobertura)
            ..where((t) =>
                t.servicioEventualId.equals(servicioEventualId) &
                (t.egresoId.isNotNull() | t.deudaId.isNotNull())))
          .get();
      if (coberturasPagadas.isNotEmpty) {
        return EliminarServicioEventualFisicamenteTieneDependencias(
          'Tiene ${coberturasPagadas.length} cobertura(s) con pago registrado.',
        );
      }

      final costosPagados = await (_db.select(_db.servicioEventualCosto)
            ..where((t) =>
                t.servicioEventualId.equals(servicioEventualId) &
                (t.egresoId.isNotNull() | t.deudaId.isNotNull())))
          .get();
      if (costosPagados.isNotEmpty) {
        return EliminarServicioEventualFisicamenteTieneDependencias(
          'Tiene ${costosPagados.length} costo(s) con pago registrado.',
        );
      }

      // schemaVersion 88 — ahora TODO eventual tiene su Cuenta por
      // cobrar, así que su mera existencia ya no puede bloquear.
      //
      // El eventual es el ORIGEN del borrado: nadie tiene que ir a
      // Finanzas a desarmar la cobranza a mano. Pero sólo se lleva lo
      // que es suyo:
      //
      //  * Pago EXCLUSIVO de esta Cuenta -> se elimina por el flujo de
      //    Pagos (`PagoRepository.eliminarFisicamente`), que ya sabe
      //    llevarse su Aplicación, su Ingreso y sus comprobantes, y que
      //    conserva sus propias reglas: Pago cancelado y sin ningún
      //    Complemento. Sus reglas mandan; aquí no se reimplementan.
      //  * Pago COMPARTIDO con otra Cuenta por cobrar -> BLOQUEA. Ese
      //    depósito cubre cobranza ajena: borrarlo movería el saldo de
      //    una operación que nada tiene que ver con este evento.
      final cuentas = await (_db.select(_db.cuentaPorCobrar)
            ..where((t) => t.servicioEventualId.equals(servicioEventualId)))
          .get();
      final pagosPropios = <String>{};
      for (final cuenta in cuentas) {
        final aplicaciones =
            await (_db.select(_db.aplicacionPago)..where((t) => t.cuentaPorCobrarId.equals(cuenta.id))).get();
        for (final aplicacion in aplicaciones) {
          final delPago = await (_db.select(_db.aplicacionPago)
                ..where((t) => t.pagoId.equals(aplicacion.pagoId)))
              .get();
          final ajenas = delPago.where((a) => a.cuentaPorCobrarId != cuenta.id).length;
          if (ajenas > 0) {
            final pago = await (_db.select(_db.pago)..where((t) => t.id.equals(aplicacion.pagoId))).getSingle();
            return EliminarServicioEventualFisicamenteTieneDependencias(
              'El pago ${pago.folioPago} también cubre $ajenas cuenta(s) por cobrar de otra operación, '
              'así que no puede eliminarse con este evento. Desaplícalo de esta cuenta primero.',
            );
          }
          // Las reglas del Pago, consultadas ANTES de tocar nada: un
          // Pago vivo o con Complemento no se elimina, y entonces
          // tampoco el evento.
          final resumen = await _pagoRepository.obtenerResumenEliminacionFisica(aplicacion.pagoId);
          if (resumen.bloqueado) {
            final pago = await (_db.select(_db.pago)..where((t) => t.id.equals(aplicacion.pagoId))).getSingle();
            return EliminarServicioEventualFisicamenteTieneDependencias(
              'Pago ${pago.folioPago}: ${resumen.detalleBloqueo}',
            );
          }
          pagosPropios.add(aplicacion.pagoId);
        }
      }

      await _db.into(_db.eliminacionFisicaEvento).insert(
            EliminacionFisicaEventoCompanion.insert(
              tipoEntidad: 'servicioEventual',
              entidadIdOriginal: servicioEventualId,
              fechaHora: DateTime.now(),
              motivo: motivo,
              snapshotJson: jsonEncode(eventual.toJson()),
              actorUsuarioId: Value(actorUsuarioId),
            ),
          );

      // Orden inverso a las dependencias.
      //
      // Documentos fiscales y sus adjuntos: el CFDI histórico se va con
      // el eventual porque sin él no documenta nada. El archivo físico
      // en disco lo limpia el mismo mantenimiento que el del resto de
      // adjuntos huérfanos — aquí sólo se sueltan las filas.
      final documentos = await (_db.select(_db.servicioEventualDocumentoFiscal)
            ..where((t) => t.servicioEventualId.equals(servicioEventualId)))
          .get();
      for (final documento in documentos) {
        final adjuntos = await (_db.select(_db.servicioEventualDocumentoFiscalAttachment)
              ..where((t) => t.servicioEventualDocumentoFiscalId.equals(documento.id)))
            .get();
        await (_db.delete(_db.servicioEventualDocumentoFiscalAttachment)
              ..where((t) => t.servicioEventualDocumentoFiscalId.equals(documento.id)))
            .go();
        for (final adjunto in adjuntos) {
          await (_db.delete(_db.attachment)..where((t) => t.id.equals(adjunto.attachmentId))).go();
        }
      }
      await (_db.delete(_db.servicioEventualDocumentoFiscal)
            ..where((t) => t.servicioEventualId.equals(servicioEventualId)))
          .go();

      // Los Pagos exclusivos, por su propio flujo: se llevan su
      // Aplicación, su Ingreso y sus comprobantes, y dejan su propio
      // `EliminacionFisicaEvento` con su snapshot. Va ANTES que la
      // Cuenta, que los referencia por `restrict`.
      for (final pagoId in pagosPropios) {
        final eliminado = await _pagoRepository.eliminarFisicamente(
          pagoId: pagoId,
          motivo: motivo,
          actorUsuarioId: actorUsuarioId,
        );
        if (eliminado is! EliminarPagoFisicamenteExitoso) {
          // Nunca debería pasar: el resumen ya se consultó arriba. Si
          // pasa, la transacción entera se deshace.
          throw StateError('No se pudo eliminar el pago $pagoId del eventual $servicioEventualId.');
        }
      }

      // La Cuenta por cobrar, ya sin una sola aplicación, y su bitácora.
      for (final cuenta in cuentas) {
        await (_db.delete(_db.cuentaPorCobrarEvento)..where((t) => t.cuentaPorCobrarId.equals(cuenta.id))).go();
        await (_db.delete(_db.cuentaPorCobrar)..where((t) => t.id.equals(cuenta.id))).go();
      }

      await (_db.delete(_db.servicioEventualEvento)
            ..where((t) => t.servicioEventualId.equals(servicioEventualId)))
          .go();
      await (_db.delete(_db.servicioEventualCosto)
            ..where((t) => t.servicioEventualId.equals(servicioEventualId)))
          .go();
      await (_db.delete(_db.servicioEventualCobertura)
            ..where((t) => t.servicioEventualId.equals(servicioEventualId)))
          .go();
      await (_db.delete(_db.servicioEventualParticipante)
            ..where((t) => t.servicioEventualId.equals(servicioEventualId)))
          .go();
      await (_db.delete(_db.servicioEventual)..where((t) => t.id.equals(servicioEventualId))).go();

      return EliminarServicioEventualFisicamenteExitoso();
    });
  }
}
