import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';
import 'package:riseg_one/core/database/tables/direccion_table.dart';
import 'package:riseg_one/features/organizacion/domain/shared/direccion_input.dart';
import 'package:uuid/uuid.dart';

import '../../domain/repositories/empleado_repository.dart';
import '../tables/empleado_table.dart';

class EmpleadoRepositoryImpl implements EmpleadoRepository {
  EmpleadoRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<EmpleadoData?> obtenerPorId(String id) {
    return (_db.select(_db.empleado)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  @override
  Future<List<EmpleadoData>> listar({
    String? estatus,
    String? puestoId,
    String? empresaId,
    String? sucursalId,
  }) {
    final query = _db.select(_db.empleado)..where((t) => t.cicloVidaRegistro.equals(CicloVidaRegistro.activo.name));
    if (estatus != null) query.where((t) => t.estatus.equals(estatus));
    if (puestoId != null) query.where((t) => t.puestoId.equals(puestoId));
    if (empresaId != null) query.where((t) => t.empresaId.equals(empresaId));
    if (sucursalId != null) query.where((t) => t.sucursalId.equals(sucursalId));
    query.orderBy([(t) => OrderingTerm.asc(t.apellidoPaterno)]);
    return query.get();
  }

  @override
  Future<List<EmpleadoEventoData>> listarEventos(String empleadoId) {
    return (_db.select(_db.empleadoEvento)
          ..where((t) => t.empleadoId.equals(empleadoId))
          ..orderBy([(t) => OrderingTerm.asc(t.fechaHora)]))
        .get();
  }

  Future<void> _registrarEvento({
    required String empleadoId,
    required TipoEventoEmpleado tipoEvento,
    String? estadoAnterior,
    String? estadoNuevo,
    String? observacion,
    String? actor,
    Map<String, dynamic>? datosRelevantes,
  }) {
    return _db.into(_db.empleadoEvento).insert(
          EmpleadoEventoCompanion.insert(
            empleadoId: empleadoId,
            fechaHora: DateTime.now(),
            tipoEvento: tipoEvento.name,
            estadoAnterior: Value(estadoAnterior),
            estadoNuevo: Value(estadoNuevo),
            observacion: Value(observacion),
            actor: Value(actor),
            datosRelevantes: Value(datosRelevantes == null ? null : jsonEncode(datosRelevantes)),
          ),
        );
  }

  @override
  Future<EmpleadoData> crear(EmpleadoCompanion datos) {
    return _db.transaction(() async {
      final empleado = await _db.into(_db.empleado).insertReturning(datos);
      await _registrarEvento(
        empleadoId: empleado.id,
        tipoEvento: TipoEventoEmpleado.creado,
        estadoNuevo: empleado.estatus,
      );
      return empleado;
    });
  }

  @override
  Future<EmpleadoData> corregir({
    required String empleadoId,
    required EmpleadoCompanion cambios,
    required String motivo,
    String? actor,
  }) {
    return _db.transaction(() async {
      await (_db.update(_db.empleado)..where((t) => t.id.equals(empleadoId))).write(
        cambios.copyWith(updatedAt: Value(DateTime.now())),
      );
      final actualizado = await (_db.select(_db.empleado)..where((t) => t.id.equals(empleadoId))).getSingle();

      await _registrarEvento(
        empleadoId: empleadoId,
        tipoEvento: TipoEventoEmpleado.corregido,
        observacion: motivo,
        actor: actor,
      );
      return actualizado;
    });
  }

  @override
  Future<EmpleadoData> cambiarEstatus({
    required String empleadoId,
    required String nuevo,
    String? motivo,
    String? actor,
  }) {
    return _db.transaction(() async {
      final anterior = await (_db.select(_db.empleado)..where((t) => t.id.equals(empleadoId))).getSingle();

      await (_db.update(_db.empleado)..where((t) => t.id.equals(empleadoId))).write(
        EmpleadoCompanion(estatus: Value(nuevo), updatedAt: Value(DateTime.now())),
      );
      final actualizado = await (_db.select(_db.empleado)..where((t) => t.id.equals(empleadoId))).getSingle();

      await _registrarEvento(
        empleadoId: empleadoId,
        tipoEvento: TipoEventoEmpleado.cambioEstatus,
        estadoAnterior: anterior.estatus,
        estadoNuevo: nuevo,
        observacion: motivo,
        actor: actor,
      );
      return actualizado;
    });
  }

  @override
  Future<EmpleadoData> actualizarFotografia({
    required String empleadoId,
    required String attachmentId,
    String? actor,
  }) {
    return _db.transaction(() async {
      await (_db.update(_db.empleado)..where((t) => t.id.equals(empleadoId))).write(
        EmpleadoCompanion(fotografiaAttachmentId: Value(attachmentId), updatedAt: Value(DateTime.now())),
      );
      final actualizado = await (_db.select(_db.empleado)..where((t) => t.id.equals(empleadoId))).getSingle();

      await _registrarEvento(
        empleadoId: empleadoId,
        tipoEvento: TipoEventoEmpleado.fotografiaActualizada,
        actor: actor,
        datosRelevantes: {'attachmentId': attachmentId},
      );
      return actualizado;
    });
  }

  @override
  Future<DireccionData?> obtenerDomicilio(String empleadoId) {
    return (_db.select(_db.direccion)
          ..where((t) => t.empleadoId.equals(empleadoId) & t.cicloVidaRegistro.equals(CicloVidaRegistro.activo.name)))
        .getSingleOrNull();
  }

  /// Busca el domicilio de este Empleado sin importar
  /// `cicloVidaRegistro` — `empleadoId` tiene un `.unique()` real en
  /// `Direccion` (1:1), así que solo puede existir una fila por
  /// Empleado en toda su historia (mismo patrón que
  /// `EntidadFiscalRepositoryImpl._buscarDomicilioDeEntidadFiscal`).
  Future<DireccionData?> _buscarDomicilioDeEmpleado(String empleadoId) {
    return (_db.select(_db.direccion)..where((t) => t.empleadoId.equals(empleadoId))).getSingleOrNull();
  }

  @override
  Future<DireccionData?> guardarDomicilio(String empleadoId, DireccionInput? input, {String? actor}) async {
    final existente = await _buscarDomicilioDeEmpleado(empleadoId);

    if (input == null) {
      if (existente != null && existente.cicloVidaRegistro == CicloVidaRegistro.activo.name) {
        await (_db.update(_db.direccion)..where((t) => t.id.equals(existente.id))).write(
          DireccionCompanion(
            cicloVidaRegistro: Value(CicloVidaRegistro.archivado.name),
            updatedAt: Value(DateTime.now()),
          ),
        );
        await _registrarEvento(empleadoId: empleadoId, tipoEvento: TipoEventoEmpleado.domicilioActualizado, actor: actor);
      }
      return null;
    }

    final cambios = DireccionCompanion(
      cicloVidaRegistro: Value(CicloVidaRegistro.activo.name),
      calle: Value(input.calle),
      numeroExterior: Value(input.numeroExterior),
      numeroInterior: Value(input.numeroInterior),
      colonia: Value(input.colonia),
      municipioAlcaldia: Value(input.municipioAlcaldia),
      ciudadLocalidad: Value(input.ciudadLocalidad),
      estado: Value(input.estado),
      codigoPostal: Value(input.codigoPostal),
      pais: Value(input.pais),
      referencias: Value(input.referencias),
      updatedAt: Value(DateTime.now()),
    );

    final DireccionData resultado;
    if (existente != null) {
      // Reactiva (si venía archivado) y actualiza — nunca un segundo
      // `INSERT`, que chocaría con el `.unique()` de `empleadoId`.
      final actualizada = existente.copyWithCompanion(cambios);
      await _db.update(_db.direccion).replace(actualizada);
      resultado = actualizada;
    } else {
      resultado = await _db.into(_db.direccion).insertReturning(
            DireccionCompanion.insert(
              empleadoId: Value(empleadoId),
              tipoDireccion: TipoDireccion.domicilio.name,
              calle: input.calle,
              numeroExterior: input.numeroExterior,
              numeroInterior: Value(input.numeroInterior),
              colonia: input.colonia,
              municipioAlcaldia: input.municipioAlcaldia,
              ciudadLocalidad: Value(input.ciudadLocalidad),
              estado: input.estado,
              codigoPostal: input.codigoPostal,
              pais: Value(input.pais),
              referencias: Value(input.referencias),
            ),
          );
    }

    await _registrarEvento(empleadoId: empleadoId, tipoEvento: TipoEventoEmpleado.domicilioActualizado, actor: actor);
    return resultado;
  }

  @override
  Future<AttachmentData> adjuntarDocumento({
    required String empleadoId,
    required String categoria,
    required String originalFileName,
    required String storedFileName,
    required String path,
    required String mimeType,
    required int sizeBytes,
    String? actor,
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
      await _db.into(_db.empleadoAttachment).insert(
            EmpleadoAttachmentCompanion.insert(attachmentId: adjunto.id, empleadoId: empleadoId),
          );

      await _registrarEvento(
        empleadoId: empleadoId,
        tipoEvento: TipoEventoEmpleado.documentoAdjuntado,
        actor: actor,
        datosRelevantes: {'categoria': categoria, 'archivoNuevo': originalFileName, 'attachmentId': adjunto.id},
      );

      return adjunto;
    });
  }
}
