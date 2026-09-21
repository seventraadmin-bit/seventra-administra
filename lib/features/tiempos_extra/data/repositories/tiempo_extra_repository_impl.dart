import 'dart:convert';

import 'package:drift/drift.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/finanzas/domain/repositories/deuda_repository.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/egreso_repository.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/servicio_repository.dart';
import 'package:riseg_one/features/personal/domain/repositories/empleado_repository.dart';
import 'package:riseg_one/features/personal/presentation/empleados/empleados_list_screen.dart' show empleadoNombreCompleto;

import '../../domain/repositories/tiempo_extra_repository.dart';
import '../../domain/usecases/eliminar_tiempo_extra_fisicamente_usecase.dart';
import '../tables/tiempo_extra_table.dart';
import 'vacante_cobertura_reader.dart';

class TiempoExtraRepositoryImpl implements TiempoExtraRepository {
  TiempoExtraRepositoryImpl(
    this._db,
    this._egresoRepository,
    this._deudaRepository,
    this._codigoSecuencia,
    this._empleadoRepository,
    this._servicioRepository,
  );

  final AppDatabase _db;
  final EgresoRepository _egresoRepository;
  final DeudaRepository _deudaRepository;
  final CodigoSecuenciaService _codigoSecuencia;
  final EmpleadoRepository _empleadoRepository;
  final ServicioRepository _servicioRepository;

  late final _vacantes = VacanteCoberturaReader(_db);

  // --- Etiquetas para el diff de auditoría -------------------------
  //
  // El diff se guarda LEGIBLE, nunca con UUIDs: Auditoría central lo
  // proyecta tal cual y un id ahí no le dice nada a quien audita.
  // Sólo se resuelve lo que realmente cambió (ver `corregir`), así que
  // esto nunca cuesta más de un puñado de lecturas por corrección.

  Future<String?> _nombreEmpleado(String? empleadoId) async {
    if (empleadoId == null) return null;
    final empleado = await _empleadoRepository.obtenerPorId(empleadoId);
    return empleado == null ? null : empleadoNombreCompleto(empleado);
  }

  Future<String?> _nombreServicio(String? servicioId) async {
    if (servicioId == null) return null;
    final servicio = await _servicioRepository.obtenerPorId(servicioId);
    return servicio?.nombre;
  }

  Future<String?> _nombreTurno(String? turnoId) async {
    if (turnoId == null) return null;
    final turno =
        await (_db.select(_db.tipoModalidadTurno)..where((t) => t.id.equals(turnoId))).getSingleOrNull();
    return turno?.nombre;
  }

  Future<String?> _etiquetaVacante(String? vacanteId) async {
    if (vacanteId == null) return null;
    final vacante = await _vacantes.porId(vacanteId);
    return vacante?.etiqueta;
  }

  @override
  Future<TiempoExtraData?> obtenerPorId(String id) {
    return (_db.select(_db.tiempoExtra)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  @override
  Future<String?> obtenerTiempoExtraIdPorEgresoId(String egresoId) async {
    final base = await (_db.select(_db.tiempoExtra)..where((t) => t.egresoId.equals(egresoId))).getSingleOrNull();
    if (base != null) return base.id;

    final costo = await (_db.select(_db.tiempoExtraCostoAdicional)..where((t) => t.egresoId.equals(egresoId)))
        .getSingleOrNull();
    return costo?.tiempoExtraId;
  }

  @override
  Future<List<String>> listarEgresoIdsEnRango({DateTime? rangoInicio, DateTime? rangoFin}) async {
    final baseQuery = _db.select(_db.tiempoExtra)..where((t) => t.egresoId.isNotNull());
    if (rangoInicio != null) baseQuery.where((t) => t.fecha.isBiggerOrEqualValue(rangoInicio));
    if (rangoFin != null) baseQuery.where((t) => t.fecha.isSmallerOrEqualValue(rangoFin));
    final base = await baseQuery.get();

    final costoQuery = _db.select(_db.tiempoExtraCostoAdicional).join([
      innerJoin(_db.tiempoExtra, _db.tiempoExtra.id.equalsExp(_db.tiempoExtraCostoAdicional.tiempoExtraId)),
    ])
      ..where(_db.tiempoExtraCostoAdicional.egresoId.isNotNull());
    if (rangoInicio != null) costoQuery.where(_db.tiempoExtra.fecha.isBiggerOrEqualValue(rangoInicio));
    if (rangoFin != null) costoQuery.where(_db.tiempoExtra.fecha.isSmallerOrEqualValue(rangoFin));
    final costos = await costoQuery.map((row) => row.readTable(_db.tiempoExtraCostoAdicional)).get();

    return [
      for (final t in base) t.egresoId!,
      for (final c in costos) c.egresoId!,
    ];
  }

  @override
  Future<List<TiempoExtraData>> listar({DateTime? rangoInicio, DateTime? rangoFin, String? servicioId, String? estatus}) {
    final query = _db.select(_db.tiempoExtra)..orderBy([(t) => OrderingTerm.desc(t.fecha)]);
    if (rangoInicio != null) query.where((t) => t.fecha.isBiggerOrEqualValue(rangoInicio));
    if (rangoFin != null) query.where((t) => t.fecha.isSmallerOrEqualValue(rangoFin));
    if (servicioId != null) query.where((t) => t.servicioId.equals(servicioId));
    if (estatus != null) query.where((t) => t.estatus.equals(estatus));
    return query.get();
  }

  @override
  Future<List<TiempoExtraCostoAdicionalData>> listarCostosAdicionales(String tiempoExtraId) {
    return (_db.select(_db.tiempoExtraCostoAdicional)
          ..where((t) => t.tiempoExtraId.equals(tiempoExtraId) & t.eliminado.equals(false)))
        .get();
  }

  /// Igual que [listarCostosAdicionales] pero SIN excluir `eliminado`
  /// — uso exclusivo de `eliminarFisicamente`/
  /// `obtenerResumenEliminacionFisica`: al borrar el TiempoExtra
  /// completo, las filas "quitadas" durante una corrección también
  /// deben limpiarse (siguen existiendo físicamente en BD).
  Future<List<TiempoExtraCostoAdicionalData>> _listarTodosLosCostos(String tiempoExtraId) {
    return (_db.select(_db.tiempoExtraCostoAdicional)..where((t) => t.tiempoExtraId.equals(tiempoExtraId))).get();
  }

  @override
  Future<Map<String, int>> totalCostosAdicionalesPorTiempoExtra(List<String> tiempoExtraIds) async {
    if (tiempoExtraIds.isEmpty) return {};
    final filas = await (_db.select(_db.tiempoExtraCostoAdicional)
          ..where((t) => t.tiempoExtraId.isIn(tiempoExtraIds) & t.eliminado.equals(false)))
        .get();
    final totales = <String, int>{};
    for (final fila in filas) {
      totales[fila.tiempoExtraId] = (totales[fila.tiempoExtraId] ?? 0) + fila.monto;
    }
    return totales;
  }

  @override
  Future<List<TiempoExtraEventoData>> listarEventos(String tiempoExtraId) {
    return (_db.select(_db.tiempoExtraEvento)
          ..where((t) => t.tiempoExtraId.equals(tiempoExtraId))
          ..orderBy([(t) => OrderingTerm.asc(t.fechaHora)]))
        .get();
  }

  @override
  Future<List<TiempoExtraData>> listarPorEmpleadoAusenteYRango({
    required String empleadoId,
    required DateTime desde,
    required DateTime hasta,
  }) {
    // Filtra también por origen: sólo la cobertura por AUSENCIA de un
    // titular se anota en la Nómina de ese titular. Una vacante o un
    // "otro" no tienen empleado ausente, así que el filtro por
    // `empleadoAusenteId` ya los excluiría — esto lo deja explícito en
    // vez de depender de que la columna siga nula.
    return (_db.select(_db.tiempoExtra)
          ..where((t) =>
              t.empleadoAusenteId.equals(empleadoId) &
              t.origenCobertura.equals(OrigenCoberturaTiempoExtra.ausenciaEmpleado.name) &
              t.estatus.equals(EstatusTiempoExtra.registrado.name) &
              t.fecha.isBiggerOrEqualValue(desde) &
              t.fecha.isSmallerOrEqualValue(hasta)))
        .get();
  }

  @override
  Future<List<AusenciaParaNomina>> listarAusenciasParaNomina({
    required String empleadoId,
    required DateTime desde,
    required DateTime hasta,
  }) async {
    final registros = await listarPorEmpleadoAusenteYRango(empleadoId: empleadoId, desde: desde, hasta: hasta);
    final resultado = <AusenciaParaNomina>[];
    for (final r in registros) {
      final servicio = await _servicioRepository.obtenerPorId(r.servicioId);
      final nombreCubre = r.empleadoCubreId != null
          ? empleadoNombreCompleto((await _empleadoRepository.obtenerPorId(r.empleadoCubreId!))!)
          : (r.nombreExternoCubre ?? '—');
      final motivoAusencia = r.motivoAusencia;
      if (motivoAusencia == null) continue; // imposible con origen ausenciaEmpleado
      resultado.add(AusenciaParaNomina(
        tiempoExtraId: r.id,
        fecha: r.fecha,
        motivoAusencia: motivoAusencia,
        servicioId: r.servicioId,
        servicioNombre: servicio?.nombre ?? '—',
        nombreCubre: nombreCubre,
      ));
    }
    return resultado;
  }

  Future<void> _registrarEvento({
    required String tiempoExtraId,
    required String tipoEvento,
    String? observacion,
    String? actorUsuarioId,
    String? estadoAnterior,
    String? estadoNuevo,
  }) {
    return _db.into(_db.tiempoExtraEvento).insert(
          TiempoExtraEventoCompanion.insert(
            tiempoExtraId: tiempoExtraId,
            fechaHora: DateTime.now(),
            tipoEvento: tipoEvento,
            observacion: Value(observacion),
            actorUsuarioId: Value(actorUsuarioId),
            estadoAnterior: Value(estadoAnterior),
            estadoNuevo: Value(estadoNuevo),
          ),
        );
  }

  @override
  Future<TiempoExtraData> crear({
    required DateTime fecha,
    required String servicioId,
    required String origenCobertura,
    String? empleadoAusenteId,
    String? motivoAusencia,
    String? vacanteOperativaId,
    String? descripcionOrigen,
    String? empleadoCubreId,
    String? nombreExternoCubre,
    required String turnoId,
    required int montoTiempoExtra,
    required String formaPago,
    String? cuentaFinancieraId,
    String? deudaIdTarjeta,
    String? observaciones,
    List<CostoAdicionalInput> costosAdicionales = const [],
    required String beneficiarioEgreso,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final folio = await _codigoSecuencia.siguienteCodigo('tiempoExtra');
      var tiempoExtra = await _db.into(_db.tiempoExtra).insertReturning(
            TiempoExtraCompanion.insert(
              folio: folio,
              fecha: fecha,
              servicioId: servicioId,
              origenCobertura: Value(origenCobertura),
              empleadoAusenteId: Value(empleadoAusenteId),
              motivoAusencia: Value(motivoAusencia),
              vacanteOperativaId: Value(vacanteOperativaId),
              descripcionOrigen: Value(descripcionOrigen),
              empleadoCubreId: Value(empleadoCubreId),
              nombreExternoCubre: Value(nombreExternoCubre),
              turnoId: turnoId,
              montoTiempoExtra: montoTiempoExtra,
              formaPago: formaPago,
              observaciones: Value(observaciones),
            ),
          );

      // Pago base — origen independiente de cada costo adicional
      // (Etapa "origen financiero unificado"): nunca se fusiona con
      // ellos aunque compartan cuenta.
      if (deudaIdTarjeta != null) {
        await _deudaRepository.registrarCargoTiempoExtra(
          deudaId: deudaIdTarjeta,
          tiempoExtraId: tiempoExtra.id,
          monto: montoTiempoExtra,
          fecha: fecha,
          actorUsuarioId: actorUsuarioId,
        );
        tiempoExtra = await (_db.update(_db.tiempoExtra)..where((t) => t.id.equals(tiempoExtra.id)))
            .writeReturning(TiempoExtraCompanion(deudaId: Value(deudaIdTarjeta)))
            .then((rows) => rows.single);
      } else {
        final folioEgreso = await _codigoSecuencia.siguienteCodigo('egreso');
        final egreso = await _egresoRepository.crear(
          folioEgreso: folioEgreso,
          monto: montoTiempoExtra,
          fecha: fecha,
          servicioId: servicioId,
          cuentaFinancieraId: cuentaFinancieraId,
          formaPago: formaPago,
          beneficiario: beneficiarioEgreso,
          concepto: 'Tiempo extra $folio — pago',
          observaciones: observaciones,
          actorUsuarioId: actorUsuarioId,
        );
        tiempoExtra = await (_db.update(_db.tiempoExtra)..where((t) => t.id.equals(tiempoExtra.id)))
            .writeReturning(TiempoExtraCompanion(egresoId: Value(egreso.id)))
            .then((rows) => rows.single);
      }

      // Cada costo adicional — su propio origen, su propio Egreso o
      // cargo de tarjeta, nunca combinado con el pago base ni entre sí.
      for (final costo in costosAdicionales) {
        final costoRow = await _db.into(_db.tiempoExtraCostoAdicional).insertReturning(
              TiempoExtraCostoAdicionalCompanion.insert(
                tiempoExtraId: tiempoExtra.id,
                concepto: costo.concepto,
                monto: costo.monto,
                formaPago: Value(costo.formaPago),
              ),
            );

        if (costo.deudaIdTarjeta != null) {
          await _deudaRepository.registrarCargoCostoAdicional(
            deudaId: costo.deudaIdTarjeta!,
            costoAdicionalId: costoRow.id,
            monto: costo.monto,
            fecha: fecha,
            actorUsuarioId: actorUsuarioId,
          );
          await (_db.update(_db.tiempoExtraCostoAdicional)..where((t) => t.id.equals(costoRow.id)))
              .write(TiempoExtraCostoAdicionalCompanion(deudaId: Value(costo.deudaIdTarjeta)));
        } else {
          final folioEgresoCosto = await _codigoSecuencia.siguienteCodigo('egreso');
          final egresoCosto = await _egresoRepository.crear(
            folioEgreso: folioEgresoCosto,
            monto: costo.monto,
            fecha: fecha,
            servicioId: servicioId,
            cuentaFinancieraId: costo.cuentaFinancieraId,
            formaPago: costo.formaPago,
            beneficiario: beneficiarioEgreso,
            concepto: 'Tiempo extra $folio — costo: ${costo.concepto}',
            actorUsuarioId: actorUsuarioId,
          );
          await (_db.update(_db.tiempoExtraCostoAdicional)..where((t) => t.id.equals(costoRow.id)))
              .write(TiempoExtraCostoAdicionalCompanion(egresoId: Value(egresoCosto.id)));
        }
      }

      final montoTotal = montoTiempoExtra + costosAdicionales.fold<int>(0, (s, c) => s + c.monto);
      await _registrarEvento(
        tiempoExtraId: tiempoExtra.id,
        tipoEvento: 'registrado',
        actorUsuarioId: actorUsuarioId,
        observacion: jsonEncode({'montoTotal': montoTotal, 'costosAdicionales': costosAdicionales.length}),
      );

      return (await obtenerPorId(tiempoExtra.id))!;
    });
  }

  @override
  Future<TiempoExtraData> cancelar({required String tiempoExtraId, required String motivo, String? actorUsuarioId}) {
    return _db.transaction(() async {
      final actual = await (_db.select(_db.tiempoExtra)..where((t) => t.id.equals(tiempoExtraId))).getSingle();

      final cancelado = await (_db.update(_db.tiempoExtra)..where((t) => t.id.equals(tiempoExtraId)))
          .writeReturning(TiempoExtraCompanion(
            estatus: const Value('cancelado'),
            motivoCancelacion: Value(motivo),
            updatedAt: Value(DateTime.now()),
          ))
          .then((rows) => rows.single);

      // Pago base — exactamente uno de los dos, según cómo se registró.
      if (actual.egresoId != null) {
        await _egresoRepository.cancelar(egresoId: actual.egresoId!, motivo: motivo, actorUsuarioId: actorUsuarioId);
      } else if (actual.deudaId != null) {
        await _deudaRepository.revertirCargoTiempoExtra(
          deudaId: actual.deudaId!,
          tiempoExtraId: tiempoExtraId,
          motivo: motivo,
          actorUsuarioId: actorUsuarioId,
        );
      }

      // Cada costo adicional, con el mismo criterio.
      final costos = await listarCostosAdicionales(tiempoExtraId);
      for (final costo in costos) {
        if (costo.egresoId != null) {
          await _egresoRepository.cancelar(egresoId: costo.egresoId!, motivo: motivo, actorUsuarioId: actorUsuarioId);
        } else if (costo.deudaId != null) {
          await _deudaRepository.revertirCargoCostoAdicional(
            deudaId: costo.deudaId!,
            costoAdicionalId: costo.id,
            motivo: motivo,
            actorUsuarioId: actorUsuarioId,
          );
        }
      }

      await _registrarEvento(
        tiempoExtraId: tiempoExtraId,
        tipoEvento: 'cancelado',
        observacion: motivo,
        actorUsuarioId: actorUsuarioId,
      );

      return cancelado;
    });
  }

  /// Núcleo de la corrección de UN ítem (pago base o un costo
  /// adicional) — resuelve la transición de origen financiero completa
  /// (ver el doc comment de `TiempoExtraRepository.corregir`) y
  /// devuelve el nuevo par (egresoId, deudaId) a escribir en la fila
  /// del ítem, mutuamente excluyente. [tiempoExtraId]/[costoAdicionalId]
  /// identifican el ítem (exactamente uno de los dos) ante
  /// `DeudaRepository`.
  Future<({String? egresoId, String? deudaId})> _aplicarTransicionOrigen({
    required String? egresoIdAnterior,
    required String? deudaIdAnterior,
    required int montoAnterior,
    required String formaPagoNueva,
    required int montoNuevo,
    String? cuentaFinancieraIdNueva,
    String? deudaIdTarjetaNueva,
    required DateTime fecha,
    required String motivo,
    String? actorUsuarioId,
    required String servicioId,
    required String beneficiarioEgreso,
    required String conceptoEgreso,
    String? tiempoExtraId,
    int? costoAdicionalId,
  }) async {
    final esNuevoTarjeta = formaPagoNueva == FormaPago.tarjeta.name;

    Future<EgresoData> crearEgresoNuevo() async {
      final folioEgresoNuevo = await _codigoSecuencia.siguienteCodigo('egreso');
      return _egresoRepository.crear(
        folioEgreso: folioEgresoNuevo,
        monto: montoNuevo,
        fecha: fecha,
        servicioId: servicioId,
        cuentaFinancieraId: cuentaFinancieraIdNueva,
        formaPago: formaPagoNueva,
        beneficiario: beneficiarioEgreso,
        concepto: conceptoEgreso,
        actorUsuarioId: actorUsuarioId,
      );
    }

    Future<void> revertirTarjetaAnterior() {
      return tiempoExtraId != null
          ? _deudaRepository.revertirCargoTiempoExtra(
              deudaId: deudaIdAnterior!, tiempoExtraId: tiempoExtraId, motivo: motivo, actorUsuarioId: actorUsuarioId)
          : _deudaRepository.revertirCargoCostoAdicional(
              deudaId: deudaIdAnterior!, costoAdicionalId: costoAdicionalId!, motivo: motivo, actorUsuarioId: actorUsuarioId);
    }

    Future<void> aplicarCargoTarjetaNueva(String deudaId) {
      return tiempoExtraId != null
          ? _deudaRepository.registrarCargoTiempoExtra(
              deudaId: deudaId, tiempoExtraId: tiempoExtraId, monto: montoNuevo, fecha: fecha, actorUsuarioId: actorUsuarioId)
          : _deudaRepository.registrarCargoCostoAdicional(
              deudaId: deudaId, costoAdicionalId: costoAdicionalId!, monto: montoNuevo, fecha: fecha, actorUsuarioId: actorUsuarioId);
    }

    // Cuenta → Cuenta (misma o distinta): sobreescribe el Egreso
    // existente — el saldo de CuentaFinanciera se deriva sumando
    // `Egreso.monto` en el momento de la lectura, así que esto ya
    // mueve el efecto sin duplicar ni dejar residuo.
    if (egresoIdAnterior != null && !esNuevoTarjeta) {
      await _egresoRepository.corregir(
        egresoId: egresoIdAnterior,
        cuentaFinancieraId: cuentaFinancieraIdNueva,
        limpiarCuentaFinancieraId: cuentaFinancieraIdNueva == null,
        servicioId: servicioId,
        beneficiario: beneficiarioEgreso,
        motivo: motivo,
        actorUsuarioId: actorUsuarioId,
      );
      if (montoNuevo != montoAnterior) {
        await _egresoRepository.corregirMonto(
          egresoId: egresoIdAnterior, nuevoMonto: montoNuevo, motivo: motivo, actorUsuarioId: actorUsuarioId);
      }
      return (egresoId: egresoIdAnterior, deudaId: null);
    }

    // TDC → TDC.
    if (deudaIdAnterior != null && esNuevoTarjeta) {
      if (deudaIdTarjetaNueva == deudaIdAnterior) {
        // Misma tarjeta: ajuste-delta, nunca reescribe el cargo original.
        final delta = montoNuevo - montoAnterior;
        if (delta != 0) {
          await (tiempoExtraId != null
              ? _deudaRepository.registrarAjusteCargoTiempoExtra(
                  deudaId: deudaIdAnterior, tiempoExtraId: tiempoExtraId, deltaImporte: delta, motivo: motivo, actorUsuarioId: actorUsuarioId)
              : _deudaRepository.registrarAjusteCargoCostoAdicional(
                  deudaId: deudaIdAnterior, costoAdicionalId: costoAdicionalId!, deltaImporte: delta, motivo: motivo, actorUsuarioId: actorUsuarioId));
        }
        return (egresoId: null, deudaId: deudaIdAnterior);
      }
      // Tarjeta distinta: revierte el cargo completo de la vieja +
      // aplica un cargo completo nuevo en la otra.
      await revertirTarjetaAnterior();
      await aplicarCargoTarjetaNueva(deudaIdTarjetaNueva!);
      return (egresoId: null, deudaId: deudaIdTarjetaNueva);
    }

    // Cuenta → TDC: cancela el Egreso viejo por completo + aplica un
    // cargo completo nuevo.
    if (egresoIdAnterior != null && esNuevoTarjeta) {
      await _egresoRepository.cancelar(egresoId: egresoIdAnterior, motivo: motivo, actorUsuarioId: actorUsuarioId);
      await aplicarCargoTarjetaNueva(deudaIdTarjetaNueva!);
      return (egresoId: null, deudaId: deudaIdTarjetaNueva);
    }

    // TDC → Cuenta: revierte el cargo completo + crea un Egreso nuevo.
    if (deudaIdAnterior != null && !esNuevoTarjeta) {
      await revertirTarjetaAnterior();
      final egreso = await crearEgresoNuevo();
      return (egresoId: egreso.id, deudaId: null);
    }

    // Ningún origen anterior (dato histórico sin origen capturado) —
    // se trata como un alta nueva para este ítem.
    if (esNuevoTarjeta) {
      await aplicarCargoTarjetaNueva(deudaIdTarjetaNueva!);
      return (egresoId: null, deudaId: deudaIdTarjetaNueva);
    }
    final egreso = await crearEgresoNuevo();
    return (egresoId: egreso.id, deudaId: null);
  }

  @override
  Future<TiempoExtraData> corregir({
    required String tiempoExtraId,
    required DateTime fecha,
    required String servicioId,
    required String origenCobertura,
    String? empleadoAusenteId,
    String? motivoAusencia,
    String? vacanteOperativaId,
    String? descripcionOrigen,
    String? empleadoCubreId,
    String? nombreExternoCubre,
    required String turnoId,
    required int montoTiempoExtra,
    required String formaPago,
    String? cuentaFinancieraId,
    String? deudaIdTarjeta,
    String? observaciones,
    List<CorreccionCostoAdicional> cambiosCostos = const [],
    required String beneficiarioEgreso,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final anterior = await (_db.select(_db.tiempoExtra)..where((t) => t.id.equals(tiempoExtraId))).getSingle();

      final estadoAnterior = <String, Object?>{};
      final estadoNuevo = <String, Object?>{};
      void anotarSiCambio(String campo, Object? antes, Object? despues) {
        if (antes != despues) {
          estadoAnterior[campo] = antes;
          estadoNuevo[campo] = despues;
        }
      }

      // El diff viaja LEGIBLE: Auditoría central lo muestra tal cual,
      // y un UUID crudo ahí no le dice nada a nadie. Se resuelven los
      // nombres una sola vez, sólo de lo que realmente cambió.
      anotarSiCambio('fecha', anterior.fecha.toIso8601String(), fecha.toIso8601String());
      if (anterior.servicioId != servicioId) {
        anotarSiCambio('servicio', await _nombreServicio(anterior.servicioId), await _nombreServicio(servicioId));
      }
      anotarSiCambio('origenCobertura', anterior.origenCobertura, origenCobertura);
      if (anterior.empleadoAusenteId != empleadoAusenteId) {
        anotarSiCambio(
          'empleadoAusente',
          await _nombreEmpleado(anterior.empleadoAusenteId),
          await _nombreEmpleado(empleadoAusenteId),
        );
      }
      anotarSiCambio('motivoAusencia', anterior.motivoAusencia, motivoAusencia);
      if (anterior.vacanteOperativaId != vacanteOperativaId) {
        anotarSiCambio(
          'vacante',
          await _etiquetaVacante(anterior.vacanteOperativaId),
          await _etiquetaVacante(vacanteOperativaId),
        );
      }
      anotarSiCambio('descripcionOrigen', anterior.descripcionOrigen, descripcionOrigen);
      if (anterior.empleadoCubreId != empleadoCubreId) {
        anotarSiCambio(
          'empleadoCubre',
          await _nombreEmpleado(anterior.empleadoCubreId),
          await _nombreEmpleado(empleadoCubreId),
        );
      }
      anotarSiCambio('nombreExternoCubre', anterior.nombreExternoCubre, nombreExternoCubre);
      if (anterior.turnoId != turnoId) {
        anotarSiCambio('turno', await _nombreTurno(anterior.turnoId), await _nombreTurno(turnoId));
      }
      anotarSiCambio('montoTiempoExtra', anterior.montoTiempoExtra, montoTiempoExtra);
      anotarSiCambio('formaPago', anterior.formaPago, formaPago);
      anotarSiCambio('observaciones', anterior.observaciones, observaciones);

      await (_db.update(_db.tiempoExtra)..where((t) => t.id.equals(tiempoExtraId))).write(
        TiempoExtraCompanion(
          fecha: Value(fecha),
          servicioId: Value(servicioId),
          origenCobertura: Value(origenCobertura),
          empleadoAusenteId: Value(empleadoAusenteId),
          motivoAusencia: Value(motivoAusencia),
          vacanteOperativaId: Value(vacanteOperativaId),
          descripcionOrigen: Value(descripcionOrigen),
          empleadoCubreId: Value(empleadoCubreId),
          nombreExternoCubre: Value(nombreExternoCubre),
          turnoId: Value(turnoId),
          montoTiempoExtra: Value(montoTiempoExtra),
          formaPago: Value(formaPago),
          observaciones: Value(observaciones),
          updatedAt: Value(DateTime.now()),
        ),
      );

      // Pago base — transición de origen independiente de cada costo.
      final origenBase = await _aplicarTransicionOrigen(
        egresoIdAnterior: anterior.egresoId,
        deudaIdAnterior: anterior.deudaId,
        montoAnterior: anterior.montoTiempoExtra,
        formaPagoNueva: formaPago,
        montoNuevo: montoTiempoExtra,
        cuentaFinancieraIdNueva: formaPago == FormaPago.tarjeta.name ? null : cuentaFinancieraId,
        deudaIdTarjetaNueva: formaPago == FormaPago.tarjeta.name ? deudaIdTarjeta : null,
        fecha: fecha,
        motivo: motivo,
        actorUsuarioId: actorUsuarioId,
        servicioId: servicioId,
        beneficiarioEgreso: beneficiarioEgreso,
        conceptoEgreso: 'Tiempo extra ${anterior.folio} — pago',
        tiempoExtraId: tiempoExtraId,
      );
      await (_db.update(_db.tiempoExtra)..where((t) => t.id.equals(tiempoExtraId))).write(
        TiempoExtraCompanion(egresoId: Value(origenBase.egresoId), deudaId: Value(origenBase.deudaId)),
      );

      final costosAntes = <String, Object?>{};
      final costosDespues = <String, Object?>{};

      for (final cambio in cambiosCostos) {
        switch (cambio) {
          case CorreccionCostoAdicionalEditar():
            final costoAnterior = await (_db.select(_db.tiempoExtraCostoAdicional)
                  ..where((t) => t.id.equals(cambio.costoAdicionalId)))
                .getSingle();
            costosAntes['costo${cambio.costoAdicionalId}'] = {
              'concepto': costoAnterior.concepto,
              'monto': costoAnterior.monto,
              'formaPago': costoAnterior.formaPago,
            };
            costosDespues['costo${cambio.costoAdicionalId}'] = {
              'concepto': cambio.concepto,
              'monto': cambio.monto,
              'formaPago': cambio.formaPago,
            };

            final origenCosto = await _aplicarTransicionOrigen(
              egresoIdAnterior: costoAnterior.egresoId,
              deudaIdAnterior: costoAnterior.deudaId,
              montoAnterior: costoAnterior.monto,
              formaPagoNueva: cambio.formaPago,
              montoNuevo: cambio.monto,
              cuentaFinancieraIdNueva: cambio.formaPago == FormaPago.tarjeta.name ? null : cambio.cuentaFinancieraId,
              deudaIdTarjetaNueva: cambio.formaPago == FormaPago.tarjeta.name ? cambio.deudaIdTarjeta : null,
              fecha: fecha,
              motivo: motivo,
              actorUsuarioId: actorUsuarioId,
              servicioId: servicioId,
              beneficiarioEgreso: beneficiarioEgreso,
              conceptoEgreso: 'Tiempo extra ${anterior.folio} — costo: ${cambio.concepto}',
              costoAdicionalId: cambio.costoAdicionalId,
            );
            await (_db.update(_db.tiempoExtraCostoAdicional)..where((t) => t.id.equals(cambio.costoAdicionalId))).write(
              TiempoExtraCostoAdicionalCompanion(
                concepto: Value(cambio.concepto),
                monto: Value(cambio.monto),
                formaPago: Value(cambio.formaPago),
                egresoId: Value(origenCosto.egresoId),
                deudaId: Value(origenCosto.deudaId),
              ),
            );

          case CorreccionCostoAdicionalAgregar():
            final costoRow = await _db.into(_db.tiempoExtraCostoAdicional).insertReturning(
                  TiempoExtraCostoAdicionalCompanion.insert(
                    tiempoExtraId: tiempoExtraId,
                    concepto: cambio.concepto,
                    monto: cambio.monto,
                    formaPago: Value(cambio.formaPago),
                  ),
                );
            costosDespues['costo${costoRow.id}Agregado'] = {
              'concepto': cambio.concepto,
              'monto': cambio.monto,
              'formaPago': cambio.formaPago,
            };
            final origenCosto = await _aplicarTransicionOrigen(
              egresoIdAnterior: null,
              deudaIdAnterior: null,
              montoAnterior: 0,
              formaPagoNueva: cambio.formaPago,
              montoNuevo: cambio.monto,
              cuentaFinancieraIdNueva: cambio.formaPago == FormaPago.tarjeta.name ? null : cambio.cuentaFinancieraId,
              deudaIdTarjetaNueva: cambio.formaPago == FormaPago.tarjeta.name ? cambio.deudaIdTarjeta : null,
              fecha: fecha,
              motivo: motivo,
              actorUsuarioId: actorUsuarioId,
              servicioId: servicioId,
              beneficiarioEgreso: beneficiarioEgreso,
              conceptoEgreso: 'Tiempo extra ${anterior.folio} — costo: ${cambio.concepto}',
              costoAdicionalId: costoRow.id,
            );
            await (_db.update(_db.tiempoExtraCostoAdicional)..where((t) => t.id.equals(costoRow.id))).write(
              TiempoExtraCostoAdicionalCompanion(egresoId: Value(origenCosto.egresoId), deudaId: Value(origenCosto.deudaId)),
            );

          case CorreccionCostoAdicionalQuitar():
            final costoAnterior = await (_db.select(_db.tiempoExtraCostoAdicional)
                  ..where((t) => t.id.equals(cambio.costoAdicionalId)))
                .getSingle();
            costosAntes['costo${cambio.costoAdicionalId}Eliminado'] = {
              'concepto': costoAnterior.concepto,
              'monto': costoAnterior.monto,
              'formaPago': costoAnterior.formaPago,
            };
            if (costoAnterior.egresoId != null) {
              await _egresoRepository.cancelar(egresoId: costoAnterior.egresoId!, motivo: motivo, actorUsuarioId: actorUsuarioId);
            } else if (costoAnterior.deudaId != null) {
              await _deudaRepository.revertirCargoCostoAdicional(
                deudaId: costoAnterior.deudaId!, costoAdicionalId: cambio.costoAdicionalId, motivo: motivo, actorUsuarioId: actorUsuarioId);
            }
            // Borrado lógico (nunca físico): la reversión recién
            // insertada arriba sigue referenciando este mismo
            // `costoAdicionalId` (`MovimientoDeuda.costoAdicionalId` es
            // `restrict`) — un `DELETE` aquí violaría esa FK. Ver el
            // doc comment de `TiempoExtraCostoAdicional.eliminado`.
            await (_db.update(_db.tiempoExtraCostoAdicional)..where((t) => t.id.equals(cambio.costoAdicionalId)))
                .write(const TiempoExtraCostoAdicionalCompanion(eliminado: Value(true)));
        }
      }

      if (costosAntes.isNotEmpty || costosDespues.isNotEmpty) {
        estadoAnterior['costos'] = costosAntes;
        estadoNuevo['costos'] = costosDespues;
      }

      await _registrarEvento(
        tiempoExtraId: tiempoExtraId,
        tipoEvento: 'corregido',
        observacion: motivo,
        actorUsuarioId: actorUsuarioId,
        estadoAnterior: jsonEncode(estadoAnterior),
        estadoNuevo: jsonEncode(estadoNuevo),
      );

      return (await obtenerPorId(tiempoExtraId))!;
    });
  }

  @override
  Future<ResumenEliminacionTiempoExtra> obtenerResumenEliminacionFisica(String tiempoExtraId) async {
    final actual = await obtenerPorId(tiempoExtraId);
    if (actual == null) return const ResumenEliminacionTiempoExtra(existe: false);

    if (actual.estatus != EstatusTiempoExtra.cancelado.name) {
      return const ResumenEliminacionTiempoExtra(
        existe: true,
        detalleBloqueo: 'Solo puede eliminarse físicamente una cobertura ya cancelada — cancélela primero.',
      );
    }

    final costos = await _listarTodosLosCostos(tiempoExtraId);
    final costoIds = [for (final c in costos) c.id];
    final bloqueoTarjeta = await _deudaRepository.detalleBloqueoEliminacionCargoTiempoExtra(
      tiempoExtraId: tiempoExtraId,
      costoAdicionalIds: costoIds,
    );
    if (bloqueoTarjeta != null) {
      return ResumenEliminacionTiempoExtra(existe: true, detalleBloqueo: bloqueoTarjeta);
    }

    return const ResumenEliminacionTiempoExtra(existe: true);
  }

  @override
  Future<EliminarTiempoExtraFisicamenteResultado> eliminarFisicamente({
    required String tiempoExtraId,
    required String motivo,
    String? detalle,
    String? actorUsuarioId,
  }) async {
    final actual = await obtenerPorId(tiempoExtraId);
    if (actual == null) return EliminarTiempoExtraFisicamenteNoExiste();

    final resumen = await obtenerResumenEliminacionFisica(tiempoExtraId);
    if (resumen.bloqueado) {
      return EliminarTiempoExtraFisicamenteTieneDependencias(resumen.detalleBloqueo!);
    }

    await _db.transaction(() async {
      final costos = await _listarTodosLosCostos(tiempoExtraId);
      final eventos = await listarEventos(tiempoExtraId);
      final costoIds = [for (final c in costos) c.id];

      final egresoIds = [
        if (actual.egresoId != null) actual.egresoId!,
        for (final c in costos)
          if (c.egresoId != null) c.egresoId!,
      ];
      final egresos = <EgresoData>[];
      for (final id in egresoIds) {
        final e = await (_db.select(_db.egreso)..where((t) => t.id.equals(id))).getSingleOrNull();
        if (e != null) egresos.add(e);
      }

      final movimientosDeuda = await (_db.select(_db.movimientoDeuda)
            ..where((t) => t.tiempoExtraId.equals(tiempoExtraId) | (costoIds.isEmpty ? t.costoAdicionalId.equals(-1) : t.costoAdicionalId.isIn(costoIds))))
          .get();

      final snapshot = <String, Object?>{
        'tiempoExtra': actual.toJson(),
        'costosAdicionales': [for (final c in costos) c.toJson()],
        'eventos': [for (final e in eventos) e.toJson()],
        'egresos': [for (final e in egresos) e.toJson()],
        'movimientosDeuda': [for (final m in movimientosDeuda) m.toJson()],
      };

      await _db.into(_db.eliminacionFisicaEvento).insert(
            EliminacionFisicaEventoCompanion.insert(
              tipoEntidad: 'tiempoExtra',
              entidadIdOriginal: tiempoExtraId,
              fechaHora: DateTime.now(),
              motivo: motivo,
              motivoCodigo: Value(motivo),
              detalle: Value(detalle),
              snapshotJson: jsonEncode(snapshot),
              actorUsuarioId: Value(actorUsuarioId),
            ),
          );

      // 1. MovimientoDeuda (restrict) — antes de borrar TiempoExtra/costos.
      await _deudaRepository.eliminarCargoTiempoExtraFisicamente(tiempoExtraId: tiempoExtraId, costoAdicionalIds: costoIds);

      // 2. TiempoExtra — cascada borra TiempoExtraCostoAdicional/TiempoExtraEvento.
      await (_db.delete(_db.tiempoExtra)..where((t) => t.id.equals(tiempoExtraId))).go();

      // 3. Egresos propios — después, `restrict` hacia Egreso.
      for (final egreso in egresos) {
        await (_db.delete(_db.egreso)..where((t) => t.id.equals(egreso.id))).go();
      }
    });

    return EliminarTiempoExtraFisicamenteExitoso();
  }
}
