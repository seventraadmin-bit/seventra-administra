import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/validation/uuid_validator.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/documento_por_emitir_table.dart';

import '../repositories/documento_por_emitir_repository.dart';

sealed class CorregirDatosEmisionDocumentoPorEmitirResultado {}

class CorregirDatosEmisionDocumentoPorEmitirExitoso extends CorregirDatosEmisionDocumentoPorEmitirResultado {
  CorregirDatosEmisionDocumentoPorEmitirExitoso(this.documento);
  final DocumentoPorEmitirData documento;
}

class CorregirDatosEmisionDocumentoPorEmitirNoExiste extends CorregirDatosEmisionDocumentoPorEmitirResultado {}

/// Solo se puede corregir un documento ya `Emitido`/`Enviado` — nunca
/// antes de emitir (no hay nada que corregir), nunca después de
/// `Procesado/Aceptado` (Resolución 6 de Marlon, explícita).
class CorregirDatosEmisionDocumentoPorEmitirNoPermitido extends CorregirDatosEmisionDocumentoPorEmitirResultado {}

class CorregirDatosEmisionDocumentoPorEmitirMotivoRequerido extends CorregirDatosEmisionDocumentoPorEmitirResultado {}

class CorregirDatosEmisionDocumentoPorEmitirCamposNoPermitidosParaRecibo
    extends CorregirDatosEmisionDocumentoPorEmitirResultado {}

/// El UUID/folio fiscal no cumple el formato estándar (8-4-4-4-12) —
/// Etapa 15, corrección estructural CFDI real.
class CorregirDatosEmisionDocumentoPorEmitirUuidFormatoInvalido extends CorregirDatosEmisionDocumentoPorEmitirResultado {}

class CorregirDatosEmisionDocumentoPorEmitirImporteInvalido extends CorregirDatosEmisionDocumentoPorEmitirResultado {}

class CorregirDatosEmisionDocumentoPorEmitirErrorInesperado extends CorregirDatosEmisionDocumentoPorEmitirResultado {
  CorregirDatosEmisionDocumentoPorEmitirErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Corrige uno o más datos definitivos ya registrados (Etapa 4I.2.1) —
/// nunca una edición silenciosa: exige motivo, conserva los valores
/// anteriores en el evento de historial (`DocumentoPorEmitirEvento`) y
/// nunca cambia el estatus del documento. `null` en un parámetro
/// significa "no tocar ese campo".
class CorregirDatosEmisionDocumentoPorEmitirUseCase {
  CorregirDatosEmisionDocumentoPorEmitirUseCase(this._repository);

  final DocumentoPorEmitirRepository _repository;

  Future<CorregirDatosEmisionDocumentoPorEmitirResultado> ejecutar({
    String? actorUsuarioId,
    required String documentoPorEmitirId,
    required String motivo,
    String? folioDocumento,
    String? uuid,
    DateTime? fechaEmisionReal,
    int? importeEmitido,
    String? observacionesEmision,
  }) async {
    final documento = await _repository.obtenerPorId(documentoPorEmitirId);
    if (documento == null) {
      return CorregirDatosEmisionDocumentoPorEmitirNoExiste();
    }

    final actual = EstatusDocumentoPorEmitir.values.byName(documento.estatus);
    if (actual != EstatusDocumentoPorEmitir.emitido && actual != EstatusDocumentoPorEmitir.enviado) {
      return CorregirDatosEmisionDocumentoPorEmitirNoPermitido();
    }

    final motivoLimpio = motivo.trim();
    if (motivoLimpio.isEmpty) {
      return CorregirDatosEmisionDocumentoPorEmitirMotivoRequerido();
    }

    final esRecibo = TipoDocumentoCobro.values.byName(documento.tipoDocumento) == TipoDocumentoCobro.reciboDePago;
    if (esRecibo && uuid != null) {
      return CorregirDatosEmisionDocumentoPorEmitirCamposNoPermitidosParaRecibo();
    }

    if (uuid != null && !esUuidFormatoValido(uuid)) {
      return CorregirDatosEmisionDocumentoPorEmitirUuidFormatoInvalido();
    }

    if (importeEmitido != null && importeEmitido < 0) {
      return CorregirDatosEmisionDocumentoPorEmitirImporteInvalido();
    }

    try {
      final actualizado = await _repository.corregirDatosEmision(
        actorUsuarioId: actorUsuarioId,
        documentoPorEmitirId: documentoPorEmitirId,
        motivo: motivoLimpio,
        folioDocumento: folioDocumento,
        uuid: uuid,
        fechaEmisionReal: fechaEmisionReal,
        importeEmitido: importeEmitido,
        observacionesEmision: observacionesEmision,
      );
      return CorregirDatosEmisionDocumentoPorEmitirExitoso(actualizado);
    } catch (e) {
      return CorregirDatosEmisionDocumentoPorEmitirErrorInesperado(e.toString());
    }
  }
}
