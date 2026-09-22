import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/data/tables/documento_por_emitir_table.dart';

import '../repositories/documento_por_emitir_repository.dart';

sealed class CambiarEstatusDocumentoPorEmitirResultado {}

class CambiarEstatusDocumentoPorEmitirExitoso extends CambiarEstatusDocumentoPorEmitirResultado {
  CambiarEstatusDocumentoPorEmitirExitoso(this.documento);
  final DocumentoPorEmitirData documento;
}

/// La transición pedida no está permitida. `Emitido` solo se alcanza
/// vía `RegistrarEmisionDocumentoUseCase` (necesita capturar datos
/// definitivos) y `Enviado` vía `RegistrarEnvioDocumentoUseCase` — este
/// caso de uso nunca los produce directamente, solo los transiciona
/// hacia adelante (`Emitido`/`Enviado` → `ProcesadoAceptado`) o corrige
/// (`Enviado` → `Emitido`).
class CambiarEstatusDocumentoPorEmitirTransicionInvalida extends CambiarEstatusDocumentoPorEmitirResultado {}

/// Cancelar o marcar No requerido exige un motivo — sin excepción.
class CambiarEstatusDocumentoPorEmitirMotivoRequerido extends CambiarEstatusDocumentoPorEmitirResultado {}

class CambiarEstatusDocumentoPorEmitirNoExiste extends CambiarEstatusDocumentoPorEmitirResultado {}

class CambiarEstatusDocumentoPorEmitirErrorInesperado extends CambiarEstatusDocumentoPorEmitirResultado {
  CambiarEstatusDocumentoPorEmitirErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Máquina de estados de las Etapas 4I.1+4I.2.1 — deliberadamente sin
/// ningún estado de pago (eso es de la futura Cuenta por cobrar).
/// `Cancelado` significa "se esperaba preparar, se decidió no
/// hacerlo"; `NoRequerido` significa "se confirmó que ese periodo no
/// necesitaba documento" — semánticamente distintos aunque ambos sean
/// terminales y exijan motivo. `Emitido` nunca puede pasar a
/// `Cancelado`/`NoRequerido` en esta etapa (decisión explícita de
/// Marlon): eso implicaría una cancelación fiscal real, fuera de
/// alcance hasta que exista timbrado/integración SAT.
class CambiarEstatusDocumentoPorEmitirUseCase {
  CambiarEstatusDocumentoPorEmitirUseCase(this._repository);

  final DocumentoPorEmitirRepository _repository;

  Future<CambiarEstatusDocumentoPorEmitirResultado> ejecutar({
    String? actorUsuarioId,
    required String documentoPorEmitirId,
    required EstatusDocumentoPorEmitir nuevo,
    String? motivo,
  }) async {
    final documento = await _repository.obtenerPorId(documentoPorEmitirId);
    if (documento == null) {
      return CambiarEstatusDocumentoPorEmitirNoExiste();
    }

    final actual = EstatusDocumentoPorEmitir.values.byName(documento.estatus);
    final (transicionValida, tipoEvento, requiereMotivo) = switch ((actual, nuevo)) {
      (EstatusDocumentoPorEmitir.pendiente, EstatusDocumentoPorEmitir.enPreparacion) => (
          true,
          TipoEventoDocumentoPorEmitir.marcadoEnPreparacion,
          false,
        ),
      (EstatusDocumentoPorEmitir.pendiente, EstatusDocumentoPorEmitir.cancelado) => (
          true,
          TipoEventoDocumentoPorEmitir.cancelado,
          true,
        ),
      (EstatusDocumentoPorEmitir.pendiente, EstatusDocumentoPorEmitir.noRequerido) => (
          true,
          TipoEventoDocumentoPorEmitir.marcadoNoRequerido,
          true,
        ),
      (EstatusDocumentoPorEmitir.enPreparacion, EstatusDocumentoPorEmitir.cancelado) => (
          true,
          TipoEventoDocumentoPorEmitir.cancelado,
          true,
        ),
      (EstatusDocumentoPorEmitir.enPreparacion, EstatusDocumentoPorEmitir.noRequerido) => (
          true,
          TipoEventoDocumentoPorEmitir.marcadoNoRequerido,
          true,
        ),
      (EstatusDocumentoPorEmitir.emitido, EstatusDocumentoPorEmitir.procesadoAceptado) => (
          true,
          TipoEventoDocumentoPorEmitir.procesadoAceptado,
          false,
        ),
      (EstatusDocumentoPorEmitir.enviado, EstatusDocumentoPorEmitir.procesadoAceptado) => (
          true,
          TipoEventoDocumentoPorEmitir.procesadoAceptado,
          false,
        ),
      // Corrección administrativa: se marcó Enviado por error, o el
      // destinatario reporta un dato incorrecto antes de aceptar.
      (EstatusDocumentoPorEmitir.enviado, EstatusDocumentoPorEmitir.emitido) => (
          true,
          TipoEventoDocumentoPorEmitir.correccionEnviadoAEmitido,
          true,
        ),
      _ => (false, null, false),
    };
    if (!transicionValida) {
      return CambiarEstatusDocumentoPorEmitirTransicionInvalida();
    }

    final motivoLimpio = motivo?.trim();
    if (requiereMotivo && (motivoLimpio == null || motivoLimpio.isEmpty)) {
      return CambiarEstatusDocumentoPorEmitirMotivoRequerido();
    }

    try {
      final actualizado = await _repository.cambiarEstatus(
        actorUsuarioId: actorUsuarioId,
        documentoPorEmitirId: documentoPorEmitirId,
        nuevoEstatus: nuevo.name,
        motivo: requiereMotivo ? motivoLimpio : null,
        tipoEvento: tipoEvento!,
      );
      return CambiarEstatusDocumentoPorEmitirExitoso(actualizado);
    } catch (e) {
      return CambiarEstatusDocumentoPorEmitirErrorInesperado(e.toString());
    }
  }
}
