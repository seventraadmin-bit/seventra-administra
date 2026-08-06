import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/documento_por_emitir_repository.dart';

sealed class ActualizarAjusteManualDocumentoPorEmitirResultado {}

class ActualizarAjusteManualDocumentoPorEmitirExitoso extends ActualizarAjusteManualDocumentoPorEmitirResultado {
  ActualizarAjusteManualDocumentoPorEmitirExitoso(this.documento);
  final DocumentoPorEmitirData documento;
}

/// Un ajuste distinto de cero exige motivo — sin excepción.
class ActualizarAjusteManualDocumentoPorEmitirMotivoRequerido extends ActualizarAjusteManualDocumentoPorEmitirResultado {}

/// `importeBaseEsperado + ajuste` no puede quedar negativo.
class ActualizarAjusteManualDocumentoPorEmitirImporteNegativo extends ActualizarAjusteManualDocumentoPorEmitirResultado {}

class ActualizarAjusteManualDocumentoPorEmitirNoExiste extends ActualizarAjusteManualDocumentoPorEmitirResultado {}

class ActualizarAjusteManualDocumentoPorEmitirErrorInesperado extends ActualizarAjusteManualDocumentoPorEmitirResultado {
  ActualizarAjusteManualDocumentoPorEmitirErrorInesperado(this.mensaje);
  final String mensaje;
}

/// El modelo de ajuste manual existe desde la Etapa 4I.1 aunque su
/// interfaz de captura completa se difiera a la 4I.2 (autorización
/// explícita de Marlon) — nunca modifica `DocumentoPorEmitirLinea`
/// (el snapshot calculado), solo el par
/// `ajusteManual`/`importeFinalEsperado` a nivel de documento.
class ActualizarAjusteManualDocumentoPorEmitirUseCase {
  ActualizarAjusteManualDocumentoPorEmitirUseCase(this._repository);

  final DocumentoPorEmitirRepository _repository;

  Future<ActualizarAjusteManualDocumentoPorEmitirResultado> ejecutar({
    required String documentoPorEmitirId,
    int? ajusteManual,
    String? motivoAjuste,
  }) async {
    final documento = await _repository.obtenerPorId(documentoPorEmitirId);
    if (documento == null) {
      return ActualizarAjusteManualDocumentoPorEmitirNoExiste();
    }

    final ajuste = ajusteManual ?? 0;
    final motivoLimpio = motivoAjuste?.trim();
    if (ajuste != 0 && (motivoLimpio == null || motivoLimpio.isEmpty)) {
      return ActualizarAjusteManualDocumentoPorEmitirMotivoRequerido();
    }

    final importeFinal = documento.importeBaseEsperado + ajuste;
    if (importeFinal < 0) {
      return ActualizarAjusteManualDocumentoPorEmitirImporteNegativo();
    }

    try {
      final actualizado = await _repository.actualizarAjusteManual(
        documentoPorEmitirId: documentoPorEmitirId,
        ajusteManual: ajuste == 0 ? null : ajuste,
        motivoAjuste: ajuste == 0 ? null : motivoLimpio,
      );
      return ActualizarAjusteManualDocumentoPorEmitirExitoso(actualizado);
    } catch (e) {
      return ActualizarAjusteManualDocumentoPorEmitirErrorInesperado(e.toString());
    }
  }
}
