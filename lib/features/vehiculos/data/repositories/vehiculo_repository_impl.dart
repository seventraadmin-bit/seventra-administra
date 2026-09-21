import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:riseg_one/core/auditoria/diff_evento.dart';
import 'package:riseg_one/core/database/app_database.dart';

import '../tables/vehiculo_table.dart';

import '../../domain/repositories/asignacion_vehiculo_repository.dart';
import '../../domain/repositories/vehiculo_repository.dart';
import '../../domain/usecases/eliminar_vehiculo_fisicamente_usecase.dart';

class VehiculoRepositoryImpl implements VehiculoRepository {
  VehiculoRepositoryImpl(this._db, this._asignacionVehiculoRepository);

  final AppDatabase _db;

  /// Repositorio compone repositorio (Etapa 8B) — mismo criterio que
  /// `EmpleadoRepositoryImpl` con `AsignacionServicioRepository` (5D):
  /// `darDeBaja` necesita cerrar la asignación vigente del Vehículo (si
  /// existe) en la misma transacción que la baja misma.
  final AsignacionVehiculoRepository _asignacionVehiculoRepository;

  @override
  Future<VehiculoData?> obtenerPorId(String id) {
    return (_db.select(_db.vehiculo)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  @override
  Future<VehiculoData?> obtenerPorPlacas(String placas) {
    return (_db.select(_db.vehiculo)..where((t) => t.placas.equals(placas))).getSingleOrNull();
  }

  @override
  Future<VehiculoData?> obtenerPorVin(String vin) {
    return (_db.select(_db.vehiculo)..where((t) => t.vin.equals(vin))).getSingleOrNull();
  }

  @override
  Future<List<VehiculoData>> listar({bool soloActivos = true}) {
    final query = _db.select(_db.vehiculo);
    if (soloActivos) query.where((t) => t.cicloVidaRegistro.equals('activo'));
    query.orderBy([(t) => OrderingTerm.asc(t.marca), (t) => OrderingTerm.asc(t.modelo)]);
    return query.get();
  }

  @override
  Future<VehiculoData> crear({
    required String codigo,
    required String marca,
    required String modelo,
    int? anio,
    String? color,
    String? placas,
    String? vin,
    String? numeroMotor,
    required String tipoVehiculo,
    DateTime? fechaAdquisicion,
    int? costoAdquisicion,
    String? observaciones,
  }) {
    return _db.into(_db.vehiculo).insertReturning(
          VehiculoCompanion.insert(
            codigo: codigo,
            marca: marca,
            modelo: modelo,
            anio: Value(anio),
            color: Value(color),
            placas: Value(placas),
            vin: Value(vin),
            numeroMotor: Value(numeroMotor),
            tipoVehiculo: tipoVehiculo,
            fechaAdquisicion: Value(fechaAdquisicion),
            costoAdquisicion: Value(costoAdquisicion),
            observaciones: Value(observaciones),
          ),
        );
  }

  @override
  Future<VehiculoData> corregir({
    required String vehiculoId,
    String? marca,
    String? modelo,
    int? anio,
    String? color,
    String? placas,
    String? vin,
    String? numeroMotor,
    String? tipoVehiculo,
    DateTime? fechaAdquisicion,
    int? costoAdquisicion,
    String? observaciones,
    bool limpiarAnio = false,
    bool limpiarColor = false,
    bool limpiarPlacas = false,
    bool limpiarVin = false,
    bool limpiarNumeroMotor = false,
    bool limpiarFechaAdquisicion = false,
    bool limpiarCostoAdquisicion = false,
    bool limpiarObservaciones = false,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      // Estado ANTES — el gap P0 que cierra la schemaVersion 80: hasta
      // esta etapa se podían cambiar placas, VIN, número de motor y
      // costo de adquisición sin dejar rastro de quién ni por qué.
      final antes = await (_db.select(_db.vehiculo)..where((t) => t.id.equals(vehiculoId))).getSingle();

      await (_db.update(_db.vehiculo)..where((t) => t.id.equals(vehiculoId))).write(
        VehiculoCompanion(
          marca: marca == null ? const Value.absent() : Value(marca),
          modelo: modelo == null ? const Value.absent() : Value(modelo),
          anio: limpiarAnio ? const Value(null) : (anio == null ? const Value.absent() : Value(anio)),
          color: limpiarColor ? const Value(null) : (color == null ? const Value.absent() : Value(color)),
          placas: limpiarPlacas ? const Value(null) : (placas == null ? const Value.absent() : Value(placas)),
          vin: limpiarVin ? const Value(null) : (vin == null ? const Value.absent() : Value(vin)),
          numeroMotor: limpiarNumeroMotor
              ? const Value(null)
              : (numeroMotor == null ? const Value.absent() : Value(numeroMotor)),
          tipoVehiculo: tipoVehiculo == null ? const Value.absent() : Value(tipoVehiculo),
          fechaAdquisicion: limpiarFechaAdquisicion
              ? const Value(null)
              : (fechaAdquisicion == null ? const Value.absent() : Value(fechaAdquisicion)),
          costoAdquisicion: limpiarCostoAdquisicion
              ? const Value(null)
              : (costoAdquisicion == null ? const Value.absent() : Value(costoAdquisicion)),
          observaciones: limpiarObservaciones
              ? const Value(null)
              : (observaciones == null ? const Value.absent() : Value(observaciones)),
          updatedAt: Value(DateTime.now()),
        ),
      );

      final despues = await (_db.select(_db.vehiculo)..where((t) => t.id.equals(vehiculoId))).getSingle();

      // Solo los campos REALMENTE modificados, nunca un snapshot
      // completo — `DiffEvento`, el mismo helper de Compra/Pagos/Nómina.
      final diff = DiffEvento()
        ..anotar('marca', antes.marca, despues.marca)
        ..anotar('modelo', antes.modelo, despues.modelo)
        ..anotar('anio', antes.anio, despues.anio)
        ..anotar('color', antes.color, despues.color)
        ..anotar('placas', antes.placas, despues.placas)
        ..anotar('vin', antes.vin, despues.vin)
        ..anotar('numeroMotor', antes.numeroMotor, despues.numeroMotor)
        ..anotar('tipoVehiculo', antes.tipoVehiculo, despues.tipoVehiculo)
        ..anotar('fechaAdquisicion', antes.fechaAdquisicion, despues.fechaAdquisicion)
        ..anotar('costoAdquisicion', antes.costoAdquisicion, despues.costoAdquisicion)
        ..anotar('observaciones', antes.observaciones, despues.observaciones);

      // Una "corrección" que no cambió nada no es una corrección: no
      // ensucia el historial con un evento vacío.
      if (diff.hayCambios) {
        await registrarEvento(
          vehiculoId: vehiculoId,
          tipoEvento: TipoEventoVehiculo.corregido,
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
  Future<void> registrarEvento({
    required String vehiculoId,
    required TipoEventoVehiculo tipoEvento,
    String? observacion,
    String? estadoAnterior,
    String? estadoNuevo,
    String? datosRelevantes,
    String? actorUsuarioId,
  }) async {
    await _db.into(_db.vehiculoEvento).insert(
          VehiculoEventoCompanion.insert(
            vehiculoId: vehiculoId,
            fechaHora: DateTime.now(),
            tipoEvento: tipoEvento.name,
            observacion: Value(observacion),
            estadoAnterior: Value(estadoAnterior),
            estadoNuevo: Value(estadoNuevo),
            datosRelevantes: Value(datosRelevantes),
            actorUsuarioId: Value(actorUsuarioId),
          ),
        );
  }

  @override
  Future<List<VehiculoEventoData>> listarEventos(String vehiculoId) {
    return (_db.select(_db.vehiculoEvento)
          ..where((t) => t.vehiculoId.equals(vehiculoId))
          ..orderBy([(t) => OrderingTerm.desc(t.fechaHora), (t) => OrderingTerm.desc(t.id)]))
        .get();
  }

  @override
  Future<VehiculoData> cambiarEstatus({required String vehiculoId, required String estatus}) {
    return _db.transaction(() async {
      await (_db.update(_db.vehiculo)..where((t) => t.id.equals(vehiculoId))).write(
        VehiculoCompanion(estatus: Value(estatus), updatedAt: Value(DateTime.now())),
      );
      return (_db.select(_db.vehiculo)..where((t) => t.id.equals(vehiculoId))).getSingle();
    });
  }

  @override
  Future<VehiculoData> darDeBaja({
    required String vehiculoId,
    required DateTime fechaBaja,
    required String motivoBaja,
    String? observacionesBaja,
  }) {
    return _db.transaction(() async {
      await _asignacionVehiculoRepository.cerrarPorBajaVehiculo(vehiculoId: vehiculoId, fecha: fechaBaja);
      await (_db.update(_db.vehiculo)..where((t) => t.id.equals(vehiculoId))).write(
        VehiculoCompanion(
          estatus: const Value('baja'),
          fechaBaja: Value(fechaBaja),
          motivoBaja: Value(motivoBaja),
          observacionesBaja: Value(observacionesBaja),
          updatedAt: Value(DateTime.now()),
        ),
      );
      return (_db.select(_db.vehiculo)..where((t) => t.id.equals(vehiculoId))).getSingle();
    });
  }

  @override
  Future<AttachmentData> adjuntarDocumento({
    required String vehiculoId,
    String? categoria,
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
              categoria: Value(categoria),
              originalFileName: originalFileName,
              storedFileName: storedFileName,
              path: path,
              mimeType: mimeType,
              sizeBytes: sizeBytes,
            ),
          );
      await _db.into(_db.vehiculoAttachment).insert(
            VehiculoAttachmentCompanion.insert(attachmentId: adjunto.id, vehiculoId: vehiculoId),
          );
      return adjunto;
    });
  }

  @override
  Future<VehiculoData> actualizarFotografia({required String vehiculoId, required String attachmentId}) {
    return _db.transaction(() async {
      await (_db.update(_db.vehiculo)..where((t) => t.id.equals(vehiculoId))).write(
        VehiculoCompanion(fotografiaAttachmentId: Value(attachmentId), updatedAt: Value(DateTime.now())),
      );
      return (_db.select(_db.vehiculo)..where((t) => t.id.equals(vehiculoId))).getSingle();
    });
  }

  /// Eliminación física extraordinaria (Etapa 11D) — condiciones
  /// exactas acordadas con Marlon: elegible solo si el Vehículo nunca
  /// tuvo `AsignacionVehiculo`, `VehiculoDocumento`, `VehiculoKilometraje`,
  /// `VehiculoMantenimiento` ni ningún `VehiculoAttachment` (activo o
  /// archivado — una fotografía alguna vez subida ya es "uso real", no
  /// un simple error de captura). Todo — validación, snapshot,
  /// registro de auditoría y `DELETE` — ocurre en una sola transacción;
  /// nunca `CASCADE` sobre ninguna de esas tablas.
  @override
  Future<EliminarVehiculoFisicamenteResultado> eliminarFisicamente({
    required String vehiculoId,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final vehiculo = await (_db.select(_db.vehiculo)..where((t) => t.id.equals(vehiculoId))).getSingleOrNull();
      if (vehiculo == null) return EliminarVehiculoFisicamenteNoExiste();

      final asignaciones = await (_db.select(_db.asignacionVehiculo)..where((t) => t.vehiculoId.equals(vehiculoId))).get();
      if (asignaciones.isNotEmpty) {
        return EliminarVehiculoFisicamenteTieneDependencias('Tiene ${asignaciones.length} asignación(es) registrada(s).');
      }

      final documentos = await (_db.select(_db.vehiculoDocumento)..where((t) => t.vehiculoId.equals(vehiculoId))).get();
      if (documentos.isNotEmpty) {
        return EliminarVehiculoFisicamenteTieneDependencias('Tiene ${documentos.length} documento(s) registrado(s).');
      }

      final kilometrajes =
          await (_db.select(_db.vehiculoKilometraje)..where((t) => t.vehiculoId.equals(vehiculoId))).get();
      if (kilometrajes.isNotEmpty) {
        return EliminarVehiculoFisicamenteTieneDependencias(
          'Tiene ${kilometrajes.length} lectura(s) de kilometraje registrada(s).',
        );
      }

      final mantenimientos =
          await (_db.select(_db.vehiculoMantenimiento)..where((t) => t.vehiculoId.equals(vehiculoId))).get();
      if (mantenimientos.isNotEmpty) {
        return EliminarVehiculoFisicamenteTieneDependencias(
          'Tiene ${mantenimientos.length} mantenimiento(s)/incidencia(s) registrado(s).',
        );
      }

      final adjuntos = await (_db.select(_db.vehiculoAttachment)..where((t) => t.vehiculoId.equals(vehiculoId))).get();
      if (adjuntos.isNotEmpty || vehiculo.fotografiaAttachmentId != null) {
        return EliminarVehiculoFisicamenteTieneDependencias('Tiene una fotografía u otro adjunto registrado.');
      }

      await _db.into(_db.eliminacionFisicaEvento).insert(
            EliminacionFisicaEventoCompanion.insert(
              tipoEntidad: 'vehiculo',
              entidadIdOriginal: vehiculoId,
              fechaHora: DateTime.now(),
              motivo: motivo,
              snapshotJson: jsonEncode(vehiculo.toJson()),
              actorUsuarioId: Value(actorUsuarioId),
            ),
          );
      await (_db.delete(_db.vehiculo)..where((t) => t.id.equals(vehiculoId))).go();

      return EliminarVehiculoFisicamenteExitoso();
    });
  }
}
