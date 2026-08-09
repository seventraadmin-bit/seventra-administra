import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:riseg_one/core/attachments/attachment_repository.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/cuenta_por_cobrar_repository.dart';
import 'package:uuid/uuid.dart';

import '../../domain/repositories/documento_por_emitir_repository.dart';
import '../../domain/usecases/documento_por_emitir_armado.dart';
import '../../domain/usecases/documento_por_emitir_detalle.dart';
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
  DocumentoPorEmitirRepositoryImpl(this._db, this._attachmentRepository, this._cuentaPorCobrarRepository);

  final AppDatabase _db;
  final AttachmentRepository _attachmentRepository;
  final CuentaPorCobrarRepository _cuentaPorCobrarRepository;

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

    return DocumentoPorEmitirDetalle(
      documento: documento,
      servicioIds: [for (final s in servicios) s.servicioId],
      configuraciones: configuraciones,
      lineas: lineas,
      correos: [for (final c in correos) c.correo],
      correosEnvio: correosEnvio,
      eventos: eventos,
    );
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
    String? actor,
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
        actor: actor,
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
          serieFiscal: actualizado.serieFiscal,
          folioFiscal: actualizado.folioFiscal,
          uuid: actualizado.uuid,
          fechaEmisionReal: actualizado.fechaEmisionReal!,
          importeEmitido: actualizado.importeEmitido!,
          fechaVencimiento: actualizado.fechaPagoEsperadoProgramada,
          actor: actor,
        );
      }

      return actualizado;
    });
  }

  @override
  Future<DocumentoPorEmitirData> registrarEmision({
    required String documentoPorEmitirId,
    required String folioDocumento,
    String? serieFiscal,
    String? folioFiscal,
    String? uuid,
    required DateTime fechaEmisionReal,
    required int importeEmitido,
    String? observacionesEmision,
    String? actor,
  }) {
    return _db.transaction(() async {
      final anterior = await (_db.select(_db.documentoPorEmitir)..where((t) => t.id.equals(documentoPorEmitirId)))
          .getSingle();

      await (_db.update(_db.documentoPorEmitir)..where((t) => t.id.equals(documentoPorEmitirId))).write(
        DocumentoPorEmitirCompanion(
          estatus: const Value(_estatusEmitido),
          folioDocumento: Value(folioDocumento),
          serieFiscal: Value(serieFiscal),
          folioFiscal: Value(folioFiscal),
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
        actor: actor,
        datosRelevantes: {
          'folioDocumento': folioDocumento,
          'serieFiscal': serieFiscal,
          'folioFiscal': folioFiscal,
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
    String? serieFiscal,
    String? folioFiscal,
    String? uuid,
    DateTime? fechaEmisionReal,
    int? importeEmitido,
    String? observacionesEmision,
    String? actor,
  }) {
    return _db.transaction(() async {
      final anterior = await (_db.select(_db.documentoPorEmitir)..where((t) => t.id.equals(documentoPorEmitirId)))
          .getSingle();

      await (_db.update(_db.documentoPorEmitir)..where((t) => t.id.equals(documentoPorEmitirId))).write(
        DocumentoPorEmitirCompanion(
          folioDocumento: folioDocumento == null ? const Value.absent() : Value(folioDocumento),
          serieFiscal: serieFiscal == null ? const Value.absent() : Value(serieFiscal),
          folioFiscal: folioFiscal == null ? const Value.absent() : Value(folioFiscal),
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
        actor: actor,
        datosRelevantes: {
          'folioDocumentoAnterior': anterior.folioDocumento,
          'serieFiscalAnterior': anterior.serieFiscal,
          'folioFiscalAnterior': anterior.folioFiscal,
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
    String? actor,
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
        actor: actor,
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
    String? actor,
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
        actor: actor,
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
    String? actor,
  }) {
    return _db.transaction(() async {
      final adjunto = await _attachmentRepository.crear(
        AttachmentCompanion.insert(
          id: const Uuid().v4(),
          documentoPorEmitirId: Value(documentoPorEmitirId),
          categoria: Value(categoria),
          originalFileName: originalFileName,
          storedFileName: storedFileName,
          path: path,
          mimeType: mimeType,
          sizeBytes: sizeBytes,
        ),
      );

      await _registrarEvento(
        documentoPorEmitirId: documentoPorEmitirId,
        tipoEvento: TipoEventoDocumentoPorEmitir.archivoAdjuntado,
        estadoAnterior: null,
        estadoNuevo: null,
        actor: actor,
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
    String? actor,
  }) {
    return _db.transaction(() async {
      final anterior = await _attachmentRepository.obtenerPorId(attachmentAnteriorId);

      final nuevo = await _attachmentRepository.crear(
        AttachmentCompanion.insert(
          id: const Uuid().v4(),
          documentoPorEmitirId: Value(documentoPorEmitirId),
          categoria: Value(categoria),
          originalFileName: originalFileName,
          storedFileName: storedFileName,
          path: path,
          mimeType: mimeType,
          sizeBytes: sizeBytes,
        ),
      );
      await _attachmentRepository.archivar(attachmentAnteriorId);

      await _registrarEvento(
        documentoPorEmitirId: documentoPorEmitirId,
        tipoEvento: TipoEventoDocumentoPorEmitir.archivoReemplazado,
        estadoAnterior: null,
        estadoNuevo: null,
        observacion: motivo,
        actor: actor,
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

  Future<void> _registrarEvento({
    required String documentoPorEmitirId,
    required TipoEventoDocumentoPorEmitir tipoEvento,
    required String? estadoAnterior,
    required String? estadoNuevo,
    String? observacion,
    String? actor,
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
            actor: Value(actor),
            datosRelevantes: Value(datosRelevantes == null ? null : jsonEncode(datosRelevantes)),
          ),
        );
  }
}

const _estatusEmitido = 'emitido';
const _estatusEnviado = 'enviado';
