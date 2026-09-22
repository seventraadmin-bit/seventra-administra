import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/data/tables/documento_por_emitir_table.dart';

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

/// El documento ya llegó a la emisión real: el ajuste quedó congelado.
/// Corregirlo exige la vía Maestro de corrección histórica.
class ActualizarAjusteManualDocumentoPorEmitirCongelado extends ActualizarAjusteManualDocumentoPorEmitirResultado {}

/// **La única definición de "este documento ya se emitió"** — la comparten
/// el dominio (que bloquea) y la pantalla (que oculta el botón), para que
/// no puedan discrepar.
///
/// Se mira el estatus Y los datos de emisión, no sólo el estatus: el folio,
/// el UUID, la fecha o el importe emitido pueden capturarse en momentos
/// distintos, y cualquiera de ellos ya significa que existe un comprobante
/// real allá afuera contra el cual el esperado se está comparando. Mover el
/// ajuste después de eso reescribe hacia atrás la diferencia de un documento
/// que ya se fue.
bool ajusteComercialCongelado(DocumentoPorEmitirData documento) {
  final estatusEmitidos = {
    EstatusDocumentoPorEmitir.emitido.name,
    EstatusDocumentoPorEmitir.enviado.name,
    EstatusDocumentoPorEmitir.procesadoAceptado.name,
  };
  return estatusEmitidos.contains(documento.estatus) ||
      documento.importeEmitido != null ||
      documento.folioDocumento != null ||
      documento.uuid != null ||
      documento.fechaEmisionReal != null;
}

class ActualizarAjusteManualDocumentoPorEmitirErrorInesperado extends ActualizarAjusteManualDocumentoPorEmitirResultado {
  ActualizarAjusteManualDocumentoPorEmitirErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Ajuste comercial **antes** de la emisión — un único importe neto con
/// signo y su motivo libre. Nunca sabe ni pregunta por qué ocurrió algo en
/// operación: "2 días no facturados" es, para RISEG ONE, sólo la
/// descripción de un ajuste comercial.
///
/// Una vez emitido el documento, este caso de uso deja de aplicar y la
/// corrección pasa por `CorregirAjusteHistoricoDocumentoPorEmitirUseCase`
/// (Maestro, con motivo administrativo propio).
///
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

    // Antes que cualquier validación de contenido: si ya se emitió, aquí
    // no se toca nada, ni siquiera para "dejarlo igual".
    if (ajusteComercialCongelado(documento)) {
      return ActualizarAjusteManualDocumentoPorEmitirCongelado();
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
