import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:riseg_one/core/attachments/attachment_repository.dart';
import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show EstatusAplicacionPago;
import 'package:riseg_one/features/finanzas/domain/repositories/cuenta_por_cobrar_repository.dart';
import 'package:uuid/uuid.dart';

import '../../domain/repositories/documento_por_emitir_repository.dart';
import '../../domain/usecases/documento_por_emitir_armado.dart';
import '../../domain/usecases/documento_por_emitir_detalle.dart';
import '../../domain/usecases/eliminar_documento_por_emitir_fisicamente_usecase.dart';
import '../tables/documento_por_emitir_table.dart';

/// **Nota de arquitectura (Etapa 4J.1):** este repositorio, de
/// `organizacion`, depende de `CuentaPorCobrarRepository`, del dominio
/// `finanzas` — la única forma de garantizar que la generación de la
/// Cuenta por cobrar ocurra en la *misma transacción* que el cambio de
/// estatus a `procesadoAceptado` (Resolución A de Marlon, explícita:
/// "nunca debe existir un documento aceptado sin su Cuenta por
/// cobrar"). Es una dependencia deliberada solo en la capa de datos
/// (el `DocumentoPorEmitirRepository` — la interfaz, capa de dominio —
/// no sabe nada de `finanzas`); mismo criterio de composición ya usado
/// con `AttachmentRepository` en 4I.2.2, aplicado aquí entre dos
/// dominios de features en vez de entre un dominio y `core`.
class DocumentoPorEmitirRepositoryImpl implements DocumentoPorEmitirRepository {
  DocumentoPorEmitirRepositoryImpl(
    this._db,
    this._attachmentRepository,
    this._cuentaPorCobrarRepository, {
    AttachmentStorage? attachmentStorage,
  }) : _attachmentStorage = attachmentStorage;

  final AppDatabase _db;
  final AttachmentRepository _attachmentRepository;
  final CuentaPorCobrarRepository _cuentaPorCobrarRepository;

  /// Opcional a propósito (Etapa 15): la mayoría de los llamadores de
  /// este repositorio (Nómina, Finanzas, otras pruebas) nunca ejecutan
  /// `eliminarFisicamente` y no necesitan construir un
  /// `AttachmentStorage` real solo para satisfacer el constructor. En
  /// producción, el provider siempre lo pasa. Si es `null` y sí hay
  /// adjuntos que limpiar, el archivo físico simplemente no se intenta
  /// borrar — se reporta como no eliminado, nunca se oculta ni se
  /// finge éxito completo.
  final AttachmentStorage? _attachmentStorage;

  @override
  Future<DocumentoPorEmitirData?> obtenerPorGenerationKey(String generationKey) {
    return (_db.select(_db.documentoPorEmitir)..where((t) => t.generationKey.equals(generationKey))).getSingleOrNull();
  }

  @override
  Future<DocumentoPorEmitirData?> obtenerPorId(String documentoPorEmitirId) {
    return (_db.select(_db.documentoPorEmitir)..where((t) => t.id.equals(documentoPorEmitirId))).getSingleOrNull();
  }

  @override
  Future<DocumentoPorEmitirData> crearDocumento({
    required String codigo,
    required DocumentoPorEmitirArmado armado,
    required TipoEventoDocumentoPorEmitir tipoEventoCreacion,
  }) {
    return _db.transaction(() async {
      final documento = await _db.into(_db.documentoPorEmitir).insertReturning(
            DocumentoPorEmitirCompanion.insert(
              codigo: codigo,
              clienteId: armado.clienteId,
              entidadFiscalId: Value(armado.entidadFiscalId),
              clientePortalId: Value(armado.clientePortalId),
              tipoDocumento: armado.tipoDocumento,
              agrupacion: armado.agrupacion,
              metodo: armado.metodo,
              requiereComplemento: Value(armado.requiereComplemento),
              periodoInicio: armado.periodoInicio,
              periodoFin: armado.periodoFin,
              fechaEmisionProgramada: Value(armado.fechaEmisionProgramada),
              fechaProcesamientoProgramada: Value(armado.fechaProcesamientoProgramada),
              fechaPagoEsperadoProgramada: Value(armado.fechaPagoEsperadoProgramada),
              generationKey: armado.generationKey,
              importeBaseEsperado: armado.importeBaseEsperado,
              importeFinalEsperado: armado.importeBaseEsperado,
            ),
          );

      for (final servicioId in armado.servicioIds) {
        await _db.into(_db.documentoPorEmitirServicio).insert(
              DocumentoPorEmitirServicioCompanion.insert(
                documentoPorEmitirId: documento.id,
                servicioId: servicioId,
              ),
            );
      }

      for (final config in armado.configuraciones) {
        await _db.into(_db.documentoPorEmitirConfiguracion).insert(
              DocumentoPorEmitirConfiguracionCompanion.insert(
                documentoPorEmitirId: documento.id,
                servicioId: config.servicioId,
                configuracionCobroVigenciaId: config.configuracionCobroVigenciaId,
                fechaEmisionProgramada: Value(config.fechaEmisionProgramada),
                fechaProcesamientoProgramada: Value(config.fechaProcesamientoProgramada),
                fechaPagoEsperadoProgramada: Value(config.fechaPagoEsperadoProgramada),
              ),
            );
        for (final hito in config.hitos) {
          await _db.into(_db.documentoPorEmitirHito).insert(
                DocumentoPorEmitirHitoCompanion.insert(
                  documentoPorEmitirId: documento.id,
                  servicioId: config.servicioId,
                  tipoSistema: Value(hito.tipoSistema),
                  nombre: Value(hito.nombre),
                  orden: hito.orden,
                  fechaProgramada: hito.fecha,
                ),
              );
        }
      }

      for (final linea in armado.lineas) {
        await _db.into(_db.documentoPorEmitirLinea).insert(
              DocumentoPorEmitirLineaCompanion.insert(
                documentoPorEmitirId: documento.id,
                servicioId: linea.servicioId,
                lineaComercialVigenciaId: linea.lineaComercialVigenciaId,
                puestoNombre: linea.puestoNombre,
                modalidadTurnoNombre: linea.modalidadTurnoNombre,
                cantidadElementos: linea.cantidadElementos,
                precioUnitario: linea.precioUnitario,
                tratamientoIva: linea.tratamientoIva,
                diasAplicables: linea.diasAplicables,
                subtotalProporcional: linea.subtotalProporcional,
              ),
            );
      }

      for (final correo in armado.correos) {
        await _db.into(_db.documentoPorEmitirCorreo).insert(
              DocumentoPorEmitirCorreoCompanion.insert(documentoPorEmitirId: documento.id, correo: correo),
            );
      }

      await _registrarEvento(
        documentoPorEmitirId: documento.id,
        tipoEvento: tipoEventoCreacion,
        estadoAnterior: null,
        estadoNuevo: documento.estatus,
      );

      return documento;
    });
  }

  @override
  Future<DocumentoPorEmitirDetalle?> obtenerDetalle(String documentoPorEmitirId) async {
    final documento = await obtenerPorId(documentoPorEmitirId);
    if (documento == null) return null;

    final servicios = await (_db.select(_db.documentoPorEmitirServicio)
          ..where((t) => t.documentoPorEmitirId.equals(documentoPorEmitirId)))
        .get();
    final configuraciones = await (_db.select(_db.documentoPorEmitirConfiguracion)
          ..where((t) => t.documentoPorEmitirId.equals(documentoPorEmitirId)))
        .get();
    final lineas = await (_db.select(_db.documentoPorEmitirLinea)
          ..where((t) => t.documentoPorEmitirId.equals(documentoPorEmitirId)))
        .get();
    final correos = await (_db.select(_db.documentoPorEmitirCorreo)
          ..where((t) => t.documentoPorEmitirId.equals(documentoPorEmitirId)))
        .get();
    final correosEnvio = await listarCorreosEnvio(documentoPorEmitirId);
    final eventos = await listarEventos(documentoPorEmitirId);
    final hitos = await listarHitos(documentoPorEmitirId);

    return DocumentoPorEmitirDetalle(
      documento: documento,
      servicioIds: [for (final s in servicios) s.servicioId],
      configuraciones: configuraciones,
      lineas: lineas,
      correos: [for (final c in correos) c.correo],
      correosEnvio: correosEnvio,
      eventos: eventos,
      hitos: hitos,
    );
  }

  @override
  Future<List<DocumentoPorEmitirHitoData>> listarHitos(String documentoPorEmitirId) {
    return (_db.select(_db.documentoPorEmitirHito)
          ..where((t) => t.documentoPorEmitirId.equals(documentoPorEmitirId))
          ..orderBy([(t) => OrderingTerm.asc(t.orden)]))
        .get();
  }

  @override
  Future<List<DocumentoPorEmitirData>> listar({
    DateTime? rangoInicio,
    DateTime? rangoFin,
    String? clienteId,
    String? servicioId,
    String? tipoDocumento,
    String? estatus,
  }) async {
    if (servicioId != null) {
      final query = _db.select(_db.documentoPorEmitir).join([
        innerJoin(
          _db.documentoPorEmitirServicio,
          _db.documentoPorEmitirServicio.documentoPorEmitirId.equalsExp(_db.documentoPorEmitir.id),
        ),
      ])
        ..where(_db.documentoPorEmitirServicio.servicioId.equals(servicioId));
      final condicionRango = _condicionRango(rangoInicio: rangoInicio, rangoFin: rangoFin);
      if (condicionRango != null) query.where(condicionRango);
      _aplicarFiltros(query, clienteId: clienteId, tipoDocumento: tipoDocumento, estatus: estatus);
      final filas = await query.get();
      return [for (final f in filas) f.readTable(_db.documentoPorEmitir)];
    }

    final query = _db.select(_db.documentoPorEmitir);
    final condicionRango = _condicionRango(rangoInicio: rangoInicio, rangoFin: rangoFin);
    if (condicionRango != null) {
      query.where((_) => condicionRango);
    }
    if (clienteId != null) {
      query.where((t) => t.clienteId.equals(clienteId));
    }
    if (tipoDocumento != null) {
      query.where((t) => t.tipoDocumento.equals(tipoDocumento));
    }
    if (estatus != null) {
      query.where((t) => t.estatus.equals(estatus));
    }
    query.orderBy([(t) => OrderingTerm.asc(t.periodoInicio)]);
    return query.get();
  }

  /// Filtra por `fechaEmisionProgramada` cuando existe; si es nula (una
  /// vigencia sin regla de Emisión — Toluca 32, Tikal, Mirabilia), usa
  /// `periodoInicio` como respaldo. Sin este respaldo, un documento
  /// creado manualmente sin fecha de emisión calculable nunca aparecería
  /// en ningún rango de la Agenda, quedando invisible para siempre.
  Expression<bool>? _condicionRango({required DateTime? rangoInicio, required DateTime? rangoFin}) {
    final fecha = _db.documentoPorEmitir.fechaEmisionProgramada;
    final periodoInicio = _db.documentoPorEmitir.periodoInicio;

    Expression<bool>? condicion;
    if (rangoInicio != null) {
      condicion = fecha.isBiggerOrEqualValue(rangoInicio) | (fecha.isNull() & periodoInicio.isBiggerOrEqualValue(rangoInicio));
    }
    if (rangoFin != null) {
      final cond = fecha.isSmallerOrEqualValue(rangoFin) | (fecha.isNull() & periodoInicio.isSmallerOrEqualValue(rangoFin));
      condicion = condicion == null ? cond : condicion & cond;
    }
    return condicion;
  }

  void _aplicarFiltros(
    JoinedSelectStatement query, {
    required String? clienteId,
    required String? tipoDocumento,
    required String? estatus,
  }) {
    if (clienteId != null) {
      query.where(_db.documentoPorEmitir.clienteId.equals(clienteId));
    }
    if (tipoDocumento != null) {
      query.where(_db.documentoPorEmitir.tipoDocumento.equals(tipoDocumento));
    }
    if (estatus != null) {
      query.where(_db.documentoPorEmitir.estatus.equals(estatus));
    }
  }

  @override
  Future<DocumentoPorEmitirData> cambiarEstatus({
    required String documentoPorEmitirId,
    required String nuevoEstatus,
    String? motivo,
    required TipoEventoDocumentoPorEmitir tipoEvento,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final anterior = await (_db.select(_db.documentoPorEmitir)..where((t) => t.id.equals(documentoPorEmitirId)))
          .getSingle();

      await (_db.update(_db.documentoPorEmitir)..where((t) => t.id.equals(documentoPorEmitirId))).write(
        DocumentoPorEmitirCompanion(
          estatus: Value(nuevoEstatus),
          motivoEstatus: Value(motivo),
          updatedAt: Value(DateTime.now()),
        ),
      );

      await _registrarEvento(
        documentoPorEmitirId: documentoPorEmitirId,
        tipoEvento: tipoEvento,
        estadoAnterior: anterior.estatus,
        estadoNuevo: nuevoEstatus,
        observacion: motivo,
        actorUsuarioId: actorUsuarioId,
      );

      final actualizado =
          await (_db.select(_db.documentoPorEmitir)..where((t) => t.id.equals(documentoPorEmitirId))).getSingle();

      // Etapa 4J.1, Resolución A de Marlon: la Cuenta por cobrar nace
      // en la misma transacción que la transición a
      // `procesadoAceptado` — nunca un paso manual, nunca puede
      // quedar un documento aceptado sin la suya. `fechaEmisionReal`/
      // `importeEmitido` son garantizados no nulos por la máquina de
      // estados (un documento solo llega aquí después de pasar por
      // `RegistrarEmisionDocumentoPorEmitirUseCase`, que los exige).
      if (nuevoEstatus == 'procesadoAceptado') {
        await _cuentaPorCobrarRepository.crear(
          documentoPorEmitirId: actualizado.id,
          clienteId: actualizado.clienteId,
          tipoDocumento: actualizado.tipoDocumento,
          metodo: actualizado.metodo,
          requiereComplemento: actualizado.requiereComplemento,
          folioDocumento: actualizado.folioDocumento,
          uuid: actualizado.uuid,
          fechaEmisionReal: actualizado.fechaEmisionReal!,
          importeEmitido: actualizado.importeEmitido!,
          fechaVencimiento: actualizado.fechaPagoEsperadoProgramada,
          actorUsuarioId: actorUsuarioId,
        );
      }

      return actualizado;
    });
  }

  @override
  Future<DocumentoPorEmitirData> registrarEmision({
    required String documentoPorEmitirId,
    required String folioDocumento,
    String? uuid,
    required DateTime fechaEmisionReal,
    required int importeEmitido,
    String? observacionesEmision,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final anterior = await (_db.select(_db.documentoPorEmitir)..where((t) => t.id.equals(documentoPorEmitirId)))
          .getSingle();

      await (_db.update(_db.documentoPorEmitir)..where((t) => t.id.equals(documentoPorEmitirId))).write(
        DocumentoPorEmitirCompanion(
          estatus: const Value(_estatusEmitido),
          folioDocumento: Value(folioDocumento),
          uuid: Value(uuid),
          fechaEmisionReal: Value(fechaEmisionReal),
          importeEmitido: Value(importeEmitido),
          observacionesEmision: Value(observacionesEmision),
          updatedAt: Value(DateTime.now()),
        ),
      );

      await _registrarEvento(
        documentoPorEmitirId: documentoPorEmitirId,
        tipoEvento: TipoEventoDocumentoPorEmitir.emisionRegistrada,
        estadoAnterior: anterior.estatus,
        estadoNuevo: _estatusEmitido,
        actorUsuarioId: actorUsuarioId,
        datosRelevantes: {
          'folioDocumento': folioDocumento,
          'uuid': uuid,
          'importeEmitido': importeEmitido,
        },
      );

      return (_db.select(_db.documentoPorEmitir)..where((t) => t.id.equals(documentoPorEmitirId))).getSingle();
    });
  }

  @override
  Future<DocumentoPorEmitirData> corregirDatosEmision({
    required String documentoPorEmitirId,
    required String motivo,
    String? folioDocumento,
    String? uuid,
    DateTime? fechaEmisionReal,
    int? importeEmitido,
    String? observacionesEmision,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final anterior = await (_db.select(_db.documentoPorEmitir)..where((t) => t.id.equals(documentoPorEmitirId)))
          .getSingle();

      await (_db.update(_db.documentoPorEmitir)..where((t) => t.id.equals(documentoPorEmitirId))).write(
        DocumentoPorEmitirCompanion(
          folioDocumento: folioDocumento == null ? const Value.absent() : Value(folioDocumento),
          uuid: uuid == null ? const Value.absent() : Value(uuid),
          fechaEmisionReal: fechaEmisionReal == null ? const Value.absent() : Value(fechaEmisionReal),
          importeEmitido: importeEmitido == null ? const Value.absent() : Value(importeEmitido),
          observacionesEmision: observacionesEmision == null ? const Value.absent() : Value(observacionesEmision),
          updatedAt: Value(DateTime.now()),
        ),
      );

      await _registrarEvento(
        documentoPorEmitirId: documentoPorEmitirId,
        tipoEvento: TipoEventoDocumentoPorEmitir.correccionDatosEmision,
        estadoAnterior: anterior.estatus,
        estadoNuevo: anterior.estatus,
        observacion: motivo,
        actorUsuarioId: actorUsuarioId,
        datosRelevantes: {
          'folioDocumentoAnterior': anterior.folioDocumento,
          'uuidAnterior': anterior.uuid,
          'importeEmitidoAnterior': anterior.importeEmitido,
        },
      );

      return (_db.select(_db.documentoPorEmitir)..where((t) => t.id.equals(documentoPorEmitirId))).getSingle();
    });
  }

  @override
  Future<DocumentoPorEmitirData> registrarEnvio({
    required String documentoPorEmitirId,
    required DateTime fechaEnvio,
    required List<String> correos,
    String? observacionesEnvio,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final anterior = await (_db.select(_db.documentoPorEmitir)..where((t) => t.id.equals(documentoPorEmitirId)))
          .getSingle();
      final correosAnteriores = await listarCorreosEnvio(documentoPorEmitirId);

      await (_db.update(_db.documentoPorEmitir)..where((t) => t.id.equals(documentoPorEmitirId))).write(
        DocumentoPorEmitirCompanion(
          estatus: const Value(_estatusEnviado),
          fechaEnvio: Value(fechaEnvio),
          observacionesEnvio: Value(observacionesEnvio),
          updatedAt: Value(DateTime.now()),
        ),
      );

      await (_db.delete(_db.documentoPorEmitirCorreoEnvio)..where((t) => t.documentoPorEmitirId.equals(documentoPorEmitirId)))
          .go();
      for (final correo in correos) {
        await _db.into(_db.documentoPorEmitirCorreoEnvio).insert(
              DocumentoPorEmitirCorreoEnvioCompanion.insert(documentoPorEmitirId: documentoPorEmitirId, correo: correo),
            );
      }

      await _registrarEvento(
        documentoPorEmitirId: documentoPorEmitirId,
        tipoEvento: TipoEventoDocumentoPorEmitir.envioRegistrado,
        estadoAnterior: anterior.estatus,
        estadoNuevo: _estatusEnviado,
        actorUsuarioId: actorUsuarioId,
        datosRelevantes: {
          'correosUtilizados': correos,
          if (correosAnteriores.isNotEmpty) 'correosAnteriores': correosAnteriores,
        },
      );

      return (_db.select(_db.documentoPorEmitir)..where((t) => t.id.equals(documentoPorEmitirId))).getSingle();
    });
  }

  @override
  Future<DocumentoPorEmitirData> actualizarAjusteManual({
    required String documentoPorEmitirId,
    int? ajusteManual,
    String? motivoAjuste,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final actual = await (_db.select(_db.documentoPorEmitir)..where((t) => t.id.equals(documentoPorEmitirId)))
          .getSingle();
      final importeFinal = actual.importeBaseEsperado + (ajusteManual ?? 0);

      await (_db.update(_db.documentoPorEmitir)..where((t) => t.id.equals(documentoPorEmitirId))).write(
        DocumentoPorEmitirCompanion(
          ajusteManual: Value(ajusteManual),
          motivoAjuste: Value(motivoAjuste),
          importeFinalEsperado: Value(importeFinal),
          updatedAt: Value(DateTime.now()),
        ),
      );

      await _registrarEvento(
        documentoPorEmitirId: documentoPorEmitirId,
        tipoEvento: TipoEventoDocumentoPorEmitir.ajusteRegistrado,
        estadoAnterior: actual.estatus,
        estadoNuevo: actual.estatus,
        observacion: motivoAjuste,
        actorUsuarioId: actorUsuarioId,
        datosRelevantes: {
          'ajusteAnterior': actual.ajusteManual,
          'ajusteNuevo': ajusteManual,
          'motivoAnterior': actual.motivoAjuste,
          'motivoNuevo': motivoAjuste,
          'importeFinalAnterior': actual.importeFinalEsperado,
          'importeFinalNuevo': importeFinal,
        },
      );

      return (_db.select(_db.documentoPorEmitir)..where((t) => t.id.equals(documentoPorEmitirId))).getSingle();
    });
  }

  @override
  Future<List<String>> listarCorreosEnvio(String documentoPorEmitirId) async {
    final filas = await (_db.select(_db.documentoPorEmitirCorreoEnvio)
          ..where((t) => t.documentoPorEmitirId.equals(documentoPorEmitirId)))
        .get();
    return [for (final f in filas) f.correo];
  }

  @override
  Future<List<DocumentoPorEmitirEventoData>> listarEventos(String documentoPorEmitirId) {
    return (_db.select(_db.documentoPorEmitirEvento)
          ..where((t) => t.documentoPorEmitirId.equals(documentoPorEmitirId))
          ..orderBy([(t) => OrderingTerm.asc(t.fechaHora)]))
        .get();
  }

  @override
  Future<AttachmentData> adjuntarArchivo({
    required String documentoPorEmitirId,
    required String categoria,
    required String originalFileName,
    required String storedFileName,
    required String path,
    required String mimeType,
    required int sizeBytes,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final adjunto = await _attachmentRepository.crear(
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
      await _db.into(_db.documentoPorEmitirAttachment).insert(
            DocumentoPorEmitirAttachmentCompanion.insert(
              attachmentId: adjunto.id,
              documentoPorEmitirId: documentoPorEmitirId,
            ),
          );

      await _registrarEvento(
        documentoPorEmitirId: documentoPorEmitirId,
        tipoEvento: TipoEventoDocumentoPorEmitir.archivoAdjuntado,
        estadoAnterior: null,
        estadoNuevo: null,
        actorUsuarioId: actorUsuarioId,
        datosRelevantes: {
          'categoria': categoria,
          'archivoNuevo': originalFileName,
          'attachmentId': adjunto.id,
        },
      );

      return adjunto;
    });
  }

  @override
  Future<AttachmentData> reemplazarArchivo({
    required String documentoPorEmitirId,
    required String attachmentAnteriorId,
    required String categoria,
    required String originalFileName,
    required String storedFileName,
    required String path,
    required String mimeType,
    required int sizeBytes,
    String? motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final anterior = await _attachmentRepository.obtenerPorId(attachmentAnteriorId);

      final nuevo = await _attachmentRepository.crear(
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
      await _db.into(_db.documentoPorEmitirAttachment).insert(
            DocumentoPorEmitirAttachmentCompanion.insert(
              attachmentId: nuevo.id,
              documentoPorEmitirId: documentoPorEmitirId,
            ),
          );
      await _attachmentRepository.archivar(attachmentAnteriorId);

      await _registrarEvento(
        documentoPorEmitirId: documentoPorEmitirId,
        tipoEvento: TipoEventoDocumentoPorEmitir.archivoReemplazado,
        estadoAnterior: null,
        estadoNuevo: null,
        observacion: motivo,
        actorUsuarioId: actorUsuarioId,
        datosRelevantes: {
          'categoria': categoria,
          'archivoAnteriorId': attachmentAnteriorId,
          'archivoAnterior': anterior?.originalFileName,
          'archivoNuevoId': nuevo.id,
          'archivoNuevo': originalFileName,
        },
      );

      return nuevo;
    });
  }

  /// Único bloqueador real (Etapa 15, corregido tras hallazgo real de
  /// Marlon): la Cuenta por cobrar del documento tiene al menos una
  /// `AplicacionPago` ACTIVA (`estatus == aplicada`). La versión
  /// anterior contaba también las `cancelada`, lo que dejaba un Pago
  /// cancelado (monto aplicado $0, sin efecto financiero real)
  /// bloqueando indefinidamente la eliminación del Documento — una
  /// aplicación cancelada ya no representa saldo aplicado, el mismo
  /// criterio que ya usa `PagoRepositoryImpl` para recalcular
  /// `CuentaPorCobrar.saldoPendiente`. Una Cuenta por cobrar sin
  /// ninguna aplicación activa es limpieza explícita segura.
  Future<({CuentaPorCobrarData? cuentaPorCobrar, bool bloqueado, String? detalleBloqueo})> _verificarCuentaPorCobrar(
    String documentoPorEmitirId,
  ) async {
    final cuentaPorCobrar = await (_db.select(_db.cuentaPorCobrar)
          ..where((t) => t.documentoPorEmitirId.equals(documentoPorEmitirId)))
        .getSingleOrNull();
    if (cuentaPorCobrar == null) {
      return (cuentaPorCobrar: null, bloqueado: false, detalleBloqueo: null);
    }

    final aplicacionesActivas = await (_db.select(_db.aplicacionPago)
          ..where(
            (t) => t.cuentaPorCobrarId.equals(cuentaPorCobrar.id) & t.estatus.equals(EstatusAplicacionPago.aplicada.name),
          ))
        .get();
    if (aplicacionesActivas.isNotEmpty) {
      return (
        cuentaPorCobrar: cuentaPorCobrar,
        bloqueado: true,
        detalleBloqueo:
            'Tiene ${aplicacionesActivas.length} pago(s) aplicado(s) a su Cuenta por cobrar — resuelve o elimina esa aplicación de pago antes de continuar.',
      );
    }
    return (cuentaPorCobrar: cuentaPorCobrar, bloqueado: false, detalleBloqueo: null);
  }

  @override
  Future<ResumenEliminacionDocumentoPorEmitir> obtenerResumenEliminacionFisica(String documentoPorEmitirId) async {
    final documento =
        await (_db.select(_db.documentoPorEmitir)..where((t) => t.id.equals(documentoPorEmitirId))).getSingleOrNull();
    if (documento == null) {
      return const ResumenEliminacionDocumentoPorEmitir(
        existe: false,
        tieneCuentaPorCobrar: false,
        cantidadAdjuntos: 0,
        bloqueadoPorPago: false,
      );
    }

    final cxc = await _verificarCuentaPorCobrar(documentoPorEmitirId);
    final adjuntos = await (_db.select(_db.documentoPorEmitirAttachment)
          ..where((t) => t.documentoPorEmitirId.equals(documentoPorEmitirId)))
        .get();

    return ResumenEliminacionDocumentoPorEmitir(
      existe: true,
      tieneCuentaPorCobrar: cxc.cuentaPorCobrar != null,
      cantidadAdjuntos: adjuntos.length,
      bloqueadoPorPago: cxc.bloqueado,
      detalleBloqueo: cxc.detalleBloqueo,
    );
  }

  /// Eliminación física extraordinaria (Etapa 15, ampliada) — el
  /// estatus del documento y la sola existencia de adjuntos o de una
  /// Cuenta por cobrar ya NO bloquean por sí solos (corrección
  /// explícita de Marlon: la facultad Maestro existe para poder
  /// limpiar datos de prueba/errores de captura reales, sin quedar
  /// atado a en qué estatus alcanzó a llegar el flujo). El único
  /// bloqueador real es una `AplicacionPago` ACTIVA — dinero realmente
  /// aplicado hoy (`_verificarCuentaPorCobrar`). Una aplicación
  /// cancelada (Pago cancelado, monto aplicado $0) ya no representa
  /// saldo real y no bloquea.
  ///
  /// Todo lo demás se limpia explícitamente, en una sola transacción:
  /// tablas hijas propias del documento (cascada automática, detalle
  /// interno, nunca una dependencia externa), la Cuenta por cobrar sin
  /// pagos aplicados (y su `CuentaPorCobrarEvento`, cascada) junto con
  /// sus `AplicacionPago` canceladas (solo la fila puente — el `Pago`
  /// origen y su propio historial permanecen intactos), y cada adjunto
  /// (fila puente + fila `Attachment`). Los archivos físicos en disco
  /// se borran DESPUÉS de que la transacción de BD haga commit — nunca
  /// antes: si el archivo no se puede borrar (permisos, en uso), la
  /// base de datos ya quedó consistente (fuente de verdad) y el
  /// documento ya está eliminado; el archivo huérfano se reporta
  /// explícitamente en el resultado, nunca se oculta.
  @override
  Future<EliminarDocumentoPorEmitirFisicamenteResultado> eliminarFisicamente({
    required String documentoPorEmitirId,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    final documentoInicial =
        await (_db.select(_db.documentoPorEmitir)..where((t) => t.id.equals(documentoPorEmitirId))).getSingleOrNull();
    if (documentoInicial == null) return EliminarDocumentoPorEmitirFisicamenteNoExiste();

    final cxc = await _verificarCuentaPorCobrar(documentoPorEmitirId);
    if (cxc.bloqueado) {
      return EliminarDocumentoPorEmitirFisicamenteTieneDependencias(cxc.detalleBloqueo!);
    }

    // Capturados antes de la transacción para poder borrar los
    // archivos físicos después del commit.
    final adjuntosQuery = _db.select(_db.attachment).join([
      innerJoin(_db.documentoPorEmitirAttachment, _db.documentoPorEmitirAttachment.attachmentId.equalsExp(_db.attachment.id)),
    ])
      ..where(_db.documentoPorEmitirAttachment.documentoPorEmitirId.equals(documentoPorEmitirId));
    final adjuntos = await adjuntosQuery.map((row) => row.readTable(_db.attachment)).get();

    // `AplicacionPago.cuentaPorCobrarId` es `restrict` — una fila
    // cancelada (sin efecto financiero real, ya no cuenta como
    // bloqueo desde `_verificarCuentaPorCobrar`) seguiría impidiendo
    // el `DELETE` de la Cuenta por cobrar a nivel de motor si no se
    // limpia explícitamente aquí. Se borra únicamente la fila puente
    // (nunca el `Pago` ni su propio historial, que permanecen intactos
    // — solo se pierde el vínculo hacia esta Cuenta ya eliminada).
    final aplicacionesCanceladas = cxc.cuentaPorCobrar == null
        ? const <AplicacionPagoData>[]
        : await (_db.select(_db.aplicacionPago)
              ..where(
                (t) =>
                    t.cuentaPorCobrarId.equals(cxc.cuentaPorCobrar!.id) &
                    t.estatus.equals(EstatusAplicacionPago.cancelada.name),
              ))
            .get();

    await _db.transaction(() async {
      final snapshot = <String, Object?>{
        'documento': documentoInicial.toJson(),
        if (cxc.cuentaPorCobrar != null) 'cuentaPorCobrar': cxc.cuentaPorCobrar!.toJson(),
        'aplicacionesPagoCanceladas': [for (final a in aplicacionesCanceladas) a.toJson()],
        'adjuntos': [for (final a in adjuntos) a.toJson()],
      };

      await (_db.delete(_db.documentoPorEmitirAttachment)..where((t) => t.documentoPorEmitirId.equals(documentoPorEmitirId)))
          .go();
      for (final adjunto in adjuntos) {
        await _attachmentRepository.eliminarFisico(adjunto.id);
      }

      if (cxc.cuentaPorCobrar != null) {
        for (final aplicacion in aplicacionesCanceladas) {
          await (_db.delete(_db.aplicacionPago)..where((t) => t.id.equals(aplicacion.id))).go();
        }
        await (_db.delete(_db.cuentaPorCobrar)..where((t) => t.id.equals(cxc.cuentaPorCobrar!.id))).go();
      }

      await _db.into(_db.eliminacionFisicaEvento).insert(
            EliminacionFisicaEventoCompanion.insert(
              tipoEntidad: 'documentoPorEmitir',
              entidadIdOriginal: documentoPorEmitirId,
              fechaHora: DateTime.now(),
              motivo: motivo,
              snapshotJson: jsonEncode(snapshot),
              actorUsuarioId: Value(actorUsuarioId),
            ),
          );
      await (_db.delete(_db.documentoPorEmitir)..where((t) => t.id.equals(documentoPorEmitirId))).go();
    });

    final archivosNoEliminados = <String>[];
    for (final adjunto in adjuntos) {
      if (_attachmentStorage == null) {
        archivosNoEliminados.add(adjunto.originalFileName);
        continue;
      }
      try {
        await _attachmentStorage.eliminarArchivo(adjunto.path);
      } catch (_) {
        archivosNoEliminados.add(adjunto.originalFileName);
      }
    }

    return EliminarDocumentoPorEmitirFisicamenteExitoso(archivosNoEliminadosFisicamente: archivosNoEliminados);
  }

  Future<void> _registrarEvento({
    required String documentoPorEmitirId,
    required TipoEventoDocumentoPorEmitir tipoEvento,
    required String? estadoAnterior,
    required String? estadoNuevo,
    String? observacion,
    String? actorUsuarioId,
    Map<String, Object?>? datosRelevantes,
  }) {
    return _db.into(_db.documentoPorEmitirEvento).insert(
          DocumentoPorEmitirEventoCompanion.insert(
            documentoPorEmitirId: documentoPorEmitirId,
            fechaHora: DateTime.now(),
            tipoEvento: tipoEvento.name,
            estadoAnterior: Value(estadoAnterior),
            estadoNuevo: Value(estadoNuevo),
            observacion: Value(observacion),
            actorUsuarioId: Value(actorUsuarioId),
            datosRelevantes: Value(datosRelevantes == null ? null : jsonEncode(datosRelevantes)),
          ),
        );
  }
}

const _estatusEmitido = 'emitido';
const _estatusEnviado = 'enviado';
