import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/vehiculo_documento_repository.dart';
import '../repositories/vehiculo_repository.dart';

sealed class RegistrarDocumentoVehiculoResultado {}

class RegistrarDocumentoVehiculoExitoso extends RegistrarDocumentoVehiculoResultado {
  RegistrarDocumentoVehiculoExitoso(this.documento);
  final VehiculoDocumentoData documento;
}

class RegistrarDocumentoVehiculoVehiculoNoExiste extends RegistrarDocumentoVehiculoResultado {}

/// `tipo == otro` sin `tipoOtroDescripcion` — sin eso, "Otro" no sirve
/// para diferenciar dos documentos distintos en el histórico.
class RegistrarDocumentoVehiculoDescripcionRequerida extends RegistrarDocumentoVehiculoResultado {}

class RegistrarDocumentoVehiculoFechasInvalidas extends RegistrarDocumentoVehiculoResultado {}

class RegistrarDocumentoVehiculoErrorInesperado extends RegistrarDocumentoVehiculoResultado {
  RegistrarDocumentoVehiculoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Registra un documento de un Vehículo (Etapa 8C) — sirve tanto para
/// "agregar documento" como para "renovar": renovar es exactamente este
/// mismo caso de uso, llamado de nuevo con el mismo `tipo` — la fila
/// anterior nunca se toca (ver el doc comment de `VehiculoDocumento`).
/// El archivo es opcional y se adjunta después, vía
/// `AdjuntarArchivoDocumentoVehiculoUseCase` — mismo patrón de
/// composición segura ya usado para la fotografía (Etapa 5D.1/8A).
class RegistrarDocumentoVehiculoUseCase {
  RegistrarDocumentoVehiculoUseCase(this._documentoRepository, this._vehiculoRepository);

  final VehiculoDocumentoRepository _documentoRepository;
  final VehiculoRepository _vehiculoRepository;

  Future<RegistrarDocumentoVehiculoResultado> ejecutar({
    required String vehiculoId,
    required String tipo,
    String? tipoOtroDescripcion,
    String? numeroFolio,
    DateTime? fechaEmision,
    DateTime? fechaVencimiento,
    String? observaciones,
  }) async {
    if (await _vehiculoRepository.obtenerPorId(vehiculoId) == null) {
      return RegistrarDocumentoVehiculoVehiculoNoExiste();
    }
    if (tipo == 'otro' && (tipoOtroDescripcion == null || tipoOtroDescripcion.trim().isEmpty)) {
      return RegistrarDocumentoVehiculoDescripcionRequerida();
    }
    if (fechaEmision != null && fechaVencimiento != null && fechaVencimiento.isBefore(fechaEmision)) {
      return RegistrarDocumentoVehiculoFechasInvalidas();
    }

    try {
      final documento = await _documentoRepository.crear(
        vehiculoId: vehiculoId,
        tipo: tipo,
        tipoOtroDescripcion: tipo == 'otro' ? tipoOtroDescripcion!.trim() : null,
        numeroFolio: numeroFolio?.trim().isEmpty ?? true ? null : numeroFolio!.trim(),
        fechaEmision: fechaEmision,
        fechaVencimiento: fechaVencimiento,
        observaciones: observaciones?.trim().isEmpty ?? true ? null : observaciones!.trim(),
      );
      return RegistrarDocumentoVehiculoExitoso(documento);
    } catch (e) {
      return RegistrarDocumentoVehiculoErrorInesperado(e.toString());
    }
  }
}
