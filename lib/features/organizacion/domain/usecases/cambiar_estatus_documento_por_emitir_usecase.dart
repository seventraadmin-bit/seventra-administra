import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/data/tables/documento_por_emitir_table.dart';

import '../repositories/documento_por_emitir_repository.dart';

sealed class CambiarEstatusDocumentoPorEmitirResultado {}

class CambiarEstatusDocumentoPorEmitirExitoso extends CambiarEstatusDocumentoPorEmitirResultado {
  CambiarEstatusDocumentoPorEmitirExitoso(this.documento);
  final DocumentoPorEmitirData documento;
}

/// La transición pedida no está permitida (Etapa 4I.1): solo
/// Pendiente→EnPreparacion, y Pendiente/EnPreparacion→Cancelado/
/// NoRequerido. Emitido/Enviado/Procesado-Aceptado llegan en la 4I.2.
class CambiarEstatusDocumentoPorEmitirTransicionInvalida extends CambiarEstatusDocumentoPorEmitirResultado {}

/// Cancelar o marcar No requerido exige un motivo — sin excepción.
class CambiarEstatusDocumentoPorEmitirMotivoRequerido extends CambiarEstatusDocumentoPorEmitirResultado {}

class CambiarEstatusDocumentoPorEmitirNoExiste extends CambiarEstatusDocumentoPorEmitirResultado {}

class CambiarEstatusDocumentoPorEmitirErrorInesperado extends CambiarEstatusDocumentoPorEmitirResultado {
  CambiarEstatusDocumentoPorEmitirErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Máquina de estados de la Etapa 4I.1 — deliberadamente sin ningún
/// estado de pago (eso es de la futura Cuenta por cobrar). `Cancelado`
/// significa "se esperaba preparar, se decidió no hacerlo";
/// `NoRequerido` significa "se confirmó que ese periodo no necesitaba
/// documento" — semánticamente distintos aunque ambos sean terminales y
/// exijan motivo.
class CambiarEstatusDocumentoPorEmitirUseCase {
  CambiarEstatusDocumentoPorEmitirUseCase(this._repository);

  final DocumentoPorEmitirRepository _repository;

  Future<CambiarEstatusDocumentoPorEmitirResultado> ejecutar({
    required String documentoPorEmitirId,
    required EstatusDocumentoPorEmitir nuevo,
    String? motivo,
  }) async {
    final documento = await _repository.obtenerPorId(documentoPorEmitirId);
    if (documento == null) {
      return CambiarEstatusDocumentoPorEmitirNoExiste();
    }

    final actual = EstatusDocumentoPorEmitir.values.byName(documento.estatus);
    final transicionValida = switch ((actual, nuevo)) {
      (EstatusDocumentoPorEmitir.pendiente, EstatusDocumentoPorEmitir.enPreparacion) => true,
      (EstatusDocumentoPorEmitir.pendiente, EstatusDocumentoPorEmitir.cancelado) => true,
      (EstatusDocumentoPorEmitir.pendiente, EstatusDocumentoPorEmitir.noRequerido) => true,
      (EstatusDocumentoPorEmitir.enPreparacion, EstatusDocumentoPorEmitir.cancelado) => true,
      (EstatusDocumentoPorEmitir.enPreparacion, EstatusDocumentoPorEmitir.noRequerido) => true,
      _ => false,
    };
    if (!transicionValida) {
      return CambiarEstatusDocumentoPorEmitirTransicionInvalida();
    }

    final requiereMotivo = nuevo == EstatusDocumentoPorEmitir.cancelado || nuevo == EstatusDocumentoPorEmitir.noRequerido;
    final motivoLimpio = motivo?.trim();
    if (requiereMotivo && (motivoLimpio == null || motivoLimpio.isEmpty)) {
      return CambiarEstatusDocumentoPorEmitirMotivoRequerido();
    }

    try {
      final actualizado = await _repository.cambiarEstatus(
        documentoPorEmitirId: documentoPorEmitirId,
        nuevoEstatus: nuevo.name,
        motivo: requiereMotivo ? motivoLimpio : null,
      );
      return CambiarEstatusDocumentoPorEmitirExitoso(actualizado);
    } catch (e) {
      return CambiarEstatusDocumentoPorEmitirErrorInesperado(e.toString());
    }
  }
}
