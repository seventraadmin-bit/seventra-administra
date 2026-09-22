import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/data/tables/documento_por_emitir_table.dart';

import '../repositories/documento_por_emitir_repository.dart';

sealed class RegistrarEnvioDocumentoPorEmitirResultado {}

class RegistrarEnvioDocumentoPorEmitirExitoso extends RegistrarEnvioDocumentoPorEmitirResultado {
  RegistrarEnvioDocumentoPorEmitirExitoso(this.documento);
  final DocumentoPorEmitirData documento;
}

class RegistrarEnvioDocumentoPorEmitirNoExiste extends RegistrarEnvioDocumentoPorEmitirResultado {}

/// Solo `Emitido` puede pasar a `Enviado` — un documento sin envío
/// formal (ej. entregado en mano) usa `Emitido → Procesado/Aceptado`
/// directamente, sin pasar por aquí.
class RegistrarEnvioDocumentoPorEmitirTransicionInvalida extends RegistrarEnvioDocumentoPorEmitirResultado {}

class RegistrarEnvioDocumentoPorEmitirErrorInesperado extends RegistrarEnvioDocumentoPorEmitirResultado {
  RegistrarEnvioDocumentoPorEmitirErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Registra el envío de un documento ya emitido (Etapa 4I.2.1) y lo
/// transiciona a `Enviado`. Los correos se reciben ya resueltos (la
/// UI los precarga desde `DocumentoPorEmitirCorreo` — el snapshot de
/// la Configuración de cobro al generar — y los deja editables) — una
/// lista vacía es válida (entrega sin correo, documentada en
/// `observacionesEnvio`), nunca se exige al menos uno.
class RegistrarEnvioDocumentoPorEmitirUseCase {
  RegistrarEnvioDocumentoPorEmitirUseCase(this._repository);

  final DocumentoPorEmitirRepository _repository;

  Future<RegistrarEnvioDocumentoPorEmitirResultado> ejecutar({
    String? actorUsuarioId,
    required String documentoPorEmitirId,
    required DateTime fechaEnvio,
    List<String> correos = const [],
    String? observacionesEnvio,
  }) async {
    final documento = await _repository.obtenerPorId(documentoPorEmitirId);
    if (documento == null) {
      return RegistrarEnvioDocumentoPorEmitirNoExiste();
    }

    final actual = EstatusDocumentoPorEmitir.values.byName(documento.estatus);
    if (actual != EstatusDocumentoPorEmitir.emitido) {
      return RegistrarEnvioDocumentoPorEmitirTransicionInvalida();
    }

    try {
      final actualizado = await _repository.registrarEnvio(
        actorUsuarioId: actorUsuarioId,
        documentoPorEmitirId: documentoPorEmitirId,
        fechaEnvio: fechaEnvio,
        correos: correos,
        observacionesEnvio: observacionesEnvio,
      );
      return RegistrarEnvioDocumentoPorEmitirExitoso(actualizado);
    } catch (e) {
      return RegistrarEnvioDocumentoPorEmitirErrorInesperado(e.toString());
    }
  }
}
