import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/documento_por_emitir_repository.dart';
import 'actualizar_ajuste_manual_documento_por_emitir_usecase.dart' show ajusteComercialCongelado;

sealed class CorregirAjusteHistoricoDocumentoPorEmitirResultado {}

class CorregirAjusteHistoricoDocumentoPorEmitirExitoso extends CorregirAjusteHistoricoDocumentoPorEmitirResultado {
  CorregirAjusteHistoricoDocumentoPorEmitirExitoso(this.documento);
  final DocumentoPorEmitirData documento;
}

class CorregirAjusteHistoricoDocumentoPorEmitirNoExiste extends CorregirAjusteHistoricoDocumentoPorEmitirResultado {}

/// Esta vía existe para documentos que YA se emitieron. Un documento que
/// todavía se puede editar por el camino normal nunca debe pasar por aquí:
/// sería una corrección administrativa sin nada que corregir.
class CorregirAjusteHistoricoDocumentoPorEmitirNoEmitido extends CorregirAjusteHistoricoDocumentoPorEmitirResultado {}

/// El motivo **administrativo** de la corrección — distinto del motivo
/// comercial del ajuste. Obligatorio siempre, incluso al dejar el ajuste en
/// cero: lo que se audita es el acto de reescribir un dato histórico.
class CorregirAjusteHistoricoDocumentoPorEmitirMotivoCorreccionRequerido
    extends CorregirAjusteHistoricoDocumentoPorEmitirResultado {}

/// Un ajuste distinto de cero exige su motivo comercial, igual que en el
/// camino normal.
class CorregirAjusteHistoricoDocumentoPorEmitirMotivoAjusteRequerido
    extends CorregirAjusteHistoricoDocumentoPorEmitirResultado {}

class CorregirAjusteHistoricoDocumentoPorEmitirImporteNegativo
    extends CorregirAjusteHistoricoDocumentoPorEmitirResultado {}

class CorregirAjusteHistoricoDocumentoPorEmitirErrorInesperado
    extends CorregirAjusteHistoricoDocumentoPorEmitirResultado {
  CorregirAjusteHistoricoDocumentoPorEmitirErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Corrige el ajuste comercial de un documento **ya emitido** — la única
/// forma de arreglar el importe esperado de documentos capturados antes de
/// que existiera esta regla.
///
/// Corrige exclusivamente el *snapshot comercial esperado* y su auditoría.
/// Deliberadamente **no** toca, ni tiene forma de tocar: `importeEmitido`,
/// folio, UUID, fecha de emisión, Cuenta por cobrar, Pago, Ingreso,
/// Complemento ni caja — el repositorio sólo escribe el trío
/// `ajusteManual`/`motivoAjuste`/`importeFinalEsperado`. Lo que se emitió,
/// se emitió; lo que aquí se corrige es lo que RISEG ONE *esperaba* cobrar.
///
/// El ajuste lo captura la persona. El sistema jamás lo deriva de
/// `importeEmitido - esperado`: eso fabricaría un cuadre perfecto que
/// escondería precisamente el error que se quiere ver.
class CorregirAjusteHistoricoDocumentoPorEmitirUseCase {
  CorregirAjusteHistoricoDocumentoPorEmitirUseCase(this._repository);

  final DocumentoPorEmitirRepository _repository;

  Future<CorregirAjusteHistoricoDocumentoPorEmitirResultado> ejecutar({
    required String documentoPorEmitirId,
    required String motivoCorreccion,
    int? ajusteManual,
    String? motivoAjuste,
    String? actorUsuarioId,
  }) async {
    final documento = await _repository.obtenerPorId(documentoPorEmitirId);
    if (documento == null) {
      return CorregirAjusteHistoricoDocumentoPorEmitirNoExiste();
    }

    // El mismo predicado que bloquea el camino normal, usado aquí al revés:
    // lo que allá cierra la puerta, aquí es el requisito de entrada.
    if (!ajusteComercialCongelado(documento)) {
      return CorregirAjusteHistoricoDocumentoPorEmitirNoEmitido();
    }

    final motivoCorreccionLimpio = motivoCorreccion.trim();
    if (motivoCorreccionLimpio.isEmpty) {
      return CorregirAjusteHistoricoDocumentoPorEmitirMotivoCorreccionRequerido();
    }

    final ajuste = ajusteManual ?? 0;
    final motivoAjusteLimpio = motivoAjuste?.trim();
    if (ajuste != 0 && (motivoAjusteLimpio == null || motivoAjusteLimpio.isEmpty)) {
      return CorregirAjusteHistoricoDocumentoPorEmitirMotivoAjusteRequerido();
    }

    if (documento.importeBaseEsperado + ajuste < 0) {
      return CorregirAjusteHistoricoDocumentoPorEmitirImporteNegativo();
    }

    try {
      final actualizado = await _repository.corregirAjusteHistorico(
        documentoPorEmitirId: documentoPorEmitirId,
        motivoCorreccion: motivoCorreccionLimpio,
        ajusteManual: ajuste == 0 ? null : ajuste,
        motivoAjuste: ajuste == 0 ? null : motivoAjusteLimpio,
        actorUsuarioId: actorUsuarioId,
      );
      return CorregirAjusteHistoricoDocumentoPorEmitirExitoso(actualizado);
    } catch (e) {
      return CorregirAjusteHistoricoDocumentoPorEmitirErrorInesperado(e.toString());
    }
  }
}
