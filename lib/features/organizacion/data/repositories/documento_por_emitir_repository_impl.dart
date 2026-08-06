import 'package:drift/drift.dart';
import 'package:riseg_one/core/database/app_database.dart';

import '../../domain/repositories/documento_por_emitir_repository.dart';
import '../../domain/usecases/documento_por_emitir_armado.dart';
import '../../domain/usecases/documento_por_emitir_detalle.dart';

class DocumentoPorEmitirRepositoryImpl implements DocumentoPorEmitirRepository {
  DocumentoPorEmitirRepositoryImpl(this._db);

  final AppDatabase _db;

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

    return DocumentoPorEmitirDetalle(
      documento: documento,
      servicioIds: [for (final s in servicios) s.servicioId],
      configuraciones: configuraciones,
      lineas: lineas,
      correos: [for (final c in correos) c.correo],
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
  }) async {
    await (_db.update(_db.documentoPorEmitir)..where((t) => t.id.equals(documentoPorEmitirId))).write(
      DocumentoPorEmitirCompanion(
        estatus: Value(nuevoEstatus),
        motivoEstatus: Value(motivo),
        updatedAt: Value(DateTime.now()),
      ),
    );
    return (_db.select(_db.documentoPorEmitir)..where((t) => t.id.equals(documentoPorEmitirId))).getSingle();
  }

  @override
  Future<DocumentoPorEmitirData> actualizarAjusteManual({
    required String documentoPorEmitirId,
    int? ajusteManual,
    String? motivoAjuste,
  }) async {
    final actual = await (_db.select(_db.documentoPorEmitir)..where((t) => t.id.equals(documentoPorEmitirId))).getSingle();
    final importeFinal = actual.importeBaseEsperado + (ajusteManual ?? 0);

    await (_db.update(_db.documentoPorEmitir)..where((t) => t.id.equals(documentoPorEmitirId))).write(
      DocumentoPorEmitirCompanion(
        ajusteManual: Value(ajusteManual),
        motivoAjuste: Value(motivoAjuste),
        importeFinalEsperado: Value(importeFinal),
        updatedAt: Value(DateTime.now()),
      ),
    );
    return (_db.select(_db.documentoPorEmitir)..where((t) => t.id.equals(documentoPorEmitirId))).getSingle();
  }
}
