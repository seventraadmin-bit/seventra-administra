import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/finanzas/domain/repositories/deuda_repository.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/egreso_repository.dart';

import '../../domain/repositories/recarga_linea_telefonica_repository.dart';
import '../tables/recarga_linea_telefonica_table.dart';

class RecargaLineaTelefonicaRepositoryImpl implements RecargaLineaTelefonicaRepository {
  RecargaLineaTelefonicaRepositoryImpl(
    this._db,
    this._egresoRepository,
    this._deudaRepository,
    this._codigoSecuencia,
  );

  final AppDatabase _db;
  final EgresoRepository _egresoRepository;
  final DeudaRepository _deudaRepository;
  final CodigoSecuenciaService _codigoSecuencia;

  /// Concepto legible del Egreso automático — "Recarga TEL-000002 ·
  /// 7225562629". Es para que un humano lo reconozca en Finanzas; la
  /// RELACIÓN real es la FK `RecargaLineaTelefonica.egresoId`, nunca
  /// este texto.
  Future<String> _conceptoEgreso(String lineaTelefonicaId) async {
    final linea =
        await (_db.select(_db.lineaTelefonica)..where((t) => t.id.equals(lineaTelefonicaId))).getSingleOrNull();
    if (linea == null) return 'Recarga de línea telefónica';
    final numero = linea.numero;
    return numero == null || numero.isEmpty
        ? 'Recarga ${linea.codigo}'
        : 'Recarga ${linea.codigo} · $numero';
  }

  /// El Egreso de una recarga se atribuye al Servicio al que la línea
  /// estaba asignada en ese momento, si lo estaba. Una línea asignada a
  /// un Empleado —o sin asignar— produce un Egreso sin Servicio, que es
  /// un estado honesto ya existente.
  Future<String?> _servicioDeLineaEnFecha(String lineaTelefonicaId, DateTime fecha) async {
    final asignacion = await (_db.select(_db.asignacionLineaTelefonica)
          ..where((t) =>
              t.lineaTelefonicaId.equals(lineaTelefonicaId) &
              t.fechaInicio.isSmallerOrEqualValue(fecha) &
              (t.fechaTermino.isNull() | t.fechaTermino.isBiggerOrEqualValue(fecha)))
          ..limit(1))
        .getSingleOrNull();
    return asignacion?.servicioId;
  }

  /// Una recarga anulada (schemaVersion 81) NO cuenta en ningún
  /// totalizador del módulo: su dinero nunca se gastó. Sí se conserva en
  /// `listarPorLinea`, que es el HISTORIAL — ahí debe verse, marcada.
  ///
  /// Este es exactamente el bug que apareció en Vehículos al introducir
  /// la anulación: la pantalla del activo seguía sumando lo anulado. Por
  /// eso el filtro vive en UN solo predicado y todos los totalizadores
  /// lo usan, en vez de repetir la condición en cada suma.
  static bool _vigente(RecargaLineaTelefonicaData r) =>
      r.estatus != EstatusRecargaLineaTelefonica.cancelada.name;

  @override
  Future<RecargaLineaTelefonicaData?> obtenerPorId(String recargaLineaTelefonicaId) {
    return (_db.select(_db.recargaLineaTelefonica)..where((t) => t.id.equals(recargaLineaTelefonicaId))).getSingleOrNull();
  }

  @override
  Future<List<String>> listarEgresoIds() async {
    final filas = await (_db.select(_db.recargaLineaTelefonica)..where((t) => t.egresoId.isNotNull())).get();
    return [for (final r in filas) r.egresoId!];
  }

  @override
  Future<RecargaLineaTelefonicaData?> obtenerPorEgresoId(String egresoId) {
    return (_db.select(_db.recargaLineaTelefonica)..where((t) => t.egresoId.equals(egresoId))).getSingleOrNull();
  }

  @override
  Future<String?> cuentaDeEgreso(String egresoId) async {
    final egreso = await (_db.select(_db.egreso)..where((t) => t.id.equals(egresoId))).getSingleOrNull();
    return egreso?.cuentaFinancieraId;
  }

  @override
  Future<String?> nombreCuentaDeEgreso(String egresoId) async {
    final egreso = await (_db.select(_db.egreso)..where((t) => t.id.equals(egresoId))).getSingleOrNull();
    final cuentaId = egreso?.cuentaFinancieraId;
    if (cuentaId == null) return null;
    final cuenta = await (_db.select(_db.cuentaFinanciera)..where((t) => t.id.equals(cuentaId))).getSingleOrNull();
    return cuenta?.nombre;
  }

  @override
  Future<List<RecargaLineaTelefonicaData>> listarPorLinea(String lineaTelefonicaId) {
    return (_db.select(_db.recargaLineaTelefonica)
          ..where((t) => t.lineaTelefonicaId.equals(lineaTelefonicaId))
          ..orderBy([(t) => OrderingTerm.desc(t.fecha)]))
        .get();
  }

  @override
  Future<int> totalPorLinea(String lineaTelefonicaId) async {
    final recargas = await listarPorLinea(lineaTelefonicaId);
    return recargas.where(_vigente).fold<int>(0, (suma, r) => suma + r.importe);
  }

  @override
  Future<Map<String, RecargaLineaTelefonicaData>> obtenerUltimasPorTodasLasLineas() async {
    final todas = await (_db.select(_db.recargaLineaTelefonica)..orderBy([(t) => OrderingTerm.desc(t.fecha)])).get();
    final ultimaPorLinea = <String, RecargaLineaTelefonicaData>{};
    // "Última recarga" es la última que SÍ ocurrió: una anulada nunca
    // debe presentarse como el estado actual de la línea.
    for (final r in todas.where(_vigente)) {
      ultimaPorLinea.putIfAbsent(r.lineaTelefonicaId, () => r);
    }
    return ultimaPorLinea;
  }

  Future<List<AsignacionLineaTelefonicaData>> _asignacionesTodas() {
    return _db.select(_db.asignacionLineaTelefonica).get();
  }

  /// Entre las asignaciones vigentes en la fecha de [recarga] para su
  /// línea, la más reciente por `fechaInicio` — desempate para el día
  /// exacto en que una asignación se cierra y otra se abre a la vez
  /// (mismo día en ambos extremos, ver `AsignacionLineaTelefonicaRepositoryImpl.cambiarResponsable`).
  AsignacionLineaTelefonicaData? _resolverDestino(
    RecargaLineaTelefonicaData recarga,
    List<AsignacionLineaTelefonicaData> asignaciones,
  ) {
    final candidatas = asignaciones.where(
      (a) =>
          a.lineaTelefonicaId == recarga.lineaTelefonicaId &&
          !a.fechaInicio.isAfter(recarga.fecha) &&
          (a.fechaTermino == null || !a.fechaTermino!.isBefore(recarga.fecha)),
    );
    if (candidatas.isEmpty) return null;
    return candidatas.reduce((a, b) => a.fechaInicio.isAfter(b.fechaInicio) ? a : b);
  }

  @override
  Future<DestinoHistoricoRecarga?> obtenerDestinoHistorico(String recargaLineaTelefonicaId) async {
    final recarga = await obtenerPorId(recargaLineaTelefonicaId);
    if (recarga == null) return null;
    final asignaciones = await _asignacionesTodas();
    final destino = _resolverDestino(recarga, asignaciones);
    if (destino == null) return null;
    return DestinoHistoricoRecarga(empleadoId: destino.empleadoId, servicioId: destino.servicioId);
  }

  /// Base de TODOS los totales por rango (empleado, servicio, general y
  /// el desglose de Reportes) — excluye lo anulado en la propia
  /// consulta, así ningún llamador puede olvidarlo.
  Future<List<RecargaLineaTelefonicaData>> _listarConRango({DateTime? desde, DateTime? hasta}) {
    final query = _db.select(_db.recargaLineaTelefonica)
      ..where((t) => t.estatus.equals(EstatusRecargaLineaTelefonica.cancelada.name).not());
    if (desde != null) query.where((t) => t.fecha.isBiggerOrEqualValue(desde));
    if (hasta != null) query.where((t) => t.fecha.isSmallerOrEqualValue(hasta));
    return query.get();
  }

  @override
  Future<int> totalPorEmpleado(String empleadoId, {DateTime? desde, DateTime? hasta}) async {
    final recargas = await _listarConRango(desde: desde, hasta: hasta);
    final asignaciones = await _asignacionesTodas();
    var total = 0;
    for (final r in recargas) {
      final destino = _resolverDestino(r, asignaciones);
      if (destino?.empleadoId == empleadoId) total += r.importe;
    }
    return total;
  }

  @override
  Future<int> totalPorServicio(String servicioId, {DateTime? desde, DateTime? hasta}) async {
    final recargas = await _listarConRango(desde: desde, hasta: hasta);
    final asignaciones = await _asignacionesTodas();
    var total = 0;
    for (final r in recargas) {
      final destino = _resolverDestino(r, asignaciones);
      if (destino?.servicioId == servicioId) total += r.importe;
    }
    return total;
  }

  @override
  Future<int> totalPorRango({DateTime? desde, DateTime? hasta}) async {
    final recargas = await _listarConRango(desde: desde, hasta: hasta);
    return recargas.fold<int>(0, (suma, r) => suma + r.importe);
  }

  @override
  Future<List<({RecargaLineaTelefonicaData recarga, DestinoHistoricoRecarga? destino})>> listarConDestinoEnRango({
    DateTime? desde,
    DateTime? hasta,
  }) async {
    final recargas = await _listarConRango(desde: desde, hasta: hasta);
    final asignaciones = await _asignacionesTodas();
    return [
      for (final r in recargas)
        (
          recarga: r,
          destino: switch (_resolverDestino(r, asignaciones)) {
            null => null,
            final d => DestinoHistoricoRecarga(empleadoId: d.empleadoId, servicioId: d.servicioId),
          },
        ),
    ];
  }

  @override
  Future<RecargaLineaTelefonicaData> registrar({
    required String lineaTelefonicaId,
    required DateTime fecha,
    required int importe,
    required String formaPago,
    String? cuentaFinancieraId,
    String? deudaIdTarjeta,
    String? observaciones,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      var recarga = await _db.into(_db.recargaLineaTelefonica).insertReturning(
            RecargaLineaTelefonicaCompanion.insert(
              lineaTelefonicaId: lineaTelefonicaId,
              fecha: fecha,
              importe: importe,
              formaPago: Value(formaPago),
              observaciones: Value(observaciones),
              actorUsuarioId: Value(actorUsuarioId),
            ),
          );

      // Tarjeta → cargo a la deuda, JAMÁS un Egreso: la salida de banco
      // ocurre después, al pagar la tarjeta. Mismo criterio exacto que
      // Compra/TiempoExtra/Mantenimiento.
      if (deudaIdTarjeta != null) {
        await _deudaRepository.registrarCargoRecargaLineaTelefonica(
          deudaId: deudaIdTarjeta,
          recargaLineaTelefonicaId: recarga.id,
          monto: importe,
          fecha: fecha,
          actorUsuarioId: actorUsuarioId,
        );
        recarga = await (_db.update(_db.recargaLineaTelefonica)..where((t) => t.id.equals(recarga.id)))
            .writeReturning(RecargaLineaTelefonicaCompanion(deudaId: Value(deudaIdTarjeta)))
            .then((filas) => filas.single);
      } else {
        final folioEgreso = await _codigoSecuencia.siguienteCodigo('egreso');
        final egreso = await _egresoRepository.crear(
          folioEgreso: folioEgreso,
          monto: importe,
          fecha: fecha,
          servicioId: await _servicioDeLineaEnFecha(lineaTelefonicaId, fecha),
          cuentaFinancieraId: cuentaFinancieraId,
          formaPago: formaPago,
          concepto: await _conceptoEgreso(lineaTelefonicaId),
          actorUsuarioId: actorUsuarioId,
        );
        recarga = await (_db.update(_db.recargaLineaTelefonica)..where((t) => t.id.equals(recarga.id)))
            .writeReturning(RecargaLineaTelefonicaCompanion(egresoId: Value(egreso.id)))
            .then((filas) => filas.single);
      }

      return recarga;
    });
  }

  /// Resuelve la transición de origen financiero de una recarga que se
  /// corrige, y devuelve el par (egresoId, deudaId) a escribir —
  /// mutuamente excluyente. Copia fiel del mecanismo de
  /// `TiempoExtraRepositoryImpl._aplicarTransicionOrigen`: mismas seis
  /// ramas, mismas decisiones.
  Future<({String? egresoId, String? deudaId})> _aplicarTransicionOrigen({
    required String recargaId,
    required String lineaTelefonicaId,
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
  }) async {
    final esNuevoTarjeta = formaPagoNueva == FormaPago.tarjeta.name;

    Future<EgresoData> crearEgresoNuevo() async {
      final folioEgreso = await _codigoSecuencia.siguienteCodigo('egreso');
      return _egresoRepository.crear(
        folioEgreso: folioEgreso,
        monto: montoNuevo,
        fecha: fecha,
        servicioId: await _servicioDeLineaEnFecha(lineaTelefonicaId, fecha),
        cuentaFinancieraId: cuentaFinancieraIdNueva,
        formaPago: formaPagoNueva,
        concepto: await _conceptoEgreso(lineaTelefonicaId),
        actorUsuarioId: actorUsuarioId,
      );
    }

    // Cuenta → Cuenta (misma o distinta): sobreescribe el Egreso
    // existente. El saldo de la cuenta se deriva sumando `Egreso.monto`
    // al leer, así que esto ya mueve el efecto sin duplicar ni dejar
    // residuo.
    if (egresoIdAnterior != null && !esNuevoTarjeta) {
      await _egresoRepository.corregir(
        egresoId: egresoIdAnterior,
        cuentaFinancieraId: cuentaFinancieraIdNueva,
        limpiarCuentaFinancieraId: cuentaFinancieraIdNueva == null,
        motivo: motivo,
        actorUsuarioId: actorUsuarioId,
      );
      if (montoNuevo != montoAnterior) {
        await _egresoRepository.corregirMonto(
          egresoId: egresoIdAnterior,
          nuevoMonto: montoNuevo,
          motivo: motivo,
          actorUsuarioId: actorUsuarioId,
        );
      }
      return (egresoId: egresoIdAnterior, deudaId: null);
    }

    // TDC → TDC.
    if (deudaIdAnterior != null && esNuevoTarjeta) {
      if (deudaIdTarjetaNueva == deudaIdAnterior) {
        // Misma tarjeta: ajuste-delta, nunca reescribe el cargo original.
        final delta = montoNuevo - montoAnterior;
        if (delta != 0) {
          await _deudaRepository.registrarAjusteCargoRecargaLineaTelefonica(
            deudaId: deudaIdAnterior,
            recargaLineaTelefonicaId: recargaId,
            deltaImporte: delta,
            motivo: motivo,
            actorUsuarioId: actorUsuarioId,
          );
        }
        return (egresoId: null, deudaId: deudaIdAnterior);
      }
      // Tarjeta distinta: revierte el cargo completo de la vieja y
      // aplica uno completo en la nueva.
      await _deudaRepository.revertirCargoRecargaLineaTelefonica(
        deudaId: deudaIdAnterior,
        recargaLineaTelefonicaId: recargaId,
        motivo: motivo,
        actorUsuarioId: actorUsuarioId,
      );
      await _deudaRepository.registrarCargoRecargaLineaTelefonica(
        deudaId: deudaIdTarjetaNueva!,
        recargaLineaTelefonicaId: recargaId,
        monto: montoNuevo,
        fecha: fecha,
        actorUsuarioId: actorUsuarioId,
      );
      return (egresoId: null, deudaId: deudaIdTarjetaNueva);
    }

    // Cuenta → TDC: cancela el Egreso viejo y aplica un cargo nuevo.
    if (egresoIdAnterior != null && esNuevoTarjeta) {
      await _egresoRepository.cancelar(
        egresoId: egresoIdAnterior,
        motivo: motivo,
        actorUsuarioId: actorUsuarioId,
      );
      await _deudaRepository.registrarCargoRecargaLineaTelefonica(
        deudaId: deudaIdTarjetaNueva!,
        recargaLineaTelefonicaId: recargaId,
        monto: montoNuevo,
        fecha: fecha,
        actorUsuarioId: actorUsuarioId,
      );
      return (egresoId: null, deudaId: deudaIdTarjetaNueva);
    }

    // TDC → Cuenta: revierte el cargo completo y crea un Egreso nuevo.
    if (deudaIdAnterior != null && !esNuevoTarjeta) {
      await _deudaRepository.revertirCargoRecargaLineaTelefonica(
        deudaId: deudaIdAnterior,
        recargaLineaTelefonicaId: recargaId,
        motivo: motivo,
        actorUsuarioId: actorUsuarioId,
      );
      final egreso = await crearEgresoNuevo();
      return (egresoId: egreso.id, deudaId: null);
    }

    // Sin origen anterior: es una recarga LEGACY (anterior a v86) que
    // se está corrigiendo. Se trata como un alta para este ítem — a
    // partir de ahí ya tiene trazabilidad financiera real.
    if (esNuevoTarjeta) {
      await _deudaRepository.registrarCargoRecargaLineaTelefonica(
        deudaId: deudaIdTarjetaNueva!,
        recargaLineaTelefonicaId: recargaId,
        monto: montoNuevo,
        fecha: fecha,
        actorUsuarioId: actorUsuarioId,
      );
      return (egresoId: null, deudaId: deudaIdTarjetaNueva);
    }
    final egreso = await crearEgresoNuevo();
    return (egresoId: egreso.id, deudaId: null);
  }

  @override
  Future<RecargaLineaTelefonicaData> corregir({
    required String recargaLineaTelefonicaId,
    DateTime? fecha,
    int? importe,
    required String formaPago,
    String? cuentaFinancieraId,
    String? deudaIdTarjeta,
    String? observaciones,
    bool limpiarObservaciones = false,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final anterior =
          await (_db.select(_db.recargaLineaTelefonica)..where((t) => t.id.equals(recargaLineaTelefonicaId)))
              .getSingle();

      final fechaFinal = fecha ?? anterior.fecha;
      final importeFinal = importe ?? anterior.importe;

      final origen = await _aplicarTransicionOrigen(
        recargaId: recargaLineaTelefonicaId,
        lineaTelefonicaId: anterior.lineaTelefonicaId,
        egresoIdAnterior: anterior.egresoId,
        deudaIdAnterior: anterior.deudaId,
        montoAnterior: anterior.importe,
        formaPagoNueva: formaPago,
        montoNuevo: importeFinal,
        cuentaFinancieraIdNueva: cuentaFinancieraId,
        deudaIdTarjetaNueva: deudaIdTarjeta,
        fecha: fechaFinal,
        motivo: motivo,
        actorUsuarioId: actorUsuarioId,
      );

      await (_db.update(_db.recargaLineaTelefonica)..where((t) => t.id.equals(recargaLineaTelefonicaId))).write(
        RecargaLineaTelefonicaCompanion(
          fecha: Value(fechaFinal),
          importe: Value(importeFinal),
          formaPago: Value(formaPago),
          egresoId: Value(origen.egresoId),
          deudaId: Value(origen.deudaId),
          observaciones: limpiarObservaciones
              ? const Value(null)
              : (observaciones == null ? const Value.absent() : Value(observaciones)),
          updatedAt: Value(DateTime.now()),
        ),
      );
      return (_db.select(_db.recargaLineaTelefonica)..where((t) => t.id.equals(recargaLineaTelefonicaId)))
          .getSingle();
    });
  }

  @override
  Future<RecargaLineaTelefonicaData> cancelar({
    required String recargaLineaTelefonicaId,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final actual =
          await (_db.select(_db.recargaLineaTelefonica)..where((t) => t.id.equals(recargaLineaTelefonicaId)))
              .getSingle();

      await (_db.update(_db.recargaLineaTelefonica)..where((t) => t.id.equals(recargaLineaTelefonicaId))).write(
        RecargaLineaTelefonicaCompanion(
          estatus: Value(EstatusRecargaLineaTelefonica.cancelada.name),
          motivoCancelacion: Value(motivo),
          updatedAt: Value(DateTime.now()),
        ),
      );

      // Exactamente uno de los dos, según cómo se registró. Una recarga
      // LEGACY (sin origen financiero) no toca ningún balance: sólo
      // cambia de estado.
      if (actual.egresoId != null) {
        await _egresoRepository.cancelar(
          egresoId: actual.egresoId!,
          motivo: motivo,
          actorUsuarioId: actorUsuarioId,
        );
      } else if (actual.deudaId != null) {
        await _deudaRepository.revertirCargoRecargaLineaTelefonica(
          deudaId: actual.deudaId!,
          recargaLineaTelefonicaId: recargaLineaTelefonicaId,
          motivo: motivo,
          actorUsuarioId: actorUsuarioId,
        );
      }

      return (_db.select(_db.recargaLineaTelefonica)..where((t) => t.id.equals(recargaLineaTelefonicaId)))
          .getSingle();
    });
  }

  @override
  Future<AttachmentData> adjuntarComprobante({
    required String recargaLineaTelefonicaId,
    required String originalFileName,
    required String storedFileName,
    required String path,
    required String mimeType,
    required int sizeBytes,
  }) {
    return _db.transaction(() async {
      final adjunto = await _db.into(_db.attachment).insertReturning(
            AttachmentCompanion.insert(
              id: const Uuid().v4(),
              originalFileName: originalFileName,
              storedFileName: storedFileName,
              path: path,
              mimeType: mimeType,
              sizeBytes: sizeBytes,
            ),
          );
      await _db.into(_db.recargaLineaTelefonicaAttachment).insert(
            RecargaLineaTelefonicaAttachmentCompanion.insert(
              attachmentId: adjunto.id,
              recargaLineaTelefonicaId: recargaLineaTelefonicaId,
            ),
          );
      return adjunto;
    });
  }
}
