import 'package:riseg_one/core/database/app_database.dart';

import '../usecases/documento_por_emitir_armado.dart';
import '../usecases/documento_por_emitir_detalle.dart';

/// Agenda de documentos por emitir (Etapa 4I.1) — obligaciones
/// administrativas de preparar un CFDI/recibo, nunca el documento real
/// ni una Cuenta por cobrar.
abstract interface class DocumentoPorEmitirRepository {
  /// `null` si ningún documento existe todavía con esa
  /// `generationKey` — usado por la generación para omitir duplicados
  /// con un mensaje comprensible antes de intentar insertar (el índice
  /// único de la tabla es la protección real contra concurrencia).
  Future<DocumentoPorEmitirData?> obtenerPorGenerationKey(String generationKey);

  Future<DocumentoPorEmitirData?> obtenerPorId(String documentoPorEmitirId);

  /// Inserta el documento y sus 4 tablas hijas en una sola transacción.
  Future<DocumentoPorEmitirData> crearDocumento({
    required String codigo,
    required DocumentoPorEmitirArmado armado,
  });

  Future<DocumentoPorEmitirDetalle?> obtenerDetalle(String documentoPorEmitirId);

  Future<List<DocumentoPorEmitirData>> listar({
    DateTime? rangoInicio,
    DateTime? rangoFin,
    String? clienteId,
    String? servicioId,
    String? tipoDocumento,
    String? estatus,
  });

  /// Cambia el estatus — el caso de uso ya validó la transición y que
  /// `motivo` esté presente cuando la transición lo exige.
  Future<DocumentoPorEmitirData> cambiarEstatus({
    required String documentoPorEmitirId,
    required String nuevoEstatus,
    String? motivo,
  });

  /// El modelo existe desde la Etapa 4I.1 aunque la interfaz de captura
  /// se difiera a la 4I.2 — nunca toca el snapshot de líneas.
  Future<DocumentoPorEmitirData> actualizarAjusteManual({
    required String documentoPorEmitirId,
    int? ajusteManual,
    String? motivoAjuste,
  });
}
