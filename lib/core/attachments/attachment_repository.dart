import 'package:drift/drift.dart';

import '../database/app_database.dart';

/// Acceso a `Attachment` — infraestructura compartida (Etapa 4A, arco
/// exclusivo migrado a tablas puente por dominio en la Etapa 5A; ver el
/// doc comment de `attachment_table.dart`), no un módulo de Documentos
/// propio. Sin métodos de eliminación física: el reemplazo archiva la
/// fila anterior (`estado = archivado`), nunca la borra.
///
/// `crear` inserta *solo* la fila de metadatos — desde la Etapa 5A, el
/// llamador siempre debe insertar también la fila de unión (en la
/// tabla puente del dueño correspondiente) en la misma transacción,
/// justo después. Ningún método de este repositorio hace esa segunda
/// inserción por sí mismo: cuál tabla puente usar depende del dominio
/// dueño, algo que este repositorio compartido no conoce.
class AttachmentRepository {
  AttachmentRepository(this._db);

  final AppDatabase _db;

  Future<AttachmentData> crear(AttachmentCompanion datos) {
    return _db.into(_db.attachment).insertReturning(datos);
  }

  Future<AttachmentData?> obtenerPorId(String id) {
    return (_db.select(_db.attachment)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// Solo `estado = activo` — la consulta normal del documento nunca
  /// debe mostrar versiones reemplazadas (Resolución 6 de Marlon).
  Future<List<AttachmentData>> listarActivosPorDocumentoPorEmitir(
    String documentoPorEmitirId, {
    String? categoria,
  }) {
    final query = _db.select(_db.attachment).join([
      innerJoin(
        _db.documentoPorEmitirAttachment,
        _db.documentoPorEmitirAttachment.attachmentId.equalsExp(_db.attachment.id),
      ),
    ])
      ..where(_db.documentoPorEmitirAttachment.documentoPorEmitirId.equals(documentoPorEmitirId) &
          _db.attachment.estado.equals('activo'));
    if (categoria != null) {
      query.where(_db.attachment.categoria.equals(categoria));
    }
    query.orderBy([OrderingTerm.asc(_db.attachment.createdAt)]);
    return query.map((row) => row.readTable(_db.attachment)).get();
  }

  /// Solo `estado = archivado` — la vía explícita para consultar
  /// versiones anteriores desde el historial (Resolución 6 de Marlon:
  /// nunca se pierde la trazabilidad).
  Future<List<AttachmentData>> listarArchivadosPorDocumentoPorEmitir(String documentoPorEmitirId) {
    final query = _db.select(_db.attachment).join([
      innerJoin(
        _db.documentoPorEmitirAttachment,
        _db.documentoPorEmitirAttachment.attachmentId.equalsExp(_db.attachment.id),
      ),
    ])
      ..where(_db.documentoPorEmitirAttachment.documentoPorEmitirId.equals(documentoPorEmitirId) &
          _db.attachment.estado.equals('archivado'))
      ..orderBy([OrderingTerm.asc(_db.attachment.createdAt)]);
    return query.map((row) => row.readTable(_db.attachment)).get();
  }

  /// Comprobantes de pago activos de un `Pago` (Etapa 4J.2) — mismo
  /// criterio que los adjuntos de `DocumentoPorEmitir`: solo `estado =
  /// activo`.
  Future<List<AttachmentData>> listarActivosPorPago(String pagoId) {
    final query = _db.select(_db.attachment).join([
      innerJoin(_db.pagoAttachment, _db.pagoAttachment.attachmentId.equalsExp(_db.attachment.id)),
    ])
      ..where(_db.pagoAttachment.pagoId.equals(pagoId) & _db.attachment.estado.equals('activo'))
      ..orderBy([OrderingTerm.asc(_db.attachment.createdAt)]);
    return query.map((row) => row.readTable(_db.attachment)).get();
  }

  /// Adjuntos (PDF/XML) activos de un `ComplementoPago` (Etapa 4J.3) —
  /// mismo criterio que los adjuntos de `DocumentoPorEmitir`/`Pago`.
  Future<List<AttachmentData>> listarActivosPorComplementoPago(String complementoPagoId) {
    final query = _db.select(_db.attachment).join([
      innerJoin(
        _db.complementoPagoAttachment,
        _db.complementoPagoAttachment.attachmentId.equalsExp(_db.attachment.id),
      ),
    ])
      ..where(_db.complementoPagoAttachment.complementoPagoId.equals(complementoPagoId) &
          _db.attachment.estado.equals('activo'))
      ..orderBy([OrderingTerm.asc(_db.attachment.createdAt)]);
    return query.map((row) => row.readTable(_db.attachment)).get();
  }

  /// Comprobantes activos de un Ingreso manual (Etapa 4K.1).
  Future<List<AttachmentData>> listarActivosPorIngreso(String ingresoId) {
    final query = _db.select(_db.attachment).join([
      innerJoin(_db.ingresoAttachment, _db.ingresoAttachment.attachmentId.equalsExp(_db.attachment.id)),
    ])
      ..where(_db.ingresoAttachment.ingresoId.equals(ingresoId) & _db.attachment.estado.equals('activo'))
      ..orderBy([OrderingTerm.asc(_db.attachment.createdAt)]);
    return query.map((row) => row.readTable(_db.attachment)).get();
  }

  /// Comprobantes activos de un Egreso (Etapa 4K.1).
  Future<List<AttachmentData>> listarActivosPorEgreso(String egresoId) {
    final query = _db.select(_db.attachment).join([
      innerJoin(_db.egresoAttachment, _db.egresoAttachment.attachmentId.equalsExp(_db.attachment.id)),
    ])
      ..where(_db.egresoAttachment.egresoId.equals(egresoId) & _db.attachment.estado.equals('activo'))
      ..orderBy([OrderingTerm.asc(_db.attachment.createdAt)]);
    return query.map((row) => row.readTable(_db.attachment)).get();
  }

  /// Comprobantes activos de un `PagoNomina` (Etapa 6D).
  Future<List<AttachmentData>> listarActivosPorPagoNomina(String pagoNominaId) {
    final query = _db.select(_db.attachment).join([
      innerJoin(_db.pagoNominaAttachment, _db.pagoNominaAttachment.attachmentId.equalsExp(_db.attachment.id)),
    ])
      ..where(_db.pagoNominaAttachment.pagoNominaId.equals(pagoNominaId) & _db.attachment.estado.equals('activo'))
      ..orderBy([OrderingTerm.asc(_db.attachment.createdAt)]);
    return query.map((row) => row.readTable(_db.attachment)).get();
  }

  /// Comprobantes activos de un `MovimientoInventario` (Etapa 7A).
  Future<List<AttachmentData>> listarActivosPorMovimientoInventario(String movimientoInventarioId) {
    final query = _db.select(_db.attachment).join([
      innerJoin(
        _db.movimientoInventarioAttachment,
        _db.movimientoInventarioAttachment.attachmentId.equalsExp(_db.attachment.id),
      ),
    ])
      ..where(_db.movimientoInventarioAttachment.movimientoInventarioId.equals(movimientoInventarioId) &
          _db.attachment.estado.equals('activo'))
      ..orderBy([OrderingTerm.asc(_db.attachment.createdAt)]);
    return query.map((row) => row.readTable(_db.attachment)).get();
  }

  /// Resguardos activos (documento de entrega firmado) de una
  /// `Asignacion` (Etapa 7C) — un mismo Attachment puede aparecer para
  /// varias Asignaciones distintas (llave compuesta en
  /// `AsignacionAttachment`, ver su doc comment): un resguardo real
  /// suele cubrir varios artículos con una sola firma.
  Future<List<AttachmentData>> listarActivosPorAsignacion(String asignacionId) {
    final query = _db.select(_db.attachment).join([
      innerJoin(_db.asignacionAttachment, _db.asignacionAttachment.attachmentId.equalsExp(_db.attachment.id)),
    ])
      ..where(_db.asignacionAttachment.asignacionId.equals(asignacionId) & _db.attachment.estado.equals('activo'))
      ..orderBy([OrderingTerm.asc(_db.attachment.createdAt)]);
    return query.map((row) => row.readTable(_db.attachment)).get();
  }

  /// Documentos activos del expediente de un Empleado (Etapa 5A).
  Future<List<AttachmentData>> listarActivosPorEmpleado(String empleadoId) {
    final query = _db.select(_db.attachment).join([
      innerJoin(_db.empleadoAttachment, _db.empleadoAttachment.attachmentId.equalsExp(_db.attachment.id)),
    ])
      ..where(_db.empleadoAttachment.empleadoId.equals(empleadoId) & _db.attachment.estado.equals('activo'))
      ..orderBy([OrderingTerm.asc(_db.attachment.createdAt)]);
    return query.map((row) => row.readTable(_db.attachment)).get();
  }

  /// Adjuntos generales activos de un Vehículo (Etapa 8A) — incluye la
  /// fotografía (también apuntada directo por
  /// `Vehiculo.fotografiaAttachmentId` para acceso O(1)). Documentos con
  /// vencimiento (Etapa 8C) y comprobantes de mantenimiento (Etapa 8D)
  /// usan sus propias tablas puente, no esta.
  Future<List<AttachmentData>> listarActivosPorVehiculo(String vehiculoId) {
    final query = _db.select(_db.attachment).join([
      innerJoin(_db.vehiculoAttachment, _db.vehiculoAttachment.attachmentId.equalsExp(_db.attachment.id)),
    ])
      ..where(_db.vehiculoAttachment.vehiculoId.equals(vehiculoId) & _db.attachment.estado.equals('activo'))
      ..orderBy([OrderingTerm.asc(_db.attachment.createdAt)]);
    return query.map((row) => row.readTable(_db.attachment)).get();
  }

  /// Adjuntos activos de un `VehiculoDocumento` puntual (Etapa 8C) —
  /// separado de `listarActivosPorVehiculo` a propósito (ver el doc
  /// comment de esa tabla): el adjunto pertenece al documento concreto,
  /// no al Vehículo directo.
  Future<List<AttachmentData>> listarActivosPorVehiculoDocumento(String vehiculoDocumentoId) {
    final query = _db.select(_db.attachment).join([
      innerJoin(
        _db.vehiculoDocumentoAttachment,
        _db.vehiculoDocumentoAttachment.attachmentId.equalsExp(_db.attachment.id),
      ),
    ])
      ..where(
        _db.vehiculoDocumentoAttachment.vehiculoDocumentoId.equals(vehiculoDocumentoId) &
            _db.attachment.estado.equals('activo'),
      )
      ..orderBy([OrderingTerm.asc(_db.attachment.createdAt)]);
    return query.map((row) => row.readTable(_db.attachment)).get();
  }

  Future<void> archivar(String id) {
    return (_db.update(_db.attachment)..where((t) => t.id.equals(id))).write(
      const AttachmentCompanion(estado: Value('archivado')),
    );
  }
}
