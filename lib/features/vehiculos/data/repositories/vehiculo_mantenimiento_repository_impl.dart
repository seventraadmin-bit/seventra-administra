import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/finanzas/domain/repositories/deuda_repository.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/egreso_repository.dart';

import '../../domain/repositories/vehiculo_mantenimiento_repository.dart';
import '../tables/vehiculo_kilometraje_table.dart';
import '../tables/vehiculo_mantenimiento_table.dart';

/// Mantenimiento/incidencia de un Vehículo, con su origen financiero
/// (schemaVersion 80).
///
/// Compone `EgresoRepository`/`DeudaRepository` exactamente igual que
/// `CompraRepositoryImpl` y `TiempoExtraRepositoryImpl` — nunca escribe
/// a mano en `egreso` ni en `movimiento_deuda`. El dinero de Vehículos
/// entra a Finanzas por la misma puerta que el de todos los demás
/// módulos.
class VehiculoMantenimientoRepositoryImpl implements VehiculoMantenimientoRepository {
  VehiculoMantenimientoRepositoryImpl(
    this._db, {
    EgresoRepository? egresoRepository,
    DeudaRepository? deudaRepository,
    CodigoSecuenciaService? codigoSecuencia,
  })  : _egresoRepository = egresoRepository ?? EgresoRepositoryImpl(_db),
        _deudaRepository = deudaRepository ?? DeudaRepositoryImpl(_db, EgresoRepositoryImpl(_db)),
        _codigoSecuencia = codigoSecuencia ?? CodigoSecuenciaService(_db);

  final AppDatabase _db;
  final EgresoRepository _egresoRepository;
  final DeudaRepository _deudaRepository;
  final CodigoSecuenciaService _codigoSecuencia;

  /// Concepto del Egreso automático — legible en Finanzas sin abrir el
  /// vehículo, mismo criterio que Compras/Tiempos Extra.
  String _conceptoEgreso(String tipo, String descripcion) => 'Vehículo — $tipo: $descripcion';

  /// Registra el cargo a TDC o crea el Egreso, según el origen. Nunca
  /// ambos: un gasto con tarjeta no toca el banco todavía.
  Future<void> _aplicarOrigen({
    required VehiculoMantenimientoData registro,
    required int costo,
    required String? cuentaFinancieraId,
    required String? deudaIdTarjeta,
    required String? actorUsuarioId,
  }) async {
    if (deudaIdTarjeta != null) {
      await _deudaRepository.registrarCargoMantenimientoVehiculo(
        deudaId: deudaIdTarjeta,
        vehiculoMantenimientoId: registro.id,
        monto: costo,
        fecha: registro.fecha,
        observaciones: _conceptoEgreso(registro.tipo, registro.descripcion),
        actorUsuarioId: actorUsuarioId,
      );
      await (_db.update(_db.vehiculoMantenimiento)..where((t) => t.id.equals(registro.id)))
          .write(VehiculoMantenimientoCompanion(deudaId: Value(deudaIdTarjeta)));
      return;
    }
    if (cuentaFinancieraId == null) return; // legacy: sin origen

    final egreso = await _egresoRepository.crear(
      folioEgreso: await _codigoSecuencia.siguienteCodigo('egreso'),
      monto: costo,
      fecha: registro.fecha,
      cuentaFinancieraId: cuentaFinancieraId,
      formaPago: FormaPago.transferencia.name,
      beneficiario: registro.tallerProveedor,
      concepto: _conceptoEgreso(registro.tipo, registro.descripcion),
      actorUsuarioId: actorUsuarioId,
    );
    await (_db.update(_db.vehiculoMantenimiento)..where((t) => t.id.equals(registro.id)))
        .write(VehiculoMantenimientoCompanion(egresoId: Value(egreso.id)));
  }

  /// Deshace el origen vigente — la mitad reutilizable de corregir y
  /// cancelar. Idempotente: si ya no hay origen, no hace nada.
  Future<void> _revertirOrigen({
    required VehiculoMantenimientoData actual,
    required String motivo,
    required String? actorUsuarioId,
  }) async {
    if (actual.egresoId != null) {
      await _egresoRepository.cancelarConOrigen(
        egresoId: actual.egresoId!,
        motivo: motivo,
        actorUsuarioId: actorUsuarioId,
      );
    } else if (actual.deudaId != null) {
      await _deudaRepository.revertirCargoMantenimientoVehiculo(
        deudaId: actual.deudaId!,
        vehiculoMantenimientoId: actual.id,
        motivo: motivo,
        actorUsuarioId: actorUsuarioId,
      );
    }
  }

  @override
  Future<VehiculoMantenimientoData?> obtenerPorId(String vehiculoMantenimientoId) {
    return (_db.select(_db.vehiculoMantenimiento)..where((t) => t.id.equals(vehiculoMantenimientoId)))
        .getSingleOrNull();
  }

  @override
  Future<VehiculoMantenimientoData?> obtenerPorEgresoId(String egresoId) {
    return (_db.select(_db.vehiculoMantenimiento)..where((t) => t.egresoId.equals(egresoId))).getSingleOrNull();
  }

  @override
  Future<List<String>> listarEgresoIds() async {
    final filas = await (_db.select(_db.vehiculoMantenimiento)..where((t) => t.egresoId.isNotNull())).get();
    return [for (final f in filas) f.egresoId!];
  }

  @override
  Future<List<VehiculoMantenimientoData>> listarPorVehiculo(String vehiculoId) {
    return (_db.select(_db.vehiculoMantenimiento)
          ..where((t) => t.vehiculoId.equals(vehiculoId))
          ..orderBy([(t) => OrderingTerm.desc(t.fecha), (t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  @override
  Future<List<VehiculoMantenimientoData>> listarTodos() {
    return _db.select(_db.vehiculoMantenimiento).get();
  }

  @override
  Future<VehiculoMantenimientoData> crear({
    required String vehiculoId,
    required DateTime fecha,
    int? kilometraje,
    required String tipo,
    required String descripcion,
    String? tallerProveedor,
    int? costo,
    DateTime? proximoMantenimientoFecha,
    int? proximoMantenimientoKilometraje,
    String? observaciones,
    String? cuentaFinancieraId,
    String? deudaIdTarjeta,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final registro = await _db.into(_db.vehiculoMantenimiento).insertReturning(
            VehiculoMantenimientoCompanion.insert(
              vehiculoId: vehiculoId,
              fecha: fecha,
              kilometraje: Value(kilometraje),
              tipo: tipo,
              descripcion: descripcion,
              tallerProveedor: Value(tallerProveedor),
              costo: Value(costo),
              proximoMantenimientoFecha: Value(proximoMantenimientoFecha),
              proximoMantenimientoKilometraje: Value(proximoMantenimientoKilometraje),
              observaciones: Value(observaciones),
              actorUsuarioId: Value(actorUsuarioId),
            ),
          );

      // El dinero entra a Finanzas por la misma puerta que Compras y
      // Tiempos Extra — dentro de la MISMA transacción, así que un fallo
      // aquí no deja el mantenimiento registrado sin su efecto
      // financiero (ni al revés).
      if (costo != null && costo > 0) {
        await _aplicarOrigen(
          registro: registro,
          costo: costo,
          cuentaFinancieraId: cuentaFinancieraId,
          deudaIdTarjeta: deudaIdTarjeta,
          actorUsuarioId: actorUsuarioId,
        );
      }

      // Repositorio compone la escritura al ledger de kilometraje
      // (Etapa 8B) directo, sin inyectar `VehiculoKilometrajeRepository`
      // solo para un insert — mismo criterio ya usado por
      // `AsignacionVehiculoRepositoryImpl._registrarKilometraje` (punto
      // 4: "no crear otra fuente paralela de kilometraje").
      if (kilometraje != null) {
        await _db.into(_db.vehiculoKilometraje).insert(
              VehiculoKilometrajeCompanion.insert(
                vehiculoId: vehiculoId,
                fecha: fecha,
                kilometraje: kilometraje,
                origen: OrigenKilometrajeVehiculo.mantenimiento.name,
              ),
            );
      }

      // Relee: `_aplicarOrigen` acaba de poblar `egresoId`/`deudaId`.
      return (await obtenerPorId(registro.id))!;
    });
  }

  @override
  Future<VehiculoMantenimientoData> corregir({
    required String vehiculoMantenimientoId,
    DateTime? fecha,
    String? tipo,
    String? descripcion,
    String? tallerProveedor,
    int? costo,
    bool limpiarCosto = false,
    DateTime? proximoMantenimientoFecha,
    int? proximoMantenimientoKilometraje,
    String? observaciones,
    String? cuentaFinancieraId,
    String? deudaIdTarjeta,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final actual = await obtenerPorId(vehiculoMantenimientoId);
      if (actual == null) throw StateError('Mantenimiento $vehiculoMantenimientoId no existe.');

      await (_db.update(_db.vehiculoMantenimiento)..where((t) => t.id.equals(vehiculoMantenimientoId))).write(
        VehiculoMantenimientoCompanion(
          fecha: fecha == null ? const Value.absent() : Value(fecha),
          tipo: tipo == null ? const Value.absent() : Value(tipo),
          descripcion: descripcion == null ? const Value.absent() : Value(descripcion),
          tallerProveedor: tallerProveedor == null ? const Value.absent() : Value(tallerProveedor),
          costo: limpiarCosto ? const Value(null) : (costo == null ? const Value.absent() : Value(costo)),
          proximoMantenimientoFecha:
              proximoMantenimientoFecha == null ? const Value.absent() : Value(proximoMantenimientoFecha),
          proximoMantenimientoKilometraje: proximoMantenimientoKilometraje == null
              ? const Value.absent()
              : Value(proximoMantenimientoKilometraje),
          observaciones: observaciones == null ? const Value.absent() : Value(observaciones),
          updatedAt: Value(DateTime.now()),
        ),
      );

      final actualizado = (await obtenerPorId(vehiculoMantenimientoId))!;
      final costoFinal = actualizado.costo ?? 0;

      // ¿Cambió el origen, el monto, o ambos? Se resuelve SIEMPRE igual:
      // revertir lo vigente y aplicar lo nuevo. Es una transición
      // completa, no un parche por caso — así las 8 combinaciones que
      // pidió Marlon (cuenta→misma, cuenta→otra, cuenta→TDC, TDC→cuenta,
      // TDC→misma, TDC→otra, ±monto, todo junto) usan un solo camino.
      //
      // La única optimización: si el origen NO cambió y sigue siendo la
      // misma tarjeta, se emite un ajuste por la diferencia en vez de
      // revertir y recargar — así el ledger de la TDC muestra la
      // corrección como tal, que es lo que hacen Compras y Tiempos
      // Extra.
      final mismaTarjeta =
          deudaIdTarjeta != null && actual.deudaId != null && actual.deudaId == deudaIdTarjeta;

      if (mismaTarjeta) {
        final netoActual = await _deudaRepository.netoAportadoPorMantenimientoVehiculo(
          deudaId: deudaIdTarjeta,
          vehiculoMantenimientoId: vehiculoMantenimientoId,
        );
        final delta = costoFinal - netoActual;
        if (delta != 0) {
          await _deudaRepository.registrarAjusteCargoMantenimientoVehiculo(
            deudaId: deudaIdTarjeta,
            vehiculoMantenimientoId: vehiculoMantenimientoId,
            deltaImporte: delta,
            motivo: motivo,
            actorUsuarioId: actorUsuarioId,
          );
        }
        return (await obtenerPorId(vehiculoMantenimientoId))!;
      }

      await _revertirOrigen(actual: actual, motivo: motivo, actorUsuarioId: actorUsuarioId);
      await (_db.update(_db.vehiculoMantenimiento)..where((t) => t.id.equals(vehiculoMantenimientoId)))
          .write(const VehiculoMantenimientoCompanion(egresoId: Value(null), deudaId: Value(null)));

      if (costoFinal > 0) {
        await _aplicarOrigen(
          registro: (await obtenerPorId(vehiculoMantenimientoId))!,
          costo: costoFinal,
          cuentaFinancieraId: cuentaFinancieraId,
          deudaIdTarjeta: deudaIdTarjeta,
          actorUsuarioId: actorUsuarioId,
        );
      }

      return (await obtenerPorId(vehiculoMantenimientoId))!;
    });
  }

  @override
  Future<VehiculoMantenimientoData> cancelar({
    required String vehiculoMantenimientoId,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final actual = await obtenerPorId(vehiculoMantenimientoId);
      if (actual == null) throw StateError('Mantenimiento $vehiculoMantenimientoId no existe.');

      // Segunda cancelación: no hace nada. `_revertirOrigen` ya es
      // idempotente por el lado de la TDC (neto 0 ⇒ no escribe), pero
      // cortar aquí evita incluso intentar cancelar un Egreso ya
      // cancelado.
      if (EstatusMantenimientoVehiculo.values.byName(actual.estatus) == EstatusMantenimientoVehiculo.cancelado) {
        return actual;
      }

      await _revertirOrigen(actual: actual, motivo: motivo, actorUsuarioId: actorUsuarioId);

      // El registro CONSERVA su `egresoId`/`deudaId`: son la evidencia
      // de qué se revirtió y hacia dónde. El Egreso queda `cancelado` y
      // el cargo de la TDC compensado con un `ajusteNegativo` — nunca se
      // borra nada.
      await (_db.update(_db.vehiculoMantenimiento)..where((t) => t.id.equals(vehiculoMantenimientoId))).write(
        VehiculoMantenimientoCompanion(
          estatus: Value(EstatusMantenimientoVehiculo.cancelado.name),
          motivoCancelacion: Value(motivo),
          updatedAt: Value(DateTime.now()),
        ),
      );

      return (await obtenerPorId(vehiculoMantenimientoId))!;
    });
  }

  @override
  Future<AttachmentData> adjuntarArchivo({
    required String vehiculoMantenimientoId,
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
      await _db.into(_db.vehiculoMantenimientoAttachment).insert(
            VehiculoMantenimientoAttachmentCompanion.insert(
              attachmentId: adjunto.id,
              vehiculoMantenimientoId: vehiculoMantenimientoId,
            ),
          );
      return adjunto;
    });
  }
}
