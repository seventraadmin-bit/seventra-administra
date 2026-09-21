import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/validation/uuid_validator.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart'
    show MetodoPagoCobro;

import '../../data/tables/servicio_eventual_documento_fiscal_table.dart';
import '../repositories/servicio_eventual_documento_fiscal_repository.dart';

sealed class CorregirDocumentoFiscalEventualResultado {}

class CorregirDocumentoFiscalEventualExitoso extends CorregirDocumentoFiscalEventualResultado {
  CorregirDocumentoFiscalEventualExitoso(this.documento);
  final ServicioEventualDocumentoFiscalData documento;
}

class CorregirDocumentoFiscalEventualNoExiste extends CorregirDocumentoFiscalEventualResultado {}

class CorregirDocumentoFiscalEventualMotivoRequerido extends CorregirDocumentoFiscalEventualResultado {}

class CorregirDocumentoFiscalEventualFolioRequerido extends CorregirDocumentoFiscalEventualResultado {}

class CorregirDocumentoFiscalEventualUuidInvalido extends CorregirDocumentoFiscalEventualResultado {}

class CorregirDocumentoFiscalEventualMetodoInvalido extends CorregirDocumentoFiscalEventualResultado {}

/// Un documento cancelado es historia fiscal: se consulta, no se
/// corrige. Si los datos estaban mal, el sustituto es el que los lleva
/// bien.
class CorregirDocumentoFiscalEventualCancelado extends CorregirDocumentoFiscalEventualResultado {}

class CorregirDocumentoFiscalEventualErrorInesperado extends CorregirDocumentoFiscalEventualResultado {
  CorregirDocumentoFiscalEventualErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Corrige los datos documentales del CFDI ya registrado — capturar el
/// UUID que llegó después es el caso más común.
///
/// `motivo` es obligatorio y el cambio queda con su diff antes/después:
/// la historia fiscal nunca cambia en silencio.
class CorregirDocumentoFiscalEventualUseCase {
  CorregirDocumentoFiscalEventualUseCase(this._repository);

  final ServicioEventualDocumentoFiscalRepository _repository;

  Future<CorregirDocumentoFiscalEventualResultado> ejecutar({
    required String documentoId,
    String? folio,
    String? uuid,
    DateTime? fechaEmision,
    MetodoPagoCobro? metodo,
    String? observaciones,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    final motivoLimpio = motivo.trim();
    if (motivoLimpio.isEmpty) return CorregirDocumentoFiscalEventualMotivoRequerido();

    final actual = await _repository.obtenerPorId(documentoId);
    if (actual == null) return CorregirDocumentoFiscalEventualNoExiste();
    if (actual.estatus == EstatusDocumentoFiscalEventual.cancelado.name) {
      return CorregirDocumentoFiscalEventualCancelado();
    }

    final folioLimpio = folio?.trim();
    if (folioLimpio != null && folioLimpio.isEmpty) {
      return CorregirDocumentoFiscalEventualFolioRequerido();
    }

    final uuidLimpio = uuid?.trim();
    if (uuidLimpio != null && uuidLimpio.isNotEmpty && !esUuidFormatoValido(uuidLimpio)) {
      return CorregirDocumentoFiscalEventualUuidInvalido();
    }

    if (metodo == MetodoPagoCobro.noAplica) return CorregirDocumentoFiscalEventualMetodoInvalido();

    try {
      final documento = await _repository.corregir(
        documentoId: documentoId,
        folio: folioLimpio,
        uuid: uuidLimpio == null || uuidLimpio.isEmpty ? null : uuidLimpio,
        fechaEmision: fechaEmision,
        metodo: metodo?.name,
        observaciones: observaciones?.trim().isEmpty ?? true ? null : observaciones!.trim(),
        motivo: motivoLimpio,
        actorUsuarioId: actorUsuarioId,
      );
      return CorregirDocumentoFiscalEventualExitoso(documento);
    } catch (e) {
      return CorregirDocumentoFiscalEventualErrorInesperado(e.toString());
    }
  }
}
