import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/documento_por_emitir_table.dart';

import '../repositories/documento_por_emitir_repository.dart';

sealed class RegistrarEmisionDocumentoPorEmitirResultado {}

class RegistrarEmisionDocumentoPorEmitirExitoso extends RegistrarEmisionDocumentoPorEmitirResultado {
  RegistrarEmisionDocumentoPorEmitirExitoso(this.documento);
  final DocumentoPorEmitirData documento;
}

class RegistrarEmisionDocumentoPorEmitirNoExiste extends RegistrarEmisionDocumentoPorEmitirResultado {}

/// Solo `Pendiente`/`EnPreparacion` pueden pasar a `Emitido` — un
/// documento ya `Emitido`/`Enviado`/`Procesado-Aceptado` no puede
/// "re-emitirse" por esta vía (para corregir datos ya emitidos existe
/// `CorregirDatosEmisionUseCase`).
class RegistrarEmisionDocumentoPorEmitirTransicionInvalida extends RegistrarEmisionDocumentoPorEmitirResultado {}

class RegistrarEmisionDocumentoPorEmitirFolioRequerido extends RegistrarEmisionDocumentoPorEmitirResultado {}

/// Un recibo nunca captura serie fiscal/folio fiscal/UUID — esos son
/// exclusivos de CFDI (Resolución 11 de Marlon).
class RegistrarEmisionDocumentoPorEmitirCamposNoPermitidosParaRecibo extends RegistrarEmisionDocumentoPorEmitirResultado {}

class RegistrarEmisionDocumentoPorEmitirImporteInvalido extends RegistrarEmisionDocumentoPorEmitirResultado {}

class RegistrarEmisionDocumentoPorEmitirErrorInesperado extends RegistrarEmisionDocumentoPorEmitirResultado {
  RegistrarEmisionDocumentoPorEmitirErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Registra los datos definitivos de un documento y lo transiciona a
/// `Emitido` (Etapa 4I.2.1) — UUID/XML pueden agregarse después (nunca
/// obligatorios al momento de emitir, Resolución 11); serie/folio
/// fiscal/UUID nunca se piden para un recibo.
class RegistrarEmisionDocumentoPorEmitirUseCase {
  RegistrarEmisionDocumentoPorEmitirUseCase(this._repository);

  final DocumentoPorEmitirRepository _repository;

  Future<RegistrarEmisionDocumentoPorEmitirResultado> ejecutar({
    required String documentoPorEmitirId,
    required String folioDocumento,
    String? serieFiscal,
    String? folioFiscal,
    String? uuid,
    required DateTime fechaEmisionReal,
    required int importeEmitido,
    String? observacionesEmision,
  }) async {
    final documento = await _repository.obtenerPorId(documentoPorEmitirId);
    if (documento == null) {
      return RegistrarEmisionDocumentoPorEmitirNoExiste();
    }

    final actual = EstatusDocumentoPorEmitir.values.byName(documento.estatus);
    if (actual != EstatusDocumentoPorEmitir.pendiente && actual != EstatusDocumentoPorEmitir.enPreparacion) {
      return RegistrarEmisionDocumentoPorEmitirTransicionInvalida();
    }

    if (folioDocumento.trim().isEmpty) {
      return RegistrarEmisionDocumentoPorEmitirFolioRequerido();
    }

    final esRecibo = TipoDocumentoCobro.values.byName(documento.tipoDocumento) == TipoDocumentoCobro.reciboDePago;
    if (esRecibo && (serieFiscal != null || folioFiscal != null || uuid != null)) {
      return RegistrarEmisionDocumentoPorEmitirCamposNoPermitidosParaRecibo();
    }

    if (importeEmitido < 0) {
      return RegistrarEmisionDocumentoPorEmitirImporteInvalido();
    }

    try {
      final actualizado = await _repository.registrarEmision(
        documentoPorEmitirId: documentoPorEmitirId,
        folioDocumento: folioDocumento.trim(),
        serieFiscal: serieFiscal,
        folioFiscal: folioFiscal,
        uuid: uuid,
        fechaEmisionReal: fechaEmisionReal,
        importeEmitido: importeEmitido,
        observacionesEmision: observacionesEmision,
      );
      return RegistrarEmisionDocumentoPorEmitirExitoso(actualizado);
    } catch (e) {
      return RegistrarEmisionDocumentoPorEmitirErrorInesperado(e.toString());
    }
  }
}
